"""Skriptbarer Fake der BLE-Nahtstelle (`vspin_bridge.ble.BleAdapter`) – kein echter Scan.

Geräte erscheinen (`appear`) und verschwinden (`vanish`); solange eine Suche läuft, kündigt
jedes erschienene Gerät sich alle `advert_interval_s` neu an, wie ein echtes Gerät. Verbinden
gelingt oder scheitert (`refuse`), Notifications kommen (`notify`), die Verbindung reißt ab
(`drop`). Der Fake zählt mit, was die Quelle tut (`scan_starts`, `connect_attempts` …).
"""

import asyncio
from collections.abc import Callable
from dataclasses import dataclass

from vspin_bridge.ble import Advertisement, BleError


@dataclass
class FakeDevice:
    address: str
    name: str | None
    rssi: int
    services: tuple[str, ...]


class FakeBleAdapter:
    def __init__(self, advert_interval_s: float = 0.02) -> None:
        self.advert_interval_s = advert_interval_s
        self.devices: dict[str, FakeDevice] = {}
        self.refused: dict[str, int] = {}  # Adresse → so viele Verbindungsversuche scheitern
        self.scan_failures = 0  # so viele `start_scan` scheitern (z. B. kein Bluetooth-Adapter)
        self.subscribe_delay_s = 0.0  # so lange dauert das Abonnieren
        self.scan_starts = 0
        self.max_parallel_scans = 0
        self.connect_attempts: list[str] = []
        self.connections: dict[str, "FakeConnection"] = {}
        self._scans: list[FakeScan] = []

    # --- Skript ------------------------------------------------------------------------

    def appear(self, address: str, name: str | None, rssi: int = -60, services: tuple[str, ...] = ()) -> None:
        """Gerät beginnt zu senden. `services`: angekündigte Services (leer = jeder Service)."""
        self.devices[address] = FakeDevice(address, name, rssi, services)
        for scan in self._scans:
            scan.announce(self.devices[address])

    def vanish(self, address: str) -> None:
        """Gerät hört auf zu senden; eine bestehende Verbindung bleibt."""
        self.devices.pop(address, None)

    def refuse(self, address: str, times: int = 1) -> None:
        self.refused[address] = times

    def notify(self, address: str, data: bytes) -> None:
        self.connections[address].notify(data)

    def drop(self, address: str) -> None:
        """Verbindung reißt ab (das Gerät sendet weiter)."""
        self.connections.pop(address).lost()

    @property
    def scanning(self) -> bool:
        return bool(self._scans)

    @property
    def connected(self) -> set[str]:
        return set(self.connections)

    # --- BleAdapter ----------------------------------------------------------------------

    async def start_scan(self, service: str, on_found: Callable[[Advertisement], None]) -> "FakeScan":
        if self.scan_failures:
            self.scan_failures -= 1
            raise BleError("kein Bluetooth-Adapter")
        scan = FakeScan(self, service, on_found)
        self._scans.append(scan)
        self.scan_starts += 1
        self.max_parallel_scans = max(self.max_parallel_scans, len(self._scans))
        for device in list(self.devices.values()):
            scan.announce(device)
        scan.task = asyncio.create_task(scan.run())
        return scan

    async def connect(self, address: str, on_disconnect: Callable[[], None]) -> "FakeConnection":
        self.connect_attempts.append(address)
        await asyncio.sleep(0)
        if self.refused.get(address, 0) > 0:
            self.refused[address] -= 1
            raise BleError(f"{address} lehnt ab")
        if address not in self.devices:
            raise BleError(f"{address} nicht erreichbar")
        connection = FakeConnection(self, address, on_disconnect)
        self.connections[address] = connection
        return connection


class FakeScan:
    def __init__(self, adapter: FakeBleAdapter, service: str, on_found: Callable[[Advertisement], None]) -> None:
        self._adapter = adapter
        self._service = service
        self._on_found = on_found
        self.task: asyncio.Task[None] | None = None

    def announce(self, device: FakeDevice) -> None:
        if not device.services or self._service in device.services:
            self._on_found(Advertisement(device.address, device.name, device.rssi))

    async def run(self) -> None:
        while True:
            await asyncio.sleep(self._adapter.advert_interval_s)
            for device in list(self._adapter.devices.values()):
                self.announce(device)

    async def stop(self) -> None:
        self._adapter._scans.remove(self)
        if self.task is not None:
            self.task.cancel()


class FakeConnection:
    def __init__(self, adapter: FakeBleAdapter, address: str, on_disconnect: Callable[[], None]) -> None:
        self.address = address
        self._adapter = adapter
        self._on_disconnect = on_disconnect
        self.subscriptions: dict[str, Callable[[bytes], None]] = {}
        self.open = True

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        if self._adapter.subscribe_delay_s:
            await asyncio.sleep(self._adapter.subscribe_delay_s)
        if not self.open:
            raise BleError(f"{self.address} getrennt")
        self.subscriptions[char] = on_notify

    def notify(self, data: bytes) -> None:
        for on_notify in list(self.subscriptions.values()):
            on_notify(data)

    def lost(self) -> None:
        self.open = False
        self._on_disconnect()

    async def disconnect(self) -> None:
        if self.open:
            self._adapter.connections.pop(self.address, None)
            self.lost()
