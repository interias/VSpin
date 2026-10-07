## Hauptszene der Inselfahrt: verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
## Strecke laut Konfiguration (`[world] track`): Insel-Rundkurs mit Insel-Welt (Standard, #14) oder Graybox.
## Die Kamera folgt dem Fahrer ruhig: Position hinter ihm auf der Strecke, Blick voraus, beides geglättet.
## Fahrer und Rad (`Track/Rider/Model`, RiderModel): Kurbel und Beine drehen mit der Kadenz, Räder rollen mit dem
## Tempo, Schräglage in Kurven, Vorbeuge bergauf; außerhalb von `riding` steht alles still.
## Grafik und Fenster: eigenes Menü (`settings_menu`, F2/F11), hier nur eingehängt.
## HUD (`Hud`, RideHud, Szene `scenes/hud.tscn`): bekommt pro Frame die Werte, Rundenfortschritt und Position.
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
	"ride_settings": [KEY_F2],
	"ride_fullscreen": [KEY_F11],
}
## Menü „Grafik und Fenster“ (F2, F11; siehe `scenes/settings_menu.gd`).
const SETTINGS_MENU := preload("res://scenes/settings_menu.tscn")
## Kamera: Abstand hinter dem Fahrer, Höhe und Blickpunkt voraus aus der Konfiguration (`[camera]`, RideConfig);
## Glättung (Zeitkonstante).
const CAMERA_SMOOTHING_S := 0.45
## Mindesthöhe der Kamera über dem Gelände (Insel).
const CAMERA_TERRAIN_CLEARANCE_M := 1.5

const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"
const RESISTANCE_NOT_SUPPORTED := "Widerstand: nicht unterstützt"

## Konfiguration; wenn vor `_ready` nicht gesetzt, wird `res://config.cfg` geladen.
var config: RideConfig = null
## Startposition auf der Strecke in Metern (Standard: Start/Ziel).
@export var start_distance_m := 0.0
## Beendet das Spiel bei `ride_quit`; Tests schalten das ab und beobachten `quit_requested`.
@export var quit_on_request := true
## Grafik-/Fenstereinstellungen; "" = Standardwerte, nichts speichern, Fenster unberührt (Tests, Probe).
var settings_path := GraphicsSettings.DEFAULT_PATH
var settings_menu: CanvasLayer

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

## Insel-Welt (null bei der Graybox-Strecke).
var world: IslandWorld = null

var _manual_pause := false
var _camera_look := Vector3.ZERO
## Telemetrie seit dem letzten Verbindungsverlust empfangen? Erst dann wird weitergefahren.
var _data_since_loss := false
var _ever_connected := false

@onready var track: Track = $Track
@onready var rider: PathFollow3D = $Track/Rider
@onready var rider_model: RiderModel = $Track/Rider/Model
@onready var hud: RideHud = $Hud
@onready var message_label: Label = $Hud/Message
@onready var hint_label: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug
@onready var camera: Camera3D = $Camera


func _ready() -> void:
	if config == null:
		config = RideConfig.load_file()
	_register_key_bindings()
	settings_menu = SETTINGS_MENU.instantiate()
	settings_menu.settings_path = settings_path
	add_child(settings_menu)
	_setup_track()
	bus = BusClient.from_config(config)
	bus.telemetry_received.connect(_on_telemetry)
	bus.status_changed.connect(_on_status_changed)
	bus.bus_connection_changed.connect(_on_bus_connection_changed)
	bus.ack_received.connect(_on_ack)
	model = RideModel.new(config, start_distance_m)
	var lap := track.length_m()
	finish_distance_m = (floorf(start_distance_m / lap) + 1.0) * lap if lap > 0.0 else INF
	hud.setup(track, world)
	_update_view()
	_update_camera(0.0, true)


func _process(delta: float) -> void:
	bus.poll(delta)
	_update_state()
	if state == STATE_RIDING:
		_ride(delta)
	_report_grade(delta)
	_update_view()
	_update_rider(delta)
	_update_camera(delta)


