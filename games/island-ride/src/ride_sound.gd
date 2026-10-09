## Ton der Inselfahrt (#44): dezent, standardmäßig leise, auf eigenem Audio-Bus BUS („Spiel“) mit Lautstärke und
## Aus-Schalter aus dem Einstellungsmenü (GraphicsSettings `[sound]`) – damit Musik nebenher nicht übertönt wird. Alle
## Klänge entstehen prozedural (SoundSynth), es gibt keine Klangdateien. Von der Hauptszene in `_ready` angelegt
## (`setup(main)`, Kind `Sound`).
##   Fahrtwind   lauter und heller mit dem Tempo (WIND_KMH), nur beim Fahren
##   Freilauf    Ticken bei Kadenz 0 und Tempo > 0; Klicks je Sekunde aus dem Tempo (Sperrklinken je Radumdrehung)
##   Meer        nach dem Abstand des Hörers zum Wasser (Messringe um ihn im Höhenfeld, `water_distance`)
##   Regen       nach der Regenstärke des Wetters (wie die sichtbaren Tropfen)
##   Möwen       je Möwenschwarm aus WorldMotion (Hafen, Leuchtturm, Westküste) ein AudioStreamPlayer3D an seinem Ort,
##               ruft ab und zu; nur wenn die Vögel zu sehen sind (Regel „birds“ in SkyController.look: nicht nachts,
##               nicht im Regen)
##   Schafglocken an den Einhängepunkten `World/Fauna/Glocken/Herde<n>` (#40) je ein AudioStreamPlayer3D als Kind,
##               bimmelt ab und zu; Sichtbarkeitsregel der Schafe (IslandFauna.shown)
##   Dorfglocke  am Glockenstuhl der Kirche im Bergdorf (`World/Props/bergdorf/Kirche/Glockenstuhl`), läutet gelegentlich
##               (CHURCH_STRIKES Schläge, zwei Glocken im Wechsel), sobald sie zu hören ist
##   UI          Klick bei jedem Knopfdruck in den Menüs und beim Öffnen/Schließen der Einstellungen, heller Doppelton
##               je sichtbarer HUD-Einblendung (RideHud.celebration_shown), weicher Ton bei einer Trainingsansage
##               (`announce`)
## Die Pegel rechnet `levels(context)` als reine Funktion aus Tempo, Kadenz, Ort, Wetter und Tageslicht (Tests ohne
## Audio-Ausgang); die Entfernungsregel ist überall dieselbe (`near`: voll bis x, still ab y). Die 3D-Spieler dämpfen nicht
## selbst (Dämpfung aus), sie verteilen nur links/rechts – den Pegel setzt diese Klasse. Ton ist nur Ausgabe: er liest
## Fahrmodell, Kadenz, Zustand, Kamera, Himmel und Welt und ändert nichts davon (ADR-0010).
## Die Klänge entstehen beim Start, einer je Frame (kein großer Block). Ohne Audio-Gerät (headless; im Browser vor der
## ersten Nutzergeste oder wenn die Audio-Worklets nicht laden) läuft alles gleich, es ist nur nichts zu hören.
class_name RideSound
extends Node

const BUS := "Spiel"
## Grundpegel je Klang (linear, vor dem Bus) – dezent; die Lautstärke im Menü (Standard 30 %) kommt am Bus dazu.
const GAIN := {"wind": 0.45, "freewheel": 0.2, "sea": 0.4, "rain": 0.35, "gulls": 0.3, "sheep": 0.3, "church": 0.45,
		"click": 0.25, "chime": 0.3, "announce": 0.35}
