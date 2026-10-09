## Fake-Bus-Server für Spiel-Tests: ein WebSocket-Server, der jedem verbundenen Client
## ein Nachrichten-Drehbuch vorspielt und empfangene Client-Nachrichten mitschreibt.
## Läuft auf einem eigenen Port (Standard 18765), nie auf dem Bus-Port 8765 der Bridge.
##
## Drehbuch = Array von Schritten, Zeit `at` in Sekunden ab Verbindungsaufbau des Clients:
##   {"at": 0.0, "send": {...}}   Nachricht (Dictionary, wird als JSON gesendet)
##   {"at": 2.0, "close": true}   Verbindung serverseitig schließen (Abbruch/Reconnect testen)
## Jede neue Verbindung spielt das Drehbuch von vorn. Bausteine: `status()`, `telemetry()`,
## `steady_cadence()`; als Datei: JSON-Array gleicher Form über `load_script()`.
## Antworten auf Client-Nachrichten: `replies["set_grade"] = FakeBusServer.ack("set_grade", false, "not_supported")`.
##
##   var bus := FakeBusServer.new([FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.0, 5.0))
##   bus.start(18765)
##   # je Frame: bus.poll()  … am Ende: bus.stop()
class_name FakeBusServer
extends RefCounted

const DEFAULT_PORT := 18765
const HOST := "127.0.0.1"

## Das Drehbuch (Schritte nach `at` sortiert).
var script_steps: Array = []
## Alle vom Client empfangenen Nachrichten (geparstes JSON) in Eingangsreihenfolge.
var received: Array = []
## Empfangszeit je Eintrag in `received` (`Time.get_ticks_msec()`), z. B. für Drosselungs-Tests.
var received_ms: Array = []
## Automatische Antworten: Nachrichtentyp → Antwort an den Absender (z. B. `ack` auf `set_grade`).
var replies := {}
## Anzahl der bisher geöffneten Client-Verbindungen.
var connections_opened := 0
## Uhr des Drehbuchs in ms: < 0 = Echtzeit (`Time.get_ticks_msec()`), sonst dieser Wert – so kann ein Test das
## Drehbuch in festen Schritten vorrücken, gleichauf mit einer Hauptszene, die er selbst schrittweise fährt (#46).
var manual_clock_ms := -1
var port := DEFAULT_PORT

var _server := TCPServer.new()
var _connections: Array = []  # je Eintrag: {peer, opened_ms, next}


func _init(steps: Array = []) -> void:
	script_steps = steps.duplicate()
	script_steps.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))


func url() -> String:
	return "ws://%s:%d" % [HOST, port]


func start(listen_port: int = DEFAULT_PORT) -> Error:
	port = listen_port
	return _server.listen(port, HOST)


func stop() -> void:
	for c in _connections:
		c["peer"].close()
	_connections.clear()
	_server.stop()


## Anzahl offener Client-Verbindungen.
func open_connections() -> int:
	var count := 0
	for c in _connections:
		if c["peer"].get_ready_state() == WebSocketPeer.STATE_OPEN:
			count += 1
	return count


## Nimmt Verbindungen an, spielt fällige Drehbuch-Schritte ab, liest Client-Nachrichten.
func poll() -> void:
	while _server.is_connection_available():
		var peer := WebSocketPeer.new()
		peer.accept_stream(_server.take_connection())
		_connections.append({"peer": peer, "opened_ms": -1, "next": 0})
	var now := manual_clock_ms if manual_clock_ms >= 0 else Time.get_ticks_msec()
	for c in _connections.duplicate():
		var peer: WebSocketPeer = c["peer"]
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_connections.erase(c)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		if c["opened_ms"] < 0:
			c["opened_ms"] = now
			connections_opened += 1
		while peer.get_available_packet_count() > 0:
			var message = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			received.append(message)
			received_ms.append(now)
			if message is Dictionary and replies.has(message.get("type")):
				peer.send_text(JSON.stringify(replies[message["type"]]))
		_play_due(c, (now - c["opened_ms"]) / 1000.0)


func _play_due(c: Dictionary, elapsed_s: float) -> void:
	var peer: WebSocketPeer = c["peer"]
	while c["next"] < script_steps.size() and float(script_steps[c["next"]]["at"]) <= elapsed_s:
		var step: Dictionary = script_steps[c["next"]]
		c["next"] += 1
		if step.get("close", false):
			peer.close()
			return
		if step.has("send"):
			peer.send_text(JSON.stringify(step["send"]))


## Nur die empfangenen Nachrichten vom Typ `type`, je {"message": …, "ms": Empfangszeit}.
func received_of_type(type: String) -> Array:
	var found: Array = []
	for i in received.size():
		if received[i] is Dictionary and received[i].get("type") == type:
			found.append({"message": received[i], "ms": received_ms[i]})
	return found


## Antwort-Baustein: `ack` der Bridge (docs/bus-protocol.md), z. B. `ack("set_grade", false, "not_supported")`.
static func ack(for_type: String, ok: bool, reason = null) -> Dictionary:
	return {"v": 0, "type": "ack", "for": for_type, "ok": ok, "reason": reason}


## Baustein: `status`-Nachricht wie von der Bridge (docs/bus-protocol.md).
static func status(state: String = "connected", source: String = "sim",
		capabilities: Array = ["CADENCE"], at: float = 0.0) -> Dictionary:
	return {"at": at, "send": {"v": 0, "type": "status", "t_ms": int(at * 1000.0),
			"state": state, "source": source, "capabilities": capabilities}}


## Baustein: eine `telemetry`-Nachricht mit Kadenz (übrige Werte null wie beim Simulator).
## `fields` überschreibt/ergänzt Felder, z. B. `{"power_w": 142.0, "power_estimated": true}`.
static func telemetry(cadence: float, at: float = 0.0, fields: Dictionary = {}) -> Dictionary:
	var message := {"v": 0, "type": "telemetry", "t_ms": int(at * 1000.0),
			"cadence": cadence, "speed_kmh": null, "power_w": null,
			"power_estimated": null, "heart_rate": null}
	message.merge(fields, true)
	return {"at": at, "send": message}


## Baustein: gleichbleibende Kadenz von `from_s` bis `to_s`, alle `interval_s` (Bridge-Takt 250 ms).
static func steady_cadence(cadence: float, from_s: float, to_s: float, interval_s: float = 0.25,
		fields: Dictionary = {}) -> Array:
	var steps: Array = []
	var t := from_s
	while t <= to_s + 0.0001:
		steps.append(telemetry(cadence, t, fields))
		t += interval_s
	return steps


## Baustein: Verbindungsabbruch durch den Server zum Zeitpunkt `at`.
static func close_at(at: float) -> Dictionary:
	return {"at": at, "close": true}


## Lädt ein Drehbuch aus einer JSON-Datei (Array von Schritten, Format wie oben).
static func load_script(path: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Array):
		push_error("FakeBusServer: %s ist kein Drehbuch (JSON-Array erwartet)" % path)
		return []
	return data
