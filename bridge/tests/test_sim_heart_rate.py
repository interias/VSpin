"""Puls des Simulators (Spec #64): folgt träge der Belastung, ist deterministisch und per Profil
steuerbar oder abschaltbar. Das Modell und die Quelle laufen im Testprozess (ohne Wanduhr-Abhängigkeit
des Ergebnisses); am Bus und in der CSV prüft die Bridge als Prozess."""

import asyncio
import csv
import random
import time

import pytest
from bridge_harness import PROFILES_DIR, receive_json
from sim_pulse import simulator_pulse
from vspin_bridge.sources.base import NotSupportedError
from vspin_bridge.sources.profile import Profile, ProfileError, Ride, load_profile
from vspin_bridge.sources.sim import Noise, SimulatorSource
from vspin_bridge.sources.sim_heart_rate import HeartRateModel

TICK_S = 0.25


def run_model(steps: list[tuple[float, int]], **kwargs) -> list[int]:
    """Folge von (Kadenz, Anzahl Takte) durch das Modell."""
    model = HeartRateModel(TICK_S)
    return [model.step(cadence, **kwargs) for cadence, count in steps for _ in range(count)]


# --- Modell -------------------------------------------------------------------------------


def test_pulse_starts_at_rest_and_follows_the_load_slowly():
    pulses = run_model([(0.0, 40), (100.0, 480)])  # 10 s Ruhe, 2 min bei 100 rpm (Ziel 150 bpm)
    assert pulses[:40] == [60] * 40  # Ruhepuls bleibt
    climbing = pulses[40:]
    assert climbing == sorted(climbing) and all(isinstance(p, int) for p in climbing)
    assert climbing[0] <= 61  # kein Sprung
    assert 115 <= climbing[119] <= 119  # nach 30 s 63 % des Weges (60 → 150)
    assert 145 <= climbing[-1] <= 150  # nach 2 min nah am Ziel, nicht darüber


def test_pulse_falls_back_in_the_recovery():
    pulses = run_model([(110.0, 480), (0.0, 480)])  # Belastung, dann Pause ohne Treten
    peak, after = pulses[479], pulses[480:]
    assert peak >= 150
    assert after == sorted(after, reverse=True)
    assert after[0] >= peak - 2  # fällt, springt nicht
    assert 60 <= after[-1] <= peak - 60  # nach 2 min deutlich unten, nicht unter Ruhepuls


def test_pulse_stays_plausible_and_integer():
    pulses = run_model([(200.0, 2000)], grade=0.2)  # absurde Belastung
    assert all(isinstance(p, int) and 50 <= p <= 190 for p in pulses)
    assert pulses[-1] == 190
    assert run_model([(0.0, 2000)]) == [60] * 2000


def test_uphill_raises_the_target_and_downhill_does_not_lower_it():
    flat, uphill, downhill = (run_model([(80.0, 400)], grade=g)[-1] for g in (0.0, 0.07, -0.05))
    assert uphill > flat + 10
    assert downhill == flat


def test_profile_target_replaces_the_formula():
    pulses = run_model([(80.0, 1200)], target=100.0)  # Formel ergäbe 132
    assert 95 <= pulses[-1] <= 100


def test_formula_matches_the_documented_values():
    assert run_model([(80.0, 8)]) == simulator_pulse(80.0, 8)
    assert HeartRateModel.target(80.0) == pytest.approx(132.0)
    assert HeartRateModel.target(130.0) == pytest.approx(177.0)
    assert HeartRateModel.target(80.0, 0.07) == pytest.approx(153.0)


# --- Quelle -------------------------------------------------------------------------------


@pytest.fixture
def fast_clock(monkeypatch):
    """Der Takt der Quelle läuft ohne Wartezeit: die Folge hängt nur von den Samples ab, nicht von der Wanduhr."""
    real_sleep = asyncio.sleep

    async def sleep(_delay):
        await real_sleep(0)

    monkeypatch.setattr(asyncio, "sleep", sleep)


