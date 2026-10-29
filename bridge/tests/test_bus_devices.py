"""Rollen-Bus und Verbindungsfenster (Spec #75, P4): `set_devices`, Suche je Rolle, Aliase aus #64, Status je Rolle,
Trainerwahl aus gemerkten Geräten, Gerätewechsel mit Freigabe, Controller (sichtbar, gesperrt, Batterie, nie ein
Schreibzugriff) und „Steuerung zurückholen“ nach `lost`.

Die Bridge läuft im Testprozess, jede Rolle auf einem eigenen BLE-Fake (`fake_ble.py`) wie in echt auf einem eigenen
`BleakAdapter`. Alles, was einen Fake skriptet, läuft über `bridge.call` im Event-Loop der Bridge.
"""

import time
from collections.abc import Callable, Iterator

import pytest
from bridge_harness import HOST, InProcessBridge, wait_until
from fake_ble import FakeBleAdapter
from heart_rate_harness import STRAP, BusReader, HeartRateRig, block, pulse
from trainer_harness import KICKR, TARGET_SIMULATION, control_responder, control_writes, kickr, simulation

from vspin_bridge import app, cli
from vspin_bridge.sources.controller import BATTERY_LEVEL, RIDE_SERVICE, ZWIFT_COMPANY_ID, ControllerSource
from vspin_bridge.sources.heart_rate import HEART_RATE_SERVICE
from vspin_bridge.sources.sim import SimulatorSource
from vspin_bridge.sources.trainer import FTMS_SERVICE, TrainerSource
from vspin_bridge.sources.trainer_control import CONTROL_POINT, MACHINE_STATUS

pytestmark = pytest.mark.usefixtures("isolated_bus")

OTHER = "AA:00:00:00:10:02"  # zweiter Trainer
STRANGER = "AA:00:00:00:10:03"  # Trainer, der nicht gemerkt ist
LEFT = "CC:00:00:00:00:08"
RIGHT = "CC:00:00:00:00:07"
BATTERY_SERVICE = "0000180f-0000-1000-8000-00805f9b34fb"
REQUEST_CONTROL, RESET, START = b"\x00", b"\x01", b"\x07"
CONTROLLER_OFF = {"state": "off", "device": None, "battery": None}


class Rig:
    """Bridge mit Trainer (oder Simulator), Pulsquelle und Controller, je auf einem eigenen BLE-Fake."""

    def __init__(self, bridge: InProcessBridge, trainer: FakeBleAdapter, pulse: HeartRateRig, controller) -> None:
        self.bridge = bridge
        self.trainer = trainer
        self.pulse = pulse
        self.controller = controller

    def trainer_on(self, address: str, rssi: int, sim: bool = False) -> None:
        def on() -> None:
            if sim:
                self.trainer.answer(address, CONTROL_POINT, CONTROL_POINT, control_responder())
            kickr(self.trainer, address, rssi, targets=TARGET_SIMULATION if sim else 0)

        self.bridge.call(on)

    def controller_on(self, address: str, side: int | None, locked: bool = False, battery: int | None = 77,
                      name: str = "Zwift SF2", rssi: int = -62) -> None:
        manufacturer = None if side is None else {ZWIFT_COMPANY_ID: bytes([side, 0x01])}
        services = (BATTERY_SERVICE,) if locked else (RIDE_SERVICE, BATTERY_SERVICE)

        def on() -> None:
            adapter = self.controller.adapter
            adapter.appear(address, name, rssi, manufacturer_data=manufacturer, gatt_services=services)
            if battery is not None:
                adapter.set_readable(address, BATTERY_LEVEL, bytes([battery]))

        self.bridge.call(on)

    def trainer_writes(self, address: str = KICKR) -> list[bytes]:
        return self.bridge.call(control_writes, self.trainer, address)


