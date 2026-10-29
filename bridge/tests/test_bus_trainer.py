"""Trainer am Bus (Spec #75, Story 6): Bridge im Testprozess mit `TrainerSource` auf dem BLE-Fake.

Geprüft wird am Bus, in den Session-Dateien und im Terminal: `source: "ble"`, Capabilities nach den Features,
gemessene Watt, Rohaufzeichnung aller Notifications, Kadenz aus Cycling Power ohne Sprünge nach `null`, und ein
Abbruch beendet weder Bridge noch Session – die Bridge meldet `disconnected`, verbindet im Hintergrund neu und
liefert wieder Telemetrie.

Steuerung (Spec #75, Stories 5, 7, 11): `status.trainer` genau einmal je Änderung, `set_grade` → `0x11` mit `ack`,
Kontrollverlust, Nur-lesen-Modus, Neuverbinden, und die sichere Grundlast der Bridge – Steigung 0, sobald alle Clients
weg sind, und Steigung 0 plus Reset beim Beenden.

Alles, was den Fake skriptet (`notify`, `drop` …), läuft über `bridge.call` im Event-Loop der Bridge.
"""

import csv
import time
from collections.abc import Callable, Iterator

import pytest
from bridge_harness import HOST, InProcessBridge, read_jsonl
from fake_ble import FakeBleAdapter
from heart_rate_harness import BusReader
from trainer_harness import (
    FEATURES_POWER_ONLY,
    KICKR,
    KICKR_NAME,
    TARGET_POWER,
    TARGET_SIMULATION,
    bike,
    control_responder,
    control_writes,
    cycling_power,
    kickr,
    simulation,
    target_power,
)

from vspin_bridge import app
from vspin_bridge.parsers import CYCLING_POWER_MEASUREMENT, INDOOR_BIKE_DATA, Decoder
from vspin_bridge.sources.base import Capability
from vspin_bridge.sources.replay import load_replay
from vspin_bridge.sources.trainer import TrainerSource
from vspin_bridge.sources.trainer_control import CONTROL_POINT, MACHINE_STATUS

pytestmark = pytest.mark.usefixtures("isolated_bus")

RECONNECT_S = 0.1


def trainer_block(control: str, connected: bool = True, mode: str = "sim", target_power: int | None = None) -> dict:
    """Der ganze Block `status.trainer` (seit P4 mit dem verbundenen Gerät, seit P7 mit Modus und Zielleistung)."""
    return {
        "control": control,
        "device": {"address": KICKR, "name": KICKR_NAME} if connected else None,
        "mode": mode,
        "target_power": target_power,
    }


class Rig:
    def __init__(self, bridge: InProcessBridge, adapter: FakeBleAdapter, tmp_path, kickr_args: dict) -> None:
        self.bridge = bridge
        self.adapter = adapter
        self.sessions = tmp_path / "sessions"
        self.kickr_args = kickr_args

    def trainer_on(self) -> None:
        """Der Trainer beginnt zu senden."""
        self.bridge.call(lambda: kickr(self.adapter, **self.kickr_args))

    def send(self, char: str, data: bytes) -> None:
        self.bridge.call(self.adapter.indicate, KICKR, char, data)

    def control_writes(self) -> list[bytes]:
        return self.bridge.call(control_writes, self.adapter)

    def wait_for_writes(self, count: int, timeout_s: float = 3.0) -> list[bytes]:
        """Die Schreibzugriffe auf den Control Point, sobald es mindestens `count` sind."""
        deadline = time.monotonic() + timeout_s
        while len(writes := self.control_writes()) < count:
            assert time.monotonic() < deadline, f"nur {len(writes)} Schreibzugriffe: {writes}"
            time.sleep(0.02)
        return writes


