## Hauptszene der Inselfahrt: verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
## Strecke laut Konfiguration (`[world] track`): Insel-Rundkurs mit Insel-Welt (Standard, #14) oder Graybox.
## Die Kamera folgt dem Fahrer ruhig: Position hinter ihm auf der Strecke, Blick voraus, beides geglättet.
## Fahrer und Rad (`Track/Rider/Model`, RiderModel): Kurbel und Beine drehen mit der Kadenz, Räder rollen mit dem
## Tempo, Schräglage in Kurven, Vorbeuge bergauf; außerhalb von `riding` steht alles still.
## Grafik und Fenster: eigenes Menü (`settings_menu`, Esc/F2, F11), hier nur eingehängt; dort auch „Beenden“.
## HUD (`Hud`, RideHud, Szene `scenes/hud.tscn`): bekommt pro Frame die Werte, Rundenfortschritt und Position.
##
## Szenenfluss (#30): Titel → Modus-Auswahl → Fahrt → Ergebnis → Menü. Nach dem Start (`start_in_menu`) steht das
## Startmenü (`scenes/start_menu.gd`) über einem langsamen Kameraflug über die lebende Insel (Licht, Wetter, Bewegung
## wie in der Fahrt; HUD und Fahrer ausgeblendet), unten der Radstatus. „Fahren → Rundfahrt“ zeigt Rundenzahl,
## Tageszeit (dasselbe Feld wie im Einstellungsmenü) und Bestzeit, „Losfahren“ startet die Fahrt (`start_ride`); zurück
## ins Menü geht es im Ziel mit Enter oder jederzeit über „Fahrt beenden“ in den Einstellungen (`return_to_menu`). Die
## beendete Fahrt landet als Zusammenfassung im Spielstand (SaveGame, `user://savegame.json`).
##
## Spielzustände (`state`):
##   riding             fahren – Bus verbunden, Quelle `connected` und Daten seit dem letzten Abbruch
##   paused_manual      pausiert per Taste (P/Leertaste), bis erneut gedrückt
##   paused_connection  pausiert wegen Verbindung: Bridge nicht erreichbar, Quelle `stale`/`disconnected`
##                      oder noch keine Daten; auch wenn die Bridge bei offenem Bus schweigt (BusClient.silent).
##                      Ein Abbruch ist keine Kadenz 0 (ADR-0004): das Fahrmodell
##                      steht still und fährt automatisch weiter, sobald wieder Daten kommen.
##   finished           Ziel erreicht – Ergebnis (Zeit, alle Rundenzeiten, Bestzeit, Ø Kadenz, Ø Tempo); Endzustand
##                      der Fahrt. Auch „Fahrt beenden“ nach mindestens einer vollen Runde (z. B. endlos) zeigt erst
##                      das Ergebnis der gefahrenen Runden.
##   menu               Startmenü mit Kameraflug, keine Fahrt (kein Fahrmodell, kein `set_grade`)
## Verbindungspause hat Vorrang vor der manuellen; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen.
##
## Virtuelle Steigung (ADR-0007): das Spiel meldet die Steigung an der Fahrerposition per `set_grade`
## (Drosselung siehe GradeReporter), nicht in der Verbindungspause; danach wird sie neu gemeldet.
##
## Runden (#31): Start an `start_distance_m`, jede Runde endet beim Überfahren der Start/Ziel-Linie (Streckenposition
## = Vielfaches der Rundenlänge), das Ziel nach `laps` Runden (0 = endlos). Rundenzeiten und Bestzeit führt die
## Rundenwertung (LapTiming) allein aus Streckenposition und Fahrzeit – also nur aus Kadenz und Steigung (ADR-0010).
## Die Bestzeit gilt je Strecke und Richtung (vorerst nur im Uhrzeigersinn) und steht im Spielstand; eine neue
## Bestzeit blendet das HUD kurz ein. Fahrzeit und Durchschnitte (RideStats) zählen nur Zeit im Zustand `riding` –
## Pausen nicht.
##
## Segmente und Medaillen (#33): Die Strecke trägt ihre Segmente als Daten (Track.segments); die Rundenwertung misst sie
## mit (SegmentTiming). Im Segment zeigt das HUD dessen Live-Zeit, beim Verlassen blendet es Zeit, Medaille und ggf.
## „neue Bestzeit“ ein. Runden und Segmente bekommen Medaillen nach Schwellen, die Medals aus dem Fahrmodell berechnet
## (`medal_limits`); das Ergebnis zeigt sie je Runde und je Segment. Segment-Bestzeiten und beste Medaillen gehen am
## Fahrtende in den Spielstand, wie die Bestzeit.
##
## Ghost (#32): Auf der Seite „Rundfahrt“ zuschaltbar – Bestzeit-Runde (Standard, sobald es sie gibt) oder letzte Fahrt
## (die letzte volle Runde der zuletzt gespeicherten Fahrt mit mindestens einer vollen Runde). Er fährt jede Runde ab
## ihrem Start neu mit, halbtransparent (`Track/Ghost`, RiderModel als Ghost) und seitlich versetzt; das HUD zeigt den
## Abstand in Sekunden (positiv = hinter dem Ghost). Er wirkt nicht auf die eigene Fahrt. Die Rundenwertung schneidet
## jede volle Runde mit; am Fahrtende gehen Bestzeit-Runde (nur bei neuer Bestzeit) und letzte Runde in den Spielstand.
##
## Erfolge und Fahrerlevel (#35): Die Fahrt meldet Ereignisse an die Erfolge (Achievements) – je volle Runde `lap`, je
## voller Kilometer (gesamt über alle Fahrten) `distance`, `weather` und `time_of_day`. Ein neuer Erfolg und ein
## Levelaufstieg (DriverLevel, aus den Gesamt-Kilometern) blenden im HUD ein, nacheinander mit Bestzeit und Segment.
## Am Fahrtende werden Strecke und Runden gesamt noch einmal geprüft (ein älterer Spielstand zieht so nach); das Ergebnis
## nennt die neuen Erfolge und das neue Level. Das Level schaltet nur Kosmetik frei (ADR-0010) und wirkt nicht auf die
## Fahrt. Das Fahrtenbuch (`scenes/logbook.gd`) öffnet aus dem Startmenü.
##
## Training (#37): „Fahren → Training“ startet eine Einheit (Training, aus `res://trainings`) als eigenen Modus
## (SaveGame.MODE_TRAINING). Die Insel läuft endlos (Rundenwertung mit 0 Runden); das HUD zeigt Phase, Zielkadenz,
## Restzeit und nächste Phase, dazu rechtzeitig die Ansage zum Widerstandsknopf. Die Einheit wertet nur die Kadenz
## (ADR-0010). Nach dem Ausrollen endet die Fahrt mit der Bewertung je Phase und gesamt; „Fahrt beenden“ vorher zeigt die
## Teilbewertung der gefahrenen Phasen. Runden im Training zählen nicht für Bestzeit, Medaillen, Segmente und Ghost –
## die Vorgabe wechselt, die Runden wären nicht vergleichbar. Ein zu Ende gefahrenes Training meldet `training_finished`
## an die Erfolge; Name und Gesamtbewertung der Einheit stehen im Fahrteintrag.
extends Node3D

