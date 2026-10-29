"""Fahrt speichern am Bus (Spec #84): `save_ride` → FIT-Datei in der Fahrtablage, Upload über einen gefälschten
`Uploader`, `ride_saved` nur an den Absender, Anmeldezustand in `status.garmin`.

Die Bridge läuft im Testprozess (`InProcessBridge`), weil nur so der Uploader gefälscht werden kann: Der echte
Prozess hätte den echten `GarminConnectUploader`. Kein Netz, kein echtes `~/.garminconnect` – die Fälschung kennt
gar kein Token-Verzeichnis, die Fahrtablage liegt in `tmp_path`. Geprüft wird am Bus, in der Fahrtablage und im
Terminal.
"""

import json
import sys
import threading
import time
from pathlib import Path

import pytest
from bridge_harness import HOST, InProcessBridge, receive_json
from fit_tool.data_message import DataMessage
from fit_tool.fit_file import FitFile
from heart_rate_harness import BusReader
from vspin_bridge import clock, ride_saver
from vspin_bridge.garmin import LoginState, UploadResult, UploadState
from vspin_bridge.sources.sim import SimulatorSource

UPLOADED = UploadResult(UploadState.UPLOADED, "Fahrt zu Garmin Connect hochgeladen.")
DUPLICATE = UploadResult(UploadState.DUPLICATE, "Die Fahrt ist schon in Garmin Connect.")
FAILED = UploadResult(
    UploadState.FAILED,
    "Upload zu Garmin Connect gescheitert (HTTP 503). Die FIT-Datei bleibt für den manuellen Import liegen.",
)
RIDE_SAVED_FIELDS = ["v", "type", "ride_id", "fit_path", "fit_error", "upload"]


class FakeUploader:
    """`Uploader` ohne Netz: liefert `result`, zählt jeden Upload; `gate` hält einen Upload an (langsames Netz)."""

    def __init__(self, result: UploadResult = UPLOADED, login: LoginState = LoginState.LOGGED_IN) -> None:
        self.result = result
        self.login = login
        self.uploads: list[Path] = []
        self.gate: threading.Event | None = None
        self.started = threading.Event()

    def login_state(self) -> LoginState:
        return self.login

    def upload(self, fit_path: Path) -> UploadResult:
        self.uploads.append(fit_path)
        assert fit_path.is_file()  # hochgeladen wird nur eine fertig geschriebene Datei
        self.started.set()
        if self.gate is not None:
            assert self.gate.wait(10), "Upload nie freigegeben"
        return self.result


@pytest.fixture
def ride_bridge(request, tmp_path):
    """Fabrik: `ride_bridge(uploader, sessions_dir=None, cadence=80)` startet eine Bridge mit Simulator im
    Testprozess."""
    started: list[InProcessBridge] = []

    def start(uploader: FakeUploader, sessions_dir: Path | None = None, cadence: int = 80) -> InProcessBridge:
        host = getattr(request.node, "bus_host", HOST)
        bridge = InProcessBridge(
            SimulatorSource(cadence=cadence), sessions_dir or tmp_path / "sessions", host, uploader=uploader
        )
        started.append(bridge)
        bridge.start()
        return bridge

    yield start
    for bridge in started:
        if bridge.uploader.gate is not None:
            bridge.uploader.gate.set()
        bridge.stop()


def ride(reader: BusReader, ride_id: str = "ride-1", upload: bool = True, seconds: float = 2.0) -> dict:
    """`save_ride` über eine gerade gefahrene Strecke: Start und Ende aus der Telemetrie (Bridge-Zeit), 8 m/s."""
    start = reader.next("telemetry")["t_ms"]
    end = reader.next("telemetry", lambda m: m["t_ms"] >= start + seconds * 1000)["t_ms"]
    distance = [[t, (t - start) * 0.008] for t in range(start, end, 1000)] + [[end, (end - start) * 0.008]]
    return {
        "v": 0,
        "type": "save_ride",
        "ride_id": ride_id,
        "start_t_ms": start,
        "end_t_ms": end,
        "lap_end_t_ms": [],
        "distance": distance,
        "upload": upload,
    }


