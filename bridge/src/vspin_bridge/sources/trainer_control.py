"""FTMS-Steuerung des Trainers (Spec #75, ADR-0007 Nachtrag): Control Point `0x2AD9` und Machine Status `0x2ADA`.

Bausteine für `TrainerSource` nach Bluetooth SIG FTMS 1.0 – kein Wahoo- oder Zwift-Sonderprotokoll:

- **Op-Codes:** `0x00` Request Control, `0x01` Reset, `0x07` Start/Resume, `0x11` Set Indoor Bike Simulation
  Parameters. Jede Anfrage beantwortet der Trainer per Indication `0x80 <Op-Code> <Ergebnis>` (`RESULT_*`).
- **`ControlPoint`:** je Verbindung ein Objekt; eine Anfrage zur Zeit (FTMS erlaubt keine zweite, solange eine offen
  ist), Schreiben mit Antwort, dann Warten auf die Indication mit Zeitlimit (`RESPONSE_TIMEOUT_S`). Das Abo der
  Indications kommt **vor** dem ersten Schreiben (ohne Abo lehnt das Gerät Schreibzugriffe ab).
- **`ControlState`:** Stand der Steuerung, auf dem Bus `status.trainer.control` (docs/bus-protocol.md).

Andockpunkt ERG (P7): Target Power `0x05` kommt als weiterer Op-Code hierher und geht wie `0x11` über
`ControlPoint.request`; Zustand, Kontrollverlust und Grundlast gelten dann für beide.
"""

import asyncio
import struct
from enum import StrEnum

from ..ble import BleConnection, BleError

CONTROL_POINT = "00002ad9-0000-1000-8000-00805f9b34fb"  # Fitness Machine Control Point: Write + Indicate
MACHINE_STATUS = "00002ada-0000-1000-8000-00805f9b34fb"  # Fitness Machine Status: Notify

OP_REQUEST_CONTROL = 0x00
OP_RESET = 0x01
OP_START = 0x07
OP_SIMULATION = 0x11
OP_RESPONSE = 0x80

RESULT_SUCCESS = 0x01
RESULT_NOT_SUPPORTED = 0x02
RESULT_INVALID_PARAMETER = 0x03
RESULT_FAILED = 0x04
RESULT_CONTROL_NOT_PERMITTED = 0x05

RESULT_NAMES = {
    RESULT_SUCCESS: "Erfolg",
    RESULT_NOT_SUPPORTED: "nicht unterstützt",
    RESULT_INVALID_PARAMETER: "ungültiger Parameter",
    RESULT_FAILED: "gescheitert",
    RESULT_CONTROL_NOT_PERMITTED: "Steuerung nicht erlaubt",
}

# Machine Status `0x2ADA` (erstes Byte), soweit sie für die Steuerung zählen: Reset und Control Permission Lost
# nehmen VSpin die Steuerung. Stop/Pause durch den Fahrer (0x02) und Start (0x04) ändern daran nichts.
STATUS_RESET = 0x01
STATUS_CONTROL_PERMISSION_LOST = 0xFF

# Standardwerte für `0x11` neben der Steigung: kein Wind, Rollwiderstand Crr 0,0040 (Rennrad auf glattem Asphalt),
# Luftwiderstand Cw 0,51 kg/m (CdA × Luftdichte, aufrechte bis Oberlenker-Haltung) – ein Rennrad auf der Insel.
WIND_MPS = 0.0
CRR = 0.0040
CW_KG_PER_M = 0.51

RESPONSE_TIMEOUT_S = 2.0  # so lange wartet eine Anfrage auf die Antwort-Indication


class ControlState(StrEnum):
    """Stand der Steuerung (Bus `status.trainer.control`)."""

    NONE = "none"  # kein Trainer verbunden (oder noch nie)
    REQUESTING = "requesting"  # verbunden, Request Control/Start laufen
    ACTIVE = "active"  # VSpin steuert: `set_grade` geht als Steigung an den Trainer
    LOST = "lost"  # eine andere App steuert (0x2ADA 0xFF/Reset oder Antwort 0x05); bis zum Neuverbinden kein Schreiben
    READ_ONLY = "read_only"  # Bridge mit `--read-only`: keine Anforderung, kein Schreiben
    NOT_SUPPORTED = "not_supported"  # Trainer ohne Indoor Bike Simulation bzw. Control Point; Simulator, Replay
    ERROR = "error"  # Anforderung gescheitert (keine Antwort, Ablehnung, Schreibfehler); bis zum Neuverbinden


