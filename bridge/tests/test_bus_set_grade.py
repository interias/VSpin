"""Rückkanal Client → Bridge (ADR-0007): `set_grade`, `ack`, `error` – nur am Bus geprüft."""

import json

import pytest
from bridge_harness import receive_json

ACK_FIELDS = {"v", "type", "for", "ok", "reason"}
ERROR_FIELDS = {"v", "type", "reason", "detail"}
NOT_SUPPORTED_ACK = {"v": 0, "type": "ack", "for": "set_grade", "ok": False, "reason": "not_supported"}


def start_sim(bridge_process, cadence: str = "80"):
    return bridge_process("--source", "sim", "--sim-cadence", cadence)


def connect(bus_client):
    client = bus_client()
    assert receive_json(client)["type"] == "status"
    return client


def reply_to(client, payload, max_messages: int = 40) -> dict:
    """Sendet `payload` und liefert die erste Nicht-Telemetrie-Nachricht (ack/error)."""
    client.send(payload if isinstance(payload, (str, bytes)) else json.dumps(payload))
    for _ in range(max_messages):
        message = receive_json(client)
        if message["type"] != "telemetry":
            return message
    raise AssertionError("keine Antwort auf die Client-Nachricht")


def settled_cadence(client, max_samples: int = 40) -> float:
    """Kadenz nach einer Änderung: Am Bus ist die Kadenz geglättet (EMA 0,3 s, ADR-0004), sie
    läuft also auf den neuen Wert zu. Abwarten, bis sich drei Samples um < 0,2 rpm
    unterscheiden (Restabstand zum Ziel dann < 0,5 rpm)."""
    cadences: list[float] = []
    while len(cadences) < max_samples:
        message = receive_json(client)
        if message["type"] == "telemetry":
            cadences.append(message["cadence"])
            if len(cadences) >= 3 and max(cadences[-3:]) - min(cadences[-3:]) < 0.2:
                return cadences[-1]
    raise AssertionError(f"Kadenz pendelt sich nicht ein: {cadences}")


def test_set_grade_is_acked_not_supported_and_logged(bridge_process, bus_client):
    bridge = start_sim(bridge_process)
    client = connect(bus_client)
    ack = reply_to(client, {"v": 0, "type": "set_grade", "grade": 0.07})
    assert set(ack) == ACK_FIELDS
    assert ack == NOT_SUPPORTED_ACK
    bridge.stop()
    assert "set_grade +0.070 (+7.0 %) -> not_supported" in bridge.log()


def test_simulator_cadence_drops_uphill_and_recovers_at_zero(bridge_process, bus_client):
    start_sim(bridge_process, cadence="80")
    client = connect(bus_client)
    assert settled_cadence(client) == 80

    assert reply_to(client, {"v": 0, "type": "set_grade", "grade": 0.07}) == NOT_SUPPORTED_ACK
    uphill = settled_cadence(client)
    assert uphill < 80 * 0.95, f"Kadenz bergauf kaum gesunken: {uphill}"  # spürbar: > 5 %
    assert uphill > 0

    assert reply_to(client, {"v": 0, "type": "set_grade", "grade": 0.12})["type"] == "ack"
    assert settled_cadence(client) < uphill  # steiler → noch weniger

    assert reply_to(client, {"v": 0, "type": "set_grade", "grade": 0})["type"] == "ack"
    assert abs(settled_cadence(client) - 80) < 0.5


BROKEN_MESSAGES = [
    pytest.param("kein json", "invalid_json", id="no-json"),
    pytest.param(b"\x00\x01", "invalid_json", id="binary-frame"),
    pytest.param("[" * 100_000, "invalid_json", id="too-deeply-nested"),
    pytest.param("[1, 2]", "invalid_message", id="not-an-object"),
    pytest.param({"v": 0, "grade": 0.05}, "invalid_message", id="missing-type"),
    pytest.param({"v": 1, "type": "set_grade", "grade": 0.05}, "unsupported_version", id="wrong-version"),
    pytest.param({"type": "set_grade", "grade": 0.05}, "unsupported_version", id="missing-version"),
    pytest.param({"v": True, "type": "set_grade", "grade": 0.05}, "unsupported_version", id="bool-version"),
    pytest.param({"v": 0, "type": "set_speed", "speed": 3}, "unknown_type", id="unknown-type"),
    pytest.param({"v": 0, "type": "set_grade"}, "invalid_grade", id="grade-missing"),
    pytest.param({"v": 0, "type": "set_grade", "grade": "0.07"}, "invalid_grade", id="grade-string"),
    pytest.param({"v": 0, "type": "set_grade", "grade": None}, "invalid_grade", id="grade-null"),
    pytest.param({"v": 0, "type": "set_grade", "grade": True}, "invalid_grade", id="grade-bool"),
    pytest.param('{"v": 0, "type": "set_grade", "grade": NaN}', "invalid_grade", id="grade-nan"),
    pytest.param('{"v": 0, "type": "set_grade", "grade": Infinity}', "invalid_grade", id="grade-inf"),
    pytest.param('{"v": 0, "type": "set_grade", "grade": 1e999}', "invalid_grade", id="grade-overflow"),
    pytest.param('{"v": 0, "type": "set_grade", "grade": ' + "9" * 400 + "}", "invalid_grade", id="grade-huge-int"),
]


@pytest.mark.parametrize(("payload", "reason"), BROKEN_MESSAGES)
def test_broken_message_gets_error_and_connection_stays_usable(bridge_process, bus_client, payload, reason):
    start_sim(bridge_process)
    client = connect(bus_client)
    error = reply_to(client, payload)
    assert set(error) == ERROR_FIELDS
    assert error["v"] == 0 and error["type"] == "error"
    assert error["reason"] == reason
    assert isinstance(error["detail"], str) and error["detail"]
    # Verbindung offen: ein gültiges set_grade wird danach normal beantwortet.
    assert reply_to(client, {"v": 0, "type": "set_grade", "grade": 0.03}) == NOT_SUPPORTED_ACK


def test_replies_go_only_to_the_sender_and_others_keep_receiving_telemetry(bridge_process, bus_client):
    start_sim(bridge_process)
    sender, other = connect(bus_client), connect(bus_client)

    assert reply_to(sender, "kaputt")["type"] == "error"
    assert reply_to(sender, {"v": 0, "type": "set_grade", "grade": 0.05}) == NOT_SUPPORTED_ACK
    # Danach sicher nach den Antworten erzeugte Telemetrie abwarten.
    for _ in range(4):
        receive_json(sender)

    seen = [receive_json(other) for _ in range(16)]
    assert {m["type"] for m in seen} == {"telemetry"}, seen  # kein fremdes ack/error
    assert seen[-1]["cadence"] < 80  # die Steigung wirkt auf die gemeinsame Quelle


def test_bridge_keeps_running_after_broken_messages(bridge_process, bus_client):
    bridge = start_sim(bridge_process)
    client = connect(bus_client)
    for payload in ("{", "null", '{"v":0}', '{"v":0,"type":"set_grade","grade":"x"}'):
        assert reply_to(client, payload)["type"] == "error"
    client.close()
    newcomer = connect(bus_client)  # neuer Client: Bus läuft weiter
    assert receive_json(newcomer)["type"] == "telemetry"
    assert bridge.stop() == 0
