"""Simulator-Profile (`--profile`) und Rauschen (`--noise`, `--seed`) – die Bridge läuft als
echter Prozess; geprüft werden Bus, Session-CSV und Terminal-Ausgabe.

Ein Profil beginnt mit dem Bridge-Start, ein Client verpasst also die ersten Samples. Die
komplette Folge steht in der Session-CSV (eine Zeile je Sample am Bus).
"""

import csv
import itertools
import time
from pathlib import Path

import pytest
from bridge_harness import PROFILES_DIR, port_open, receive_json, run_bridge
from vspin_bridge.sources.profile import Ride, load_profile

RAMP_PROFILE = """
name = "Test-Rampe"

[[steps]]
duration_s = 1
cadence = 60
cadence_to = 90

[[steps]]
duration_s = 0.5
action = "pause"

[[steps]]
duration_s = 0.5
cadence = 100
"""
# 4 Takte Rampe (60 → 90), Pause, 2 Takte 100.
RAMP_CADENCES = [60.0, 70.0, 80.0, 90.0, 100.0, 100.0]

STEADY_PROFILE = """
[[steps]]
duration_s = 3
cadence = 80
"""


def write_profile(tmp_path: Path, text: str, name: str = "profile.toml") -> Path:
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return path


def play_to_end(bridge_process, bus_client, out: Path, *args: str) -> list[dict]:
    """Bridge mit Profil laufen lassen, bis die Quelle endet (`disconnected`); liefert die CSV-Zeilen."""
    bridge = bridge_process("--source", "sim", "--sessions-dir", str(out), *args)
    client = bus_client()
    deadline = time.monotonic() + 20
    while receive_json(client, timeout_s=5).get("state") != "disconnected":
        assert time.monotonic() < deadline, "Profil endet nicht"
    assert bridge.stop() == 0
    [path] = out.glob("*.csv")
    with open(path, encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def cadences(rows: list[dict]) -> list[float]:
    return [float(r["cadence"]) for r in rows]


def raw_cadences(rows: list[dict]) -> list[float]:
    return [float(r["cadence_raw"]) for r in rows]


def test_profile_plays_deterministically(bridge_process, bus_client, tmp_path, isolated_bus):
    profile = write_profile(tmp_path, RAMP_PROFILE)
    runs = [
        play_to_end(bridge_process, bus_client, tmp_path / f"run{i}", "--profile", str(profile)) for i in (1, 2)
    ]
    # Die Quelle liefert in jedem Lauf exakt dieselbe Folge (Rohwert in der CSV) …
    assert raw_cadences(runs[0]) == raw_cadences(runs[1]) == RAMP_CADENCES
    # … am Bus (Spalte `cadence`) geglättet (EMA 0,3 s): startet beim ersten Wert und läuft
    # dem Profil steigend hinterher.
    for run in runs:
        smoothed = cadences(run)
        assert smoothed[0] == RAMP_CADENCES[0], smoothed
        assert all(a < b for a, b in itertools.pairwise(smoothed)), smoothed
        assert all(s < r for s, r in zip(smoothed[1:], RAMP_CADENCES[1:])), smoothed
    assert all(r["status"] == "connected" for r in runs[0])
    # Die Pause ist eine Datenlücke von Takt + 0,5 s zwischen Rampe und letztem Schritt.
    t_ms = [int(r["t_ms"]) for r in runs[0]]
    assert t_ms[4] - t_ms[3] >= 700, t_ms


def test_reported_cadence_zero_reaches_zero_quickly(bridge_process, bus_client, tmp_path, isolated_bus):
    profile = write_profile(
        tmp_path, "[[steps]]\nduration_s = 1\ncadence = 60\n\n[[steps]]\nduration_s = 3\ncadence = 0\n"
    )
    rows = play_to_end(bridge_process, bus_client, tmp_path / "out", "--profile", str(profile))
    assert raw_cadences(rows) == [60.0] * 4 + [0.0] * 12
    # Die Quelle meldet ausdrücklich 0: am Bus fällt die Kadenz und ist nach spätestens
    # 1,5 s (6 Takten) genau 0 – statt nur asymptotisch (EMA allein: erst nach ~2,1 s 0,0).
    falling = cadences(rows)[4:]
    assert falling == sorted(falling, reverse=True), falling
    assert 0 < falling[0] < 60 and falling[5:] == [0.0] * 7, falling


def test_noise_with_seed_is_reproducible(bridge_process, bus_client, tmp_path, isolated_bus):
    profile = write_profile(tmp_path, STEADY_PROFILE)

    def run(name: str, *noise: str) -> list[dict]:
        return play_to_end(bridge_process, bus_client, tmp_path / name, "--profile", str(profile), *noise)

    first = run("a", "--noise", "--seed", "42")
    second = run("b", "--noise", "--seed", "42")
    other_seed = run("c", "--noise", "--seed", "7")

    # Rohwerte der Quelle (die geglätteten hängen zusätzlich vom echten Sample-Abstand ab).
    assert raw_cadences(first) == raw_cadences(second)  # gleicher Seed → gleiche Folge
    assert len(first) == 12  # Rauschen ändert Werte, nicht die Anzahl der Samples
    assert raw_cadences(other_seed) != raw_cadences(first)
    noisy = raw_cadences(first)
    assert len(set(noisy)) > 3, noisy
    assert all(60 <= c <= 100 for c in noisy), noisy
    # Die Glättung (EMA 0,3 s) dämpft das Rauschen am Bus.
    smoothed = cadences(first)
    assert max(smoothed) - min(smoothed) < max(noisy) - min(noisy), (smoothed, noisy)
    # Jitter: der Abstand der Samples schwankt deutlich um den Takt von 250 ms.
    t_ms = [int(r["t_ms"]) for r in first]
    gaps = [b - a for a, b in itertools.pairwise(t_ms)]
    assert max(gaps) - min(gaps) >= 20, gaps
    assert min(gaps) > 0


def test_noise_in_manual_mode(bridge_process, bus_client, isolated_bus):
    bridge_process("--source", "sim", "--sim-cadence", "80", "--noise")
    client = bus_client()
    values = [m["cadence"] for m in (receive_json(client) for _ in range(13)) if m["type"] == "telemetry"]
    assert len(set(values)) > 3, values
    assert all(abs(v - 80) < 20 for v in values), values


def test_noise_keeps_cadence_zero(bridge_process, bus_client):
    bridge_process("--source", "sim", "--sim-cadence", "0", "--noise")
    client = bus_client()
    values = [m["cadence"] for m in (receive_json(client) for _ in range(9)) if m["type"] == "telemetry"]
    assert values == [0] * 8  # wer nicht tritt, rauscht nicht


EXAMPLES = sorted(p.name for p in PROFILES_DIR.glob("*.toml"))


def test_example_profiles_exist():
    assert {"einrollen.toml", "sprint.toml", "stillstand.toml", "abbruch.toml"} <= set(EXAMPLES)


@pytest.mark.parametrize("name", EXAMPLES)
def test_example_profile_starts(bridge_process, bus_client, name):
    bridge = bridge_process("--source", "sim", "--profile", str(PROFILES_DIR / name))
    client = bus_client()
    assert receive_json(client) | {"t_ms": 0} == {
        "v": 0,
        "type": "status",
        "t_ms": 0,
        "state": "connected",
        "source": "sim",
        "capabilities": ["CADENCE"],
        "heart_rate": {"state": "off", "device": None},  # Pulsquelle bis zum ersten Befehl aus (#64)
    }
    telemetry = receive_json(client)
    assert telemetry["type"] == "telemetry" and 0 <= telemetry["cadence"] <= 200
    assert bridge.stop() == 0
    assert "Profil: " in bridge.log()


# Arcade-Szenarien (#46, #47, #48): dieselben Profile `zone_*`, `durchbruch_*` und `jagd_*` spielt
# games/island-ride/tests/test_arcade_ride.gd, `takt_*` und `sammeln_*` test_arcade_rhythm_collect_ride.gd über den
# Fake-Bus durch das Spiel und prüft dort das Ergebnis (geschafft, weich verfehlt, Pause bei Abbruch). Die
# Messprofile `antritt`/`innehalten` (#45) wertet tests/cadence_latency.py aus; im Spiel spielt sie
# test_abilities_ride.gd (#50) zusammen mit `gleichmass` und `rhythmus` nach: Muster erkannt, Fähigkeit ausgelöst.
# Die Boss-Szenarien `boss_*` (#51) spielt test_bosses_ride.gd: besiegt, entkommen, Pause beim Abbruch im Bosskampf.
# Die Elite-Szenarien `elite_*` (#52) spielt test_elite_groups_ride.gd: Champions abgehängt, Seltene mit Gefolge verfehlt.
ARCADE_DIR = PROFILES_DIR / "arcade"
ARCADE_PROFILES = sorted(p.name for p in ARCADE_DIR.glob("*.toml"))


def test_arcade_profiles_exist():
    assert {
        "zone_perfekt.toml",
        "zone_knapp_daneben.toml",
        "zone_abbruch.toml",
        "durchbruch_geschafft.toml",
        "durchbruch_zu_schwach.toml",
        "jagd_entkommen.toml",
        "jagd_eingeholt.toml",
        "takt_getroffen.toml",
        "takt_verfehlt.toml",
        "sammeln_viel.toml",
        "sammeln_wenig.toml",
        "antritt.toml",
        "innehalten.toml",
        "gleichmass.toml",
        "rhythmus.toml",
        "boss_abbruch.toml",
        "boss_tramuntana.toml",
        "boss_drac.toml",
        "boss_dimonis_besiegt.toml",
        "boss_dimonis_entkommen.toml",
        "elite_champion.toml",
        "elite_selten.toml",
    } <= set(ARCADE_PROFILES)


@pytest.mark.parametrize("name", ARCADE_PROFILES)
def test_arcade_profile_loads_and_starts(bridge_process, bus_client, name):
    profile = load_profile(ARCADE_DIR / name)
    assert profile.name.startswith("Arcade: ")
    assert not profile.repeat  # endet nach dem Szenario (Quelle beendet)
    first = next(step for step in profile.steps if isinstance(step, Ride))
    bridge = bridge_process("--source", "sim", "--profile", str(ARCADE_DIR / name))
    client = bus_client()
    assert receive_json(client)["state"] == "connected"
    telemetry = receive_json(client)
    assert telemetry["type"] == "telemetry" and telemetry["cadence"] == first.cadence
    assert bridge.stop() == 0
    assert f"Profil: {profile.name}" in bridge.log()


BAD_PROFILES = [
    pytest.param("[[steps]]\nduration_s = 1\ncadence = 300\n", "zwischen 0 und 200", id="cadence-too-high"),
    pytest.param("[[steps]]\nduration_s = 0\ncadence = 80\n", "> 0", id="zero-duration"),
    pytest.param("[[steps]]\nduration_s = 1\ncadence = 80\nspeed = 3\n", "unbekannte", id="unknown-key"),
    pytest.param("[[steps]]\nduration_s = 1\naction = \"explode\"\n", "action", id="unknown-action"),
    pytest.param("[[steps]]\nduration_s = 2\naction = \"pause\"\n", "cadence", id="no-ride-step"),
    pytest.param("repeat = 1\n[[steps]]\nduration_s = 1\ncadence = 80\n", "repeat", id="repeat-not-bool"),
    pytest.param("name = \"x\"\n", "steps", id="no-steps"),
    pytest.param("[[steps]\n", "TOML", id="broken-toml"),
]


@pytest.mark.parametrize(("text", "hint"), BAD_PROFILES)
def test_bad_profile_is_rejected_with_message(tmp_path, text, hint):
    profile = write_profile(tmp_path, text)
    result = run_bridge(["--source", "sim", "--profile", str(profile)], cwd=tmp_path)
    assert result.returncode == 2, result
    assert hint in result.stderr and str(profile) in result.stderr, result.stderr
    assert "Traceback" not in result.stderr
    assert not (tmp_path / "sessions").exists()  # Abbruch vor dem Start: keine Session


def test_missing_profile_and_conflicting_options(tmp_path):
    missing = run_bridge(["--source", "sim", "--profile", str(tmp_path / "fehlt.toml")], cwd=tmp_path)
    assert missing.returncode == 2 and "nicht lesbar" in missing.stderr, missing
    profile = write_profile(tmp_path, STEADY_PROFILE)
    both = run_bridge(["--source", "sim", "--profile", str(profile), "--sim-cadence", "80"], cwd=tmp_path)
    assert both.returncode == 2 and "schließen sich aus" in both.stderr, both
    seed_only = run_bridge(["--source", "sim", "--seed", "1"], cwd=tmp_path)
    assert seed_only.returncode == 2 and "--noise" in seed_only.stderr, seed_only


def test_unwritable_sessions_dir_gives_message_not_traceback(tmp_path):
    blocker = tmp_path / "keine-verzeichnis"
    blocker.write_text("eine Datei, kein Verzeichnis", encoding="utf-8")
    result = run_bridge(["--source", "sim", "--sessions-dir", str(blocker / "sessions")], cwd=tmp_path)
    output = result.stdout + result.stderr
    assert result.returncode == 1, output
    assert "Session-Datei konnte nicht angelegt werden" in output, output
    assert "Traceback" not in output
    assert not port_open()  # Bus wieder zu