## Neuer Spielzustand (siehe STATE_*).
signal state_changed(state: String)
## Beenden angefordert – Knopf „Beenden“ im Menü (vor dem Beenden, siehe `quit_on_request`).
signal quit_requested

const STATE_RIDING := "riding"
const STATE_PAUSED_MANUAL := "paused_manual"
const STATE_PAUSED_CONNECTION := "paused_connection"
const STATE_FINISHED := "finished"
const STATE_MENU := "menu"

## Tastenbelegung: Aktion → Tasten (physische Tastenposition, unabhängig vom Layout).
const KEY_BINDINGS := {
	"ride_pause": [KEY_P, KEY_SPACE],
	"ride_debug": [KEY_F3],
	"ride_settings": [KEY_ESCAPE, KEY_F2],
	"ride_fullscreen": [KEY_F11],
	"ride_menu": [KEY_ENTER, KEY_KP_ENTER],
}
## Menü „Grafik und Fenster“ (Esc/F2, F11, Beenden; siehe `scenes/settings_menu.gd`).
const SETTINGS_MENU := preload("res://scenes/settings_menu.tscn")
## Startmenü (Titel, Menüpunkte, Radstatus).
const START_MENU := preload("res://scenes/start_menu.tscn")
## Fahrtenbuch (Statistik, Bestzeiten, Erfolge, letzte Fahrten; #35).
const LOGBOOK := preload("res://scenes/logbook.gd")
## Kamera: Abstand hinter dem Fahrer, Höhe und Blickpunkt voraus aus der Konfiguration (`[camera]`, RideConfig);
## Glättung (Zeitkonstante).
const CAMERA_SMOOTHING_S := 0.45
## Mindesthöhe der Kamera über dem Gelände (Insel).
const CAMERA_TERRAIN_CLEARANCE_M := 1.5
## Titelbild: Kameraflug entlang des Rundkurses – Tempo, Höhe über der Straße, Blickpunkt voraus, Mindesthöhe über
## dem Gelände und Glättung (ruhig auch in den Kehren).
const TITLE_FLIGHT_MPS := 9.0
const TITLE_FLIGHT_HEIGHT_M := 38.0
const TITLE_LOOK_AHEAD_M := 170.0
const TITLE_TERRAIN_CLEARANCE_M := 22.0
const TITLE_SMOOTHING_S := 2.5
## Ghost: seitlicher Versatz zum Fahrer auf der Straße (m, nach links), damit beide nebeneinander fahren.
const GHOST_OFFSET_M := -1.3

const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"
const RESISTANCE_NOT_SUPPORTED := "Widerstand: nicht unterstützt"

