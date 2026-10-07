"""Bus: WebSocket-Server auf 127.0.0.1:8765 (Standard), beliebig viele Clients."""

from collections.abc import Awaitable, Callable

from websockets.asyncio.server import Server, ServerConnection, broadcast, serve
from websockets.exceptions import ConnectionClosed

HOST = "127.0.0.1"  # Standard: nur localhost – niemand im Netz liest mit oder steuert
PORT = 8765


class BusStartError(Exception):
    """Der Bus konnte nicht auf Host:8765 lauschen (z. B. Port belegt)."""


class BusServer:
    """Verteilt Nachrichten an alle Clients. Jeder neue Client bekommt zuerst `status`.

    Eingehende Client-Nachrichten gehen an `on_message`; dessen Antwort (`ack`/`error`)
    bekommt nur der sendende Client, nie ein Broadcast.
    """

    def __init__(
        self,
        status: Callable[[], str],
        on_clients_changed: Callable[[int], None] = lambda n: None,
        on_message: Callable[[str | bytes], Awaitable[str | None]] | None = None,
        host: str = HOST,
    ) -> None:
        self.host = host  # 0.0.0.0 nur im Container (Port dort nur auf 127.0.0.1 veröffentlicht)
        self._status = status
        self._on_clients_changed = on_clients_changed
        self._on_message = on_message
        self._clients: set[ServerConnection] = set()
        self._server: Server | None = None

    @property
    def client_count(self) -> int:
        return len(self._clients)

    async def start(self) -> None:
        try:
            self._server = await serve(self._handle, self.host, PORT)
        except OSError as exc:
            raise BusStartError(f"ws://{self.host}:{PORT} nicht verfügbar: {exc}") from exc

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

    def publish(self, message: str) -> None:
        broadcast(self._clients, message)

    async def _handle(self, connection: ServerConnection) -> None:
        # Synchron senden und erst danach registrieren: so ist `status` garantiert
        # die erste Nachricht, und kein späterer Broadcast geht dazwischen verloren.
        broadcast([connection], self._status())
        self._clients.add(connection)
        self._on_clients_changed(len(self._clients))
        try:
            async for raw in connection:
                if self._on_message is None:
                    continue
                reply = await self._on_message(raw)
                if reply is not None:
                    await connection.send(reply)  # nur an den Absender
        except ConnectionClosed:
            pass  # Client ist ohne sauberen Close-Handshake weg – kein Fehler der Bridge
        finally:
            self._clients.discard(connection)
            self._on_clients_changed(len(self._clients))