def save(reader: BusReader, command: dict) -> dict:
    reader.client.send(json.dumps(command))
    return reader.next("ride_saved", timeout_s=10.0)


def fit_files(sessions_dir: Path) -> list[Path]:
    return sorted((sessions_dir / "rides").glob("*.fit"))


def decode(path: Path) -> list[DataMessage]:
    return [r.message for r in FitFile.from_file(str(path)).records if isinstance(r.message, DataMessage)]


def new_bridge_process(monkeypatch) -> None:
    """Wie ein neuer Bridge-Prozess: Die Bridge-Zeit beginnt wieder bei 0 (im Testprozess liefe sie sonst weiter)."""
    monkeypatch.setattr(clock, "_START_NS", time.monotonic_ns())


# --- Speichern und Upload --------------------------------------------------------------------------


def test_save_writes_the_fit_file_uploads_once_and_answers_only_the_sender(
    ride_bridge, bus_client, isolated_bus, tmp_path
):
    uploader = FakeUploader()
    bridge = ride_bridge(uploader)
    sender, other = BusReader(bus_client()), BusReader(bus_client())

    reply = save(sender, ride(sender))

    assert list(reply) == RIDE_SAVED_FIELDS
    assert reply["ride_id"] == "ride-1" and reply["fit_error"] is None
    assert reply["upload"] == {"state": "uploaded", "message": "Fahrt zu Garmin Connect hochgeladen."}
    [fit] = fit_files(tmp_path / "sessions")
    assert reply["fit_path"] == str(fit.absolute()) and Path(reply["fit_path"]).is_absolute()
    assert fit.name.endswith("_ride-1.fit")
    assert uploader.uploads == [fit]
    messages = decode(fit)
    records = [m for m in messages if m.name == "record"]
    assert len(records) >= 2 and all(r.cadence == 80 for r in records)
    assert [m.name for m in messages].count("session") == 1

    other.drain(0.6)
    assert "ride_saved" not in {m["type"] for m in other.seen}  # nie als Broadcast
    assert f"Fahrt ride-1 gespeichert: {fit.absolute()}" in bridge.log()


def test_failed_upload_keeps_the_file_with_a_clear_message_and_is_not_retried(
    ride_bridge, bus_client, isolated_bus, tmp_path
):
    uploader = FakeUploader(FAILED)
    ride_bridge(uploader)
    reader = BusReader(bus_client())
    command = ride(reader)

    reply = save(reader, command)

    assert reply["upload"] == {"state": "failed", "message": FAILED.message}
    assert "FIT-Datei bleibt für den manuellen Import liegen" in reply["upload"]["message"]
    assert Path(reply["fit_path"]).is_file()
    reader.drain(0.6)
    assert len(uploader.uploads) == 1  # genau ein Versuch, kein Wiederholen

    # Ein gescheiterter Upload kommt nicht auf die Merkliste: erneutes Speichern ist eine bewusste Handlung.
    uploader.result = UPLOADED
    assert save(reader, command)["upload"]["state"] == "uploaded"
    assert len(uploader.uploads) == 2 and len(fit_files(tmp_path / "sessions")) == 1


def test_saving_again_does_not_upload_again_and_writes_the_same_file(ride_bridge, bus_client, isolated_bus, tmp_path):
    uploader = FakeUploader()
    ride_bridge(uploader)
    reader = BusReader(bus_client())
    command = ride(reader)

    first = save(reader, command)
    [fit] = fit_files(tmp_path / "sessions")
    data = fit.read_bytes()
    second = save(reader, command)

    assert first["upload"]["state"] == "uploaded"
    assert second["upload"] == {
        "state": "already_uploaded",
        "message": "Die Fahrt ist schon in Garmin Connect – nicht erneut hochgeladen.",
    }
    assert second["fit_path"] == first["fit_path"]
    assert fit_files(tmp_path / "sessions") == [fit] and fit.read_bytes() == data  # dieselbe Datei, Byte für Byte
    assert uploader.uploads == [fit]


