"""TrainerSource gegen den BLE-Fake: Suche und Auswahl, Features → Capabilities, Indoor Bike Data, Kadenz nur über
Cycling Power, Rohdaten, Abbruch und Neuverbinden, CLI-Anbindung.

Kein echter Scan; alle Zeiten sind kurz eingestellt. Asynchron über `asyncio.run`."""

import asyncio
import contextlib
from collections.abc import AsyncIterator, Callable

import pytest
from fake_ble import FakeBleAdapter
from trainer_harness import (
    FEATURES_CADENCE_POWER,
    FEATURES_POWER_ONLY,
    KICKR,
    bike,
    cycling_power,
    features,
    kickr,
    sim_kickr,
)

from vspin_bridge import cli
from vspin_bridge.parsers import CYCLING_POWER_MEASUREMENT, FITNESS_MACHINE_FEATURE, INDOOR_BIKE_DATA, Decoder
from vspin_bridge.sources.base import (
    Capability,
    ControlRefusedError,
    NotSupportedError,
    RawNotification,
    SourceDisconnectedError,
)
from vspin_bridge.sources.trainer import CYCLING_POWER_SERVICE, FTMS_SERVICE, TrainerSource
from vspin_bridge.sources.trainer_control import CONTROL_POINT, MACHINE_STATUS, ControlState

OTHER = "AA:00:00:00:10:02"
HEART_RATE_SERVICE = "0000180d-0000-1000-8000-00805f9b34fb"
TIMEOUT_S = 5


def run(scenario: Callable[[FakeBleAdapter], object]) -> None:
    async def main() -> None:
        adapter = FakeBleAdapter()
        await asyncio.wait_for(scenario(adapter), TIMEOUT_S * 2)
        # Wächter für jeden Test hier: Trainer ohne Indoor Bike Simulation und der Nur-lesen-Modus werden nur gelesen
        # (Spec #75). Die Steuerung (P3) hebt ihn bewusst auf – deren Tests in test_trainer_control.py prüfen
        # `adapter.writes` selbst.
        assert adapter.writes == [], "die Trainerquelle hat auf den Trainer geschrieben"

    asyncio.run(main())


def source_for(adapter: FakeBleAdapter, address: str | None = None) -> TrainerSource:
    return TrainerSource(adapter, address, scan_s=0.3, settle_s=0.05)


async def take(stream: AsyncIterator[RawNotification], count: int) -> list[RawNotification]:
    """Die nächsten `count` Notifications aus dem Strom `source.samples()`."""
    async with asyncio.timeout(TIMEOUT_S):
        return [await anext(stream) for _ in range(count)]


async def pump(adapter: FakeBleAdapter, address: str, char: str, *payloads: bytes) -> None:
    for payload in payloads:
        adapter.indicate(address, char, payload)
        await asyncio.sleep(0)


# --- Suche und Auswahl -----------------------------------------------------------------------


def test_name_and_no_control_surface():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        assert source.name == "ble" and source.power_estimated is False
        await source.connect()
        with pytest.raises(NotSupportedError):
            await source.set_grade(0.05)
        assert adapter.writes == []  # liest nur; kein Control Point

    run(scenario)


def test_strongest_ftms_device_wins_over_a_stronger_cycling_power_only_device():
    async def scenario(adapter):
        kickr(adapter, KICKR, rssi=-70)
        adapter.appear(OTHER, "Powermeter", -40, services=(CYCLING_POWER_SERVICE,))
        kickr(adapter, "AA:00:00:00:10:03", rssi=-80)
        await source_for(adapter).connect()
        assert adapter.connected == {KICKR}
        assert adapter.max_parallel_scans == 1 and not adapter.scanning  # Suche nach dem Fund beendet

    run(scenario)


def test_falls_back_to_the_strongest_cycling_power_device():
    async def scenario(adapter):
        adapter.appear(OTHER, "Powermeter", -50, services=(CYCLING_POWER_SERVICE,))
        adapter.appear("AA:00:00:00:10:03", "Powermeter 2", -60, services=(CYCLING_POWER_SERVICE,))
        source = source_for(adapter)
        await source.connect()
        assert adapter.connected == {OTHER}
        assert source.capabilities == {Capability.POWER, Capability.CADENCE}  # nur Cycling Power

    run(scenario)


def test_a_device_found_later_within_the_settle_time_can_win():
    async def scenario(adapter):
        adapter.appear(OTHER, "Powermeter", -40, services=(CYCLING_POWER_SERVICE,))
        source = TrainerSource(adapter, scan_s=1.0, settle_s=0.3)
        connecting = asyncio.create_task(source.connect())
        await asyncio.sleep(0.1)
        kickr(adapter, KICKR, rssi=-90)
        await connecting
        assert adapter.connected == {KICKR}

    run(scenario)