class ControllerRig:
    def __init__(self, locked_retry_s: float) -> None:
        self.adapter = FakeBleAdapter()
        self.locked_retry_s = locked_retry_s
        self.source: ControllerSource | None = None

    def factory(self, on_status) -> ControllerSource:
        self.source = ControllerSource(self.adapter, on_status, retry_s=0.05, locked_retry_s=self.locked_retry_s)
        return self.source


@pytest.fixture
def devices_bridge(request, tmp_path, monkeypatch) -> Iterator[Callable[..., Rig]]:
    """Fabrik: `devices_bridge(trainer=True, known_only=False, read_only=False)` – Bridge mit `TrainerSource` (sonst
    Simulator), Pulsquelle und Controller auf eigenen Fakes; Neuverbinden nach 0,1 s statt 3 s."""
    monkeypatch.setattr(app, "RECONNECT_INTERVAL_S", 0.1)
    started: list[InProcessBridge] = []

    def start(trainer: bool = True, known_only: bool = False, read_only: bool = False,
              locked_retry_s: float = 30.0) -> Rig:
        trainer_adapter = FakeBleAdapter()
        pulse_rig = HeartRateRig()
        controller_rig = ControllerRig(locked_retry_s)
        source = (
            TrainerSource(trainer_adapter, scan_s=0.3, settle_s=0.05, read_only=read_only, known_only=known_only)
            if trainer
            else SimulatorSource(cadence=80)
        )
        bridge = InProcessBridge(
            source,
            tmp_path / "sessions",
            getattr(request.node, "bus_host", HOST),
            pulse_rig.factory,
            controller_rig.factory,
        )
        started.append(bridge)
        bridge.start()
        return Rig(bridge, trainer_adapter, pulse_rig, controller_rig)

    yield start
    for bridge in started:
        bridge.stop()


def ack(for_type: str, ok: bool = True, reason: str | None = None) -> dict:
    return {"v": 0, "type": "ack", "for": for_type, "ok": ok, "reason": reason}


def set_devices(kind: str, *devices: dict) -> dict:
    return {"v": 0, "type": "set_devices", "kind": kind, "devices": list(devices)}


def trainer(address: str, name: str = "KICKR") -> dict:
    return {"address": address, "name": name}


def controller(address: str, side: str | None) -> dict:
    return {"address": address, "name": "Zwift SF2", "side": side}


def start_search(kind: str, duration_s: float = 30.0) -> dict:
    return {"v": 0, "type": "start_device_search", "kind": kind, "duration_s": duration_s}


def stop_search(kind: str | None = None) -> dict:
    message = {"v": 0, "type": "stop_device_search"}
    return message if kind is None else message | {"kind": kind}


RECLAIM = {"v": 0, "type": "reclaim_trainer_control"}


def statuses(messages: list[dict]) -> list[dict]:
    return [m for m in messages if m["type"] == "status"]


def without_time(status: dict) -> dict:
    return {key: value for key, value in status.items() if key != "t_ms"}


def assert_one_status_per_change(reader: BusReader) -> None:
    seen = [without_time(m) for m in reader.statuses()]
    for before, after in zip(seen, seen[1:]):
        assert before != after, f"status ohne Änderung: {after}"


def connected_trainer(reader: BusReader) -> dict:
    if reader.first["state"] == "connected":
        return reader.first
    return reader.next("status", lambda m: m["state"] == "connected")


# --- Status je Rolle und set_devices -----------------------------------------------------------


def test_first_status_has_a_block_per_role(devices_bridge, bus_client):
    devices_bridge(trainer=False)
    status = BusReader(bus_client()).first
    assert status["trainer"] == {"control": "not_supported", "device": None, "mode": "sim", "target_power": None}
    assert status["heart_rate"] == {"state": "off", "device": None}
    assert status["controller"] == CONTROLLER_OFF
    assert status["signal"] == {"trainer": None, "heart_rate": None, "controller": None}


