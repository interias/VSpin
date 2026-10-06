"""Bridge-Ablauf: DeviceSource → Bus, Statuszeile im Terminal, Tastatur für den Simulator."""

import asyncio
import contextlib

from .bus import HOST, PORT, BusServer
from .bus.messages import status_message, telemetry_message
from .clock import bridge_time_ms
from .console import Console
from .keyboard import HELP, Key, Keyboard, keyboard_available
from .sources.base import DeviceSource
from .sources.sim import SimulatorSource

CONNECTED = "connected"
DISCONNECTED = "disconnected"

CADENCE_STEP = 5.0


class Bridge:
    def __init__(self, source: DeviceSource, console: Console) -> None:
        self._source = source
        self._console = console
        self._state = DISCONNECTED
        self._cadence: float | None = None
        self._bus = BusServer(self._status_message, on_clients_changed=lambda _: self._render())
        self._stop: asyncio.Event | None = None

    async def run(self, stop: asyncio.Event) -> None:
        """Läuft, bis `stop` gesetzt wird. Wirft `BusStartError`, wenn der Bus-Port belegt ist."""
        self._stop = stop
        await self._bus.start()
        keyboard: Keyboard | None = None
        try:
            self._console.info(f"vspin-bridge: Bus auf ws://{HOST}:{PORT}")
            if isinstance(self._source, SimulatorSource) and keyboard_available():
                keyboard = Keyboard(self._on_key)
                keyboard.start()
                self._console.info(HELP)
            self._render()
            await self._source.connect()
            self._set_state(CONNECTED)

            pump = asyncio.create_task(self._pump())
            stopped = asyncio.create_task(stop.wait())
            await asyncio.wait({pump, stopped}, return_when=asyncio.FIRST_COMPLETED)
            if pump.done() and pump.exception() is not None:
                raise pump.exception()
            await stop.wait()  # Quelle beendet → Bus bleibt bis zum Stopp erreichbar
            for task in (pump, stopped):
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        finally:
            if keyboard is not None:
                keyboard.stop()
            await self._bus.stop()
            self._console.close()

    async def _pump(self) -> None:
        async for sample in self._source.samples():
            self._cadence = sample.cadence
            self._bus.publish(telemetry_message(sample))
            self._render()
        self._set_state(DISCONNECTED)

    def _status_message(self) -> str:
        return status_message(
            bridge_time_ms(), self._state, self._source.name, self._source.capabilities
        )

    def _set_state(self, state: str) -> None:
        if state == self._state:
            return
        self._state = state
        self._bus.publish(self._status_message())  # `status` bei jeder Änderung
        self._render()

    def _on_key(self, key: Key) -> None:
        if key is Key.QUIT:
            if self._stop is not None:
                self._stop.set()
        elif isinstance(self._source, SimulatorSource):
            self._source.adjust_cadence(CADENCE_STEP if key is Key.UP else -CADENCE_STEP)

    def _render(self) -> None:
        self._console.show(self._source.name, self._state, self._cadence, self._bus.client_count)