def test_address_selects_exactly_that_device_case_insensitive():
    async def scenario(adapter):
        kickr(adapter, KICKR, rssi=-40)
        kickr(adapter, OTHER, rssi=-80)
        await source_for(adapter, OTHER.lower()).connect()
        assert adapter.connected == {OTHER}

    run(scenario)


def test_other_devices_are_not_a_trainer():
    async def scenario(adapter):
        adapter.appear(OTHER, "Brustgurt", -40, services=(HEART_RATE_SERVICE,))
        with pytest.raises(SourceDisconnectedError, match="nicht gefunden"):
            await source_for(adapter).connect()
        assert adapter.connect_attempts == [] and not adapter.scanning

    run(scenario)


def test_unset_address_not_present_raises_disconnected():
    async def scenario(adapter):
        kickr(adapter, KICKR)
        with pytest.raises(SourceDisconnectedError, match=OTHER):
            await source_for(adapter, OTHER).connect()
        assert adapter.connect_attempts == []

    run(scenario)


def test_scan_failure_is_a_disconnect():
    async def scenario(adapter):
        adapter.scan_failures = 1
        with pytest.raises(SourceDisconnectedError):
            await source_for(adapter).connect()

    run(scenario)


# --- Features → Capabilities -----------------------------------------------------------------


@pytest.mark.parametrize(
    ("bits", "services", "expected"),
    [
        (FEATURES_CADENCE_POWER, (FTMS_SERVICE, CYCLING_POWER_SERVICE), {"CADENCE", "POWER", "SPEED"}),
        (FEATURES_CADENCE_POWER, (FTMS_SERVICE,), {"CADENCE", "POWER", "SPEED"}),
        (0x0002, (FTMS_SERVICE,), {"CADENCE", "SPEED"}),  # Kadenz ohne Leistungsmessung
        (FEATURES_POWER_ONLY, (FTMS_SERVICE,), {"POWER", "SPEED"}),  # keine Kadenz, kein Cycling Power
        (FEATURES_POWER_ONLY, (FTMS_SERVICE, CYCLING_POWER_SERVICE), {"CADENCE", "POWER", "SPEED"}),  # Kadenz über CP
        (0, (FTMS_SERVICE,), {"SPEED"}),
    ],
)
def test_capabilities_follow_the_features(bits, services, expected):
    async def scenario(adapter):
        kickr(adapter, bits=bits, services=services)
        source = source_for(adapter)
        assert source.capabilities == {Capability.CADENCE}  # vor dem ersten Verbinden
        await source.connect()
        assert {str(capability) for capability in source.capabilities} == expected
        assert Capability.RESISTANCE_CONTROL not in source.capabilities  # Steuern ist ein eigenes Paket

    run(scenario)


def test_features_read_failure_is_a_disconnect_and_closes_the_connection():
    async def scenario(adapter):
        kickr(adapter)
        adapter.fail_reads[KICKR] = 1
        source = source_for(adapter)
        with pytest.raises(SourceDisconnectedError):
            await source.connect()
        assert adapter.connected == set()
        await source.connect()  # beim nächsten Versuch klappt es
        assert adapter.connected == {KICKR}

    run(scenario)


def test_unreadable_features_are_a_disconnect():
    async def scenario(adapter):
        kickr(adapter)
        adapter.set_readable(KICKR, FITNESS_MACHINE_FEATURE, b"\x02")
        with pytest.raises(SourceDisconnectedError):
            await source_for(adapter).connect()
        assert adapter.connected == set()

    run(scenario)


def test_refused_connection_is_a_disconnect():
    async def scenario(adapter):
        kickr(adapter)
        adapter.refuse(KICKR)
        with pytest.raises(SourceDisconnectedError):
            await source_for(adapter).connect()

    run(scenario)


# --- Notifications ---------------------------------------------------------------------------


def test_indoor_bike_data_comes_raw_and_decodes_as_measured():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        payloads = [bike(25.0, 84, 140), bike(26.5, 90, 160)]
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, *payloads)
        items = await take(stream, 2)
        assert [(item.char, item.data) for item in items] == [(INDOOR_BIKE_DATA, p) for p in payloads]
        assert items[0].t_ms <= items[1].t_ms
        decoder = Decoder(power_estimated=source.power_estimated)
        first, second = (decoder.decode(item) for item in items)
        assert (first.speed_kmh, first.cadence, first.power_w, first.power_estimated) == (25.0, 84.0, 140, False)
        assert (second.speed_kmh, second.cadence, second.power_w) == (26.5, 90.0, 160)
        # Genau 0x2AD2 ist abonniert (Kadenz kommt hier aus Indoor Bike Data, nicht aus Cycling Power).
        assert set(adapter.connections[KICKR].subscriptions) == {INDOOR_BIKE_DATA}

    run(scenario)


