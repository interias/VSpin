"""Weiterleitung Client → alle anderen Clients (Spec #76, #77): `ride_state`, `ride_event`, `companion_ptt`,
`companion_status` – unverändert, nie an den Sender, ohne Antwort; nur am Bus geprüft."""

import json

import pytest
from bridge_harness import receive_json

NOT_SUPPORTED_ACK = {"v": 0, "type": "ack", "for": "set_grade", "ok": False, "reason": "not_supported"}

# Frames, wie Spiel und Begleiter sie senden könnten – mit eigenwilligem Leerraum, Umlauten und Feldern, die die
# Bridge nicht kennt: Sie müssen Zeichen für Zeichen ankommen.
RELAYED = [
    pytest.param(
        '{"v":0,"type":"ride_state","mode":"rundfahrt","direction":"cw","lap":2,"km_done":12.4,'
        '"next_poi":"Bergdorf","grade":0.07,"power_w":null,"heart_rate":null,"neu_in_80":[1,2]}',
        id="ride_state",
    ),
    pytest.param(
        '{ "v": 0, "type": "ride_event", "kind": "medal", "medal": "gold", "for": "Küstenwelle" }',
        id="ride_event",
    ),
    pytest.param('{"type":"companion_ptt","v":0,"action":"down"}', id="companion_ptt"),
    pytest.param('{"v":0,"type":"companion_status","state":"speaking","speaking":true}', id="companion_status"),
]


def start_sim(bridge_process):
    return bridge_process("--source", "sim", "--sim-cadence", "80")


def connect(bus_client):
    client = bus_client()
    assert receive_json(client)["type"] == "status"
    return client


def next_non_telemetry(client, max_messages: int = 40) -> str:
    """Nächster Frame, der keine Telemetrie ist – als Rohtext, damit „unverändert“ prüfbar bleibt."""
    for _ in range(max_messages):
        raw = client.recv(timeout=3.0)
        assert isinstance(raw, str), "Bus-Nachrichten sind UTF-8-JSON-Textframes"
        if json.loads(raw)["type"] != "telemetry":
            return raw
    raise AssertionError("keine Nachricht außer Telemetrie")


def assert_sender_got_no_reply(sender) -> None:
    """Auf die weitergeleitete Nachricht bekommt der Sender nichts: Die nächste Nicht-Telemetrie ist das ack
    auf ein danach gesendetes `set_grade` (die Bridge antwortet in Empfangsreihenfolge)."""
    sender.send(json.dumps({"v": 0, "type": "set_grade", "grade": 0.0}))
    assert json.loads(next_non_telemetry(sender)) == NOT_SUPPORTED_ACK


@pytest.mark.parametrize("frame", RELAYED)
def test_relayed_message_reaches_all_other_clients_unchanged_but_not_the_sender(bridge_process, bus_client, frame):
    start_sim(bridge_process)
    sender, first, second = connect(bus_client), connect(bus_client), connect(bus_client)

    sender.send(frame)
    assert next_non_telemetry(first) == frame
    assert next_non_telemetry(second) == frame
    assert_sender_got_no_reply(sender)


def test_relay_works_in_both_directions_and_with_the_sender_alone(bridge_process, bus_client):
    bridge = start_sim(bridge_process)
    game = connect(bus_client)
    ptt = '{"v":0,"type":"companion_ptt","action":"up"}'
    game.send(ptt)  # noch kein anderer Client: geht ins Leere, nichts kaputt
    assert_sender_got_no_reply(game)

    companion = connect(bus_client)
    status = '{"v":0,"type":"companion_status","state":"thinking","speaking":false}'
    companion.send(status)
    game.send(ptt)
    assert next_non_telemetry(game) == status
    assert next_non_telemetry(companion) == ptt
    assert_sender_got_no_reply(game)
    assert_sender_got_no_reply(companion)
    assert bridge.stop() == 0


def test_relay_skips_a_client_that_just_left(bridge_process, bus_client):
    start_sim(bridge_process)
    sender, gone, stays = connect(bus_client), connect(bus_client), connect(bus_client)
    gone.close()
    frame = '{"v":0,"type":"ride_event","kind":"lap","lap":1}'
    sender.send(frame)
    assert next_non_telemetry(stays) == frame
    assert_sender_got_no_reply(sender)


BROKEN_ENVELOPES = [
    pytest.param({"type": "ride_state", "lap": 1}, "unsupported_version", id="ride_state-missing-version"),
    pytest.param({"v": 1, "type": "ride_event", "kind": "lap"}, "unsupported_version", id="ride_event-v1"),
    pytest.param({"v": "0", "type": "companion_ptt", "action": "down"}, "unsupported_version", id="ptt-string-v"),
    pytest.param({"v": True, "type": "companion_status", "state": "idle"}, "unsupported_version", id="status-bool-v"),
    pytest.param({"v": 0, "type": "Ride_State"}, "unknown_type", id="wrong-case"),
    pytest.param({"v": 0, "type": ["ride_state"]}, "unknown_type", id="type-not-a-string"),
    pytest.param({"v": 0, "action": "down"}, "invalid_message", id="missing-type"),
]


@pytest.mark.parametrize(("payload", "reason"), BROKEN_ENVELOPES)
def test_broken_envelope_gets_the_usual_error_and_is_not_relayed(bridge_process, bus_client, payload, reason):
    start_sim(bridge_process)
    sender, other = connect(bus_client), connect(bus_client)
    sender.send(json.dumps(payload))
    error = json.loads(next_non_telemetry(sender))
    assert error["type"] == "error" and error["reason"] == reason
    assert isinstance(error["detail"], str) and error["detail"]

    # Der andere sieht davon nichts – nur die danach weitergeleitete gültige Nachricht.
    valid = '{"v":0,"type":"companion_status","state":"idle","speaking":false}'
    sender.send(valid)
    assert next_non_telemetry(other) == valid


def test_relayed_fields_are_not_checked_by_the_bridge(bridge_process, bus_client):
    """Die Felder gehören Spiel und Begleiter: Auch ein unvollständiger Inhalt geht durch (#80 ergänzt Felder
    ohne Bridge-Änderung)."""
    start_sim(bridge_process)
    sender, other = connect(bus_client), connect(bus_client)
    for frame in ('{"v":0,"type":"companion_ptt"}', '{"v":0,"type":"ride_state","km_done":"viel"}'):
        sender.send(frame)
        assert next_non_telemetry(other) == frame
    assert_sender_got_no_reply(sender)
