"""FTMS Indoor Bike Data (Characteristic 0x2AD2, Fitness Machine Service 0x1826).

Aufbau laut Bluetooth-SIG-Spezifikation (Little Endian): `uint16` Flags, danach die Felder
in fester Reihenfolge, jeweils nur wenn ihr Flag es sagt::

    Bit  Feld                              Typ / Auflösung
    0    More Data                         ACHTUNG umgekehrt: Bit 0 = 0 → Instantaneous Speed
         Instantaneous Speed               uint16, 0,01 km/h             (vorhanden!)
    1    Average Speed                     uint16, 0,01 km/h
    2    Instantaneous Cadence             uint16, 0,5 rpm
    3    Average Cadence                   uint16, 0,5 rpm
    4    Total Distance                    uint24, m
    5    Resistance Level                  sint16
    6    Instantaneous Power               sint16, W
    7    Average Power                     sint16, W
    8    Expended Energy                   uint16 kcal gesamt, uint16 kcal/h, uint8 kcal/min
    9    Heart Rate                        uint8, bpm
    10   Metabolic Equivalent              uint8, 0,1
    11   Elapsed Time                      uint16, s
    12   Remaining Time                    uint16, s

Alle Felder werden gelesen (sonst stimmen die Offsets der folgenden nicht); genutzt werden
Geschwindigkeit, Kadenz, Leistung und Puls. Bytes hinter dem letzten angekündigten Feld
(z. B. künftige Felder bei reservierten Flag-Bits) werden ignoriert.
"""

import struct
from dataclasses import dataclass

from .errors import ParseError

MORE_DATA = 1 << 0

# (Flag-Bit, Name, struct-Format) in Reihenfolge der Spezifikation; Bit 0 ist Sonderfall.
_FIELDS: tuple[tuple[int, str, str], ...] = (
    (1, "average_speed", "<H"),
    (2, "cadence", "<H"),
    (3, "average_cadence", "<H"),
    (4, "total_distance", "uint24"),
    (5, "resistance", "<h"),
    (6, "power", "<h"),
    (7, "average_power", "<h"),
    (8, "expended_energy", "<HHB"),
    (9, "heart_rate", "<B"),
    (10, "metabolic_equivalent", "<B"),
    (11, "elapsed_time", "<H"),
    (12, "remaining_time", "<H"),
)


@dataclass(frozen=True, slots=True)
class IndoorBikeData:
    speed_kmh: float | None = None
    cadence_rpm: float | None = None
    power_w: int | None = None
    heart_rate: int | None = None


def parse_indoor_bike_data(data: bytes) -> IndoorBikeData:
    """Bytes → Felder; fehlt ein Feld laut Flags, ist es `None`. Wirft `ParseError`, wenn die
    Notification kürzer ist, als die Flags ankündigen."""
    if len(data) < 2:
        raise ParseError(f"Indoor Bike Data ohne Flags ({len(data)} Bytes)")
    flags = int.from_bytes(data[:2], "little")
    offset = 2
    raw: dict[str, tuple] = {}
    if not flags & MORE_DATA:  # umgekehrte Logik: Bit 0 = 0 heißt „Speed vorhanden“
        raw["speed"], offset = _read("<H", data, offset, "speed")
    for bit, name, fmt in _FIELDS:
        if flags & (1 << bit):
            raw[name], offset = _read(fmt, data, offset, name)
    speed = raw.get("speed")
    cadence = raw.get("cadence")
    power = raw.get("power")
    heart_rate = raw.get("heart_rate")
    return IndoorBikeData(
        speed_kmh=None if speed is None else speed[0] / 100,
        cadence_rpm=None if cadence is None else cadence[0] / 2,
        power_w=None if power is None else power[0],
        # 0 bpm heißt bei FTMS-Geräten „kein Pulssensor“, kein echter Wert.
        heart_rate=None if heart_rate is None or heart_rate[0] == 0 else heart_rate[0],
    )


def _read(fmt: str, data: bytes, offset: int, name: str) -> tuple[tuple, int]:
    size = 3 if fmt == "uint24" else struct.calcsize(fmt)
    if len(data) < offset + size:
        raise ParseError(f"Indoor Bike Data zu kurz für {name} ({len(data)} Bytes)")
    if fmt == "uint24":
        return (int.from_bytes(data[offset : offset + 3], "little"),), offset + size
    return struct.unpack_from(fmt, data, offset), offset + size
