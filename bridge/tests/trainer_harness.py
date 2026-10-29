"""Gemeinsames für die Trainer-Tests (Spec #75): handgebaute Notifications nach der Bluetooth-SIG-Spezifikation
(Little Endian) und ein Fake-Trainer hinter `fake_ble.py`. Kein Test spricht echte Hardware an."""

import struct
from collections.abc import Callable, Mapping

from fake_ble import FakeBleAdapter
from vspin_bridge.parsers import FITNESS_MACHINE_FEATURE
from vspin_bridge.sources.trainer import CYCLING_POWER_SERVICE, FTMS_SERVICE
from vspin_bridge.sources.trainer_control import CONTROL_POINT, OP_RESPONSE, RESULT_SUCCESS

KICKR = "AA:00:00:00:10:01"
KICKR_NAME = "KICKR CORE 2 1234"

FEATURES_CADENCE_POWER = 0x4002  # Bit 1 Cadence, Bit 14 Power Measurement
FEATURES_POWER_ONLY = 0x4000
TARGET_SIMULATION = 1 << 13  # Target Setting Features: Indoor Bike Simulation Parameters
TARGET_POWER = 1 << 3  # Target Setting Features: Power Target (ERG)


def features(bits: int, targets: int = 0) -> bytes:
    """Fitness Machine Feature `0x2ACC`: Fitness Machine Features, dann Target Setting Features."""
    return struct.pack("<II", bits, targets)


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
    targets: int = 0,
) -> str:
    """Ein Trainer, der sendet, mit lesbaren Features (`targets`: Target Setting Features, Standard keine)."""
    adapter.appear(address, KICKR_NAME, rssi, services=services)
    adapter.set_readable(address, FITNESS_MACHINE_FEATURE, features(bits, targets))
    return address


def control_responder(results: Mapping[int, int | None] | None = None) -> Callable[[bytes], bytes | None]:
    """Antworten des Control Points nach FTMS: `0x80 <Op-Code> <Ergebnis>`, Ergebnis je Op-Code aus `results`
    (Standard Erfolg `0x01`; `None` = keine Antwort)."""
    results = dict(results or {})

    def respond(data: bytes) -> bytes | None:
        result = results.get(data[0], RESULT_SUCCESS)
        return None if result is None else bytes([OP_RESPONSE, data[0], result])

    return respond


def sim_kickr(
    adapter: FakeBleAdapter,
    address: str = KICKR,
    respond: Callable[[bytes], bytes | None] | None = None,
    **kickr_args,
) -> str:
    """Ein Trainer mit Indoor Bike Simulation, dessen Control Point `0x2AD9` antwortet (Standard: immer Erfolg). Wie am
    echten Gerät lehnt er Schreibzugriffe ab, solange die Indications von `0x2AD9` nicht abonniert sind."""
    kickr_args["targets"] = TARGET_SIMULATION | kickr_args.get("targets", 0)
    kickr(adapter, address, **kickr_args)
    adapter.answer(address, CONTROL_POINT, CONTROL_POINT, respond or control_responder())
    return address


def control_writes(adapter: FakeBleAdapter, address: str = KICKR) -> list[bytes]:
    """Alles, was auf den Control Point dieses Trainers geschrieben wurde, in Reihenfolge."""
    return [data for to, char, data in adapter.writes if to == address and char == CONTROL_POINT]


def simulation(grade_hundredths: int) -> bytes:
    """Erwartete Bytes von `0x11`: Wind 0, Steigung in 0,01 %, Crr 0,0040 (40), Cw 0,51 kg/m (51)."""
    return bytes([0x11]) + struct.pack("<hhBB", 0, grade_hundredths, 40, 51)


def target_power(watts: int) -> bytes:
    """Erwartete Bytes von `0x05`: Zielleistung sint16 in W."""
    return bytes([0x05]) + struct.pack("<h", watts)