@pytest.fixture
def trainer_bridge(request, tmp_path, monkeypatch) -> Iterator[Callable[..., Rig]]:
    """Fabrik: `trainer_bridge(present=True, bits=…)` startet eine Bridge mit Fake-Trainer (`present=False`: er sendet
    erst nach `trainer_on()`); Neuverbinden nach 0,1 s statt 3 s. `sim=True`: der Trainer kann Indoor Bike Simulation,
    sein Control Point antwortet mit `respond` (Standard: Erfolg); `read_only`: Bridge mit `--read-only`."""
    monkeypatch.setattr(app, "RECONNECT_INTERVAL_S", RECONNECT_S)
    started: list[InProcessBridge] = []

    def start(present: bool = True, sim: bool = False, read_only: bool = False, respond=None, **kickr_args) -> Rig:
        adapter = FakeBleAdapter()
        if sim:
            kickr_args["targets"] = TARGET_SIMULATION | kickr_args.get("targets", 0)
            adapter.answer(KICKR, CONTROL_POINT, CONTROL_POINT, respond or control_responder())
        if present:
            kickr(adapter, **kickr_args)
        source = TrainerSource(adapter, scan_s=0.3, settle_s=0.02, read_only=read_only)
        bridge = InProcessBridge(source, tmp_path / "sessions", getattr(request.node, "bus_host", HOST))
        started.append(bridge)
        bridge.start()
        return Rig(bridge, adapter, tmp_path, kickr_args)

    yield start
    for bridge in started:
        bridge.stop()


def states(reader: BusReader) -> list[str]:
    return [m["state"] for m in reader.statuses()]


def wait_for_state(reader: BusReader, state: str) -> dict:
    """Der Status `state`: der erste, den der Client bekommen hat, sonst der nächste."""
    if reader.first["state"] == state:
        return reader.first
    return reader.next("status", lambda m: m["state"] == state)


def test_status_and_measured_power(trainer_bridge, bus_client):
    rig = trainer_bridge()
    reader = BusReader(bus_client())
    status = wait_for_state(reader, "connected")
    assert status["source"] == "ble"
    assert status["capabilities"] == ["CADENCE", "POWER", "SPEED"]
    rig.send(INDOOR_BIKE_DATA, bike(27.5, 88, 190))
    telemetry = reader.next("telemetry")
    assert (telemetry["speed_kmh"], telemetry["power_w"], telemetry["power_estimated"]) == (27.5, 190, False)
    assert telemetry["cadence"] == 88.0 and telemetry["heart_rate"] is None


