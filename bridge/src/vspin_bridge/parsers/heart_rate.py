"""Heart Rate Measurement (Characteristic 0x2A37, Heart Rate Service 0x180D).

Aufbau laut Bluetooth-SIG-Spezifikation (Little Endian)::

    uint8   Flags             Bit 0: Puls als uint16 (sonst uint8)
                              Bit 1-2: Sensor Contact (Status, wird nicht ausgewertet)
                              Bit 3: Energy Expended vorhanden
                              Bit 4: RR-Intervalle vorhanden
    uint8 / uint16  Heart Rate Measurement Value (bpm)
    uint16  Energy Expended (kJ)                      } nur bei Bit 3
    uint16  RR-Interval (1/1024 s), beliebig viele    } nur bei Bit 4

Brustgurt und Uhr nutzen dasselbe Standardprofil. Energy Expended und RR-Intervalle werden
nur so weit gelesen, dass die Länge stimmt und die Offsets passen; ausgewertet werden sie
nicht (keine RR-/HRV-Auswertung).
"""

from dataclasses import dataclass

from .errors import ParseError

HEART_RATE_16BIT = 0x01
ENERGY_EXPENDED = 0x08
RR_INTERVALS = 0x10


@dataclass(frozen=True, slots=True)
class HeartRateMeasurement:
    bpm: int


def parse_heart_rate_measurement(data: bytes) -> HeartRateMeasurement:
    """Bytes → Puls. Wirft `ParseError`, wenn die Notification kürzer ist, als die Flags sagen,
    oder die RR-Intervalle nicht aus ganzen uint16 bestehen. Bytes hinter den angekündigten
    Feldern werden ignoriert."""
    if not data:
        raise ParseError("Heart Rate Measurement ohne Flags-Byte")
    flags = data[0]
    bpm_size = 2 if flags & HEART_RATE_16BIT else 1
    offset = 1 + bpm_size
    if len(data) < offset:
        raise ParseError(f"Heart Rate Measurement zu kurz für den Puls ({len(data)} Bytes)")
    bpm = int.from_bytes(data[1:offset], "little")
    if flags & ENERGY_EXPENDED:
        offset += 2
        if len(data) < offset:
            raise ParseError(f"Heart Rate Measurement zu kurz für Energy Expended ({len(data)} Bytes)")
    if flags & RR_INTERVALS and (len(data) - offset) % 2:
        raise ParseError(
            f"Heart Rate Measurement: RR-Intervalle mit ungerader Länge ({len(data) - offset} Bytes)"
        )
    return HeartRateMeasurement(bpm)
