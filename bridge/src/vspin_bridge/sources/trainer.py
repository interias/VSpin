"""Trainerquelle: Rad-Trainer (z. B. Wahoo KICKR CORE 2) per BLE Fitness Machine Service `0x1826`
(Spec #75, ADR-0003, ADR-0004).

Eine `DeviceSource` mit Bus-`source` = `ble`, hinter der BLE-Nahtstelle `ble/` (bleak, in Tests der Fake).
Sie liest nur; Schreibzugriffe auf den Trainer (Control Point `0x2AD9`) gibt es hier nicht.

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

Andockpunkt Widerstandssteuerung (ADR-0007): `connect` hält die Verbindung in `self._connection`; dort kommen
der Control Point und die Capability `RESISTANCE_CONTROL` hinzu, `set_grade` setzt dann um.
"""

import asyncio
import contextlib
from collections.abc import AsyncIterator, Iterable

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
from .base import Capability, NotSupportedError, RawNotification, SourceDisconnectedError

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
CYCLING_POWER_SERVICE = "00001818-0000-1000-8000-00805f9b34fb"

SCAN_S = 10.0  # so lange sucht ein Verbindungsversuch, dann gilt der Trainer als nicht da
SETTLE_S = 1.0  # nach dem ersten Fund ohne Adresse: so lange noch auf ein stärkeres Gerät warten
NO_CADENCE_AFTER = 3  # so viele 0x2AD2-Notifications ohne Kadenzfeld, dann kommt 0x2A63 dazu

_LOST = object()  # Marke in der Warteschlange: die Verbindung ist weg


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
    ) -> None:
        self._adapter = adapter
        self._address = address
        self._scan_s = scan_s
        self._settle_s = settle_s
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
        wenn kein Trainer da ist oder etwas scheitert."""
        address = await self._find()
        queue: asyncio.Queue[object] = asyncio.Queue()
        self._queue = queue
        self._cycling_power = False
        self._bike_without_cadence = 0
        self._cadence_seen = False
        connection: BleConnection | None = None
        try:
            connection = await self._adapter.connect(address, lambda: queue.put_nowait(_LOST))
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
            elif self._cycling_power_available:
                # Leistungsmesser ohne FTMS: Leistung und Kadenz kommen allein aus 0x2A63.
                self.capabilities = {Capability.POWER, Capability.CADENCE}
                await self._subscribe_cycling_power(connection, queue)
            else:
                raise BleError(f"{address} hat weder FTMS noch Cycling Power")
        except (BleError, ParseError) as exc:
            await self._close(connection)
            raise SourceDisconnectedError(f"Trainer {address}: {exc}") from exc
        except BaseException:  # abgebrochen (Bridge endet) mitten im Verbinden: nichts offen lassen
            await self._close(connection)
            raise
        self._connection = connection

    async def samples(self) -> AsyncIterator[RawNotification]:
        """Rohe Notifications, bis die Verbindung abreißt (dann `SourceDisconnectedError`)."""
        connection, queue = self._connection, self._queue
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
            await self._close(connection)

    async def set_grade(self, grade: float) -> None:
        raise NotSupportedError("Der Trainer wird noch nicht gesteuert (Capability RESISTANCE_CONTROL fehlt)")

    # --- Hilfen --------------------------------------------------------------------------

    async def _find(self) -> str:
        """Adresse des Trainers; wirft `SourceDisconnectedError`, wenn nach `scan_s` keiner gesendet hat."""
        seen: dict[str, Advertisement] = {}
        found = asyncio.Event()

        def on_found(advertisement: Advertisement) -> None:
            if self._address is None or advertisement.address.lower() == self._address.lower():
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
                raise SourceDisconnectedError(
                    f"{what} nicht gefunden (ist er an und von Zwift, der Hersteller-App o. Ä. getrennt?)"
                ) from None
            if self._address is None:
                await asyncio.sleep(self._settle_s)
        finally:
            with contextlib.suppress(BleError):
                await scan.stop()
        return _strongest(seen.values()).address

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
