"""Test-Harness für die Bridge (Spec #2, Testing Decisions).

Die Bridge läuft als echter Prozess (`python -m vspin_bridge ...`), Tests hängen
Test-Clients an den Bus und prüfen nur das dort beobachtbare Verhalten.
Spätere Pakete übernehmen `bridge_process` bzw. `BridgeProcess` für andere Quellen.
"""

import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

from websockets.sync.client import ClientConnection

BRIDGE_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = BRIDGE_ROOT / "src"
HOST = "127.0.0.1"
PORT = 8765
BUS_URL = f"ws://{HOST}:{PORT}"

START_TIMEOUT_S = 10.0
STOP_TIMEOUT_S = 5.0


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


class BridgeProcess:
    """Startet die Bridge als Subprozess, wartet auf den Bus und beendet sie sauber."""

    def __init__(self, args: list[str], log_path: Path) -> None:
        self.args = args
        self.log_path = log_path
        self.proc: subprocess.Popen | None = None
        self.returncode: int | None = None

    def start(self) -> None:
        # Port muss frei sein, sonst würde der Test gegen eine fremde Bridge laufen.
        wait_until(lambda: not port_open(), STOP_TIMEOUT_S, f"Port {PORT} wird frei")
        env = dict(os.environ)
        env["PYTHONPATH"] = os.pathsep.join(filter(None, [str(SRC_DIR), env.get("PYTHONPATH")]))
        env["PYTHONUNBUFFERED"] = "1"
        self._log = open(self.log_path, "w", encoding="utf-8")
        self.proc = subprocess.Popen(
            [sys.executable, "-m", "vspin_bridge", *self.args],
            stdin=subprocess.DEVNULL,  # kein TTY → Tastatur aus, Bridge läuft trotzdem
            stdout=self._log,
            stderr=subprocess.STDOUT,
            env=env,
            # Arbeitsverzeichnis = Testverzeichnis: die Standard-Ablage `./sessions` landet dort,
            # nie im Repo.
            cwd=self.log_path.parent,
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
                self.proc.terminate()
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

    def log(self) -> str:
        return self.log_path.read_text(encoding="utf-8", errors="replace")


def receive_json(client: ClientConnection, timeout_s: float = 3.0) -> dict:
    raw = client.recv(timeout=timeout_s)
    assert isinstance(raw, str), "Bus-Nachrichten sind UTF-8-JSON-Textframes"
    return json.loads(raw)
