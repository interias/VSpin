"""Gemeinsames für die Trainer-Tests (Spec #75): handgebaute Notifications nach der Bluetooth-SIG-Spezifikation
(Little Endian) und ein Fake-Trainer hinter `fake_ble.py`. Kein Test spricht echte Hardware an."""

import struct

from fake_ble import FakeBleAdapter
from vspin_bridge.parsers import FITNESS_MACHINE_FEATURE
from vspin_bridge.sources.trainer import CYCLING_POWER_SERVICE, FTMS_SERVICE

KICKR = "AA:00:00:00:10:01"
KICKR_NAME = "KICKR CORE 2 1234"

FEATURES_CADENCE_POWER = 0x4002  # Bit 1 Cadence, Bit 14 Power Measurement
FEATURES_POWER_ONLY = 0x4000


def features(bits: int) -> bytes:
    """Fitness Machine Feature `0x2ACC`: Fitness Machine Features, dann Target Setting Features."""
    return struct.pack("<II", bits, 0)


def bike(speed_kmh: float | None = None, cadence_rpm: float | None = None, power_w: int | None = None) -> bytes:
    """Indoor Bike Data `0x2AD2`: Flags, [Speed 0,01 km/h (Bit 0 = 0)], [Kadenz 0,5 rpm], [Leistung]."""
    flags = (0 if speed_kmh is not None else 1)
    flags |= 4 if cadence_rpm is not None else 0
    flags |= 0x40 if power_w is not None else 0
    data = struct.pack("<H", flags)
    if speed_kmh is not None:
        data += struct.pack("<H", round(speed_kmh * 100))
    if cadence_rpm is not None:
        data += struct.pack("<H", round(cadence_rpm * 2))
    if power_w is not None:
        data += struct.pack("<h", power_w)
    return data


def cycling_power(power_w: int, crank: tuple[int, int] | None = None) -> bytes:
    """Cycling Power Measurement `0x2A63`: Flags, Leistung, [Kurbel-Umdrehungen, Kurbel-Zeit 1/1024 s]."""
    data = struct.pack("<Hh", 0x20 if crank else 0, power_w)
    if crank:
        data += struct.pack("<HH", crank[0] % 2**16, crank[1] % 2**16)
    return data


def kickr(
    adapter: FakeBleAdapter,
    address: str = KICKR,
    rssi: int = -55,
    bits: int = FEATURES_CADENCE_POWER,
    services: tuple[str, ...] = (FTMS_SERVICE, CYCLING_POWER_SERVICE),
) -> str:
    """Ein Trainer, der sendet, mit lesbaren Features."""
    adapter.appear(address, KICKR_NAME, rssi, services=services)
    adapter.set_readable(address, FITNESS_MACHINE_FEATURE, features(bits))
    return address