async def collect(source: SimulatorSource, count: int) -> list:
    await source.connect()
    samples = []
    async for sample in source.samples():
        samples.append(sample)
        if len(samples) == count:
            break
    return samples


def pulses_of(source: SimulatorSource, count: int) -> list[int | None]:
    return [s.heart_rate for s in asyncio.run(collect(source, count))]


def test_every_sample_carries_the_pulse_and_it_depends_only_on_the_sequence(fast_clock):
    runs = [pulses_of(SimulatorSource(cadence=90), 600) for _ in range(2)]
    assert runs[0] == runs[1] == simulator_pulse(90.0, 600)  # Takt der Quelle, nicht die Wanduhr
    assert all(isinstance(p, int) for p in runs[0]) and runs[0][-1] > runs[0][0] + 50


def test_noise_with_the_same_seed_gives_the_same_pulse(fast_clock):
    def run(seed: int) -> list[int | None]:
        return pulses_of(SimulatorSource(cadence=90, noise=Noise(random.Random(seed))), 600)

    assert run(5) == run(5)
    assert run(5) != run(6)


def test_grade_raises_the_pulse_of_the_running_source(fast_clock):
    source = SimulatorSource(cadence=80)

    async def ride() -> tuple[list, list]:
        flat = await collect(source, 1500)
        with pytest.raises(NotSupportedError):  # der Simulator wertet die Steigung trotzdem aus
            await source.set_grade(0.07)
        return flat, await collect(source, 1500)

    flat, uphill = asyncio.run(ride())
    assert uphill[-1].heart_rate > flat[-1].heart_rate + 10


# --- Profil -------------------------------------------------------------------------------


def write(tmp_path, text: str):
    path = tmp_path / "p.toml"
    path.write_text(text, encoding="utf-8")
    return path


def test_profile_step_sets_and_ramps_the_target_pulse(tmp_path):
    profile = load_profile(
        write(
            tmp_path,
            "[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate = 150\n"
            "[[steps]]\nduration_s = 1\ncadence = 60\nheart_rate = 150\nheart_rate_to = 110\n"
            "[[steps]]\nduration_s = 1\ncadence = 60\n",
        )
    )
    assert profile.heart_rate is True
    assert [(s.heart_rate, s.heart_rate_to) for s in profile.steps] == [(150, None), (150, 110), (None, None)]
    pulses = pulses_of(SimulatorSource(interval_s=0.001, profile=profile), 3)
    assert all(isinstance(p, int) for p in pulses)


def test_profile_target_reaches_the_source(fast_clock):
    steady = Profile("t", (Ride(1, 80, heart_rate=100.0),), repeat=True)
    follows_target = pulses_of(SimulatorSource(interval_s=2.0, profile=steady), 30)  # grober Takt: schnelle Folge
    formula = pulses_of(SimulatorSource(cadence=80, interval_s=2.0), 30)
    assert follows_target[-1] < formula[-1]
    assert 60 < follows_target[-1] <= 100


def test_profile_can_switch_the_pulse_off(tmp_path):
    profile = load_profile(write(tmp_path, "heart_rate = false\n[[steps]]\nduration_s = 1\ncadence = 80\n"))
    assert profile.heart_rate is False
    assert pulses_of(SimulatorSource(interval_s=0.001, profile=profile), 4) == [None] * 4


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("heart_rate = 150\n[[steps]]\nduration_s = 1\ncadence = 80\n", "'heart_rate' im Profilkopf"),
        ("heart_rate = false\n[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate = 120\n", "verträgt sich nicht"),
        ("[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate_to = 120\n", "braucht 'heart_rate'"),
        ("[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate = 300\n", "zwischen 50 und 190"),
        ("[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate = 120\nheart_rate_to = 20\n", "zwischen 50 und 190"),
        ("[[steps]]\nduration_s = 1\ncadence = 80\nheart_rate = \"hoch\"\n", "endliche Zahl"),
        ("[[steps]]\nduration_s = 1\naction = \"pause\"\nheart_rate = 120\n", "unbekannte Schlüssel heart_rate"),
        ("[[steps]]\nduration_s = 1\ncadence = 80\npulse = 120\n", "unbekannte Schlüssel pulse"),
    ],
)
def test_invalid_pulse_keys_are_rejected(tmp_path, text, message):
    with pytest.raises(ProfileError, match=message):
        load_profile(write(tmp_path, text))


