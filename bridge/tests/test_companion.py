"""Begleiter-Gerüst (Spec #76, #77): Sprechtaste → Ears → Brain → Mouth über einen echten Bus, nur mit Fakes;
jeder Fehler eines Ports macht Toni heiser, der Prozess läuft weiter. Kein Claude, OpenRouter, Mikrofon, GPU."""

import json
import os
import subprocess
import sys

import pytest
from bridge_harness import PORT, START_TIMEOUT_S, bridge_env, receive_json, wait_until
from companion_harness import next_status, ptt
from vspin_companion.claude_brain import API_KEY_ENV, OAUTH_TOKEN_ENV
from vspin_companion.config import DATA_DIR_ENV, CompanionConfig, ConfigError, default_data_dir, load_config
from vspin_companion.fakes import FakeBrain, FakeClock, FakeEars, FakeMouth
from vspin_companion.ports import ToolCall


def status(state: str) -> dict:
    return {"v": 0, "type": "companion_status", "state": state, "speaking": state == "speaking"}


def start_bus(bridge_process):
    return bridge_process("--source", "sim", "--sim-cadence", "80")


def connect(bus_client):
    client = bus_client()
    assert receive_json(client)["type"] == "status"
    return client


def states(client, count: int) -> list[str]:
    return [next_status(client)["state"] for _ in range(count)]


def ask(game) -> None:
    ptt(game, "down")
    ptt(game, "up")


def test_ptt_question_is_heard_answered_and_spoken_with_status_on_the_bus(
    bridge_process, bus_client, in_process_companion
):
    start_bus(bridge_process)
    game = connect(bus_client)
    brain = FakeBrain([["Noch 5 km", ToolCall("remember", {"text": "fragt gern nach km"}), ", easy peasy!"]])
    ears, mouth, clock = FakeEars(["Wie weit noch bis zum Bergdorf?"]), FakeMouth(), FakeClock()
    companion = in_process_companion(brain, ears, mouth, clock)

    assert next_status(game) == status("idle")  # nach dem Verbinden: aktueller Stand
    ptt(game, "down")
    assert next_status(game) == status("listening")
    assert ears.listening
    ptt(game, "up")
    assert next_status(game) == status("thinking")
    assert next_status(game) == status("speaking")  # `speaking: true` – das Spiel duckt den Ton
    assert next_status(game) == status("idle")

    assert brain.prompts == ["Frage: Wie weit noch bis zum Bergdorf?"]  # vor der Fahrt: ohne Fahrtzustand
    assert mouth.spoken == ["Noch 5 km, easy peasy!"]  # Werkzeugaufrufe werden nicht gesprochen
    assert "Werkzeug remember: gemerkt" in companion.log()  # seit #78 ausgeführt statt ignoriert
    assert (companion.data_dir / "memory.md").read_text(encoding="utf-8") == "- fragt gern nach km\n"


def test_status_goes_to_every_other_client_and_again_at_ride_start(bridge_process, bus_client, in_process_companion):
    start_bus(bridge_process)
    companion = in_process_companion(FakeBrain(), FakeEars(), FakeMouth(), FakeClock())
    wait_until(lambda: "Bus verbunden" in companion.log(), START_TIMEOUT_S, "Begleiter verbunden")
    hud = connect(bus_client)  # kommt nach Toni: kennt seinen Stand erst ab Fahrtbeginn
    other = connect(bus_client)
    hud.send(json.dumps({"v": 0, "type": "ride_event", "kind": "ride_start", "logbook": {"rides": 3}}))
    assert next_status(hud) == status("idle")
    assert next_status(other) == status("idle")


def test_nothing_heard_returns_to_idle_without_asking_the_brain(bridge_process, bus_client, in_process_companion):
    start_bus(bridge_process)
    game = connect(bus_client)
    brain, mouth = FakeBrain([["Was?"]]), FakeMouth()
    in_process_companion(brain, FakeEars(["  "]), mouth, FakeClock())
    assert next_status(game)["state"] == "idle"
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "idle"]
    assert brain.prompts == [] and mouth.spoken == []