def test_upload_mark_survives_a_bridge_restart_and_is_what_prevents_the_second_upload(
    ride_bridge, bus_client, isolated_bus, tmp_path
):
    sessions = tmp_path / "sessions"
    uploader = FakeUploader()
    bridge = ride_bridge(uploader, sessions)
    reader = BusReader(bus_client())
    command = ride(reader)
    assert save(reader, command)["upload"]["state"] == "uploaded"
    bridge.stop()

    # Neuer Bridge-Lauf, dieselbe Fahrtablage: die Merkliste liegt in `rides/rides.json`.
    restarted = FakeUploader()
    bridge = ride_bridge(restarted, sessions)
    reader = BusReader(bus_client())
    assert save(reader, command)["upload"]["state"] == "already_uploaded"
    assert restarted.uploads == []
    bridge.stop()

    # Gegenprobe: ohne Merkliste würde dieselbe Fahrt noch einmal hochgeladen.
    (sessions / "rides" / "rides.json").unlink()
    without_list = FakeUploader()
    ride_bridge(without_list, sessions)
    reader = BusReader(bus_client())
    assert save(reader, command)["upload"]["state"] == "uploaded"
    assert len(without_list.uploads) == 1


def test_saving_again_in_a_later_bridge_run_keeps_the_file_and_uploads_it(
    ride_bridge, bus_client, isolated_bus, tmp_path, monkeypatch
):
    """Upload scheitert, Neustart der Bridge (etwa nach `pip install -e ".[garmin]"`), erneutes Speichern aus dem
    Spiel: Die neue Session-CSV ist länger als die Fahrt, hat unter denselben Bridge-Zeiten aber fremde Samples
    (hier 60 statt 80 rpm). Die Datei bleibt Byte für Byte, hochgeladen wird genau sie."""
    sessions = tmp_path / "sessions"
    new_bridge_process(monkeypatch)
    bridge = ride_bridge(FakeUploader(FAILED), sessions)
    reader = BusReader(bus_client())
    command = ride(reader)
    first = save(reader, command)
    assert first["upload"]["state"] == "failed"
    [fit] = fit_files(sessions)
    data = fit.read_bytes()
    bridge.stop()

    new_bridge_process(monkeypatch)
    restarted = FakeUploader()
    bridge = ride_bridge(restarted, sessions, cadence=60)
    reader = BusReader(bus_client())
    reader.next("telemetry", lambda m: m["t_ms"] > command["end_t_ms"] + 500, timeout_s=15.0)
    second = save(reader, command)

    assert second["fit_path"] == first["fit_path"] and second["fit_error"] is None
    assert second["upload"]["state"] == "uploaded"
    assert fit_files(sessions) == [fit] and fit.read_bytes() == data
    assert restarted.uploads == [fit]
    assert "FIT-Datei aus einem früheren Bridge-Lauf, nicht neu gebaut" in bridge.log()
    assert len(list(sessions.glob("*.csv"))) == 2


def test_a_later_bridge_run_shorter_than_the_ride_still_takes_the_existing_file(
    ride_bridge, bus_client, isolated_bus, tmp_path, monkeypatch
):
    """Gleich nach dem Neustart liegt das Ende der Fahrt nach der Bridge-Zeit: kein `invalid_ride`, weil die
    Fahrtablage die Fahrt kennt."""
    sessions = tmp_path / "sessions"
    new_bridge_process(monkeypatch)
    bridge = ride_bridge(FakeUploader(), sessions)
    reader = BusReader(bus_client())
    command = ride(reader, seconds=4.0, upload=False)
    first = save(reader, command)
    data = Path(first["fit_path"]).read_bytes()
    bridge.stop()

    new_bridge_process(monkeypatch)
    restarted = FakeUploader()
    ride_bridge(restarted, sessions, cadence=60)
    reader = BusReader(bus_client())
    assert reader.first["t_ms"] < command["end_t_ms"]
    command["upload"] = True
    second = save(reader, command)

    assert second["fit_path"] == first["fit_path"] and second["upload"]["state"] == "uploaded"
    assert Path(first["fit_path"]).read_bytes() == data and restarted.uploads == [Path(first["fit_path"])]