def test_every_notification_goes_into_the_session_raw_file(trainer_bridge, bus_client):
    rig = trainer_bridge(bits=FEATURES_POWER_ONLY)
    reader = BusReader(bus_client())
    sent = [
        (INDOOR_BIKE_DATA, bike(25.0, None, 150)),
        (CYCLING_POWER_MEASUREMENT, cycling_power(150, crank=(1, 0))),
        (INDOOR_BIKE_DATA, b"\x04"),  # kaputt: steht trotzdem in den Rohdaten (ADR-0008)
        (CYCLING_POWER_MEASUREMENT, cycling_power(151, crank=(2, 1024))),
    ]
    wait_for_state(reader, "connected")
    for char, data in sent:
        rig.send(char, data)
    reader.next("telemetry", lambda m: m["cadence"] == 60.0)
    rig.bridge.stop()
    [raw_path] = rig.sessions.glob("*.raw.jsonl")
    assert [(line["char"], bytes.fromhex(line["hex"])) for line in read_jsonl(raw_path)] == sent
    # Die Aufnahme einer Trainerfahrt spielt der Replay wieder ab (ADR-0003); dort gelten die Watt als geschätzt.
    replay = load_replay(raw_path)
    assert [(n.char, n.data) for n in replay.notifications] == sent
    assert replay.capabilities == {Capability.CADENCE, Capability.POWER, Capability.SPEED}
    assert Decoder().decode(replay.notifications[0]).power_estimated is True
    [csv_path] = rig.sessions.glob("*.csv")
    with open(csv_path, encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert {row["power_estimated"] for row in rows} == {"false"}  # gemessene Watt auch in der CSV
    assert "Notification verworfen" in rig.bridge.log()


def test_cadence_from_cycling_power_never_jumps_back_to_null(trainer_bridge, bus_client):
    rig = trainer_bridge(bits=FEATURES_POWER_ONLY)
    reader = BusReader(bus_client())
    status = wait_for_state(reader, "connected")
    assert status["capabilities"] == ["CADENCE", "POWER", "SPEED"]
    # Zwei Characteristics im Wechsel: 0x2AD2 (Tempo, Leistung, keine Kadenz) und 0x2A63 (Kurbel, 60 rpm).
    for i in range(8):
        rig.send(INDOOR_BIKE_DATA, bike(30.0, None, 210))
        rig.send(CYCLING_POWER_MEASUREMENT, cycling_power(210, crank=(i, i * 1024)))
    telemetry = [reader.next("telemetry") for _ in range(16)]
    first_value = next(i for i, m in enumerate(telemetry) if m["cadence"] is not None)
    assert first_value >= 2  # erst das zweite Kurbel-Event liefert eine Kadenz
    for message in telemetry[first_value:]:
        assert message["cadence"] == 60.0  # nie zwischen Wert und null
        assert message["cadence_raw"] == 60.0
    for message in telemetry[1:]:
        assert message["speed_kmh"] == 30.0 and message["power_w"] == 210  # Tempo und Leistung auch aus 0x2A63-Samples
        assert message["power_estimated"] is False


def test_drop_pauses_nothing_but_reconnects_in_the_background_with_the_same_session(trainer_bridge, bus_client):
    rig = trainer_bridge()
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    rig.send(INDOOR_BIKE_DATA, bike(25.0, 80, 150))
    assert reader.next("telemetry")["cadence"] == 80.0

    rig.bridge.call(rig.adapter.drop, KICKR)  # Verbindung reißt ab, der Trainer sendet weiter
    reader.next("status", lambda m: m["state"] == "disconnected")
    reader.next("status", lambda m: m["state"] == "connected")  # Neuverbinden im Hintergrund
    rig.send(INDOOR_BIKE_DATA, bike(26.0, 82, 155))
    after = reader.next("telemetry", lambda m: m["power_w"] == 155)
    assert after["speed_kmh"] == 26.0 and after["power_estimated"] is False

    rig.bridge.stop()
    assert rig.bridge.error is None  # der Abbruch hat die Bridge nicht beendet
    assert rig.adapter.writes == []  # auch beim Neuverbinden nur lesen (kein Control Point)
    assert len(list(rig.sessions.glob("*.csv"))) == len(list(rig.sessions.glob("*.raw.jsonl"))) == 1  # keine neue Datei
    [raw_path] = rig.sessions.glob("*.raw.jsonl")
    assert [bytes.fromhex(line["hex"]) for line in read_jsonl(raw_path)] == [bike(25.0, 80, 150), bike(26.0, 82, 155)]
    log = rig.bridge.log()
    assert log.count("Status: disconnected (") == 1 and log.count("Status: connected (") == 2


def test_trainer_gone_then_back(trainer_bridge, bus_client):
    rig = trainer_bridge()
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")

    rig.bridge.call(rig.adapter.vanish, KICKR)  # Akku leer, Trainer aus
    rig.bridge.call(rig.adapter.drop, KICKR)
    reader.next("status", lambda m: m["state"] == "disconnected")
    quiet = reader.drain(0.8)  # mehrere Suchversuche ohne Trainer: weder Telemetrie noch ein weiterer Status
    assert [m["type"] for m in quiet] == []
    assert rig.adapter.scan_starts >= 3

    rig.trainer_on()  # Trainer wieder an
    reader.next("status", lambda m: m["state"] == "connected")
    rig.send(INDOOR_BIKE_DATA, bike(24.0, 75, 140))
    assert reader.next("telemetry")["cadence"] == 75.0
    assert states(reader)[-3:] == ["connected", "disconnected", "connected"]
    assert "Verbindung gescheitert" in rig.bridge.log()


def test_start_without_trainer_reports_disconnected_and_connects_once_it_shows_up(trainer_bridge, bus_client):
    rig = trainer_bridge(present=False)
    reader = BusReader(bus_client())
    assert reader.first["state"] == "disconnected"
    assert reader.drain(0.5) == []  # Suche läuft im Hintergrund, kein Status, keine Telemetrie
    assert rig.adapter.scan_starts >= 2
    rig.trainer_on()
    status = reader.next("status", lambda m: m["state"] == "connected")
    assert status["source"] == "ble"
    rig.send(INDOOR_BIKE_DATA, bike(24.0, 75, 140))
    assert reader.next("telemetry")["power_w"] == 140
    assert "Verbindung gescheitert" in rig.bridge.log()


# --- Steuerung (Spec #75) ------------------------------------------------------------------------

REQUEST_CONTROL, RESET, START = b"\x00", b"\x01", b"\x07"


def ack(ok: bool, reason: str | None = None) -> dict:
    return {"v": 0, "type": "ack", "for": "set_grade", "ok": ok, "reason": reason}


def set_grade(grade: float) -> dict:
    return {"v": 0, "type": "set_grade", "grade": grade}


def without_time(status: dict) -> dict:
    return {key: value for key, value in status.items() if key != "t_ms"}


def assert_one_status_per_change(reader: BusReader) -> None:
    statuses = [without_time(m) for m in reader.statuses()]
    for before, after in zip(statuses, statuses[1:]):
        assert before != after, f"status ohne Änderung: {after}"


def test_status_trainer_reports_control_once_per_change(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True)
    reader = BusReader(bus_client())
    status = wait_for_state(reader, "connected")
    assert status["trainer"] == trainer_block("active")
    assert "RESISTANCE_CONTROL" in status["capabilities"]
    assert rig.control_writes() == [REQUEST_CONTROL, START]

    rig.send(MACHINE_STATUS, b"\xff")  # Zwift o. Ä. übernimmt
    lost = reader.next("status")
    assert lost["trainer"] == trainer_block("lost") and lost["state"] == "connected"
    rig.send(MACHINE_STATUS, b"\xff")
    assert [m for m in reader.drain(0.4) if m["type"] == "status"] == []  # genau ein Broadcast
    assert reader.reply(set_grade(0.05)) == ack(False, "control_lost")
    assert rig.control_writes() == [REQUEST_CONTROL, START]  # danach kein Schreiben mehr
    assert_one_status_per_change(reader)
    assert "Trainer-Steuerung: lost" in rig.bridge.log()


def test_new_client_gets_the_trainer_block_in_its_first_status(trainer_bridge, bus_client):
    trainer_bridge(sim=True)
    wait_for_state(BusReader(bus_client()), "connected")
    assert BusReader(bus_client()).first["trainer"] == trainer_block("active")


def test_set_grade_reaches_the_trainer_and_is_acked(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_grade(0.07)) == ack(True)
    assert rig.control_writes()[-1] == simulation(700)
    # Gedrosselt (2 Hz): beide bekommen sofort ok, geschrieben wird der letzte Wert nach Ablauf des Intervalls.
    assert reader.reply(set_grade(0.08)) == ack(True)
    assert reader.reply(set_grade(0.09)) == ack(True)
    assert rig.control_writes()[-1] == simulation(700)
    assert rig.wait_for_writes(4)[-1] == simulation(900)
    assert "set_grade +0.070 (+7.0 %) -> ok" in rig.bridge.log()


def test_trainer_refusal_is_a_source_error(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, respond=control_responder({0x11: 0x03}))
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_grade(0.3)) == ack(False, "source_error")
    assert "ungültiger Parameter (0x03)" in rig.bridge.log()


