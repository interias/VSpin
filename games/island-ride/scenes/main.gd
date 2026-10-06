## Hauptszene der Inselfahrt (Graybox): verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
##
## Spielzustände (`state`):
##   riding             fahren – Bus verbunden, Quelle `connected` und Daten seit dem letzten Abbruch
##   paused_manual      pausiert per Taste (P/Leertaste), bis erneut gedrückt
##   paused_connection  pausiert wegen Verbindung: Bridge nicht erreichbar, Quelle `stale`/`disconnected`
##                      oder noch keine Daten. Ein Abbruch ist keine Kadenz 0 (ADR-0004): das Fahrmodell
##                      steht still und fährt automatisch weiter, sobald wieder Daten kommen.
## Verbindungspause hat Vorrang vor der manuellen; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen.
extends Node3D

## Neuer Spielzustand (siehe STATE_*).
signal state_changed(state: String)
## Beenden per Taste angefordert (vor dem Beenden, siehe `quit_on_request`).
signal quit_requested

const STATE_RIDING := "riding"
const STATE_PAUSED_MANUAL := "paused_manual"
const STATE_PAUSED_CONNECTION := "paused_connection"

## Tastenbelegung: Aktion → Tasten (physische Tastenposition, unabhängig vom Layout).
const KEY_BINDINGS := {
	"ride_pause": [KEY_P, KEY_SPACE],
	"ride_quit": [KEY_ESCAPE],
}
const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"

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

var _manual_pause := false
## Telemetrie seit dem letzten Verbindungsverlust empfangen? Erst dann wird weitergefahren.
var _data_since_loss := false
var _ever_connected := false

@onready var track: Track = $Track
@onready var rider: PathFollow3D = $Track/Rider
@onready var hud_label: Label = $Hud/Label
@onready var message_label: Label = $Hud/Message


func _ready() -> void:
	if config == null:
		config = RideConfig.load_file()
	_register_key_bindings()
	bus = BusClient.from_config(config)
	bus.telemetry_received.connect(_on_telemetry)
	bus.status_changed.connect(_on_status_changed)
	bus.bus_connection_changed.connect(_on_bus_connection_changed)
	model = RideModel.new(config, start_distance_m)
	_update_view()


func _process(delta: float) -> void:
	bus.poll(delta)
	_update_state()
	if state == STATE_RIDING:
		model.step(bus.cadence, current_grade(), delta)
	_update_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ride_pause"):
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


## Aktuelle Steigung an der Position des Fahrers (Anteil).
func current_grade() -> float:
	return track.grade_at(model.distance_m)


## Hinweistext zum Zustand (leer beim Fahren), wie er groß im HUD steht.
func status_message() -> String:
	match state:
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
	var connection_ok := bus.bus_connected and bus.status == BusClient.STATE_CONNECTED and _data_since_loss
	var next := STATE_RIDING
	if not connection_ok:
		next = STATE_PAUSED_CONNECTION
	elif _manual_pause:
		next = STATE_PAUSED_MANUAL
	if next != state:
		state = next
		state_changed.emit(state)


func _on_telemetry(_message: Dictionary) -> void:
	_data_since_loss = true


func _on_status_changed(new_state: String) -> void:
	if new_state != BusClient.STATE_CONNECTED:
		_data_since_loss = false


func _on_bus_connection_changed(connected: bool) -> void:
	if not connected:
		_data_since_loss = false


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
	hud_label.text = "Kadenz: %d rpm\nTempo: %.1f km/h" % [roundi(bus.cadence), model.speed_kmh()]
	var message := status_message()
	message_label.text = message
	message_label.visible = not message.is_empty()