def test_a_later_bridge_run_without_the_file_says_so_and_does_not_rebuild_or_upload(
    ride_bridge, bus_client, isolated_bus, tmp_path, monkeypatch
):
    sessions = tmp_path / "sessions"
    new_bridge_process(monkeypatch)
    bridge = ride_bridge(FakeUploader(FAILED), sessions)
    reader = BusReader(bus_client())
    command = ride(reader)
    fit = Path(save(reader, command)["fit_path"])
    bridge.stop()
    fit.unlink()  # vom Nutzer gelöscht oder verschoben

    new_bridge_process(monkeypatch)
    restarted = FakeUploader()
    ride_bridge(restarted, sessions, cadence=60)
    reader = BusReader(bus_client())
    reader.next("telemetry", lambda m: m["t_ms"] > command["end_t_ms"] + 500, timeout_s=15.0)
    reply = save(reader, command)

    assert reply["fit_path"] is None and reply["upload"] is None
    assert reply["fit_error"] == ride_saver.missing_file(fit.name)
    assert "früheren Bridge-Lauf" in reply["fit_error"]
    assert fit_files(sessions) == [] and restarted.uploads == []


def test_two_clients_saving_the_same_ride_at_once_upload_it_once(ride_bridge, bus_client, isolated_bus):
    uploader = FakeUploader()
    uploader.gate = threading.Event()
    ride_bridge(uploader)
    first, second = BusReader(bus_client()), BusReader(bus_client())
    command = ride(first)

    first.client.send(json.dumps(command))
    assert uploader.started.wait(10)
    second.client.send(json.dumps(command))  # während der erste Upload noch hängt
    second.drain(0.3)
    uploader.gate.set()

    assert first.next("ride_saved", timeout_s=5.0)["upload"]["state"] == "uploaded"
    assert second.next("ride_saved", timeout_s=5.0)["upload"]["state"] == "already_uploaded"
    assert len(uploader.uploads) == 1


def test_duplicate_at_garmin_counts_as_success_and_goes_on_the_list(ride_bridge, bus_client, isolated_bus):
    uploader = FakeUploader(DUPLICATE)
    ride_bridge(uploader)
    reader = BusReader(bus_client())
    command = ride(reader)

    assert save(reader, command)["upload"] == {"state": "duplicate", "message": DUPLICATE.message}
    assert save(reader, command)["upload"]["state"] == "already_uploaded"
    assert len(uploader.uploads) == 1


def test_upload_false_writes_the_file_but_does_not_upload(ride_bridge, bus_client, isolated_bus, tmp_path):
    uploader = FakeUploader()
    ride_bridge(uploader)
    reader = BusReader(bus_client())

    reply = save(reader, ride(reader, upload=False))

    assert reply["upload"] == {
        "state": "skipped",
        "message": "Nicht hochgeladen – der Upload ist für diese Fahrt abgeschaltet.",
    }
    assert Path(reply["fit_path"]).is_file() and fit_files(tmp_path / "sessions") == [Path(reply["fit_path"])]
    assert uploader.uploads == []


