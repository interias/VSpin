"""Cycling Power Measurement (Characteristic 0x2A63, Cycling Power Service 0x1818).

Aufbau laut Bluetooth-SIG-Spezifikation (Little Endian): `uint16` Flags, `sint16` Instantaneous
Power (Watt, immer da), danach die Felder in fester Reihenfolge, jeweils nur wenn ihr Flag es sagt::

    Bit  Feld                              Typ / Auflösung
    0    Pedal Power Balance               uint8, 0,5 %
    2    Accumulated Torque                uint16, 1/32 Nm
    4    Wheel Revolution Data             uint32 Umdrehungen, uint16 Zeit (1/2048 s)
    5    Crank Revolution Data             uint16 Umdrehungen, uint16 Zeit (1/1024 s)

Alle Felder bis zu den Kurbeldaten werden gelesen (sonst stimmen die Offsets nicht); was dahinter
steht (Extremwerte, Winkel, Energie), ignoriert der Parser. Die Kadenz entsteht wie bei CSC aus
zwei Kurbel-Events (`csc.CscCadence`); die Kurbel-Zeit hat dieselbe Auflösung von 1/1024 s.
"""

import struct
from dataclasses import dataclass

from .csc import CscMeasurement
from .errors import ParseError

PEDAL_POWER_BALANCE = 1 << 0
ACCUMULATED_TORQUE = 1 << 2
WHEEL_DATA = 1 << 4
CRANK_DATA = 1 << 5


@dataclass(frozen=True, slots=True)
class CyclingPowerMeasurement:
    power_w: int
    crank_revs: int | None = None
    crank_event_time: int | None = None

    @property
    def crank(self) -> CscMeasurement:
        """Die Kurbeldaten im Format der CSC-Kadenzrechnung."""
        return CscMeasurement(crank_revs=self.crank_revs, crank_event_time=self.crank_event_time)


def parse_cycling_power_measurement(data: bytes) -> CyclingPowerMeasurement:
    """Bytes → Felder. Wirft `ParseError`, wenn die Notification kürzer ist, als die Flags sagen."""
    if len(data) < 4:
        raise ParseError(f"Cycling Power Measurement zu kurz ({len(data)} Bytes)")
    flags, power = struct.unpack_from("<Hh", data, 0)
    offset = 4
    if flags & PEDAL_POWER_BALANCE:
        offset += 1
    if flags & ACCUMULATED_TORQUE:
        offset += 2
    if flags & WHEEL_DATA:
        offset += 6
    if not flags & CRANK_DATA:
        return CyclingPowerMeasurement(power)
    if len(data) < offset + 4:
        raise ParseError(f"Cycling Power Measurement zu kurz für Crank Revolution Data ({len(data)} Bytes)")
    revs, event_time = struct.unpack_from("<HH", data, offset)
    return CyclingPowerMeasurement(power, revs, event_time)
