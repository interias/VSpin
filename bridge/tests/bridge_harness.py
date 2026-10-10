"""Test-Harness für die Bridge (Spec #2, Testing Decisions).

Die Bridge läuft als echter Prozess (`python -m vspin_bridge ...`), Tests hängen
Test-Clients an den Bus und prüfen nur das dort beobachtbare Verhalten.
Spätere Pakete übernehmen `bridge_process` bzw. `BridgeProcess` für andere Quellen.
Nur wo eine Quelle oder das Dateisystem gezielt Fehler werfen muss, läuft die Bridge im
Testprozess (`InProcessBridge`) – geprüft wird auch dann nur am Bus und im Terminal.
"""

import asyncio
import contextlib
import csv
import io
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Iterator
from pathlib import Path

from websockets.sync.client import ClientConnection

BRIDGE_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = BRIDGE_ROOT / "src"
HOST = "127.0.0.1"

# Parallele Testläufe (#62): `VSPIN_PORT_BASE=n` gibt jedem Lauf (je Worktree) einen eigenen Bus-Port
# 8765 + n; ohne Variable (oder 0) bleibt es 8765. Das Spiel leitet daraus seine Testports ab
# (18765 + 100·n, `tests/support/isolation.gd`). Die Bereiche überschneiden sich nie; n ≤ 466 hält
# alle Ports ≤ 65535.
PORT_BASE_ENV = "VSPIN_PORT_BASE"
DEFAULT_PORT = 8765
MAX_PORT_BASE = 466


def port_base(env: dict[str, str] | None = None) -> int:
    """Wert n aus `VSPIN_PORT_BASE` (leer/fehlt = 0); ein ungültiger Wert bricht den Lauf ab, statt still
    auf 8765 zu fallen und einem parallelen Lauf in die Quere zu kommen."""
    raw = (os.environ if env is None else env).get(PORT_BASE_ENV, "").strip()
    if not raw:
        return 0
    try:
        base = int(raw)
    except ValueError:
        raise ValueError(f"{PORT_BASE_ENV}={raw!r}: erwartet eine ganze Zahl 0–{MAX_PORT_BASE}") from None
    if not 0 <= base <= MAX_PORT_BASE:
        raise ValueError(f"{PORT_BASE_ENV}={raw!r}: erwartet eine ganze Zahl 0–{MAX_PORT_BASE}")
    return base


PORT = DEFAULT_PORT + port_base()
BUS_URL = f"ws://{HOST}:{PORT}"

PROFILES_DIR = BRIDGE_ROOT / "profiles"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"

START_TIMEOUT_S = 10.0
STOP_TIMEOUT_S = 5.0

# Testläufe auf derselben Port-Basis dürfen nie gleichzeitig Bridges starten: Die Sperre gilt rechnerweit
# je Bus-Port über eine Datei im Temp-Ordner. Läufe mit anderer Basis (VSPIN_PORT_BASE) laufen gleichzeitig.
LOCK_WAIT_POLL_S = 0.2


def lock_path(port: int) -> Path:
    return Path(tempfile.gettempdir()) / f"vspin-bridge-tests-{port}.lock"


LOCK_PATH = lock_path(PORT)


def try_lock(lock_file) -> bool:
    """Sperrt `lock_file` exklusiv, ohne zu warten; False, wenn ein anderer Prozess die Sperre hält.

    Linux/macOS `fcntl.flock`, Windows `msvcrt.locking` (erstes Byte). Beide gibt das OS beim Prozessende
    von selbst frei – auch nach SIGKILL bzw. TerminateProcess bleibt keine verwaiste Sperre.
    """
    if sys.platform == "win32":
        import msvcrt

        lock_file.seek(0)
        try:
            msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            return False
        return True
    import fcntl

    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return False
    return True


def _unlock(lock_file) -> None:
    if sys.platform == "win32":
        import msvcrt

        lock_file.seek(0)
        msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
        return
    import fcntl

    fcntl.flock(lock_file, fcntl.LOCK_UN)


