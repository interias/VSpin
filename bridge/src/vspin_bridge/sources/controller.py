"""Controller-Quelle: Zwift-Ride-Lenkercontroller per BLE (Spec #75, Rolle `controller` im Verbindungsfenster).

Dritte Rolle der Bridge neben Rad und Puls; keine `DeviceSource`, sondern eine kleine Schnittstelle nach dem Vorbild
der `HeartRateSource` (`sources/heart_rate.py`): verbinden, Gerätedatenbank prüfen, Batterie lesen, Verbindung halten.
Seit Spec #89 (Messteil) schreibt sie auf den Controller, aber **nur den Klartext-Handshake** und nur zum Messen: Sie
abonniert alles und protokolliert es roh; Tasten wertet sie nicht aus (ADR-0003, Nachtrag Spec #89).

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
- **Handshake** (Spec #89, clean-room nach der öffentlichen Prosa-Beschreibung des Zwift-Play-Protokolls, makinolo.com;
  ob der Ride V2 sie teilt, ist unbelegt): Nach dem Verbinden – nicht bei `locked` – abonniert die Quelle **zuerst** jede
  Characteristic mit `notify`/`indicate` der Zwift-Services (`0xFC82`, Legacy) aus der Gerätedatenbank
  (`BleConnection.characteristics`) und schreibt **dann einmal je Verbindung** `RideOn` (ASCII, nichts weiter) auf die
  beschreibbare – bevorzugt `…0003` (Control Point); ohne Antwort, wenn sie nur das kann. Nennt die Gerätedatenbank
  keine Characteristics dieser Services, gelten die der Beschreibung: `…0002` (Notify), `…0004` (Indicate), `…0003`
  (Write). Die Antwort ordnet sie als Hypothese ein (`Handshake`): Beginnt eine Notification/Indication mit `RideOn`,
  ist der Stand `encrypted`, wenn danach mindestens 64 Byte folgen (laut Beschreibung 2 Byte und ein öffentlicher
  Schlüssel), sonst `answered`; ohne Antwort binnen `handshake_timeout_s` (3 s) `no_answer`; nicht verbunden, gesperrt
  oder solange die Antwort aussteht `none`. Verlangte ein Gerät einmal Verschlüsselung, schreibt die Quelle in diesem
  Lauf nie wieder auf es, auch nicht nach dem Neuverbinden (der Stand bleibt `encrypted`).
- **Rohprotokoll** (Spec #89): `on_log` bekommt je Ereignis einen Eintrag ohne `t_ms` (den setzt der Besitzer):
  Verbinden, Trennen, `locked`, Services und Characteristics, Abos, das Schreiben, jede Notification/Indication der
  abonnierten Characteristics, der Handshake-Stand und Fehler. Die Bridge schreibt es nach `<zeit>.controller.jsonl`.
- **Zustand** `connected | locked | disconnected | off` mit Gerät, Batterie und Handshake-Stand; jede Änderung meldet
  `on_status` genau einmal.

**Suche auf Anfrage** teilt sich den einen Scanner mit der Hintergrundsuche (wie beim Puls). Suche und Verbindungen
führt allein eine Hintergrundaufgabe (`start`/`stop`); die öffentlichen Methoden setzen nur Wünsche und wecken sie.
"""

import asyncio
import contextlib
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace
from enum import StrEnum

from ..ble import Advertisement, BleAdapter, BleConnection, BleError, BleScan, GattCharacteristic