def test_missing_fit_tool_gives_a_clear_message_without_file_and_the_bridge_runs_on(
    ride_bridge, bus_client, isolated_bus, tmp_path, monkeypatch
):
    # fit-tool ausblenden, als wäre das Extra nicht installiert (die Bridge läuft im selben Prozess).
    for name in [n for n in sys.modules if n == "fit_tool" or n.startswith("fit_tool.")]:
        monkeypatch.setitem(sys.modules, name, None)
    monkeypatch.setitem(sys.modules, "fit_tool", None)
    uploader = FakeUploader()
    ride_bridge(uploader)
    reader = BusReader(bus_client())

    reply = save(reader, ride(reader))

    assert reply["fit_path"] is None and reply["upload"] is None
    assert "fit-tool fehlt" in reply["fit_error"] and 'pip install -e ".[fit]"' in reply["fit_error"]
    assert fit_files(tmp_path / "sessions") == [] and uploader.uploads == []
    reader.next("telemetry")  # die Bridge läuft weiter
    assert reader.reply({"v": 0, "type": "set_grade", "grade": 0.02})["type"] == "ack"


def test_slow_upload_blocks_neither_telemetry_nor_the_bus(ride_bridge, bus_client, isolated_bus):
    uploader = FakeUploader()
    uploader.gate = threading.Event()
    ride_bridge(uploader)
    sender, other = BusReader(bus_client()), BusReader(bus_client())
    sender.client.send(json.dumps(ride(sender)))
    assert uploader.started.wait(10)

    # Während der Upload hängt: Telemetrie an alle, Antworten an den Absender selbst und an andere Clients.
    t_ms = [sender.next("telemetry")["t_ms"] for _ in range(4)]
    assert t_ms == sorted(t_ms) and t_ms[-1] - t_ms[0] >= 500
    assert other.next("telemetry")
    assert sender.reply({"v": 0, "type": "set_grade", "grade": 0.01})["type"] == "ack"
    assert other.reply({"v": 0, "type": "set_grade", "grade": 0.01})["type"] == "ack"
    assert "ride_saved" not in {m["type"] for m in sender.seen}

    uploader.gate.set()
    assert sender.next("ride_saved", timeout_s=5.0)["upload"]["state"] == "uploaded"
    assert len(uploader.uploads) == 1


# --- Ungültige Befehle -----------------------------------------------------------------------------


def valid() -> dict:
    return {
        "v": 0,
        "type": "save_ride",
        "ride_id": "ride-1",
        "start_t_ms": 0,
        "end_t_ms": 100,
        "lap_end_t_ms": [],
        "distance": [[0, 0.0], [100, 1.0]],
        "upload": False,
    }


INVALID_RIDES = [
    pytest.param({"ride_id": "../x"}, id="ride-id-path"),
    pytest.param({"ride_id": "a/b"}, id="ride-id-slash"),
    pytest.param({"ride_id": ""}, id="ride-id-empty"),
    pytest.param({"ride_id": "x" * 65}, id="ride-id-too-long"),
    pytest.param({"ride_id": 7}, id="ride-id-number"),
    pytest.param({"start_t_ms": None}, id="start-missing"),
    pytest.param({"start_t_ms": "0"}, id="start-string"),
    pytest.param({"start_t_ms": True}, id="start-bool"),
    pytest.param({"start_t_ms": 0.5}, id="start-fraction"),
    pytest.param({"start_t_ms": -1}, id="start-negative"),
    pytest.param({"end_t_ms": 0}, id="end-equals-start"),
    pytest.param({"end_t_ms": 10**12}, id="end-after-bridge-time"),
    pytest.param({"lap_end_t_ms": 50}, id="laps-not-a-list"),
    pytest.param({"lap_end_t_ms": ["50"]}, id="lap-string"),
    pytest.param({"distance": None}, id="distance-missing"),
    pytest.param({"distance": [[0, 0.0, 1]]}, id="distance-triple"),
    pytest.param({"distance": [[0, -1.0]]}, id="distance-negative"),
    pytest.param({"distance": [[0, 2.0], [100, 1.0]]}, id="distance-falls"),
    pytest.param({"distance": [[100, 0.0], [100, 1.0]]}, id="distance-time-not-rising"),
    pytest.param({"upload": None}, id="upload-missing"),
    pytest.param({"upload": "true"}, id="upload-string"),
]


