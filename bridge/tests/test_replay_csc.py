"""Replay (`--source replay DATEI`) mit CSC-Measurement-Fixtures und die Datenaufbereitung
(ADR-0004). Die Bridge läuft als echter Prozess; geprüft werden Bus, Session-Dateien und
Terminal-Log. Die Fixtures sind handgebaut (`tests/fixtures/make_fixtures.py`).

Mit `--wait-client` beginnt das Replay erst, wenn der Test-Client verbunden ist – so sieht
er jede Notification. Jede auswertbare Notification ergibt genau eine Telemetrie-Nachricht.
Die Aufbereitung rechnet auf der Zeitachse der Aufnahme: die Werte sind unabhängig von
`--speed`, deshalb laufen die meisten Tests beschleunigt.
"""

import itertools
import math
import struct

import pytest
from bridge_harness import FIXTURES_DIR, read_jsonl, replay_to_end, run_bridge, wait_until

FAST = ("--speed", "20")
CSC = "00002a5b-0000-1000-8000-00805f9b34fb"
NULL_FIELDS = ("speed_kmh", "power_w", "power_estimated", "heart_rate")

# `--wait-client` gibt beim ersten Client frei: ein fremder Client am Bus (ein laufendes Spiel) startete das
# Replay vor dem Test-Client.
pytestmark = pytest.mark.usefixtures("isolated_bus")


def fixture(name: str):
    return FIXTURES_DIR / name


def record_times(name: str) -> list[int]:
    """Aufnahmezeiten der Notifications, die die Bridge auswerten kann."""
    return [entry["t_ms"] for entry in read_jsonl(fixture(name)) if entry["char"] == CSC and len(entry["hex"]) > 8]


def relative(name: str) -> list[int]:
    times = record_times(name)
    return [t - times[0] for t in times]


def crank_fields(hex_: str) -> tuple[int, int]:
    """Kurbeldaten unabhängig von der Bridge aus den Bytes gelesen (nur Fixture-Kontrolle)."""
    data = bytes.fromhex(hex_)
    offset = 1 + (6 if data[0] & 0x01 else 0)
    return struct.unpack_from("<HH", data, offset)


def reference_cadence(times: list[int], raw: list[float | None]) -> list[float | None]:
    """ADR-0004 als Referenz: verwerfen außerhalb 0–200, EMA mit τ = 0,3 s (zeitbasiert),
    Neustart nach ≥ 2,5 s ohne Wert, Kadenz 0 nach 2,5 s ohne neuen Wert."""
    ema = ema_t = last = None
    out = []
    for t, value in zip(times, raw):
        if last is None:
            last = t
        if value is not None and 0 <= value <= 200:
            if ema is None or t - last >= 2500:
                ema = value
            else:
                ema += (1 - math.exp(-(t - ema_t) / 300)) * (value - ema)
            ema_t = last = t
        elif ema is not None and t - last >= 2500:
            ema, ema_t = 0.0, t
        out.append(None if ema is None else round(ema, 1))
    return out


def assert_close(actual: list, expected: list) -> None:
    assert len(actual) == len(expected), (actual, expected)
    for a, e in zip(actual, expected):
        assert (a is None) == (e is None) and (a is None or abs(a - e) <= 0.1), (actual, expected)


def raw_column(run) -> list[float | None]:
    return [float(r["cadence_raw"]) if r["cadence_raw"] else None for r in run.rows]


def assert_bus_matches_csv(run) -> None:
    """Eine CSV-Zeile pro Telemetrie am Bus, gleiche Zeit und gleiche Werte."""
    assert [int(r["t_ms"]) for r in run.rows] == [m["t_ms"] for m in run.telemetry]
    for row, message in zip(run.rows, run.telemetry):
        assert (float(row["cadence"]) if row["cadence"] else None) == message["cadence"]
        assert row["status"] == "connected"