## Fahrtwind: hörbar ab / voll bei km/h; Abspieltempo (Tonhöhe) dabei von / bis.
const WIND_KMH := Vector2(5.0, 45.0)
const WIND_PITCH := Vector2(0.8, 1.35)
## Freilauf: ab dieser Geschwindigkeit (km/h) bei Kadenz unter FREEWHEEL_MAX_RPM; Klicks je Radumdrehung, Radumfang (m).
const FREEWHEEL_MIN_KMH := 1.0
const FREEWHEEL_MAX_RPM := 1.0
const FREEWHEEL_CLICKS_PER_REV := 12.0
const WHEEL_M := 2.1
## Entfernungen (m): voll bis x, still ab y.
const SEA_M := Vector2(25.0, 220.0)
const GULL_M := Vector2(40.0, 260.0)
const SHEEP_M := Vector2(15.0, 110.0)
const CHURCH_M := Vector2(60.0, 520.0)
## Meer: Halbmesser der Messringe um den Hörer (m), Richtungen je Ring, Prüfintervall (s).
const WATER_RINGS_M := [0.0, 10.0, 25.0, 45.0, 70.0, 100.0, 140.0, 180.0, 220.0]
const WATER_DIRECTIONS := 12
const WATER_EVERY_S := 0.3
## Pausen zwischen Möwenrufen, Glockenbimmeln und Geläut (s, von/bis); erstes Geläut nach so viel hörbarer Zeit,
## Schläge je Geläut und Abstand der Schläge (s).
const GULL_PAUSE_S := Vector2(3.0, 9.0)
const SHEEP_PAUSE_S := Vector2(1.5, 5.0)
const CHURCH_PAUSE_S := Vector2(60.0, 120.0)
const CHURCH_FIRST_S := 6.0
const CHURCH_STRIKES := 5
const CHURCH_STRIKE_S := 1.6
## UI-Klänge (SoundSynth-IDs) und Mindestabstand zweier Klicks (s) – Knopf und Menüwechsel im selben Moment klicken
## einmal.
const UI_CLICK := "click"
const UI_CELEBRATION := "chime"
const UI_ANNOUNCEMENT := "announce"
const UI_GAP_S := 0.08
## Endlosklänge (ein AudioStreamPlayer je Klang) und UI-Klänge.
const LOOPS := ["wind", "freewheel", "sea", "rain"]
const UI := [UI_CLICK, UI_CELEBRATION, UI_ANNOUNCEMENT]

## Hauptszene (Fahrmodell, Bus, Zustand, Kamera, Himmel) und Insel-Welt (null bei der Graybox).
var main: Node3D
var world: IslandWorld
## Ton an (Einstellung); aus: alle Spieler gestoppt, keine Auslösungen.
var enabled := true
## Erzeugte Klänge (SoundSynth-ID → AudioStreamWAV) und noch zu erzeugende.
var streams := {}
var pending: Array = SoundSynth.IDS.duplicate()
## Auslösungen je Klang (Endlosklang gestartet, Ruf, Bimmeln, Glockenschlag, UI-Klang) – für Tests und Fehlersuche.
var plays := {}
## Zuletzt gerechnete Pegel (`levels`) und der Abstand des Hörers zum Wasser (m, INF = keins in Reichweite).
var current := {}
var water_m := INF
## Spieler: Endlos- und UI-Klänge (ID → AudioStreamPlayer), Möwenschwärme, Schafherden, Kirchturm.
var players := {}
var gull_players: Array[AudioStreamPlayer3D] = []
var sheep_players: Array[AudioStreamPlayer3D] = []
var church_player: AudioStreamPlayer3D = null

var _rng := RandomNumberGenerator.new()
var _gull_wait: Array[float] = []
var _sheep_wait: Array[float] = []
var _church_wait := CHURCH_FIRST_S
var _strikes_left := 0
var _strike_wait := 0.0
var _water_wait := 0.0
var _click_s := -INF
var _announced := ""
var _phase := -1


