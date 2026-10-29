"""ControllerSource gegen den BLE-Fake (Spec #89, Messteil): erst abonnieren, dann einmal `RideOn` je Verbindung, die
Antwort als Hypothese eingeordnet (`answered` / `encrypted` / `no_answer`), nie ein Schreibzugriff bei `locked`, das
Rohprotokoll (`on_log`).

Die Antwortrahmen sind aus der öffentlichen Prosa-Beschreibung des Zwift-Play-Protokolls gebaut: `RideOn`, bei
Schlüsseltausch gefolgt von 2 Byte und einem öffentlichen Schlüssel (64 Byte). Asynchron über `asyncio.run`.
"""

import asyncio
import time
from collections.abc import Callable

from fake_ble import FakeBleAdapter

from vspin_bridge.ble import GattCharacteristic
from vspin_bridge.sources.controller import (
    RIDE_ON,
    RIDE_SERVICE,
    RIDE_SERVICE_LEGACY,
    ZWIFT_COMPANY_ID,
    ZWIFT_CONTROL_POINT,
    ZWIFT_MEASUREMENT,
    ZWIFT_RESPONSE,
    ControllerDevice,
    ControllerSource,
    ControllerState,
    ControllerStatus,
    Handshake,
    Side,
    classify_answer,
    short_uuid,
)

LEFT = ControllerDevice("CC:00:00:00:00:08", "Zwift SF2", Side.LEFT)
BATTERY_SERVICE = "0000180f-0000-1000-8000-00805f9b34fb"
UNKNOWN_NOTIFY = "00000006-19ca-4651-86e5-fa29dcdd09d1"  # weitere Characteristic, die die Datenbank nennt

ANSWER_PLAIN = RIDE_ON + b"\x01\x02"
ANSWER_KEY = RIDE_ON + b"\x01\x02" + bytes(range(64))  # 2 Byte und öffentlicher Schlüssel
BUTTON_FRAME = bytes.fromhex("23 08 ff ff ff ff 0f")  # irgendein späterer Rahmen; wird nicht ausgewertet

# Gerätedatenbank wie in der Beschreibung (die tatsächliche des Ride V2 ist unbelegt)
PLAY_CHARS = (
    GattCharacteristic(RIDE_SERVICE, ZWIFT_MEASUREMENT, frozenset({"notify"})),
    GattCharacteristic(RIDE_SERVICE, ZWIFT_CONTROL_POINT, frozenset({"write"})),
    GattCharacteristic(RIDE_SERVICE, ZWIFT_RESPONSE, frozenset({"indicate"})),
    GattCharacteristic(RIDE_SERVICE, UNKNOWN_NOTIFY, frozenset({"notify", "read"})),
    GattCharacteristic(BATTERY_SERVICE, "00002a19-0000-1000-8000-00805f9b34fb", frozenset({"read", "notify"})),
)


class Owner:
    """Besitzer der Quelle: sammelt Zustandsmeldungen und das Rohprotokoll."""

    def __init__(self) -> None:
        self.statuses: list[ControllerStatus] = []
        self.log: list[dict] = []

    def events(self, *names: str) -> list[dict]:
        return [entry for entry in self.log if entry["event"] in names]


def run(scenario: Callable[[FakeBleAdapter, ControllerSource, Owner], object], timeout_s: float = 0.3) -> None:
    async def main() -> None:
        adapter = FakeBleAdapter()
        owner = Owner()
        source = ControllerSource(
            adapter, owner.statuses.append, retry_s=0.05, locked_retry_s=30.0, handshake_timeout_s=timeout_s
        )
        source.on_log = owner.log.append
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


def appear(adapter: FakeBleAdapter, chars=PLAY_CHARS, services=(RIDE_SERVICE, BATTERY_SERVICE)) -> None:
    adapter.appear(
        LEFT.address, LEFT.name, -61, manufacturer_data={ZWIFT_COMPANY_ID: bytes([8, 1])}, gatt_services=services,
        characteristics=chars,
    )


def handshake(source: ControllerSource) -> Handshake:
    return source.status.handshake


def ride_on_writes(adapter: FakeBleAdapter) -> list[tuple[str, str, bytes]]:
    return [write for write in adapter.writes if write[2] == RIDE_ON]


# --- Einordnung (rein) ---------------------------------------------------------------------------


def test_answers_are_classified_after_the_description():
    assert classify_answer(RIDE_ON) is Handshake.ANSWERED
    assert classify_answer(ANSWER_PLAIN) is Handshake.ANSWERED
    assert classify_answer(RIDE_ON + bytes(63)) is Handshake.ANSWERED  # zu kurz für einen Schlüssel
    assert classify_answer(RIDE_ON + bytes(64)) is Handshake.ENCRYPTED
    assert classify_answer(ANSWER_KEY) is Handshake.ENCRYPTED
    assert classify_answer(BUTTON_FRAME) is None
    assert classify_answer(b"Ride") is None


