"""HeartRateSource gegen den BLE-Fake: automatisch verbinden, Vorrang Gurt vor Uhr, Neuverbinden,
stale, Erkennung am Namen, Suche auf Anfrage, kaputte Notifications, eine Meldung je Änderung.

Kein echter Scan; alle Zeiten sind kurz eingestellt. Asynchron über `asyncio.run`.
"""

import asyncio
import time
from collections.abc import Callable

from fake_ble import FakeBleAdapter

from vspin_bridge.ble import Advertisement
from vspin_bridge.parsers import HEART_RATE_MEASUREMENT
from vspin_bridge.sources.base import RawNotification
from vspin_bridge.sources.heart_rate import (
    HeartRateDevice,
    HeartRateSource,
    HeartRateState,
    HeartRateStatus,
    Role,
)

STRAP = HeartRateDevice("AA:00:00:00:00:01", "HRM-Pro", Role.STRAP)
WATCH = HeartRateDevice("AA:00:00:00:00:02", "Forerunner 970", Role.WATCH)
STRANGER = ("AA:00:00:00:00:99", "Fremder Gurt")

STALE_S = 0.3
RETRY_S = 0.1

PULSE_72 = bytes.fromhex("00 48")
PULSE_80 = bytes.fromhex("00 50")


class Owner:
    """Besitzer der Quelle: sammelt Zustandsmeldungen und Rohnotifications."""

    def __init__(self) -> None:
        self.statuses: list[HeartRateStatus] = []
        self.raw: list[RawNotification] = []

    @property
    def states(self) -> list[HeartRateState]:
        return [status.state for status in self.statuses]


def run(scenario: Callable[[FakeBleAdapter, HeartRateSource, Owner], object], **times: float) -> None:
    async def main() -> None:
        adapter = FakeBleAdapter()
        owner = Owner()
        source = HeartRateSource(
            adapter,
            owner.statuses.append,
            owner.raw.append,
            stale_s=times.get("stale_s", STALE_S),
            retry_s=times.get("retry_s", RETRY_S),
            search_s=times.get("search_s", 5.0),
        )
        await source.start()
        try:
            await asyncio.wait_for(scenario(adapter, source, owner), 10)
        finally:
            await source.stop()

    asyncio.run(main())


async def until(condition: Callable[[], bool], timeout: float = 2.0) -> None:
    deadline = time.monotonic() + timeout
    while not condition():
        assert time.monotonic() < deadline, "Bedingung nicht erreicht"
        await asyncio.sleep(0.005)


def connected_to(source: HeartRateSource, device: HeartRateDevice) -> Callable[[], bool]:
    return lambda: source.status == HeartRateStatus(HeartRateState.CONNECTED, device)


def test_off_before_first_devices():
    async def scenario(adapter, source, owner):
        adapter.appear(STRAP.address, STRAP.name)
        await asyncio.sleep(0.1)
        assert source.status == HeartRateStatus(HeartRateState.OFF)
        assert source.heart_rate is None
        assert adapter.scan_starts == 0
        assert adapter.connect_attempts == []
        assert owner.statuses == []

    run(scenario)


def test_connects_automatically_to_known_sending_device():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        assert source.status == HeartRateStatus(HeartRateState.DISCONNECTED)
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        adapter.notify(STRAP.address, PULSE_72)
        assert source.heart_rate == 72

    run(scenario)


def test_unknown_device_is_not_connected():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(*STRANGER)
        await asyncio.sleep(0.2)
        assert adapter.connect_attempts == []
        assert source.status == HeartRateStatus(HeartRateState.DISCONNECTED)

    run(scenario)


def test_strap_wins_over_watch_when_both_send():
    async def scenario(adapter, source, owner):
        adapter.appear(WATCH.address, WATCH.name)
        adapter.appear(STRAP.address, STRAP.name)
        await source.set_known_devices([STRAP, WATCH])
        await until(connected_to(source, STRAP))
        await asyncio.sleep(0.1)
        assert adapter.connect_attempts == [STRAP.address]
        assert adapter.connected == {STRAP.address}

    run(scenario)