## Strecke laut Konfiguration: Insel-Rundkurs mit Welt (Gelände, Meer, Stationen) oder Graybox mit Boden.
func _setup_track() -> void:
	if config.track == RideConfig.TRACK_GRAYBOX:
		track.curve = GrayboxTrack.build_curve()
		var ground := MeshInstance3D.new()
		ground.name = "Ground"
		var plane := PlaneMesh.new()
		plane.size = Vector2(600.0, 600.0)
		ground.mesh = plane
		var ground_material := StandardMaterial3D.new()
		ground_material.albedo_color = Color(0.45, 0.55, 0.4)
		ground.material_override = ground_material
		ground.position = Vector3(0.0, -0.05, 143.0)
		add_child(ground)
		var road := MeshInstance3D.new()
		road.name = "Road"
		road.mesh = track.road_mesh(0.02, 16.0)
		var road_material := StandardMaterial3D.new()
		road_material.vertex_color_use_as_albedo = true
		road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		road.material_override = road_material
		track.add_child(road)
		return
	IslandCourse.apply_to(track)
	world = IslandWorld.new()
	world.name = "World"
	add_child(world)
	world.build(track)


## Abschnitt (Station) an der Fahrerposition, "" ohne Stationen (Graybox).
func current_station() -> String:
	return track.station_at(model.distance_m).get("name", "")


## Kamera ruhig hinter dem Fahrer: Zielposition hinter ihm auf der Strecke (folgt Kurven und Kehren, statt
## seitlich auszuschwenken), Blick auf einen Punkt voraus; beides exponentiell geglättet. `snap` springt sofort.
func _update_camera(delta: float, snap: bool = false) -> void:
	var d := model.distance_m
	var up := Vector3.UP
	var target := track.to_global(track.position_at(d - config.camera_behind_m)) + up * config.camera_height_m
	var look := track.to_global(track.position_at(d + config.camera_look_ahead_m)) + up * config.camera_look_height_m
	if world != null:
		target.y = maxf(target.y, world.terrain.height_at(target.x, target.z) + CAMERA_TERRAIN_CLEARANCE_M)
	var follow := 1.0 if snap else 1.0 - exp(-delta / CAMERA_SMOOTHING_S)
	camera.global_position = camera.global_position.lerp(target, follow)
	_camera_look = _camera_look.lerp(look, follow)
	if camera.global_position.distance_to(_camera_look) > 0.01:
		camera.look_at(_camera_look, Vector3.UP)


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


## Krümmung der Strecke an der Position des Fahrers (1/m, positiv = Linkskurve).
func current_curvature() -> float:
	var d := model.distance_m
	return RiderMotion.signed_curvature(track.position_at(d - RiderMotion.CURVE_SAMPLE_M), track.position_at(d),
			track.position_at(d + RiderMotion.CURVE_SAMPLE_M))


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
			return "Pause\nP / Leertaste: weiter · Esc: beenden\nF2: Grafik und Fenster"
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


## Pose von Fahrer und Rad: Kadenz und Tempo wie gefahren, Pause in jedem Zustand außer `riding`.
func _update_rider(delta: float) -> void:
	rider_model.update(bus.cadence, model.speed_mps, current_grade(), current_curvature(), state != STATE_RIDING, delta)


func _update_view() -> void:
	rider.progress = track.wrap_distance(model.distance_m)
	var grade := current_grade()
	hud.show_ride(bus.cadence, model.speed_kmh(), stats.distance_m, format_time(lap_time_s()), grade,
			format_grade(grade), current_station(), format_power(bus.power_w(), bus.power_estimated()))
	hud.show_lap(model.distance_m, start_distance_m, finish_distance_m, rider.progress)
	if debug_label.visible:
		debug_label.text = debug_text()
	hint_label.text = resistance_hint
	var message := status_message()
	message_label.text = message
	message_label.visible = not message.is_empty()