def test_up_without_down_and_unknown_actions_are_ignored(bridge_process, bus_client, in_process_companion):
    start_bus(bridge_process)
    game = connect(bus_client)
    ears, mouth = FakeEars(["Hallo Toni"]), FakeMouth()
    in_process_companion(FakeBrain([["Servus!"]]), ears, mouth, FakeClock())
    assert next_status(game)["state"] == "idle"
    ptt(game, "up")
    ptt(game, "hold")
    game.send(json.dumps({"v": 1, "type": "companion_ptt", "action": "down"}))  # falsche Version: ignoriert
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    assert ears.sessions == 1 and mouth.spoken == ["Servus!"]


def _fail_ears_start(brain, ears, mouth, clock):
    ears.fail_start = OSError("Mikrofon nicht gefunden")


def _fail_ears_stop(brain, ears, mouth, clock):
    ears.transcripts.insert(0, RuntimeError("Erkennung abgestürzt"))


def _fail_brain_at_once(brain, ears, mouth, clock):
    brain.replies.insert(0, ConnectionError("kein Netz"))


def _fail_brain_mid_stream(brain, ears, mouth, clock):
    brain.replies.insert(0, ["Noch fünf", RuntimeError("Abo-Limit erreicht")])


def _fail_mouth(brain, ears, mouth, clock):
    mouth.fail_speak = ConnectionError("OpenRouter: 502")


def _fail_clock(brain, ears, mouth, clock):
    clock.fail_now = RuntimeError("Uhr kaputt")


PORT_FAILURES = [
    pytest.param(_fail_ears_start, "Ears", ["hoarse"], id="ears-start"),
    pytest.param(_fail_ears_stop, "Ears", ["listening", "thinking", "hoarse"], id="ears-stop"),
    pytest.param(_fail_brain_at_once, "Brain", ["listening", "thinking", "hoarse"], id="brain"),
    pytest.param(_fail_brain_mid_stream, "Brain", ["listening", "thinking", "hoarse"], id="brain-mid-stream"),
    pytest.param(_fail_mouth, "Mouth", ["listening", "thinking", "speaking", "hoarse"], id="mouth"),
    pytest.param(_fail_clock, "Clock", ["listening", "thinking", "hoarse"], id="clock"),
]


@pytest.mark.parametrize(("break_port", "port", "expected"), PORT_FAILURES)
def test_failing_port_makes_toni_hoarse_and_the_next_ptt_tries_again(
    bridge_process, bus_client, in_process_companion, break_port, port, expected
):
    start_bus(bridge_process)
    game = connect(bus_client)
    answer = ["Jetzt geht's wieder."]
    brain, ears, mouth, clock = FakeBrain([answer, answer]), FakeEars(["Bist du da?"] * 2), FakeMouth(), FakeClock()
    break_port(brain, ears, mouth, clock)
    companion = in_process_companion(brain, ears, mouth, clock)
    assert next_status(game)["state"] == "idle"

    ask(game)
    assert states(game, len(expected)) == expected
    assert f"Toni ist heiser – {port}:" in companion.log()
    assert companion.alive and companion.error is None

    # Heiser hält bis zur nächsten Sprechtaste; die versucht es neu – hier mit heilen Ports.
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    assert mouth.spoken == ["Jetzt geht's wieder."]
    assert companion.alive


def test_companion_reconnects_when_the_bus_comes_and_goes(bridge_process, bus_client, in_process_companion):
    ears, mouth = FakeEars(["eins", "zwei"]), FakeMouth()
    companion = in_process_companion(FakeBrain([["Erste."], ["Zweite."]]), ears, mouth, FakeClock())  # Bus fehlt noch

    wait_until(lambda: "nicht erreichbar" in companion.log(), START_TIMEOUT_S, "Begleiter wartet auf den Bus")

    for round_, answer in enumerate(["Erste.", "Zweite."], start=1):
        bridge = start_bus(bridge_process)
        wait_until(lambda: companion.log().count("Bus verbunden") == round_, START_TIMEOUT_S, "Begleiter verbunden")
        game = connect(bus_client)  # nach Toni: sein Stand kommt auf `ride_start`
        game.send(json.dumps({"v": 0, "type": "ride_event", "kind": "ride_start"}))
        assert next_status(game, timeout_s=10.0)["state"] == "idle"  # verbunden (wieder)
        ask(game)
        assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
        assert mouth.spoken[-1] == answer
        game.close()
        assert bridge.stop() == 0

    log = companion.log()
    assert "nicht erreichbar" in log and "Bus getrennt" in log
    assert log.count("Bus verbunden") == 2
    assert companion.alive


