"""Session-CSV (ADR-0008): jeder Bridge-Lauf schreibt `sessions/YYYY-MM-DD_HH-MM-SS.csv`.

Die Bridge läuft als echter Prozess; verglichen wird die CSV mit dem, was ein Test-Client
am Bus gesehen hat.
"""

import csv
import errno
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

from bridge_harness import BRIDGE_ROOT, FIXTURES_DIR, receive_json, run_bridge, wait_until
from vspin_bridge.cli import process_alive
from vspin_bridge.session import files as session_files
from vspin_bridge.sources.sim import SimulatorSource
from websockets.exceptions import ConnectionClosed

HEADER = "t_ms,cadence_raw,cadence,speed_kmh,power_w,power_estimated,hr_bpm,grade,status"
NAME_PATTERN = re.compile(r"^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})\.csv$")
NAME_FORMAT = "%Y-%m-%d_%H-%M-%S"


def start_sim(bridge_process, sessions_dir: Path, cadence: str = "80"):
    return bridge_process("--source", "sim", "--sim-cadence", cadence, "--sessions-dir", str(sessions_dir))


def session_file(sessions_dir: Path) -> Path:
    wait_until(lambda: any(sessions_dir.glob("*.csv")), 5.0, "Session-CSV angelegt")
    files = sorted(sessions_dir.glob("*.csv"))
    assert len(files) == 1, files
    return files[0]


def connect(bus_client):
    client = bus_client()
    assert receive_json(client)["type"] == "status"
    return client


def telemetry(client, count: int) -> list[dict]:
    return [m for m in (receive_json(client) for _ in range(count)) if m["type"] == "telemetry"]


def drain(client) -> list[dict]:
    """Alle Nachrichten bis zum Schließen der Verbindung durch die Bridge."""
    messages = []
    try:
        while True:
            messages.append(json.loads(client.recv(timeout=5)))
    except ConnectionClosed:
        return messages


def read_csv(path: Path) -> tuple[str, list[dict]]:
    text = path.read_text(encoding="utf-8")
    assert text.endswith("\n"), f"letzte Zeile unvollständig: {text[-80:]!r}"
    lines = text.split("\n")[:-1]
    rows = list(csv.reader(lines))
    assert all(len(row) == 9 for row in rows), [row for row in rows if len(row) != 9]
    return lines[0], [dict(zip(rows[0], row)) for row in rows[1:]]


def stop_with_ctrl_c(bridge) -> int:
    bridge.interrupt()
    bridge.proc.wait(timeout=5)
    return bridge.stop()


def test_simulator_run_writes_csv_matching_the_bus(bridge_process, bus_client, tmp_path):
    sessions = tmp_path / "out"
    started = datetime.now()
    bridge = start_sim(bridge_process, sessions)
    client = connect(bus_client)
    seen = telemetry(client, 10)
    assert bridge.stop() == 0  # SIGTERM, unter Windows Stoppdatei
    seen += [m for m in drain(client) if m["type"] == "telemetry"]

    path = session_file(sessions)
    name = NAME_PATTERN.match(path.name)
    assert name, path.name
    assert abs(datetime.strptime(name.group(1), NAME_FORMAT) - started) < timedelta(seconds=30)

    header, rows = read_csv(path)
    assert header == HEADER
    # Ab dem ersten Sample, das der Client sah, entspricht die CSV exakt dem Bus:
    # gleiche Anzahl, gleiche t_ms, gleiche Werte. Davor liegen nur Samples vor dem Connect.
    first = seen[0]["t_ms"]
    tail = [r for r in rows if int(r["t_ms"]) >= first]
    assert [int(r["t_ms"]) for r in tail] == [m["t_ms"] for m in seen]
    assert len(rows) - len(tail) <= 8  # Client hing praktisch ab Start am Bus
    for row, message in zip(tail, seen):
        assert float(row["cadence"]) == message["cadence"] == 80
        # Konstante Kadenz: Rohwert und geglätteter Wert (EMA, ADR-0004) sind gleich.
        assert float(row["cadence_raw"]) == 80
    for row in rows:
        assert row["speed_kmh"] == row["power_w"] == row["power_estimated"] == row["hr_bpm"] == ""
        assert row["grade"] == ""  # kein set_grade in diesem Lauf
        assert row["status"] == "connected"
    # Rohdaten-Datei derselben Session: der Simulator hat keine rohen Notifications → leer.
    raw = path.with_name(path.stem + ".raw.jsonl")
    assert raw.exists() and raw.read_bytes() == b""


