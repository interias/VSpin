"""Bus-Client des Begleiters (docs/bus-protocol.md): verbindet sich mit der Bridge und hält die Verbindung.

Ist der Bus nicht erreichbar oder bricht die Verbindung ab, versucht der Client es alle
`reconnect_interval_s` neu – der Begleiter darf vor und nach der Bridge starten.
"""

import asyncio
import contextlib
import json
from collections.abc import Awaitable, Callable

from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed, WebSocketException

HOST = "127.0.0.1"
PORT = 8765  # wie die Bridge (ADR-0002); anderer nur für parallele Testläufe (VSPIN_PORT_BASE)
RECONNECT_INTERVAL_S = 1.0
OPEN_TIMEOUT_S = 3.0


class BusClient:
    """`on_connected` läuft nach jedem (Neu-)Verbinden, `on_message` je empfangenem JSON-Objekt. Was kein
    JSON-Objekt ist, wird verworfen; unbekannte Typen entscheidet der Empfänger (er ignoriert sie)."""

    def __init__(
        self,
        url: str,
        on_message: Callable[[dict], Awaitable[None]],
        on_connected: Callable[[], Awaitable[None]] = lambda: asyncio.sleep(0),
        log: Callable[[str], None] = lambda text: None,
        reconnect_interval_s: float = RECONNECT_INTERVAL_S,
    ) -> None:
        self.url = url
        self._on_message = on_message
        self._on_connected = on_connected
        self._log = log
        self._reconnect_interval_s = reconnect_interval_s
        self._connection: ClientConnection | None = None

    @property
    def connected(self) -> bool:
        return self._connection is not None

    async def run(self, stop: asyncio.Event) -> None:
        """Verbinden, empfangen, neu verbinden – bis `stop` gesetzt wird."""
        session = asyncio.create_task(self._connect_forever())
        stopped = asyncio.create_task(stop.wait())
        try:
            await asyncio.wait({session, stopped}, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for task in (session, stopped):
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task

    async def send(self, message: dict) -> bool:
        """Sendet `message`; ohne Verbindung geht sie verloren (False) – nach dem Neuverbinden zählt der neue Stand."""
        connection = self._connection
        if connection is None:
            return False
        try:
            await connection.send(json.dumps(message, separators=(",", ":"), ensure_ascii=False))
        except ConnectionClosed:
            return False
        return True

    async def _connect_forever(self) -> None:
        announced_wait = False
        while True:
            was_connected = False
            try:
                async with connect(self.url, open_timeout=OPEN_TIMEOUT_S) as connection:
                    self._connection, was_connected, announced_wait = connection, True, False
                    self._log(f"Bus verbunden: {self.url}")
                    await self._on_connected()
                    async for raw in connection:
                        message = _decode(raw)
                        if message is not None:
                            await self._on_message(message)
            except (OSError, TimeoutError, WebSocketException):
                pass  # Bus weg oder (noch) nicht da – unten neu versuchen
            finally:
                self._connection = None
            retry = f"neuer Versuch alle {self._reconnect_interval_s:g} s"
            if was_connected:
                self._log(f"Bus getrennt – {retry}")
            elif not announced_wait:
                self._log(f"Bus {self.url} nicht erreichbar – {retry}")
                announced_wait = True
            await asyncio.sleep(self._reconnect_interval_s)


def _decode(raw: str | bytes) -> dict | None:
    if not isinstance(raw, str):
        return None
    try:
        message = json.loads(raw)
    except (ValueError, RecursionError):
        return None
    return message if isinstance(message, dict) else None
