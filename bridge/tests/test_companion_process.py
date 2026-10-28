"""Prozess des Begleiters (Spec #76, #79): fehlende Pakete des Extras machen Toni heiser statt den Prozess zu beenden,
Parent-Wächter über `VSPIN_COMPANION_PARENT_PID` – ohne Mikrofon, Modell, Lautsprecher und Netz."""

import asyncio
import os
import subprocess
import sys

import pytest
from bridge_harness import PORT, START_TIMEOUT_S, bridge_env, receive_json
from companion_harness import next_status
from vspin_companion import cli
from vspin_companion.cli import AdapterMissing, Unavailable, build_ears, build_mouth
from vspin_companion.clock import SystemClock
from vspin_companion.config import DATA_DIR_ENV, CompanionConfig
from vspin_companion.parent import PARENT_PID_ENV, parent_pid, process_alive, watch_parent


@pytest.fixture
def without_audio_packages(monkeypatch):
    """`None` in `sys.modules` lässt den Import scheitern – auch mit installiertem Extra `companion`."""
    for name in ("sounddevice", "av", "faster_whisper"):
        monkeypatch.setitem(sys.modules, name, None)


def test_without_the_packages_ears_and_mouth_are_placeholders_that_fail_on_use(without_audio_packages, tmp_path):
    ears = build_ears(SystemClock(), lambda text: None)
    mouth = build_mouth(CompanionConfig(), tmp_path, lambda text: None)
    assert isinstance(ears, Unavailable) and isinstance(mouth, Unavailable)

    async def use():
        with pytest.raises(AdapterMissing, match="Ears: .*sounddevice"):
            await ears.start_listening()
        with pytest.raises(AdapterMissing, match="Mouth: "):
            await mouth.speak("Hallo.")
        await mouth.stop()  # Aufräumen und Verbrauch gehen trotzdem
        mouth.set_volume(0.5)
        return mouth.take_usage(), await mouth.cost_of(["gen-1"])

    usage, costs = asyncio.run(use())
    assert (usage.chars, usage.requests, costs) == (0, 0, {})


def test_the_api_key_comes_from_the_environment_or_the_local_env_file_never_from_the_working_directory(
    monkeypatch, tmp_path
):
    """Der Schlüssel wird je Anfrage gelesen (ein nachgetragener wirkt ohne Neustart); ohne ihn geht keine Anfrage raus."""
    import vspin_companion.mouth as mouth_module

    captured = {}
    monkeypatch.setattr(mouth_module, "create_mouth", lambda client, log: captured.setdefault("client", client))
    monkeypatch.setattr(cli, "UrllibHttp", lambda: object())  # kein Netz im Test
    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text("OPENROUTER_API_KEY=aus-dem-arbeitsverzeichnis", encoding="utf-8")
    data_dir = tmp_path / "ablage"
    data_dir.mkdir()
    build_mouth(CompanionConfig(), data_dir, lambda text: None)
    client = captured["client"]
    with pytest.raises(Exception, match="OPENROUTER_API_KEY fehlt"):
        client._api_key()  # die .env im Arbeitsverzeichnis zählt nicht
    (data_dir / ".env").write_text('OPENROUTER_API_KEY="sk-or-aus-der-ablage"\n', encoding="utf-8")
    assert client._api_key() == "sk-or-aus-der-ablage"
    assert (client._model, client._voice) == ("elevenlabs/eleven-v4-turbo", "charlie")  # aus companion.json-Standard


def test_parent_pid_reads_only_a_positive_number():
    assert parent_pid({PARENT_PID_ENV: "4242"}) == 4242
    for value in ("", "abc", "0", "-3", "12.5"):
        assert parent_pid({PARENT_PID_ENV: value}) is None
    assert parent_pid({}) is None


def test_the_watcher_stops_the_companion_once_the_parent_is_gone():
    async def scenario():
        stop, log, alive = asyncio.Event(), [], [True, True, False]
        await asyncio.wait_for(
            watch_parent(4242, stop, log.append, alive=lambda pid: pid == 4242 and alive.pop(0), poll_s=0.01), 5
        )
        return stop.is_set(), log

    stopped, log = asyncio.run(scenario())
    assert stopped and "Elternprozess 4242 läuft nicht mehr" in log[0]


def test_hard_killed_game_stops_the_companion_cleanly(bridge_process, bus_client, tmp_path):
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    game_stand_in = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])  # das „Spiel“
    env = bridge_env()
    env["APPDATA"] = str(tmp_path / "appdata")  # nie das echte %APPDATA%
    env.pop(DATA_DIR_ENV, None)
    env[PARENT_PID_ENV] = str(game_stand_in.pid)
    env["PYTHONPATH"] = os.pathsep.join([str(tmp_path / "stub"), env["PYTHONPATH"]])
    stub = tmp_path / "stub"
    stub.mkdir()
    for name in ("sounddevice", "faster_whisper", "av"):  # nie Mikrofon oder Lautsprecher
        (stub / f"{name}.py").write_text("raise ImportError('Stub')\n", encoding="utf-8")
    log_path = tmp_path / "companion.log"
    with open(log_path, "w", encoding="utf-8") as log:
        proc = subprocess.Popen(
            [sys.executable, "-m", "vspin_companion", "--port", str(PORT), "--data-dir", str(tmp_path / "companion")],
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, env=env, cwd=tmp_path,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
        )
    try:
        assert next_status(game, timeout_s=START_TIMEOUT_S)["state"] == "idle"
        assert process_alive(game_stand_in.pid)
        assert proc.poll() is None  # das Spiel lebt: der Begleiter läuft weiter
        game_stand_in.kill()  # TerminateProcess unter Windows – keine Stoppdatei
        game_stand_in.wait(timeout=5)
        assert proc.wait(timeout=10) == 0
    finally:
        for process in (proc, game_stand_in):  # nur die eigenen Prozesse, über ihre PID
            if process.poll() is None:
                process.kill()
                process.wait()
    assert "Elternprozess" in log_path.read_text(encoding="utf-8") and "beendet" in log_path.read_text(encoding="utf-8")
