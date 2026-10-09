"""Replay der Pulsquelle: spielt aufgezeichnete `0x2A37`-Notifications ab (Spec #64).

Statt eines Gurts steckt hinter der BLE-Nahtstelle (`ble/base.py`) dieser Adapter; die
`HeartRateSource` läuft unverändert. Sie bleibt `off`, bis ein Client `set_heart_rate_devices`
schickt. Danach gilt wie bei echten Geräten:

- `start_scan` kündigt das Gerät der Aufnahme an: Adresse `REPLAY_ADDRESS`, Name `REPLAY_NAME`
  (fest, damit Tests und Spiel es kennen). Der Client merkt es an Adresse oder Namen.
- `connect` und `subscribe` spielen die Notifications im Takt der Aufnahme ab, die erste kurz
  nach dem Abonnieren.
- Am Ende reißt die Verbindung ab, wie bei einem abgenommenen Gurt: die Quelle meldet
  `disconnected`. Danach kündigt der Adapter das Gerät nicht mehr an, es gibt also keine
  Wiederholung. Trennt der Client vorher von sich aus (z. B. mit `[]`), beginnt die Aufnahme beim
  nächsten Verbinden von vorn.

Eingabe ist das Rohformat aus `replay.py`; aus der Datei zählen nur die `0x2A37`-Zeilen (Rad-Zeilen
werden übersprungen), deren `t_ms` nicht fallen darf. Pulszeilen einer Session tragen die
Bridge-Zeit; nur die Abstände zählen.
"""

import asyncio
import contextlib
from collections.abc import Callable
from pathlib import Path

from ..ble import Advertisement, BleError
from ..parsers import HEART_RATE_MEASUREMENT
from .base import RawNotification
from .heart_rate import HEART_RATE_SERVICE
from .replay import ReplayError, read_notifications

REPLAY_ADDRESS = "56:53:50:49:4E:01"  # „VSPIN“ + 01; kein echtes Gerät
REPLAY_NAME = "VSpin Replay"
REPLAY_RSSI = -50
ADVERT_INTERVAL_S = 0.5  # so oft kündigt sich das Gerät an, wie ein echtes
START_DELAY_S = 0.05  # Vorlauf nach dem Abonnieren, in dem die Quelle die Verbindung übernimmt


def load_heart_rate_replay(path: Path) -> list[RawNotification]:
    """Die `0x2A37`-Zeilen der Rohdatei. Fehler wie bei `--source replay`; eine Datei ohne Pulszeilen ist einer."""
    notifications = read_notifications(path, lambda n: n.char.lower() == HEART_RATE_MEASUREMENT)
    if not notifications:
        raise ReplayError(f"Replay-Datei {path} enthält keine Puls-Notifications (0x2A37)")
    return notifications


class ReplayBleAdapter:
    def __init__(self, notifications: list[RawNotification]) -> None:
        self.notifications = notifications
        self._connection: _ReplayConnection | None = None
        self._finished = False  # Aufnahme bis zum Ende gespielt: das Gerät ist weg

    @property
    def _present(self) -> bool:
        """Sendet das Gerät? Nicht mehr nach dem Ende, und nicht, solange es verbunden ist."""
        return not self._finished and self._connection is None

    async def start_scan(self, service: str, on_found: Callable[[Advertisement], None]) -> "_ReplayScan":
        scan = _ReplayScan()
        if service.lower() == HEART_RATE_SERVICE:
            scan.task = asyncio.create_task(self._advertise(on_found))
        return scan

    async def _advertise(self, on_found: Callable[[Advertisement], None]) -> None:
        while True:
            if self._present:
                on_found(Advertisement(REPLAY_ADDRESS, REPLAY_NAME, REPLAY_RSSI))
            await asyncio.sleep(ADVERT_INTERVAL_S)

    async def connect(self, address: str, on_disconnect: Callable[[], None]) -> "_ReplayConnection":
        if address.lower() != REPLAY_ADDRESS.lower() or not self._present:
            raise BleError(f"{address} nicht erreichbar")
        self._connection = _ReplayConnection(self, on_disconnect)
        return self._connection

    def _closed(self, connection: "_ReplayConnection", finished: bool) -> None:
        if self._connection is connection:
            self._connection = None
            self._finished = self._finished or finished


class _ReplayScan:
    def __init__(self) -> None:
        self.task: asyncio.Task[None] | None = None

    async def stop(self) -> None:
        if self.task is not None:
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task


class _ReplayConnection:
    address = REPLAY_ADDRESS

    def __init__(self, adapter: ReplayBleAdapter, on_disconnect: Callable[[], None]) -> None:
        self._adapter = adapter
        self._on_disconnect = on_disconnect
        self._task: asyncio.Task[None] | None = None
        self._open = True

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        if char.lower() != HEART_RATE_MEASUREMENT:
            raise BleError(f"{REPLAY_ADDRESS}: {char} gibt es nicht")
        if not self._open:
            raise BleError(f"{REPLAY_ADDRESS} getrennt")
        self._task = asyncio.create_task(self._play(on_notify))

    async def _play(self, on_notify: Callable[[bytes], None]) -> None:
        loop = asyncio.get_running_loop()
        notifications = self._adapter.notifications
        start = loop.time() + START_DELAY_S
        first_ms = notifications[0].t_ms
        for notification in notifications:
            due = start + (notification.t_ms - first_ms) / 1000.0
            await asyncio.sleep(max(0.0, due - loop.time()))
            on_notify(notification.data)
        self._close(finished=True)

    async def disconnect(self) -> None:
        task, self._task = self._task, None
        if task is not None and task is not asyncio.current_task():
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
        self._close(finished=False)

    def _close(self, finished: bool) -> None:
        if self._open:
            self._open = False
            self._adapter._closed(self, finished)
            self._on_disconnect()
