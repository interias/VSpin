"""Die Erweiterungen des BLE-Fakes (Spec #75) in Gebrauch: Suche über Services und Herstellerdaten, lesen,
schreiben mit Schreibprotokoll, Antwort als Indication, Fehlerinjektion. Das ist die Grundlage, auf der
die Pakete für Trainer und Controller ihre Fake-Geräte bauen."""

import asyncio
from collections.abc import Callable

import pytest
from fake_ble import FakeBleAdapter

from vspin_bridge.ble import Advertisement, BleError

FTMS = "00001826-0000-1000-8000-00805f9b34fb"
HEART_RATE = "0000180d-0000-1000-8000-00805f9b34fb"
CONTROLLER_SERVICE = "0000fc82-0000-1000-8000-00805f9b34fb"
ZWIFT = 0x094A
TRAINER = "AA:00:00:00:00:10"
CONTROLLER = "AA:00:00:00:00:20"
WRITE_CHAR = "00002ad9-0000-1000-8000-00805f9b34fb"
INDICATE_CHAR = "00002ada-0000-1000-8000-00805f9b34fb"
READ_CHAR = "00002acc-0000-1000-8000-00805f9b34fb"


def run(scenario: Callable[[FakeBleAdapter], object]) -> None:
    async def main() -> None:
        await scenario(FakeBleAdapter())

    asyncio.run(main())


def test_scan_over_services_and_manufacturer_data_reports_matches_with_their_data():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR", services=(FTMS,))
        adapter.appear(CONTROLLER, None, manufacturer_data={ZWIFT: b"\x07"})
        adapter.appear("AA:00:00:00:00:30", "Gurt", services=(HEART_RATE,))
        adapter.appear("AA:00:00:00:00:40", "Fremder", manufacturer_data={0x004C: b"\x02"})
        found: dict[str, Advertisement] = {}
        scan = await adapter.start_scan(lambda a: found.update({a.address: a}), services=[FTMS], manufacturer_ids=[ZWIFT])
        await scan.stop()
        assert set(found) == {TRAINER, CONTROLLER}
        assert found[TRAINER].service_uuids == (FTMS,)
        assert found[CONTROLLER].manufacturer_data == {ZWIFT: b"\x07"}

    run(scenario)


def test_manufacturer_only_scan_ignores_service_devices():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR", services=(FTMS,))
        adapter.appear("AA:00:00:00:00:50", "Ohne Angaben")
        adapter.appear(CONTROLLER, None, manufacturer_data={ZWIFT: b"\x08"})
        found: list[str] = []
        scan = await adapter.start_scan(lambda a: found.append(a.address), manufacturer_ids=[ZWIFT])
        await scan.stop()
        assert set(found) == {CONTROLLER}

    run(scenario)


def test_service_database_differs_from_the_advertisement():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(CONTROLLER, None, manufacturer_data={ZWIFT: b"\x07"})
        locked = await adapter.connect(CONTROLLER, lambda: None)
        assert CONTROLLER_SERVICE not in locked.service_uuids
        adapter.appear(TRAINER, "KICKR", services=(FTMS,), gatt_services=(FTMS, CONTROLLER_SERVICE))
        trainer = await adapter.connect(TRAINER, lambda: None)
        assert trainer.service_uuids == {FTMS, CONTROLLER_SERVICE}

    run(scenario)


def test_read_returns_the_prepared_value_and_fails_on_injection():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        adapter.set_readable(TRAINER, READ_CHAR, b"\x2a")
        connection = await adapter.connect(TRAINER, lambda: None)
        assert await connection.read(READ_CHAR) == b"\x2a"
        adapter.fail_reads[TRAINER] = 1
        with pytest.raises(BleError):
            await connection.read(READ_CHAR)
        assert await connection.read(READ_CHAR) == b"\x2a"  # nur einmal
        with pytest.raises(BleError):
            await connection.read("00002a00-0000-1000-8000-00805f9b34fb")  # unbekannt

    run(scenario)


def test_write_is_logged_in_order_and_answered_as_indication():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        adapter.answer(TRAINER, WRITE_CHAR, INDICATE_CHAR, lambda data: b"\x80" + data[:1])
        connection = await adapter.connect(TRAINER, lambda: None)
        indications: list[bytes] = []
        await connection.subscribe(INDICATE_CHAR, indications.append)
        await connection.write(WRITE_CHAR, b"\x00")
        assert indications == []  # die Indication folgt erst der Quittung
        await asyncio.sleep(0)
        assert indications == [b"\x80\x00"]
        await connection.write(WRITE_CHAR, b"\x07\x01")
        await asyncio.sleep(0)
        assert indications == [b"\x80\x00", b"\x80\x07"]
        assert adapter.writes == [(TRAINER, WRITE_CHAR, b"\x00"), (TRAINER, WRITE_CHAR, b"\x07\x01")]

    run(scenario)


def test_answer_function_may_stay_silent():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        adapter.answer(TRAINER, WRITE_CHAR, INDICATE_CHAR, lambda data: None if data == b"\x00" else b"\x01")
        connection = await adapter.connect(TRAINER, lambda: None)
        indications: list[bytes] = []
        await connection.subscribe(INDICATE_CHAR, indications.append)
        await connection.write(WRITE_CHAR, b"\x00")
        await connection.write(WRITE_CHAR, b"\x05")
        await asyncio.sleep(0)
        assert indications == [b"\x01"]

    run(scenario)


def test_write_before_subscribing_to_the_indication_is_refused_and_not_logged():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        adapter.answer(TRAINER, WRITE_CHAR, INDICATE_CHAR, b"\x01")
        connection = await adapter.connect(TRAINER, lambda: None)
        with pytest.raises(BleError, match="nicht abonniert"):
            await connection.write(WRITE_CHAR, b"\x00")
        assert adapter.writes == []
        await connection.subscribe(INDICATE_CHAR, lambda data: None)
        await connection.write(WRITE_CHAR, b"\x00")
        assert len(adapter.writes) == 1

    run(scenario)


def test_write_failure_injection_and_dropped_connection():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        connection = await adapter.connect(TRAINER, lambda: None)
        adapter.fail_writes[TRAINER] = 1
        with pytest.raises(BleError):
            await connection.write(WRITE_CHAR, b"\x00")
        await connection.write(WRITE_CHAR, b"\x01")
        assert adapter.writes == [(TRAINER, WRITE_CHAR, b"\x01")]
        adapter.drop(TRAINER)
        with pytest.raises(BleError):
            await connection.write(WRITE_CHAR, b"\x02")
        with pytest.raises(BleError):
            await connection.read(READ_CHAR)

    run(scenario)


def test_indicate_reaches_only_the_subscribers_of_that_characteristic():
    async def scenario(adapter: FakeBleAdapter) -> None:
        adapter.appear(TRAINER, "KICKR")
        connection = await adapter.connect(TRAINER, lambda: None)
        on_indicate: list[bytes] = []
        on_other: list[bytes] = []
        await connection.subscribe(INDICATE_CHAR, on_indicate.append)
        await connection.subscribe(READ_CHAR, on_other.append)
        adapter.indicate(TRAINER, INDICATE_CHAR, b"\x01")
        adapter.notify(TRAINER, b"\x02")  # wie bisher: an alle
        assert on_indicate == [b"\x01", b"\x02"] and on_other == [b"\x02"]

    run(scenario)
