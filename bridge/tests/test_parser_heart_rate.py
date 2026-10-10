"""Parser für Heart Rate Measurement (0x2A37): uint8/uint16, Energy Expended, RR-Intervalle, kaputte Längen.

Reine Funktionstests ohne Bridge-Prozess; die Byte-Folgen sind handgebaut (Little Endian).
"""

import pytest

from vspin_bridge.parsers import HEART_RATE_MEASUREMENT, ParseError, parse_heart_rate_measurement


def bpm(hex_data: str) -> int:
    return parse_heart_rate_measurement(bytes.fromhex(hex_data)).bpm


def test_uuid_constant():
    assert HEART_RATE_MEASUREMENT == "00002a37-0000-1000-8000-00805f9b34fb"


def test_uint8():
    assert bpm("00 48") == 72


def test_uint16_little_endian():
    assert bpm("01 2c 01") == 300


def test_sensor_contact_bits_do_not_change_the_result():
    assert bpm("00 48") == bpm("04 48") == bpm("06 48")


def test_energy_expended():
    assert bpm("08 48 e8 03") == 72


def test_one_rr_interval():
    assert bpm("10 48 00 04") == 72


def test_several_rr_intervals():
    assert bpm("10 48 00 04 f0 03 10 04") == 72


def test_energy_expended_and_rr_intervals_with_uint16():
    assert bpm("19 2c 01 e8 03 00 04 f0 03") == 300


def test_rr_flag_without_intervals_is_valid():
    assert bpm("10 48") == 72


def test_trailing_bytes_without_flag_are_ignored():
    assert bpm("00 48 00 04 ff") == 72


@pytest.mark.parametrize(
    "hex_data, text",
    [
        ("", "Flags"),
        ("00", "Puls"),
        ("01 2c", "Puls"),
        ("08 48 e8", "Energy Expended"),
        ("08 48", "Energy Expended"),
        ("18 48 e8", "Energy Expended"),
        ("10 48 00", "RR-Intervalle"),
        ("18 48 e8 03 00 04 f0", "RR-Intervalle"),
    ],
)
def test_broken_lengths_raise_parse_error(hex_data, text):
    with pytest.raises(ParseError, match=text):
        parse_heart_rate_measurement(bytes.fromhex(hex_data))