## Konfiguration; wenn vor `_ready` nicht gesetzt, wird `res://config.cfg` geladen.
var config: RideConfig = null
## Startposition auf der Strecke in Metern (Standard: Start/Ziel).
@export var start_distance_m := 0.0
## Beendet das Spiel bei „Beenden“ im Menü; Tests schalten das ab und beobachten `quit_requested`.
@export var quit_on_request := true
## Nach dem Start erst das Startmenü zeigen (Spiel); Tests und Prüfhilfen fahren sofort los.
@export var start_in_menu := true
## Grafik-/Fenstereinstellungen; "" = Standardwerte, nichts speichern, Fenster unberührt (Tests, Probe).
var settings_path := GraphicsSettings.DEFAULT_PATH
var settings_menu: CanvasLayer
var start_menu: CanvasLayer
var logbook: CanvasLayer
## Spielstand; "" = nicht laden/speichern, Fahrten nur im Speicher (Tests, Probe).
var save_path := SaveGame.DEFAULT_PATH
var save_game: SaveGame
## Spielmodus der laufenden Fahrt (SaveGame.MODE_*).
var ride_mode := SaveGame.MODE_ROUND_TRIP
## Rundenzahl der laufenden Fahrt; 0 = endlos.
var laps := 1
## Rundenwertung der laufenden Fahrt (Rundenzeiten, Bestzeit, Segmentzeiten).
var lap_timing: LapTiming
## Medaillen-Schwellen der Strecke aus dem Fahrmodell (Medals.thresholds): {Medals.LAP: {…}, "<segment-id>": {…}}.
var medal_limits: Dictionary = {}
## Ghost der laufenden Fahrt (null = aus); seine Runde beginnt mit jeder Runde der Fahrt neu.
var ghost: Ghost = null
## In dieser Fahrt neu freigeschaltete Erfolge (Einträge aus Achievements.LIST) und das Fahrerlevel jetzt.
var ride_achievements: Array = []
var ride_level := 1
## Trainingseinheit der laufenden Fahrt (null = kein Training).
var training: Training = null
## Mitfahrer des Ghosts auf der Strecke und sein halbtransparentes Fahrermodell.
var ghost_rider: PathFollow3D
var ghost_model: RiderModel

var bus: BusClient
var model: RideModel
## Aktueller Spielzustand (STATE_*).
var state := STATE_PAUSED_CONNECTION
## Hinweis aus der letzten `ack` auf `set_grade` ("" = umgesetzt oder noch keine Antwort).
var resistance_hint := ""
var grade_reporter := GradeReporter.new()
## Fahrzeit, Strecke und Durchschnitte der laufenden Fahrt (ohne Pausen).
var stats := RideStats.new()
## Streckenposition (wie `model.distance_m`) der Ziellinie nach der letzten Runde (INF = endlos).
var finish_distance_m := 0.0

## Insel-Welt (null bei der Graybox-Strecke).
var world: IslandWorld = null
## Tag/Nacht und Wetter (G6), Kind `Sky`.
var sky: SkyController = null

var _manual_pause := false
var _camera_look := Vector3.ZERO
## Telemetrie seit dem letzten Verbindungsverlust empfangen? Erst dann wird weitergefahren.
var _data_since_loss := false
var _ever_connected := false
## Laufende Fahrt schon im Spielstand?
var _ride_saved := false
## Streckenposition des Kameraflugs im Titelbild.
var _flight_m := 0.0
## Vor der Fahrt: Kilometer und volle Runden gesamt, Fahrerlevel; nächster voller Kilometer (gesamt) für die Ereignisse.
var _km_before := 0.0
var _laps_before := 0
var _level_before := 1
var _next_km := 1.0

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
	settings_menu.quit_requested.connect(_on_quit_requested)
	settings_menu.ride_end_requested.connect(return_to_menu)
	add_child(settings_menu)
	save_game = SaveGame.load_file(save_path) if not save_path.is_empty() else SaveGame.new()
	start_menu = START_MENU.instantiate()
	start_menu.ride_requested.connect(_on_ride_requested)
	start_menu.settings_requested.connect(settings_menu.open)
	start_menu.quit_requested.connect(_on_quit_requested)
	start_menu.logbook_requested.connect(open_logbook)
	add_child(start_menu)
	logbook = LOGBOOK.new()
	logbook.name = "Logbook"
	logbook.closed.connect(_on_logbook_closed)
	add_child(logbook)
	settings_menu.visibility_changed.connect(_on_settings_visibility_changed)
	_setup_track()
	_setup_ghost_rider()
	sky = SkyController.new()
	add_child(sky)
	sky.setup(self)
	_setup_sky_settings()
	bus = BusClient.from_config(config)
	bus.telemetry_received.connect(_on_telemetry)
	bus.status_changed.connect(_on_status_changed)
	bus.bus_connection_changed.connect(_on_bus_connection_changed)
	bus.ack_received.connect(_on_ack)
	model = RideModel.new(config, start_distance_m)
	_new_lap_timing()
	_reset_progress()
	hud.setup(track, world)
	_update_view()
	_update_camera(0.0, true)
	if start_in_menu:
		_enter_menu()
	else:
		start_menu.close()
		settings_menu.set_ride_active(true)


func _process(delta: float) -> void:
	bus.poll(delta)
	_update_state()
	if state == STATE_MENU:
		_fly_title(delta)
		start_menu.show_wheel_status(bus)
		return
	if state == STATE_RIDING:
		_ride(delta)
	_report_grade(delta)
	_update_view()
	_update_rider(delta)
	_update_camera(delta)


## Tageszeit/Wetter aus dem Menü: gespeicherte Werte (`settings.cfg [sky]`) über `config.cfg` legen, sonst den
## Stand aus `config.cfg` im Menü anzeigen; danach wirkt jede Auswahl sofort.
func _setup_sky_settings() -> void:
	var settings: GraphicsSettings = settings_menu.settings
	if settings.sky_saved:
		settings.apply_sky(sky)
	else:
		settings.capture_sky(sky)
	settings_menu.settings_changed.connect(_on_settings_changed)


func _on_settings_changed(key: String) -> void:
	if key in ["time", "weather"]:
		settings_menu.settings.apply_sky(sky)
	if key == "time" and state == STATE_MENU:
		_update_round_trip_menu()


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


