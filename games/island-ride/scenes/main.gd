## Hauptszene der Inselfahrt (Graybox): verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
##
## Spielzustände (`state`):
##   riding             fahren – Bus verbunden, Quelle `connected` und Daten seit dem letzten Abbruch
##   paused_manual      pausiert per Taste (P/Leertaste), bis erneut gedrückt
##   paused_connection  pausiert wegen Verbindung: Bridge nicht erreichbar, Quelle `stale`/`disconnected`
##                      oder noch keine Daten. Ein Abbruch ist keine Kadenz 0 (ADR-0004): das Fahrmodell
##                      steht still und fährt automatisch weiter, sobald wieder Daten kommen.
##   finished           Ziel erreicht – Zusammenfassung (Zeit, Ø Kadenz, Ø Tempo); Endzustand
## Verbindungspause hat Vorrang vor der manuellen; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen.
##
## Virtuelle Steigung (ADR-0007): das Spiel meldet die Steigung an der Fahrerposition per `set_grade`
## (Drosselung siehe GradeReporter), nicht in der Verbindungspause; danach wird sie neu gemeldet.
##
## Runde: Start an `start_distance_m`, Ziel beim nächsten Überfahren der Start/Ziel-Linie (Streckenposition 0,
## also nach einer vollen Runde, wenn bei 0 gestartet wird). Fahrzeit und Durchschnitte (RideStats) zählen
## nur Zeit im Zustand `riding` – Pausen nicht.
extends Node3D

## Neuer Spielzustand (siehe STATE_*).
signal state_changed(state: String)
## Beenden per Taste angefordert (vor dem Beenden, siehe `quit_on_request`).
signal quit_requested

const STATE_RIDING := "riding"
const STATE_PAUSED_MANUAL := "paused_manual"
const STATE_PAUSED_CONNECTION := "paused_connection"
const STATE_FINISHED := "finished"

## Tastenbelegung: Aktion → Tasten (physische Tastenposition, unabhängig vom Layout).
const KEY_BINDINGS := {
	"ride_pause": [KEY_P, KEY_SPACE],
	"ride_quit": [KEY_ESCAPE],
	"ride_debug": [KEY_F3],
}
const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"
const RESISTANCE_NOT_SUPPORTED := "Widerstand: nicht unterstützt"

## Konfiguration; wenn vor `_ready` nicht gesetzt, wird `res://config.cfg` geladen.
var config: RideConfig = null
## Startposition auf der Strecke in Metern (Standard: Start/Ziel).
@export var start_distance_m := 0.0
## Beendet das Spiel bei `ride_quit`; Tests schalten das ab und beobachten `quit_requested`.
@export var quit_on_request := true

var bus: BusClient
var model: RideModel
## Aktueller Spielzustand (STATE_*).
var state := STATE_PAUSED_CONNECTION
## Hinweis aus der letzten `ack` auf `set_grade` ("" = umgesetzt oder noch keine Antwort).
var resistance_hint := ""
var grade_reporter := GradeReporter.new()
## Fahrzeit, Strecke und Durchschnitte der laufenden Runde (ohne Pausen).
var stats := RideStats.new()
## Streckenposition (wie `model.distance_m`) der Ziellinie.
var finish_distance_m := 0.0

var _manual_pause := false
## Telemetrie seit dem letzten Verbindungsverlust empfangen? Erst dann wird weitergefahren.
var _data_since_loss := false
var _ever_connected := false

@onready var track: Track = $Track
@onready var rider: PathFollow3D = $Track/Rider
@onready var hud_label: Label = $Hud/Label
@onready var message_label: Label = $Hud/Message
@onready var hint_label: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug


func _ready() -> void:
	if config == null:
		config = RideConfig.load_file()
	_register_key_bindings()
	bus = BusClient.from_config(config)
	bus.telemetry_received.connect(_on_telemetry)
	bus.status_changed.connect(_on_status_changed)
	bus.bus_connection_changed.connect(_on_bus_connection_changed)
	bus.ack_received.connect(_on_ack)
	model = RideModel.new(config, start_distance_m)
	var lap := track.length_m()
	finish_distance_m = (floorf(start_distance_m / lap) + 1.0) * lap if lap > 0.0 else INF
	_update_view()


func _process(delta: float) -> void:
	bus.poll(delta)
	_update_state()
	if state == STATE_RIDING:
		_ride(delta)
	_report_grade(delta)
	_update_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ride_debug"):
		debug_label.visible = not debug_label.visible
		_update_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_pause"):
		if state != STATE_FINISHED:
			_manual_pause = not _manual_pause
		_update_state()
		_update_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_quit"):
		get_viewport().set_input_as_handled()
		quit_requested.emit()
		if quit_on_request:
			get_tree().quit()


func _exit_tree() -> void:
	if bus != null:
		bus.close()


## Fahrzeit der laufenden Runde in Sekunden (ohne Pausen); nach dem Ziel die Rundenzeit.
func lap_time_s() -> float:
	return stats.ride_time_s


## Aktuelle Steigung an der Position des Fahrers (Anteil).
func current_grade() -> float:
	return track.grade_at(model.distance_m)


## Steigung (Anteil) für die Anzeige, z. B. 0.06 → "+6.0 %", flach → "0.0 %".
static func format_grade(grade: float) -> String:
	var percent := snappedf(grade * 100.0, 0.1)
	if is_zero_approx(percent):
		return "0.0 %"
	return "%+.1f %%" % percent


