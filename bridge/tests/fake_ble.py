"""Skriptbarer Fake der BLE-Nahtstelle (`vspin_bridge.ble.BleAdapter`) – kein echter Scan.

Geräte erscheinen (`appear`) und verschwinden (`vanish`); solange eine Suche läuft, kündigt
jedes erschienene Gerät sich alle `advert_interval_s` neu an, wie ein echtes Gerät. Verbinden
gelingt oder scheitert (`refuse`), Notifications kommen (`notify`), die Verbindung reißt ab
(`drop`). Der Fake zählt mit, was die Quelle tut (`scan_starts`, `connect_attempts` …).

Erweiterung (Spec #75), ohne Wissen über ein Protokoll (kein FTMS hier):
- Ankündigung mit Services und Herstellerdaten (`appear(..., services=, manufacturer_data=)`),
  die Services der Gerätedatenbank getrennt davon (`gatt_services`, Standard = angekündigte).
- Lesbare Characteristics (`set_readable`), Schreibprotokoll (`writes`).
- Antworten auf Schreibzugriffe als Indication (`answer`). Wie am echten Gerät lehnt der Fake den
  Schreibzugriff ab, solange die Indication-Characteristic nicht abonniert ist.
- Fehlerinjektion für `read` und `write` (`fail_reads`, `fail_writes`).
- Spec #89: `answer_before_ack` – die Antwort-Indication kommt schon, bevor der Schreibzugriff quittiert ist (so kann
  ein Stack sie ausliefern, z. B. WinRT).
"""

import asyncio
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field

from vspin_bridge.ble import Advertisement, BleError


@dataclass
class FakeDevice:
    address: str
    name: str | None
    rssi: int
    services: tuple[str, ...]
    manufacturer_data: dict[int, bytes] = field(default_factory=dict)
    gatt_services: tuple[str, ...] = ()


