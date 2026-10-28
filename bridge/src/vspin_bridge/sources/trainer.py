"""Trainerquelle: Rad-Trainer (z. B. Wahoo KICKR CORE 2) per BLE Fitness Machine Service `0x1826`
(Spec #75, ADR-0003, ADR-0004).

Eine `DeviceSource` mit Bus-`source` = `ble`, hinter der BLE-Nahtstelle `ble/` (bleak, in Tests der Fake).
Sie liest den Trainer und steuert ihn über den Control Point `0x2AD9`, wenn er Indoor Bike Simulation kann (unten).

- **Suche:** nach FTMS `0x1826` und Cycling Power `0x1818` zugleich (ein Trainer kündigt beides an). Mit
  Adresse (`--trainer`) gilt nur dieses Gerät, sonst das stärkste Gerät mit FTMS, ersatzweise das stärkste
  mit Cycling Power. Ohne Adresse sammelt die Suche nach dem ersten Fund noch `settle_s`, damit ein
  stärkeres Gerät, das etwas später sendet, gewinnt.
- **Verbinden:** `0x2ACC` (Features) lesen; daraus kommen die Capabilities: `SPEED` immer (Indoor Bike Data
  hat das Tempo), `POWER` und `CADENCE` laut Features. Danach `0x2AD2` abonnieren. Kadenz kommt aus `0x2AD2`;
  fehlt sie dort – laut Features oder in den ersten `NO_CADENCE_AFTER` Notifications –, kommt Cycling Power
  Measurement `0x2A63` (Kurbeldaten) dazu. Ein Gerät nur mit Cycling Power (kein FTMS) liefert Leistung und
  Kadenz aus `0x2A63` allein.
- **Rohdaten:** Jede Notification geht roh (`RawNotification`, Bridge-Zeit) an die Bridge und damit in die
  Session-Rohdatei (ADR-0008) – dasselbe Format wie beim Replay.
- **Abbruch:** Reißt die Verbindung ab oder ist der Trainer beim Start nicht da, wirft die Quelle
  `SourceDisconnectedError`; die Bridge meldet `disconnected` und ruft alle 3 s `connect` neu auf (ADR-0004).
- **Gemessene Watt:** `power_estimated = False` – die Bridge legt den `Decoder` danach an.

Widerstand (ADR-0007, Nachtrag Spec #75; Bausteine in `trainer_control.py`):
- **Übernehmen:** Melden die Target Setting Features (`0x2ACC`, zweites `uint32`) Indoor Bike Simulation (Bit 13) und
  lässt sich `0x2AD9` abonnieren, kommt `RESISTANCE_CONTROL` dazu. Dann im Verbinden: `0x2ADA` abonnieren,
  `0x00` Request Control → Antwort, `0x07` Start → Antwort; danach ist die Steuerung `active`, und eine schon gemeldete
  Steigung geht sofort als `0x11` hinterher (auch nach jedem Neuverbinden). Scheitert das Übernehmen, liest die Quelle
  trotzdem weiter (Zustand `lost`, `not_supported` oder `error`).
- **`set_grade`:** `0x11` mit der Steigung, gedrosselt gegenüber dem zuletzt **geschriebenen** Wert: nur bei einer
  Änderung ab `GRADE_STEP` (0,1 %) und höchstens alle `GRADE_INTERVAL_S` (2 Hz). Eine gedrosselte Änderung holt die
  Quelle nach Ablauf des Intervalls mit dem dann aktuellen Wert nach; der Endwert geht nie verloren.
- **Kontrollverlust:** `0x2ADA` `0xFF` (Control Permission Lost) oder `0x01` (Reset durch jemand anderen) oder eine
  Antwort `0x05` → `lost`. Ab dann schreibt die Quelle nichts mehr, bis der Trainer neu verbunden ist; erst dann fordert
  sie die Steuerung neu an (Regel: angefordert wird nur beim Verbinden oder auf „Steuerung zurückholen“, unten – nie
  im Streit mit einer anderen App).
- **Grundlast:** `reset_grade()` (Bridge: alle Clients weg oder der Client der letzten Steigung weg) schreibt sofort
  Steigung 0, `release()` (Bridge endet) Steigung 0 und danach `0x01` Reset, der die Steuerung zurückgibt – beide nie
  gedrosselt. `release()` gibt auch nach `error` frei, wenn `0x00` in dieser Verbindung bestätigt war, nie nach `lost`.
  Ab `release()` schreibt weder `set_grade` noch das Nachholen etwas, auch wenn das Reset scheitert.
- **Nur lesen** (`read_only`, CLI `--read-only`): kein Abo von `0x2AD9`, keine Anforderung, kein Schreibzugriff;
  `set_grade` → `ControlRefusedError("read_only")`.
- Stand der Steuerung in `control` (`ControlState`); jede Änderung meldet `on_control_changed(state, grund)`.
- **Steuerung zurückholen** (`reclaim_control()`, Knopf im Verbindungsfenster): nach `lost` oder `error` nur auf einen
  Klick des Fahrers – `0x00`, `0x07` und die letzte Steigung wie beim Verbinden. Von selbst fordert die Quelle nie neu an.

Verbindungsfenster (Spec #75, Rolle `trainer`):
- **Gemerkte Trainer** (`set_known_devices`, vom Spiel über `set_devices`): Sobald eine Liste gesetzt ist, gilt nur sie –
  die Suche nimmt das stärkste gemerkte Gerät, das sendet (FTMS vor Cycling Power); eine leere Liste heißt: keiner, bis
  eine Liste mit Geräten kommt. Ohne jede Liste gilt das Verhalten von oben (`--trainer` oder das stärkste Gerät); mit
  `known_only` (CLI `--known-trainers`, Start aus dem Spiel) wartet die Quelle von Anfang an auf die Liste. Fällt der
  verbundene Trainer aus der Liste, gibt die Quelle ihn frei (`release()`: Steigung 0, Reset) und trennt; danach
  verbindet die Bridge neu, mit dem neuen.
- **Suche auf Anfrage** (`start_search`): ein eigener Scanner nach FTMS und Cycling Power für die angegebene Dauer;
  jede Ankündigung geht an den Empfänger, auch nicht gemerkte. Verbindungen berührt sie nicht.
- **Gerät:** `device` (Adresse, Name) und `rssi` (Signalstärke der Ankündigung vor dem Verbinden), solange verbunden.
"""