def steady_raw(name: str, period_ms: int = 750, value: float = 80.0) -> list[float | None]:
    """Neues Kurbel-Event alle `period_ms` ab dem Start-Event bei 0 → Rohwert, sonst nichts."""
    return [value if t > 0 and t % period_ms == 0 else None for t in relative(name)]


def test_steady_csc_replay_at_the_bus(bridge_process, bus_client, tmp_path):
    run = replay_to_end(bridge_process, bus_client, fixture("csc_steady.raw.jsonl"), tmp_path, *FAST)
    assert run.returncode == 0
    # Erst nach dem ersten Client geht es los: disconnected → connected → … → Ende.
    assert run.states == ["disconnected", "connected", "disconnected"]
    status = run.messages[1]
    assert status["source"] == "replay" and status["capabilities"] == ["CADENCE"]
    assert len(run.telemetry) == 17  # eine Telemetrie pro Notification

    # Erste Notification: nur Bezugspunkt; danach alle 750 ms ein neues Event = 80 rpm.
    # Wiederholte Events (2 von 3 Notifications) liefern keinen neuen Rohwert.
    expected_raw = steady_raw("csc_steady.raw.jsonl")
    assert raw_column(run) == expected_raw
    assert [m["cadence"] for m in run.telemetry] == [None, None, None] + [80.0] * 14
    for message in run.telemetry:
        assert all(message[field] is None for field in NULL_FIELDS)  # CSC: kein Tempo, keine Leistung
    assert_bus_matches_csv(run)
    # Session-Rohdaten: identisch zur Eingabe (gleiche Zeilen, gleiche t_ms).
    assert run.raw_path.read_bytes() == fixture("csc_steady.raw.jsonl").read_bytes()
    assert run.raw_path.stem == run.csv_path.stem + ".raw"  # gleicher Session-Name


@pytest.mark.parametrize(
    ("name", "field"),
    [("csc_crank_overflow.raw.jsonl", 0), ("csc_time_overflow.raw.jsonl", 1)],
    ids=["crank-revolutions", "event-time"],
)
def test_counter_overflow_keeps_cadence_correct(bridge_process, bus_client, tmp_path, name, field):
    # Kontrolle der Fixture: der Zähler läuft tatsächlich über (wird kleiner).
    values = [crank_fields(e["hex"])[field] for e in read_jsonl(fixture(name))]
    assert any(b < a for a, b in itertools.pairwise(values)), values

    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    assert raw_column(run) == steady_raw(name)  # auch über den Überlauf hinweg genau 80 rpm
    assert [m["cadence"] for m in run.telemetry][3:] == [80.0] * (len(run.telemetry) - 3)
    assert_bus_matches_csv(run)


def test_cadence_is_smoothed_with_0_3_second_time_constant(bridge_process, bus_client, tmp_path):
    name = "csc_step.raw.jsonl"
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    times = relative(name)
    # 60 rpm bis 4 s (Event jede Sekunde), dann 120 rpm (alle 500 ms).
    expected_raw = [
        60.0 if 0 < t <= 4000 and t % 1000 == 0 else 120.0 if t > 4000 and t % 500 == 0 else None for t in times
    ]
    assert raw_column(run) == expected_raw

    bus = [m["cadence"] for m in run.telemetry]
    assert_close(bus, reference_cadence(times, expected_raw))
    by_time = dict(zip(times, bus))
    assert by_time[4000] == 60.0
    # Sprung auf 120 ab 4,5 s: geglättet statt sprunghaft – der erste Wert holt bei 500 ms
    # Abstand 1 − e^(−0,5/0,3) ≈ 81 % des Sprungs auf, nach 1 s ist er fast ganz oben.
    assert 100 < by_time[4500] < 115
    assert 117 < by_time[5000] < 119
    assert 119 < by_time[5500] < 120
    assert by_time[8000] > 119.5
    assert bus[4:] == sorted(bus[4:])  # ab dem ersten Wert nur steigend
    assert_bus_matches_csv(run)