def _companion_process(tmp_path, *args: str, extra_env: dict[str, str] | None = None) -> subprocess.Popen:
    env = bridge_env()
    env["APPDATA"] = str(tmp_path / "appdata")  # Sicherheitsnetz: nie das echte %APPDATA%
    for name in (DATA_DIR_ENV, OAUTH_TOKEN_ENV, API_KEY_ENV):  # nie ein echtes Geheimnis des Nutzers
        env.pop(name, None)
    env.update(extra_env or {})
    with open(tmp_path / "companion.log", "w", encoding="utf-8") as log:  # der Prozess erbt seinen eigenen Griff
        return subprocess.Popen(
            [sys.executable, "-m", "vspin_companion", "--port", str(PORT), *args],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            cwd=tmp_path,
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
        )


def test_entry_point_without_adapters_goes_hoarse_and_keeps_running(bridge_process, bus_client, tmp_path):
    start_bus(bridge_process)
    game = connect(bus_client)
    data_dir, stop_file = tmp_path / "companion", tmp_path / "companion.stop"
    data_dir.mkdir()
    (data_dir / "companion.json").write_text('{"brain": "api_key", "kommt_spaeter": 1}', encoding="utf-8")
    proc = _companion_process(tmp_path, "--data-dir", str(data_dir), "--stop-file", str(stop_file))
    try:
        assert next_status(game, timeout_s=START_TIMEOUT_S) == status("idle")
        ptt(game, "down")  # bis #79 kein echtes Ohr: heiser
        assert next_status(game) == status("hoarse")
        game.send(json.dumps({"v": 0, "type": "ride_event", "kind": "ride_start"}))
        assert next_status(game) == status("hoarse")  # lebt weiter und meldet seinen Stand
        assert proc.poll() is None
        stop_file.touch()
        assert proc.wait(timeout=5) == 0
    finally:
        if proc.poll() is None:  # nur der eigene Prozess, über seine PID
            proc.kill()
            proc.wait()
    log = (tmp_path / "companion.log").read_text(encoding="utf-8")
    assert f"Ablage {data_dir} (Denken: api_key)" in log
    assert "Toni ist heiser – Ears: AdapterMissing" in log
    assert "Toni ist heiser – Brain: BrainUnavailable: ANTHROPIC_API_KEY fehlt" in log  # #78: echtes Brain
    # In die Ablage kommt nur die Vorgabe-Seele (#78); companion.json bleibt, wie sie war.
    assert sorted(p.name for p in data_dir.iterdir()) == ["companion.json", "soul.md"]
    assert (data_dir / "companion.json").read_text(encoding="utf-8") == '{"brain": "api_key", "kommt_spaeter": 1}'
    assert not (tmp_path / "appdata").exists()