ZWIFT_COMPANY_ID = 0x094A
SIDE_RIGHT = 7  # erstes Nutzdatenbyte der Herstellerdaten
SIDE_LEFT = 8
CONTROLLER_NAME = "Zwift SF2"  # Ersatz, wenn die Herstellerdaten fehlen
RIDE_SERVICE = "0000fc82-0000-1000-8000-00805f9b34fb"
RIDE_SERVICE_LEGACY = "00000001-19ca-4651-86e5-fa29dcdd09d1"
BATTERY_LEVEL = "00002a19-0000-1000-8000-00805f9b34fb"
# Characteristics laut öffentlicher Beschreibung des Zwift-Play-Protokolls (Basis `0000000X-19ca-…`); Ersatz, wenn die
# Gerätedatenbank für die Zwift-Services keine nennt.
ZWIFT_MEASUREMENT = "00000002-19ca-4651-86e5-fa29dcdd09d1"  # Notify (Messwerte)
ZWIFT_CONTROL_POINT = "00000003-19ca-4651-86e5-fa29dcdd09d1"  # Write (Control Point)
ZWIFT_RESPONSE = "00000004-19ca-4651-86e5-fa29dcdd09d1"  # Indicate (Antworten)
RIDE_ON = b"RideOn"  # Klartext-Handshake
KEY_BYTES = 64  # öffentlicher Schlüssel in der Antwort eines Geräts mit Schlüsseltausch (Hypothese)

RETRY_S = 3.0  # Pause nach Abbruch oder gescheitertem Versuch (ADR-0004)
LOCKED_RETRY_S = 30.0  # Pause nach „gesperrt“: erst dann wieder verbinden
SEARCH_S = 30.0  # Dauer einer Suche auf Anfrage
HANDSHAKE_TIMEOUT_S = 3.0  # so lange wartet der Handshake auf eine Antwort

ControllerLog = Callable[[dict], None]  # ein Eintrag des Controller-Rohprotokolls (ohne `t_ms`)

_SIG_BASE = "-0000-1000-8000-00805f9b34fb"
_ZWIFT_BASE = "-19ca-4651-86e5-fa29dcdd09d1"


class Side(StrEnum):
    LEFT = "left"
    RIGHT = "right"


class ControllerState(StrEnum):
    CONNECTED = "connected"
    LOCKED = "locked"  # verbunden gewesen, Service versteckt: einmal in Zwift verbinden
    DISCONNECTED = "disconnected"  # Geräte gemerkt, keines verbunden, Hintergrundsuche läuft
    OFF = "off"  # keine Geräte gemerkt


class Handshake(StrEnum):
    """Stand des Klartext-Handshakes (Bus `status.controller.handshake`), als Hypothese abgeleitet (Spec #89)."""

    NONE = "none"  # nicht verbunden, gesperrt oder Antwort steht noch aus
    ANSWERED = "answered"  # Antwort beginnt mit `RideOn`, ohne Schlüsselmaterial
    ENCRYPTED = "encrypted"  # Antwort beginnt mit `RideOn` und trägt ≥ 64 Byte danach: verlangt Verschlüsselung
    NO_ANSWER = "no_answer"  # keine Antwort im Zeitlimit (oder das Schreiben scheiterte)


def classify_answer(data: bytes) -> Handshake | None:
    """Einordnung einer Notification/Indication als Antwort auf `RideOn`; `None`, wenn sie keine ist."""
    if not data.startswith(RIDE_ON):
        return None
    return Handshake.ENCRYPTED if len(data) - len(RIDE_ON) >= KEY_BYTES else Handshake.ANSWERED


def short_uuid(char: str) -> str:
    """Kurzform im Rohprotokoll: `0000fc82-0000-1000-8000-00805f9b34fb` → `fc82`,
    `00000002-19ca-4651-86e5-fa29dcdd09d1` → `0002`; andere UUIDs bleiben ganz."""
    if char.endswith(_SIG_BASE) or char.endswith(_ZWIFT_BASE):
        return char[4:8]
    return char


@dataclass(frozen=True, slots=True)
class ControllerDevice:
    address: str
    name: str
    side: Side | None = None


@dataclass(frozen=True, slots=True)
class ControllerStatus:
    """`device`: das verbundene (bei `locked` das zuletzt geprüfte) Gerät mit der tatsächlichen Adresse; `battery` in
    Prozent oder `None`; `handshake`: Stand des Handshakes (außer bei `connected` immer `none`)."""

    state: ControllerState
    device: ControllerDevice | None = None
    battery: int | None = None
    handshake: Handshake = Handshake.NONE


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


def _device_entry(device: ControllerDevice) -> dict:
    """Gerät im Rohprotokoll."""
    return {"address": device.address, "name": device.name, "side": None if device.side is None else str(device.side)}