def test_grade_is_logged_after_set_grade(bridge_process, bus_client, tmp_path):
    bridge = start_sim(bridge_process, tmp_path)
    client = connect(bus_client)
    before = telemetry(client, 4)

    def set_grade(grade) -> list[dict]:
        """Sendet set_grade; liefert die Telemetrie, die nach dem ack kam."""
        client.send(json.dumps({"v": 0, "type": "set_grade", "grade": grade}))
        while receive_json(client)["type"] != "ack":
            pass
        return telemetry(client, 4)

    uphill = set_grade(0.07)
    downhill = set_grade(-0.02)
    assert stop_with_ctrl_c(bridge) == 0

    _, rows = read_csv(session_file(tmp_path))
    by_t = {int(r["t_ms"]): r for r in rows}
    assert {by_t[m["t_ms"]]["grade"] for m in before} == {""}
    assert {float(by_t[m["t_ms"]]["grade"]) for m in uphill} == {0.07}
    assert {float(by_t[m["t_ms"]]["grade"]) for m in downhill} == {-0.02}
    assert rows[-1]["grade"] == "-0.02"  # zuletzt gemeldete Steigung bleibt stehen
    # Die geloggte Kadenz ist die am Bus (bergauf vom Simulator gesenkt).
    for message in uphill:
        assert float(by_t[message["t_ms"]]["cadence"]) == message["cadence"]


def test_ctrl_c_leaves_complete_csv(bridge_process, bus_client, tmp_path):
    bridge = start_sim(bridge_process, tmp_path)
    client = connect(bus_client)
    telemetry(client, 6)
    assert stop_with_ctrl_c(bridge) == 0
    seen = [m for m in drain(client) if m["type"] == "telemetry"]

    header, rows = read_csv(session_file(tmp_path))  # endet mit \n, jede Zeile 9 Felder
    assert header == HEADER
    assert len(rows) >= 6
    assert all(r["t_ms"].isdigit() and float(r["cadence"]) == 80 for r in rows)
    if seen:  # was nach dem Signal noch am Bus kam, steht auch in der CSV
        assert int(rows[-1]["t_ms"]) == seen[-1]["t_ms"]


def test_stop_file_leaves_complete_session(bridge_process, bus_client, tmp_path):
    """Stoppweg des Spiels (#25, unter Windows auch des Harness): Stoppdatei mitten im Replay."""
    fixture = FIXTURES_DIR / "csc_stop.raw.jsonl"
    bridge = bridge_process("--source", "replay", str(fixture), "--wait-client", "--sessions-dir", str(tmp_path))
    client = connect(bus_client)
    seen = telemetry(client, 6)
    bridge.request_stop()
    bridge.proc.wait(timeout=5)
    assert bridge.stop() == 0
    seen += [m for m in drain(client) if m["type"] == "telemetry"]
    assert not bridge.stop_file.exists()  # die Bridge räumt die Stoppdatei weg

    path = session_file(tmp_path)
    header, rows = read_csv(path)  # endet mit \n, jede Zeile 9 Felder
    assert header == HEADER
    # Client hing ab Start am Bus (--wait-client): CSV und Bus enthalten genau dieselben Samples.
    assert [int(r["t_ms"]) for r in rows] == [m["t_ms"] for m in seen]
    # Rohdaten: ganze Zeilen, genau der Anfang der Aufnahme – abgebrochen vor ihrem Ende.
    raw = path.with_name(path.stem + ".raw.jsonl").read_bytes()
    recording = fixture.read_bytes()
    assert raw.endswith(b"\n") and recording.startswith(raw) and len(raw) < len(recording)
    assert len(raw.splitlines()) >= len(rows)
    assert "Traceback" not in bridge.log()