def test_entry_point_with_oauth_goes_hoarse_without_token_and_never_uses_the_api_key(
    bridge_process, bus_client, tmp_path
):
    """ADR-0011: Standard `oauth`; fehlt das Token, wird Toni heiser – auch wenn ein API-Schlüssel da ist. Eine `.env`
    im Arbeitsverzeichnis zählt nie, die in der Ablage schon (dort fehlt dann nur noch das SDK)."""
    start_bus(bridge_process)
    game = connect(bus_client)
    data_dir, stop_file = tmp_path / "companion", tmp_path / "companion.stop"
    data_dir.mkdir()
    (tmp_path / ".env").write_text(f"{OAUTH_TOKEN_ENV}=aus-dem-arbeitsverzeichnis\n", encoding="utf-8")
    # Ein Stub vor dem echten Paket scheitert beim Import: Der Test gilt auch mit installiertem Extra `companion`
    # und startet nie die gebündelte CLI.
    stub_dir = tmp_path / "stub"
    stub_dir.mkdir()
    (stub_dir / "claude_agent_sdk.py").write_text('raise ImportError("Stub: SDK im Test gesperrt")\n', encoding="utf-8")
    pythonpath = os.pathsep.join([str(stub_dir), bridge_env()["PYTHONPATH"]])
    proc = _companion_process(
        tmp_path, "--data-dir", str(data_dir), "--stop-file", str(stop_file),
        extra_env={API_KEY_ENV: "sk-ant-test-kein-echter-schluessel", "PYTHONPATH": pythonpath},
    )
    log_file = tmp_path / "companion.log"
    try:
        assert next_status(game, timeout_s=START_TIMEOUT_S) == status("idle")
        game.send(json.dumps({"v": 0, "type": "ride_event", "kind": "ride_start"}))
        assert next_status(game) == status("idle")  # Antwort auf ride_start
        assert next_status(game) == status("hoarse")  # die Sitzung zur Fahrt scheitert an der Anmeldung
        assert f"Toni ist heiser – Brain: BrainUnavailable: {OAUTH_TOKEN_ENV} fehlt" in log_file.read_text("utf-8")

        (data_dir / ".env").write_text(f'{OAUTH_TOKEN_ENV}="test-token-aus-der-ablage"\n', encoding="utf-8")
        game.send(json.dumps({"v": 0, "type": "ride_event", "kind": "ride_start"}))
        assert next_status(game) == status("hoarse")
        wait_until(
            lambda: "claude-agent-sdk nicht installiert" in log_file.read_text("utf-8"), 5.0, "Token gefunden, SDK fehlt"
        )
        assert proc.poll() is None
        stop_file.touch()
        assert proc.wait(timeout=5) == 0
    finally:
        if proc.poll() is None:  # nur der eigene Prozess, über seine PID
            proc.kill()
            proc.wait()
    log = log_file.read_text(encoding="utf-8")
    assert "(Denken: oauth)" in log
    assert log.count(f"{OAUTH_TOKEN_ENV} fehlt") == 1  # die .env im Arbeitsverzeichnis wurde nie gelesen


def test_entry_point_stops_with_a_message_on_a_broken_config(tmp_path):
    data_dir = tmp_path / "companion"
    data_dir.mkdir()
    (data_dir / "companion.json").write_text("{kaputt", encoding="utf-8")
    proc = _companion_process(tmp_path, "--data-dir", str(data_dir))
    assert proc.wait(timeout=START_TIMEOUT_S) == 1
    assert "Konfiguration ungültig" in (tmp_path / "companion.log").read_text(encoding="utf-8")


def test_data_dir_defaults_to_appdata_and_can_be_redirected(tmp_path):
    appdata = tmp_path / "Roaming"
    assert default_data_dir({"APPDATA": str(appdata)}) == appdata / "VSpin" / "companion"
    assert default_data_dir({"APPDATA": str(appdata), DATA_DIR_ENV: str(tmp_path / "x")}) == tmp_path / "x"


def test_config_defaults_values_and_errors(tmp_path):
    assert load_config(tmp_path) == CompanionConfig()  # keine Datei: Standardwerte, nichts angelegt
    assert list(tmp_path.iterdir()) == []
    assert CompanionConfig().brain == "oauth"  # ADR-0011: kein API-Schlüssel ohne Einstellung

    config_file = tmp_path / "companion.json"
    config_file.write_text(
        json.dumps({"wake_min_minutes": 1, "wake_max_minutes": 30, "voice": "charlie", "neu": True}), encoding="utf-8"
    )
    assert load_config(tmp_path) == CompanionConfig(wake_min_minutes=1, wake_max_minutes=30)

    for broken in ('{"brain": "api"}', '{"wake_min_minutes": 0}', '{"wake_max_minutes": 31}',
                   '{"wake_min_minutes": 9}', '{"wake_min_minutes": true}', '{"voice": ""}', "[]", "{"):
        config_file.write_text(broken, encoding="utf-8")
        with pytest.raises(ConfigError):
            load_config(tmp_path)