class _Link:
    def __init__(self, rank: int, device: ControllerDevice, rssi: int | None) -> None:
        self.rank = rank
        self.device = device
        self.rssi = rssi
        self.connection: BleConnection | None = None
        self.alive = True
        self.handshake = Handshake.NONE
        self.handshake_timer: asyncio.TimerHandle | None = None
        self.disconnect_logged = False


def _cancel_timer(link: _Link) -> None:
    if link.handshake_timer is not None:
        link.handshake_timer.cancel()
        link.handshake_timer = None


class ControllerSource:
    def __init__(
        self,
        adapter: BleAdapter,
        on_status: Callable[[ControllerStatus], None],
        *,
        retry_s: float = RETRY_S,
        locked_retry_s: float = LOCKED_RETRY_S,
        search_s: float = SEARCH_S,
        handshake_timeout_s: float = HANDSHAKE_TIMEOUT_S,
    ) -> None:
        self._adapter = adapter
        self._on_status = on_status
        self._retry_s = retry_s
        self._locked_retry_s = locked_retry_s
        self._search_s = search_s
        self._handshake_timeout_s = handshake_timeout_s
        # Rohprotokoll (Spec #89): setzt der Besitzer (die Bridge schreibt es in die Session); ohne ihn nichts.
        self.on_log: ControllerLog | None = None
        self._encrypted: set[str] = set()  # Adressen, die Verschlüsselung verlangten: nie wieder schreiben

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
            self._log({"event": "connect", **_device_entry(device), "rssi": advertisement.rssi})
            services = link.connection.service_uuids
            locked = RIDE_SERVICE not in services and RIDE_SERVICE_LEGACY not in services
            chars = self._log_database(link.connection, services)
            battery = await self._read_battery(link.connection)
            if locked:
                self._log({"event": "locked", **_device_entry(device)})
            else:
                await self._handshake(link, chars)
        except BleError as error:
            link.alive = False
            self._log({"event": "error", "text": str(error)})
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

    def _log_database(self, connection: BleConnection, services: frozenset[str]) -> tuple[GattCharacteristic, ...]:
        """Services und Characteristics der Gerätedatenbank einmal je Verbindung ins Rohprotokoll; liefert die
        Characteristics (leer, wenn sie sich nicht lesen lassen)."""
        try:
            chars = connection.characteristics
        except BleError as error:
            chars = ()
            self._log({"event": "error", "text": str(error)})
        self._log(
            {
                "event": "services",
                "services": sorted(services),
                "chars": [
                    {"service": char.service, "char": char.uuid, "properties": sorted(char.properties)}
                    for char in chars
                ],
            }
        )
        return chars

    async def _handshake(self, link: _Link, chars: tuple[GattCharacteristic, ...]) -> None:
        """Erst alle Notify-/Indicate-Characteristics der Zwift-Services abonnieren, dann einmal `RideOn` schreiben.
        Die Antwort ordnet `_on_notify` ein, das Zeitlimit `_on_handshake_timeout`."""
        connection = link.connection
        assert connection is not None
        zwift = [char for char in chars if char.service in (RIDE_SERVICE, RIDE_SERVICE_LEGACY)]
        if zwift:
            subscribe = [char for char in zwift if {"notify", "indicate"} & char.properties]
            writable = [char for char in zwift if {"write", "write-without-response"} & char.properties]
            writable.sort(key=lambda char: char.uuid != ZWIFT_CONTROL_POINT)  # stabil: sonst die erste
            target = writable[0] if writable else None
        else:  # die Gerätedatenbank nennt keine: die Characteristics der Beschreibung
            subscribe = [
                GattCharacteristic(RIDE_SERVICE, ZWIFT_MEASUREMENT, frozenset({"notify"})),
                GattCharacteristic(RIDE_SERVICE, ZWIFT_RESPONSE, frozenset({"indicate"})),
            ]
            target = GattCharacteristic(RIDE_SERVICE, ZWIFT_CONTROL_POINT, frozenset({"write"}))
        for char in subscribe:
            kind = "notification" if "notify" in char.properties else "indication"
            try:
                await connection.subscribe(
                    char.uuid, lambda data, uuid=char.uuid, kind=kind: self._on_notify(link, uuid, kind, data)
                )
            except BleError as error:
                self._log({"event": "error", "text": str(error)})
                continue
            self._log({"event": "subscribe", "char": short_uuid(char.uuid), "kind": kind})
        if connection.address in self._encrypted:
            link.handshake = Handshake.ENCRYPTED
            self._log(
                {"event": "handshake", "state": str(link.handshake), "reason": "verlangte schon Verschlüsselung"}
            )
            return
        if target is None:
            self._log({"event": "error", "text": "keine beschreibbare Characteristic in den Zwift-Services"})
            self._set_handshake(link, Handshake.NO_ANSWER)
            return
        response = "write" in target.properties
        self._log({"event": "write", "char": short_uuid(target.uuid), "hex": RIDE_ON.hex(), "response": response})
        try:
            await connection.write(target.uuid, RIDE_ON, response=response)
        except BleError as error:
            self._log({"event": "error", "text": str(error)})
            self._set_handshake(link, Handshake.NO_ANSWER)
            return
        if link.handshake is Handshake.NONE:  # die Antwort kann schon vor der Quittung da sein
            link.handshake_timer = asyncio.get_running_loop().call_later(
                self._handshake_timeout_s, self._on_handshake_timeout, link
            )

    def _set_handshake(self, link: _Link, handshake: Handshake) -> None:
        link.handshake = handshake
        _cancel_timer(link)
        if handshake is Handshake.ENCRYPTED and link.connection is not None:
            self._encrypted.add(link.connection.address)
        self._log({"event": "handshake", "state": str(handshake)})
        if link is self._link:
            self._publish()

    async def _close(self, link: _Link) -> None:
        link.alive = False
        _cancel_timer(link)
        if link.connection is not None:
            with contextlib.suppress(BleError):
                await link.connection.disconnect()
            self._log_disconnect(link, "bridge")

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

    def _on_notify(self, link: _Link, char: str, kind: str, data: bytes) -> None:
        """Jede Notification/Indication ins Rohprotokoll; eine Antwort auf `RideOn` legt den Handshake-Stand fest
        (auch eine nach dem Zeitlimit)."""
        self._log({"event": kind, "char": short_uuid(char), "hex": data.hex()})
        answer = classify_answer(data)
        if answer is not None and link.alive and link.handshake in (Handshake.NONE, Handshake.NO_ANSWER):
            self._set_handshake(link, answer)

    def _on_handshake_timeout(self, link: _Link) -> None:
        link.handshake_timer = None
        if link.alive and link.handshake is Handshake.NONE:
            self._set_handshake(link, Handshake.NO_ANSWER)

    def _on_disconnect(self, link: _Link) -> None:
        self._log_disconnect(link, "device" if link.alive else "bridge")
        link.alive = False
        _cancel_timer(link)
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

    def _log(self, entry: dict) -> None:
        if self.on_log is not None:
            self.on_log(entry)

    def _log_disconnect(self, link: _Link, by: str) -> None:
        """Trennen genau einmal je Verbindung ins Rohprotokoll; `by`: `bridge` (selbst getrennt) oder `device`."""
        if not link.disconnect_logged:
            link.disconnect_logged = True
            self._log({"event": "disconnect", **_device_entry(link.device), "by": by})

    def _end_search(self) -> None:
        if self._search_timer is not None:
            self._search_timer.cancel()
            self._search_timer = None
        self._search_receiver = None

    def _publish(self) -> None:
        if not self._known:
            status = ControllerStatus(ControllerState.OFF)
        elif self._link is not None:
            status = ControllerStatus(ControllerState.CONNECTED, self._link.device, self._battery, self._link.handshake)
        elif self._locked is not None:
            status = self._locked
        else:
            status = ControllerStatus(ControllerState.DISCONNECTED)
        if status != self._reported:
            self._reported = status
            self._on_status(status)
