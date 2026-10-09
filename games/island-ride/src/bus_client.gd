## Client am Bus (docs/bus-protocol.md, ADR-0002): verbindet sich mit der Bridge,
## reconnectet nach Abbruch, parst `status`/`telemetry` und stellt den Zustand bereit.
##
## Schweigen: Hängt die Bridge bei offenem WebSocket, kommt kein `stale` mehr von ihr. Kommt bei `connected`
## länger als `silence_timeout_s` weder `status` noch `telemetry`, gilt die Quelle als `stale` (`silent` = true);
## die nächste Telemetrie setzt wieder `connected`. Antworten (`ack`/`error`) zählen nicht – sie belegen nur,
## dass die Bridge auf eigene Nachrichten reagiert, nicht dass Daten fließen.
##
## Kein Node: der Besitzer ruft `poll(delta)` regelmäßig auf (z. B. in `_process`).
## Senden an die Bridge (z. B. `set_grade`) läuft über `send_message`; Antworten kommen als `ack_received`.
class_name BusClient
extends RefCounted

## Verbindung zum Bus auf- oder abgebaut (nicht der Gerätestatus der Bridge).
signal bus_connection_changed(connected: bool)
## Neuer Verbindungsstatus der Quelle: connected | stale | disconnected.
signal status_changed(state: String)
## Telemetrie-Nachricht empfangen (geparstes JSON).
signal telemetry_received(message: Dictionary)
## Antwort der Bridge auf eine eigene Nachricht (`ack`, z. B. auf `set_grade`; geparstes JSON).
signal ack_received(message: Dictionary)

const PROTOCOL_VERSION := 0
const STATE_CONNECTED := "connected"
const STATE_STALE := "stale"
const STATE_DISCONNECTED := "disconnected"
## Schweigen bei `connected`, ab dem das Spiel selbst `stale` annimmt (Sekunden). Die Bridge meldet `stale` per
## Timer genau 3 s nach dem letzten Sample (ADR-0004); 1 s Reserve, damit ihr `stale` bei laufender Bridge immer
## zuerst ankommt und nur eine hängende Bridge hier greift.
const SILENCE_TIMEOUT_S := 4.0

var url: String
var reconnect_s: float
## Höchstdauer eines Verbindungsaufbaus (Sekunden); hängt er länger in CONNECTING, wird neu verbunden.
var connect_timeout_s: float
## Schweigen (Sekunden), nach dem eine `connected` gemeldete Quelle als `stale` gilt (siehe SILENCE_TIMEOUT_S).
var silence_timeout_s := SILENCE_TIMEOUT_S
## Gilt die Quelle wegen Schweigens als `stale` (nicht von der Bridge gemeldet)?
var silent := false

## Letzte gemeldete Kadenz in rpm. Bleibt bei Abbruch stehen – ein Abbruch ist keine
## Kadenz 0 (ADR-0004); ob gefahren wird, entscheidet der Besitzer anhand von `status`.
var cadence := 0.0
## Letzte gemeldete ungeglättete Kadenz in rpm (`cadence_raw`, #45) – nur für die Kadenzmuster; Anzeige und
## Fahrmodell nutzen `cadence` (ADR-0004). Bleibt wie `cadence` bei Abbruch und `null` stehen. Eine ältere Bridge
## ohne das Feld: dann gilt `cadence`.
var cadence_raw := 0.0
## Verbindungsstatus der Quelle laut letzter `status`-Nachricht; ohne Bus-Verbindung `disconnected`.
var status := STATE_DISCONNECTED
## Quelle laut `status`: ble | sim | replay ("" solange unbekannt).
var source := ""
## Capabilities laut `status`, z. B. ["CADENCE"].
var capabilities := PackedStringArray()
## `t_ms` der letzten Telemetrie (-1 = noch keine).
var last_telemetry_t_ms := -1
## Letzte Telemetrie-Nachricht unverändert, wie empfangen (leer = noch keine) – z. B. für die Debug-Anzeige.
var last_telemetry := {}
## Empfangszeit der letzten Telemetrie (`Time.get_ticks_msec()`, -1 = noch keine).
var last_telemetry_received_ms := -1
## Besteht die WebSocket-Verbindung zum Bus?
var bus_connected := false

var _peer: WebSocketPeer = null
var _retry_in_s := 0.0
var _connecting_s := 0.0
var _silent_s := 0.0


func _init(bus_url: String, reconnect_interval_s: float = 2.0, connect_timeout: float = 5.0) -> void:
	url = bus_url
	reconnect_s = reconnect_interval_s
	connect_timeout_s = connect_timeout


static func from_config(config: RideConfig) -> BusClient:
	return BusClient.new(config.bus_url, config.bus_reconnect_s, config.bus_connect_timeout_s)