class FakeBleAdapter:
    def __init__(self, advert_interval_s: float = 0.02) -> None:
        self.advert_interval_s = advert_interval_s
        self.devices: dict[str, FakeDevice] = {}
        self.refused: dict[str, int] = {}  # Adresse → so viele Verbindungsversuche scheitern
        self.scan_failures = 0  # so viele `start_scan` scheitern (z. B. kein Bluetooth-Adapter)
        self.subscribe_delay_s = 0.0  # so lange dauert das Abonnieren
        self.readable: dict[tuple[str, str], bytes] = {}  # (Adresse, Characteristic) → Wert
        self.writes: list[tuple[str, str, bytes]] = []  # (Adresse, Characteristic, Daten), in Reihenfolge
        self.fail_reads: dict[str, int] = {}  # Adresse → so viele `read` scheitern
        self.fail_writes: dict[str, int] = {}  # Adresse → so viele `write` scheitern
        self.answers: dict[tuple[str, str], tuple[str, Callable[[bytes], bytes | None]]] = {}
        self.answer_before_ack = False  # Antwort-Indication noch vor der Quittung des Schreibzugriffs
        self.scan_starts = 0
        self.max_parallel_scans = 0
        self.connect_attempts: list[str] = []
        self.connections: dict[str, "FakeConnection"] = {}
        self._scans: list[FakeScan] = []

    # --- Skript ------------------------------------------------------------------------

    def appear(
        self,
        address: str,
        name: str | None,
        rssi: int = -60,
        services: tuple[str, ...] = (),
        manufacturer_data: Mapping[int, bytes] | None = None,
        gatt_services: tuple[str, ...] | None = None,
    ) -> None:
        """Gerät beginnt zu senden. `services`: angekündigte Services (leer und ohne Herstellerdaten
        = passt zu jeder Suche nach Services). `manufacturer_data`: Firmen-ID → Nutzdaten.
        `gatt_services`: Services der Gerätedatenbank nach dem Verbinden (Standard: `services`)."""
        self.devices[address] = FakeDevice(
            address,
            name,
            rssi,
            services,
            dict(manufacturer_data or {}),
            services if gatt_services is None else gatt_services,
        )
        for scan in self._scans:
            scan.announce(self.devices[address])

    def vanish(self, address: str) -> None:
        """Gerät hört auf zu senden; eine bestehende Verbindung bleibt."""
        self.devices.pop(address, None)

    def refuse(self, address: str, times: int = 1) -> None:
        self.refused[address] = times

    def notify(self, address: str, data: bytes) -> None:
        self.connections[address].notify(data)

    def indicate(self, address: str, char: str, data: bytes) -> None:
        """Eine Notification/Indication nur auf `char` (nur an dessen Abonnenten)."""
        self.connections[address].notify(data, char)

    def set_readable(self, address: str, char: str, value: bytes) -> None:
        self.readable[(address, char)] = value

    def answer(
        self, address: str, write_char: str, indicate_char: str, response: bytes | Callable[[bytes], bytes | None]
    ) -> None:
        """Jeder Schreibzugriff auf `write_char` wird als Indication auf `indicate_char` beantwortet:
        mit `response` oder mit dem, was `response(geschriebene Daten)` liefert (`None` = keine Antwort)."""
        respond = response if callable(response) else (lambda _data: response)
        self.answers[(address, write_char)] = (indicate_char, respond)

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

    async def start_scan(
        self,
        on_found: Callable[[Advertisement], None],
        *,
        services: Iterable[str] = (),
        manufacturer_ids: Iterable[int] = (),
    ) -> "FakeScan":
        if self.scan_failures:
            self.scan_failures -= 1
            raise BleError("kein Bluetooth-Adapter")
        scan = FakeScan(self, {service.lower() for service in services}, set(manufacturer_ids), on_found)
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
    def __init__(
        self,
        adapter: FakeBleAdapter,
        services: set[str],
        manufacturer_ids: set[int],
        on_found: Callable[[Advertisement], None],
    ) -> None:
        self._adapter = adapter
        self._services = services
        self._manufacturer_ids = manufacturer_ids
        self._on_found = on_found
        self.task: asyncio.Task[None] | None = None

    def _matches(self, device: FakeDevice) -> bool:
        if not self._services and not self._manufacturer_ids:
            return True
        if self._manufacturer_ids.intersection(device.manufacturer_data):
            return True
        if not device.services and not device.manufacturer_data:
            return bool(self._services)  # Gerät ohne Angaben: passt zu jeder Service-Suche
        return bool(self._services.intersection(device.services))

    def announce(self, device: FakeDevice) -> None:
        if self._matches(device):
            self._on_found(
                Advertisement(device.address, device.name, device.rssi, device.services, dict(device.manufacturer_data))
            )

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

    @property
    def service_uuids(self) -> frozenset[str]:
        device = self._adapter.devices.get(self.address)
        return frozenset(device.gatt_services) if device is not None else frozenset()

    async def read(self, char: str) -> bytes:
        await asyncio.sleep(0)
        if not self.open:
            raise BleError(f"{self.address} getrennt")
        if self._adapter.fail_reads.get(self.address, 0) > 0:
            self._adapter.fail_reads[self.address] -= 1
            raise BleError(f"{self.address}: {char} nicht lesbar")
        try:
            return self._adapter.readable[(self.address, char)]
        except KeyError:
            raise BleError(f"{self.address}: {char} gibt es nicht") from None

    async def write(self, char: str, data: bytes) -> None:
        await asyncio.sleep(0)
        if not self.open:
            raise BleError(f"{self.address} getrennt")
        if self._adapter.fail_writes.get(self.address, 0) > 0:
            self._adapter.fail_writes[self.address] -= 1
            raise BleError(f"{self.address}: {char} nicht beschreibbar")
        answer = self._adapter.answers.get((self.address, char))
        if answer is not None and answer[0] not in self.subscriptions:
            raise BleError(f"{self.address}: Indications von {answer[0]} nicht abonniert")
        self._adapter.writes.append((self.address, char, data))
        if answer is not None:
            indicate_char, respond = answer
            response = respond(data)
            if response is not None and self._adapter.answer_before_ack:
                self.notify(response, indicate_char)
            elif response is not None:
                # Die Indication folgt der Quittung des Schreibzugriffs.
                asyncio.get_running_loop().call_soon(self.notify, response, indicate_char)

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        if self._adapter.subscribe_delay_s:
            await asyncio.sleep(self._adapter.subscribe_delay_s)
        if not self.open:
            raise BleError(f"{self.address} getrennt")
        self.subscriptions[char] = on_notify

    def notify(self, data: bytes, char: str | None = None) -> None:
        """An alle Abonnenten, mit `char` nur an den dieser Characteristic."""
        for subscribed, on_notify in list(self.subscriptions.items()):
            if char is None or subscribed == char:
                on_notify(data)

    def lost(self) -> None:
        self.open = False
        self._on_disconnect()

    async def disconnect(self) -> None:
        if self.open:
            self._adapter.connections.pop(self.address, None)
            self.lost()