def test_all_clients_leaving_sets_zero_grade_at_once(trainer_bridge, bus_client):
    # Grundlast, Fall 1: Spiel abgestürzt oder geschlossen.
    rig = trainer_bridge(sim=True)
    game, other = BusReader(bus_client()), BusReader(bus_client())
    wait_for_state(game, "connected")
    assert game.reply(set_grade(0.08)) == ack(True)
    assert game.reply(set_grade(0.09)) == ack(True)  # gedrosselt, steht noch aus
    other.client.close()
    time.sleep(0.3)
    assert simulation(0) not in rig.control_writes()  # ein Client ist noch da
    game.client.close()
    writes = rig.wait_for_writes(4, timeout_s=1.0)
    assert writes[:4] == [REQUEST_CONTROL, START, simulation(800), simulation(0)]  # vor dem Nachholen: nie gedrosselt
    time.sleep(0.7)
    assert rig.control_writes() == writes[:4]  # die ausstehenden 9 % kommen nicht nach
    assert "Grundlast, Steigung 0 am Trainer" in rig.bridge.log()


def test_the_client_of_the_last_grade_leaving_sets_zero_grade_at_once(trainer_bridge, bus_client):
    # Grundlast, Fall 1b: das Spiel stürzt ab, ein zweiter Client (z. B. der Begleiter) bleibt verbunden.
    rig = trainer_bridge(sim=True)
    game, companion = BusReader(bus_client()), BusReader(bus_client())
    wait_for_state(game, "connected")
    assert game.reply(set_grade(0.08)) == ack(True)
    game.client.close()
    writes = rig.wait_for_writes(4, timeout_s=1.0)
    assert writes == [REQUEST_CONTROL, START, simulation(800), simulation(0)]
    time.sleep(0.3)
    assert rig.control_writes() == writes  # genau einmal
    assert companion.reply(set_grade(0.02)) == ack(True)  # der verbliebene Client steuert weiter
    assert "Client der letzten Steigung weg: Grundlast, Steigung 0 am Trainer" in rig.bridge.log()