import asyncio
import contextlib
import math
from collections.abc import AsyncIterator, Callable, Iterable, Sequence
from dataclasses import dataclass

from ..ble import Advertisement, BleAdapter, BleConnection, BleError
from ..clock import bridge_time_ms
from ..parsers import (
    CYCLING_POWER_MEASUREMENT,
    FITNESS_MACHINE_FEATURE,
    INDOOR_BIKE_DATA,
    ParseError,
    parse_fitness_machine_features,
)
from ..parsers.ftms import parse_indoor_bike_data
from .base import Capability, ControlRefusedError, NotSupportedError, RawNotification, SourceDisconnectedError
from .trainer_control import (
    MACHINE_STATUS,
    OP_REQUEST_CONTROL,
    OP_RESET,
    OP_SIMULATION,
    OP_START,
    RESPONSE_TIMEOUT_S,
    RESULT_CONTROL_NOT_PERMITTED,
    RESULT_NOT_SUPPORTED,
    STATUS_CONTROL_PERMISSION_LOST,
    STATUS_RESET,
    ControlPoint,
    ControlPointError,
    ControlState,
    simulation_parameters,
)

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
CYCLING_POWER_SERVICE = "00001818-0000-1000-8000-00805f9b34fb"

SCAN_S = 10.0  # so lange sucht ein Verbindungsversuch, dann gilt der Trainer als nicht da
SETTLE_S = 1.0  # nach dem ersten Fund ohne Adresse: so lange noch auf ein stärkeres Gerät warten
NO_CADENCE_AFTER = 3  # so viele 0x2AD2-Notifications ohne Kadenzfeld, dann kommt 0x2A63 dazu

GRADE_STEP = 0.001  # Drosselung: neue Steigung erst ab 0,1 % Abstand zum zuletzt geschriebenen Wert …
GRADE_INTERVAL_S = 0.5  # … und höchstens alle 0,5 s (2 Hz)

_LOST = object()  # Marke in der Warteschlange: die Verbindung ist weg


@dataclass(frozen=True, slots=True)
class TrainerDevice:
    address: str
    name: str