## Mitfahrer für den Ghost neben dem Fahrer: eigene Kopie des Fahrermodells, halbtransparent; ausgeblendet ohne Ghost.
func _setup_ghost_rider() -> void:
	ghost_rider = PathFollow3D.new()
	ghost_rider.name = "Ghost"
	ghost_rider.loop = true
	ghost_rider.h_offset = GHOST_OFFSET_M
	ghost_rider.visible = false
	track.add_child(ghost_rider)
	ghost_model = RiderModel.new()
	ghost_model.name = "Model"
	ghost_model.position = rider_model.position
	ghost_rider.add_child(ghost_model)
	ghost_model.make_ghost()


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
	_aim_camera(target, look, 1.0 if snap else 1.0 - exp(-delta / CAMERA_SMOOTHING_S))


## Titelbild: die Kamera fliegt langsam hoch über dem Rundkurs voraus und blickt weit nach vorn. `snap` springt.
func _fly_title(delta: float, snap: bool = false) -> void:
	_flight_m += TITLE_FLIGHT_MPS * delta
	var up := Vector3.UP
	var target := track.to_global(track.position_at(_flight_m)) + up * TITLE_FLIGHT_HEIGHT_M
	var look := track.to_global(track.position_at(_flight_m + TITLE_LOOK_AHEAD_M)) + up * 4.0
	if world != null:
		target.y = maxf(target.y, world.terrain.height_at(target.x, target.z) + TITLE_TERRAIN_CLEARANCE_M)
	_aim_camera(target, look, 1.0 if snap else 1.0 - exp(-delta / TITLE_SMOOTHING_S))


## Kamera um den Anteil `follow` (0..1) zur Position `target` und zum Blickpunkt `look` hin bewegen.
func _aim_camera(target: Vector3, look: Vector3, follow: float) -> void:
	camera.global_position = camera.global_position.lerp(target, follow)
	_camera_look = _camera_look.lerp(look, follow)
	if camera.global_position.distance_to(_camera_look) > 0.01:
		camera.look_at(_camera_look, Vector3.UP)


## „Losfahren“: neue Fahrt ab `start_distance_m` über `lap_count` Runden (0 = endlos) mit Ghost `ghost_kind`
## (Ghost.BEST/LAST, "" = aus; ohne Aufzeichnung aus) – Fahrmodell, Statistik, Rundenwertung und Pausen
## zurückgesetzt; gefahren wird, sobald das Rad Daten liefert (wie bisher beim Start). Mit `training_unit` (wie
## Training.load_file) ein Training: endlos, ohne Ghost.
func start_ride(mode: String = SaveGame.MODE_ROUND_TRIP, lap_count: int = 1, ghost_kind: String = "",
		training_unit: Dictionary = {}) -> void:
	ride_mode = mode
	training = Training.new(training_unit) if not training_unit.is_empty() else null
	if training != null:
		lap_count = 0
		ghost_kind = ""
	laps = lap_count
	ghost = save_game.ghost(config.track, LapTiming.DIRECTION_CW, ghost_kind) if not ghost_kind.is_empty() else null
	model = RideModel.new(config, start_distance_m)
	stats = RideStats.new()
	_new_lap_timing()
	_reset_progress()
	grade_reporter.reset()
	resistance_hint = ""
	_manual_pause = false
	_ride_saved = false
	start_menu.close()
	settings_menu.set_ride_active(true)
	hud.visible = true
	rider.visible = true
	ghost_rider.visible = ghost != null
	state = STATE_PAUSED_CONNECTION
	state_changed.emit(state)
	_update_state()
	_update_view()
	_update_camera(0.0, true)


## Rundfahrt aus dem Startmenü: gewählte Tageszeit wie im Einstellungsmenü setzen, dann mit der Rundenzahl und dem
## gewählten Ghost losfahren.
func _on_ride_requested(mode: String) -> void:
	settings_menu.select_time(start_menu.time_index())
	if mode == SaveGame.MODE_TRAINING:
		start_ride(mode, 0, "", start_menu.training_unit())
		return
	start_ride(mode, start_menu.round_trip_laps(), start_menu.ghost_choice())


## Neue Rundenwertung ab `start_distance_m` mit `laps` Runden, den Segmenten der Strecke und den gespeicherten
## Bestzeiten; dazu die Medaillen-Schwellen (beim ersten Mal berechnet, danach zwischengespeichert). Im Training ohne
## Segmente und Bestzeiten: dort zählen Runden nicht.
func _new_lap_timing() -> void:
	if training != null:
		lap_timing = LapTiming.new(track.length_m(), start_distance_m, laps)
	else:
		lap_timing = LapTiming.new(track.length_m(), start_distance_m, laps,
				save_game.best_time_s(config.track, LapTiming.DIRECTION_CW), track.segments,
				save_game.segment_best_times(config.track, LapTiming.DIRECTION_CW))
	finish_distance_m = lap_timing.finish_m()
	medal_limits = Medals.thresholds(track, config)


## Erfolge und Fahrerlevel für eine neue Fahrt: Stand vor der Fahrt aus dem Spielstand (Kilometer und Runden aller
## Fahrten), noch nichts Neues.
func _reset_progress() -> void:
	_km_before = save_game.total_km()
	_laps_before = save_game.total_laps()
	_level_before = DriverLevel.level_for(_km_before)
	ride_level = _level_before
	_next_km = floorf(_km_before) + 1.0
	ride_achievements = []


