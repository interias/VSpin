"""Parser für Cycling Power Measurement (0x2A63) und Fitness Machine Feature (0x2ACC) sowie der `Decoder`
mit beiden: Kadenz aus den Kurbeldaten mit Zählerüberlauf, Herkunft der Watt je Quelle.

Reine Funktionstests ohne Bridge-Prozess; die Byte-Folgen sind handgebaut (Little Endian)."""

import pytest
from trainer_harness import bike, cycling_power, features

from vspin_bridge.parsers import (
    CYCLING_POWER_MEASUREMENT,
    FITNESS_MACHINE_FEATURE,
    INDOOR_BIKE_DATA,
    Decoder,
    ParseError,
    capabilities,
    parse_fitness_machine_features,
)
from vspin_bridge.parsers.cycling_power import parse_cycling_power_measurement
from vspin_bridge.processing import CadenceProcessor
from vspin_bridge.sources.base import Capability, RawNotification


def raw(t_ms: int, char: str, data: bytes) -> RawNotification:
    return RawNotification(t_ms, char, data)


def test_uuid_constants():
    assert CYCLING_POWER_MEASUREMENT == "00002a63-0000-1000-8000-00805f9b34fb"
    assert FITNESS_MACHINE_FEATURE == "00002acc-0000-1000-8000-00805f9b34fb"


def test_power_only():
    measurement = parse_cycling_power_measurement(bytes.fromhex("00 00 c8 00"))
    assert measurement.power_w == 200
    assert measurement.crank_revs is None and measurement.crank_event_time is None


def test_negative_power_is_signed():
    assert parse_cycling_power_measurement(bytes.fromhex("00 00 fb ff")).power_w == -5


def test_crank_revolution_data():
    measurement = parse_cycling_power_measurement(cycling_power(180, crank=(10, 2048)))
    assert (measurement.power_w, measurement.crank_revs, measurement.crank_event_time) == (180, 10, 2048)


def test_fields_before_the_crank_data_are_skipped():
    # Pedal Power Balance (1 Byte), Accumulated Torque (2), Wheel Revolution Data (6) stehen vor den Kurbeldaten.
    data = bytes.fromhex("35 00 c8 00") + b"\x64" + b"\x00\x01" + bytes(6) + bytes.fromhex("07 00 00 04")
    measurement = parse_cycling_power_measurement(data)
    assert (measurement.power_w, measurement.crank_revs, measurement.crank_event_time) == (200, 7, 1024)


def test_bytes_after_the_crank_data_are_ignored():
    data = cycling_power(200, crank=(3, 100)) + bytes.fromhex("e8 03 00 00")
    assert parse_cycling_power_measurement(data).crank_revs == 3


@pytest.mark.parametrize("hex_data", ["", "00", "00 00 c8", "20 00 c8 00 01 00 02", "31 00 c8 00 00 00"])
def test_truncated_raises(hex_data):
    with pytest.raises(ParseError):
        parse_cycling_power_measurement(bytes.fromhex(hex_data))


def test_features():
    both = parse_fitness_machine_features(features(0x4002))
    assert (both.cadence, both.power) == (True, True)
    power = parse_fitness_machine_features(features(0x4000))
    assert (power.cadence, power.power) == (False, True)
    neither = parse_fitness_machine_features(features(0))
    assert (neither.cadence, neither.power) == (False, False)
    assert parse_fitness_machine_features(bytes.fromhex("02 40 00 00")).cadence  # Target Setting Features fehlen


def test_features_too_short():
    with pytest.raises(ParseError):
        parse_fitness_machine_features(bytes.fromhex("02 40"))


# --- Decoder ---------------------------------------------------------------------------------


def test_cadence_from_crank_events_with_counter_overflow():
    decoder = Decoder()
    # 80 rpm = 768 Ticks je Umdrehung; Umdrehungen laufen nach 65535, die Kurbel-Zeit nach 64 s über.
    first = decoder.decode(raw(0, CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=(65534, 65000))))
    assert first.cadence is None  # erstes Event: nur die Basis
    event = (1, (65000 + 2304) % 65536)
    second = decoder.decode(raw(1000, CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=event)))
    assert second.cadence == 80.0
    repeat = decoder.decode(raw(1250, CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=event)))
    assert repeat.cadence is None  # dasselbe Kurbel-Event: kein neuer Wert


def test_power_estimated_follows_the_source():
    data = bike(25.0, 84, 140)
    estimated = Decoder().decode(raw(0, INDOOR_BIKE_DATA, data))
    measured = Decoder(power_estimated=False).decode(raw(0, INDOOR_BIKE_DATA, data))
    assert (estimated.power_w, estimated.power_estimated) == (140, True)  # wie bisher beim Replay
    assert (measured.power_w, measured.power_estimated) == (140, False)
    assert Decoder(power_estimated=False).decode(raw(0, INDOOR_BIKE_DATA, bike(25.0))).power_estimated is None


def test_cycling_power_sample_keeps_speed_and_power_of_the_bike_sample():
    decoder = Decoder(power_estimated=False)
    decoder.decode(raw(0, INDOOR_BIKE_DATA, bike(31.5, None, 210)))
    decoder.decode(raw(100, CYCLING_POWER_MEASUREMENT, cycling_power(205, crank=(0, 0))))
    sample = decoder.decode(raw(1100, CYCLING_POWER_MEASUREMENT, cycling_power(205, crank=(1, 1024))))
    # Das Sample aus 0x2A63 setzt Tempo und Leistung nicht auf `None`; Kadenz kommt nur von ihm.
    assert (sample.cadence, sample.speed_kmh, sample.power_w, sample.power_estimated) == (60.0, 31.5, 210, False)
    assert decoder.decode(raw(1200, INDOOR_BIKE_DATA, bike(31.5, None, 210))).cadence is None


def test_cadence_falls_to_zero_after_2_5_s_when_the_crank_stops_reporting_events():
    decoder, processor = Decoder(power_estimated=False), CadenceProcessor(reports_cadence=True)
    revs = ticks = 0
    published: dict[int, float | None] = {}
    for t in range(0, 6000, 250):  # beide Characteristics im 250-ms-Takt; Kurbel mit 80 rpm bis 2 s, dann Stillstand
        if t < 2000 and t % 750 == 0:
            revs, ticks = revs + 1, ticks + 768
        notifications = (
            (INDOOR_BIKE_DATA, bike(30.0, None, 200)),
            (CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=(revs, ticks))),
        )
        for char, data in notifications:
            published[t] = processor.process(decoder.decode(raw(t, char, data))).sample.cadence
    assert published[1500] == 80.0  # letztes Kurbel-Event
    assert published[3750] == 80.0  # der Wert gilt bis 2,5 s nach dem letzten Event (ADR-0004)
    assert published[4000] == 0.0 == published[5750]  # danach 0, auch wenn 0x2A63 das alte Event wiederholt


def test_cycling_power_alone_delivers_power():
    sample = Decoder(power_estimated=False).decode(raw(0, CYCLING_POWER_MEASUREMENT, cycling_power(180)))
    assert (sample.power_w, sample.power_estimated, sample.speed_kmh) == (180, False, None)


def test_capabilities_of_a_cycling_power_notification():
    assert capabilities(raw(0, CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=(1, 1)))) == {Capability.CADENCE}
    assert capabilities(raw(0, CYCLING_POWER_MEASUREMENT, cycling_power(200))) == set()
    assert capabilities(raw(0, CYCLING_POWER_MEASUREMENT, b"\x00")) == set()
