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
##
## Puls (ADR-0008, docs/bus-protocol.md „Puls“): `heart_rate_state`/`heart_rate_device` aus `status.heart_rate`, der Wert
## `heart_rate_bpm` aus `telemetry.heart_rate`. Anders als die Kadenz bleibt der Wert nicht stehen: ohne laufende
## Telemetrie (Bus weg, Quelle `stale`/`disconnected`, Schweigen) ist er NAN – ein alter Puls wäre eine falsche Angabe.
## Die gemerkten Geräte gehören dem Spiel: `set_heart_rate_devices` schickt sie sofort und nach jedem (Neu-)Verbinden
## erneut, auch eine leere Liste (eine frisch gestartete Bridge kennt keine Geräte, eine geteilte die eines anderen).
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
## Pulszustand oder -gerät hat sich geändert (`status.heart_rate`, auch wenn die Verbindung zum Bus abbricht).
signal heart_rate_changed(state: String)
## Suchergebnis (`heart_rate_found`) nach `start_heart_rate_search`; `device_name` ist "" ohne Namen.
signal heart_rate_found(address: String, device_name: String, rssi: int)
## Die Suche endete ohne eigenes `stop` (`heart_rate_search_ended`); `reason`: timeout | taken_over.
signal heart_rate_search_ended(reason: String)

const PROTOCOL_VERSION := 0
const STATE_CONNECTED := "connected"
const STATE_STALE := "stale"
const STATE_DISCONNECTED := "disconnected"
## Schweigen bei `connected`, ab dem das Spiel selbst `stale` annimmt (Sekunden). Die Bridge meldet `stale` per
## Timer genau 3 s nach dem letzten Sample (ADR-0004); 1 s Reserve, damit ihr `stale` bei laufender Bridge immer
## zuerst ankommt und nur eine hängende Bridge hier greift.
const SILENCE_TIMEOUT_S := 4.0
## Pulszustände laut `status.heart_rate.state`.
const HEART_RATE_OFF := "off"
const HEART_RATE_DISCONNECTED := "disconnected"
const HEART_RATE_CONNECTED := "connected"
const HEART_RATE_STALE := "stale"

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
## Pulszustand laut `status.heart_rate`: off | disconnected | connected | stale. Eine ältere Bridge ohne den Block und
## ein Abbruch des Busses ergeben `off`.
var heart_rate_state := HEART_RATE_OFF
## Verbundenes Pulsgerät ({address, name, role}) bei `connected`/`stale`, sonst leer.
var heart_rate_device := {}
## Aktueller Puls in bpm; NAN = kein Wert (`null` in der Telemetrie, keine Telemetrie). Auch ohne Pulsgerät kann ein
## Wert da sein: Rad oder Simulator liefern dann ihren eigenen.
var heart_rate_bpm := NAN

var _peer: WebSocketPeer = null
var _retry_in_s := 0.0
var _connecting_s := 0.0
var _silent_s := 0.0
## Zuletzt gesetzte Geräteliste (null = noch nie gesetzt: dann schickt der Client beim Verbinden nichts).
var _heart_rate_devices = null


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


## Gibt es einen aktuellen Pulswert?
func has_heart_rate() -> bool:
	return not is_nan(heart_rate_bpm)


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
				_send_heart_rate_devices()
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


## Setzt die gemerkten Pulsgeräte der Bridge: `devices` = [{address, name, role}] in Vorrang-Reihenfolge, `[]` schaltet
## den Puls aus. Geht sofort raus, wenn der Bus verbunden ist, und danach nach jedem (Neu-)Verbinden erneut.
func set_heart_rate_devices(devices: Array) -> Error:
	_heart_rate_devices = devices.duplicate(true)
	return _send_heart_rate_devices()


## Startet die Suche nach Pulsgeräten (Ergebnisse als `heart_rate_found`); ohne `duration_s` gilt die Dauer der Bridge.
func start_heart_rate_search(duration_s: float = 0.0) -> Error:
	var message := {"type": "start_heart_rate_search"}
	if duration_s > 0.0:
		message["duration_s"] = duration_s
	return send_message(message)


## Beendet die eigene Suche (danach kommt kein `heart_rate_search_ended`).
func stop_heart_rate_search() -> Error:
	return send_message({"type": "stop_heart_rate_search"})


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


func _send_heart_rate_devices() -> Error:
	if _heart_rate_devices == null:
		return OK
	return send_message({"type": "set_heart_rate_devices", "devices": _heart_rate_devices})


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
		_set_heart_rate(HEART_RATE_OFF, {})  # ohne Bus weiß das Spiel nichts über den Puls


func _set_status(state: String) -> void:
	if status != state:
		status = state
		status_changed.emit(state)
	if state != STATE_CONNECTED:
		heart_rate_bpm = NAN  # Telemetrie gibt es nur bei `connected`: ein alter Puls bliebe sonst stehen


func _set_heart_rate(state: String, device: Dictionary) -> void:
	if heart_rate_state != state or heart_rate_device != device:
		heart_rate_state = state
		heart_rate_device = device
		heart_rate_changed.emit(state)


## `status.heart_rate` übernehmen; fehlt der Block (ältere Bridge) oder ist er kaputt, gilt `off`.
func _read_heart_rate_status(block) -> void:
	var state := HEART_RATE_OFF
	var device := {}
	if block is Dictionary:
		var reported = block.get("state")
		if reported in [HEART_RATE_DISCONNECTED, HEART_RATE_CONNECTED, HEART_RATE_STALE]:
			state = reported
		var info = block.get("device")
		if info is Dictionary and state in [HEART_RATE_CONNECTED, HEART_RATE_STALE]:
			device = {"address": str(info.get("address", "")), "name": str(info.get("name", "")),
					"role": str(info.get("role", ""))}
	_set_heart_rate(state, device)


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
			_read_heart_rate_status(message.get("heart_rate"))
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
			var bpm = message.get("heart_rate")
			heart_rate_bpm = float(bpm) if (bpm is float or bpm is int) and bpm > 0 else NAN
			if message.get("t_ms") is float:
				last_telemetry_t_ms = int(message["t_ms"])
			last_telemetry = message
			last_telemetry_received_ms = Time.get_ticks_msec()
			telemetry_received.emit(message)
		"ack":
			ack_received.emit(message)
		"heart_rate_found":
			var found_name = message.get("name")
			var rssi = message.get("rssi")
			heart_rate_found.emit(str(message.get("address", "")), found_name if found_name is String else "",
					int(rssi) if rssi is float or rssi is int else 0)
		"heart_rate_search_ended":
			heart_rate_search_ended.emit(str(message.get("reason", "")))
		"error":
			push_warning("BusClient: Bridge meldet Fehler %s: %s" % [message.get("reason"), message.get("detail")])
		_:
			pass  # unbekannte Typen ignorieren (Vorwärtskompatibilität)
