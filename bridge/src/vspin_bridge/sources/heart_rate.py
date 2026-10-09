"""Pulsquelle: Herzfrequenz per BLE Heart Rate Service `0x180D` (ADR-0008, Spec #64).

Zweite Quelle der Bridge neben der Radquelle; keine `DeviceSource`, sondern eine eigene,
kleinere Schnittstelle. Sie fasst die Radquelle nie an.

- **Gemerkte Geräte** setzt der Besitzer (das Spiel über den Bus): Adresse, Name, Rolle
  `strap | watch`; die Reihenfolge ist der Vorrang. Die Quelle merkt sich nichts dauerhaft.
  Ein gemerktes Gerät wird an der Adresse erkannt oder, wenn die nicht passt, am Namen
  (ob die Uhr beim Senden eine feste Adresse nutzt, ist nicht verifiziert).
- **Hintergrundsuche:** Solange nicht das Gerät mit dem höchsten Vorrang verbunden ist, sucht
  die Quelle nach `0x180D` und verbindet sich mit dem besten gemerkten Gerät, das sendet;
  eine verbundene Uhr tauscht sie gegen den Gurt (erst verbinden, dann die Uhr trennen).
  Sie verbindet sich nie mit nicht gemerkten Geräten.
- **Neuverbinden:** Nach Abbruch oder gescheitertem Versuch wartet sie `retry_s` (3 s wie
  beim Rad, ADR-0004) und braucht eine neue Ankündigung des Geräts, bevor sie es wieder
  versucht – ein Gerät, das nicht mehr sendet, wird nicht blind weiter angewählt.
- **Zustand** `connected | stale | disconnected | off` mit verbundenem Gerät; jede Änderung
  meldet `on_status` genau einmal. `stale`: verbunden, aber seit mehr als `stale_s` (5 s)
  kein Pulswert.
- **Pulswert:** `heart_rate` ist der letzte Wert, `None` wenn er älter als `stale_s` ist.
  Jede Notification geht zusätzlich roh an `on_raw` (Session-Rohdatei), auch eine kaputte;
  deren Wert wird verworfen, die Verbindung bleibt.

**Suche auf Anfrage und ein einziger Scanner:** Die Quelle hält höchstens eine Suche beim
BLE-Stack offen und verteilt jede Ankündigung an beide Abnehmer – an den Empfänger der Suche
auf Anfrage (alle Pulsgeräte, auch nicht gemerkte) und an die Hintergrundsuche (nur gemerkte).
Die Suche läuft, solange einer der beiden sie braucht. So startet oder stoppt die Suche auf
Anfrage keinen zweiten Scanner neben dem ersten (unter Windows teilen sich mehrere Watcher
einen Adapter) und unterbricht die Hintergrundsuche nicht; Verbindungen berührt sie nie.

Suche und Verbindungen führt allein eine Hintergrundaufgabe (`start`/`stop`); die öffentlichen
Methoden setzen nur Wünsche und wecken sie. Dadurch gibt es keine zwei gleichzeitigen
Verbindungsversuche und keinen Wettlauf um den Scanner.
"""

import asyncio
import contextlib
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace
from enum import StrEnum

from ..ble import Advertisement, BleAdapter, BleConnection, BleError, BleScan
from ..clock import bridge_time_ms
from ..parsers import HEART_RATE_MEASUREMENT, ParseError, parse_heart_rate_measurement
from .base import RawNotification

HEART_RATE_SERVICE = "0000180d-0000-1000-8000-00805f9b34fb"

STALE_S = 5.0  # ohne Pulswert länger als das: stale, Wert None (Spec #64)
RETRY_S = 3.0  # Pause nach Abbruch oder gescheitertem Versuch (ADR-0004)
SEARCH_S = 30.0  # Dauer einer Suche auf Anfrage


class Role(StrEnum):
    STRAP = "strap"
    WATCH = "watch"


class HeartRateState(StrEnum):
    CONNECTED = "connected"
    STALE = "stale"
    DISCONNECTED = "disconnected"  # Geräte gemerkt, keines verbunden, Hintergrundsuche läuft
    OFF = "off"  # keine Geräte gemerkt


@dataclass(frozen=True, slots=True)
class HeartRateDevice:
    address: str
    name: str
    role: Role


@dataclass(frozen=True, slots=True)
class HeartRateStatus:
    """`device`: das verbundene Gerät mit der tatsächlich verbundenen Adresse (bei Erkennung
    am Namen weicht sie von der gemerkten ab), Name und Rolle aus der gemerkten Liste."""

    state: HeartRateState
    device: HeartRateDevice | None = None