def test_switches_from_watch_to_strap():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP, WATCH])
        adapter.appear(WATCH.address, WATCH.name)
        await until(connected_to(source, WATCH))
        adapter.notify(WATCH.address, PULSE_72)
        assert adapter.scanning  # sucht weiter nach dem Gurt

        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        await until(lambda: adapter.connected == {STRAP.address})
        assert source.heart_rate == 72  # der Wert der Uhr gilt bis zum ersten Wert des Gurts
        await until(lambda: not adapter.scanning)  # höchster Vorrang verbunden: Suche aus
        assert owner.statuses == [
            HeartRateStatus(HeartRateState.DISCONNECTED),
            HeartRateStatus(HeartRateState.CONNECTED, WATCH),
            HeartRateStatus(HeartRateState.CONNECTED, STRAP),
        ]

    run(scenario)


def test_watch_that_starts_sending_later_is_found():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP, WATCH])
        await asyncio.sleep(0.2)
        assert source.status == HeartRateStatus(HeartRateState.DISCONNECTED)
        adapter.appear(WATCH.address, WATCH.name)  # „Herzfrequenz übertragen“ während der Fahrt
        await until(connected_to(source, WATCH))

    run(scenario)


def test_reconnects_after_connection_loss():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        await until(lambda: not adapter.scanning)

        adapter.drop(STRAP.address)
        assert source.status == HeartRateStatus(HeartRateState.DISCONNECTED)
        await until(lambda: adapter.scanning)  # Hintergrundsuche läuft wieder
        await until(connected_to(source, STRAP))
        assert owner.states == [
            HeartRateState.DISCONNECTED,
            HeartRateState.CONNECTED,
            HeartRateState.DISCONNECTED,
            HeartRateState.CONNECTED,
        ]

    run(scenario)


def test_failed_connection_attempt_is_retried_after_a_pause():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.refuse(STRAP.address)
        started = time.monotonic()
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        assert adapter.connect_attempts == [STRAP.address, STRAP.address]
        assert time.monotonic() - started >= RETRY_S

    run(scenario)


def test_device_that_stops_sending_is_not_dialled_blindly():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        adapter.vanish(STRAP.address)
        adapter.drop(STRAP.address)
        await asyncio.sleep(5 * RETRY_S)
        assert adapter.connect_attempts == [STRAP.address]
        assert source.status == HeartRateStatus(HeartRateState.DISCONNECTED)

    run(scenario)


def test_stale_and_no_heart_rate_without_values():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        adapter.notify(STRAP.address, PULSE_72)
        await asyncio.sleep(STALE_S / 2)
        assert source.status.state == HeartRateState.CONNECTED
        assert source.heart_rate == 72

        await until(lambda: source.status.state == HeartRateState.STALE)
        assert source.status.device == STRAP
        assert source.heart_rate is None

        adapter.notify(STRAP.address, PULSE_80)
        assert source.status == HeartRateStatus(HeartRateState.CONNECTED, STRAP)
        assert source.heart_rate == 80

    run(scenario)


def test_stale_without_any_value_after_connect():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        await until(lambda: source.status.state == HeartRateState.STALE)
        assert source.heart_rate is None

    run(scenario)


def test_recognised_by_name_when_the_address_differs():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP, WATCH])
        adapter.appear("BB:00:00:00:00:02", WATCH.name)
        await until(lambda: source.status.state == HeartRateState.CONNECTED)
        assert source.status.device == HeartRateDevice("BB:00:00:00:00:02", WATCH.name, Role.WATCH)
        assert adapter.connected == {"BB:00:00:00:00:02"}

    run(scenario)


def test_empty_list_switches_off_and_disconnects():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        adapter.notify(STRAP.address, PULSE_72)

        await source.set_known_devices([])
        assert source.status == HeartRateStatus(HeartRateState.OFF)
        assert source.heart_rate is None
        assert adapter.connected == set()
        await asyncio.sleep(0.1)
        assert not adapter.scanning
        assert adapter.connect_attempts == [STRAP.address]
        assert owner.states[-1] == HeartRateState.OFF

    run(scenario)