def test_short_uuids():
    assert short_uuid(ZWIFT_CONTROL_POINT) == "0003"
    assert short_uuid(RIDE_SERVICE) == "fc82"
    assert short_uuid("0000fff0-1111-2222-3333-444455556666") == "0000fff0-1111-2222-3333-444455556666"


# --- Handshake ------------------------------------------------------------------------------------


def test_subscribes_every_notify_and_indicate_of_the_zwift_service_before_writing_ride_on_once():
    async def scenario(adapter, source, owner):
        appear(adapter)
        # Wie am echten Gerät: Schreiben scheitert, solange die Antwort-Characteristic nicht abonniert ist.
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ANSWERED)
        connection = adapter.connections[LEFT.address]
        # nicht die Batterie: nur die Zwift-Services
        assert set(connection.subscriptions) == {ZWIFT_MEASUREMENT, ZWIFT_RESPONSE, UNKNOWN_NOTIFY}
        assert adapter.writes == [(LEFT.address, ZWIFT_CONTROL_POINT, b"RideOn")]
        assert adapter.writes_without_response == []
        assert RIDE_ON == bytes.fromhex("52 69 64 65 4F 6E")
        order = [(e["event"], e.get("char")) for e in owner.events("subscribe", "write")]
        assert order == [("subscribe", "0002"), ("subscribe", "0004"), ("subscribe", "0006"), ("write", "0003")]
        await asyncio.sleep(0.4)  # über das Zeitlimit hinaus: kein zweiter Versuch, der Stand bleibt
        assert len(adapter.writes) == 1 and handshake(source) is Handshake.ANSWERED

    run(scenario)


def test_answered_handshake_is_part_of_the_status():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ANSWERED)
        assert source.status.state is ControllerState.CONNECTED
        assert [status.handshake for status in owner.statuses if status.state is ControllerState.CONNECTED][-1] == (
            Handshake.ANSWERED
        )

    run(scenario)


def test_answer_with_key_material_is_encrypted_and_never_written_again():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_KEY)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ENCRYPTED)
        adapter.drop(LEFT.address)
        await until(lambda: source.status.state is ControllerState.DISCONNECTED)
        assert source.status.handshake is Handshake.NONE
        await until(lambda: source.status.state is ControllerState.CONNECTED)
        assert handshake(source) is Handshake.ENCRYPTED  # gleich wieder, ohne zu schreiben
        await asyncio.sleep(0.4)
        assert len(ride_on_writes(adapter)) == 1
        assert set(adapter.connections[LEFT.address].subscriptions) == {ZWIFT_MEASUREMENT, ZWIFT_RESPONSE,
                                                                        UNKNOWN_NOTIFY}  # mitgeschnitten wird weiter

    run(scenario)


def test_no_answer_within_the_time_limit():
    async def scenario(adapter, source, owner):
        appear(adapter)
        await source.set_known_devices([LEFT])
        await until(lambda: source.status.state is ControllerState.CONNECTED)
        assert handshake(source) is Handshake.NONE  # Antwort steht aus
        started = time.monotonic()
        await until(lambda: handshake(source) is Handshake.NO_ANSWER)
        assert time.monotonic() - started > 0.2
        assert len(ride_on_writes(adapter)) == 1

    run(scenario)


def test_a_late_answer_still_counts():
    async def scenario(adapter, source, owner):
        appear(adapter)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.NO_ANSWER)
        adapter.indicate(LEFT.address, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await until(lambda: handshake(source) is Handshake.ANSWERED)

    run(scenario, timeout_s=0.05)


def test_answer_before_the_write_is_acknowledged_counts():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.answer_before_ack = True
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ANSWERED)
        await asyncio.sleep(0.4)
        assert handshake(source) is Handshake.ANSWERED  # kein `no_answer` hinterher

    run(scenario)


def test_without_characteristics_in_the_database_the_described_ones_are_used():
    async def scenario(adapter, source, owner):
        appear(adapter, chars=())
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ANSWERED)
        assert set(adapter.connections[LEFT.address].subscriptions) == {ZWIFT_MEASUREMENT, ZWIFT_RESPONSE}
        assert adapter.writes == [(LEFT.address, ZWIFT_CONTROL_POINT, RIDE_ON)]
        [services] = owner.events("services")
        assert services["chars"] == [] and services["services"] == sorted({RIDE_SERVICE, BATTERY_SERVICE})

    run(scenario)