def test_another_client_leaving_keeps_the_grade(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True)
    game, companion = BusReader(bus_client()), BusReader(bus_client())
    wait_for_state(game, "connected")
    assert game.reply(set_grade(0.08)) == ack(True)
    companion.client.close()
    time.sleep(0.3)
    assert rig.control_writes() == [REQUEST_CONTROL, START, simulation(800)]


def test_stopping_the_bridge_writes_zero_and_reset_before_disconnecting(trainer_bridge, bus_client):
    # Grundlast, Fall 2: normales Beenden (Stoppdatei, Strg+C, Elternprozess – alle setzen dasselbe `stop`).
    rig = trainer_bridge(sim=True)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_grade(0.08)) == ack(True)
    assert rig.bridge.stop() is None
    # Der Fake nimmt Schreibzugriffe nur bei offener Verbindung an: beides lag vor dem Trennen.
    assert control_writes(rig.adapter) == [REQUEST_CONTROL, START, simulation(800), simulation(0), RESET]
    assert rig.adapter.connected == set()


def test_read_only_bridge_never_writes(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, read_only=True)
    reader = BusReader(bus_client())
    status = wait_for_state(reader, "connected")
    assert status["trainer"] == trainer_block("read_only")
    assert "RESISTANCE_CONTROL" not in status["capabilities"]
    assert reader.reply(set_grade(0.07)) == ack(False, "read_only")
    reader.client.close()  # auch die Grundlast schreibt nichts
    time.sleep(0.3)
    rig.bridge.stop()
    assert rig.adapter.writes == []
    assert "set_grade +0.070 (+7.0 %) -> read_only" in rig.bridge.log()


def test_reconnect_requests_control_again_and_resends_the_last_grade(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_grade(0.05)) == ack(True)
    rig.bridge.call(rig.adapter.drop, KICKR)
    assert reader.next("status", lambda m: m["state"] == "disconnected")["trainer"] == trainer_block("none", False)
    assert reader.next("status", lambda m: m["state"] == "connected")["trainer"] == trainer_block("active")
    assert rig.wait_for_writes(6) == [REQUEST_CONTROL, START, simulation(500)] * 2
    assert_one_status_per_change(reader)


def test_trainer_without_simulation_reports_not_supported(trainer_bridge, bus_client):
    rig = trainer_bridge()
    reader = BusReader(bus_client())
    assert wait_for_state(reader, "connected")["trainer"] == trainer_block("not_supported")
    assert reader.reply(set_grade(0.05)) == ack(False, "not_supported")
    reader.client.close()
    rig.bridge.stop()
    assert rig.adapter.writes == []


# --- ERG (P7) --------------------------------------------------------------------------------


def set_target_power(watts) -> dict:
    return {"v": 0, "type": "set_target_power", "watts": watts}


def ack_power(ok: bool, reason: str | None = None) -> dict:
    return {"v": 0, "type": "ack", "for": "set_target_power", "ok": ok, "reason": reason}


