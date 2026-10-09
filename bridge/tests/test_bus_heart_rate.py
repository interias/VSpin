"""Puls am Bus (Spec #64): Pulsblock in `status`, `telemetry.heart_rate` aus der Pulsquelle, neue Befehle mit
`ack`/`error`, Suchergebnisse nur an den Anfrager. Die Bridge läuft im Testprozess mit dem BLE-Fake und kurzen
Zeiten (`heart_rate_harness.py`); geprüft wird nur am Bus und im Terminal."""

import asyncio

import pytest
from bridge_harness import FIXTURES_DIR, receive_json, wait_until
from heart_rate_harness import (  # noqa: F401 – pulse_bridge ist eine Fixture
    DISCONNECTED,
    OFF,
    STRAP,
    WATCH,
    WHEEL_PART,
    BusReader,
    ack,
    block,
    heart_rate_blocks,
    pulse,
    pulse_bridge,
    set_devices,
)
from vspin_bridge.sources.replay import ReplaySource, load_replay

SEARCH_ACK = ack("start_heart_rate_search")
STOP_ACK = ack("stop_heart_rate_search")
DEVICES_ACK = ack("set_heart_rate_devices")


def start_search(duration_s: float | None = None) -> dict:
    message = {"v": 0, "type": "start_heart_rate_search"}
    return message if duration_s is None else message | {"duration_s": duration_s}


STOP_SEARCH = {"v": 0, "type": "stop_heart_rate_search"}


def with_pulse(bpm):
    return lambda m: m["heart_rate"] == bpm


def wheel_part(status: dict) -> dict:
    return {key: status[key] for key in ("state", "source", "capabilities")}


def connect_strap(bridge, rig, reader: BusReader, bpm: int | None = None) -> None:
    assert reader.reply(set_devices(STRAP)) == DEVICES_ACK
    bridge.call(rig.adapter.appear, STRAP.address, STRAP.name)
    reader.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    if bpm is not None:
        bridge.call(rig.adapter.notify, STRAP.address, pulse(bpm))
        reader.next("telemetry", with_pulse(bpm))


# --- status -------------------------------------------------------------------------------


def test_first_status_has_heart_rate_off_behind_the_unchanged_wheel_part(bridge_process, bus_client, isolated_bus):
    # Echter Prozess mit der Standard-Pulsquelle (bleak): bis zum ersten Befehl fasst sie BLE nicht an.
    bridge_process("--source", "sim", "--sim-cadence", "80")
    client = bus_client()
    status = receive_json(client)
    assert list(status) == ["v", "type", "t_ms", "state", "source", "capabilities", "heart_rate"]
    assert wheel_part(status) == WHEEL_PART
    assert status["heart_rate"] == OFF
    assert receive_json(client)["heart_rate"] is None  # ohne Pulsgerät und ohne FTMS-Puls


def test_set_devices_acks_and_broadcasts_exactly_one_disconnected(pulse_bridge, bus_client, isolated_bus):
    pulse_bridge()
    sender, other = BusReader(bus_client()), BusReader(bus_client())
    assert sender.first["heart_rate"] == other.first["heart_rate"] == OFF

    assert sender.reply(set_devices(STRAP, WATCH)) == DEVICES_ACK
    assert heart_rate_blocks(sender.seen) == [OFF, DISCONNECTED]  # `status` kommt vor dem `ack`
    other.drain(0.6)
    assert heart_rate_blocks(other.seen) == [OFF, DISCONNECTED]
    assert all(wheel_part(s) == WHEEL_PART for s in other.statuses())  # Radteil unverändert

    # Dieselbe Liste noch einmal: `ack`, aber keine Änderung, also kein `status`.
    assert sender.reply(set_devices(STRAP, WATCH)) == DEVICES_ACK
    other.drain(0.6)
    assert heart_rate_blocks(other.seen) == [OFF, DISCONNECTED]


