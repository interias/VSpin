"""CSC Measurement (Characteristic 0x2A5B, Cycling Speed and Cadence Service 0x1816).

Aufbau laut Bluetooth-SIG-Spezifikation (Little Endian)::

    uint8   Flags            Bit 0: Wheel Revolution Data vorhanden
                             Bit 1: Crank Revolution Data vorhanden
    uint32  Cumulative Wheel Revolutions      } nur bei Bit 0
    uint16  Last Wheel Event Time (1/1024 s)  }
    uint16  Cumulative Crank Revolutions      } nur bei Bit 1
    uint16  Last Crank Event Time (1/1024 s)  }

Kadenz entsteht aus zwei aufeinanderfolgenden Kurbel-Events: Δ Umdrehungen / Δ Event-Zeit.
Beide uint16-Zähler laufen über (Umdrehungen nach 65535, Event-Zeit nach 64 s); die
Differenzen werden deshalb modulo 2^16 gebildet.

Geschwindigkeit aus den Raddaten bräuchte den Radumfang, den die Bridge nicht kennt –
CSC liefert daher keine Geschwindigkeit (`speed_kmh` bleibt `null`).
"""

import struct
from dataclasses import dataclass

from .errors import ParseError

WHEEL_DATA = 0x01
CRANK_DATA = 0x02

EVENT_TIME_HZ = 1024
U16 = 0x10000
# Längste Lücke, über die eine Differenz der Event-Zeit eindeutig ist (64 s, ein uint16-Umlauf).
MAX_EVENT_GAP_MS = U16 * 1000 // EVENT_TIME_HZ


@dataclass(frozen=True, slots=True)
class CscMeasurement:
    wheel_revs: int | None = None
    wheel_event_time: int | None = None
    crank_revs: int | None = None
    crank_event_time: int | None = None

    @property
    def has_crank(self) -> bool:
        return self.crank_revs is not None


def parse_csc_measurement(data: bytes) -> CscMeasurement:
    """Bytes → Felder. Wirft `ParseError`, wenn die Notification kürzer ist, als die Flags sagen.
    Bytes hinter den angekündigten Feldern werden ignoriert."""
    if not data:
        raise ParseError("CSC Measurement ohne Flags-Byte")
    flags = data[0]
    offset = 1
    wheel_revs = wheel_time = crank_revs = crank_time = None
    if flags & WHEEL_DATA:
        wheel_revs, wheel_time = _unpack("<IH", data, offset, "Wheel Revolution Data")
        offset += 6
    if flags & CRANK_DATA:
        crank_revs, crank_time = _unpack("<HH", data, offset, "Crank Revolution Data")
    return CscMeasurement(wheel_revs, wheel_time, crank_revs, crank_time)


def _unpack(fmt: str, data: bytes, offset: int, what: str) -> tuple:
    size = struct.calcsize(fmt)
    if len(data) < offset + size:
        raise ParseError(f"CSC Measurement zu kurz für {what} ({len(data)} Bytes)")
    return struct.unpack_from(fmt, data, offset)


class CscCadence:
    """Kadenz aus aufeinanderfolgenden CSC-Measurements (zustandsbehaftet).

    `update` liefert nur bei einem **neuen** Kurbel-Event eine Kadenz. Wiederholt das Gerät
    das letzte Event (gleiche Umdrehungen), kommt `None` – das zählt für die 2,5-s-Regel als
    „kein neues Event“ (siehe `processing`). Nach mehr als 64 s ohne neues Event (Empfangszeit
    `t_ms`) ist die Differenz der Event-Zeit nicht mehr eindeutig; dann beginnt die Rechnung
    mit dem neuen Event von vorn (keine Kadenz für dieses Event).
    """

    def __init__(self) -> None:
        self._revs: int | None = None
        self._event_time: int | None = None
        self._seen_ms: int = 0  # Empfangszeit des letzten neuen Events

    def update(self, measurement: CscMeasurement, t_ms: int) -> float | None:
        if not measurement.has_crank:
            return None
        revs, event_time = measurement.crank_revs, measurement.crank_event_time
        if self._revs is None:
            self._remember(revs, event_time, t_ms)
            return None
        delta_revs = (revs - self._revs) % U16
        if delta_revs == 0:
            return None  # kein neues Kurbel-Event (Wiederholung)
        delta_time = (event_time - self._event_time) % U16
        too_old = t_ms - self._seen_ms >= MAX_EVENT_GAP_MS
        self._remember(revs, event_time, t_ms)
        if delta_time == 0 or too_old:
            return None  # nicht berechenbar: neue Basis, nächstes Event liefert wieder Kadenz
        return delta_revs * 60.0 * EVENT_TIME_HZ / delta_time

    def _remember(self, revs: int, event_time: int, t_ms: int) -> None:
        self._revs, self._event_time, self._seen_ms = revs, event_time, t_ms