def test_legacy_service_and_write_without_response():
    chars = (
        GattCharacteristic(RIDE_SERVICE_LEGACY, ZWIFT_MEASUREMENT, frozenset({"notify"})),
        GattCharacteristic(RIDE_SERVICE_LEGACY, ZWIFT_CONTROL_POINT, frozenset({"write-without-response"})),
        GattCharacteristic(RIDE_SERVICE_LEGACY, ZWIFT_RESPONSE, frozenset({"indicate"})),
    )

    async def scenario(adapter, source, owner):
        appear(adapter, chars=chars, services=(RIDE_SERVICE_LEGACY,))
        await source.set_known_devices([LEFT])
        await until(lambda: len(adapter.writes) == 1)
        assert adapter.writes_without_response == [(LEFT.address, ZWIFT_CONTROL_POINT, RIDE_ON)]
        [write] = owner.events("write")
        assert write == {"event": "write", "char": "0003", "hex": "526964654f6e", "response": False}

    run(scenario)


def test_locked_controller_is_never_subscribed_or_written():
    async def scenario(adapter, source, owner):
        appear(adapter, services=(BATTERY_SERVICE,), chars=PLAY_CHARS[4:])
        await source.set_known_devices([LEFT])
        await until(lambda: source.status.state is ControllerState.LOCKED)
        await asyncio.sleep(0.1)
        assert adapter.writes == [] and adapter.connected == set()
        assert source.status.handshake is Handshake.NONE
        assert [e["event"] for e in owner.log] == ["connect", "services", "locked", "disconnect"]
        assert owner.events("locked") == [{"event": "locked", "address": LEFT.address, "name": "Zwift SF2",
                                           "side": "left"}]

    run(scenario)


def test_failed_write_is_logged_and_no_answer():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.fail_writes[LEFT.address] = 1
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.NO_ANSWER)
        assert source.status.state is ControllerState.CONNECTED  # bleibt verbunden, nur kein Handshake
        assert any("nicht beschreibbar" in e["text"] for e in owner.events("error"))
        assert adapter.writes == []

    run(scenario)


def test_failed_subscription_is_logged_and_the_others_go_on():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.fail_subscribes[LEFT.address] = 1  # die erste (`…0002`)
        await source.set_known_devices([LEFT])
        await until(lambda: len(adapter.writes) == 1)
        assert set(adapter.connections[LEFT.address].subscriptions) == {ZWIFT_RESPONSE, UNKNOWN_NOTIFY}
        assert any("nicht abonnierbar" in e["text"] for e in owner.events("error"))

    run(scenario)


# --- Rohprotokoll ---------------------------------------------------------------------------------


def test_raw_log_of_one_connection():
    async def scenario(adapter, source, owner):
        appear(adapter)
        adapter.answer(LEFT.address, ZWIFT_CONTROL_POINT, ZWIFT_RESPONSE, ANSWER_PLAIN)
        await source.set_known_devices([LEFT])
        await until(lambda: handshake(source) is Handshake.ANSWERED)
        adapter.indicate(LEFT.address, ZWIFT_MEASUREMENT, BUTTON_FRAME)
        adapter.indicate(LEFT.address, UNKNOWN_NOTIFY, b"\x01")
        adapter.drop(LEFT.address)
        await until(lambda: source.status.state is ControllerState.DISCONNECTED)
        device = {"address": LEFT.address, "name": "Zwift SF2", "side": "left"}
        assert owner.log[0] == {"event": "connect", **device, "rssi": -61}
        assert owner.log[1]["event"] == "services"
        assert {"service": RIDE_SERVICE, "char": ZWIFT_CONTROL_POINT, "properties": ["write"]} in owner.log[1]["chars"]
        assert {"service": RIDE_SERVICE, "char": UNKNOWN_NOTIFY, "properties": ["notify", "read"]} in (
            owner.log[1]["chars"]
        )
        assert owner.log[2:] == [
            {"event": "subscribe", "char": "0002", "kind": "notification"},
            {"event": "subscribe", "char": "0004", "kind": "indication"},
            {"event": "subscribe", "char": "0006", "kind": "notification"},
            {"event": "write", "char": "0003", "hex": "526964654f6e", "response": True},
            {"event": "indication", "char": "0004", "hex": ANSWER_PLAIN.hex()},
            {"event": "handshake", "state": "answered"},
            {"event": "notification", "char": "0002", "hex": BUTTON_FRAME.hex()},
            {"event": "notification", "char": "0006", "hex": "01"},
            {"event": "disconnect", **device, "by": "device"},
        ]

    run(scenario)
