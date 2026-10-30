"""bleak-Umsetzung der erweiterten Nahtstelle (Spec #75): Suche über mehrere Services und Herstellerdaten,
`read`, `write` mit Antwort und Zeitlimit, Services der Gerätedatenbank, Indications, Fehler als `BleError`.

`BleakScanner` und `BleakClient` sind durch Attrappen ersetzt; es gibt weder Scan noch Gerät."""

import asyncio
from types import SimpleNamespace

import pytest
from bleak.exc import BleakError
from vspin_bridge.ble import Advertisement, BleError, GattCharacteristic
from vspin_bridge.ble import bleak_adapter
from vspin_bridge.ble.bleak_adapter import BleakAdapter

FTMS = "00001826-0000-1000-8000-00805f9b34fb"
CYCLING_POWER = "00001818-0000-1000-8000-00805f9b34fb"
HEART_RATE = "0000180d-0000-1000-8000-00805f9b34fb"
ZWIFT = 0x094A
CONTROL_POINT = "00002ad9-0000-1000-8000-00805f9b34fb"
INDICATE_ONLY = "00002ada-0000-1000-8000-00805f9b34fb"


class FakeScanner:
    """Merkt sich, wie die Nahtstelle den Scanner baut, und lässt den Test Ankündigungen einspielen."""

    instances: list["FakeScanner"] = []

    def __init__(self, detection_callback, **kwargs) -> None:
        self.callback = detection_callback
        self.kwargs = kwargs
        self.started = False
        FakeScanner.instances.append(self)

    async def start(self) -> None:
        self.started = True

    async def stop(self) -> None:
        self.started = False

    def advertise(self, address: str, *, services=(), manufacturer_data=None, name="Gerät", rssi=-60) -> None:
        device = SimpleNamespace(address=address, name=name)
        data = SimpleNamespace(
            local_name=name,
            rssi=rssi,
            service_uuids=list(services),
            manufacturer_data=manufacturer_data or {},
        )
        self.callback(device, data)


class FakeClient:
    """Attrappe für `BleakClient`: Zugriffe werden protokolliert, Fehler und Hänger lassen sich einstellen."""

    instances: list["FakeClient"] = []

    def __init__(self, device, disconnected_callback=None, timeout=10.0) -> None:
        self.device = device
        self.services = [SimpleNamespace(uuid=FTMS.upper()), SimpleNamespace(uuid=CYCLING_POWER)]
        self.values = {CONTROL_POINT: b"\x01\x02"}
        self.notify_only = {INDICATE_ONLY}  # Characteristics, die nur Indicate/Notify können
        self.writes: list[tuple[str, bytes, bool]] = []
        self.notified: list[str] = []
        self.error: Exception | None = None
        self.hang = False
        FakeClient.instances.append(self)

    async def connect(self) -> None:
        pass

    async def disconnect(self) -> None:
        pass

    async def _maybe_fail(self) -> None:
        if self.hang:
            await asyncio.sleep(3600)
        if self.error is not None:
            raise self.error

    async def read_gatt_char(self, char):
        await self._maybe_fail()
        return bytearray(self.values[char])

    async def write_gatt_char(self, char, data, response=None):
        await self._maybe_fail()
        self.writes.append((char, bytes(data), response))

    async def start_notify(self, char, callback):
        await self._maybe_fail()
        self.notified.append(char)
        self.callback = callback


@pytest.fixture(autouse=True)
def fakes(monkeypatch):
    FakeScanner.instances = []
    FakeClient.instances = []
    monkeypatch.setattr(bleak_adapter, "BleakScanner", FakeScanner)
    monkeypatch.setattr(bleak_adapter, "BleakClient", FakeClient)


def scan(**kwargs) -> tuple[list[Advertisement], FakeScanner]:
    found: list[Advertisement] = []
    asyncio.run(BleakAdapter().start_scan(found.append, **kwargs))
    return found, FakeScanner.instances[-1]


# --- Suche -------------------------------------------------------------------------------------


def test_services_only_search_lets_bleak_filter():
    found, scanner = scan(services=[FTMS, CYCLING_POWER.upper()])
    assert scanner.kwargs["service_uuids"] == [FTMS, CYCLING_POWER]
    scanner.advertise("AA", services=[FTMS])
    assert [a.address for a in found] == ["AA"]


def test_search_over_several_services_finds_each():
    found, scanner = scan(services=[FTMS, CYCLING_POWER, HEART_RATE], manufacturer_ids=[ZWIFT])
    scanner.advertise("T1", services=[FTMS])
    scanner.advertise("T2", services=[CYCLING_POWER, "0000fff0-0000-1000-8000-00805f9b34fb"])
    scanner.advertise("H1", services=[HEART_RATE.upper()])
    assert [a.address for a in found] == ["T1", "T2", "H1"]
    assert found[1].service_uuids == (CYCLING_POWER, "0000fff0-0000-1000-8000-00805f9b34fb")
    assert found[2].service_uuids == (HEART_RATE,)  # klein geschrieben


def test_manufacturer_only_device_is_found_without_service_filter_in_bleak():
    found, scanner = scan(services=[FTMS], manufacturer_ids=[ZWIFT])
    assert "service_uuids" not in scanner.kwargs  # sonst verwürfe bleak Geräte ohne Service-Ankündigung
    scanner.advertise("C1", manufacturer_data={ZWIFT: bytearray(b"\x07\x01")})
    assert found == [Advertisement("C1", "Gerät", -60, (), {ZWIFT: b"\x07\x01"})]
    assert type(found[0].manufacturer_data[ZWIFT]) is bytes