def test_cadence_only_in_cycling_power_when_the_features_say_so():
    async def scenario(adapter):
        kickr(adapter, bits=FEATURES_POWER_ONLY)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        assert set(adapter.connections[KICKR].subscriptions) == {INDOOR_BIKE_DATA, CYCLING_POWER_MEASUREMENT}
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(25.0, None, 200))
        await pump(adapter, KICKR, CYCLING_POWER_MEASUREMENT, cycling_power(200, crank=(10, 0)))
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(25.0, None, 200))
        await pump(adapter, KICKR, CYCLING_POWER_MEASUREMENT, cycling_power(201, crank=(11, 1024)))
        items = await take(stream, 4)
        assert [item.char for item in items] == [INDOOR_BIKE_DATA, CYCLING_POWER_MEASUREMENT] * 2
        decoder = Decoder(power_estimated=False)
        samples = [decoder.decode(item) for item in items]
        assert [s.cadence for s in samples] == [None, None, None, 60.0]
        assert {s.speed_kmh for s in samples[1:]} == {25.0}  # kein Sample setzt das Tempo auf None
        assert {s.power_w for s in samples} == {200}

    run(scenario)


def test_cycling_power_is_added_when_indoor_bike_data_has_no_cadence():
    async def scenario(adapter):
        kickr(adapter)  # die Features versprechen Kadenz
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        subscriptions = adapter.connections[KICKR].subscriptions
        assert set(subscriptions) == {INDOOR_BIKE_DATA}
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, *[bike(25.0, None, 150)] * 2)
        assert set(subscriptions) == {INDOOR_BIKE_DATA}  # zwei Notifications ohne Kadenz reichen noch nicht
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(25.0, None, 150))
        # Die Quelle abonniert beim Weiterreichen der dritten Notification nach.
        await take(stream, 3)
        assert set(subscriptions) == {INDOOR_BIKE_DATA, CYCLING_POWER_MEASUREMENT}
        adapter.indicate(KICKR, CYCLING_POWER_MEASUREMENT, cycling_power(150, crank=(1, 1)))
        [item] = await take(stream, 1)
        assert item.char == CYCLING_POWER_MEASUREMENT

    run(scenario)


def test_cycling_power_stays_off_when_indoor_bike_data_has_cadence():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(25.0, 80, 150), *[bike(25.0, None, 150)] * 5)
        await take(stream, 6)
        assert set(adapter.connections[KICKR].subscriptions) == {INDOOR_BIKE_DATA}

    run(scenario)


def test_no_cycling_power_to_add_without_the_service():
    async def scenario(adapter):
        kickr(adapter, services=(FTMS_SERVICE,))
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, *[bike(25.0, None, 150)] * 4)
        await take(stream, 4)
        assert set(adapter.connections[KICKR].subscriptions) == {INDOOR_BIKE_DATA}

    run(scenario)


def test_cycling_power_subscription_failure_is_a_disconnect():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        connection = adapter.connections[KICKR]
        original = connection.subscribe

        async def refusing(char, on_notify):
            if char == CYCLING_POWER_MEASUREMENT:
                from vspin_bridge.ble import BleError

                raise BleError("nicht abonnierbar")
            await original(char, on_notify)

        connection.subscribe = refusing
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, *[bike(25.0, None, 150)] * 3)
        with pytest.raises(SourceDisconnectedError, match="Cycling Power"):
            await take(stream, 3)
        assert adapter.connected == set()

    run(scenario)


def test_broken_bike_notifications_do_not_count_as_missing_cadence():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, *[b"\x04"] * 4)  # zu kurz
        await take(stream, 4)
        assert set(adapter.connections[KICKR].subscriptions) == {INDOOR_BIKE_DATA}

    run(scenario)


# --- Abbruch und Neuverbinden ----------------------------------------------------------------


def test_drop_raises_after_the_pending_notifications_and_connect_works_again():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(25.0, 80, 150))
        adapter.drop(KICKR)
        seen: list[RawNotification] = []
        with pytest.raises(SourceDisconnectedError):
            async with asyncio.timeout(TIMEOUT_S):
                async for item in source.samples():
                    seen.append(item)
        assert len(seen) == 1  # was vor dem Abbruch ankam, geht nicht verloren
        with pytest.raises(SourceDisconnectedError):
            await take(source.samples(), 1)  # ohne neues `connect` liefert die Quelle nichts

        await source.connect()
        stream = source.samples()
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(26.0, 82, 155))
        [item] = await take(stream, 1)
        assert item.data == bike(26.0, 82, 155)

    run(scenario)


