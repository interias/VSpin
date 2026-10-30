"""`BleAdapter` über bleak (`BleakScanner`, `BleakClient`, ADR-0002)."""

import asyncio
from collections.abc import Callable, Iterable

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData
from bleak.exc import BleakError

from .base import Advertisement, BleError, GattCharacteristic

# Fehler, die bleak je nach Plattform beim Suchen, Verbinden und Trennen wirft
# (WinRT meldet einiges als OSError, Zeitüberschreitung als TimeoutError).
_BLE_FAILURES = (BleakError, OSError, TimeoutError)

CONNECT_TIMEOUT_S = 10.0
IO_TIMEOUT_S = 5.0  # Lesen und Schreiben mit Antwort


class BleakAdapter:
    """Merkt sich die zuletzt gefundenen Geräte: `connect` nutzt dann das gefundene
    `BLEDevice`, statt bleak für die Adresse erneut suchen zu lassen."""

    def __init__(self, connect_timeout_s: float = CONNECT_TIMEOUT_S, io_timeout_s: float = IO_TIMEOUT_S) -> None:
        self._connect_timeout_s = connect_timeout_s
        self._io_timeout_s = io_timeout_s
        self._devices: dict[str, BLEDevice] = {}

    async def start_scan(
        self,
        on_found: Callable[[Advertisement], None],
        *,
        services: Iterable[str] = (),
        manufacturer_ids: Iterable[int] = (),
    ) -> "_BleakScan":
        wanted_services = [service.lower() for service in services]
        wanted_makers = set(manufacturer_ids)
        # Nur Services: bleak filtert selbst. Mit Herstellerdaten würde dieser Filter Geräte
        # ohne Service-Ankündigung verwerfen, dann filtert der Rückruf (Service oder Hersteller).
        filter_here = bool(wanted_makers)

        def detected(device: BLEDevice, data: AdvertisementData) -> None:
            announced = tuple(uuid.lower() for uuid in data.service_uuids)
            if filter_here and not (
                wanted_makers.intersection(data.manufacturer_data) or set(wanted_services).intersection(announced)
            ):
                return
            self._devices[device.address] = device
            on_found(
                Advertisement(
                    device.address,
                    data.local_name or device.name,
                    data.rssi,
                    announced,
                    {company: bytes(payload) for company, payload in data.manufacturer_data.items()},
                )
            )

        try:
            # Auch das Bauen kann scheitern (z. B. kein Backend für diese Plattform).
            if wanted_services and not filter_here:
                scanner = BleakScanner(detection_callback=detected, service_uuids=wanted_services)
            else:
                scanner = BleakScanner(detection_callback=detected)
            await scanner.start()
        except _BLE_FAILURES as error:
            raise BleError(f"Suche startet nicht: {error}") from error
        return _BleakScan(scanner)

    async def connect(self, address: str, on_disconnect: Callable[[], None]) -> "_BleakConnection":
        client = BleakClient(
            self._devices.get(address, address),
            disconnected_callback=lambda _client: on_disconnect(),
            timeout=self._connect_timeout_s,
        )
        try:
            await client.connect()
        except _BLE_FAILURES as error:
            raise BleError(f"{address} nicht erreichbar: {error}") from error
        return _BleakConnection(address, client, self._io_timeout_s)


class _BleakScan:
    def __init__(self, scanner: BleakScanner) -> None:
        self._scanner = scanner

    async def stop(self) -> None:
        try:
            await self._scanner.stop()
        except _BLE_FAILURES as error:
            raise BleError(f"Suche stoppt nicht: {error}") from error


class _BleakConnection:
    def __init__(self, address: str, client: BleakClient, io_timeout_s: float = IO_TIMEOUT_S) -> None:
        self.address = address
        self._client = client
        self._io_timeout_s = io_timeout_s

    @property
    def service_uuids(self) -> frozenset[str]:
        try:
            return frozenset(service.uuid.lower() for service in self._client.services)
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: Services nicht lesbar: {error}") from error

    @property
    def characteristics(self) -> tuple[GattCharacteristic, ...]:
        try:
            return tuple(
                GattCharacteristic(service.uuid.lower(), char.uuid.lower(), frozenset(char.properties))
                for service in self._client.services
                for char in service.characteristics
            )
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: Characteristics nicht lesbar: {error}") from error

    async def read(self, char: str) -> bytes:
        try:
            return bytes(await asyncio.wait_for(self._client.read_gatt_char(char), self._io_timeout_s))
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: {char} nicht lesbar: {error}") from error

    async def write(self, char: str, data: bytes, *, response: bool = True) -> None:
        try:
            await asyncio.wait_for(self._client.write_gatt_char(char, data, response=response), self._io_timeout_s)
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: {char} nicht beschreibbar: {error}") from error

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        # `start_notify` abonniert auch Indications (bleak nimmt Indicate, wenn die Characteristic nur das kann).
        try:
            await self._client.start_notify(char, lambda _char, data: on_notify(bytes(data)))
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: {char} nicht abonnierbar: {error}") from error

    async def disconnect(self) -> None:
        try:
            await self._client.disconnect()
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: Trennen gescheitert: {error}") from error
