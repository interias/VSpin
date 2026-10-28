"""Replay der Pulsquelle (`--hr-replay`, Spec #64) und Rad-Replay mit Pulszeilen in derselben Rohdatei.

Die Bridge läuft als echter Prozess; geprüft werden Bus, Session-Dateien und Terminal. Der Adapter
selbst läuft im Testprozess mit der `HeartRateSource` ohne Bus.
"""

import asyncio
import csv
import json
import time
from pathlib import Path

import pytest
from bridge_harness import FIXTURES_DIR, read_jsonl, receive_json, replay_to_end, run_bridge
from vspin_bridge.parsers import CSC_MEASUREMENT, HEART_RATE_MEASUREMENT
from vspin_bridge.sources.heart_rate import HeartRateDevice, HeartRateSource, HeartRateState, Role
from vspin_bridge.sources.heart_rate_replay import (
    REPLAY_ADDRESS,
    REPLAY_NAME,
    ReplayBleAdapter,
    load_heart_rate_replay,
)
from vspin_bridge.sources.replay import ReplayError, load_replay

DEVICE = {"address": REPLAY_ADDRESS, "name": REPLAY_NAME, "role": "strap"}
SET_DEVICES = json.dumps({"v": 0, "type": "set_heart_rate_devices", "devices": [DEVICE]})
BPM = [140, 142, 145, 147, 150, 152]  # Puls der Aufnahme, ein Wert alle 400 ms

NO_PULSE_PROFILE = "heart_rate = false\nrepeat = true\n[[steps]]\nduration_s = 5\ncadence = 80\n"


def hr_line(t_ms: int, bpm: int) -> str:
    return json.dumps({"t_ms": t_ms, "char": HEART_RATE_MEASUREMENT, "hex": bytes([0, bpm]).hex()})


def recording(path: Path, bpms=BPM, start_ms: int = 800_000, step_ms: int = 400) -> Path:
    """Reine Puls-Aufnahme; die Zeiten sind Bridge-Zeit einer früheren Session."""
    path.write_text("\n".join(hr_line(start_ms + i * step_ms, b) for i, b in enumerate(bpms)) + "\n", encoding="utf-8")
    return path