def test_search_on_request_reports_unknown_devices_and_leaves_the_connection_alone():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name, rssi=-50)
        await until(connected_to(source, STRAP))
        adapter.appear(*STRANGER, rssi=-80)
        statuses_before = list(owner.statuses)

        found: list[Advertisement] = []
        source.start_search(found.append, duration_s=0.3)
        assert source.searching
        await until(lambda: {ad.address for ad in found} >= {STRAP.address, STRANGER[0]})
        assert Advertisement(*STRANGER, -80) in found
        assert Advertisement(STRAP.address, STRAP.name, -50) in found

        await until(lambda: not source.searching)
        await until(lambda: not adapter.scanning)
        assert owner.statuses == statuses_before
        assert adapter.connect_attempts == [STRAP.address]
        assert adapter.connected == {STRAP.address}

    run(scenario, stale_s=5.0)  # kein Pulswert nötig: stale soll hier nicht dazwischenkommen


def test_search_on_request_shares_the_background_search():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP, WATCH])
        adapter.appear(WATCH.address, WATCH.name)
        await until(connected_to(source, WATCH))  # Hintergrundsuche läuft weiter (Gurt fehlt)

        found: list[Advertisement] = []
        source.start_search(found.append)
        await until(lambda: len(found) >= 2)
        source.stop_search()
        assert not source.searching
        await asyncio.sleep(0.1)
        assert adapter.scanning  # die Hintergrundsuche bleibt
        assert adapter.max_parallel_scans == 1

        adapter.appear(STRAP.address, STRAP.name)  # und findet weiterhin den Gurt
        await until(connected_to(source, STRAP))

    run(scenario)


def test_broken_notification_is_dropped_and_the_connection_stays():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        adapter.notify(STRAP.address, PULSE_72)
        adapter.notify(STRAP.address, bytes.fromhex("01 48"))  # uint16 angekündigt, ein Byte da
        assert source.heart_rate == 72
        assert source.status == HeartRateStatus(HeartRateState.CONNECTED, STRAP)
        assert adapter.connected == {STRAP.address}
        assert [raw.data for raw in owner.raw] == [PULSE_72, bytes.fromhex("01 48")]
        assert {raw.char for raw in owner.raw} == {HEART_RATE_MEASUREMENT}

    run(scenario)


def test_exactly_one_report_per_change():
    async def scenario(adapter, source, owner):
        await source.set_known_devices([STRAP])
        await source.set_known_devices([STRAP])  # gleiche Liste: keine Änderung
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        for _ in range(5):
            adapter.notify(STRAP.address, PULSE_72)
            await asyncio.sleep(0.01)
        await until(lambda: source.status.state == HeartRateState.STALE)
        await asyncio.sleep(STALE_S)  # bleibt stale, ohne neue Meldung
        adapter.notify(STRAP.address, PULSE_80)
        adapter.notify(STRAP.address, PULSE_80)
        adapter.drop(STRAP.address)
        await source.set_known_devices([])
        assert owner.statuses == [
            HeartRateStatus(HeartRateState.DISCONNECTED),
            HeartRateStatus(HeartRateState.CONNECTED, STRAP),
            HeartRateStatus(HeartRateState.STALE, STRAP),
            HeartRateStatus(HeartRateState.CONNECTED, STRAP),
            HeartRateStatus(HeartRateState.DISCONNECTED),
            HeartRateStatus(HeartRateState.OFF),
        ]

    run(scenario)


def test_stop_while_connecting_leaves_no_connection_open():
    async def scenario(adapter, source, owner):
        adapter.subscribe_delay_s = 1.0  # `stop` kommt mitten ins Abonnieren
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(lambda: adapter.connected == {STRAP.address})
        await source.stop()
        assert adapter.connected == set()

    run(scenario)


def test_search_start_failure_is_retried():
    async def scenario(adapter, source, owner):
        adapter.scan_failures = 1  # z. B. Bluetooth-Adapter noch nicht bereit
        await source.set_known_devices([STRAP])
        adapter.appear(STRAP.address, STRAP.name)
        await until(connected_to(source, STRAP))
        assert adapter.scan_starts == 1

    run(scenario)