@pytest.mark.parametrize("change", INVALID_RIDES)
def test_invalid_save_ride_gets_error_and_nothing_is_saved(ride_bridge, bus_client, isolated_bus, tmp_path, change):
    uploader = FakeUploader()
    ride_bridge(uploader)
    reader = BusReader(bus_client())
    command = valid() | change
    command = {k: v for k, v in command.items() if v is not None}

    error = reader.reply(command)

    assert error["type"] == "error" and error["reason"] == "invalid_ride", error
    assert isinstance(error["detail"], str) and error["detail"]
    assert not (tmp_path / "sessions" / "rides").exists() and uploader.uploads == []


def test_godot_style_float_times_and_missing_laps_are_accepted(ride_bridge, bus_client, isolated_bus):
    ride_bridge(FakeUploader())
    reader = BusReader(bus_client())
    command = ride(reader, upload=False)
    command["start_t_ms"], command["end_t_ms"] = float(command["start_t_ms"]), float(command["end_t_ms"])
    del command["lap_end_t_ms"]

    assert save(reader, command)["fit_error"] is None


# --- Anmeldezustand -------------------------------------------------------------------------------


def test_login_state_is_in_status_and_a_change_goes_out_exactly_once(
    ride_bridge, bus_client, isolated_bus, monkeypatch
):
    monkeypatch.setattr(ride_saver, "LOGIN_CHECK_S", 0.1)
    uploader = FakeUploader(login=LoginState.NOT_LOGGED_IN)
    ride_bridge(uploader)
    sender, other = BusReader(bus_client()), BusReader(bus_client())
    assert sender.first["garmin"] == other.first["garmin"] == {"login": "not_logged_in"}
    # als letzter Block, hinter dem Pulsblock und den Blöcken aus Spec #75
    assert list(sender.first)[-5:] == ["heart_rate", "trainer", "controller", "signal", "garmin"]

    uploader.login = LoginState.LOGGED_IN  # im Terminal angemeldet, während die Bridge läuft
    assert other.next("status")["garmin"] == {"login": "logged_in"}
    other.drain(0.6)
    assert [s["garmin"] for s in other.statuses()] == [{"login": "not_logged_in"}, {"login": "logged_in"}]
    assert BusReader(bus_client()).first["garmin"] == {"login": "logged_in"}


def test_login_state_is_checked_again_after_each_save(ride_bridge, bus_client, isolated_bus, monkeypatch):
    monkeypatch.setattr(ride_saver, "LOGIN_CHECK_S", 60.0)  # nur das Speichern prüft hier neu, nicht der Takt
    uploader = FakeUploader(UploadResult(UploadState.NOT_LOGGED_IN, "Nicht bei Garmin angemeldet"))
    ride_bridge(uploader)
    reader = BusReader(bus_client())
    assert reader.first["garmin"] == {"login": "logged_in"}
    command = ride(reader)

    uploader.login = LoginState.NOT_LOGGED_IN  # Token-Verzeichnis weg, die Bridge merkt es beim Speichern
    reader.client.send(json.dumps(command))
    reader.next("ride_saved", timeout_s=10.0)
    assert reader.next("status", timeout_s=1.0)["garmin"] == {"login": "not_logged_in"}


def test_bridge_process_never_sees_the_users_garmin_token(bridge_process, bus_client, isolated_bus):
    """Echter Prozess mit dem Standard-Uploader: Sein Heimatverzeichnis ist der Testordner (`bridge_harness`), also
    nie `logged_in` – `unavailable` ohne das Extra `garmin`, sonst `not_logged_in`."""
    bridge_process("--source", "sim", "--sim-cadence", "80")
    status = receive_json(bus_client())
    assert status["garmin"]["login"] in ("unavailable", "not_logged_in")