func setup(main_scene: Node3D) -> void:
	main = main_scene
	world = main.world
	name = "Sound"
	_rng.seed = 4400
	ensure_bus()
	for id in LOOPS + UI:
		var player := AudioStreamPlayer.new()
		player.name = id.capitalize().replace(" ", "")
		player.bus = BUS
		add_child(player)
		players[id] = player
	if world != null:
		for centre in gull_places(world.motion):
			var gull := _player_3d(self, "Moewen%d" % (gull_players.size() + 1), 2)
			gull.position = centre
			gull_players.append(gull)
			_gull_wait.append(_rng.randf_range(0.5, GULL_PAUSE_S.y))
		for herd in world.fauna.bell_herds:
			sheep_players.append(_player_3d(herd["node"], "Schafglocke", 2))
			_sheep_wait.append(_rng.randf_range(0.0, SHEEP_PAUSE_S.y))
		var belfry := world.get_node_or_null("Props/bergdorf/Kirche/Glockenstuhl")
		if belfry != null:
			church_player = _player_3d(belfry, "Dorfglocke", 3)
	watch_ui(main)
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	update(delta)


## Ein Zeitschritt: nächsten Klang erzeugen, Pegel rechnen und setzen, Rufe und Geläut auslösen.
func update(delta: float) -> void:
	_build_next()
	if not enabled:
		return
	var listener := listener_position()
	_water_wait -= delta
	if _water_wait <= 0.0 and world != null:
		_water_wait = WATER_EVERY_S
		water_m = water_distance(world.terrain, listener)
	var c := context(listener)
	current = levels(c)
	_set_loop("wind", current["wind"], lerpf(WIND_PITCH.x, WIND_PITCH.y, current["wind"]))
	_set_loop("freewheel", current["freewheel"], freewheel_pitch(c["speed_kmh"]))
	_set_loop("sea", current["sea"], 1.0)
	_set_loop("rain", current["rain"], 1.0)
	for i in range(gull_players.size()):
		_gull_wait[i] -= delta
		if _ring(gull_players[i], current["gulls"][i], "gulls", _gull_wait[i]):
			_gull_wait[i] = _rng.randf_range(GULL_PAUSE_S.x, GULL_PAUSE_S.y)
	for i in range(sheep_players.size()):
		_sheep_wait[i] -= delta
		if _ring(sheep_players[i], current["sheep"][i], "sheep", _sheep_wait[i]):
			_sheep_wait[i] = _rng.randf_range(SHEEP_PAUSE_S.x, SHEEP_PAUSE_S.y)
	if is_instance_valid(church_player):
		_toll(delta, current["church"])


## Pegel 0..1 je Klang aus `c` (siehe `context`): {wind, freewheel, sea, rain, church, gulls: [je Schwarm],
## sheep: [je Herde]}. Reine Funktion.
static func levels(c: Dictionary) -> Dictionary:
	var speed: float = c.get("speed_kmh", 0.0) if c.get("riding", false) else 0.0
	var gulls := []
	for d in c.get("gull_m", []):
		gulls.append(near(d, GULL_M) if c.get("gulls_shown", false) else 0.0)
	var sheep := []
	for d in c.get("sheep_m", []):
		sheep.append(near(d, SHEEP_M) if c.get("sheep_shown", true) else 0.0)
	var coasting: bool = speed >= FREEWHEEL_MIN_KMH and c.get("cadence", 0.0) < FREEWHEEL_MAX_RPM
	return {
		"wind": smoothstep(WIND_KMH.x, WIND_KMH.y, speed),
		"freewheel": lerpf(0.6, 1.0, smoothstep(FREEWHEEL_MIN_KMH, 30.0, speed)) if coasting else 0.0,
		"sea": near(c.get("water_m", INF), SEA_M),
		"rain": clampf(c.get("rain", 0.0), 0.0, 1.0),
		"church": near(c.get("church_m", INF), CHURCH_M),
		"gulls": gulls,
		"sheep": sheep,
	}


## Entfernungsregel: 1 bis `range_m.x`, weich auf 0 bei `range_m.y` (m).
static func near(distance_m: float, range_m: Vector2) -> float:
	return 1.0 - smoothstep(range_m.x, range_m.y, distance_m)