## Ein Ereignis der Fahrt an die Erfolge: neu erfüllte werden freigeschaltet (im Spielstand, gespeichert mit der Fahrt)
## und mit `announce` eingeblendet.
func _achievement_event(event: Dictionary, announce: bool = true) -> void:
	for achievement in Achievements.check(event, save_game.achievements()):
		save_game.unlock_achievement(achievement["id"])
		ride_achievements.append(achievement)
		if announce:
			hud.celebrate("Erfolg: %s – %s" % [achievement["name"], achievement["text"]])


## Fahrerlevel aus den Gesamt-Kilometern (bisher plus diese Fahrt); ein Aufstieg blendet mit `announce` ein.
func _check_level(announce: bool = true) -> void:
	var level := DriverLevel.level_for(_km_before + stats.distance_m / 1000.0)
	if level > ride_level:
		ride_level = level
		if announce:
			hud.celebrate("Fahrerlevel %d erreicht!" % level)


## Ereignisse je voller Kilometer (gesamt): Strecke, Wetter und Tageszeit beim Fahren. Die Jahreszeit (#39) kommt hier
## als {"type": Achievements.EVENT_SEASON, "season": …} dazu.
func _km_events() -> Array:
	return [
		{"type": Achievements.EVENT_DISTANCE, "total_km": _km_before + stats.distance_m / 1000.0,
			"ride_km": stats.distance_m / 1000.0},
		{"type": Achievements.EVENT_WEATHER, "state": sky.weather.state},
		{"type": Achievements.EVENT_TIME_OF_DAY, "hour": sky.clock.local_hour()},
	]


## Fahrtenbuch aus dem Startmenü öffnen (das Menü tritt so lange zurück).
func open_logbook() -> void:
	start_menu.close()
	logbook.open(save_game)


func _on_logbook_closed() -> void:
	start_menu.open()
	start_menu.buttons["logbook"].grab_focus()


func _on_settings_visibility_changed() -> void:
	start_menu.set_covered(settings_menu.visible)
	if not settings_menu.visible:
		logbook.focus_default.call_deferred()  # Einstellungen über dem Fahrtenbuch geschlossen


## Seite „Rundfahrt“ im Startmenü: Tageszeiten wie im Einstellungsmenü, die gespeicherten Ghosts und die Bestzeit der
## Strecke.
func _update_round_trip_menu() -> void:
	var times: Array = settings_menu.time_choices()
	start_menu.set_time_choices(times[0], times[1])
	start_menu.set_ghost_choices(save_game.ghost(config.track, LapTiming.DIRECTION_CW, Ghost.BEST) != null,
			save_game.ghost(config.track, LapTiming.DIRECTION_CW, Ghost.LAST) != null)
	var best := save_game.best_time_s(config.track, LapTiming.DIRECTION_CW)
	start_menu.show_best_time(format_time(best, true) if is_finite(best) else "")


## Fahrt beenden (Ziel oder Abbruch) und zurück ins Startmenü; das Spiel läuft weiter. Die Fahrt kommt in den
## Spielstand, sofern nicht schon geschehen. Mit mindestens einer vollen Runde (z. B. endlos) erst das Ergebnis, im
## Training nach gefahrener Zeit die Teilbewertung.
func return_to_menu() -> void:
	if state == STATE_MENU:
		return
	var has_result := training.elapsed_s > 0.0 if training != null else not lap_timing.lap_times.is_empty()
	if state != STATE_FINISHED and has_result:
		_finish_ride()
		return
	_save_ride()
	_flight_m = model.distance_m
	_enter_menu()


func _enter_menu() -> void:
	logbook.close()
	state = STATE_MENU
	_manual_pause = false
	hud.visible = false
	rider.visible = false
	ghost_rider.visible = false
	settings_menu.set_ride_active(false)
	_update_round_trip_menu()
	start_menu.open()
	state_changed.emit(state)
	_fly_title(0.0, true)


## Ergebnis: Zustand `finished`, Fahrt in den Spielstand. Ein zu Ende gefahrenes Training meldet sich vorher bei den
## Erfolgen (ohne Einblendung – die neuen Erfolge stehen im Ergebnis).
func _finish_ride() -> void:
	state = STATE_FINISHED
	hud.end_celebration()  # „neu!“ steht im Ergebnis; die Einblendung stünde dahinter
	if training != null and training.finished() and not _ride_saved:
		_achievement_event({"type": Achievements.EVENT_TRAINING,
				"total_trainings": save_game.finished_trainings() + 1, "score": training.total_score()}, false)
	_save_ride()
	state_changed.emit(state)


