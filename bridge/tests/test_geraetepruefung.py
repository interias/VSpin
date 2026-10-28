"""Geräteprüfung (`tools/ble_discovery.py`): Dekodierung, Erkennung, Urteile, ganzer Lauf gegen Fake-bleak.

Das Werkzeug wird aus `tools/` geladen. `BleakScanner` und `BleakClient` sind durch Fakes ersetzt; es wird kein
echtes Bluetooth angesprochen. Die Nur-lesen-Zusage (kein Schreiben, kein Abo auf 0x2AD9) ist hier belegt.
"""

import asyncio
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from bleak.exc import BleakError
from vspin_bridge.sources.replay import load_replay

TOOL_PATH = Path(__file__).resolve().parents[2] / "tools" / "ble_discovery.py"
ALLOWED_SUBSCRIPTIONS = {0x2AD2, 0x2ADA, 0x2AD3, 0x2A63, 0x2A5B, 0x2A37}
LEGACY_ZWIFT = "00000001-19ca-4651-86e5-fa29dcdd09d1"
PROPRIETARY = "a026ee01-0a7d-4440-be5e-8fb75d0ba0a0"  # herstellerspezifisch, darf nie abonniert werden


@pytest.fixture(scope="module")
def tool():
    spec = importlib.util.spec_from_file_location("ble_discovery_tool", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def uuid16(short: int) -> str:
    return f"0000{short:04x}-0000-1000-8000-00805f9b34fb"


# --- Fake-bleak ------------------------------------------------------------------------------------------

class FakeChar:
    def __init__(self, uuid: str, props: list[str], value: bytes = b"", handle: int = 0) -> None:
        self.uuid, self.properties, self.value, self.handle, self.descriptors = uuid, props, value, handle, []


class FakeService:
    def __init__(self, uuid: str, chars: list[FakeChar]) -> None:
        self.uuid, self.characteristics = uuid, chars


class FakeWorld:
    """Fake-Umgebung: Geräte der Suche samt GATT-Tabelle; merkt sich alle Schreib- und Abo-Versuche."""

    def __init__(self) -> None:
        self.adverts: list[tuple[SimpleNamespace, SimpleNamespace]] = []
        self.services: dict[str, list[FakeService]] = {}
        self.connect_errors: dict[str, Exception] = {}
        self.scan_error: Exception | None = None
        self.writes: list[str] = []
        self.subscribed: list[str] = []
        self.subscribe_delay = 0.0  # Dauer je start_notify wie am echten Rad (Meldungen laufen schon)
        self.feed_count = 5

    def add(self, address, name, rssi, service_uuids=(), manufacturer=None, services=None) -> None:
        device = SimpleNamespace(address=address, name=name)
        adv = SimpleNamespace(local_name=name, rssi=rssi, service_uuids=list(service_uuids),
                              manufacturer_data=manufacturer or {})
        self.adverts.append((device, adv))
        self.services[address] = services or []

    @property
    def subscribed_shorts(self) -> set[int]:
        return {int(u[4:8], 16) for u in self.subscribed if u.endswith("-0000-1000-8000-00805f9b34fb")}

    def violations(self) -> list[str]:
        bad_subscriptions = [u for u in self.subscribed
                             if u not in {uuid16(s) for s in ALLOWED_SUBSCRIPTIONS}]
        return self.writes + bad_subscriptions

    def install(self, monkeypatch, tool) -> None:
        world = self

        class FakeScanner:
            @staticmethod
            async def discover(timeout=5.0, return_adv=False):
                if world.scan_error:
                    raise world.scan_error
                return {d.address: (d, a) for d, a in world.adverts}

        class FakeClient:
            def __init__(self, device, timeout=10.0) -> None:
                self.address = device.address
                self.tasks: list[asyncio.Task] = []

            async def __aenter__(self):
                if self.address in world.connect_errors:
                    raise world.connect_errors[self.address]
                return self

            async def __aexit__(self, *exc):
                for task in self.tasks:
                    task.cancel()

            @property
            def is_connected(self) -> bool:
                return True

            @property
            def services(self):
                return world.services[self.address]

            async def read_gatt_char(self, char):
                return bytearray(char.value)

            async def write_gatt_char(self, char, data, response=None):
                world.writes.append(f"write_gatt_char {getattr(char, 'uuid', char)}")

            async def write_gatt_descriptor(self, handle, data):
                world.writes.append(f"write_gatt_descriptor {handle}")

            async def start_notify(self, char, callback):
                world.subscribed.append(char.uuid)
                if char.uuid == uuid16(0x2AD2):
                    self.tasks.append(asyncio.create_task(self._feed(callback)))
                await asyncio.sleep(world.subscribe_delay)

            async def stop_notify(self, char):
                pass

            @staticmethod
            async def _feed(callback):
                for _ in range(world.feed_count):
                    await asyncio.sleep(0.02)
                    callback(None, bytearray(IBD_CADENCE_POWER))

        monkeypatch.setattr(tool, "BleakScanner", FakeScanner)
        monkeypatch.setattr(tool, "BleakClient", FakeClient)


# Indoor Bike Data: Flags 0x0044 (Geschwindigkeit da, Kadenz, Leistung), 40,00 km/h, 90 rpm, 150 W
IBD_CADENCE_POWER = bytes.fromhex("4400" "a00f" "b400" "9600")
FEATURE_BYTES = bytes.fromhex("82400000" "0c200000")  # Kadenz, Widerstandsstufe, Leistung / Widerstand, ERG, SIM
RESISTANCE_BYTES = bytes.fromhex("0000" "e803" "0a00")  # 0 bis 100,0 in Schritten von 1,0
POWER_BYTES = bytes.fromhex("0000" "d007" "0100")  # 0 bis 2000 W, 1 W


def trainer_services() -> list[FakeService]:
    return [
        FakeService(uuid16(0x1826), [
            FakeChar(uuid16(0x2ACC), ["read"], FEATURE_BYTES),
            FakeChar(uuid16(0x2AD2), ["notify"]),
            FakeChar(uuid16(0x2AD3), ["notify"]),
            FakeChar(uuid16(0x2AD6), ["read"], RESISTANCE_BYTES),
            FakeChar(uuid16(0x2AD8), ["read"], POWER_BYTES),
            FakeChar(uuid16(0x2AD9), ["write", "indicate"]),
            FakeChar(uuid16(0x2ADA), ["notify"]),
        ]),
        FakeService(uuid16(0x1818), [FakeChar(uuid16(0x2A63), ["notify"])]),
        FakeService(uuid16(0x180A), [
            FakeChar(uuid16(0x2A29), ["read"], b"Wahoo Fitness"),
            FakeChar(uuid16(0x2A24), ["read"], b"KICKR CORE 2"),
            FakeChar(uuid16(0x2A26), ["read"], b"1.2.3"),
        ]),
        FakeService(PROPRIETARY, [FakeChar("a026e002-0a7d-4440-be5e-8fb75d0ba0a0", ["notify", "write"])]),
    ]


def controller_services(visible: bool, firmware: str) -> list[FakeService]:
    services = [FakeService(uuid16(0x180A), [FakeChar(uuid16(0x2A26), ["read"], firmware.encode())]),
                FakeService(uuid16(0x180F), [FakeChar(uuid16(0x2A19), ["read", "notify"], bytes([87]))])]
    if visible:
        services.append(FakeService(uuid16(0xFC82), [FakeChar("00000002-19ca-4651-86e5-fa29dcdd09d1", ["write"]),
                                                      FakeChar("00000003-19ca-4651-86e5-fa29dcdd09d1", ["notify"])]))
    return services


def full_world(monkeypatch, tool) -> FakeWorld:
    world = FakeWorld()
    world.add("T1", "KICKR CORE 2 1234", -60, [uuid16(0x1826), uuid16(0x1818)], services=trainer_services())
    world.add("C1", "Zwift SF2", -50, [], {0x094A: bytes([7, 1])}, controller_services(True, "1.1.0"))
    world.add("C2", "Zwift SF2", -55, [], {0x094A: bytes([8, 1])}, controller_services(False, "1.3.2"))
    world.add("X", "Kopfhörer", -40)
    world.install(monkeypatch, tool)
    return world


def run_tool(tool, tmp_path, *extra: str) -> int:
    return tool.main(["--scan-time", "0", "--duration", "0.3", "--out", str(tmp_path / "out"), *extra])


# --- Dekodierung -----------------------------------------------------------------------------------------

def test_decode_fitness_machine_feature(tool):
    features = tool.decode_fitness_machine_feature(FEATURE_BYTES)
    assert features["machine"] == ["Kadenz", "Widerstandsstufe", "Leistung"]
    assert features["target"] == ["Zielwiderstand", "Zielleistung (ERG)", "Simulation (SIM)"]
    assert features["machine_raw"] == "0x00004082" and features["target_raw"] == "0x0000200C"


def test_decode_feature_marks_unnamed_bits_and_rejects_short_data(tool):
    assert tool.decode_fitness_machine_feature(bytes.fromhex("00000080" "00000000"))["machine"] == ["unbekanntes Bit 31"]
    assert tool.decode_fitness_machine_feature(bytes(8)) == {
        "machine_raw": "0x00000000", "machine": [], "target_raw": "0x00000000", "target": []}
    with pytest.raises(ValueError):
        tool.decode_fitness_machine_feature(bytes(7))


def test_decode_ranges(tool):
    assert tool.decode_resistance_range(RESISTANCE_BYTES) == {"min": 0.0, "max": 100.0, "step": 1.0}
    assert tool.decode_resistance_range(bytes.fromhex("f6ff" "0a00" "0100"))["min"] == -1.0  # sint16
    assert tool.decode_power_range(POWER_BYTES) == {"min_w": 0, "max_w": 2000, "step_w": 1}
    with pytest.raises(ValueError):
        tool.decode_power_range(bytes(5))
    with pytest.raises(ValueError):
        tool.decode_resistance_range(bytes(5))


def test_inspect_indoor_bike_data(tool):
    assert tool.inspect_indoor_bike_data(IBD_CADENCE_POWER) == {
        "cadence_flag": True, "power_flag": True, "cadence_rpm": 90.0, "power_w": 150}
    only_speed = tool.inspect_indoor_bike_data(bytes.fromhex("0000" "a00f"))
    assert only_speed["cadence_flag"] is False and only_speed["power_flag"] is False
    assert only_speed["cadence_rpm"] is None
    # Bit 0 gesetzt = keine Geschwindigkeit; Flags nur Leistung (Bit 6), -5 W
    assert tool.inspect_indoor_bike_data(bytes.fromhex("4100" "fbff"))["power_w"] == -5
    assert tool.inspect_indoor_bike_data(b"\x44")["cadence_flag"] is False


# --- Erkennung -------------------------------------------------------------------------------------------

def test_classify_trainer_by_service(tool):
    assert tool.classify_device("x", [uuid16(0x1826)], {})["trainer_kind"] == "FTMS"
    assert tool.classify_device("x", [uuid16(0x1818)], {})["trainer_kind"] == "Cycling Power"
    assert tool.classify_device("x", [uuid16(0x1816)], {})["trainer_kind"] == "CSC"
    assert tool.classify_device("x", [uuid16(0x180D)], {})["role"] is None


def test_classify_zwift_controller_sides(tool):
    right = tool.classify_device("", [], {0x094A: bytes([7, 0])})
    left = tool.classify_device("", [], {0x094A: bytes([8, 0])})
    other = tool.classify_device("", [], {0x094A: bytes([9, 0])})
    assert (right["role"], right["side"]) == ("controller", "rechts")
    assert (left["role"], left["side"]) == ("controller", "links")
    assert (other["role"], other["side"]) == ("controller", "unbekannt")
    by_name = tool.classify_device("Zwift SF2", [], {})
    assert (by_name["role"], by_name["side"]) == ("controller", "unbekannt")
    assert tool.classify_device("Zwift SF2", [uuid16(0xFC82)], {})["advertises_zwift_service"] is True
    assert tool.classify_device("x", [LEGACY_ZWIFT], {0x094A: bytes([7])})["advertises_zwift_service"] is True
    assert tool.classify_device("Andere Firma", [], {0x004C: bytes([7])})["role"] is None


def test_pick_trainer_strongest_signal_and_ftms_first(tool):
    def dev(kind, rssi, name):
        return {"role": "trainer", "trainer_kind": kind, "rssi": rssi, "name": name}

    devices = [dev("Cycling Power", -30, "cp"), dev("FTMS", -80, "weak"), dev("FTMS", -50, "strong"),
               {"role": None, "trainer_kind": None, "rssi": -10, "name": "other"}]
    assert tool.pick_trainer(devices)["name"] == "strong"
    assert tool.pick_trainer(devices[:1])["name"] == "cp"
    assert tool.pick_trainer(devices[3:]) is None


# --- Urteil ----------------------------------------------------------------------------------------------

def test_controller_verdict_visible(tool):
    verdict = tool.judge_controller(True, "1.3.0")
    assert verdict["verdict"] == "sichtbar" and "erreichbar" in verdict["text"]


@pytest.mark.parametrize("firmware", ["1.3.0", "1.4", "2.0.1"])
def test_controller_verdict_locked_new_firmware_mentions_zwift_app(tool, firmware):
    verdict = tool.judge_controller(False, firmware)
    assert verdict["verdict"] == "gesperrt"
    assert "Ride V2 gibt ihn erst frei, nachdem er in der Zwift-App verbunden war (ca. 24 h)" in verdict["text"]


def test_controller_verdict_locked_old_or_unknown_firmware(tool):
    old = tool.judge_controller(False, "1.2.9")
    assert old["verdict"] == "gesperrt" and "24 h" not in old["text"] and "älter als 1.3" in old["text"]
    unknown = tool.judge_controller(False, None)
    assert unknown["verdict"] == "gesperrt" and "24 h" in unknown["text"] and "nicht lesen" in unknown["text"]


# --- Ganzer Lauf -----------------------------------------------------------------------------------------

def test_full_run_writes_result_and_replayable_raw_file(tool, monkeypatch, tmp_path, capsys):
    full_world(monkeypatch, tool)
    assert run_tool(tool, tmp_path) == 0
    out = tmp_path / "out"
    [result_file] = out.glob("geraetepruefung_*.json")
    [raw_file] = out.glob("trainer_*.raw.jsonl")
    result = json.loads(result_file.read_text(encoding="utf-8"))

    trainer = result["trainer"]
    assert trainer["address"] == "T1"
    assert trainer["features"]["machine"] == ["Kadenz", "Widerstandsstufe", "Leistung"]
    assert "Zielleistung (ERG)" in trainer["features"]["target"]
    assert trainer["resistance_range"]["max"] == 100.0 and trainer["power_range"]["max_w"] == 2000
    assert trainer["device_information"] == {"manufacturer": "Wahoo Fitness", "model": "KICKR CORE 2",
                                             "firmware": "1.2.3", "hardware": None}
    assert {s["kind"] for s in trainer["services"]} >= {"FTMS", "Cycling Power", "Device Information"}
    assert any(s["kind"].startswith("unbekannt") for s in trainer["services"])
    ibd = trainer["capture"]["indoor_bike_data"]
    assert ibd["messages"] == 5 and ibd["cadence_flag_messages"] == 5 and ibd["max_cadence_rpm"] == 90.0
    assert ibd["max_power_w"] == 150 and ibd["messages_per_second"] > 0
    assert any(line.startswith("Kadenz in 0x2AD2: ja") for line in trainer["findings"])
    assert any(line.startswith("Leistung in 0x2AD2: ja") for line in trainer["findings"])

    right, left = {c["side"]: c for c in result["controllers"]}["rechts"], \
        {c["side"]: c for c in result["controllers"]}["links"]
    assert right["verdict"] == "sichtbar" and right["firmware"] == "1.1.0" and right["battery_percent"] == 87
    assert left["verdict"] == "gesperrt" and left["firmware"] == "1.3.2" and "24 h" in left["text"]
    assert len(result["scan"]) == 4 and not any("_device" in d for d in result["scan"])

    # Replay-Format: volle 128-Bit-UUID, t_ms aufsteigend, lädt in der Bridge
    lines = [json.loads(line) for line in raw_file.read_text(encoding="utf-8").splitlines()]
    assert len(lines) == 5
    assert {line["char"] for line in lines} == {uuid16(0x2AD2)}
    assert [line["t_ms"] for line in lines] == sorted(line["t_ms"] for line in lines)
    assert lines[0]["hex"] == IBD_CADENCE_POWER.hex()
    source = load_replay(raw_file)
    assert len(source.notifications) == 5
    assert {c.value for c in source.capabilities} == {"CADENCE", "POWER", "SPEED"}

    text = capsys.readouterr().out
    assert "BITTE VORHER SCHLIESSEN: Zwift, die Wahoo-App" in text
    assert "locker treten" in text and "schneller treten" in text and "AUFHÖREN" in text
    assert "Bitte schicke diese Dateien zurück" in text
    assert str(result_file) in text and str(raw_file) in text
    assert "Zielleistung (ERG)" in text and "Simulation (SIM)" in text


def test_raw_file_timestamps_stay_ascending_when_messages_arrive_while_subscribing(tool, monkeypatch, tmp_path):
    """Die Zeitbasis von t_ms gilt ab dem ersten Abo; sonst lehnt der Replay die Datei ab (t_ms darf nicht fallen)."""
    world = full_world(monkeypatch, tool)
    world.subscribe_delay, world.feed_count = 0.05, 15
    assert tool.main(["--scan-time", "0", "--duration", "0.6", "--out", str(tmp_path / "out")]) == 0
    [raw_file] = (tmp_path / "out").glob("trainer_*.raw.jsonl")
    times = [json.loads(line)["t_ms"] for line in raw_file.read_text(encoding="utf-8").splitlines()]
    assert len(times) == 15 and times == sorted(times)
    assert len(load_replay(raw_file).notifications) == 15


def test_result_folder_is_gitignored(tool):
    assert (TOOL_PATH.parent.parent / ".gitignore").read_text(encoding="utf-8").count("pruefung/") == 1


def test_scan_only_writes_nothing_and_connects_to_nothing(tool, monkeypatch, tmp_path):
    world = full_world(monkeypatch, tool)
    assert tool.main(["--scan-time", "0", "--scan-only", "--out", str(tmp_path / "out")]) == 0
    assert not (tmp_path / "out").exists() and world.subscribed == []


def test_strongest_of_several_trainers_is_used(tool, monkeypatch, tmp_path, capsys):
    world = FakeWorld()
    world.add("WEAK", "Trainer schwach", -85, [uuid16(0x1826)], services=trainer_services())
    world.add("STRONG", "Trainer stark", -45, [uuid16(0x1826)], services=trainer_services())
    world.install(monkeypatch, tool)
    assert run_tool(tool, tmp_path) == 0
    [result_file] = (tmp_path / "out").glob("geraetepruefung_*.json")
    assert json.loads(result_file.read_text(encoding="utf-8"))["trainer"]["address"] == "STRONG"
    assert "Mehrere Trainer" in capsys.readouterr().out


# --- Nur lesen (Abnahmepunkt 5) --------------------------------------------------------------------------

def test_full_run_only_reads_and_never_touches_control_point(tool, monkeypatch, tmp_path):
    world = full_world(monkeypatch, tool)
    assert run_tool(tool, tmp_path) == 0
    assert world.writes == []
    assert world.subscribed, "der Lauf muss die Messdaten abonnieren"
    assert 0x2AD9 not in world.subscribed_shorts
    assert world.subscribed_shorts <= ALLOWED_SUBSCRIPTIONS
    assert PROPRIETARY not in world.subscribed and "a026e002-0a7d-4440-be5e-8fb75d0ba0a0" not in world.subscribed
    assert world.violations() == []


def test_probe_detects_writes_and_control_point_subscription(tool, monkeypatch):
    """Gegenprobe: dieselbe Fake-Umgebung schlägt an, sobald Code schreibt oder 0x2AD9 abonniert."""
    world = full_world(monkeypatch, tool)
    control_point = trainer_services()[0].characteristics[5]

    async def misbehave():
        client = tool.BleakClient(world.adverts[0][0])
        async with client:
            await client.start_notify(control_point, lambda *_: None)
            await client.write_gatt_char(control_point, b"\x00")

    asyncio.run(misbehave())
    assert 0x2AD9 in world.subscribed_shorts
    assert len(world.violations()) == 2


def test_tool_source_has_no_write_calls(tool):
    source = TOOL_PATH.read_text(encoding="utf-8")
    assert "write_gatt" not in source
    assert 0x2AD9 not in tool.SUBSCRIBABLE and all(s <= 0xFFFF for s in tool.SUBSCRIBABLE)


# --- Fehler ----------------------------------------------------------------------------------------------

def test_no_bluetooth_adapter(tool, monkeypatch, tmp_path, capsys):
    world = full_world(monkeypatch, tool)
    world.scan_error = BleakError("Bluetooth device is turned off")
    assert run_tool(tool, tmp_path) == 1
    out = capsys.readouterr().out
    assert "Bluetooth ist nicht verfügbar" in out and "eingeschaltet" in out
    assert not (tmp_path / "out").exists()


def test_no_trainer_found(tool, monkeypatch, tmp_path, capsys):
    world = FakeWorld()
    world.add("X", "Kopfhörer", -40)
    world.install(monkeypatch, tool)
    assert run_tool(tool, tmp_path) == 2
    out = capsys.readouterr().out
    assert "Kein Trainer gefunden" in out and "aufgeweckt" in out and "3 BLE-Verbindungen" in out


def test_trainer_connection_refused_gives_pairing_hint_and_controllers_still_checked(
        tool, monkeypatch, tmp_path, capsys):
    world = full_world(monkeypatch, tool)
    world.connect_errors["T1"] = BleakError("Access denied")
    assert run_tool(tool, tmp_path) == 0  # die Controller wurden erfasst
    out = capsys.readouterr().out
    assert "Verbindung zum Trainer fehlgeschlagen" in out
    assert "gebondetes Pairing" in out and "Bluetooth & Geräte" in out
    [result_file] = (tmp_path / "out").glob("geraetepruefung_*.json")
    result = json.loads(result_file.read_text(encoding="utf-8"))
    assert "Access denied" in result["trainer"]["error"]
    assert {c["verdict"] for c in result["controllers"]} == {"sichtbar", "gesperrt"}
    assert not list((tmp_path / "out").glob("*.raw.jsonl"))


def test_controller_error_does_not_abort_trainer_check(tool, monkeypatch, tmp_path, capsys):
    world = full_world(monkeypatch, tool)
    world.connect_errors["C1"] = asyncio.TimeoutError()
    assert run_tool(tool, tmp_path) == 0
    [result_file] = (tmp_path / "out").glob("geraetepruefung_*.json")
    result = json.loads(result_file.read_text(encoding="utf-8"))
    assert result["trainer"]["capture"]["indoor_bike_data"]["messages"] == 5
    verdicts = {c["side"]: c["verdict"] for c in result["controllers"]}
    assert verdicts == {"rechts": "nicht geprüft", "links": "gesperrt"}
    assert "Verbindung zum Controller fehlgeschlagen" in capsys.readouterr().out


def test_nothing_captured_when_every_connection_fails(tool, monkeypatch, tmp_path):
    world = full_world(monkeypatch, tool)
    for address in ("T1", "C1", "C2"):
        world.connect_errors[address] = BleakError("refused")
    assert run_tool(tool, tmp_path) == 3
    assert list((tmp_path / "out").glob("geraetepruefung_*.json"))