def test_cadence_drops_to_zero_after_two_and_a_half_seconds_without_crank_event(bridge_process, bus_client, tmp_path):
    name = "csc_stop.raw.jsonl"
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    times = relative(name)
    # Letztes Event bei 3 s, dann wiederholt der Sensor es; ab 7,75 s wieder Events.
    # Das erste neue Event umspannt die Pause: 1 Umdrehung in 4,75 s.
    expected_raw = [
        80.0 if (0 < t <= 3000 and t % 750 == 0) or (t > 7750 and (t - 7750) % 750 == 0)
        else 60_000 / 4750 if t == 7750
        else None
        for t in times
    ]
    assert raw_column(run) == expected_raw
    bus = dict(zip(times, (m["cadence"] for m in run.telemetry)))

    # Wiederholte Events zählen zur 2,5-s-Regel, liefern aber keinen neuen Wert:
    # bis knapp 2,5 s nach dem letzten Event bleibt 80, ab 2,5 s ist die Kadenz 0.
    assert {bus[t] for t in times if 750 <= t < 5500} == {80.0}
    assert {bus[t] for t in times if 5500 <= t < 7750} == {0.0}
    # Wieder treten: Glättung startet neu beim ersten Wert und steigt Richtung 80.
    assert bus[7750] == round(60_000 / 4750, 1)
    rising = [bus[t] for t in times if t >= 7750]
    assert rising == sorted(rising) and 60 < rising[-1] <= 80, rising
    assert_close([m["cadence"] for m in run.telemetry], reference_cadence(times, expected_raw))
    # Status bleibt connected – Kadenz 0 mit weiterlaufenden Daten ist kein Ausfall.
    assert run.states == ["disconnected", "connected", "disconnected"]
    assert_bus_matches_csv(run)


def test_outlier_is_discarded_and_junk_is_skipped(bridge_process, bus_client, tmp_path):
    name = "csc_outlier.raw.jsonl"
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    entries = read_jsonl(fixture(name))
    assert len(run.telemetry) == len(entries) - 2  # abgeschnittenes Paket + fremde Characteristic

    times = relative(name)
    expected_raw = [800.0 if t == 3000 else 80.0 if t > 0 and t % 750 == 0 else None for t in times]
    assert raw_column(run) == expected_raw  # die CSV hält den verworfenen Rohwert fest …
    # … am Bus kommt er nie an: nicht begrenzt (200), sondern verworfen.
    assert [m["cadence"] for m in run.telemetry] == [None, None, None] + [80.0] * (len(times) - 3)
    assert "Kadenz 800.0 rpm verworfen (außerhalb 0–200 rpm)" in run.log
    assert "CSC Measurement zu kurz" in run.log
    assert "Characteristic 00002a19-0000-1000-8000-00805f9b34fb wird nicht ausgewertet" in run.log
    # Rohdaten enthalten alles, auch was nicht ausgewertet wurde.
    assert run.raw_path.read_bytes() == fixture(name).read_bytes()
    assert_bus_matches_csv(run)


def bus_span_ms(run) -> int:
    return run.telemetry[-1]["t_ms"] - run.telemetry[0]["t_ms"]


def test_replay_in_real_time(bridge_process, bus_client, tmp_path):
    name = "csc_steady.raw.jsonl"  # 4 s Aufnahme
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path)
    assert 3900 <= bus_span_ms(run) <= 4600, bus_span_ms(run)
    gaps = [b["t_ms"] - a["t_ms"] for a, b in itertools.pairwise(run.telemetry)]
    assert all(200 <= gap <= 400 for gap in gaps), gaps  # Takt der Aufnahme: 250 ms
    # Gleiche Werte wie beschleunigt (Aufbereitung auf der Zeitachse der Aufnahme).
    assert [m["cadence"] for m in run.telemetry] == [None, None, None] + [80.0] * 14
    assert run.raw_path.read_bytes() == fixture(name).read_bytes()