class _Link:
    """Eine Verbindung samt Platz in der gemerkten Liste (`rank`, 0 = höchster Vorrang)."""

    def __init__(self, rank: int, device: HeartRateDevice) -> None:
        self.rank = rank
        self.device = device
        self.connection: BleConnection | None = None
        self.alive = True


class HeartRateSource:
    def __init__(
        self,
        adapter: BleAdapter,
        on_status: Callable[[HeartRateStatus], None],
        on_raw: Callable[[RawNotification], None] | None = None,
        *,
        stale_s: float = STALE_S,
        retry_s: float = RETRY_S,
        search_s: float = SEARCH_S,
    ) -> None:
        self._adapter = adapter
        self._on_status = on_status
        self._on_raw = on_raw
        self._stale_s = stale_s
        self._retry_s = retry_s
        self._search_s = search_s

        self._known: list[HeartRateDevice] = []
        self._link: _Link | None = None
        self._stale = False
        self._stale_timer: asyncio.TimerHandle | None = None
        self._bpm: int | None = None
        self._bpm_at = 0.0  # time.monotonic() des letzten Pulswerts

        self._scan: BleScan | None = None
        self._scan_retry_at = 0.0
        self._seen: dict[int, str] = {}  # Rang → Adresse, seit dem letzten Versuch angekündigt
        self._retry_at = 0.0
        self._epoch = 0  # zählt jedes Setzen der Liste; ein laufender Versuch erkennt so Veraltetes

        self._search_receiver: Callable[[Advertisement], None] | None = None
        self._search_timer: asyncio.TimerHandle | None = None

        self._wake = asyncio.Event()
        self._task: asyncio.Task[None] | None = None
        self._reported = HeartRateStatus(HeartRateState.OFF)

    # --- Schnittstelle für den Besitzer -------------------------------------------------

    @property
    def status(self) -> HeartRateStatus:
        return self._reported

    @property
    def heart_rate(self) -> int | None:
        """Letzter Pulswert in bpm; `None`, wenn er älter als `stale_s` ist oder keiner kam."""
        # `_stale` zusätzlich: der Zeitgeber des Loops darf minimal vor `time.monotonic` auslösen,
        # `stale` und `None` sollen trotzdem zusammenpassen.
        if self._bpm is None or self._stale or time.monotonic() - self._bpm_at > self._stale_s:
            return None
        return self._bpm

    @property
    def searching(self) -> bool:
        """Läuft gerade eine Suche auf Anfrage?"""
        return self._search_receiver is not None

    async def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="heart-rate-source")

    async def stop(self) -> None:
        """Beendet Hintergrundaufgabe, Suche und Verbindung. Meldet keinen Zustand mehr."""
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None
        self._end_search()
        self._cancel_stale_timer()
        if self._scan is not None:
            scan, self._scan = self._scan, None
            with contextlib.suppress(BleError):
                await scan.stop()
        if self._link is not None:
            link, self._link = self._link, None
            await self._close(link)

    async def set_known_devices(self, devices: Sequence[HeartRateDevice]) -> None:
        """Gemerkte Geräte, höchster Vorrang zuerst. Eine leere Liste schaltet die Quelle
        `off` und trennt eine bestehende Verbindung."""
        self._known = list(devices)
        self._epoch += 1
        self._seen.clear()
        self._retry_at = 0.0
        dropped: _Link | None = None
        if self._link is not None:
            rank = self._rank(self._link.device.address, self._link.device.name)
            if rank is None:
                dropped, self._link = self._link, None
                self._cancel_stale_timer()
            else:
                known = self._known[rank]
                self._link.rank = rank
                self._link.device = replace(known, address=self._link.device.address)
        if not self._known:
            self._bpm = None
        self._publish()
        self._wake.set()
        if dropped is not None:
            await self._close(dropped)

    def start_search(self, on_found: Callable[[Advertisement], None], duration_s: float | None = None) -> None:
        """Startet eine Suche auf Anfrage: `on_found` bekommt bis zum Ende jede Ankündigung
        eines Pulsgeräts (wiederholt, mit aktueller Signalstärke), auch nicht gemerkter.
        Endet nach `duration_s` (Standard `search_s`) oder mit `stop_search`; ein neuer
        Aufruf ersetzt eine laufende Suche."""
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
                    self._scan = await self._adapter.start_scan(HEART_RATE_SERVICE, self._on_advertisement)
                except BleError:
                    self._scan_retry_at = loop.time() + self._retry_s
        elif self._scan is not None:
            scan, self._scan = self._scan, None
            self._seen.clear()  # ohne Suche veralten die Ankündigungen
            with contextlib.suppress(BleError):
                await scan.stop()

    def _candidate(self) -> tuple[int, str] | None:
        """Bestes angekündigtes gemerktes Gerät mit höherem Vorrang als das verbundene."""
        limit = len(self._known) if self._link is None else self._link.rank
        ranks = [rank for rank in self._seen if rank < limit]
        if not ranks:
            return None
        best = min(ranks)
        return best, self._seen[best]

    async def _connect(self, rank: int, address: str) -> None:
        loop = asyncio.get_running_loop()
        epoch = self._epoch
        link = _Link(rank, replace(self._known[rank], address=address))
        try:
            link.connection = await self._adapter.connect(address, lambda: self._on_disconnect(link))
            await link.connection.subscribe(HEART_RATE_MEASUREMENT, lambda data: self._on_notify(link, data))
        except BleError:
            link.alive = False
        except asyncio.CancelledError:
            await self._close(link)  # `stop` mitten im Verbinden: keine Verbindung offen lassen
            raise
        if not link.alive or epoch != self._epoch:
            await self._close(link)
            if epoch == self._epoch:
                self._seen.pop(rank, None)
                self._retry_at = loop.time() + self._retry_s
            return
        previous, self._link = self._link, link
        self._stale = False
        self._restart_stale_timer(link)
        self._publish()
        if previous is not None:
            await self._close(previous)

    async def _close(self, link: _Link) -> None:
        link.alive = False
        if link.connection is not None:
            with contextlib.suppress(BleError):
                await link.connection.disconnect()

    # --- Rückrufe aus dem BLE-Stack (im Event-Loop) ------------------------------------

    def _on_advertisement(self, advertisement: Advertisement) -> None:
        if self._search_receiver is not None:
            self._search_receiver(advertisement)
        rank = self._rank(advertisement.address, advertisement.name)
        if rank is not None:
            self._seen[rank] = advertisement.address
            self._wake.set()

    def _on_disconnect(self, link: _Link) -> None:
        link.alive = False
        if link is not self._link:
            return
        self._link = None
        self._cancel_stale_timer()
        self._seen.pop(link.rank, None)
        self._retry_at = asyncio.get_running_loop().time() + self._retry_s
        self._publish()
        self._wake.set()

    def _on_notify(self, link: _Link, data: bytes) -> None:
        if link is not self._link:
            return
        if self._on_raw is not None:
            self._on_raw(RawNotification(bridge_time_ms(), HEART_RATE_MEASUREMENT, data))
        try:
            measurement = parse_heart_rate_measurement(data)
        except ParseError:
            return
        self._bpm = measurement.bpm
        self._bpm_at = time.monotonic()
        self._restart_stale_timer(link)
        if self._stale:
            self._stale = False
            self._publish()

    def _mark_stale(self, link: _Link) -> None:
        if link is self._link and not self._stale:
            self._stale = True
            self._publish()

    # --- Hilfen --------------------------------------------------------------------------

    def _rank(self, address: str, name: str | None) -> int | None:
        """Platz des gemerkten Geräts: zuerst nach Adresse, sonst nach Name."""
        for rank, known in enumerate(self._known):
            if known.address.lower() == address.lower():
                return rank
        if name:
            for rank, known in enumerate(self._known):
                if known.name == name:
                    return rank
        return None

    def _restart_stale_timer(self, link: _Link) -> None:
        self._cancel_stale_timer()
        self._stale_timer = asyncio.get_running_loop().call_later(self._stale_s, self._mark_stale, link)

    def _cancel_stale_timer(self) -> None:
        if self._stale_timer is not None:
            self._stale_timer.cancel()
            self._stale_timer = None

    def _end_search(self) -> None:
        if self._search_timer is not None:
            self._search_timer.cancel()
            self._search_timer = None
        self._search_receiver = None

    def _publish(self) -> None:
        if not self._known:
            status = HeartRateStatus(HeartRateState.OFF)
        elif self._link is None:
            status = HeartRateStatus(HeartRateState.DISCONNECTED)
        elif self._stale:
            status = HeartRateStatus(HeartRateState.STALE, self._link.device)
        else:
            status = HeartRateStatus(HeartRateState.CONNECTED, self._link.device)
        if status != self._reported:
            self._reported = status
            self._on_status(status)