class TrainerSource:
    name = "ble"
    power_estimated = False  # der Trainer misst die Leistung (ADR-0004, Nachtrag Spec #75)

    def __init__(
        self,
        adapter: BleAdapter,
        address: str | None = None,
        *,
        scan_s: float = SCAN_S,
        settle_s: float = SETTLE_S,
        read_only: bool = False,
        response_timeout_s: float = RESPONSE_TIMEOUT_S,
        grade_interval_s: float = GRADE_INTERVAL_S,
        known_only: bool = False,
    ) -> None:
        self._adapter = adapter
        self._address = address
        # Gemerkte Trainer (Verbindungsfenster): None = noch keine Liste (Verhalten ohne Spiel), [] = keiner.
        self._known: list[TrainerDevice] | None = [] if known_only else None
        self._known_changed = asyncio.Event()
        self.device: TrainerDevice | None = None  # verbundener Trainer
        self.rssi: int | None = None  # Signalstärke seiner Ankündigung vor dem Verbinden
        self._search: asyncio.Task[None] | None = None  # Suche auf Anfrage
        self._scan_s = scan_s
        self._settle_s = settle_s
        self._read_only = read_only
        self._response_timeout_s = response_timeout_s
        self._grade_interval_s = grade_interval_s
        # Steuerung (Spec #75): Stand, Rückrufe der Bridge (Bus-`status`, Terminal), Control Point der Verbindung.
        self.control = ControlState.READ_ONLY if read_only else ControlState.NONE
        self.on_control_changed: Callable[[ControlState, str], None] = lambda state, reason: None
        self.on_info: Callable[[str], None] = lambda text: None
        self._control_point: ControlPoint | None = None
        self._grade: float | None = None  # zuletzt gemeldete Steigung – wird nach dem (Neu-)Verbinden nachgesendet
        self._written: float | None = None  # zuletzt an den Trainer geschriebene Steigung (dieser Verbindung)
        self._written_at = -math.inf  # Loop-Zeit des letzten Schreibens von 0x11
        self._catch_up: asyncio.Task[None] | None = None  # Nachholen einer gedrosselten Änderung
        self._releasing = False  # `release()` läuft: eigenes Reset ist kein Kontrollverlust, kein `set_grade` mehr
        self._granted = False  # `0x00` in dieser Verbindung bestätigt: der Trainer führt VSpin als Steuerer
        # Vor der ersten Verbindung ist nur die Kadenz sicher (ADR-0004: einziger Game-Input); nach dem
        # Verbinden stehen hier die Fähigkeiten laut Features.
        self.capabilities: set[Capability] = {Capability.CADENCE}
        self._connection: BleConnection | None = None
        self._queue: asyncio.Queue[object] = asyncio.Queue()
        self._cycling_power = False  # 0x2A63 ist abonniert
        self._cycling_power_available = False  # das Gerät hat den Cycling Power Service
        self._bike_without_cadence = 0
        self._cadence_seen = False

    async def connect(self) -> None:
        """Sucht den Trainer, verbindet, liest die Features und abonniert. Wirft `SourceDisconnectedError`,
        wenn kein Trainer da ist oder etwas scheitert. Mit leerer Liste gemerkter Trainer wartet es auf eine Liste."""
        found = await self._find()
        address = found.address
        queue: asyncio.Queue[object] = asyncio.Queue()
        self._queue = queue
        self._cycling_power = False
        self._bike_without_cadence = 0
        self._cadence_seen = False
        self._releasing = False
        self._granted = False
        connection: BleConnection | None = None
        control_point: ControlPoint | None = None

        def on_disconnect() -> None:
            queue.put_nowait(_LOST)
            self._end_control(queue, control_point)  # eine offene Anfrage scheitert sofort, nicht erst am Zeitlimit

        try:
            connection = await self._adapter.connect(address, on_disconnect)
            self.device = TrainerDevice(address, self._device_name(found))
            self.rssi = found.rssi
            services = connection.service_uuids
            self._cycling_power_available = CYCLING_POWER_SERVICE in services
            if FTMS_SERVICE in services:
                features = parse_fitness_machine_features(await connection.read(FITNESS_MACHINE_FEATURE))
                capabilities = {Capability.SPEED}
                if features.power:
                    capabilities.add(Capability.POWER)
                if features.cadence or self._cycling_power_available:
                    capabilities.add(Capability.CADENCE)
                self.capabilities = capabilities
                await self._subscribe(connection, queue, INDOOR_BIKE_DATA)
                if not features.cadence and self._cycling_power_available:
                    await self._subscribe_cycling_power(connection, queue)
                if not features.simulation:
                    self._set_control(ControlState.NOT_SUPPORTED, "Trainer meldet keine Indoor Bike Simulation")
                elif not self._read_only:
                    control_point = ControlPoint(connection, self._response_timeout_s)
                    await self._take_control(connection, control_point)
            elif self._cycling_power_available:
                # Leistungsmesser ohne FTMS: Leistung und Kadenz kommen allein aus 0x2A63.
                self.capabilities = {Capability.POWER, Capability.CADENCE}
                await self._subscribe_cycling_power(connection, queue)
                self._set_control(ControlState.NOT_SUPPORTED, "Gerät ohne FTMS")
            else:
                raise BleError(f"{address} hat weder FTMS noch Cycling Power")
        except (BleError, ParseError) as exc:
            self._forget_device()
            self._end_control(queue, control_point)
            await self._close(connection)
            raise SourceDisconnectedError(f"Trainer {address}: {exc}") from exc
        except BaseException:  # abgebrochen (Bridge endet) mitten im Verbinden: nichts offen lassen
            self._forget_device()
            self._end_control(queue, control_point)
            await self._close(connection)
            raise
        if not self._wanted(address):  # während des Verbindens aus der Liste gefallen: freigeben, nicht nutzen
            with contextlib.suppress(Exception):
                await self.release()
            self._forget_device()
            self._end_control(queue, control_point)
            await self._close(connection)
            raise SourceDisconnectedError(f"Trainer {address} nicht mehr gemerkt")
        self._connection = connection

    async def samples(self) -> AsyncIterator[RawNotification]:
        """Rohe Notifications, bis die Verbindung abreißt (dann `SourceDisconnectedError`)."""
        connection, queue, control_point = self._connection, self._queue, self._control_point
        if connection is None:
            raise SourceDisconnectedError("nicht verbunden")
        try:
            while True:
                item = await queue.get()
                if item is _LOST:
                    raise SourceDisconnectedError("Verbindung zum Trainer abgebrochen")
                assert isinstance(item, RawNotification)
                if item.char == INDOOR_BIKE_DATA:
                    await self._watch_cadence(connection, queue, item)
                yield item
        finally:
            if self._connection is connection:
                self._connection = None
                self._forget_device()
            self._end_control(queue, control_point)
            await self._close(connection)

    async def set_grade(self, grade: float) -> None:
        """Steigung an den Trainer (gedrosselt, siehe oben). Wirft `ControlRefusedError` (`read_only`,
        `control_lost`), `NotSupportedError` (Trainer kann keine Simulation oder antwortet `0x02`), `ControlPointError`
        (andere Antwort, keine Antwort), `BleError`, `ValueError` (Steigung nicht darstellbar) oder `RuntimeError`
        (gerade keine Steuerung, z. B. nicht verbunden – die Steigung folgt dann nach dem Verbinden)."""
        simulation_parameters(grade)  # nicht darstellbar → ValueError, bevor sie als Ziel gilt
        self._grade = grade
        if self._read_only:
            raise ControlRefusedError("read_only", "Nur-lesen-Modus (--read-only): VSpin steuert den Trainer nicht")
        if self.control is ControlState.LOST:
            raise ControlRefusedError("control_lost", "eine andere App steuert den Trainer")
        if self._releasing:  # nach der Grundlast beim Beenden nichts mehr, auch wenn das Reset noch aussteht
            raise RuntimeError("Bridge endet: Trainer wird freigegeben")
        if self.control is not ControlState.ACTIVE or self._control_point is None:
            if Capability.RESISTANCE_CONTROL not in self.capabilities:
                raise NotSupportedError("Der Trainer nimmt keine Steigung an (Capability RESISTANCE_CONTROL fehlt)")
            raise RuntimeError(f"Trainer gerade nicht gesteuert ({self.control})")
        if self._written is not None and abs(grade - self._written) < GRADE_STEP - 1e-9:
            return  # unter der Schwelle: am Trainer ändert sich nichts
        wait_s = self._written_at + self._grade_interval_s - asyncio.get_running_loop().time()
        if wait_s > 0:
            if self._catch_up is None:
                self._catch_up = asyncio.create_task(self._catch_up_after(wait_s))
            return  # gedrosselt: das Nachholen schreibt den dann aktuellen Wert
        self._cancel_catch_up()
        await self._write_grade(grade)

    async def reset_grade(self) -> bool:
        """Sichere Grundlast (Bridge: alle Clients weg): sofort Steigung 0, nie gedrosselt. `True`, wenn sie an den
        Trainer ging; ohne aktive Steuerung wird sie nur das Ziel fürs nächste Verbinden. Wirft wie `set_grade`."""
        self._grade = 0.0
        self._cancel_catch_up()
        if self.control is not ControlState.ACTIVE or self._control_point is None:
            return False
        await self._write_grade(0.0)
        return True

    async def release(self) -> None:
        """Beim Beenden der Bridge, vor dem Trennen: Steigung 0, dann `0x01` Reset (gibt die Steuerung zurück) – beides
        nie gedrosselt. Auch ohne `active`, wenn `0x00` in dieser Verbindung bestätigt wurde (z. B. `error`, weil `0x07`
        scheiterte): dann Steigung 0 nur, falls eine geschrieben wurde, und das Reset. Bei `lost` nichts (eine andere App
        steuert), ebenso ohne Verbindung. Wirft `RuntimeError` mit den Fehlern, versucht aber beides."""
        self._cancel_catch_up()
        control_point = self._control_point
        active = self.control is ControlState.ACTIVE
        if control_point is None or self.control is ControlState.LOST or not (active or self._granted):
            return
        self._releasing = True
        errors = []
        if active or self._written is not None:
            try:
                await self._write_grade(0.0)
            except Exception as exc:  # Reset trotzdem versuchen
                errors.append(f"Steigung 0: {exc}")
        # `0x05` auf die Steigung 0: die Steuerung hat jetzt eine andere App; Verbindung weg: nichts mehr zu senden
        if self.control is not ControlState.LOST and not control_point.closed:
            try:
                await control_point.request(OP_RESET)
            except (ControlPointError, BleError) as exc:
                errors.append(f"Reset: {exc}")
            else:
                self._granted = False
                self._set_control(ControlState.NONE, "Steuerung zurückgegeben (Reset)")
        if errors:
            raise RuntimeError("; ".join(errors))

    async def reclaim_control(self) -> None:
        """Steuerung zurückholen (Knopf „Steuerung zurückholen“, Bus `reclaim_trainer_control`): nur auf den Klick des
        Fahrers, gedacht nach `lost` oder `error`. Fordert `0x00`/`0x07` neu an und sendet die letzte Steigung nach –
        nach denselben Regeln wie beim Verbinden. Steuert VSpin schon (`active`, `requesting`), passiert nichts. Wirft
        `ControlRefusedError` (`read_only`; `control_lost`, wenn der Trainer wieder ablehnt), `NotSupportedError` oder
        `RuntimeError` (nicht verbunden, Freigabe läuft, Übernehmen gescheitert)."""
        if self._read_only:
            raise ControlRefusedError("read_only", "Nur-lesen-Modus (--read-only): VSpin steuert den Trainer nicht")
        if self._releasing:
            raise RuntimeError("Trainer wird freigegeben")
        if self.control is ControlState.NOT_SUPPORTED:
            raise NotSupportedError("Der Trainer nimmt keine Steigung an")
        control_point = self._control_point
        if control_point is None or control_point.closed or self._connection is None:
            raise RuntimeError(f"Trainer gerade nicht verbunden ({self.control})")
        if self.control in (ControlState.ACTIVE, ControlState.REQUESTING):
            return
        self.on_info("Steuerung zurückholen: fordere die Steuerung neu an")
        await self._request_control(control_point)
        if self.control is ControlState.ACTIVE:
            return
        if self.control is ControlState.LOST:
            raise ControlRefusedError("control_lost", "der Trainer verweigert die Steuerung (eine andere App steuert)")
        if self.control is ControlState.NOT_SUPPORTED:
            raise NotSupportedError("Der Trainer nimmt keine Steigung an")
        raise RuntimeError(f"Steuerung nicht übernommen ({self.control})")

    # --- Verbindungsfenster --------------------------------------------------------------

    async def set_known_devices(self, devices: Sequence[TrainerDevice]) -> None:
        """Gemerkte Trainer (Spiel über `set_devices`); ab jetzt gilt nur diese Liste, leer = keiner. Fällt der verbundene
        Trainer heraus: erst freigeben (Steigung 0, Reset), dann trennen – die Bridge verbindet danach neu."""
        self._known = list(devices)
        self._known_changed.set()
        connection = self._connection
        if connection is None or self._wanted(connection.address):
            return
        self.on_info(f"Trainer {connection.address} nicht mehr gemerkt: Freigabe, dann Wechsel")
        try:
            await self.release()
        except Exception as exc:  # trotzdem trennen: der Trainer gehört nicht mehr zur Fahrt
            self.on_info(f"Trainer beim Wechsel nicht freigegeben: {exc}")
        await self._close(connection)

    @property
    def searching(self) -> bool:
        """Läuft gerade eine Suche auf Anfrage?"""
        return self._search is not None and not self._search.done()

    def start_search(self, on_found: Callable[[Advertisement], None], duration_s: float | None = None) -> None:
        """Suche auf Anfrage nach Trainern (FTMS, Cycling Power): `on_found` bekommt jede Ankündigung, bis `duration_s`
        (Standard `scan_s`) um ist oder `stop_search` kommt; ein neuer Aufruf ersetzt eine laufende Suche."""
        self.stop_search()
        duration = self._scan_s if duration_s is None else duration_s
        self._search = asyncio.create_task(self._run_search(on_found, duration), name="trainer-search")

    def stop_search(self) -> None:
        if self._search is not None:
            self._search.cancel()
            self._search = None

    async def _run_search(self, on_found: Callable[[Advertisement], None], duration_s: float) -> None:
        scan = None
        try:
            scan = await self._adapter.start_scan(on_found, services=[FTMS_SERVICE, CYCLING_POWER_SERVICE])
            await asyncio.sleep(duration_s)
        except BleError as exc:  # z. B. ohne Bluetooth: die Suche endet am Zeitlimit ohne Treffer
            self.on_info(f"Trainersuche nicht möglich: {exc}")
        finally:
            if scan is not None:
                with contextlib.suppress(BleError):
                    await scan.stop()

    def _wanted(self, address: str) -> bool:
        """Kommt dieser Trainer in Frage? Mit Liste nur ein gemerkter, sonst `--trainer` bzw. jeder."""
        if self._known is None:
            return self._address is None or address.lower() == self._address.lower()
        return any(known.address.lower() == address.lower() for known in self._known)

    def _device_name(self, advertisement: Advertisement) -> str:
        for known in self._known or ():
            if known.address.lower() == advertisement.address.lower() and known.name:
                return known.name
        return advertisement.name or ""

    def _forget_device(self) -> None:
        self.device = None
        self.rssi = None

    # --- Steuerung -----------------------------------------------------------------------

    async def _take_control(self, connection: BleConnection, control_point: ControlPoint) -> None:
        """Steuerung übernehmen (im Verbinden). Scheitert es, bleibt die Verbindung zum Lesen (nur `BleError` beim
        Abo von `0x2ADA` ist egal, Abbruch geht weiter)."""
        try:
            await control_point.subscribe()  # Indications vor dem ersten Schreiben (sonst lehnt der Trainer ab)
        except BleError as exc:
            self._set_control(ControlState.NOT_SUPPORTED, f"Control Point nicht abonnierbar: {exc}")
            return
        self.capabilities.add(Capability.RESISTANCE_CONTROL)
        self._control_point = control_point
        with contextlib.suppress(BleError):  # Machine Status ist optional; ohne ihn meldet sich ein Verlust per 0x05
            await connection.subscribe(MACHINE_STATUS, lambda data: self._on_machine_status(control_point, data))
        await self._request_control(control_point)

    async def _request_control(self, control_point: ControlPoint) -> None:
        """`0x00` Request Control, `0x07` Start, danach die letzte Steigung – im Verbinden und beim Zurückholen."""
        self._set_control(ControlState.REQUESTING, "fordere die Steuerung an")
        try:
            await control_point.request(OP_REQUEST_CONTROL)
            self._granted = True  # scheitert gleich `0x07`, gibt `release()` die Steuerung trotzdem zurück
            await control_point.request(OP_START)
        except ControlPointError as exc:
            if exc.result == RESULT_NOT_SUPPORTED:
                self.capabilities.discard(Capability.RESISTANCE_CONTROL)
                self._set_control(ControlState.NOT_SUPPORTED, str(exc))
            elif exc.result == RESULT_CONTROL_NOT_PERMITTED:
                self._lose(control_point, str(exc))
            else:
                self._set_control(ControlState.ERROR, str(exc))
            return
        except BleError as exc:  # z. B. Windows ohne gebondetes Pairing: lesen geht, schreiben nicht
            self._set_control(ControlState.ERROR, f"Control Point nicht beschreibbar: {exc}")
            return
        self._set_control(ControlState.ACTIVE, "VSpin steuert den Trainer")
        # zuletzt gemeldete Steigung nachsenden (Neuverbinden) – nicht, wenn `release()` schon läuft (`0x07` kam spät)
        if self._grade is not None and not self._releasing:
            try:
                await self._write_grade(self._grade)
            except Exception as exc:  # Steuerung steht; der Fehler gehört ins Terminal (lost meldet der Zustand)
                self.on_info(f"Steigung {self._grade * 100:+.1f} % nach dem Verbinden nicht gesetzt: {exc}")

    async def _write_grade(self, grade: float) -> None:
        """`0x11` mit `grade`, ohne Drosselung. `0x05` → Kontrollverlust (`ControlRefusedError`)."""
        control_point = self._control_point
        if control_point is None:
            raise RuntimeError("Trainer gerade nicht gesteuert")
        self._written_at = asyncio.get_running_loop().time()  # vor dem Warten: gleichzeitige Aufrufe drosseln
        try:
            await control_point.request(OP_SIMULATION, simulation_parameters(grade))
        except ControlPointError as exc:
            if exc.result == RESULT_CONTROL_NOT_PERMITTED:
                self._lose(control_point, str(exc))
                raise ControlRefusedError("control_lost", str(exc)) from exc
            if exc.result == RESULT_NOT_SUPPORTED:
                raise NotSupportedError(str(exc)) from exc
            raise
        if control_point is self._control_point:
            self._written = grade

    async def _catch_up_after(self, delay_s: float) -> None:
        """Gedrosselte Änderung nachholen: nach `delay_s` den dann aktuellen Wert schreiben (falls er weit genug weg
        ist). Fehler gehen ins Terminal – einen Client, der ein `ack` bekäme, gibt es hier nicht."""
        await asyncio.sleep(delay_s)
        self._catch_up = None
        grade = self._grade
        if grade is None or self._releasing or self.control is not ControlState.ACTIVE:
            return
        if self._written is not None and abs(grade - self._written) < GRADE_STEP - 1e-9:
            return
        try:
            await self._write_grade(grade)
        except Exception as exc:
            self.on_info(f"set_grade {grade:+.3f} nachgeholt -> {exc}")

    def _cancel_catch_up(self) -> None:
        if self._catch_up is not None:
            self._catch_up.cancel()
            self._catch_up = None

    def _on_machine_status(self, control_point: ControlPoint, data: bytes) -> None:
        if control_point is not self._control_point or not data or self._releasing:
            return  # Nachzügler einer alten Verbindung bzw. das eigene Reset beim Beenden
        if data[0] == STATUS_CONTROL_PERMISSION_LOST:
            self._lose(control_point, "Machine Status: Control Permission Lost (0xFF)")
        elif data[0] == STATUS_RESET:
            self._lose(control_point, "Machine Status: Reset (0x01) durch eine andere App")

    def _lose(self, control_point: ControlPoint, reason: str) -> None:
        """Eine andere App steuert: ab jetzt kein Schreiben mehr bis zum Neuverbinden."""
        if control_point is not self._control_point:
            return
        self._granted = False  # auch bei `error`: `release()` funkt nicht in die fremde Steuerung
        if self.control in (ControlState.REQUESTING, ControlState.ACTIVE):
            self._cancel_catch_up()
            self._set_control(ControlState.LOST, reason)

    def _end_control(self, queue: asyncio.Queue[object], control_point: ControlPoint | None) -> None:
        """Verbindung weg: Control Point schließen (eine offene Anfrage scheitert), Nachholen abbrechen, Zustand `none`.
        Nur für die aktuelle Verbindung (`queue`); ein Nachzügler einer alten Verbindung ändert nichts. Ein Trainer ohne
        Simulation bleibt `not_supported` – das ändert ein Abbruch nicht (kein `status` je Neuverbinden)."""
        if control_point is not None:
            control_point.close()
        if queue is not self._queue:
            return
        if self._control_point is control_point:
            self._control_point = None
        self._cancel_catch_up()
        self._written = None
        if self.control is not ControlState.NOT_SUPPORTED:
            self._set_control(ControlState.NONE, "Trainer nicht verbunden")

    def _set_control(self, state: ControlState, reason: str) -> None:
        if self._read_only or state is self.control:
            return  # im Nur-lesen-Modus bleibt es `read_only`
        self.control = state
        self.on_control_changed(state, reason)

    # --- Hilfen --------------------------------------------------------------------------

    async def _find(self) -> Advertisement:
        """Ankündigung des Trainers; wirft `SourceDisconnectedError`, wenn nach `scan_s` keiner gesendet hat. Mit leerer
        Liste gemerkter Trainer wartet es zuerst, bis eine Liste mit Geräten kommt."""
        while self._known is not None and not self._known:
            self._known_changed.clear()
            await self._known_changed.wait()
        seen: dict[str, Advertisement] = {}
        found = asyncio.Event()

        def on_found(advertisement: Advertisement) -> None:
            if self._wanted(advertisement.address):
                seen[advertisement.address] = advertisement
                found.set()

        try:
            scan = await self._adapter.start_scan(on_found, services=[FTMS_SERVICE, CYCLING_POWER_SERVICE])
        except BleError as exc:
            raise SourceDisconnectedError(f"Suche nach dem Trainer nicht möglich: {exc}") from exc
        try:
            try:
                await asyncio.wait_for(found.wait(), self._scan_s)
            except TimeoutError:
                what = "Trainer" if self._address is None else f"Trainer {self._address}"
                if self._known is not None:
                    what = "Gemerkter Trainer"
                raise SourceDisconnectedError(
                    f"{what} nicht gefunden (ist er an und von Zwift, der Hersteller-App o. Ä. getrennt?)"
                ) from None
            # ohne Adresse bzw. mit mehreren gemerkten: noch kurz auf ein stärkeres Gerät warten
            if (self._known is None and self._address is None) or (self._known is not None and len(self._known) > 1):
                await asyncio.sleep(self._settle_s)
        finally:
            with contextlib.suppress(BleError):
                await scan.stop()
        candidates = [advertisement for advertisement in seen.values() if self._wanted(advertisement.address)]
        if not candidates:  # die Liste hat sich während der Suche geändert
            raise SourceDisconnectedError("gemerkter Trainer nicht mehr in der Liste")
        return _strongest(candidates)

    async def _subscribe(self, connection: BleConnection, queue: asyncio.Queue[object], char: str) -> None:
        await connection.subscribe(char, lambda data: queue.put_nowait(RawNotification(bridge_time_ms(), char, data)))

    async def _subscribe_cycling_power(self, connection: BleConnection, queue: asyncio.Queue[object]) -> None:
        await self._subscribe(connection, queue, CYCLING_POWER_MEASUREMENT)
        self._cycling_power = True

    async def _watch_cadence(
        self, connection: BleConnection, queue: asyncio.Queue[object], raw: RawNotification
    ) -> None:
        """Zählt 0x2AD2-Notifications ohne Kadenz; bleibt die Kadenz aus, abonniert die Quelle 0x2A63 nach.
        Scheitert das, ist es ein Abbruch: die Bridge verbindet neu."""
        if self._cadence_seen or self._cycling_power or not self._cycling_power_available:
            return
        try:
            cadence = parse_indoor_bike_data(raw.data).cadence_rpm
        except ParseError:
            return  # kaputt: zählt nicht (die Bridge meldet es)
        if cadence is not None:
            self._cadence_seen = True
            return
        self._bike_without_cadence += 1
        if self._bike_without_cadence >= NO_CADENCE_AFTER:
            try:
                await self._subscribe_cycling_power(connection, queue)
            except BleError as exc:
                raise SourceDisconnectedError(f"Cycling Power nicht abonniert: {exc}") from exc

    @staticmethod
    async def _close(connection: BleConnection | None) -> None:
        if connection is not None:
            with contextlib.suppress(BleError):
                await connection.disconnect()


def _strongest(found: Iterable[Advertisement]) -> Advertisement:
    """Stärkstes Gerät mit FTMS, ersatzweise das stärkste mit Cycling Power."""
    devices = list(found)
    with_ftms = [device for device in devices if FTMS_SERVICE in device.service_uuids]
    return max(with_ftms or devices, key=lambda device: device.rssi)