## Die laufende Fahrt als Zusammenfassung in den Spielstand (einmal je Fahrt), mit den Zeiten der vollen Runden und
## einer neuen Bestzeit samt ihrer Runde als Ghost; die letzte volle Runde wird der Ghost „letzte Fahrt“. Eine
## abgebrochene Fahrt nur, wenn gefahren wurde. Ein Training trägt Einheit und Gesamtbewertung ein, aber keine
## Bestzeit, Medaille, Segmentzeit oder Ghost.
func _save_ride() -> void:
	if state == STATE_MENU or _ride_saved or (state != STATE_FINISHED and stats.ride_time_s <= 0.0):
		return
	_ride_saved = true
	var entry := SaveGame.ride_entry(ride_mode, config.track,
			training.finished() if training != null else lap_timing.finished(), lap_timing.lap_times.size(), stats,
			SaveGame.utc_now(), lap_timing.lap_times)
	if training != null:
		var score := training.total_score()
		entry["training"] = training.unit["name"]
		entry["training_score"] = snappedf(score, 0.001) if not is_nan(score) else 0.0
	save_game.add_ride(entry)
	if training == null:
		_record_round_trip()
	# Gesamtstand mit dieser Fahrt: holt auch nach, was ein älterer Spielstand schon erfüllt (ohne Einblendung – im
	# Ergebnis stehen die neuen Erfolge und das Level).
	_achievement_event({"type": Achievements.EVENT_DISTANCE, "total_km": save_game.total_km(),
			"ride_km": stats.distance_m / 1000.0}, false)
	_achievement_event({"type": Achievements.EVENT_LAP, "total_laps": save_game.total_laps(),
			"ride_laps": lap_timing.lap_times.size()}, false)
	_check_level(false)
	if not save_path.is_empty():
		save_game.save_file(save_path)


## Rundfahrt: neue Bestzeit samt Ghost, letzte Runde als Ghost, Medaillen und Segmentzeiten in den Spielstand.
func _record_round_trip() -> void:
	var best_ghost := lap_timing.best_ghost
	if save_game.record_best_time(config.track, LapTiming.DIRECTION_CW, lap_timing.ride_best_s()) \
			and best_ghost != null and is_equal_approx(best_ghost.time_s, lap_timing.ride_best_s()):
		save_game.record_ghost(config.track, LapTiming.DIRECTION_CW, Ghost.BEST, best_ghost)
	if lap_timing.last_ghost != null:
		save_game.record_ghost(config.track, LapTiming.DIRECTION_CW, Ghost.LAST, lap_timing.last_ghost)
	for i in range(lap_timing.lap_times.size()):
		save_game.record_medal(config.track, LapTiming.DIRECTION_CW, Medals.LAP, lap_medal(i))
	for result in lap_timing.segments.results:
		save_game.record_segment_time(config.track, LapTiming.DIRECTION_CW, result["id"], result["time_s"])
		save_game.record_medal(config.track, LapTiming.DIRECTION_CW, result["id"], segment_medal(result))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ride_debug"):
		debug_label.visible = not debug_label.visible
		_update_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_menu") and state == STATE_FINISHED:
		return_to_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_pause") and state != STATE_MENU:
		if state != STATE_FINISHED:
			_manual_pause = not _manual_pause
		_update_state()
		_update_view()
		get_viewport().set_input_as_handled()


func _on_quit_requested() -> void:
	_save_ride()
	quit_requested.emit()
	if quit_on_request:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_ride()  # Fenster geschlossen mitten in der Fahrt


func _exit_tree() -> void:
	if bus != null:
		bus.close()


## Fahrzeit der Fahrt in Sekunden (ohne Pausen); bei einer Runde die Rundenzeit. Die Zeit der laufenden Runde steht
## in `lap_timing.lap_time_s`.
func lap_time_s() -> float:
	return stats.ride_time_s


## Aktuelle Steigung an der Position des Fahrers (Anteil).
func current_grade() -> float:
	return track.grade_at(model.distance_m)


## Krümmung der Strecke an der Position des Fahrers (1/m, positiv = Linkskurve).
func current_curvature() -> float:
	return curvature_at(model.distance_m)


## Krümmung der Strecke an Streckenposition `d` (1/m, positiv = Linkskurve).
func curvature_at(d: float) -> float:
	return RiderMotion.signed_curvature(track.position_at(d - RiderMotion.CURVE_SAMPLE_M), track.position_at(d),
			track.position_at(d + RiderMotion.CURVE_SAMPLE_M))


## Fährt ein Ghost mit? (Abfrage für spätere Pakete, z. B. keine Panorama-Momente mit Ghost, #43.)
func ghost_active() -> bool:
	return ghost != null and state != STATE_MENU


## Läuft ein Training? (Abfrage für spätere Pakete, z. B. keine Panorama-Momente im Training, #43.)
func training_active() -> bool:
	return training != null and state != STATE_MENU


## Streckenposition des Ghosts (wie `model.distance_m`): Beginn der laufenden Runde plus seine Position zur Rundenzeit.
func ghost_distance_m() -> float:
	return lap_timing.lap_start_m() + ghost.position_at(lap_timing.lap_time_s)


## Abstand zum Ghost in Sekunden an der Position des Fahrers: positiv = dahinter, negativ = davor (NAN ohne Ghost).
func ghost_gap_s() -> float:
	return ghost.gap_s(lap_timing.lap_distance_m(), lap_timing.lap_time_s) if ghost != null else NAN