class ControlPointError(Exception):
    """Der Trainer hat eine Anfrage nicht mit Erfolg beantwortet (`result`) oder gar nicht (`result` = None)."""

    def __init__(self, op: int, result: int | None) -> None:
        if result is None:
            text = f"keine Antwort auf 0x{op:02X} (Zeitlimit)"
        else:
            text = f"Trainer lehnt 0x{op:02X} ab: {RESULT_NAMES.get(result, 'unbekannt')} (0x{result:02X})"
        super().__init__(text)
        self.op = op
        self.result = result


def simulation_parameters(
    grade: float, wind_mps: float = WIND_MPS, crr: float = CRR, cw_kg_per_m: float = CW_KG_PER_M
) -> bytes:
    """Parameter von `0x11` (ohne Op-Code), Little Endian: Wind sint16 (0,001 m/s), Steigung sint16 (0,01 %), Crr uint8
    (0,0001), Cw uint8 (0,01 kg/m). `grade` ist ein Anteil (0.07 = 7 % → 700). Kein stilles Begrenzen: was nicht ins
    Feld passt (über ±327,67 %), ist ein `ValueError`; ob der Trainer die Steigung annimmt, sagt seine Antwort."""
    try:
        return struct.pack(
            "<hhBB", round(wind_mps * 1000), round(grade * 10000), round(crr * 10000), round(cw_kg_per_m * 100)
        )
    except struct.error as exc:
        raise ValueError(f"Steigung {grade * 100:+.2f} % nicht darstellbar (FTMS: sint16 in 0,01 %)") from exc


class ControlPoint:
    """Control Point einer Verbindung. Nach `close()` (Verbindung weg) scheitert jede Anfrage mit `BleError`."""

    def __init__(self, connection: BleConnection, timeout_s: float = RESPONSE_TIMEOUT_S) -> None:
        self._connection = connection
        self._timeout_s = timeout_s
        self._lock = asyncio.Lock()
        self._waiting: tuple[int, asyncio.Future[int]] | None = None
        self.closed = False

    async def subscribe(self) -> None:
        """Indications von `0x2AD9` abonnieren – vor dem ersten Schreiben. Wirft `BleError`."""
        await self._connection.subscribe(CONTROL_POINT, self._on_indication)

    async def request(self, op: int, params: bytes = b"") -> None:
        """`op` mit `params` schreiben und die Antwort abwarten. Wirft `ControlPointError` (kein Erfolg, keine Antwort
        im Zeitlimit) oder `BleError` (Schreiben gescheitert, Verbindung weg)."""
        async with self._lock:
            if self.closed:
                raise BleError("Verbindung zum Trainer getrennt")
            future: asyncio.Future[int] = asyncio.get_running_loop().create_future()
            self._waiting = (op, future)
            try:
                await self._connection.write(CONTROL_POINT, bytes([op]) + params)
                try:
                    result = await asyncio.wait_for(future, self._timeout_s)
                except TimeoutError:
                    raise ControlPointError(op, None) from None
            finally:
                self._waiting = None
        if result != RESULT_SUCCESS:
            raise ControlPointError(op, result)

    def close(self) -> None:
        self.closed = True
        if self._waiting is not None and not self._waiting[1].done():
            self._waiting[1].set_exception(BleError("Verbindung zum Trainer getrennt"))

    def _on_indication(self, data: bytes) -> None:
        if len(data) < 3 or data[0] != OP_RESPONSE or self._waiting is None:
            return  # keine Antwort oder keine offene Anfrage (Nachzügler nach dem Zeitlimit)
        op, future = self._waiting
        if data[1] == op and not future.done():
            future.set_result(data[2])