def _sleeper() -> subprocess.Popen:
    """Stellvertreter für das Spiel: ein Elternprozess, der nur wartet."""
    return subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])


def _gone_pid() -> int:
    """PID eines Prozesses, der schon beendet ist."""
    proc = subprocess.Popen([sys.executable, "-c", "pass"])
    proc.wait(timeout=10)
    assert not process_alive(proc.pid)
    return proc.pid


def test_process_alive_sees_running_and_ended_processes():
    sleeper = _sleeper()
    try:
        assert process_alive(sleeper.pid)
    finally:
        sleeper.kill()
        sleeper.wait(timeout=5)
    assert not process_alive(sleeper.pid)
    assert not process_alive(_gone_pid())


def test_hard_killed_parent_stops_bridge_cleanly(bridge_process, bus_client, tmp_path):
    """Wächter auf das Spiel (Nacharbeit #26): endet der Elternprozess hart – Absturz, „Stop“ im Editor –,
    beendet sich die Bridge selbst sauber, statt unsichtbar weiterzulaufen. Gegenprobe: ohne Ende des
    Elternprozesses läuft sie weiter."""
    parent = _sleeper()
    try:
        bridge = bridge_process(
            "--source", "sim", "--sim-cadence", "80", "--sessions-dir", str(tmp_path), "--parent-pid", str(parent.pid)
        )
        client = connect(bus_client)
        seen = telemetry(client, 4)
        time.sleep(1.5)  # drei Prüfungen des Wächters bei lebendem Elternprozess
        assert bridge.proc.poll() is None, "Elternprozess lebt: Bridge läuft weiter"
        parent.kill()  # TerminateProcess unter Windows – kein Aufräumen des Spiels
        parent.wait(timeout=5)
        bridge.proc.wait(timeout=5)
    finally:
        if parent.poll() is None:
            parent.kill()
    assert bridge.stop() == 0
    header, rows = read_csv(session_file(tmp_path))  # vollständig: ganze Zeilen bis zum Zeilenende
    assert header == HEADER
    assert {m["t_ms"] for m in seen} <= {int(r["t_ms"]) for r in rows}
    assert "läuft nicht mehr" in bridge.log()
    assert "Traceback" not in bridge.log()


