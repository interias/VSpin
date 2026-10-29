"""Controller-Quelle: Zwift-Ride-Lenkercontroller per BLE (Spec #75, Rolle `controller` im Verbindungsfenster).

Dritte Rolle der Bridge neben Rad und Puls; keine `DeviceSource`, sondern eine kleine Schnittstelle nach dem Vorbild
der `HeartRateSource` (`sources/heart_rate.py`). Sie **schreibt nie** auf den Controller (kein RideOn-Handshake, keine
Tasten, kein Abo): verbinden, Gerätedatenbank prüfen, Batterie lesen, Verbindung halten.

- **Erkennen:** Herstellerdaten der Firma `0x094A` (Zwift), erstes Nutzdatenbyte 7 = rechts, 8 = links; ersatzweise
  der Name „Zwift SF2“ (Seite unbekannt). Die Suche nimmt jede Ankündigung (ohne Filter beim BLE-Stack, weil auch der
  Name zählt) und filtert selbst.
- **Gemerkte Geräte** setzt der Besitzer (das Spiel über den Bus): Adresse, Name, Seite. Der linke Controller hat
  Vorrang – er tunnelt den rechten, die App braucht nur ihn –, danach gilt die Reihenfolge der Liste. Erkannt wird an
  der Adresse, sonst am Namen (wie beim Puls).
- **Hintergrundsuche und Neuverbinden** wie beim Puls: solange nicht das Gerät mit dem höchsten Vorrang verbunden ist,
  sucht die Quelle und verbindet das beste gemerkte Gerät, das sendet; nach Abbruch `retry_s` (3 s, ADR-0004) und eine
  neue Ankündigung.
- **Gesperrt:** Ab Firmware 1.3 versteckt der Ride V2 seinen Service, bis er einmal in Zwift verbunden war (gilt dann
  etwa 24 h). Fehlt nach dem Verbinden in der Gerätedatenbank (`BleConnection.service_uuids`) `0xFC82` und ebenso
  `00000001-19ca-4651-86e5-fa29dcdd09d1`, meldet die Quelle `locked`, trennt und versucht es erst nach
  `locked_retry_s` (30 s) wieder – so nimmt sie den Controller nicht im 3-s-Takt einer anderen App weg.
- **Batterie:** `0x2A19` wird nach dem Verbinden einmal gelesen, wenn es das gibt (sonst `None`), auch bei `locked`.
- **Zustand** `connected | locked | disconnected | off` mit Gerät und Batterie; jede Änderung meldet `on_status`
  genau einmal.

**Suche auf Anfrage** teilt sich den einen Scanner mit der Hintergrundsuche (wie beim Puls). Suche und Verbindungen
führt allein eine Hintergrundaufgabe (`start`/`stop`); die öffentlichen Methoden setzen nur Wünsche und wecken sie.
"""

import asyncio
import contextlib
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace
from enum import StrEnum

from ..ble import Advertisement, BleAdapter, BleConnection, BleError, BleScan

ZWIFT_COMPANY_ID = 0x094A
SIDE_RIGHT = 7  # erstes Nutzdatenbyte der Herstellerdaten
SIDE_LEFT = 8
CONTROLLER_NAME = "Zwift SF2"  # Ersatz, wenn die Herstellerdaten fehlen
RIDE_SERVICE = "0000fc82-0000-1000-8000-00805f9b34fb"
RIDE_SERVICE_LEGACY = "00000001-19ca-4651-86e5-fa29dcdd09d1"
BATTERY_LEVEL = "00002a19-0000-1000-8000-00805f9b34fb"

RETRY_S = 3.0  # Pause nach Abbruch oder gescheitertem Versuch (ADR-0004)
LOCKED_RETRY_S = 30.0  # Pause nach „gesperrt“: erst dann wieder verbinden
SEARCH_S = 30.0  # Dauer einer Suche auf Anfrage


class Side(StrEnum):
    LEFT = "left"
    RIGHT = "right"


class ControllerState(StrEnum):
    CONNECTED = "connected"
    LOCKED = "locked"  # verbunden gewesen, Service versteckt: einmal in Zwift verbinden
    DISCONNECTED = "disconnected"  # Geräte gemerkt, keines verbunden, Hintergrundsuche läuft
    OFF = "off"  # keine Geräte gemerkt


@dataclass(frozen=True, slots=True)
class ControllerDevice:
    address: str
    name: str
    side: Side | None = None


@dataclass(frozen=True, slots=True)
class ControllerStatus:
    """`device`: das verbundene (bei `locked` das zuletzt geprüfte) Gerät mit der tatsächlichen Adresse; `battery` in
    Prozent oder `None`."""

    state: ControllerState
    device: ControllerDevice | None = None
    battery: int | None = None