## Abspieltempo des Freilaufs für `speed_kmh`: Klicks je Sekunde (Radumdrehungen × Klicks je Umdrehung) im Verhältnis zur
## Schleife (SoundSynth.FREEWHEEL_TICKS_PER_S).
static func freewheel_pitch(speed_kmh: float) -> float:
	var ticks := speed_kmh / 3.6 / WHEEL_M * FREEWHEEL_CLICKS_PER_REV
	return clampf(ticks / SoundSynth.FREEWHEEL_TICKS_PER_S, 0.2, 4.0)


## Abstand (m) vom Punkt `at` zum Wasser (Höhenfeld unter null): kleinster Messring (WATER_RINGS_M) mit Wasser, INF ohne.
static func water_distance(terrain: IslandTerrain, at: Vector3) -> float:
	for r in WATER_RINGS_M:
		var count := 1 if r == 0.0 else WATER_DIRECTIONS
		for k in range(count):
			var angle := TAU * k / count
			if terrain.height_at(at.x + cos(angle) * r, at.z + sin(angle) * r) < 0.0:
				return r
	return INF


## Mitten der Möwenschwärme (WorldMotion: Vögel „Moewe…“, je Schwarm eine Kreismitte).
static func gull_places(motion: WorldMotion) -> Array:
	var places := []
	for bird in motion.birds:
		if String(bird["node"].name).begins_with("Moewe") and bird["centre"] not in places:
			places.append(bird["centre"])
	return places


## Eingaben für `levels` am Hörer `listener`: Fahrt (`riding`, `speed_kmh`, `cadence`), Wasserabstand, Regen, Sichtbarkeit
## der Möwen und Schafe und die Abstände zu Schwärmen, Herden und Kirchturm.
func context(listener: Vector3) -> Dictionary:
	var sky: SkyController = main.sky
	var c := {"riding": main.state == main.STATE_RIDING, "speed_kmh": main.model.speed_kmh(), "cadence": main.bus.cadence,
			"water_m": water_m, "rain": sky.current.get("rain", 0.0), "church_m": INF}
	if world != null:
		var birds := world.motion.get_node_or_null("Voegel") as Node3D
		c["gulls_shown"] = birds != null and birds.visible
		c["gull_m"] = gull_players.map(_distance.bind(listener))
		c["sheep_shown"] = IslandFauna.shown("Schafe", sky.sun_angles.x, sky.weather.params(), sky.applied_season)
		c["sheep_m"] = sheep_players.map(_distance.bind(listener))
		c["church_m"] = _distance(church_player, listener)
	return c


## Abstand eines 3D-Spielers zum Hörer; INF ohne Spieler (oder wenn sein Ort mit der Welt abgebaut wurde).
static func _distance(player, listener: Vector3) -> float:
	return player.global_position.distance_to(listener) if is_instance_valid(player) else INF


## Hörer: die Kamera der Hauptszene (auch Hörer der 3D-Spieler).
func listener_position() -> Vector3:
	return main.camera.global_position


## Ton an/aus und Lautstärke (0..1) am Bus; aus stoppt alle Spieler.
func apply_settings(on: bool, volume: float) -> void:
	enabled = on
	var index := ensure_bus()
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, not on)
	if not on:
		for player in find_children("*", "AudioStreamPlayer", true, false) + _3d_players():
			player.stop()


## Bus BUS (an Master), legt ihn beim ersten Mal an. Index.
static func ensure_bus() -> int:
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, "Master")
	return index