## Abstand zum Ghost für die Anzeige (Sekunden, eine Nachkommastelle): 1.43 → "+1.4", −0.8 → "-0.8", gleichauf "0.0".
static func format_gap(seconds: float) -> String:
	var rounded := snappedf(seconds, 0.1)
	if is_zero_approx(rounded):
		return "0.0"
	return "%+.1f" % rounded


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
			if training != null:
				return training_result()
			var rewards := rewards_result()  # in der Kopfzeile: als eigene Zeile passten 20 Runden nicht mehr in 1152×648
			return "%s%s\nZeit: %s\n%s\nØ Kadenz: %d rpm\nØ Tempo: %.1f km/h\nEnter: zurück ins Menü · Esc: Einstellungen" % [
					"Ziel erreicht!" if lap_timing.finished() else "Fahrt beendet",
					" · " + rewards if not rewards.is_empty() else "", format_time(lap_time_s(), true),
					lap_result(), roundi(stats.avg_cadence()), stats.avg_speed_kmh()]
		STATE_PAUSED_MANUAL:
			return "Pause\nP / Leertaste: weiter\nEsc / F2: Einstellungen (Fahrt beenden, Beenden)"
		STATE_PAUSED_CONNECTION:
			var text: String
			if not bus.bus_connected:
				text = "%sBridge nicht erreichbar (%s)\n%s\nNeuer Versuch läuft …" % [
						"Verbindung verloren: " if _ever_connected else "", bus.url, BRIDGE_START_HINT]
			elif bus.silent:
				text = "Verbindung verloren (Bridge sendet seit %d s nichts)\nWarte auf Daten …" % roundi(
						bus.silence_timeout_s)
			elif bus.status != BusClient.STATE_CONNECTED:
				text = "Verbindung verloren (Rad: %s)\nWarte auf Daten …" % bus.status
			else:
				text = "Verbunden – warte auf Daten …"
			if _manual_pause:
				text += "\n(manuell pausiert)"
			return text
	return ""


## Rundenzeiten, Medaillen, Bestzeit und Segmente fürs Ergebnis, z. B. "Runden: 1:52.3 · 1:49.8\nMedaillen: Silber ·
## Gold\nBestzeit: 1:49.8 – neu!\nSegmente: Dorfsprint 0:41.2 Gold" – je Segment die schnellste Zeit der Fahrt.
func lap_result() -> String:
	var times := lap_timing.lap_times.map(func(t): return format_time(t, true))
	var medals := []
	for i in range(times.size()):
		medals.append(lap_medal(i))
	var best := lap_timing.best_s()
	var text := "%s: %s\n%s: %s\nBestzeit: %s%s" % ["Runde" if times.size() == 1 else "Runden", " · ".join(times),
			"Medaille" if times.size() == 1 else "Medaillen", Medals.summary(medals),
			format_time(best, true) if is_finite(best) else "–", " – neu!" if lap_timing.new_best() else ""]
	var segments := []
	for segment in track.segments:
		var fastest := {}
		for result in lap_timing.segments.results:
			if result["id"] == segment["id"] and (fastest.is_empty() or result["time_s"] < fastest["time_s"]):
				fastest = result
		if not fastest.is_empty():
			segments.append(("%s %s %s" % [segment["name"], format_time(fastest["time_s"], true),
					Medals.name_of(segment_medal(fastest))]).strip_edges())
	if not segments.is_empty():
		text += "\nSegmente: " + " · ".join(segments)
	return text


## Ergebnis eines Trainings: Einheit, Zeit, Treffer der Zielkadenz gesamt und je gefahrener Phase, z. B.
## „Training beendet! · Neuer Erfolg: Erste Einheit\nPyramide · Zeit: 34:00.0\nZielkadenz getroffen: 87 %\nJe Phase:
## Aufwärmen 100 % · 70 rpm 80 % · …“. Abgebrochen: die Teilbewertung der gefahrenen Phasen.
func training_result() -> String:
	var rewards := rewards_result()
	return "%s%s\n%s · Zeit: %s\nZielkadenz getroffen: %s\nJe Phase: %s\nØ Kadenz: %d rpm · Ø Tempo: %.1f km/h\n%s" % [
			"Training beendet!" if training.finished() else "Training abgebrochen",
			" · " + rewards if not rewards.is_empty() else "", training.unit["name"], format_time(lap_time_s(), true),
			Training.percent_text(training.total_score()), training.phase_summary(), roundi(stats.avg_cadence()),
			stats.avg_speed_kmh(), "Enter: zurück ins Menü · Esc: Einstellungen"]


## Neue Erfolge und Levelaufstieg dieser Fahrt fürs Ergebnis in einer Zeile, z. B. „Neuer Erfolg: Erste Runde ·
## Fahrerlevel 2 erreicht“ oder „3 neue Erfolge“ ("" = nichts Neues). Alle stehen im Fahrtenbuch.
func rewards_result() -> String:
	var parts := []
	if ride_achievements.size() == 1:
		parts.append("Neuer Erfolg: %s" % ride_achievements[0]["name"])
	elif ride_achievements.size() > 1:
		parts.append("%d neue Erfolge" % ride_achievements.size())
	if ride_level > _level_before:
		parts.append("Fahrerlevel %d erreicht" % ride_level)
	return " · ".join(parts)


## Medaille der Runde `index` (ab 0). Eine verkürzte erste Runde (Start nicht an der Start/Ziel-Linie) bekommt keine.
func lap_medal(index: int) -> String:
	if index == 0 and not is_zero_approx(track.wrap_distance(start_distance_m)):
		return Medals.NONE
	return Medals.medal_for(lap_timing.lap_times[index], medal_limits.get(Medals.LAP, {}))


## Medaille eines gewerteten Segments ({id, time_s, …} aus SegmentTiming.results).
func segment_medal(result: Dictionary) -> String:
	return Medals.medal_for(result["time_s"], medal_limits.get(result["id"], {}))


