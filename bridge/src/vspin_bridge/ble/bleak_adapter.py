"""`BleAdapter` über bleak (`BleakScanner`, `BleakClient`, ADR-0002)."""

from collections.abc import Callable

from bleak import BleakClient, BleakScanner
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData
from bleak.exc import BleakError

from .base import Advertisement, BleError

# Fehler, die bleak je nach Plattform beim Suchen, Verbinden und Trennen wirft
# (WinRT meldet einiges als OSError, Zeitüberschreitung als TimeoutError).
_BLE_FAILURES = (BleakError, OSError, TimeoutError)

CONNECT_TIMEOUT_S = 10.0


class BleakAdapter:
    """Merkt sich die zuletzt gefundenen Geräte: `connect` nutzt dann das gefundene
    `BLEDevice`, statt bleak für die Adresse erneut suchen zu lassen."""

    def __init__(self, connect_timeout_s: float = CONNECT_TIMEOUT_S) -> None:
        self._connect_timeout_s = connect_timeout_s
        self._devices: dict[str, BLEDevice] = {}

    async def start_scan(self, service: str, on_found: Callable[[Advertisement], None]) -> "_BleakScan":
        def detected(device: BLEDevice, data: AdvertisementData) -> None:
            self._devices[device.address] = device
            on_found(Advertisement(device.address, data.local_name or device.name, data.rssi))

        try:
            # Auch das Bauen kann scheitern (z. B. kein Backend für diese Plattform).
            scanner = BleakScanner(detection_callback=detected, service_uuids=[service])
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
        return _BleakConnection(address, client)


class _BleakScan:
    def __init__(self, scanner: BleakScanner) -> None:
        self._scanner = scanner

    async def stop(self) -> None:
        try:
            await self._scanner.stop()
        except _BLE_FAILURES as error:
            raise BleError(f"Suche stoppt nicht: {error}") from error


class _BleakConnection:
    def __init__(self, address: str, client: BleakClient) -> None:
        self.address = address
        self._client = client

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        try:
            await self._client.start_notify(char, lambda _char, data: on_notify(bytes(data)))
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: {char} nicht abonnierbar: {error}") from error

    async def disconnect(self) -> None:
        try:
            await self._client.disconnect()
        except _BLE_FAILURES as error:
            raise BleError(f"{self.address}: Trennen gescheitert: {error}") from error