func has_capability(capability: String) -> bool:
	return capabilities.has(capability)


## Leistung in Watt aus der letzten Telemetrie; NAN, wenn die Quelle keine liefert (`power_w: null`).
func power_w() -> float:
	var value = last_telemetry.get("power_w")
	return float(value) if value is float else NAN


## Ist die Leistung geschätzt? Nur ein ausdrückliches `power_estimated: false` gilt als gemessen (ADR-0004).
func power_estimated() -> bool:
	return last_telemetry.get("power_estimated") != false


## Alter der letzten Telemetrie in Millisekunden (-1 = noch keine).
func telemetry_age_ms() -> int:
	if last_telemetry_received_ms < 0:
		return -1
	return Time.get_ticks_msec() - last_telemetry_received_ms


## Treibt Verbindung, Reconnect und Empfang voran. `delta_s` = vergangene Zeit seit dem letzten Aufruf.
func poll(delta_s: float) -> void:
	if _peer == null:
		_retry_in_s -= delta_s
		if _retry_in_s <= 0.0:
			_open()
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connecting_s += delta_s
			if _connecting_s >= connect_timeout_s:
				push_warning("BusClient: Verbindungsaufbau zu %s nach %.1f s abgebrochen, verbinde neu" % [url, _connecting_s])
				_peer.close()
				_lost()
		WebSocketPeer.STATE_OPEN:
			if not bus_connected:
				bus_connected = true
				bus_connection_changed.emit(true)
			_silent_s += delta_s
			while _peer.get_available_packet_count() > 0:
				_handle(_peer.get_packet().get_string_from_utf8())
			if status == STATE_CONNECTED and _silent_s > silence_timeout_s:
				push_warning("BusClient: seit %.1f s keine Daten vom Bus, behandle Quelle als stale" % _silent_s)
				silent = true
				_set_status(STATE_STALE)
		WebSocketPeer.STATE_CLOSED:
			_lost()


## Sendet eine Nachricht an die Bridge; `v` wird ergänzt. ERR_UNAVAILABLE ohne Bus-Verbindung.
func send_message(message: Dictionary) -> Error:
	if not bus_connected:
		return ERR_UNAVAILABLE
	var out := message.duplicate()
	out["v"] = PROTOCOL_VERSION
	return _peer.send_text(JSON.stringify(out))


## Trennt die Verbindung und hört auf, neu zu verbinden.
func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	_retry_in_s = INF
	_set_bus_connected(false)


func _open() -> void:
	_peer = WebSocketPeer.new()
	_connecting_s = 0.0
	_silent_s = 0.0
	var err := _peer.connect_to_url(url)
	if err != OK:
		push_warning("BusClient: Verbindung zu %s nicht möglich (Fehler %d)" % [url, err])
		_peer = null
		_retry_in_s = reconnect_s


func _lost() -> void:
	_peer = null
	_retry_in_s = reconnect_s
	_set_bus_connected(false)


func _set_bus_connected(connected: bool) -> void:
	if bus_connected != connected:
		bus_connected = connected
		bus_connection_changed.emit(connected)
	if not connected:
		silent = false
		_set_status(STATE_DISCONNECTED)


func _set_status(state: String) -> void:
	if status != state:
		status = state
		status_changed.emit(state)


func _handle(text: String) -> void:
	var message = JSON.parse_string(text)
	if not (message is Dictionary) or message.get("v") != float(PROTOCOL_VERSION):
		push_warning("BusClient: unbekannte Nachricht verworfen: %s" % text)
		return
	match message.get("type"):
		"status":
			_silent_s = 0.0
			silent = false
			var src = message.get("source")
			source = src if src is String else ""
			var caps = message.get("capabilities")
			capabilities = PackedStringArray(caps) if caps is Array else PackedStringArray()
			_set_status(str(message.get("state", STATE_DISCONNECTED)))
		"telemetry":
			_silent_s = 0.0
			if silent:  # Telemetrie gibt es nur bei `connected` (docs/bus-protocol.md)
				silent = false
				_set_status(STATE_CONNECTED)
			var value = message.get("cadence")
			if value is float:
				cadence = value
			var raw = message.get("cadence_raw", value)
			if raw is float:
				cadence_raw = raw
			if message.get("t_ms") is float:
				last_telemetry_t_ms = int(message["t_ms"])
			last_telemetry = message
			last_telemetry_received_ms = Time.get_ticks_msec()
			telemetry_received.emit(message)
		"ack":
			ack_received.emit(message)
		"error":
			push_warning("BusClient: Bridge meldet Fehler %s: %s" % [message.get("reason"), message.get("detail")])
		_:
			pass  # unbekannte Typen ignorieren (Vorwärtskompatibilität)