@contextlib.contextmanager
def port_lock(path: Path = LOCK_PATH) -> Iterator[None]:
    """Exklusive Sperre für alle Bridge-Tests eines Laufs auf dieser Port-Basis; andere Läufe derselben Basis
    warten."""
    with open(path, "a+") as lock_file:
        if not try_lock(lock_file):
            print(f"\nWarte auf {path} – ein anderer Bridge-Testlauf belegt Port {PORT} …", file=sys.__stderr__)
            while not try_lock(lock_file):
                time.sleep(LOCK_WAIT_POLL_S)
        try:
            yield
        finally:
            _unlock(lock_file)


def port_open(host: str = HOST, port: int = PORT) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            return True
    except OSError:
        return False


def wait_until(predicate, timeout_s: float, what: str) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise TimeoutError(f"Zeitüberschreitung: {what}")


def bridge_env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(SRC_DIR), env.get("PYTHONPATH")]))
    env["PYTHONUNBUFFERED"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"  # Ausgabe in UTF-8, wie der Harness sie liest (Windows: sonst cp1252)
    return env


def run_bridge(args: list[str], cwd: Path, timeout_s: float = START_TIMEOUT_S) -> subprocess.CompletedProcess:
    """Für Läufe, die von selbst enden (Fehler beim Start): Exit-Code und Ausgabe."""
    wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} wird frei")
    result = subprocess.run(
        [sys.executable, "-m", "vspin_bridge", *args, "--port", str(PORT)],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        encoding="utf-8",
        env=bridge_env(),
        cwd=cwd,
        timeout=timeout_s,
        check=False,
    )
    wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} nach Ende frei")
    return result


class BridgeProcess:
    """Startet die Bridge als Subprozess, wartet auf den Bus und beendet sie sauber.

    Beenden wie im Betrieb: Linux/macOS mit SIGTERM; Windows über die Stoppdatei (`--stop-file`), wie das
    Spiel seine Bridge beendet – TerminateProcess ließe sich nicht abfangen. `interrupt()` ist Strg+C.
    """

    def __init__(self, args: list[str], log_path: Path) -> None:
        self.args = args
        self.log_path = log_path
        self.stop_file = log_path.with_suffix(".stop")
        self.proc: subprocess.Popen | None = None
        self.returncode: int | None = None

    def start(self) -> None:
        # Port muss frei sein, sonst würde der Test gegen eine fremde Bridge laufen.
        wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} wird frei")
        env = bridge_env()
        self._log = open(self.log_path, "w", encoding="utf-8")
        self.proc = subprocess.Popen(
            [sys.executable, "-m", "vspin_bridge", *self.args, "--stop-file", str(self.stop_file), "--port", str(PORT)],
            stdin=subprocess.DEVNULL,  # kein TTY → Tastatur aus, Bridge läuft trotzdem
            stdout=self._log,
            stderr=subprocess.STDOUT,
            env=env,
            # Arbeitsverzeichnis = Testverzeichnis: die Standard-Ablage `./sessions` landet dort,
            # nie im Repo.
            cwd=self.log_path.parent,
            # Windows: eigene Prozessgruppe, damit `interrupt()` nur diese Bridge trifft.
            creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if sys.platform == "win32" else 0,
        )

        def ready() -> bool:
            if self.proc.poll() is not None:
                raise RuntimeError(f"Bridge vorzeitig beendet ({self.proc.returncode}):\n{self.log()}")
            return port_open()

        try:
            wait_until(ready, START_TIMEOUT_S, f"Bus auf {BUS_URL}")
        except BaseException:
            self.stop()
            raise

    def stop(self) -> int | None:
        if self.proc is None:
            return self.returncode
        if self.proc.poll() is None:
            if sys.platform == "win32":
                self.request_stop()
            else:
                self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=STOP_TIMEOUT_S)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.returncode = self.proc.returncode
        self.proc = None
        self._log.close()
        wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} nach Stopp frei")
        return self.returncode

    def request_stop(self) -> None:
        """Stoppweg des Spiels: Stoppdatei anlegen – die Bridge endet sauber (alle Plattformen)."""
        self.stop_file.touch()

    def interrupt(self) -> None:
        """Strg+C im Kommandofenster: SIGINT. Windows kann Strg+C nicht gezielt an einen Prozess schicken –
        dort Strg+Untbr an die eigene Prozessgruppe; die Bridge behandelt beide gleich."""
        self.proc.send_signal(signal.CTRL_BREAK_EVENT if sys.platform == "win32" else signal.SIGINT)

    def log(self) -> str:
        return self.log_path.read_text(encoding="utf-8", errors="replace")