def test_set_devices_per_role_acks_and_broadcasts_exactly_one_status_per_change(devices_bridge, bus_client):
    devices_bridge(trainer=False)
    sender, other = BusReader(bus_client()), BusReader(bus_client())
    assert sender.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    assert sender.statuses()[-1]["controller"] == {"state": "disconnected", "device": None, "battery": None}
    assert sender.reply(set_devices("heart_rate", {"address": STRAP.address, "name": STRAP.name, "role": "strap"})) == (
        ack("set_devices")
    )
    assert sender.statuses()[-1]["heart_rate"] == {"state": "disconnected", "device": None}
    # Simulator: kein Trainer – quittiert, ohne Wirkung, kein `status`.
    assert sender.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    other.drain(0.5)
    assert len(other.statuses()) == 3  # erster Status, Controller, Puls
    # Dieselben Listen noch einmal: `ack`, keine Änderung, kein `status`.
    assert sender.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    other.drain(0.4)
    assert len(other.statuses()) == 3
    assert_one_status_per_change(other)


def test_alias_and_new_form_set_the_same_heart_rate_devices(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    strap = {"address": STRAP.address, "name": STRAP.name, "role": "strap"}
    assert client.reply(set_devices("heart_rate", strap)) == ack("set_devices")
    rig.bridge.call(rig.pulse.adapter.appear, STRAP.address, STRAP.name, -58, (HEART_RATE_SERVICE,))
    connected = client.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    assert connected["signal"]["heart_rate"] == -58  # Signalstärke der Ankündigung vor dem Verbinden
    rig.bridge.call(rig.pulse.adapter.notify, STRAP.address, pulse(97))
    assert client.next("telemetry", lambda m: m["heart_rate"] == 97)["heart_rate"] == 97
    # Der Alias aus #64 setzt dieselbe Liste: `ack` mit dem alten Typ, keine Änderung, kein `status`.
    alias = {"v": 0, "type": "set_heart_rate_devices", "devices": [strap]}
    assert client.reply(alias) == ack("set_heart_rate_devices")
    assert statuses(client.drain(0.4)) == []
    assert client.reply({"v": 0, "type": "set_heart_rate_devices", "devices": []}) == ack("set_heart_rate_devices")
    assert client.statuses()[-1]["heart_rate"] == {"state": "off", "device": None}
    assert client.statuses()[-1]["signal"]["heart_rate"] is None
    assert "Trainer:" not in rig.bridge.log() and "Pulsgeräte: keine – Puls aus" in rig.bridge.log()


def test_trainer_list_without_trainer_source_has_no_effect_and_search_is_not_supported(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    assert client.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    assert client.reply(start_search("trainer")) == ack("start_device_search", False, "not_supported")
    assert client.reply(RECLAIM) == ack("reclaim_trainer_control", False, "not_supported")
    assert "Trainer: KICKR (ohne Trainerquelle ohne Wirkung)" in rig.bridge.log()


BROKEN = [
    pytest.param(set_devices("bike", trainer(KICKR)), "invalid_kind", id="kind-unknown"),
    pytest.param({"v": 0, "type": "set_devices", "devices": []}, "invalid_kind", id="kind-missing"),
    pytest.param({"v": 0, "type": "start_device_search", "kind": 5}, "invalid_kind", id="kind-number"),
    pytest.param(stop_search("bike"), "invalid_kind", id="stop-kind-unknown"),
    pytest.param({"v": 0, "type": "set_devices", "kind": "trainer"}, "invalid_devices", id="devices-missing"),
    pytest.param(set_devices("trainer", {"address": "", "name": "x"}), "invalid_devices", id="address-empty"),
    pytest.param(set_devices("heart_rate", {"address": "A", "name": "x"}), "invalid_devices", id="role-missing"),
    pytest.param(set_devices("controller", controller(LEFT, "up")), "invalid_devices", id="side-unknown"),
    pytest.param(start_search("trainer", 0), "invalid_duration", id="duration-zero"),
    pytest.param(start_search("controller", 121), "invalid_duration", id="duration-too-long"),
]


@pytest.mark.parametrize(("payload", "reason"), BROKEN)
def test_broken_device_command_gets_error(devices_bridge, bus_client, payload, reason):
    devices_bridge()
    client = BusReader(bus_client())
    error = client.reply(payload)
    assert error["type"] == "error" and error["reason"] == reason and error["detail"]
    assert client.reply(stop_search()) == ack("stop_device_search")  # Verbindung offen


# --- Suche je Rolle -------------------------------------------------------------------------------


def test_searches_run_per_role_and_results_go_only_to_the_requester(devices_bridge, bus_client):
    rig = devices_bridge()
    first, second = BusReader(bus_client()), BusReader(bus_client())
    rig.trainer_on(STRANGER, -50)
    rig.controller_on(LEFT, 8)
    rig.controller_on(RIGHT, 7, rssi=-70)
    rig.bridge.call(rig.controller.adapter.appear, "DD:00:00:00:00:01", "Kopfhörer", -40)  # kein Controller
    assert first.reply(start_search("trainer", 1.0)) == ack("start_device_search")
    assert second.reply(start_search("controller", 1.0)) == ack("start_device_search")

    found_trainer = first.next("device_found")
    assert found_trainer == found_trainer | {"kind": "trainer", "address": STRANGER, "rssi": -50}  # auch nicht gemerkte
    assert list(found_trainer) == ["v", "type", "t_ms", "kind", "address", "name", "rssi"]
    ended = first.next("device_search_ended", timeout_s=3.0)
    assert list(ended) == ["v", "type", "t_ms", "kind", "reason"]
    assert (ended["kind"], ended["reason"]) == ("trainer", "timeout")

    second.next("device_search_ended", timeout_s=3.0)
    found = [m for m in second.seen if m["type"] == "device_found"]
    assert {(m["kind"], m["address"], m["side"]) for m in found} == {("controller", LEFT, "left"),
                                                                     ("controller", RIGHT, "right")}
    assert all(m["type"] != "device_found" or m["kind"] == "trainer" for m in first.seen)
    for address in (LEFT, RIGHT):  # gedrosselt wie in #64: höchstens einmal je Sekunde
        assert 1 <= sum(m["address"] == address for m in found) <= 2, found
    wait_until(lambda: not rig.bridge.call(lambda: rig.trainer.scanning), 3.0, "Trainersuche zu")
    assert "Trainersuche beendet (Zeit abgelaufen)" in rig.bridge.log()
    assert "Controllersuche beendet (Zeit abgelaufen)" in rig.bridge.log()


def test_controller_found_by_name_without_manufacturer_data_has_no_side(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, None)
    assert client.reply(start_search("controller")) == ack("start_device_search")
    found = client.next("device_found")
    assert (found["address"], found["name"], found["side"]) == (LEFT, "Zwift SF2", None)


def test_search_of_another_client_takes_over_in_its_own_form(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    old, new = BusReader(bus_client()), BusReader(bus_client())
    assert old.reply({"v": 0, "type": "start_heart_rate_search", "duration_s": 30}) == ack("start_heart_rate_search")
    assert new.reply(start_search("heart_rate")) == ack("start_device_search")
    assert old.next("heart_rate_search_ended")["reason"] == "taken_over"  # Alias: Antwort in der Form aus #64
    rig.bridge.call(rig.pulse.adapter.appear, "C0:00:00:00:00:01", "Polar H10", -55, (HEART_RATE_SERVICE,))
    found = new.next("device_found")
    assert (found["kind"], found["address"]) == ("heart_rate", "C0:00:00:00:00:01")
    assert old.reply({"v": 0, "type": "start_heart_rate_search", "duration_s": 30}) == ack("start_heart_rate_search")
    ended = new.next("device_search_ended")
    assert (ended["kind"], ended["reason"]) == ("heart_rate", "taken_over")
    assert old.next("heart_rate_found")["address"] == "C0:00:00:00:00:01"
    assert all(m["type"] != "device_found" for m in old.seen)


def test_stop_without_kind_ends_all_own_searches_with_ack_only(devices_bridge, bus_client):
    rig = devices_bridge()
    client, other = BusReader(bus_client()), BusReader(bus_client())
    assert client.reply(start_search("trainer")) == ack("start_device_search")
    assert client.reply(start_search("controller")) == ack("start_device_search")
    assert other.reply(start_search("heart_rate")) == ack("start_device_search")
    assert client.reply(stop_search()) == ack("stop_device_search")
    wait_until(lambda: not rig.bridge.call(lambda: rig.trainer.scanning), 3.0, "Trainersuche zu")
    assert rig.bridge.call(lambda: rig.pulse.source.searching), "die Suche des anderen läuft weiter"
    assert not rig.bridge.call(lambda: rig.controller.source.searching)
    assert [m for m in client.drain(0.4) if m["type"] == "device_search_ended"] == []


def test_search_ends_when_the_requester_disconnects(devices_bridge, bus_client):
    rig = devices_bridge()
    client = BusReader(bus_client())
    assert client.reply(start_search("trainer")) == ack("start_device_search")
    assert rig.bridge.call(lambda: rig.trainer.scanning)
    client.client.close()
    wait_until(lambda: not rig.bridge.call(lambda: rig.trainer.scanning), 3.0, "Suche endet mit dem Anfrager")
    assert "Trainersuche beendet (Client getrennt)" in rig.bridge.log()


# --- Trainer aus den gemerkten Geräten -----------------------------------------------------------


def test_strongest_remembered_sending_trainer_wins(devices_bridge, bus_client):
    rig = devices_bridge(known_only=True)
    client = BusReader(bus_client())
    rig.trainer_on(STRANGER, -40)  # am stärksten, aber nicht gemerkt
    rig.trainer_on(OTHER, -70)
    rig.trainer_on(KICKR, -55)
    assert client.reply(set_devices("trainer", trainer(OTHER, "Zweiter"), trainer(KICKR, "KICKR CORE"))) == (
        ack("set_devices")
    )
    status = connected_trainer(client)
    assert status["trainer"]["device"] == {"address": KICKR, "name": "KICKR CORE"}
    assert status["signal"]["trainer"] == -55
    assert rig.bridge.call(lambda: list(rig.trainer.connect_attempts)) == [KICKR]
    assert_one_status_per_change(client)


def test_empty_trainer_list_connects_nothing_until_a_trainer_is_remembered(devices_bridge, bus_client):
    rig = devices_bridge(known_only=True)
    client = BusReader(bus_client())
    rig.trainer_on(KICKR, -55)
    assert client.reply(set_devices("trainer")) == ack("set_devices")
    time.sleep(0.6)
    assert rig.bridge.call(lambda: (list(rig.trainer.connect_attempts), rig.trainer.scan_starts)) == ([], 0)
    assert client.first["state"] == "disconnected" and client.statuses() == [client.first]
    assert "Trainer: keine – kein Trainer verbindet sich von selbst" in rig.bridge.log()
    assert client.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    assert connected_trainer(client)["trainer"]["device"]["address"] == KICKR


def test_without_any_list_the_bridge_takes_the_strongest_trainer(devices_bridge, bus_client):
    rig = devices_bridge()  # wie von Hand ohne Spiel: P2-Verhalten
    rig.trainer_on(OTHER, -70)
    rig.trainer_on(KICKR, -50)
    status = connected_trainer(BusReader(bus_client()))
    assert status["trainer"]["device"] == {"address": KICKR, "name": "KICKR CORE 2 1234"}  # Name der Ankündigung
    # Ab der ersten Liste gilt nur sie – auch eine leere: der verbundene Trainer wird getrennt, keiner kommt nach.
    client = BusReader(bus_client())
    assert client.reply(set_devices("trainer")) == ack("set_devices")
    disconnected = client.next("status", lambda m: m["state"] == "disconnected")
    assert disconnected["trainer"]["device"] is None and disconnected["signal"]["trainer"] is None
    time.sleep(0.5)
    assert rig.bridge.call(lambda: rig.trainer.connected) == set()


def test_switching_the_trainer_releases_the_old_one_before_connecting_the_new(devices_bridge, bus_client):
    rig = devices_bridge(known_only=True)
    client = BusReader(bus_client())
    rig.trainer_on(KICKR, -55, sim=True)
    rig.trainer_on(OTHER, -60, sim=True)
    assert client.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    assert connected_trainer(client)["trainer"]["control"] == "active"
    assert client.reply({"v": 0, "type": "set_grade", "grade": 0.05}) == ack("set_grade")
    assert rig.trainer_writes(KICKR) == [REQUEST_CONTROL, START, simulation(500)]

    assert client.reply(set_devices("trainer", trainer(OTHER))) == ack("set_devices")
    # Freigabe am alten (Steigung 0, Reset), erst dann der neue – mit der zuletzt gemeldeten Steigung.
    assert rig.trainer_writes(KICKR) == [REQUEST_CONTROL, START, simulation(500), simulation(0), RESET]
    status = client.next("status", lambda m: m["state"] == "connected" and m["trainer"]["control"] == "active")
    assert status["trainer"]["device"]["address"] == OTHER
    wait_until(lambda: len(rig.trainer_writes(OTHER)) >= 3, 3.0, "Steigung am neuen Trainer")
    assert rig.trainer_writes(OTHER) == [REQUEST_CONTROL, START, simulation(500)]
    assert rig.bridge.call(lambda: rig.trainer.connected) == {OTHER}
    assert_one_status_per_change(client)


def test_forgetting_the_trainer_during_a_ride_releases_it_and_connects_none(devices_bridge, bus_client):
    rig = devices_bridge(known_only=True)
    client = BusReader(bus_client())
    rig.trainer_on(KICKR, -55, sim=True)
    assert client.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    assert connected_trainer(client)["trainer"]["control"] == "active"
    assert client.reply({"v": 0, "type": "set_grade", "grade": 0.05}) == ack("set_grade")
    assert client.reply(set_devices("trainer")) == ack("set_devices")  # „Vergessen“ im Fenster
    assert rig.trainer_writes() == [REQUEST_CONTROL, START, simulation(500), simulation(0), RESET]
    disconnected = client.next("status", lambda m: m["state"] == "disconnected")
    assert disconnected["trainer"] == {"control": "none", "device": None, "mode": "sim", "target_power": None}
    time.sleep(0.5)
    assert rig.bridge.call(lambda: (rig.trainer.connected, list(rig.trainer.connect_attempts))) == (set(), [KICKR])
    assert rig.trainer_writes() == [REQUEST_CONTROL, START, simulation(500), simulation(0), RESET]


# --- Steuerung zurückholen -----------------------------------------------------------------------


def test_reclaim_after_lost_requests_again_and_resends_the_last_grade(devices_bridge, bus_client):
    rig = devices_bridge()
    rig.trainer_on(KICKR, -55, sim=True)
    client = BusReader(bus_client())
    connected_trainer(client)
    assert client.reply({"v": 0, "type": "set_grade", "grade": 0.04}) == ack("set_grade")
    rig.bridge.call(rig.trainer.indicate, KICKR, MACHINE_STATUS, b"\xff")  # Zwift übernimmt
    assert client.next("status")["trainer"]["control"] == "lost"
    time.sleep(0.3)
    assert rig.trainer_writes() == [REQUEST_CONTROL, START, simulation(400)]  # bei `lost` nichts von selbst

    assert client.reply(RECLAIM) == ack("reclaim_trainer_control")
    assert rig.trainer_writes() == [REQUEST_CONTROL, START, simulation(400)] * 2
    controls = [m["trainer"]["control"] for m in client.statuses()]
    assert controls[-3:] == ["lost", "requesting", "active"]
    assert client.reply({"v": 0, "type": "set_grade", "grade": 0.06}) == ack("set_grade")
    assert "Steuerung zurückholen -> ok" in rig.bridge.log()
    assert_one_status_per_change(client)


def test_reclaim_refused_by_the_trainer_stays_lost(devices_bridge, bus_client):
    rig = devices_bridge()
    rig.trainer_on(KICKR, -55, sim=True)
    client = BusReader(bus_client())
    connected_trainer(client)
    rig.bridge.call(rig.trainer.indicate, KICKR, MACHINE_STATUS, b"\xff")
    client.next("status", lambda m: m["trainer"]["control"] == "lost")
    rig.bridge.call(rig.trainer.answer, KICKR, CONTROL_POINT, CONTROL_POINT, control_responder({0x00: 0x05}))
    assert client.reply(RECLAIM) == ack("reclaim_trainer_control", False, "control_lost")
    assert client.statuses()[-1]["trainer"]["control"] == "lost"
    assert rig.trainer_writes() == [REQUEST_CONTROL, START, REQUEST_CONTROL]  # kein `0x07`, keine Steigung


def test_reclaim_in_read_only_mode_writes_nothing(devices_bridge, bus_client):
    rig = devices_bridge(read_only=True)
    rig.trainer_on(KICKR, -55, sim=True)
    client = BusReader(bus_client())
    assert connected_trainer(client)["trainer"]["control"] == "read_only"
    assert client.reply(RECLAIM) == ack("reclaim_trainer_control", False, "read_only")
    assert rig.bridge.call(lambda: list(rig.trainer.writes)) == []


def test_reclaim_while_active_changes_nothing(devices_bridge, bus_client):
    rig = devices_bridge()
    rig.trainer_on(KICKR, -55, sim=True)
    client = BusReader(bus_client())
    connected_trainer(client)
    assert client.reply(RECLAIM) == ack("reclaim_trainer_control")
    assert rig.trainer_writes() == [REQUEST_CONTROL, START]


# --- Controller ----------------------------------------------------------------------------------


def assert_controller_never_written(rig: Rig) -> None:
    adapter = rig.controller.adapter
    assert rig.bridge.call(lambda: list(adapter.writes)) == []
    assert rig.bridge.call(lambda: [c.subscriptions for c in adapter.connections.values()]) in ([], [{}])


def test_visible_controller_connects_with_battery_and_without_a_single_write(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, 8, battery=81, rssi=-61)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    status = client.next("status", lambda m: m["controller"]["state"] == "connected")
    assert status["controller"] == {
        "state": "connected",
        "device": {"address": LEFT, "name": "Zwift SF2", "side": "left"},
        "battery": 81,
    }
    assert status["signal"]["controller"] == -61
    assert rig.bridge.call(lambda: rig.controller.adapter.connected) == {LEFT}
    assert_controller_never_written(rig)
    assert "Controller: connected, Zwift SF2 (left), Batterie 81 %" in rig.bridge.log()
    assert rig.bridge.stop() is None
    # Loop beendet: direkt lesen. Auch das Beenden schreibt nichts, die Verbindung ist zu.
    assert rig.controller.adapter.writes == [] and rig.controller.adapter.connected == set()


def test_controller_without_battery_service_reports_none(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, 8, battery=None)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    status = client.next("status", lambda m: m["controller"]["state"] == "connected")
    assert status["controller"]["battery"] is None


def test_locked_controller_is_reported_and_left_alone(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False, locked_retry_s=30.0)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, 8, locked=True, battery=64)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    status = client.next("status", lambda m: m["controller"]["state"] == "locked")
    assert status["controller"] == {
        "state": "locked",
        "device": {"address": LEFT, "name": "Zwift SF2", "side": "left"},
        "battery": 64,
    }
    time.sleep(0.5)
    adapter = rig.controller.adapter
    assert rig.bridge.call(lambda: (adapter.connected, len(adapter.connect_attempts))) == (set(), 1)  # getrennt, Ruhe
    assert statuses(client.drain(0.2)) == []
    assert_controller_never_written(rig)


def test_locked_controller_is_tried_again_after_the_pause(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False, locked_retry_s=0.3)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, 8, locked=True)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    client.next("status", lambda m: m["controller"]["state"] == "locked")
    rig.controller_on(LEFT, 8, locked=False)  # einmal in Zwift verbunden: der Service ist sichtbar
    assert client.next("status", lambda m: m["controller"]["state"] == "connected")["controller"]["battery"] == 77
    assert_controller_never_written(rig)


def test_left_controller_wins_over_the_right(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    rig.controller_on(RIGHT, 7)
    assert client.reply(set_devices("controller", controller(RIGHT, "right"), controller(LEFT, "left"))) == (
        ack("set_devices")
    )
    assert client.next("status", lambda m: m["controller"]["state"] == "connected")["controller"]["device"][
        "side"
    ] == "right"
    rig.controller_on(LEFT, 8)
    status = client.next("status", lambda m: (m["controller"]["device"] or {}).get("side") == "left")
    assert status["controller"]["state"] == "connected"
    wait_until(lambda: rig.bridge.call(lambda: rig.controller.adapter.connected) == {LEFT}, 3.0, "rechts getrennt")
    assert_controller_never_written(rig)


def test_controller_dropout_reconnects_in_the_background(devices_bridge, bus_client):
    rig = devices_bridge(trainer=False)
    client = BusReader(bus_client())
    rig.controller_on(LEFT, 8)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    client.next("status", lambda m: m["controller"]["state"] == "connected")
    rig.bridge.call(rig.controller.adapter.drop, LEFT)
    assert client.next("status")["controller"] == {"state": "disconnected", "device": None, "battery": None}
    client.next("status", lambda m: m["controller"]["state"] == "connected")
    assert [m["state"] for m in client.statuses()] == ["connected"] * len(client.statuses())  # das Rad läuft weiter
    assert client.reply(set_devices("controller")) == ack("set_devices")
    assert client.statuses()[-1]["controller"] == CONTROLLER_OFF
    assert_controller_never_written(rig)


def test_trainer_status_and_ftms_scan_are_untouched_by_the_controller(devices_bridge, bus_client):
    rig = devices_bridge(known_only=True)
    client = BusReader(bus_client())
    rig.trainer_on(KICKR, -55)
    rig.controller_on(LEFT, 8)
    assert client.reply(set_devices("controller", controller(LEFT, "left"))) == ack("set_devices")
    assert client.reply(set_devices("trainer", trainer(KICKR))) == ack("set_devices")
    status = client.next(
        "status", lambda m: m["state"] == "connected" and m["controller"]["state"] == "connected", timeout_s=5.0
    )
    assert status["trainer"]["device"]["address"] == KICKR
    assert rig.bridge.call(lambda: rig.trainer.connected) == {KICKR}
    assert rig.bridge.call(lambda: FTMS_SERVICE in rig.trainer.devices[KICKR].services)


# --- CLI (Start aus dem Spiel) --------------------------------------------------------------------


def test_cli_known_trainers_waits_for_the_list_of_the_client():
    source = cli.SOURCES["ble"](cli.build_parser().parse_args(["--source", "ble", "--known-trainers"]))
    assert source._known == []  # leere Liste: kein Trainer, bis das Spiel eine schickt
    assert cli.SOURCES["ble"](cli.build_parser().parse_args(["--source", "ble"]))._known is None  # P2-Verhalten


@pytest.mark.parametrize(
    ("args", "error"),
    [
        (["--source", "sim", "--known-trainers"], "--known-trainers gibt es nur mit --source ble"),
        (["--source", "ble", "--known-trainers", "--trainer", KICKR], "schließen sich aus"),
    ],
)
def test_cli_known_trainers_rejects_wrong_combinations(capsys, args, error):
    with pytest.raises(SystemExit) as exit_:
        cli.main(args)
    assert exit_.value.code == 2
    assert error in capsys.readouterr().err