def test_erg_on_and_off_with_one_status_per_change(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, targets=TARGET_POWER)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_grade(0.04)) == ack(True)
    assert reader.reply(set_target_power(250)) == ack_power(True)
    assert reader.statuses()[-1]["trainer"] == trainer_block("active", mode="erg", target_power=250)  # vor dem ack
    assert rig.control_writes()[-1] == target_power(250)
    assert reader.reply(set_target_power(250)) == ack_power(True)  # unverändert: kein Schreiben, kein status
    assert [m for m in reader.drain(0.3) if m["type"] == "status"] == []
    assert reader.reply(set_grade(0.06)) == ack(False, "erg_active")  # in ERG schreibt keine Steigung
    assert rig.control_writes() == [REQUEST_CONTROL, START, simulation(400), target_power(250)]
    assert reader.reply(set_target_power(None)) == ack_power(True)
    assert reader.statuses()[-1]["trainer"] == trainer_block("active")
    assert rig.control_writes()[-1] == simulation(600)  # zurück in SIM mit der zuletzt gemeldeten Steigung
    assert_one_status_per_change(reader)
    assert "set_target_power 250 W -> ok" in rig.bridge.log()
    assert "set_grade +0.060 (+6.0 %) -> erg_active" in rig.bridge.log()


def test_set_target_power_without_power_target_is_not_supported(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True)  # Simulation ja, Power Target nein
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_target_power(200)) == ack_power(False, "not_supported")
    assert rig.control_writes() == [REQUEST_CONTROL, START]
    assert reader.reply(set_grade(0.03)) == ack(True)  # SIM bleibt


def test_invalid_watts_is_an_error(trainer_bridge, bus_client):
    trainer_bridge(sim=True, targets=TARGET_POWER)
    reader = BusReader(bus_client())
    for bad in (-1, 2001, 250.5, "250", True):
        assert reader.reply(set_target_power(bad))["reason"] == "invalid_watts"
    assert reader.reply({"v": 0, "type": "set_target_power"})["reason"] == "invalid_watts"


def test_the_client_of_the_last_target_power_leaving_ends_erg_with_zero_grade(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, targets=TARGET_POWER)
    game, companion = BusReader(bus_client()), BusReader(bus_client())
    wait_for_state(companion, "connected")
    assert game.reply(set_target_power(220)) == ack_power(True)
    assert companion.next("status")["trainer"]["mode"] == "erg"
    game.client.close()
    assert companion.next("status")["trainer"] == trainer_block("active")  # ERG aus
    assert rig.wait_for_writes(4, timeout_s=1.0) == [REQUEST_CONTROL, START, target_power(220), simulation(0)]
    assert "Client der letzten Steigung weg: Grundlast, Steigung 0 am Trainer" in rig.bridge.log()


def test_all_clients_leaving_in_erg_sets_zero_grade(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, targets=TARGET_POWER)
    game = BusReader(bus_client())
    wait_for_state(game, "connected")
    assert game.reply(set_target_power(180)) == ack_power(True)
    game.client.close()
    assert rig.wait_for_writes(4, timeout_s=1.0) == [REQUEST_CONTROL, START, target_power(180), simulation(0)]
    assert BusReader(bus_client()).first["trainer"] == trainer_block("active")


def test_stopping_the_bridge_in_erg_writes_zero_grade_and_reset(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, targets=TARGET_POWER)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_target_power(200)) == ack_power(True)
    assert rig.bridge.stop() is None
    assert control_writes(rig.adapter) == [REQUEST_CONTROL, START, target_power(200), simulation(0), RESET]


def test_reconnect_in_erg_resends_the_target_power(trainer_bridge, bus_client):
    rig = trainer_bridge(sim=True, targets=TARGET_POWER)
    reader = BusReader(bus_client())
    wait_for_state(reader, "connected")
    assert reader.reply(set_target_power(230)) == ack_power(True)
    rig.bridge.call(rig.adapter.drop, KICKR)
    disconnected = reader.next("status", lambda m: m["state"] == "disconnected")
    assert disconnected["trainer"] == trainer_block("none", False, "erg", 230)  # ERG bleibt das Ziel
    reader.next("status", lambda m: m["state"] == "connected")
    assert rig.wait_for_writes(6) == [REQUEST_CONTROL, START, target_power(230)] * 2
    assert_one_status_per_change(reader)