class InProcessBridge:
    """Bridge im Testprozess (eigener Thread mit Event-Loop) mit einer vom Test gebauten Quelle,
    z. B. einer, die bei `set_grade` einen Fehler wirft. Terminal-Ausgabe in `log()`; `stop()`
    liefert die Ausnahme, mit der `Bridge.run` endete (`None` = sauber beendet)."""

    def __init__(self, source, sessions_dir: Path) -> None:
        self.source = source
        self.sessions_dir = sessions_dir
        self.error: BaseException | None = None
        self._output = io.StringIO()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop: asyncio.Event | None = None

    def start(self) -> None:
        wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} wird frei")
        self._thread = threading.Thread(target=self._main, daemon=True)
        self._thread.start()

        def ready() -> bool:
            if not self._thread.is_alive():
                raise RuntimeError(f"Bridge vorzeitig beendet ({self.error!r}):\n{self.log()}")
            return port_open()

        wait_until(ready, START_TIMEOUT_S, f"Bus auf {BUS_URL}")

    def _main(self) -> None:
        from vspin_bridge.app import Bridge
        from vspin_bridge.console import Console

        async def main() -> None:
            self._loop, self._stop = asyncio.get_running_loop(), asyncio.Event()
            await Bridge(self.source, Console(self._output), self.sessions_dir, port=PORT).run(self._stop)

        try:
            asyncio.run(main())
        except BaseException as exc:  # Ergebnis für `stop()` – der Test prüft es
            self.error = exc

    def stop(self) -> BaseException | None:
        if self._thread is None:
            return self.error
        if self._thread.is_alive() and self._loop is not None:
            self._loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(STOP_TIMEOUT_S)
        assert not self._thread.is_alive(), "Bridge im Testprozess endet nicht"
        self._thread = None
        wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} nach Stopp frei")
        return self.error

    def log(self) -> str:
        return self._output.getvalue()


def receive_json(client: ClientConnection, timeout_s: float = 3.0) -> dict:
    raw = client.recv(timeout=timeout_s)
    assert isinstance(raw, str), "Bus-Nachrichten sind UTF-8-JSON-Textframes"
    return json.loads(raw)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


class ReplayRun:
    """Ergebnis eines kompletten Replays (siehe `replay_to_end`)."""

    def __init__(self, messages: list[dict], sessions_dir: Path, log: str, returncode: int | None) -> None:
        self.messages = messages
        self.log = log
        self.returncode = returncode
        [self.csv_path] = sessions_dir.glob("*.csv")
        [self.raw_path] = sessions_dir.glob("*.raw.jsonl")
        with open(self.csv_path, encoding="utf-8", newline="") as stream:
            self.rows = list(csv.DictReader(stream))

    @property
    def telemetry(self) -> list[dict]:
        return [m for m in self.messages if m["type"] == "telemetry"]

    @property
    def states(self) -> list[str]:
        return [m["state"] for m in self.messages if m["type"] == "status"]


def replay_to_end(bridge_process, bus_client, fixture: Path, out: Path, *args: str, timeout_s: float = 30.0) -> ReplayRun:
    """Bridge mit `--source replay fixture --wait-client` starten, als erster Client alles bis
    zum Ende der Aufnahme (`disconnected`) mitschneiden, Bridge stoppen."""
    bridge = bridge_process(
        "--source", "replay", str(fixture), "--wait-client", "--sessions-dir", str(out), *args
    )
    client = bus_client()
    messages = [receive_json(client)]
    assert messages[0]["type"] == "status" and messages[0]["state"] == "disconnected", messages
    deadline = time.monotonic() + timeout_s
    while not (messages[-1]["type"] == "status" and messages[-1]["state"] == "disconnected" and len(messages) > 1):
        assert time.monotonic() < deadline, "Replay endet nicht"
        messages.append(receive_json(client, timeout_s=5.0))
    returncode = bridge.stop()
    return ReplayRun(messages, out, bridge.log(), returncode)
