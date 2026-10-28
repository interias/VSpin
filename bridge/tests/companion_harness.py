"""Test-Harness für den Begleiter (Spec #76, Testing Decisions): Toni mit Fakes an einem echten Bus.

`InProcessCompanion` lässt `Companion` mit den vom Test gebauten Fakes in einem eigenen Thread laufen, verbunden mit
der Bridge auf `BUS_URL` (8765 + Platz von VSPIN_PORT_BASE). Geprüft wird am Bus (`companion_status`) und an den
Fakes – nie Claude, OpenRouter, Mikrofon oder GPU.
"""

import asyncio
import io
import json
import threading
import time

from bridge_harness import BUS_URL, STOP_TIMEOUT_S, wait_until
from websockets.sync.client import ClientConnection

RECONNECT_INTERVAL_S = 0.2  # Tests warten nicht die volle Sekunde aufs Neuverbinden


class InProcessCompanion:
    def __init__(self, brain, ears, mouth, clock) -> None:
        self.brain, self.ears, self.mouth, self.clock = brain, ears, mouth, clock
        self.error: BaseException | None = None
        self.companion = None
        self._output = io.StringIO()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop: asyncio.Event | None = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._main, daemon=True)
        self._thread.start()
        wait_until(lambda: self._loop is not None, STOP_TIMEOUT_S, "Begleiter läuft")

    def _main(self) -> None:
        from vspin_companion.companion import Companion

        async def main() -> None:
            self.companion = Companion(
                self.brain, self.ears, self.mouth, self.clock, BUS_URL, self._log, RECONNECT_INTERVAL_S
            )
            self._stop = asyncio.Event()
            self._loop = asyncio.get_running_loop()
            await self.companion.run(self._stop)

        try:
            asyncio.run(main())
        except BaseException as exc:  # Ergebnis für `stop()` – der Test prüft es
            self.error = exc

    def _log(self, text: str) -> None:
        self._output.write(text + "\n")

    @property
    def alive(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def stop(self) -> BaseException | None:
        if self._thread is None:
            return self.error
        if self._thread.is_alive() and self._loop is not None:
            self._loop.call_soon_threadsafe(self._stop.set)
        self._thread.join(STOP_TIMEOUT_S)
        assert not self._thread.is_alive(), "Begleiter im Testprozess endet nicht"
        self._thread = None
        return self.error

    def log(self) -> str:
        return self._output.getvalue()


def next_status(client: ClientConnection, timeout_s: float = 5.0) -> dict:
    """Nächstes `companion_status` am Bus (spätestens nach `timeout_s`); Telemetrie und `status` der Bridge
    dazwischen werden übergangen."""
    deadline = time.monotonic() + timeout_s
    while (remaining := deadline - time.monotonic()) > 0:
        try:
            raw = client.recv(timeout=remaining)
        except TimeoutError:
            break
        message = json.loads(raw)
        if message["type"] == "companion_status":
            return message
    raise AssertionError(f"kein companion_status in {timeout_s:g} s")


def ptt(client: ClientConnection, action: str) -> None:
    client.send(json.dumps({"v": 0, "type": "companion_ptt", "action": action}))
