"""Erzeugt die handgebauten Replay-Fixtures (`*.raw.jsonl`) in diesem Ordner.

    python tests/fixtures/make_fixtures.py      # im Ordner bridge/

Format wie `tools/ble_discovery.py` (eine Zeile pro Notification:
`{"t_ms": int, "char": "<128-Bit-UUID>", "hex": "…"}`). Die Bytes werden hier unabhängig
von den Parsern der Bridge nach der Bluetooth-SIG-Spezifikation zusammengesetzt; die
Erwartungswerte stehen in den Tests (`tests/test_replay_*.py`). Die Werte der
Fixtures sind so gewählt, dass die Tests sie aus Index bzw. Zeit ablesen können.

Alle Zeiten sind Vielfache von 125 ms, damit die CSC-Event-Zeit (1/1024 s) exakt ist:
250 ms = 256 Ticks, 750 ms = 768 Ticks (80 rpm), 1000 ms = 1024 Ticks (60 rpm).
"""

import json
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent

CSC = "00002a5b-0000-1000-8000-00805f9b34fb"
FTMS_BIKE = "00002ad2-0000-1000-8000-00805f9b34fb"  # FTMS Indoor Bike Data
NOTIFY_MS = 250  # Takt der Notifications in allen Fixtures


def line(t_ms: int, char: str, data: bytes) -> str:
    return json.dumps({"t_ms": t_ms, "char": char, "hex": data.hex()})


def csc(crank: tuple[int, int] | None = None, wheel: tuple[int, int] | None = None) -> bytes:
    """CSC Measurement (0x2A5B): Flags, [uint32 Rad-Umdrehungen, uint16 Zeit], [uint16 Kurbel-Umdrehungen, uint16 Zeit]."""
    flags = (0x01 if wheel else 0) | (0x02 if crank else 0)
    data = bytes([flags])
    if wheel:
        data += struct.pack("<IH", wheel[0] % 2**32, wheel[1] % 2**16)
    if crank:
        data += struct.pack("<HH", crank[0] % 2**16, crank[1] % 2**16)
    return data


def ticks(ms: int) -> int:
    assert ms * 1024 % 1000 == 0, ms
    return ms * 1024 // 1000


