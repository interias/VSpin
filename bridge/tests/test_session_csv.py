"""Session-CSV (ADR-0008): jeder Bridge-Lauf schreibt `sessions/YYYY-MM-DD_HH-MM-SS.csv`.

Die Bridge läuft als echter Prozess; verglichen wird die CSV mit dem, was ein Test-Client
am Bus gesehen hat.
"""

import csv
import json
import re
import signal
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from bridge_harness import BRIDGE_ROOT, receive_json, wait_until
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


def stop_with(bridge, sig: signal.Signals) -> int:
    bridge.proc.send_signal(sig)
    bridge.proc.wait(timeout=5)
    return bridge.stop()


def test_simulator_run_writes_csv_matching_the_bus(bridge_process, bus_client, tmp_path):
    sessions = tmp_path / "out"
    started = datetime.now()
    bridge = start_sim(bridge_process, sessions)
    client = connect(bus_client)
    seen = telemetry(client, 10)
    assert bridge.stop() == 0  # SIGTERM
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
        assert row["cadence_raw"] == row["cadence"]  # ohne Glättung identisch
    for row in rows:
        assert row["speed_kmh"] == row["power_w"] == row["power_estimated"] == row["hr_bpm"] == ""
        assert row["grade"] == ""  # kein set_grade in diesem Lauf
        assert row["status"] == "connected"


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
    assert stop_with(bridge, signal.SIGINT) == 0

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
    assert stop_with(bridge, signal.SIGINT) == 0
    seen = [m for m in drain(client) if m["type"] == "telemetry"]

    header, rows = read_csv(session_file(tmp_path))  # endet mit \n, jede Zeile 9 Felder
    assert header == HEADER
    assert len(rows) >= 6
    assert all(r["t_ms"].isdigit() and float(r["cadence"]) == 80 for r in rows)
    if seen:  # was nach dem Signal noch am Bus kam, steht auch in der CSV
        assert int(rows[-1]["t_ms"]) == seen[-1]["t_ms"]


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


def test_sessions_directory_is_git_ignored():
    repo = BRIDGE_ROOT.parent

    def ignored(path: str) -> bool:
        result = subprocess.run(["git", "-C", str(repo), "check-ignore", "-q", path], check=False)
        assert result.returncode in (0, 1), result
        return result.returncode == 0

    assert ignored("sessions/2026-10-06_12-00-00.csv")
    assert ignored("bridge/sessions/2026-10-06_12-00-00.csv")
    assert not ignored("bridge/src/vspin_bridge/session/csv_log.py")  # Gegenprobe: greift nicht überall