## Einblendung beim Verlassen eines Segments, z. B. "Dorfsprint  0:41.2 · Gold – neue Bestzeit!".
func segment_result_text(result: Dictionary) -> String:
	var text := "%s  %s" % [result["name"], format_time(result["time_s"], true)]
	var medal := Medals.name_of(segment_medal(result))
	if not medal.is_empty():
		text += " · " + medal
	if result["new_best"]:
		text += " – neue Bestzeit!"
	return text


func _update_state() -> void:
	if bus.bus_connected:
		_ever_connected = true
	if state == STATE_FINISHED or state == STATE_MENU:
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


## Ein Zeitschritt Fahrt: Fahrmodell, Statistik, Rundenwertung, Training und Ziel. Den Schritt über die Ziellinie
## (bzw. über das Ende der Einheit) zählen Statistik und Rundenwertung nur anteilig, damit Zeiten und Durchschnitte
## genau sind.
func _ride(delta: float) -> void:
	var before := model.distance_m
	model.step(bus.cadence, current_grade(), delta)
	var moved := model.distance_m - before
	var used := delta
	if model.distance_m >= finish_distance_m:
		used = delta * ((finish_distance_m - before) / moved if moved > 0.0 else 1.0)
		model.distance_m = finish_distance_m
	if training != null and training.remaining_total_s() < used:
		model.distance_m = before + moved * training.remaining_total_s() / delta
		used = training.remaining_total_s()
	stats.add(used, bus.cadence, model.distance_m - before)
	if training != null:
		training.advance(bus.cadence, used)
	var segments_before := lap_timing.segments.results.size()
	var laps_done := lap_timing.advance(model.distance_m, used)
	if laps_done > 0 and training == null and lap_timing.last_lap_is_new_best():
		hud.celebrate("Neue Bestzeit!  %s" % format_time(lap_timing.lap_times[-1], true))
	for i in range(segments_before, lap_timing.segments.results.size()):
		hud.celebrate(segment_result_text(lap_timing.segments.results[i]))
	if laps_done > 0:
		_achievement_event({"type": Achievements.EVENT_LAP, "total_laps": _laps_before + lap_timing.lap_times.size(),
				"ride_laps": lap_timing.lap_times.size()})
	while _km_before + stats.distance_m / 1000.0 >= _next_km:
		_next_km += 1.0
		for event in _km_events():
			_achievement_event(event)
		_check_level()
	if lap_timing.finished() or (training != null and training.finished()):
		_finish_ride()


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


## Inhalt der Debug-Anzeige (F3): Kadenz-Rohwert wie empfangen, Bridge-Zeitstempel und Zeit seit Empfang der
## letzten Telemetrie im Spiel – zur Prüfung der Latenz (< 200 ms, ADR-0005). Die Zeit seit Empfang zeigt nur, ob
## Daten stocken; die Gesamtlatenz Kurbel → Bild misst sie nicht (siehe docs/anleitung.md).
func debug_text() -> String:
	var raw = bus.last_telemetry.get("cadence")
	var age := bus.telemetry_age_ms()
	return "DEBUG\nKadenz roh: %s\nt_ms: %s\nLetzte Telemetrie vor: %s\nBus: %s · Quelle: %s (%s)" % [
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
	if ghost == null:
		return
	# Der Ghost kennt nur Strecke über Zeit: Tempo daraus, Kadenz für die Kurbel über das Fahrmodell zurückgerechnet.
	var t := lap_timing.lap_time_s
	var d := ghost_distance_m()
	var speed := ghost.position_at(t + 0.5) - ghost.position_at(t - 0.5)
	var grade := track.grade_at(d)
	var per_rpm := model.target_speed_mps(1.0, grade)
	ghost_model.update(speed / per_rpm if per_rpm > 0.0 else 0.0, speed, grade, curvature_at(d), state != STATE_RIDING,
			delta)


## Trainingszeile und Ansage im HUD (ausgeblendet ohne Training und im Ergebnis).
func _show_training() -> void:
	if training == null or state == STATE_FINISHED:
		hud.show_training("", "", "", "")
		hud.show_announcement("")
		return
	var phase := training.phase()
	var next := training.next_phase()
	hud.show_training(phase["name"], Training.target_text(phase), format_time(ceilf(training.remaining_s())),
			"%s · %s" % [next["name"], Training.target_text(next)] if not next.is_empty() else "Ende der Einheit")
	hud.show_announcement(training.announcement())


func _update_view() -> void:
	rider.progress = track.wrap_distance(model.distance_m)
	var grade := current_grade()
	hud.show_ride(bus.cadence, model.speed_kmh(), stats.distance_m, format_time(lap_time_s()), grade,
			format_grade(grade), current_station(), format_power(bus.power_w(), bus.power_estimated()))
	hud.show_lap(model.distance_m, lap_timing.lap_start_m(), lap_timing.lap_end_m(), rider.progress)
	hud.show_lap_count(lap_timing.lap_number(), laps, format_time(lap_timing.lap_time_s))
	if ghost != null:
		ghost_rider.progress = track.wrap_distance(ghost_distance_m())
		var gap := ghost_gap_s()
		hud.show_ghost(format_gap(gap), gap > 0.0)
	else:
		hud.show_ghost("", false)
	_show_training()
	var segment := lap_timing.segments.current()
	hud.show_segment(segment.get("name", ""), format_time(segment["time_s"], true) if not segment.is_empty() else "")
	if debug_label.visible:
		debug_label.text = debug_text()
	hint_label.text = resistance_hint
	var message := status_message()
	message_label.text = message
	message_label.visible = not message.is_empty()