## Zeit für die Anzeige: "m:ss", mit `tenths` "m:ss.z".
static func format_time(seconds: float, tenths: bool = false) -> String:
	if tenths:
		var t := snappedf(maxf(seconds, 0.0), 0.1)
		return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]
	var whole := int(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


## Leistung für die Anzeige: geschätzt immer mit „~“ (ADR-0004), z. B. "~142 W"; "" ohne Wert.
static func format_power(watts: float, estimated: bool) -> String:
	if is_nan(watts):
		return ""
	return "%s%d W" % ["~" if estimated else "", roundi(watts)]


## Hinweistext zum Zustand (leer beim Fahren), wie er groß im HUD steht.
func status_message() -> String:
	match state:
		STATE_FINISHED:
			return "Ziel erreicht!\nZeit: %s\nØ Kadenz: %d rpm\nØ Tempo: %.1f km/h\nEsc: beenden" % [
					format_time(lap_time_s(), true), roundi(stats.avg_cadence()), stats.avg_speed_kmh()]
		STATE_PAUSED_MANUAL:
			return "Pause\nP / Leertaste: weiter · Esc: beenden"
		STATE_PAUSED_CONNECTION:
			var text: String
			if not bus.bus_connected:
				text = "%sBridge nicht erreichbar (%s)\n%s\nNeuer Versuch läuft …" % [
						"Verbindung verloren: " if _ever_connected else "", bus.url, BRIDGE_START_HINT]
			elif bus.status != BusClient.STATE_CONNECTED:
				text = "Verbindung verloren (Rad: %s)\nWarte auf Daten …" % bus.status
			else:
				text = "Verbunden – warte auf Daten …"
			if _manual_pause:
				text += "\n(manuell pausiert)"
			return text
	return ""


func _update_state() -> void:
	if bus.bus_connected:
		_ever_connected = true
	if state == STATE_FINISHED:
		return
	var connection_ok := bus.bus_connected and bus.status == BusClient.STATE_CONNECTED and _data_since_loss
	var next := STATE_RIDING
	if not connection_ok:
		next = STATE_PAUSED_CONNECTION
	elif _manual_pause:
		next = STATE_PAUSED_MANUAL
	if next != state:
		state = next
		if state == STATE_PAUSED_CONNECTION:
			grade_reporter.reset()  # nach der Rückkehr Steigung neu melden
		state_changed.emit(state)


## Ein Zeitschritt Fahrt: Fahrmodell, Statistik und Ziel. Den Schritt über die Ziellinie zählt die
## Statistik nur anteilig bis zur Linie, damit Rundenzeit und Durchschnitte genau sind.
func _ride(delta: float) -> void:
	var before := model.distance_m
	model.step(bus.cadence, current_grade(), delta)
	var moved := model.distance_m - before
	if model.distance_m < finish_distance_m:
		stats.add(delta, bus.cadence, moved)
		return
	var fraction := (finish_distance_m - before) / moved if moved > 0.0 else 1.0
	stats.add(delta * fraction, bus.cadence, finish_distance_m - before)
	model.distance_m = finish_distance_m
	state = STATE_FINISHED
	state_changed.emit(state)


## Meldet die Steigung per `set_grade`, wenn sie sich genug geändert hat (gedrosselt, siehe GradeReporter).
## In der Verbindungspause nicht – Senden wäre sinnlos.
func _report_grade(delta: float) -> void:
	grade_reporter.tick(delta)
	if state == STATE_PAUSED_CONNECTION:
		return
	var grade := GradeReporter.quantize(current_grade())
	if grade_reporter.wants_to_send(grade) and bus.send_message({"type": "set_grade", "grade": grade}) == OK:
		grade_reporter.sent(grade)


func _on_ack(message: Dictionary) -> void:
	if message.get("for") != "set_grade":
		return
	if message.get("ok") == true:
		resistance_hint = ""
	elif message.get("reason") == "not_supported":
		resistance_hint = RESISTANCE_NOT_SUPPORTED
	else:
		resistance_hint = "Widerstand: Fehler (%s)" % message.get("reason")


func _on_telemetry(_message: Dictionary) -> void:
	_data_since_loss = true


func _on_status_changed(new_state: String) -> void:
	if new_state != BusClient.STATE_CONNECTED:
		_data_since_loss = false


func _on_bus_connection_changed(connected: bool) -> void:
	if not connected:
		_data_since_loss = false


## Inhalt der Debug-Anzeige (F3): Kadenz-Rohwert wie empfangen, Bridge-Zeitstempel und Alter der
## letzten Telemetrie – zur Prüfung der Latenz (< 200 ms, ADR-0005).
func debug_text() -> String:
	var raw = bus.last_telemetry.get("cadence")
	var age := bus.telemetry_age_ms()
	return "DEBUG\nKadenz roh: %s\nt_ms: %s\nAlter: %s\nBus: %s · Quelle: %s (%s)" % [
			"–" if raw == null else str(raw),
			"–" if bus.last_telemetry_t_ms < 0 else str(bus.last_telemetry_t_ms),
			"–" if age < 0 else "%d ms" % age,
			"verbunden" if bus.bus_connected else "getrennt", bus.status,
			bus.source if not bus.source.is_empty() else "?"]


func _register_key_bindings() -> void:
	for action in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _update_view() -> void:
	rider.progress = track.wrap_distance(model.distance_m)
	var lines := [
		"Kadenz: %d rpm" % roundi(bus.cadence),
		"Tempo: %.1f km/h" % model.speed_kmh(),
		"Strecke: %.2f km" % (stats.distance_m / 1000.0),
		"Zeit: %s" % format_time(lap_time_s()),
		"Steigung: %s" % format_grade(current_grade()),
	]
	var power := format_power(bus.power_w(), bus.power_estimated())
	if not power.is_empty():
		lines.append("Leistung: %s" % power)
	hud_label.text = "\n".join(lines)
	if debug_label.visible:
		debug_label.text = debug_text()
	hint_label.text = resistance_hint
	var message := status_message()
	message_label.text = message
	message_label.visible = not message.is_empty()