def pedal(
    events_ms: list[int],
    end_ms: int,
    revs0: int = 0,
    ticks0: int = 0,
    t0_ms: int = 1000,
    wheel: bool = True,
    revs_per_event: dict[int, int] | None = None,
) -> list[str]:
    """Notifications alle 250 ms von 0 bis `end_ms` (relativ, Aufnahmezeit ab `t0_ms`).
    Jede meldet das letzte Kurbel-Event mit Zeit ≤ jetzt (wie ein echter Sensor: ohne neues
    Event wiederholt er das letzte). Vor dem ersten Event steht das Start-Event bei 0 ms.
    `revs_per_event`: abweichende Umdrehungen für einzelne Events (Ausreißer)."""
    revs_per_event = revs_per_event or {}
    lines = []
    revs, last_event = revs0, 0
    pending = sorted(events_ms)
    for t in range(0, end_ms + 1, NOTIFY_MS):
        while pending and pending[0] <= t:
            event = pending.pop(0)
            revs += revs_per_event.get(event, 1)
            last_event = event
        crank = (revs, ticks0 + ticks(last_event))
        wheel_data = (1000 + t // 100, ticks(t)) if wheel else None
        lines.append(line(t0_ms + t, CSC, csc(crank=crank, wheel=wheel_data)))
    return lines


def every(start_ms: int, end_ms: int, step_ms: int) -> list[int]:
    return list(range(start_ms, end_ms + 1, step_ms))


# --- FTMS Indoor Bike Data (0x2AD2) -------------------------------------------

# Flag-Bits; Bit 0 „More Data“ ist umgekehrt: 0 = Instantaneous Speed vorhanden.
MORE_DATA, AVG_SPEED, CADENCE, AVG_CADENCE, DISTANCE, RESISTANCE = (1 << b for b in range(6))
POWER, AVG_POWER, ENERGY, HEART_RATE, MET, ELAPSED, REMAINING = (1 << b for b in range(6, 13))


def bike(
    *,
    speed: int | None = None,  # 0,01 km/h
    cadence: int | None = None,  # 0,5 rpm
    power: int | None = None,  # W
    extras: bool = False,
    heart_rate: int = 128,
) -> bytes:
    """Indoor Bike Data. `extras`: zusätzlich alle übrigen Felder mit Lockwerten (Durchschnitte,
    Strecke, Widerstand, Energie, Puls, MET, Zeiten), damit falsche Offsets auffallen."""
    flags = 0 if speed is not None else MORE_DATA
    fields = b""
    if speed is not None:
        fields += struct.pack("<H", speed)
    if extras:
        flags |= AVG_SPEED
        fields += struct.pack("<H", 0x1111)
    if cadence is not None:
        flags |= CADENCE
        fields += struct.pack("<H", cadence)
    if extras:
        flags |= AVG_CADENCE | DISTANCE | RESISTANCE
        fields += struct.pack("<H", 0x2222) + (0x333333).to_bytes(3, "little") + struct.pack("<h", -5)
    if power is not None:
        flags |= POWER
        fields += struct.pack("<h", power)
    if extras:
        flags |= AVG_POWER | ENERGY | HEART_RATE | MET | ELAPSED | REMAINING
        fields += struct.pack("<h", 0x4444) + struct.pack("<HHB", 0x5555, 0x6666, 0x77)
        fields += struct.pack("<BBHH", heart_rate, 0x88, 0x9999, 0xAAAA)
    return struct.pack("<H", flags) + fields


def ftms(payloads: list[bytes], t0_ms: int = 1000) -> list[str]:
    return [line(t0_ms + i * NOTIFY_MS, FTMS_BIKE, data) for i, data in enumerate(payloads)]


FIXTURES: dict[str, list[str]] = {
    # 80 rpm gleichmäßig (Event alle 750 ms, zwei von drei Notifications wiederholen das letzte
    # Event), mit Raddaten davor (Offset-Prüfung). 4 s.
    "csc_steady.raw.jsonl": pedal(every(750, 4000, 750), 4000),
    # Kurbel-Umdrehungen laufen über: Start bei 65533, nach dem 3. Event 0, 1, …
    "csc_crank_overflow.raw.jsonl": pedal(every(750, 6000, 750), 6000, revs0=65533),
    # Event-Zeit läuft über: Start 1000 Ticks vor 65536 (≈ 1 s), ohne Raddaten.
    "csc_time_overflow.raw.jsonl": pedal(every(750, 6000, 750), 6000, ticks0=65536 - 1000, wheel=False),
    # 60 rpm (Event jede Sekunde) bis 4 s, dann 120 rpm (alle 500 ms) bis 8 s – Glättung.
    "csc_step.raw.jsonl": pedal(every(1000, 4000, 1000) + every(4500, 8000, 500), 8000),
    # 80 rpm bis 3 s, dann aufhören (Sensor wiederholt das letzte Event) bis 7 s,
    # ab 7,75 s wieder 80 rpm bis 10 s.
    "csc_stop.raw.jsonl": pedal(every(750, 3000, 750) + every(7750, 10000, 750), 10000),
    # 80 rpm, beim Event 3000 ms springen die Umdrehungen um 10 (→ 800 rpm, Ausreißer).
    # Dazu ein abgeschnittenes Paket und eine fremde Characteristic (beides wird nicht
    # ausgewertet, steht aber in den Rohdaten).
    "csc_outlier.raw.jsonl": (
        pedal(every(750, 5250, 750), 5250, revs_per_event={3000: 10})[:17]
        + [
            line(5005, CSC, csc(crank=(13, ticks(3750)))[:4]),  # zu kurz für die Kurbeldaten
            line(5010, "00002a19-0000-1000-8000-00805f9b34fb", bytes([87])),  # Battery Level
        ]
        + pedal(every(750, 5250, 750), 5250, revs_per_event={3000: 10})[17:]
    ),
    # FTMS: Speed (25,00 + 0,25·i km/h), Kadenz 84 rpm, Leistung 140 + i W; bei i = 5 meldet
    # das Rad 250 rpm (Ausreißer). 9 Notifications.
    "ftms_speed_cadence_power.raw.jsonl": ftms(
        [bike(speed=2500 + 25 * i, cadence=500 if i == 5 else 168, power=140 + i) for i in range(9)]
    ),
    # FTMS: nur Speed (20,0 + 0,5·i km/h) – Kadenz und Leistung fehlen laut Flags.
    "ftms_speed_only.raw.jsonl": ftms([bike(speed=2000 + 50 * i) for i in range(9)]),
    # FTMS mit „More Data“ (Bit 0 = 1 → kein Speed): Kadenz 90,5 rpm, Leistung 200 − i W.
    "ftms_more_data.raw.jsonl": ftms([bike(cadence=181, power=200 - i) for i in range(9)]),
    # FTMS mit allen Feldern (Flags 0x1FFE): Speed 30,00 km/h, Kadenz 70 rpm, Leistung 155 + i W,
    # Puls 128 – dazwischen Lockwerte. Am Ende ein abgeschnittenes Paket (Flags versprechen
    # mehr Bytes als da sind).
    "ftms_all_fields.raw.jsonl": ftms(
        [bike(speed=3000, cadence=140, power=155 + i, extras=True) for i in range(9)]
        + [bike(speed=3000, cadence=140, power=164, extras=True)[:12]]
    ),
    # FTMS: 1 s mit Kadenz 80 rpm, dann 3 s Notifications ohne Kadenzfeld (nur Speed).
    "ftms_cadence_gap.raw.jsonl": ftms(
        [bike(speed=2500, cadence=160) for _ in range(5)] + [bike(speed=2500) for _ in range(12)]
    ),
}


def main() -> None:
    for name, lines in FIXTURES.items():
        (HERE / name).write_text("".join(entry + "\n" for entry in lines), encoding="utf-8", newline="\n")
        print(f"{name}: {len(lines)} Zeilen")


if __name__ == "__main__":
    main()
