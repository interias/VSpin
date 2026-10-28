"""Trainer am Bus (Spec #75, Story 6): Bridge im Testprozess mit `TrainerSource` auf dem BLE-Fake.

Geprüft wird am Bus, in den Session-Dateien und im Terminal: `source: "ble"`, Capabilities nach den Features,
gemessene Watt, Rohaufzeichnung aller Notifications, Kadenz aus Cycling Power ohne Sprünge nach `null`, und ein
Abbruch beendet weder Bridge noch Session – die Bridge meldet `disconnected`, verbindet im Hintergrund neu und
liefert wieder Telemetrie.

Alles, was den Fake skriptet (`notify`, `drop` …), läuft über `bridge.call` im Event-Loop der Bridge.
"""

import csv
from collections.abc import Callable, Iterator

import pytest
from bridge_harness import HOST, InProcessBridge, read_jsonl
from fake_ble import FakeBleAdapter
from heart_rate_harness import BusReader
from trainer_harness import FEATURES_POWER_ONLY, KICKR, bike, cycling_power, kickr

from vspin_bridge import app
from vspin_bridge.parsers import CYCLING_POWER_MEASUREMENT, INDOOR_BIKE_DATA, Decoder
from vspin_bridge.sources.base import Capability
from vspin_bridge.sources.replay import load_replay
from vspin_bridge.sources.trainer import TrainerSource

pytestmark = pytest.mark.usefixtures("isolated_bus")

RECONNECT_S = 0.1


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


@pytest.fixture
def trainer_bridge(request, tmp_path, monkeypatch) -> Iterator[Callable[..., Rig]]:
    """Fabrik: `trainer_bridge(present=True, bits=…)` startet eine Bridge mit Fake-Trainer (`present=False`: er sendet
    erst nach `trainer_on()`); Neuverbinden nach 0,1 s statt 3 s."""
    monkeypatch.setattr(app, "RECONNECT_INTERVAL_S", RECONNECT_S)
    started: list[InProcessBridge] = []

    def start(present: bool = True, **kickr_args) -> Rig:
        adapter = FakeBleAdapter()
        if present:
            kickr(adapter, **kickr_args)
        source = TrainerSource(adapter, scan_s=0.3, settle_s=0.02)
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
