"""Ungeglättete Kadenz `cadence_raw` am Bus für die Kadenzmuster (#45, Nachtrag ADR-0004) – und die Messung, die
sie begründet (`tests/cadence_latency.py`). Die Bridge läuft als echter Prozess; geprüft werden Bus und Session-CSV.
"""

import csv
import time

from bridge_harness import PROFILES_DIR, receive_json, replay_to_end
from cadence_latency import ANTRITT, INNEHALTEN, detect_innehalten, measure_profile
from test_replay_csc import FAST, assert_bus_matches_csv, assert_close, fixture, raw_column, reference_cadence, relative

STOP_PROFILE = """
[[steps]]
duration_s = 3
cadence = 80

[[steps]]
duration_s = 3
cadence = 0

[[steps]]
duration_s = 1
cadence = 80
"""


def test_simulator_sends_unsmoothed_cadence_next_to_the_smoothed_one(bridge_process, bus_client, tmp_path):
    profile = tmp_path / "stop.toml"
    profile.write_text(STOP_PROFILE, encoding="utf-8")
    out = tmp_path / "sessions"
    bridge = bridge_process("--source", "sim", "--profile", str(profile), "--sessions-dir", str(out))
    client = bus_client()
    messages = [receive_json(client)]
    deadline = time.monotonic() + 20
    while not (messages[-1].get("state") == "disconnected" and len(messages) > 1):
        assert time.monotonic() < deadline, "Profil endet nicht"
        messages.append(receive_json(client, timeout_s=5))
    assert bridge.stop() == 0
    telemetry = [m for m in messages if m["type"] == "telemetry"]

    # In jeder Telemetrie, ungeglättet: genau die Werte des Profils, ohne Zwischenwerte.
    assert all("cadence_raw" in m for m in telemetry)
    raw = [m["cadence_raw"] for m in telemetry]
    stop = raw.index(0.0)
    restart = raw.index(80.0, stop)
    assert set(raw[:stop]) == {80.0} and set(raw[stop:restart]) == {0.0} and set(raw[restart:]) == {80.0}, raw

    # `cadence` bleibt der geglättete Wert (EMA 0,3 s): er fällt nach dem Stopp über mehrere Takte.
    smoothed = [m["cadence"] for m in telemetry]
    assert set(smoothed[:stop]) == {80.0}
    assert 25 < smoothed[stop] < 45, smoothed  # 80 · e^(−0,25/0,3) ≈ 35 nach einem Takt
    assert smoothed[stop:restart] == sorted(smoothed[stop:restart], reverse=True)
    assert smoothed[restart - 1] == 0.0
    [csv_path] = out.glob("*.csv")
    with open(csv_path, encoding="utf-8", newline="") as stream:
        rows = {int(r["t_ms"]): r for r in csv.DictReader(stream)}
    for message in telemetry:  # Bus und CSV: gleiche geglättete Kadenz, gleicher Rohwert der Quelle
        assert float(rows[message["t_ms"]]["cadence"]) == message["cadence"]
        assert float(rows[message["t_ms"]]["cadence_raw"]) == message["cadence_raw"]

    # Innehalten (< 10 rpm seit 2 s) kommt am ungeglätteten Wert ~0,5 s früher (Messung, ADR-0004 Nachtrag #45).
    t_ms = [m["t_ms"] for m in telemetry]
    [at_raw] = detect_innehalten(t_ms, raw)
    [at_smoothed] = detect_innehalten(t_ms, smoothed)
    assert 350 <= at_smoothed - at_raw <= 650, (at_raw, at_smoothed)


def test_csc_raw_cadence_holds_between_crank_events_and_follows_the_zero_rule(bridge_process, bus_client, tmp_path):
    name = "csc_stop.raw.jsonl"
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    times = relative(name)
    # 80 rpm bis 3 s, dann wiederholt der Sensor das letzte Event; 2,5 s danach ist die Kadenz 0. Ab 7,75 s wieder
    # Events – das erste umspannt die Pause (1 Umdrehung in 4,75 s).
    expected = [
        None if t < 750  # erst das zweite Kurbel-Event liefert eine Kadenz
        else 80.0 if t < 5500
        else 0.0 if t < 7750
        else round(60_000 / 4750, 1) if t < 8500
        else 80.0
        for t in times
    ]
    assert [m["cadence_raw"] for m in run.telemetry] == expected
    # `cadence` unverändert geglättet wie bisher.
    assert_close([m["cadence"] for m in run.telemetry], reference_cadence(times, raw_column(run)))
    assert_bus_matches_csv(run)


def test_discarded_outlier_never_reaches_the_raw_cadence(bridge_process, bus_client, tmp_path):
    name = "csc_outlier.raw.jsonl"
    run = replay_to_end(bridge_process, bus_client, fixture(name), tmp_path, *FAST)
    # Das Event mit 800 rpm wird verworfen, als wäre es nicht gekommen: der letzte angenommene Wert gilt weiter.
    assert [m["cadence_raw"] for m in run.telemetry] == [None, None, None] + [80.0] * (len(run.telemetry) - 3)
    assert 800.0 in raw_column(run)  # die CSV hält den Rohwert der Quelle weiter fest


def delays(interval_ms: int, profile: str) -> dict[tuple[str, int], tuple[int | None, int | None]]:
    """Erkennung ohne Rauschen: (ungeglättet, geglättet) in ms nach dem stetigen Profilverlauf, je Muster und Episode."""
    rows = measure_profile(PROFILES_DIR / "arcade" / profile, interval_ms, [None])
    return {(r.pattern, r.episode): (r.unsmoothed[0], r.smoothed[0]) for r in rows}


def test_measurement_smoothing_costs_a_quarter_to_half_a_second_at_250_ms():
    # Meldetakt 250 ms (Simulator): der EMA kostet je Antritt einen Takt, beim Innehalten zwei – und den knappen
    # Antritt (+26 rpm in 2 s) erkennt der geglättete Wert gar nicht.
    assert delays(250, "antritt.toml") == {(ANTRITT, 1): (80, 330), (ANTRITT, 2): (0, 250), (ANTRITT, 3): (70, None)}
    assert delays(250, "innehalten.toml") == {(INNEHALTEN, 1): (0, 500), (INNEHALTEN, 2): (0, 500)}


def test_measurement_smoothing_costs_nothing_at_one_second():
    # Meldet das Gerät nur 1×/s, holt der zeitbasierte EMA je Wert 96 % auf – dann bestimmt der Meldetakt allein.
    assert delays(1000, "antritt.toml") == {(ANTRITT, 1): (580, 580), (ANTRITT, 2): (250, 250), (ANTRITT, 3): (70, 70)}
    assert delays(1000, "innehalten.toml") == {(INNEHALTEN, 1): (0, 0), (INNEHALTEN, 2): (0, 0)}


def test_measurement_with_noise_misses_more_close_antritts_when_smoothed():
    rows = measure_profile(PROFILES_DIR / "arcade" / "antritt.toml", 250, range(1, 21))
    close = next(r for r in rows if r.episode == 3)
    assert close.smoothed.count(None) > close.unsmoothed.count(None)
    assert sum(r.false_unsmoothed + r.false_smoothed for r in rows) == 0  # keine Fehlauslösung im Rauschen