def test_manufacturer_ids_only_search():
    found, scanner = scan(manufacturer_ids=[ZWIFT])
    scanner.advertise("C1", manufacturer_data={ZWIFT: b"\x08"})
    assert [a.address for a in found] == ["C1"]


def test_repeated_advertisements_and_empty_manufacturer_payload_are_reported():
    found, scanner = scan(services=[FTMS], manufacturer_ids=[ZWIFT])
    scanner.advertise("C1", manufacturer_data={ZWIFT: b""})  # Firma gesendet, keine Nutzdaten: trotzdem ein Treffer
    scanner.advertise("C1", manufacturer_data={ZWIFT: b""}, rssi=-70)
    assert [(a.address, a.rssi) for a in found] == [("C1", -60), ("C1", -70)]  # jede Ankündigung, mit aktuellem rssi
    assert found[0].manufacturer_data == {ZWIFT: b""}


def test_advertisement_without_match_is_not_reported():
    found, scanner = scan(services=[FTMS], manufacturer_ids=[ZWIFT])
    scanner.advertise("X1", services=[HEART_RATE])
    scanner.advertise("X2", manufacturer_data={0x004C: b"\x02\x15"})
    scanner.advertise("X3")
    assert found == []


# --- Verbindung --------------------------------------------------------------------------------


def connect() -> tuple["object", FakeClient]:
    connection = asyncio.run(BleakAdapter(io_timeout_s=0.05).connect("AA", lambda: None))
    return connection, FakeClient.instances[-1]


def test_service_uuids_of_the_device_database_are_lowercase():
    connection, _ = connect()
    assert connection.service_uuids == {FTMS, CYCLING_POWER}


def test_characteristics_of_the_device_database_with_properties():
    # Spec #89: Characteristics je Service mit den Eigenschaften, wie bleak sie nennt.
    connection, client = connect()
    client.services = [
        SimpleNamespace(uuid="0000FC82-0000-1000-8000-00805F9B34FB", characteristics=[
            SimpleNamespace(uuid="00000002-19CA-4651-86E5-FA29DCDD09D1", properties=["notify"]),
            SimpleNamespace(
                uuid="00000003-19ca-4651-86e5-fa29dcdd09d1", properties=["write-without-response", "write"]
            ),
        ]),
    ]
    assert connection.characteristics == (
        GattCharacteristic("0000fc82-0000-1000-8000-00805f9b34fb", "00000002-19ca-4651-86e5-fa29dcdd09d1",
                           frozenset({"notify"})),
        GattCharacteristic("0000fc82-0000-1000-8000-00805f9b34fb", "00000003-19ca-4651-86e5-fa29dcdd09d1",
                           frozenset({"write", "write-without-response"})),
    )


def test_write_without_response():
    connection, client = connect()
    asyncio.run(connection.write(CONTROL_POINT, b"RideOn", response=False))
    assert client.writes == [(CONTROL_POINT, b"RideOn", False)]


def test_read_returns_bytes():
    connection, _ = connect()
    value = asyncio.run(connection.read(CONTROL_POINT))
    assert value == b"\x01\x02" and type(value) is bytes


def test_write_goes_out_with_response():
    connection, client = connect()
    asyncio.run(connection.write(CONTROL_POINT, b"\x00"))
    assert client.writes == [(CONTROL_POINT, b"\x00", True)]


def test_subscribe_to_an_indicate_only_characteristic_uses_start_notify():
    connection, client = connect()
    received: list[bytes] = []

    async def scenario() -> None:
        await connection.subscribe(INDICATE_ONLY, received.append)
        client.callback(None, bytearray(b"\x80\x00\x01"))

    asyncio.run(scenario())
    assert client.notified == [INDICATE_ONLY]
    assert received == [b"\x80\x00\x01"]


@pytest.mark.parametrize("error", [BleakError("weg"), OSError("WinRT"), TimeoutError()])
def test_failures_become_ble_errors(error):
    connection, client = connect()
    client.error = error
    for call in (
        connection.read(CONTROL_POINT),
        connection.write(CONTROL_POINT, b"\x00"),
        connection.subscribe(INDICATE_ONLY, lambda data: None),
    ):
        with pytest.raises(BleError, match="AA"):
            asyncio.run(call)


def test_unknown_characteristic_is_a_ble_error():
    connection, client = connect()
    client.error = BleakError("Characteristic nicht gefunden")
    with pytest.raises(BleError):
        asyncio.run(connection.read("0000ffff-0000-1000-8000-00805f9b34fb"))


def test_service_uuids_that_cannot_be_read_are_a_ble_error():
    connection, client = connect()

    class Undiscovered:
        def __iter__(self):
            raise BleakError("Services nicht ermittelt")  # so meldet bleak eine noch nicht erkannte Gerätedatenbank

    client.services = Undiscovered()
    with pytest.raises(BleError, match="Services"):
        connection.service_uuids  # noqa: B018
    with pytest.raises(BleError, match="Characteristics"):
        connection.characteristics  # noqa: B018


def test_hanging_read_and_write_time_out_as_ble_error():
    connection, client = connect()
    client.hang = True
    with pytest.raises(BleError, match="nicht lesbar"):
        asyncio.run(connection.read(CONTROL_POINT))
    with pytest.raises(BleError, match="nicht beschreibbar"):
        asyncio.run(connection.write(CONTROL_POINT, b"\x00"))
