"""Bridge mit `--source sim` als Prozess; geprüft wird nur das Verhalten am Bus."""

from bridge_harness import HOST, PORT, port_open, receive_json
from sim_pulse import is_window, simulator_pulse
from vspin_bridge.cli import build_parser

TELEMETRY_FIELDS = {"v", "type", "t_ms", "cadence", "cadence_raw", "speed_kmh", "power_w", "power_estimated", "heart_rate"}
STATUS_FIELDS = {"v", "type", "t_ms", "state", "source", "capabilities", "heart_rate"}


def start_sim(bridge_process, cadence: str = "80"):
    return bridge_process("--source", "sim", "--sim-cadence", cadence)


def test_new_client_gets_status_first_then_telemetry_with_monotonic_t_ms(bridge_process, bus_client, isolated_bus):
    start_sim(bridge_process)
    client = bus_client()

    status = receive_json(client)
    assert set(status) == STATUS_FIELDS
    assert status["v"] == 0
    assert status["type"] == "status"
    assert status["source"] == "sim"
    assert status["state"] == "connected"
    assert status["capabilities"] == ["CADENCE"]
    assert isinstance(status["t_ms"], int)

    samples = [receive_json(client) for _ in range(8)]
    assert [m["type"] for m in samples] == ["telemetry"] * 8
    for message in samples:
        assert set(message) == TELEMETRY_FIELDS
        assert message["v"] == 0
        assert message["cadence"] == 80
        assert message["cadence_raw"] == 80  # ungeglättet (#45); bei konstanter Kadenz gleich
        # Der Simulator liefert nur Kadenz; fehlende Werte sind null.
        assert message["speed_kmh"] is None
        assert message["power_w"] is None
        assert message["power_estimated"] is None
    # Der Simulator liefert den Puls eines FTMS-Rads: träge steigend, bei 80 rpm vom Ruhepuls Richtung 132 bpm.
    # Ohne Pulsgerät geht er unverändert auf den Bus; ein Client sieht einen Ausschnitt vom Anfang der erwarteten
    # Folge (er hängt praktisch ab Start am Bus, höchstens 10 s später).
    pulses = [m["heart_rate"] for m in samples]
    assert all(isinstance(p, int) for p in pulses), pulses
    assert is_window(pulses, simulator_pulse(80.0, 40 + len(pulses))), pulses
    t_ms = [m["t_ms"] for m in samples]
    assert all(isinstance(t, int) for t in t_ms)
    assert t_ms == sorted(t_ms) and len(set(t_ms)) == len(t_ms), f"t_ms nicht streng monoton: {t_ms}"
    assert status["t_ms"] <= t_ms[0]


def test_every_bus_message_has_v_and_type(bridge_process, bus_client):
    start_sim(bridge_process, cadence="0")
    client = bus_client()
    messages = [receive_json(client) for _ in range(12)]
    for message in messages:
        assert message["v"] == 0
        assert message["type"] in {"status", "telemetry"}
    assert messages[0]["type"] == "status"
    assert messages[1]["cadence"] == 0


def test_multiple_clients_receive_the_same_messages(bridge_process, bus_client):
    start_sim(bridge_process)
    first, second, third = bus_client(), bus_client(), bus_client()
    for client in (first, second, third):
        assert receive_json(client)["type"] == "status"

    streams = [[receive_json(c) for _ in range(10)] for c in (first, second, third)]

    # Clients sind kurz nacheinander verbunden: ab dem ersten gemeinsamen
    # Sample müssen alle exakt dieselben Nachrichten in derselben Reihenfolge sehen.
    common_start = max(stream[0]["t_ms"] for stream in streams)
    aligned = [[m for m in stream if m["t_ms"] >= common_start] for stream in streams]
    length = min(len(a) for a in aligned)
    assert length >= 5, aligned
    assert aligned[0][:length] == aligned[1][:length] == aligned[2][:length]


def test_bus_listens_only_on_127_0_0_1(bridge_process):
    start_sim(bridge_process)
    assert port_open(HOST, PORT)
    # Andere Loopback-Adresse bzw. IPv6: nur erreichbar, wenn auf allen Interfaces gelauscht würde.
    assert not port_open("127.0.0.2", PORT)
    assert not port_open("::1", PORT)


def test_host_option_listens_on_all_interfaces(bridge_process, bus_client):
    # Für den Container (docker-compose.yml): --host 0.0.0.0 ist auch über andere Adressen erreichbar.
    bridge = bridge_process("--source", "sim", "--sim-cadence", "80", "--host", "0.0.0.0")
    assert port_open("127.0.0.2", PORT)
    assert receive_json(bus_client())["type"] == "status"
    assert f"Bus auf ws://0.0.0.0:{PORT}" in bridge.log()


def test_bus_port_stays_8765_unless_given(monkeypatch):
    # Für den Nutzer ändert sich nichts (#62): Die Bridge liest VSPIN_PORT_BASE nicht selbst; nur Test- und
    # Prüfläufe geben ihr mit --port einen eigenen Port (Harness: jede Bridge hier läuft auf `PORT`).
    monkeypatch.setenv("VSPIN_PORT_BASE", "5")
    assert build_parser().parse_args(["--source", "sim"]).port == 8765
    assert build_parser().parse_args(["--source", "sim", "--port", "8770"]).port == 8770


def test_bridge_stops_cleanly_and_frees_the_port(bridge_process, bus_client):
    bridge = start_sim(bridge_process)
    client = bus_client()
    assert receive_json(client)["type"] == "status"
    assert bridge.stop() == 0  # stop() wartet auch, bis der Port wieder frei ist
    assert not port_open()
    log = bridge.log()
    assert "Quelle: sim" in log and "Status: connected" in log and "Kadenz: 80 rpm" in log