## UI-Klang `id` (UI_*); ein Klick nicht zweimal binnen UI_GAP_S.
func play_ui(id: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not enabled or (id == UI_CLICK and now - _click_s < UI_GAP_S):
		return
	if id == UI_CLICK:
		_click_s = now
	_start(players[id], id, GAIN[id])


## Trainingsansage (#37): Klang, wenn eine Ansage erscheint ("" → Text) und beim Phasenwechsel – nicht bei jeder
## Textänderung (der Countdown ändert den Text jede Sekunde). `phase` = Training.phase_index(), -1 ohne Training.
func announce(text: String, phase: int) -> void:
	var chime := (not text.is_empty() and _announced.is_empty()) or (phase >= 0 and _phase >= 0 and phase != _phase)
	_announced = text
	_phase = phase
	if chime:
		play_ui(UI_ANNOUNCEMENT)


## Klick an jedem Knopf unter `root` (auch später angelegten, siehe `_on_node_added`).
func watch_ui(root: Node) -> void:
	for button in root.find_children("*", "BaseButton", true, false):
		_watch_button(button)


## Alle Klänge sofort erzeugen (Tests, Prüfhilfe); im Spiel einer je Frame.
func build_all() -> void:
	while not pending.is_empty():
		_build_next()


func _build_next() -> void:
	if pending.is_empty():
		return
	var id: String = pending.pop_front()
	var stream := SoundSynth.build(id)
	streams[id] = stream
	if players.has(id):
		players[id].stream = stream
	var targets: Array = {"gull": gull_players, "sheep": sheep_players}.get(id, [])
	if id == "church" and church_player != null:
		targets = [church_player]
	for player in targets:
		if is_instance_valid(player):
			player.stream = stream


func _player_3d(parent: Node, node_name: String, polyphony: int) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.bus = BUS
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.attenuation_filter_db = 0.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.max_polyphony = polyphony
	parent.add_child(player)
	return player


func _3d_players() -> Array:
	return (gull_players + sheep_players + [church_player]).filter(func(p): return is_instance_valid(p))


## Endlosklang `id` auf Pegel `level` und Abspieltempo `pitch`; still → gestoppt.
func _set_loop(id: String, level: float, pitch: float) -> void:
	var player: AudioStreamPlayer = players[id]
	if player.stream == null:
		return
	player.volume_db = linear_to_db(maxf(level * GAIN[id], 0.0001))
	player.pitch_scale = pitch
	if level > 0.001 and not player.playing:
		_start(player, id, level * GAIN[id])
	elif level <= 0.001 and player.playing:
		player.stop()


## Ruf/Bimmeln am 3D-Spieler `player` mit Pegel `level`, wenn hörbar und die Wartezeit `wait` um ist. Ausgelöst?
func _ring(player, level: float, key: String, wait: float) -> bool:
	if not is_instance_valid(player):
		return false
	player.volume_db = linear_to_db(maxf(level * GAIN[key], 0.0001))
	if level <= 0.001 or wait > 0.0:
		return false
	player.pitch_scale = _rng.randf_range(0.88, 1.12)
	_start(player, key, -1.0)
	return true


## Dorfglocke: Geläut aus CHURCH_STRIKES Schlägen (zwei Glocken im Wechsel), danach Pause; die Zeit läuft nur, solange sie
## zu hören ist.
func _toll(delta: float, level: float) -> void:
	church_player.volume_db = linear_to_db(maxf(level * GAIN["church"], 0.0001))
	if level <= 0.001:
		return
	if _strikes_left > 0:
		_strike_wait -= delta
		if _strike_wait <= 0.0:
			church_player.pitch_scale = 1.0 if _strikes_left % 2 == 1 else 0.89
			_start(church_player, "church", -1.0)
			_strikes_left -= 1
			_strike_wait = CHURCH_STRIKE_S
		return
	_church_wait -= delta
	if _church_wait <= 0.0:
		_strikes_left = CHURCH_STRIKES
		_strike_wait = 0.0
		_church_wait = _rng.randf_range(CHURCH_PAUSE_S.x, CHURCH_PAUSE_S.y)


## Spieler starten (sofern sein Klang schon erzeugt ist) und die Auslösung zählen; `volume` ≥ 0 setzt den Pegel (linear).
func _start(player: Node, key: String, volume: float) -> void:
	plays[key] = plays.get(key, 0) + 1
	if volume >= 0.0:
		player.volume_db = linear_to_db(maxf(volume, 0.0001))
	if player.stream != null:
		player.play()


func _on_node_added(node: Node) -> void:
	if node is BaseButton and main.is_ancestor_of(node):
		_watch_button(node)


func _watch_button(button: BaseButton) -> void:
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_ui(UI_CLICK)