def test_parent_pid_that_does_not_exist_stops_at_once(tmp_path):
    """Zeigt --parent-pid auf keinen Prozess, endet die Bridge sofort sauber und läuft nicht ewig."""
    started = time.monotonic()
    result = run_bridge(
        ["--source", "sim", "--sessions-dir", str(tmp_path), "--parent-pid", str(_gone_pid())], cwd=tmp_path, timeout_s=15
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert time.monotonic() - started < 10
    assert "läuft nicht mehr" in result.stdout
    _, rows = read_csv(session_file(tmp_path))
    assert rows == [] or all(len(r) == 9 for r in rows)


def test_hard_kill_leaves_only_whole_lines(bridge_process, bus_client, tmp_path):
    bridge = start_sim(bridge_process, tmp_path)
    client = connect(bus_client)
    seen = telemetry(client, 6)
    bridge.proc.kill()  # kein Aufräumen möglich – nur zeilenweises Flushen hilft
    bridge.proc.wait(timeout=5)
    bridge.stop()

    _, rows = read_csv(session_file(tmp_path))
    assert {m["t_ms"] for m in seen} <= {int(r["t_ms"]) for r in rows}


def test_default_location_is_sessions_in_working_directory(bridge_process, bus_client, tmp_path):
    bridge = bridge_process("--source", "sim", "--sim-cadence", "80")  # Arbeitsverzeichnis: tmp_path
    telemetry(connect(bus_client), 2)
    assert bridge.stop() == 0
    assert NAME_PATTERN.match(session_file(tmp_path / "sessions").name)


def test_session_started_in_an_occupied_second_does_not_overwrite(bridge_process, bus_client, tmp_path):
    # Alle Namen der nächsten Sekunden belegen, als hätte gerade eine andere Session begonnen.
    now = datetime.now()
    occupied = {}
    for offset in range(-1, 20):
        path = tmp_path / ((now + timedelta(seconds=offset)).strftime(NAME_FORMAT) + ".csv")
        path.write_text(f"fremd {offset}\n", encoding="utf-8")
        occupied[path] = path.read_text(encoding="utf-8")

    bridge = start_sim(bridge_process, tmp_path)
    telemetry(connect(bus_client), 2)
    assert bridge.stop() == 0

    for path, content in occupied.items():
        assert path.read_text(encoding="utf-8") == content
    new = sorted(set(tmp_path.glob("*.csv")) - set(occupied))
    assert len(new) == 1, new
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_2\.csv", new[0].name)
    assert read_csv(new[0])[0] == HEADER


def test_occupied_raw_file_name_moves_the_whole_session(bridge_process, bus_client, tmp_path):
    # Nur die Rohdaten-Namen sind belegt: CSV und Rohdaten bekommen trotzdem denselben neuen Namen.
    now = datetime.now()
    occupied = []
    for offset in range(-1, 20):
        path = tmp_path / ((now + timedelta(seconds=offset)).strftime(NAME_FORMAT) + ".raw.jsonl")
        path.write_text("fremd\n", encoding="utf-8")
        occupied.append(path)

    bridge = start_sim(bridge_process, tmp_path)
    telemetry(connect(bus_client), 2)
    assert bridge.stop() == 0

    assert all(p.read_text(encoding="utf-8") == "fremd\n" for p in occupied)
    [csv_path] = tmp_path.glob("*.csv")
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_2\.csv", csv_path.name)
    assert csv_path.with_name(csv_path.stem + ".raw.jsonl").read_bytes() == b""


def test_sessions_directory_is_git_ignored():
    repo = BRIDGE_ROOT.parent

    def ignored(path: str) -> bool:
        result = subprocess.run(["git", "-C", str(repo), "check-ignore", "-q", path], check=False)
        assert result.returncode in (0, 1), result
        return result.returncode == 0

    assert ignored("sessions/2026-10-06_12-00-00.csv")
    assert ignored("bridge/sessions/2026-10-06_12-00-00.csv")
    assert not ignored("bridge/src/vspin_bridge/session/csv_log.py")  # Gegenprobe: greift nicht überall


class DiskFullAfter:
    """Datei-Stream, der nach `lines` Zeilen mit „Platte voll“ scheitert (wie ein volles Laufwerk)."""

    def __init__(self, stream, lines: int) -> None:
        self._stream = stream
        self._lines = lines

    def write(self, text: str) -> int:
        if self._lines <= 0:
            raise OSError(errno.ENOSPC, "No space left on device")
        self._lines -= text.count("\n")
        return self._stream.write(text)

    def flush(self) -> None:
        self._stream.flush()

    def close(self) -> None:
        self._stream.close()

    @property
    def closed(self) -> bool:
        return self._stream.closed


def test_write_error_stops_session_logging_but_bridge_keeps_running(
    in_process_bridge, bus_client, tmp_path, monkeypatch
):
    real_open = open

    def open_with_full_disk(path, *args, **kwargs):
        stream = real_open(path, *args, **kwargs)
        return DiskFullAfter(stream, lines=5) if str(path).endswith(".csv") else stream

    monkeypatch.setattr(session_files, "open", open_with_full_disk, raising=False)
    out = tmp_path / "out"
    bridge = in_process_bridge(SimulatorSource(cadence=80), out)
    client = connect(bus_client)
    # Nach Kopfzeile + 4 Samples ist die Platte voll – die Telemetrie läuft trotzdem weiter …
    assert len(telemetry(client, 16)) == 16
    assert receive_json(connect(bus_client))["type"] == "telemetry"  # … und neue Clients kommen an.

    assert bridge.stop() is None  # kein Abbruch, kein Traceback
    log = bridge.log()
    assert log.count("Session-Logging beendet") == 1, log
    assert "No space left on device" in log and "Bridge läuft weiter" in log
    header, rows = read_csv(session_file(out))  # was vor dem Fehler stand, bleibt lesbar
    assert header == HEADER and len(rows) == 4
