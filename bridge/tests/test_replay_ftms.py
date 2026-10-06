"""Replay mit FTMS-Indoor-Bike-Data-Fixtures (0x2AD2): mehrere Flag-Kombinationen.

Die Bridge läuft als echter Prozess (`--source replay … --wait-client`, beschleunigt);
geprüft werden Bus, Session-Dateien und Terminal-Log. Die Fixtures sind handgebaut
(`tests/fixtures/make_fixtures.py`), Notifications alle 250 ms.
"""

import pytest
from bridge_harness import FIXTURES_DIR, read_jsonl, replay_to_end

FAST = ("--speed", "20")


def replay(bridge_process, bus_client, tmp_path, name: str):
    run = replay_to_end(bridge_process, bus_client, FIXTURES_DIR / name, tmp_path, *FAST)
    assert run.returncode == 0
    assert run.states == ["disconnected", "connected", "disconnected"]
    # Rohdaten der Session = Eingabe.
    assert run.raw_path.read_bytes() == (FIXTURES_DIR / name).read_bytes()
    # Eine CSV-Zeile pro Telemetrie am Bus, mit denselben Werten.
    assert [int(r["t_ms"]) for r in run.rows] == [m["t_ms"] for m in run.telemetry]
    for row, message in zip(run.rows, run.telemetry):
        assert row["cadence"] == ("" if message["cadence"] is None else repr(message["cadence"]))
        assert row["speed_kmh"] == ("" if message["speed_kmh"] is None else repr(message["speed_kmh"]))
        assert row["power_w"] == ("" if message["power_w"] is None else repr(message["power_w"]))
        assert row["power_estimated"] == {None: "", True: "true", False: "false"}[message["power_estimated"]]
        assert row["hr_bpm"] == ("" if message["heart_rate"] is None else repr(message["heart_rate"]))
    return run


def capabilities(run) -> list[str]:
    return run.messages[1]["capabilities"]  # status `connected` beim Start der Quelle


def column(run, field: str) -> list:
    return [m[field] for m in run.telemetry]


def test_speed_cadence_and_estimated_power(bridge_process, bus_client, tmp_path):
    run = replay(bridge_process, bus_client, tmp_path, "ftms_speed_cadence_power.raw.jsonl")
    assert run.messages[1]["source"] == "replay"
    assert capabilities(run) == ["CADENCE", "POWER", "SPEED"]
    assert len(run.telemetry) == 9
    assert column(run, "speed_kmh") == [25 + 0.25 * i for i in range(9)]  # 0,01 km/h
    assert column(run, "power_w") == [140 + i for i in range(9)]
    # JC312-Watt sind geschätzt (ADR-0004) – am Bus und in der CSV markiert.
    assert column(run, "power_estimated") == [True] * 9
    assert {r["power_estimated"] for r in run.rows} == {"true"}
    assert column(run, "heart_rate") == [None] * 9
    # Kadenz 84 rpm (168 × 0,5); der Ausreißer 250 rpm bei i = 5 wird verworfen.
    assert column(run, "cadence") == [84.0] * 9
    assert [r["cadence_raw"] for r in run.rows] == ["84.0"] * 5 + ["250.0"] + ["84.0"] * 3
    assert "Kadenz 250.0 rpm verworfen" in run.log


def test_speed_only_leaves_cadence_and_power_null(bridge_process, bus_client, tmp_path):
    run = replay(bridge_process, bus_client, tmp_path, "ftms_speed_only.raw.jsonl")
    assert capabilities(run) == ["SPEED"]
    assert column(run, "speed_kmh") == [20 + 0.5 * i for i in range(9)]
    for field in ("cadence", "power_w", "power_estimated", "heart_rate"):
        assert column(run, field) == [None] * 9, field  # fehlen laut Flags → null
    # Ohne Kadenzfeld greift auch die 2,5-s-Regel nicht: unbekannt bleibt null, nicht 0.
    assert {r["cadence"] for r in run.rows} == {r["cadence_raw"] for r in run.rows} == {""}


def test_more_data_flag_means_no_speed(bridge_process, bus_client, tmp_path):
    run = replay(bridge_process, bus_client, tmp_path, "ftms_more_data.raw.jsonl")
    assert capabilities(run) == ["CADENCE", "POWER"]
    assert column(run, "speed_kmh") == [None] * 9  # Bit 0 gesetzt → kein Instantaneous Speed
    assert column(run, "cadence") == [90.5] * 9  # 181 × 0,5 rpm
    assert column(run, "power_w") == [200 - i for i in range(9)]
    assert column(run, "power_estimated") == [True] * 9


def test_all_fields_offsets(bridge_process, bus_client, tmp_path):
    name = "ftms_all_fields.raw.jsonl"
    run = replay(bridge_process, bus_client, tmp_path, name)
    assert read_jsonl(FIXTURES_DIR / name)[0]["hex"].startswith("fe1f")  # Flags 0x1FFE: alles außer More Data
    assert capabilities(run) == ["CADENCE", "POWER", "SPEED"]
    # Das abgeschnittene letzte Paket wird übersprungen (steht aber in den Rohdaten).
    assert len(run.telemetry) == 9
    assert "Indoor Bike Data zu kurz" in run.log
    # Zwischen den genutzten Feldern stehen Durchschnitte, Strecke (uint24), Widerstand usw.
    assert column(run, "speed_kmh") == [30.0] * 9
    assert column(run, "cadence") == [70.0] * 9
    assert column(run, "power_w") == [155 + i for i in range(9)]  # nach Strecke/Widerstand
    assert column(run, "heart_rate") == [128] * 9  # nach der Energie (5 Bytes)
    assert {r["hr_bpm"] for r in run.rows} == {"128"}


@pytest.mark.parametrize("speed", ["20", "5"])
def test_cadence_falls_to_zero_after_two_and_a_half_seconds_without_cadence(bridge_process, bus_client, tmp_path, speed):
    # 80 rpm bis 1 s, danach Notifications ohne Kadenzfeld: Wert bleibt, ab 3,5 s (2,5 s nach
    # dem letzten Wert) ist die Kadenz 0 – unabhängig von der Abspielgeschwindigkeit.
    run = replay_to_end(
        bridge_process, bus_client, FIXTURES_DIR / "ftms_cadence_gap.raw.jsonl", tmp_path, "--speed", speed
    )
    assert capabilities(run) == ["CADENCE", "SPEED"]
    assert column(run, "cadence") == [80.0] * 14 + [0.0] * 3
    assert column(run, "speed_kmh") == [25.0] * 17
    assert run.states == ["disconnected", "connected", "disconnected"]  # kein stale: Daten liefen