def test_trainer_missing_at_the_start_then_back():
    async def scenario(adapter):
        source = source_for(adapter)
        with pytest.raises(SourceDisconnectedError):
            await source.connect()
        kickr(adapter)
        await source.connect()
        assert adapter.connected == {KICKR}

    run(scenario)


def test_stale_notifications_of_the_old_connection_do_not_reach_the_new_one():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        old = adapter.connections[KICKR]
        adapter.drop(KICKR)
        await source.connect()
        stream = source.samples()
        old.notify(bike(1.0, 1, 1), INDOOR_BIKE_DATA)  # Nachzügler der alten Verbindung
        await pump(adapter, KICKR, INDOOR_BIKE_DATA, bike(30.0, 80, 150))
        [item] = await take(stream, 1)
        assert item.data == bike(30.0, 80, 150)

    run(scenario)


def test_closing_the_samples_disconnects():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        stream = source.samples()
        task = asyncio.create_task(anext(stream))
        await asyncio.sleep(0.05)
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
        await stream.aclose()
        assert adapter.connected == set()

    run(scenario)


def test_cancelled_while_searching_leaves_no_scan():
    async def scenario(adapter):
        source = TrainerSource(adapter, scan_s=5.0)
        task = asyncio.create_task(source.connect())
        await asyncio.sleep(0.05)
        assert adapter.scanning
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
        assert not adapter.scanning

    run(scenario)


# --- Nur-lesen-Modus (Story 5) ---------------------------------------------------------------


def test_read_only_never_requests_control_nor_writes():
    async def scenario(adapter):
        sim_kickr(adapter)  # der Trainer könnte gesteuert werden
        source = TrainerSource(adapter, scan_s=0.3, settle_s=0.05, read_only=True)
        changes = []
        source.on_control_changed = lambda state, reason: changes.append(state)
        assert source.control is ControlState.READ_ONLY
        await source.connect()
        subscriptions = set(adapter.connections[KICKR].subscriptions)
        assert CONTROL_POINT not in subscriptions and MACHINE_STATUS not in subscriptions
        assert Capability.RESISTANCE_CONTROL not in source.capabilities
        with pytest.raises(ControlRefusedError) as refused:
            await source.set_grade(0.07)
        assert refused.value.reason == "read_only"
        assert await source.reset_grade() is False
        await source.release()
        adapter.drop(KICKR)
        await source.connect()
        assert source.control is ControlState.READ_ONLY and changes == []  # bleibt read_only, auch über Abbrüche

    run(scenario)


def test_trainer_without_simulation_is_read_only_by_nature():
    async def scenario(adapter):
        kickr(adapter)
        source = source_for(adapter)
        await source.connect()
        assert source.control is ControlState.NOT_SUPPORTED
        assert await source.reset_grade() is False
        await source.release()

    run(scenario)


# --- Kommandozeile ---------------------------------------------------------------------------


def test_cli_builds_the_trainer_source_with_bleak_without_touching_hardware():
    args = cli.build_parser().parse_args(["--source", "ble", "--trainer", KICKR])
    source = cli.SOURCES["ble"](args)
    assert isinstance(source, TrainerSource) and source.name == "ble"
    assert source._address == KICKR
    assert type(source._adapter).__name__ == "BleakAdapter"


def test_cli_help_names_the_default_choice():
    text = " ".join(cli.build_parser().format_help().split())
    assert "--trainer ADRESSE" in text
    assert "stärkste Gerät mit FTMS" in text


def test_cli_read_only_builds_a_read_only_trainer_source():
    source = cli.SOURCES["ble"](cli.build_parser().parse_args(["--source", "ble", "--read-only"]))
    assert source.control is ControlState.READ_ONLY
    assert cli.SOURCES["ble"](cli.build_parser().parse_args(["--source", "ble"])).control is ControlState.NONE


def test_cli_read_only_needs_the_ble_source(capsys):
    with pytest.raises(SystemExit) as exit_:
        cli.main(["--source", "sim", "--read-only"])
    assert exit_.value.code == 2
    assert "--read-only gibt es nur mit --source ble" in capsys.readouterr().err


def test_cli_trainer_needs_the_ble_source(capsys):
    with pytest.raises(SystemExit) as exit_:
        cli.main(["--source", "sim", "--trainer", KICKR])
    assert exit_.value.code == 2
    assert "--trainer gibt es nur mit --source ble" in capsys.readouterr().err