def mixed(path: Path) -> Path:
    """Rad-Aufnahme (`csc_steady`, Zeiten ab 1000 ms) mit Pulszeilen dazwischen, deren Zeiten ganz woanders liegen."""
    wheel = (FIXTURES_DIR / "csc_steady.raw.jsonl").read_text(encoding="utf-8").splitlines()
    lines = []
    for i, line in enumerate(wheel):
        lines.append(line)
        if i % 3 == 0 and i // 3 < len(BPM):
            lines.append(hr_line(900_000 + (i // 3) * 400, BPM[i // 3]))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


# --- Loader ---------------------------------------------------------------------------------


def test_wheel_replay_skips_pulse_lines_and_checks_order_only_over_the_rest(tmp_path):
    plain = load_replay(FIXTURES_DIR / "csc_steady.raw.jsonl")
    mix = load_replay(mixed(tmp_path / "mixed.raw.jsonl"))
    assert mix.notifications == plain.notifications
    assert mix.capabilities == plain.capabilities
    # Auch unter den übrigen Zeilen gilt "t_ms nicht fallend".
    bad = tmp_path / "bad.raw.jsonl"
    wheel = (FIXTURES_DIR / "csc_steady.raw.jsonl").read_text(encoding="utf-8").splitlines()
    bad.write_text("\n".join([wheel[1], hr_line(5, 70), wheel[0]]) + "\n", encoding="utf-8")
    with pytest.raises(ReplayError, match="Zeile 3: t_ms 1000 kleiner als davor"):
        load_replay(bad)


def test_wheel_replay_of_a_pulse_only_file_has_nothing_to_play(tmp_path):
    with pytest.raises(ReplayError, match="enthält keine Notifications"):
        load_replay(recording(tmp_path / "hr.raw.jsonl"))


def test_pulse_replay_reads_only_pulse_lines_and_checks_their_order_alone(tmp_path):
    notifications = load_heart_rate_replay(mixed(tmp_path / "mixed.raw.jsonl"))
    assert [n.data[1] for n in notifications] == BPM
    assert {n.char for n in notifications} == {HEART_RATE_MEASUREMENT}
    wheel = (FIXTURES_DIR / "csc_steady.raw.jsonl").read_text(encoding="utf-8").splitlines()
    unordered = tmp_path / "unordered.raw.jsonl"  # die Radzeilen fallen gegenüber den Pulszeilen: kein Fehler
    unordered.write_text("\n".join([hr_line(900_000, 70), wheel[0], hr_line(900_400, 71), wheel[0]]) + "\n")
    assert [n.t_ms for n in load_heart_rate_replay(unordered)] == [900_000, 900_400]
    falling = tmp_path / "falling.raw.jsonl"
    falling.write_text("\n".join([hr_line(900_400, 70), wheel[0], hr_line(900_000, 71)]) + "\n")
    with pytest.raises(ReplayError, match="Zeile 3: t_ms 900000 kleiner als davor"):
        load_heart_rate_replay(falling)


def test_pulse_replay_rejects_a_file_without_pulse_lines_and_broken_lines(tmp_path):
    with pytest.raises(ReplayError, match="keine Puls-Notifications"):
        load_heart_rate_replay(FIXTURES_DIR / "csc_steady.raw.jsonl")
    broken = tmp_path / "broken.raw.jsonl"
    broken.write_text(hr_line(1, 70) + "\nkein json\n", encoding="utf-8")
    with pytest.raises(ReplayError, match="Zeile 2: kein gültiges JSON"):
        load_heart_rate_replay(broken)
    with pytest.raises(ReplayError, match="nicht lesbar"):
        load_heart_rate_replay(tmp_path / "gibt-es-nicht.jsonl")


# --- Adapter hinter der HeartRateSource ---------------------------------------------------------


def test_adapter_plays_after_the_device_is_set_and_ends_like_a_removed_strap(tmp_path):
    notifications = load_heart_rate_replay(recording(tmp_path / "hr.raw.jsonl", BPM[:3], step_ms=100))

    async def scenario() -> tuple[list, list, int | None]:
        states, raw = [], []
        source = HeartRateSource(
            ReplayBleAdapter(notifications), lambda s: states.append(s), raw.append, retry_s=0.1, stale_s=5.0
        )
        await source.start()
        await asyncio.sleep(0.4)
        assert states == [] and source.status.state is HeartRateState.OFF  # nichts gemerkt: keine Verbindung
        await source.set_known_devices([HeartRateDevice(REPLAY_ADDRESS, REPLAY_NAME, Role.STRAP)])
        await asyncio.sleep(1.0)  # 3 Notifications in 0,2 s, danach reißt die Verbindung ab; keine Wiederholung
        last = source.heart_rate  # der letzte Wert bleibt bis zu stale_s lesbar
        await source.stop()
        return states, raw, last

    states, raw, last = asyncio.run(scenario())
    assert [s.state for s in states] == [
        HeartRateState.DISCONNECTED,
        HeartRateState.CONNECTED,
        HeartRateState.DISCONNECTED,
    ]
    assert states[1].device == HeartRateDevice(REPLAY_ADDRESS, REPLAY_NAME, Role.STRAP)
    assert [n.data[1] for n in raw] == BPM[:3] and last == BPM[2]


def test_adapter_connects_by_name_and_refuses_strangers(tmp_path):
    notifications = load_heart_rate_replay(recording(tmp_path / "hr.raw.jsonl", BPM[:2], step_ms=50))

    async def scenario() -> list:
        states = []
        source = HeartRateSource(ReplayBleAdapter(notifications), lambda s: states.append(s), retry_s=0.1)
        await source.start()
        await source.set_known_devices(
            [HeartRateDevice("00:00:00:00:00:00", "Anderer Gurt", Role.STRAP)]  # weder Adresse noch Name
        )
        await asyncio.sleep(0.8)
        assert [s.state for s in states] == [HeartRateState.DISCONNECTED]
        await source.set_known_devices([HeartRateDevice("11:22:33:44:55:66", REPLAY_NAME, Role.WATCH)])  # Name passt
        await asyncio.sleep(0.8)
        await source.stop()
        return states

    states = asyncio.run(scenario())
    assert [s.state for s in states][-2:] == [HeartRateState.CONNECTED, HeartRateState.DISCONNECTED]
    assert states[-2].device == HeartRateDevice(REPLAY_ADDRESS, REPLAY_NAME, Role.WATCH)


# --- Bridge mit --hr-replay -----------------------------------------------------------------


def start_with_replay(bridge_process, bus_client, tmp_path, file: Path, profile_text: str | None = NO_PULSE_PROFILE):
    out = tmp_path / "out"
    args = ["--hr-replay", str(file), "--sessions-dir", str(out)]
    if profile_text is None:
        args += ["--source", "sim", "--sim-cadence", "80"]
    else:
        profile = tmp_path / "profile.toml"
        profile.write_text(profile_text, encoding="utf-8")
        args += ["--source", "sim", "--profile", str(profile)]
    bridge = bridge_process(*args)
    return bridge, bus_client(), out


def read_until(client, stop, timeout_s: float = 20.0) -> list[dict]:
    messages = [receive_json(client)]
    deadline = time.monotonic() + timeout_s
    while not stop(messages[-1]):
        assert time.monotonic() < deadline, f"Ende nicht erreicht; zuletzt: {messages[-5:]}"
        messages.append(receive_json(client, timeout_s=5.0))
    return messages


def pulse_ended():
    """Bedingung für `read_until`: nach `connected` meldet die Pulsquelle wieder `disconnected` (Ende der Aufnahme)."""
    seen_connected = False

    def ended(message: dict) -> bool:
        nonlocal seen_connected
        seen_connected = seen_connected or pulse_state(message, "connected")
        return seen_connected and pulse_state(message, "disconnected")

    return ended


def pulse_state(message: dict, state: str) -> bool:
    return message["type"] == "status" and message["heart_rate"]["state"] == state


def distinct(values: list) -> list:
    return [v for i, v in enumerate(values) if i == 0 or values[i - 1] != v]


def test_hr_replay_is_off_until_devices_are_set_then_plays_and_disconnects_at_the_end(
    bridge_process, bus_client, tmp_path, isolated_bus
):
    bridge, client, out = start_with_replay(bridge_process, bus_client, tmp_path, recording(tmp_path / "hr.raw.jsonl"))

    # Vor dem ersten Befehl ist die Pulsquelle `off`, auch wenn eine Aufnahme bereitliegt.
    before = [receive_json(client) for _ in range(6)]
    assert before[0]["heart_rate"] == {"state": "off", "device": None}
    assert all(m["heart_rate"] is None for m in before if m["type"] == "telemetry")  # Rad ohne Puls
    assert not [m for m in before if m["type"] == "status" and m is not before[0]]

    client.send(SET_DEVICES)
    messages = before + read_until(client, pulse_ended())
    messages += [receive_json(client) for _ in range(3)]  # der letzte Wert bleibt nach dem Ende noch lesbar
    # off → disconnected (nach dem Befehl) → connected → disconnected (Ende der Aufnahme, wie abgenommener Gurt)
    blocks = [m["heart_rate"] for m in messages if m["type"] == "status"]
    assert [b["state"] for b in blocks] == ["off", "disconnected", "connected", "disconnected"]
    assert blocks[2]["device"] == DEVICE
    telemetry = [m for m in messages if m["type"] == "telemetry"]
    assert distinct([m["heart_rate"] for m in telemetry if m["heart_rate"] is not None]) == BPM
    acks = [m for m in messages if m["type"] == "ack"]
    assert acks == [{"v": 0, "type": "ack", "for": "set_heart_rate_devices", "ok": True, "reason": None}]

    assert bridge.stop() == 0
    log = bridge.log()
    assert "Puls: connected, VSpin Replay (strap)" in log
    # Session: Roh-Notifications des Pulses wie beim Rad, `hr_bpm` aus der Pulsquelle.
    [raw_path] = out.glob("*.raw.jsonl")
    raw = read_jsonl(raw_path)
    assert [bytes.fromhex(r["hex"])[1] for r in raw] == BPM and {r["char"] for r in raw} == {HEART_RATE_MEASUREMENT}
    gaps = [b["t_ms"] - a["t_ms"] for a, b in zip(raw, raw[1:])]
    assert all(300 <= g <= 600 for g in gaps), gaps  # im Takt der Aufnahme (400 ms)
    [csv_path] = out.glob("*.csv")
    with open(csv_path, encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert distinct([int(r["hr_bpm"]) for r in rows if r["hr_bpm"]]) == BPM


def test_replay_pulse_replaces_the_simulator_pulse_once_connected(bridge_process, bus_client, tmp_path, isolated_bus):
    # Der Simulator liefert selbst einen Puls (hier 60 → 70); ist das Replay-Gerät verbunden, gilt dessen Wert.
    _, client, _ = start_with_replay(
        bridge_process, bus_client, tmp_path, recording(tmp_path / "hr.raw.jsonl", [160, 161, 162, 163]), None
    )
    before = [receive_json(client) for _ in range(5)]
    assert all(60 <= m["heart_rate"] <= 70 for m in before if m["type"] == "telemetry")

    client.send(SET_DEVICES)
    after = read_until(client, lambda m: pulse_state(m, "connected"))
    after += read_until(client, lambda m: m["type"] == "telemetry" and m["heart_rate"] == 163)
    pulses = [m["heart_rate"] for m in after if m["type"] == "telemetry" and m["heart_rate"] is not None]
    assert 160 in pulses and pulses[-1] == 163
    assert all(p >= 160 for p in pulses[pulses.index(160) :])  # nie wieder zurück zum Simulator-Puls


def test_hr_replay_of_a_mixed_session_file_uses_only_the_pulse_lines(
    bridge_process, bus_client, tmp_path, isolated_bus
):
    _, client, _ = start_with_replay(bridge_process, bus_client, tmp_path, mixed(tmp_path / "mixed.raw.jsonl"))
    client.send(SET_DEVICES)
    messages = read_until(client, lambda m: pulse_state(m, "connected"))
    messages += read_until(client, lambda m: pulse_state(m, "disconnected"))
    messages += [receive_json(client) for _ in range(3)]  # der letzte Wert bleibt nach dem Ende noch lesbar
    assert distinct([m["heart_rate"] for m in messages if m["type"] == "telemetry" and m["heart_rate"]]) == BPM


def test_hr_replay_combines_with_the_wheel_replay_from_the_same_file(
    bridge_process, bus_client, tmp_path, isolated_bus
):
    file = mixed(tmp_path / "mixed.raw.jsonl")
    bridge_process("--source", "replay", str(file), "--wait-client", "--hr-replay", str(file), "--speed", "20")
    client = bus_client()
    status = receive_json(client)
    assert status["source"] == "replay" and status["heart_rate"] == {"state": "off", "device": None}
    rest = read_until(client, lambda m: m["type"] == "status" and m["state"] == "disconnected")  # Ende des Rad-Replays
    assert len([m for m in rest if m["type"] == "telemetry"]) == 17


def test_wheel_replay_of_a_session_file_with_pulse_lines(bridge_process, bus_client, tmp_path, isolated_bus):
    plain = replay_to_end(
        bridge_process, bus_client, FIXTURES_DIR / "csc_steady.raw.jsonl", tmp_path / "plain", "--speed", "20"
    )
    mix = mixed(tmp_path / "mixed.raw.jsonl")
    run = replay_to_end(bridge_process, bus_client, mix, tmp_path / "mix", "--speed", "20")
    assert run.returncode == 0 and run.states == plain.states == ["disconnected", "connected", "disconnected"]
    assert [m["cadence"] for m in run.telemetry] == [m["cadence"] for m in plain.telemetry]
    assert len(run.telemetry) == 17  # die Pulszeilen ergeben keine Telemetrie
    assert {m["heart_rate"] for m in run.telemetry} == {None}
    assert "0x2a37" not in run.log.lower() and "00002a37" not in run.log  # keine Meldung "wird nicht ausgewertet"
    # Die Session-Rohdatei enthält nur, was abgespielt wurde: die Radzeilen.
    assert run.raw_path.read_bytes() == (FIXTURES_DIR / "csc_steady.raw.jsonl").read_bytes()


# --- CLI-Fehler -------------------------------------------------------------------------------


def cli_error(tmp_path: Path, *args: str):
    result = run_bridge(["--sessions-dir", str(tmp_path / "out"), *args], cwd=tmp_path)
    assert result.returncode == 2, (result.stdout, result.stderr)
    assert not (tmp_path / "out").exists()  # kein Lauf, keine Session
    return result.stderr


def test_broken_hr_replay_file_is_a_cli_error(tmp_path):
    broken = tmp_path / "broken.raw.jsonl"
    broken.write_text(hr_line(1, 70) + "\n{kaputt\n", encoding="utf-8")
    error = cli_error(tmp_path, "--source", "sim", "--hr-replay", str(broken))
    assert "Zeile 2" in error and "kein gültiges JSON" in error


def test_hr_replay_file_without_pulse_lines_or_missing_is_a_cli_error(tmp_path):
    error = cli_error(tmp_path, "--source", "sim", "--hr-replay", str(FIXTURES_DIR / "csc_steady.raw.jsonl"))
    assert "keine Puls-Notifications" in error
    error = cli_error(tmp_path, "--source", "sim", "--hr-replay", str(tmp_path / "gibt-es-nicht.jsonl"))
    assert "nicht lesbar" in error