def test_connected_device_in_status_and_its_pulse_in_telemetry(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    client = BusReader(bus_client())
    connect_strap(bridge, rig, client, bpm=91)
    status = client.statuses()[-1]
    assert status["heart_rate"] == {
        "state": "connected",
        "device": {"address": STRAP.address, "name": "HRM-Pro", "role": "strap"},
    }
    assert wheel_part(status) == WHEEL_PART
    # Der Takt bleibt der des Rads: weiter alle 250 ms eine `telemetry`, jetzt mit dem Puls.
    assert [client.next("telemetry")["heart_rate"] for _ in range(4)] == [91] * 4

    newcomer = BusReader(bus_client())  # neuer Client: aktueller Pulsblock im ersten `status`
    assert newcomer.first["heart_rate"] == block("connected", STRAP)
    assert "Puls: connected, HRM-Pro (strap)" in bridge.log()


def test_no_pulse_for_longer_than_stale_gives_null_and_stale(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge(stale_s=0.6)
    client = BusReader(bus_client())
    connect_strap(bridge, rig, client, bpm=84)

    client.next("status", lambda m: m["heart_rate"] == block("stale", STRAP), timeout_s=3.0)
    assert client.next("telemetry")["heart_rate"] is None
    # Kommt wieder ein Wert, ist das Gerät wieder `connected` und der Puls zurück.
    bridge.call(rig.adapter.notify, STRAP.address, pulse(86))
    client.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    client.next("telemetry", with_pulse(86))


def test_pulse_dropout_does_not_disturb_the_ride_and_reconnects(pulse_bridge, bus_client, isolated_bus):
    # Story 12 auf Bridge-Seite: Pulsausfall stört die Fahrt nicht.
    bridge, rig = pulse_bridge(stale_s=0.6)
    client = BusReader(bus_client())
    connect_strap(bridge, rig, client, bpm=88)

    def lose_strap() -> None:
        rig.adapter.vanish(STRAP.address)  # sendet nicht mehr, Neuverbindung erst nach neuer Ankündigung
        rig.adapter.drop(STRAP.address)

    bridge.call(lose_strap)
    client.next("status", lambda m: m["heart_rate"] == DISCONNECTED)
    # Die Fahrt läuft weiter: Telemetrie im Takt des Rads, der Puls wird nach `stale_s` null.
    client.next("telemetry", with_pulse(None), timeout_s=3.0)
    assert [client.next("telemetry")["cadence"] for _ in range(4)] == [80.0] * 4
    assert all(wheel_part(s) == WHEEL_PART for s in client.statuses())

    bridge.call(rig.adapter.appear, STRAP.address, STRAP.name)
    client.next("status", lambda m: m["heart_rate"] == block("connected", STRAP), timeout_s=3.0)
    bridge.call(rig.adapter.notify, STRAP.address, pulse(95))
    client.next("telemetry", with_pulse(95))


def test_strap_wins_over_watch(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    client = BusReader(bus_client())
    assert client.reply(set_devices(STRAP, WATCH)) == DEVICES_ACK

    def both_send() -> None:
        rig.adapter.appear(WATCH.address, WATCH.name)
        rig.adapter.appear(STRAP.address, STRAP.name)

    bridge.call(both_send)
    client.next("status", lambda m: m["heart_rate"]["state"] == "connected")
    client.drain(0.4)
    assert heart_rate_blocks(client.seen) == [OFF, DISCONNECTED, block("connected", STRAP)]
    assert rig.adapter.connect_attempts == [STRAP.address]


def test_switch_from_watch_to_strap_keeps_the_pulse_flowing(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    client = BusReader(bus_client())
    assert client.reply(set_devices(STRAP, WATCH)) == DEVICES_ACK
    bridge.call(rig.adapter.appear, WATCH.address, WATCH.name)
    client.next("status", lambda m: m["heart_rate"] == block("connected", WATCH))
    bridge.call(rig.adapter.notify, WATCH.address, pulse(100))
    client.next("telemetry", with_pulse(100))

    bridge.call(rig.adapter.appear, STRAP.address, STRAP.name)  # Gurt kommt dazu: Wechsel ohne Lücke
    client.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    assert client.next("telemetry")["heart_rate"] == 100  # Wert der Uhr gilt, bis der Gurt liefert
    bridge.call(rig.adapter.notify, STRAP.address, pulse(120))
    client.next("telemetry", with_pulse(120))
    assert heart_rate_blocks(client.seen) == [OFF, DISCONNECTED, block("connected", WATCH), block("connected", STRAP)]
    assert WATCH.address not in rig.adapter.connected


def test_last_devices_set_by_any_client_win(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    first, second = BusReader(bus_client()), BusReader(bus_client())
    assert first.reply(set_devices(WATCH)) == DEVICES_ACK
    assert second.reply(set_devices(STRAP)) == DEVICES_ACK  # z. B. ein zweites Spiel an derselben Bridge

    def both_send() -> None:
        rig.adapter.appear(WATCH.address, WATCH.name)
        rig.adapter.appear(STRAP.address, STRAP.name)

    bridge.call(both_send)
    first.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    assert rig.adapter.connect_attempts == [STRAP.address]  # die Uhr ist nicht mehr gemerkt


def test_exactly_one_status_per_heart_rate_change(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge(stale_s=0.6)
    actor, observer = BusReader(bus_client()), BusReader(bus_client())
    connect_strap(bridge, rig, actor, bpm=80)
    actor.next("status", lambda m: m["heart_rate"] == block("stale", STRAP), timeout_s=3.0)
    bridge.call(rig.adapter.notify, STRAP.address, pulse(81))
    actor.next("status", lambda m: m["heart_rate"] == block("connected", STRAP))
    bridge.call(lambda: (rig.adapter.vanish(STRAP.address), rig.adapter.drop(STRAP.address)))
    actor.next("status", lambda m: m["heart_rate"] == DISCONNECTED)
    assert actor.reply(set_devices()) == DEVICES_ACK  # leere Liste: aus
    assert actor.reply(set_devices()) == DEVICES_ACK  # noch einmal: keine Änderung

    observer.drain(1.0)
    statuses = observer.statuses()
    assert heart_rate_blocks(statuses) == [
        OFF,
        DISCONNECTED,
        block("connected", STRAP),
        block("stale", STRAP),
        block("connected", STRAP),
        DISCONNECTED,
        OFF,
    ]
    assert all(wheel_part(s) == WHEEL_PART for s in statuses)
    assert bridge.log().count("Puls: ") == 6  # je Änderung eine Terminalzeile


# --- FTMS-Puls nur ohne Pulsgerät ---------------------------------------------------------------


class GatedReplay(ReplaySource):
    """Replay, das erst abspielt, wenn der Test das Tor öffnet (`open`, im Loop der Bridge)."""

    def __init__(self, name: str, speed: float) -> None:
        super().__init__(load_replay(FIXTURES_DIR / name, speed).notifications, speed)
        self._gate: asyncio.Event | None = None

    def _event(self) -> asyncio.Event:
        if self._gate is None:
            self._gate = asyncio.Event()
        return self._gate

    async def connect(self) -> None:
        await self._event().wait()

    def open(self) -> None:
        self._event().set()


def replay_telemetry(bridge, replay: GatedReplay, client: BusReader) -> list[dict]:
    bridge.call(replay.open)
    client.next("status", lambda m: m["state"] == "connected")
    client.next("status", lambda m: m["state"] == "disconnected", timeout_s=10.0)  # Ende der Aufnahme
    return [m for m in client.seen if m["type"] == "telemetry"]


def test_ftms_heart_rate_counts_without_connected_device(pulse_bridge, bus_client, isolated_bus):
    replay = GatedReplay("ftms_all_fields.raw.jsonl", speed=4)
    bridge, _ = pulse_bridge(replay)
    client = BusReader(bus_client())
    # Gemerkt, aber nicht verbunden (die Uhr sendet nicht): es zählt der Puls, den das Rad liefert.
    assert client.reply(set_devices(WATCH)) == DEVICES_ACK
    telemetry = replay_telemetry(bridge, replay, client)
    assert [m["heart_rate"] for m in telemetry] == [128] * 9  # die Aufnahme enthält FTMS-Puls


def test_connected_strap_wins_over_ftms_heart_rate(pulse_bridge, bus_client, isolated_bus):
    replay = GatedReplay("ftms_all_fields.raw.jsonl", speed=4)
    bridge, rig = pulse_bridge(replay)
    client = BusReader(bus_client())
    connect_strap(bridge, rig, client)
    bridge.call(rig.adapter.notify, STRAP.address, pulse(77))
    telemetry = replay_telemetry(bridge, replay, client)
    assert [m["heart_rate"] for m in telemetry] == [77] * 9


# --- Suche auf Anfrage --------------------------------------------------------------------------

POLAR = ("C0:00:00:00:00:01", "Polar H10 1234", -55)
NAMELESS = ("C0:00:00:00:00:02", None, -70)
FOUND_FIELDS = ["v", "type", "t_ms", "address", "name", "rssi"]


def kinds(messages: list[dict]) -> set[str]:
    return {m["type"] for m in messages}


def searching(bridge, rig) -> bool:
    return bridge.call(lambda: rig.source.searching or rig.adapter.scanning)


def test_search_results_go_only_to_the_requester_and_are_throttled(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    requester, other = BusReader(bus_client()), BusReader(bus_client())
    bridge.call(lambda: [rig.adapter.appear(*device) for device in (POLAR, NAMELESS)])

    assert requester.reply(start_search(1.5)) == SEARCH_ACK
    ended = requester.next("heart_rate_search_ended", timeout_s=5.0)
    assert list(ended) == ["v", "type", "t_ms", "reason"] and ended["reason"] == "timeout"

    found = [m for m in requester.seen if m["type"] == "heart_rate_found"]
    assert all(list(m) == FOUND_FIELDS for m in found)
    assert {(m["address"], m["name"], m["rssi"]) for m in found} == {POLAR, NAMELESS}  # auch nicht gemerkte
    # Der Fake kündigt jedes Gerät alle 20 ms an (~75-mal in 1,5 s); am Bus höchstens einmal je Sekunde.
    for address in (POLAR[0], NAMELESS[0]):
        assert 1 <= sum(m["address"] == address for m in found) <= 2, found

    assert kinds(other.drain(0.5)) <= {"telemetry"}  # der andere Client sieht nichts von der Suche
    wait_until(lambda: not searching(bridge, rig), 3.0, "Suche beendet")
    assert "Pulssuche beendet (Zeit abgelaufen)" in bridge.log()


def test_stop_ends_the_own_search_with_ack_only(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    client = BusReader(bus_client())
    assert client.reply(start_search()) == SEARCH_ACK  # Standarddauer 30 s
    assert searching(bridge, rig)
    assert client.reply(STOP_SEARCH) == STOP_ACK
    wait_until(lambda: not searching(bridge, rig), 3.0, "Suche beendet")
    bridge.call(rig.adapter.appear, *POLAR)
    assert kinds(client.drain(0.5)) <= {"telemetry"}  # kein Ergebnis, kein `heart_rate_search_ended`
    assert client.reply(STOP_SEARCH) == STOP_ACK  # ohne laufende Suche ohne Wirkung


def test_search_ends_when_the_requester_disconnects(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    requester = BusReader(bus_client())
    assert requester.reply(start_search(30)) == SEARCH_ACK
    assert searching(bridge, rig)
    requester.client.close()
    wait_until(lambda: not searching(bridge, rig), 3.0, "Suche endet mit dem Anfrager")
    assert "Pulssuche beendet (Client getrennt)" in bridge.log()


def test_bridge_stops_cleanly_during_a_search(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    requester = BusReader(bus_client())
    assert requester.reply(start_search(30)) == SEARCH_ACK
    bridge.call(rig.adapter.appear, *POLAR)
    requester.next("heart_rate_found")
    assert bridge.stop() is None
    # Loop beendet: direkt lesen. Suche und Scanner sind zu, keine Ausnahme beim Abräumen.
    assert not rig.source.searching and not rig.adapter.scanning
    assert "Traceback" not in bridge.log()


def test_search_of_another_client_takes_over(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    first, second = BusReader(bus_client()), BusReader(bus_client())
    assert first.reply(start_search(30)) == SEARCH_ACK
    assert second.reply(start_search(30)) == SEARCH_ACK
    assert first.next("heart_rate_search_ended")["reason"] == "taken_over"

    bridge.call(rig.adapter.appear, *POLAR)
    assert second.next("heart_rate_found")["address"] == POLAR[0]
    assert "heart_rate_found" not in kinds(first.drain(0.5))

    assert first.reply(STOP_SEARCH) == STOP_ACK  # stoppt nicht die Suche des anderen
    assert searching(bridge, rig)
    assert second.reply(STOP_SEARCH) == STOP_ACK
    wait_until(lambda: not searching(bridge, rig), 3.0, "Suche beendet")


def test_failing_search_without_bluetooth_does_not_stop_the_bridge(pulse_bridge, bus_client, isolated_bus):
    bridge, rig = pulse_bridge()
    bridge.call(setattr, rig.adapter, "scan_failures", 10**6)  # wie ohne Bluetooth-Adapter: jede Suche scheitert
    client = BusReader(bus_client())
    assert client.reply(set_devices(STRAP)) == DEVICES_ACK
    assert client.reply(start_search(0.5)) == SEARCH_ACK
    assert client.next("heart_rate_search_ended", timeout_s=3.0)["reason"] == "timeout"
    assert client.statuses()[-1]["heart_rate"] == DISCONNECTED
    assert [client.next("telemetry")["cadence"] for _ in range(4)] == [80.0] * 4
    assert bridge.stop() is None
    assert "Traceback" not in bridge.log()


# --- kaputte Befehle ----------------------------------------------------------------------------

DEVICE = {"address": STRAP.address, "name": STRAP.name, "role": "strap"}

BROKEN_COMMANDS = [
    pytest.param({"v": 0, "type": "set_heart_rate_devices"}, "invalid_devices", id="devices-missing"),
    pytest.param({"v": 0, "type": "set_heart_rate_devices", "devices": DEVICE}, "invalid_devices", id="not-a-list"),
    pytest.param({"v": 0, "type": "set_heart_rate_devices", "devices": ["AA"]}, "invalid_devices", id="no-object"),
    pytest.param(
        {"v": 0, "type": "set_heart_rate_devices", "devices": [DEVICE | {"address": ""}]},
        "invalid_devices",
        id="address-empty",
    ),
    pytest.param(
        {"v": 0, "type": "set_heart_rate_devices", "devices": [{"name": "x", "role": "strap"}]},
        "invalid_devices",
        id="address-missing",
    ),
    pytest.param(
        {"v": 0, "type": "set_heart_rate_devices", "devices": [DEVICE | {"name": 5}]},
        "invalid_devices",
        id="name-number",
    ),
    pytest.param(
        {"v": 0, "type": "set_heart_rate_devices", "devices": [DEVICE | {"role": "chest"}]},
        "invalid_devices",
        id="role-unknown",
    ),
    pytest.param(
        {"v": 0, "type": "set_heart_rate_devices", "devices": [DEVICE, {"address": "B", "name": "B"}]},
        "invalid_devices",
        id="role-missing",
    ),
    pytest.param(start_search() | {"duration_s": "10"}, "invalid_duration", id="duration-string"),
    pytest.param(start_search() | {"duration_s": True}, "invalid_duration", id="duration-bool"),
    pytest.param(start_search(0), "invalid_duration", id="duration-zero"),
    pytest.param(start_search(-5), "invalid_duration", id="duration-negative"),
    pytest.param(start_search(121), "invalid_duration", id="duration-too-long"),
    pytest.param('{"v": 0, "type": "start_heart_rate_search", "duration_s": NaN}', "invalid_duration", id="nan"),
    pytest.param('{"v": 0, "type": "start_heart_rate_search", "duration_s": 1e999}', "invalid_duration", id="inf"),
    pytest.param({"type": "stop_heart_rate_search"}, "unsupported_version", id="version-missing"),
    pytest.param({"v": 0, "type": "set_heart_rate"}, "unknown_type", id="unknown-type"),
]


@pytest.mark.parametrize(("payload", "reason"), BROKEN_COMMANDS)
def test_broken_command_gets_error_and_changes_nothing(pulse_bridge, bus_client, isolated_bus, payload, reason):
    bridge, rig = pulse_bridge()
    client = BusReader(bus_client())
    error = client.reply(payload)
    assert list(error) == ["v", "type", "reason", "detail"]
    assert error["type"] == "error" and error["reason"] == reason and error["detail"]
    assert not searching(bridge, rig)
    # Verbindung offen, nichts verändert: ein gültiger Befehl wird normal beantwortet, der Puls bleibt aus.
    assert client.reply(STOP_SEARCH) == STOP_ACK
    assert heart_rate_blocks(client.seen) == [OFF]