def controller_side(advertisement: Advertisement) -> Side | None:
    """Seite laut Herstellerdaten (`None`, wenn sie fehlen oder kein Ride-Controller sind)."""
    payload = advertisement.manufacturer_data.get(ZWIFT_COMPANY_ID, b"")
    if payload[:1] == bytes([SIDE_LEFT]):
        return Side.LEFT
    if payload[:1] == bytes([SIDE_RIGHT]):
        return Side.RIGHT
    return None


def is_controller(advertisement: Advertisement) -> bool:
    """Ein Ride-Controller: Herstellerdaten mit Seite oder ersatzweise der Name „Zwift SF2“."""
    return controller_side(advertisement) is not None or (advertisement.name or "").startswith(CONTROLLER_NAME)


class _Link:
    def __init__(self, rank: int, device: ControllerDevice, rssi: int | None) -> None:
        self.rank = rank
        self.device = device
        self.rssi = rssi
        self.connection: BleConnection | None = None
        self.alive = True


class ControllerSource:
    def __init__(
        self,
        adapter: BleAdapter,
        on_status: Callable[[ControllerStatus], None],
        *,
        retry_s: float = RETRY_S,
        locked_retry_s: float = LOCKED_RETRY_S,
        search_s: float = SEARCH_S,
    ) -> None:
        self._adapter = adapter
        self._on_status = on_status
        self._retry_s = retry_s
        self._locked_retry_s = locked_retry_s
        self._search_s = search_s

        self._known: list[ControllerDevice] = []
        self._link: _Link | None = None
        self._locked: ControllerStatus | None = None  # letzte Prüfung ergab „gesperrt“ (bis zum Verbinden)
        self._locked_rssi: int | None = None
        self._battery: int | None = None

        self._scan: BleScan | None = None
        self._scan_retry_at = 0.0
        self._seen: dict[int, Advertisement] = {}  # Rang → letzte Ankündigung seit dem letzten Versuch
        self._retry_at = 0.0
        self._epoch = 0

        self._search_receiver: Callable[[Advertisement], None] | None = None
        self._search_timer: asyncio.TimerHandle | None = None

        self._wake = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._reported = ControllerStatus(ControllerState.OFF)

    # --- Schnittstelle für den Besitzer -------------------------------------------------

    @property
    def status(self) -> ControllerStatus:
        return self._reported

    @property
    def rssi(self) -> int | None:
        """Signalstärke (dBm) der Ankündigung, über die das verbundene bzw. gesperrte Gerät verbunden wurde."""
        if self._link is not None:
            return self._link.rssi
        return self._locked_rssi if self._locked is not None else None

    @property
    def searching(self) -> bool:
        return self._search_receiver is not None

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="controller-source")

    async def stop(self) -> None:
        """Beendet Hintergrundaufgabe, Suche und Verbindung. Meldet keinen Zustand mehr."""
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        self._end_search()
        if self._scan is not None:
            scan, self._scan = self._scan, None
            with contextlib.suppress(BleError):
                await scan.stop()
        if self._link is not None:
            link, self._link = self._link, None
            await self._close(link)

    async def set_known_devices(self, devices: Sequence[ControllerDevice]) -> None:
        """Gemerkte Controller (links zuerst, sonst in dieser Reihenfolge). Eine leere Liste schaltet die Quelle `off`
        und trennt eine bestehende Verbindung."""
        self._known = sorted(devices, key=lambda device: device.side is not Side.LEFT)
        self._epoch += 1
        self._seen.clear()
        self._retry_at = 0.0
        locked = None if self._locked is None else self._locked.device
        if locked is not None and self._rank(locked.address, locked.name, locked.side) is None:
            self._locked = None
        dropped: _Link | None = None
        if self._link is not None:
            rank = self._rank(self._link.device.address, self._link.device.name, self._link.device.side)
            if rank is None:
                dropped, self._link = self._link, None
            else:
                self._link.rank = rank
        self._publish()
        self._wake.set()
        if dropped is not None:
            await self._close(dropped)

    def start_search(self, on_found: Callable[[Advertisement], None], duration_s: float | None = None) -> None:
        """Suche auf Anfrage: `on_found` bekommt bis zum Ende jede Ankündigung eines Ride-Controllers, auch nicht
        gemerkter. Endet nach `duration_s` (Standard `search_s`) oder mit `stop_search`."""
        self._end_search()
        self._search_receiver = on_found
        delay = self._search_s if duration_s is None else duration_s
        self._search_timer = asyncio.get_running_loop().call_later(delay, self.stop_search)
        self._wake.set()

    def stop_search(self) -> None:
        self._end_search()
        self._wake.set()

    # --- Hintergrundaufgabe -------------------------------------------------------------

    async def _run(self) -> None:
        loop = asyncio.get_running_loop()
        while True:
            self._wake.clear()
            await self._sync_scan()
            timeout: float | None = None
            target = self._candidate()
            if target is not None:
                wait = self._retry_at - loop.time()
                if wait <= 0:
                    await self._connect(*target)
                    continue
                timeout = wait
            if self._scan_wanted() and self._scan is None:
                wait = max(self._scan_retry_at - loop.time(), 0.0)
                timeout = wait if timeout is None else min(timeout, wait)
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self._wake.wait(), timeout)

    def _scan_wanted(self) -> bool:
        if self._search_receiver is not None:
            return True
        return bool(self._known) and (self._link is None or self._link.rank > 0)

    async def _sync_scan(self) -> None:
        loop = asyncio.get_running_loop()
        if self._scan_wanted():
            if self._scan is None and loop.time() >= self._scan_retry_at:
                try:
                    self._scan = await self._adapter.start_scan(self._on_advertisement)
                except BleError:
                    self._scan_retry_at = loop.time() + self._retry_s
        elif self._scan is not None:
            scan, self._scan = self._scan, None
            self._seen.clear()
            with contextlib.suppress(BleError):
                await scan.stop()

    def _candidate(self) -> tuple[int, Advertisement] | None:
        limit = len(self._known) if self._link is None else self._link.rank
        ranks = [rank for rank in self._seen if rank < limit]
        if not ranks:
            return None
        best = min(ranks)
        return best, self._seen[best]

    async def _connect(self, rank: int, advertisement: Advertisement) -> None:
        loop = asyncio.get_running_loop()
        epoch = self._epoch
        known = self._known[rank]
        device = replace(known, address=advertisement.address, side=controller_side(advertisement) or known.side)
        link = _Link(rank, device, advertisement.rssi)
        locked = False
        battery: int | None = None
        try:
            link.connection = await self._adapter.connect(advertisement.address, lambda: self._on_disconnect(link))
            services = link.connection.service_uuids
            locked = RIDE_SERVICE not in services and RIDE_SERVICE_LEGACY not in services
            battery = await self._read_battery(link.connection)
        except BleError:
            link.alive = False
        except asyncio.CancelledError:
            await self._close(link)
            raise
        if not link.alive or epoch != self._epoch or locked:
            await self._close(link)
            if epoch == self._epoch:
                self._seen.pop(rank, None)
                self._retry_at = loop.time() + (self._locked_retry_s if locked else self._retry_s)
                if locked:
                    self._locked = ControllerStatus(ControllerState.LOCKED, device, battery)
                    self._locked_rssi = advertisement.rssi
                    self._publish()
            return
        previous, self._link = self._link, link
        self._locked = None
        self._battery = battery
        self._publish()
        if previous is not None:
            await self._close(previous)

    @staticmethod
    async def _read_battery(connection: BleConnection) -> int | None:
        """Batterie in Prozent aus `0x2A19`, wenn es das gibt (nur lesen)."""
        try:
            data = await connection.read(BATTERY_LEVEL)
        except BleError:
            return None
        return data[0] if data else None

    async def _close(self, link: _Link) -> None:
        link.alive = False
        if link.connection is not None:
            with contextlib.suppress(BleError):
                await link.connection.disconnect()

    # --- Rückrufe aus dem BLE-Stack (im Event-Loop) ------------------------------------

    def _on_advertisement(self, advertisement: Advertisement) -> None:
        if not is_controller(advertisement):
            return
        if self._search_receiver is not None:
            self._search_receiver(advertisement)
        rank = self._rank(advertisement.address, advertisement.name, controller_side(advertisement))
        if rank is not None:
            self._seen[rank] = advertisement
            self._wake.set()

    def _on_disconnect(self, link: _Link) -> None:
        link.alive = False
        if link is not self._link:
            return
        self._link = None
        self._seen.pop(link.rank, None)
        self._retry_at = asyncio.get_running_loop().time() + self._retry_s
        self._publish()
        self._wake.set()

    # --- Hilfen --------------------------------------------------------------------------

    def _rank(self, address: str, name: str | None, side: Side | None) -> int | None:
        """Platz des gemerkten Geräts: zuerst nach Adresse, sonst nach Name – beide Seiten heißen gleich, deshalb
        dann nur, wenn die Seite nicht widerspricht."""
        for rank, known in enumerate(self._known):
            if known.address.lower() == address.lower():
                return rank
        if name:
            for rank, known in enumerate(self._known):
                if known.name == name and (side is None or known.side is None or known.side is side):
                    return rank
        return None

    def _end_search(self) -> None:
        if self._search_timer is not None:
            self._search_timer.cancel()
            self._search_timer = None
        self._search_receiver = None

    def _publish(self) -> None:
        if not self._known:
            status = ControllerStatus(ControllerState.OFF)
        elif self._link is not None:
            status = ControllerStatus(ControllerState.CONNECTED, self._link.device, self._battery)
        elif self._locked is not None:
            status = self._locked
        else:
            status = ControllerStatus(ControllerState.DISCONNECTED)
        if status != self._reported:
            self._reported = status
            self._on_status(status)