def test_example_profiles_load_and_the_pulse_example_sets_targets():
    for path in PROFILES_DIR.glob("*.toml"):
        load_profile(path)
    profile = load_profile(PROFILES_DIR / "intervall-puls.toml")
    assert profile.heart_rate is True and profile.repeat
    assert [s.heart_rate for s in profile.steps] == [100, 170, 110]


# --- Bus und CSV ----------------------------------------------------------------------------


def run_sim(bridge_process, bus_client, out, *args: str) -> tuple[list[dict], list[dict]]:
    """Bridge mit Profil bis zum Ende laufen lassen; liefert Telemetrie am Bus und CSV-Zeilen."""
    bridge = bridge_process("--source", "sim", "--sessions-dir", str(out), *args)
    client = bus_client()
    messages = [receive_json(client)]
    deadline = time.monotonic() + 20
    while not (messages[-1]["type"] == "status" and messages[-1]["state"] == "disconnected"):
        assert time.monotonic() < deadline, "Profil endet nicht"
        messages.append(receive_json(client, timeout_s=5))
    assert bridge.stop() == 0
    [path] = out.glob("*.csv")
    with open(path, encoding="utf-8", newline="") as stream:
        return [m for m in messages if m["type"] == "telemetry"], list(csv.DictReader(stream))


def test_csv_hr_bpm_is_the_simulator_pulse_and_pulse_off_leaves_it_empty(
    bridge_process, bus_client, tmp_path, isolated_bus
):
    on = write(tmp_path, "[[steps]]\nduration_s = 2\ncadence = 90\n")
    off = tmp_path / "off.toml"
    off.write_text("heart_rate = false\n[[steps]]\nduration_s = 2\ncadence = 90\n", encoding="utf-8")

    bus, rows = run_sim(bridge_process, bus_client, tmp_path / "on", "--profile", str(on))
    assert [int(r["hr_bpm"]) for r in rows] == simulator_pulse(90.0, 8)  # 8 Takte, vom Ruhepuls an
    assert [m["heart_rate"] for m in bus] == [int(r["hr_bpm"]) for r in rows[len(rows) - len(bus) :]]

    bus, rows = run_sim(bridge_process, bus_client, tmp_path / "off", "--profile", str(off))
    assert {r["hr_bpm"] for r in rows} == {""}
    assert [m["heart_rate"] for m in bus] == [None] * len(bus)


def test_pulse_does_not_depend_on_the_wall_clock_across_runs(bridge_process, bus_client, tmp_path, isolated_bus):
    profile = write(tmp_path, "[[steps]]\nduration_s = 2\ncadence = 100\n")
    runs = [
        [r["hr_bpm"] for r in run_sim(bridge_process, bus_client, tmp_path / f"run{i}", "--profile", str(profile))[1]]
        for i in (1, 2)
    ]
    assert runs[0] == runs[1] and len(runs[0]) == 8


def test_noise_with_the_same_seed_reproduces_the_pulse_in_the_csv(bridge_process, bus_client, tmp_path, isolated_bus):
    profile = write(tmp_path, "[[steps]]\nduration_s = 2\ncadence = 100\n")
    args = ("--profile", str(profile), "--noise", "--seed", "11")
    runs = [[r["hr_bpm"] for r in run_sim(bridge_process, bus_client, tmp_path / f"n{i}", *args)[1]] for i in (1, 2)]
    assert runs[0] == runs[1] and "" not in runs[0]