def test_replay_accelerated(bridge_process, bus_client, tmp_path):
    name = "csc_stop.raw.jsonl"  # 10 s Aufnahme → 1 s bei --speed 10
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, "--speed", "10")
    assert 950 <= bus_span_ms(run) <= 2000, bus_span_ms(run)
    assert_close([m["cadence"] for m in run.telemetry], reference_cadence(relative(name), raw_column(run)))
    assert run.raw_path.read_bytes() == fixture(name).read_bytes()


def test_replay_without_client_still_writes_the_session(bridge_process, tmp_path):
    name = "csc_steady.raw.jsonl"
    bridge = bridge_process("--source", "replay", str(fixture(name)), "--speed", "20", "--sessions-dir", str(tmp_path))
    wait_until(lambda: "Status: disconnected (Quelle beendet)" in bridge.log(), 10.0, "Replay zu Ende")
    assert bridge.stop() == 0
    [raw_path] = tmp_path.glob("*.raw.jsonl")
    assert raw_path.read_bytes() == fixture(name).read_bytes()
    [csv_path] = tmp_path.glob("*.csv")
    assert len(csv_path.read_text(encoding="utf-8").splitlines()) == 1 + 17


BAD_REPLAYS = [
    pytest.param('{"t_ms": 0, "char": "x", "hex": "zz"}\n', "Zeile 1", "hex", id="bad-hex"),
    pytest.param('{"t_ms": 5, "char": "x", "hex": "00"}\n\n{"t_ms": 4, "char": "x", "hex": "00"}\n', "Zeile 3", "kleiner", id="time-goes-back"),
    pytest.param("kein json\n", "Zeile 1", "JSON", id="no-json"),
    pytest.param('{"t_ms": "0", "char": "x", "hex": "00"}\n', "Zeile 1", "t_ms", id="t-ms-string"),
    pytest.param('{"t_ms": 0, "hex": "00"}\n', "Zeile 1", "char", id="char-missing"),
    pytest.param("\n\n", "", "keine Notifications", id="empty"),
]


@pytest.mark.parametrize(("text", "where", "hint"), BAD_REPLAYS)
def test_bad_replay_file_is_rejected_with_message(tmp_path, text, where, hint):
    path = tmp_path / "bad.raw.jsonl"
    path.write_text(text, encoding="utf-8")
    result = run_bridge(["--source", "replay", str(path)], cwd=tmp_path)
    assert result.returncode == 2, result
    assert hint in result.stderr and where in result.stderr and str(path) in result.stderr, result.stderr
    assert "Traceback" not in result.stderr
    assert not (tmp_path / "sessions").exists()  # Abbruch vor dem Start: keine Session


@pytest.mark.parametrize(
    ("args", "hint"),
    [
        (["--source", "replay"], "braucht eine Datei"),
        (["--source", "replay", "fehlt.raw.jsonl"], "nicht lesbar"),
        (["--source", "replay", str(FIXTURES_DIR / "csc_steady.raw.jsonl"), "--speed", "0"], "--speed"),
        (["--source", "replay", str(FIXTURES_DIR / "csc_steady.raw.jsonl"), "--speed", "nan"], "--speed"),
        (["--source", "sim", "--speed", "10"], "nur mit --source replay"),
        (["--source", "sim", "--wait-client"], "nur mit --source replay"),
        (["--source", "sim", str(FIXTURES_DIR / "csc_steady.raw.jsonl")], "nur mit --source replay"),
        (["--source", "replay", str(FIXTURES_DIR / "csc_steady.raw.jsonl"), "--noise"], "nur mit --source sim"),
    ],
    ids=["no-file", "missing-file", "speed-zero", "speed-nan", "speed-with-sim", "wait-with-sim", "file-with-sim", "noise-with-replay"],
)
def test_replay_command_line_errors(tmp_path, args, hint):
    result = run_bridge(args, cwd=tmp_path)
    assert result.returncode == 2, result
    assert hint in result.stderr, result.stderr
    assert "Traceback" not in result.stderr
