## Manuelle Sichtprüfung (#15): startet die Hauptszene gerendert (ohne `--headless`, ohne Bus), stellt den Fahrer
## an Streckenpositionen und speichert je ein Viewport-Bild; optional fährt sie einen Abschnitt mit festem Tempo ab
## und misst die Bildrate.
##   godot --path games/island-ride -s res://tools/view_probe.gd -- --out=C:/tmp/shots [--shots=0,200,450]
##         [--fps-from=0 --fps-to=2310 --speed-kmh=50] [--size=1920x1080] [--cadence=85] [--close] [--pair]
##         [--advance=1.5] [--time=21:30] [--date=2026-06-21] [--weather=rain] [--season=summer] [--profile=forward|compat]
##         [--aa=msaa_4x] [--scale=1.0] [--upscaler=bilinear] [--vsync=off] [--hud] [--debug] [--menu] [--crop=x,y,w,h]
##         [--title] [--window=left|right|fullscreen] [--laps=3] [--segments] [--ghost=1.4] [--logbook] [--rewards]
##         [--training] [--ccw] [--wardrobe=trikot_gelb,radfarbe_blau,helm_schwarz] [--fauna]
## `--shots`: Streckenpositionen (m) für Screenshots (`shot_<m>.png` in `--out`). `--fps-from/--fps-to`: Fahrt mit
## `--speed-kmh` über diesen Abschnitt, danach eine Zeile mit min/Mittel/1-%-Tief der fps. Das HUD wird ausgeblendet
## (ohne Bridge stünde dort die Verbindungsmeldung) – außer mit `--hud`: dann zeigt es Beispielwerte (Kadenz wie
## `--cadence`, Tempo des Fahrmodells, Steigung und Abschnitt der Strecke, Strecke/Zeit bis zur Position, „~142 W“),
## die Verbindungsmeldung ist unsichtbar. `--debug` blendet zusätzlich die Debug-Anzeige (F3) ein. `--menu` öffnet
## das Grafikmenü. Grafik wie bei einem frischen Start (GraphicsSettings-Standard,
## `user://settings.cfg` bleibt unberührt); `--aa`/`--scale`/`--upscaler`/`--vsync=off` überschreiben. `--crop`:
## zusätzlich Bildausschnitt `crop_<m>.png` (z. B. für den AA-Vergleich). VSync wie im Projekt (Standard: an).
## Fahrer und Rad treten mit `--cadence` (rpm, 0 = Stillstand): die Hauptszene füttert ohne Bus nur eine Attrappe
## (sie steht in der Verbindungspause), die Probe bewegt das echte Modell. Vor jedem Screenshot 1 s Tritt.
## `--close`: zusätzlich Nahaufnahmen je Position (`close_<m>_side.png`, `close_<m>_rear.png`, Kamera nur hier
## versetzt). `--pair`: zweites Bild 0,15 s später (`shot_<m>_b.png`) – Kurbelstellung muss sich unterscheiden.
## `--advance`: im Bildpaar zusätzlich die Weltanimation (WorldMotion: Flügel, Vögel, Boote, Wolken) um so viele
## Sekunden vorrücken, damit die Bewegung im Vergleich sichtbar wird (Standard 0).
## Tag/Nacht und Wetter (G6): `--time` feste Ortszeit (Mallorca, HH:MM), `--date` Datum dazu (Standard heute),
## `--weather` festes Wetter (clear, light_clouds, overcast, rain) ohne Überblendung. Ohne Angabe gilt `[sky]` aus
## config.cfg. Bei Regen wartet die Probe, bis die Tropfen gefallen sind. Jahreszeit (#39): `--season` feste Phase
## (almond, spring, summer, autumn, winter); ohne Angabe folgt sie dem Datum (`--date` oder heute). `--profile` erzwingt das Lichtprofil
## (Vergleich: Compatibility-Renderer mit `--profile=forward` zeigt das Bild ohne Web-Profil).
## Startmenü (#30): `--title` startet wie das Spiel mit Titelbild und Kameraflug und speichert `title.png`,
## `title_modes.png` (Seite „Fahren“) und `title_b.png` (3 s später, Kamera weitergeflogen) statt der Streckenbilder.
## `--window` legt das Fenster vorher wie im Grafikmenü auf die linke/rechte Bildschirmhälfte oder ins Vollbild.
## Rundfahrt (#31): `--laps=N` (0 = endlos) zeigt eine Fahrt über N Runden mit Beispiel-Bestzeit (LAP_SAMPLES_S, nur im
## Speicher). Mit `--title` zusätzlich `title_round_trip.png` (Seite „Rundfahrt“), mit `--hud` steht der Fahrer in
## Runde 2 (HUD mit Runde und Rundenzeit, Einblendung „Neue Bestzeit!“), danach `result.png` mit dem Ergebnis aller
## Runden (mit Medaillen und, über die Beispielzeiten anteilig, den Segmenten, #33).
## Segmente (#33): `--segments` (mit `--hud`) stellt den Fahrer in jedes Segment der Strecke – HUD mit Live-Zeit,
## `segment_<id>.png` – und kurz hinter sein Ende mit dem Ergebnis beim Verlassen (`segment_<id>_result.png`);
## Beispielzeit knapp unter der Silber-Schwelle. Die Torbögen zeigen `--shots` kurz vor dem Segmentstart.
## Ghost (#32): `--ghost=S` lässt einen Beispiel-Ghost mitfahren, gegen den der Fahrer S Sekunden zurückliegt (negativ:
## vorn) – gleiches Tempo wie der Fahrer (Beispielfahrt 22 km/h, bei `--fps-*` dessen Tempo), halbtransparent
## neben/vor dem Fahrer, mit `--hud` der Abstand im HUD. Mit `--title --laps=N` steht er (nur im Speicher) als
## Bestzeit und letzte Fahrt in der Ghost-Auswahl der Seite „Rundfahrt“.
## Fahrtenbuch (#35): `--title --logbook` füllt den Spielstand (nur im Speicher) mit Beispielfahrten, Bestzeiten,
## Segmentzeiten, Medaillen und Erfolgen, öffnet das Fahrtenbuch aus dem Startmenü und speichert je Seite
## `logbook_overview.png`, `logbook_achievements.png` und `logbook_rides.png` statt der Titelbilder.
## `--hud --rewards` speichert nach den Streckenbildern die Einblendung eines Erfolgs (`achievement.png`) und eines
## Levelaufstiegs (`level_up.png`) an der letzten Position aus `--shots`.
## Training (#37): `--title --training` speichert zusätzlich `title_training.png` (Seite „Training“); `--hud --training`
## fährt nach den Streckenbildern die Einheit „Intervalle kurz“ bis kurz vor die erste harte Phase (HUD mit
## Trainingszeile und Ansage, `training.png`) und dann zu Ende, mit Treffern je nach Phase (`training_result.png`).
## Gegenrichtung (#34): `--ccw` fährt gegen den Uhrzeigersinn – `--shots`, `--segments`, `--laps` und `--ghost` dann in
## Fahrtposition dieser Richtung, mit `--title` ist die Richtung auf der Seite „Rundfahrt“ gewählt.
## Garderobe (#36): `--wardrobe=TEIL,…` gibt dem Spielstand (nur im Speicher) Kilometer bis Level 12 und wählt die Teile
## (Wardrobe.PARTS; leer = Standard) – der Fahrer trägt sie in `--shots`/`--close`. Mit `--title` öffnet die Probe die
## Garderobe aus dem Startmenü und speichert `wardrobe.png` statt der Titelbilder.
## Tiere (#40): `--fauna` speichert nach den Streckenbildern je Tierart (IslandFauna.KINDS) eine Nahaufnahme
## (`fauna_<Art>.png`, Kamera wenige Meter neben dem Tier, Blick von der Straße) und 2,5 s Tieranimation später ein
## zweites Bild (`fauna_<Art>_b.png`). Die Ziegenquerung zeigen `--shots` 100–35 m vor IslandFauna.CROSSINGS_M.
## Delfine und Fische (#41) im Sprung, das zweite Bild 0,25 s später; ausgeblendete Arten (Tag/Nacht, Wetter) fehlen.
extends SceneTree

## Beispiel-Rundenzeiten (s) für `--laps`: gespeicherte Bestzeit vorher, dann die Runden der Fahrt.
const LAP_SAMPLES_S := [905.3, 912.4, 884.7, 897.9, 890.2]

var _ride: Node3D
## Echtes Fahrer-/Radmodell in der Szene und Kadenz, mit der es tritt.
var _model: RiderModel
var _cadence := 85.0
## Bildausschnitt für `crop_<m>.png` (leer = keiner).
var _crop := Rect2i()
## Gegen den Uhrzeigersinn fahren (#34)?
var _ccw := false
## HUD mit Beispielwerten zeigen (`--hud`).
var _hud := false
## Debug-Anzeige (F3) zeigen (`--debug`).
var _debug := false
## Rundenzahl der Beispiel-Rundfahrt (`--laps`; −1 = ohne).
var _laps := -1
## Live-Zeit und Ergebnis je Segment zeigen (`--segments`).
var _segments := false
## Rückstand auf den Beispiel-Ghost in Sekunden (`--ghost`; NAN = ohne Ghost).
var _ghost_s := NAN
## Fahrtenbuch statt Titelbilder (`--logbook`), Einblendungen von Erfolg und Levelaufstieg (`--rewards`).
var _logbook := false
## Nahaufnahmen der Tiere (`--fauna`).
var _fauna := false
var _rewards := false
## Trainingsseite bzw. Training im HUD (`--training`).
var _training := false
## Garderobe: gewählte Teile (`--wardrobe`; null = ohne).
var _outfit = null


func _initialize() -> void:
	var out_dir := OS.get_user_data_dir()
	var shots: Array[float] = []
	var fps_from := -1.0
	var fps_to := -1.0
	var speed_kmh := 50.0
	var size := Vector2i(1920, 1080)
	var close := false
	var pair := false
	var advance := 0.0
	var menu := false
	var title := false
	var window := ""
	var graphics := GraphicsSettings.new()
	var hour := NAN
	var date := ""
	var weather := ""
	var season := ""
	var profile := ""
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--out="):
			out_dir = value
		elif arg.begins_with("--shots="):
			for part in value.split(",", false):
				shots.append(float(part))
		elif arg.begins_with("--fps-from="):
			fps_from = float(value)
		elif arg.begins_with("--fps-to="):
			fps_to = float(value)
		elif arg.begins_with("--speed-kmh="):
			speed_kmh = float(value)
		elif arg.begins_with("--size="):
			size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
		elif arg.begins_with("--cadence="):
			_cadence = float(value)
		elif arg == "--close":
			close = true
		elif arg == "--pair":
			pair = true
		elif arg.begins_with("--advance="):
			advance = float(value)
		elif arg.begins_with("--aa="):
			graphics.aa = value
		elif arg.begins_with("--scale="):
			graphics.render_scale = float(value)
		elif arg.begins_with("--upscaler="):
			graphics.upscaler = value
		elif arg == "--vsync=off":
			graphics.vsync = false
		elif arg == "--hud":
			_hud = true
		elif arg == "--debug":
			_debug = true
		elif arg == "--menu":
			menu = true
		elif arg == "--title":
			title = true
		elif arg.begins_with("--window="):
			window = value
		elif arg.begins_with("--laps="):
			_laps = int(value)
		elif arg == "--segments":
			_segments = true
		elif arg.begins_with("--ghost="):
			_ghost_s = float(value)
		elif arg == "--logbook":
			_logbook = true
		elif arg == "--rewards":
			_rewards = true
		elif arg == "--training":
			_training = true
		elif arg.begins_with("--wardrobe"):
			_outfit = Array(value.split(",", false)) if arg.contains("=") else []
		elif arg == "--fauna":
			_fauna = true
		elif arg == "--ccw":
			_ccw = true
		elif arg.begins_with("--crop="):
			var p := value.split(",")
			_crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
		elif arg.begins_with("--time="):
			hour = float(value.get_slice(":", 0)) + float(value.get_slice(":", 1)) / 60.0
		elif arg.begins_with("--date="):
			date = value
		elif arg.begins_with("--weather="):
			weather = value
		elif arg.begins_with("--season="):
			season = value
		elif arg.begins_with("--profile="):
			profile = value
	DisplayServer.window_set_size(size)
	var config := RideConfig.load_file()
	config.bridge_autostart = false  # Prüfhilfe startet nie selbst eine Bridge (#25)
	config.track = RideConfig.TRACK_ISLAND
	_ride = load("res://scenes/main.tscn").instantiate()
	_ride.config = config
	_ride.settings_path = ""
	_ride.save_path = ""
	_ride.start_in_menu = title
	root.add_child(_ride)
	_ride.get_node("Hud").visible = _hud
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(10)
	_ride.settings_menu.settings = graphics  # erst nach `_ready` der Hauptszene vorhanden
	_ride.settings_menu.apply()
	if window == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif window in ["left", "right"]:
		_ride.settings_menu.place_half(window == "right")
	if not window.is_empty():
		await _frames(30)
	_ride.debug_label.visible = _debug
	if menu:
		_ride.settings_menu.open()
	if _hud:
		# Beispielwerte: die Hauptszene zeigt Kadenz und Watt des (ohne Bridge nicht verbundenen) Bus-Clients an.
		_ride.get_node("Hud/Message").modulate = Color.TRANSPARENT
		_ride.bus.cadence = _cadence
		_ride.bus.last_telemetry = {"cadence": _cadence, "power_w": 142.0}
	if not profile.is_empty():
		_ride.sky.set_compatibility(profile == "compat")
	_set_sky(hour, date, weather, season)
	if weather == Weather.RAIN:
		await _frames(100)
	if _ccw:
		_ride._set_direction(Track.DIRECTION_CCW)
		(_ride.start_menu.options["direction"] as OptionButton).select(1)
		_ride._new_lap_timing()
		_ride._update_round_trip_menu()
	if _laps >= 0:
		_ride.save_game.record_best_time(config.track, _ride.track.direction, LAP_SAMPLES_S[0])
		_ride.laps = _laps
		_ride._update_round_trip_menu()
		(_ride.start_menu.options["laps"] as OptionButton).select(_ride.start_menu.LAP_CHOICES.find(_laps))
		if not is_nan(_ghost_s):
			for kind in [Ghost.BEST, Ghost.LAST]:
				_ride.save_game.record_ghost(config.track, _ride.track.direction, kind, _sample_ghost(22.0 / 3.6))
			_ride._update_round_trip_menu()
	if _outfit != null:
		_dress()
	if title:
		if _outfit != null:
			await _wardrobe_shot(out_dir)
		elif _logbook:
			await _logbook_shots(out_dir)
		else:
			await _title_shots(out_dir)
		quit(0)
		return
	_model = _ride.rider_model  # erst nach `_ready` der Hauptszene gesetzt
	var dummy := RiderModel.new()
	_ride.rider_model = dummy
	for d in shots:
		_place(d)
		_pedal(1.0)
		await _frames(8)
		_save(out_dir.path_join("shot_%d.png" % int(d)))
		if pair:
			_pedal(0.15)
			if advance > 0.0 and _ride.world != null:
				_ride.world.motion.advance(advance)
			await _frames(2)
			_save(out_dir.path_join("shot_%d_b.png" % int(d)))
		if close:
			await _close_ups(out_dir, d)
	if _fauna and _ride.world != null:
		await _fauna_shots(out_dir)
	if _segments:
		await _segment_shots(out_dir)
	if _rewards and _hud:
		await _reward_shots(out_dir)
	if _training and _hud:
		await _training_shots(out_dir)
	if fps_to > fps_from:
		await _measure(fps_from, fps_to, speed_kmh / 3.6)
	if _laps >= 0 and _hud:
		await _result_shot(out_dir)
	_ride.rider_model = _model  # die Hauptszene läuft bis zum Beenden noch einen Frame weiter
	dummy.free()
	quit(0)


## Feste Uhrzeit/Datum/Wetter/Jahreszeit (siehe Kopf); leere Angaben lassen `[sky]` gelten.
func _set_sky(hour: float, date: String, weather: String, season: String) -> void:
	var sky: SkyController = _ride.sky
	if not is_nan(hour):
		sky.set_time_mode(DayNight.MODE_FIXED, hour)
	if not date.is_empty():
		var parts := date.split("-")
		sky.clock.set_mode(DayNight.MODE_FIXED)
		sky.clock.unix_s = DayNight.local_to_unix(int(parts[0]), int(parts[1]), int(parts[2]), sky.clock.fixed_hour)
	if not weather.is_empty():
		sky.set_weather_mode(Weather.MODE_FIXED, weather)
		sky.weather.snap()
	if not season.is_empty():
		sky.set_season_mode(Season.MODE_FIXED, season)
	sky.apply_now()
	print("SKY local=%.2f h sun=%.1f°/%.1f° weather=%s season=%s compat=%s lights=%s" % [sky.clock.local_hour(),
			sky.sun_angles.x, sky.sun_angles.y, sky.weather.state, sky.season(), sky.compatibility, sky.current["lights_on"]])


## Titelbild mit Startmenü (Hauptseite, Seite „Fahren“) und ein Bild 3 s später (Kameraflug).
func _title_shots(out_dir: String) -> void:
	await _frames(20)
	_save_image(out_dir.path_join("title.png"))
	_ride.start_menu.show_page(true)
	await _frames(4)
	_save_image(out_dir.path_join("title_modes.png"))
	if _laps >= 0:
		_ride.start_menu.show_round_trip()
		await _frames(4)
		_save_image(out_dir.path_join("title_round_trip.png"))
	if _training:
		_ride.start_menu.show_training()
		await _frames(4)
		_save_image(out_dir.path_join("title_training.png"))
	_ride.start_menu.show_page(false)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		await process_frame
	_save_image(out_dir.path_join("title_b.png"))


## Fahrtenbuch mit Beispielstand (nur im Speicher): je Seite ein Bild.
func _logbook_shots(out_dir: String) -> void:
	var save: SaveGame = _ride.save_game
	var track := RideConfig.TRACK_ISLAND
	for i in range(24):
		var stats := RideStats.new()
		var laps := 1 + i % 3
		stats.add(LAP_SAMPLES_S[1 + i % 4] * laps, 84.0 + i % 7, 9210.0 * laps)
		save.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, track, i % 5 != 0, laps, stats,
				"2026-09-%02dT%02d:30:00Z" % [1 + i, 6 + i % 15]))
	save.record_best_time(track, LapTiming.DIRECTION_CW, LAP_SAMPLES_S[2])
	save.record_medal(track, LapTiming.DIRECTION_CW, Medals.LAP, Medals.SILVER)
	var medals := [Medals.GOLD, Medals.SILVER, Medals.BRONZE]
	for i in range(_ride.track.segments.size()):
		var segment: Dictionary = _ride.track.segments[i]
		save.record_segment_time(track, LapTiming.DIRECTION_CW, segment["id"],
				_ride.medal_limits[segment["id"]][medals[i]] - 1.0)
		save.record_medal(track, LapTiming.DIRECTION_CW, segment["id"], medals[i])
	for id in ["km_1", "km_10", "km_100", "ride_km_20", "laps_1", "laps_10", "ride_laps_3", "morning", "evening",
			"night", "clear", "clouds", "rain"]:
		save.unlock_achievement(id, "2026-09-%02dT18:00:00Z" % (1 + id.length()))
	await _frames(20)
	_ride.start_menu.buttons["logbook"].pressed.emit()
	for page in ["overview", "achievements", "rides"]:
		_ride.logbook.show_page(page)
		await _frames(4)
		_save_image(out_dir.path_join("logbook_%s.png" % page))


## Garderobe (nur im Speicher): Kilometer bis Level 12, dann die Teile aus `--wardrobe` wählen; der Fahrer trägt sie.
func _dress() -> void:
	var stats := RideStats.new()
	var km := DriverLevel.km_for(12)
	stats.add(km * 150.0, 85.0, km * 1000.0)
	_ride.save_game.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, false, 0, stats,
			"2026-09-20T18:00:00Z"))
	for item in _outfit:
		if not Wardrobe.choose(_ride.save_game, item):
			push_warning("view_probe: Teil %s unbekannt oder gesperrt" % item)
	_ride._apply_wardrobe()


## Garderobe aus dem Startmenü mit Vorschau.
func _wardrobe_shot(out_dir: String) -> void:
	await _frames(20)
	_ride.start_menu.buttons["wardrobe"].pressed.emit()
	await _frames(30)
	_save_image(out_dir.path_join("wardrobe.png"))


## Einblendungen wie in der Fahrt: ein neuer Erfolg, danach ein Levelaufstieg (die laufende Einblendung beendet).
func _reward_shots(out_dir: String) -> void:
	_ride.hud.end_celebration()
	_ride._achievement_event({"type": Achievements.EVENT_WEATHER, "state": Weather.RAIN})
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("achievement.png"))
	_ride.hud.end_celebration()
	_ride._km_before = DriverLevel.km_for(3) - _ride.stats.distance_m / 1000.0
	_ride._check_level()
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("level_up.png"))


## Training „Intervalle kurz“ an der aktuellen Position: 7,5 s vor der ersten harten Phase (Ansage im HUD), danach die
## ganze Einheit mit Beispieltreffern (jede dritte Phase knapp daneben) bis zum Ergebnis.
func _training_shots(out_dir: String) -> void:
	var unit: Dictionary = Training.load_all()[0]
	var training := Training.new(unit)
	training.advance(_cadence, unit["phases"][0]["duration_s"] - 7.5)
	_ride.ride_mode = SaveGame.MODE_TRAINING
	_ride.training = training
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 0)
	_ride.lap_timing.advance(_ride.model.distance_m, _ride.stats.ride_time_s)
	_ride.hud.end_celebration()
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("training.png"))
	for i in range(training.phase_index(), training.phases.size()):
		var phase: Dictionary = training.phases[i]
		var cadence: float = (phase["cadence_min"] + phase["cadence_max"]) / 2.0
		training.advance(cadence, training.remaining_s() * 0.8)
		training.advance(cadence - 12.0 if i % 3 == 1 else cadence, training.remaining_s())
	_ride.stats = RideStats.new()
	_ride.stats.add(training.duration_s(), 88.0, training.duration_s() * 22.0 / 3.6)
	_ride._finish_ride()  # wie im Spiel: Erfolg „Erste Einheit“, Spielstand nur im Speicher (save_path "")
	_ride.get_node("Hud/Message").modulate = Color.WHITE
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("training_result.png"))


func _save_image(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT %s window=%s+%s mode=%d camera=%s" % [path, DisplayServer.window_get_position(),
		DisplayServer.window_get_size(), DisplayServer.window_get_mode(), _ride.camera.global_position])


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	if _crop.has_area() and path.get_file().begins_with("shot_"):
		image.get_region(_crop).save_png(path.get_base_dir().path_join(path.get_file().replace("shot_", "crop_")))
	print("SHOT %s station=%s crank=%.0f° lean=%.1f° bend=%.1f°" % [path, _ride.current_station(),
		rad_to_deg(_model.motion.crank_angle), rad_to_deg(_model.motion.lean), rad_to_deg(_model.motion.bend)])


## Bewegt das echte Modell `seconds` lang mit `_cadence` und dem passenden Tempo des Fahrmodells.
func _pedal(seconds: float, dt: float = 1.0 / 60.0) -> void:
	var grade: float = _ride.current_grade()
	var speed: float = _ride.model.target_speed_mps(_cadence, grade)
	for i in range(maxi(int(seconds / dt), 1)):
		_model.update(_cadence, speed, grade, _ride.current_curvature(), false, dt)


## Nahaufnahmen von der Seite (rechts) und schräg von hinten links; die Kamera der Hauptszene ruht so lange.
func _close_ups(out_dir: String, d: float) -> void:
	_ride.set_process(false)
	var at: Transform3D = _ride.rider.global_transform
	var camera: Camera3D = _ride.camera
	var views := {
		"side": at.origin + at.basis.x * 3.2 + Vector3.UP * 1.0,
		"rear": at.origin + at.basis.z * 2.6 - at.basis.x * 1.6 + Vector3.UP * 1.7,
	}
	for view in views:
		camera.global_position = views[view]
		camera.look_at(at.origin + Vector3.UP * 0.75, Vector3.UP)
		await _frames(4)
		_save(out_dir.path_join("close_%d_%s.png" % [int(d), view]))
	_ride.set_process(true)
	_place(d)


## Je Tierart das erste Tier (Herdentiere zuerst) aus der Nähe, Blick von der Straßenseite; zweites Bild 2,5 s
## Tieranimation später. Fahrer und Kamera der Hauptszene ruhen so lange.
func _fauna_shots(out_dir: String) -> void:
	var fauna: IslandFauna = _ride.world.fauna
	var track: Track = _ride.track
	fauna.set_process(false)
	for kind in IslandFauna.KINDS:
		var all := fauna.positions(kind)
		if all.is_empty():
			continue
		var target: Vector3 = all[0]
		var d := track.curve.get_closest_offset(target)
		_place(track.path_distance(d))
		await _frames(4)
		_ride.set_process(false)
		var road := track.position_at(d)
		var towards := Vector3(road.x - target.x, 0.0, road.z - target.z).normalized()
		var distance: float = {"Schafe": 6.0, "Ziegen": 6.0, "Esel": 4.5, "Katzen": 2.2, "Delfine": 12.0, "Fische": 3.5,
				"Geier": 9.0, "Schmetterlinge": 1.0, "Eidechsen": 0.9}[kind]
		var small: bool = kind in ["Schmetterlinge", "Eidechsen"]
		var camera: Camera3D = _ride.camera
		var eye := target + towards * distance + Vector3.UP * (0.9 if kind == "Katzen" else 0.4 if small else 1.8)
		eye.y = maxf(eye.y, _ride.world.terrain.height_at(eye.x, eye.z) + 0.8)
		# Springende Tiere (#41): erstes Bild im Sprung, zweites 0,25 s später; sonst 2,5 s Tieranimation dazwischen.
		var t := 2.0
		var leaping: bool = kind in ["Delfine", "Fische"]
		fauna.apply(t, fauna.rider_path_m)
		while leaping and fauna.positions(kind)[0].y < 0.2 and t < 30.0:
			t += 0.05
			fauna.apply(t, fauna.rider_path_m)
		for suffix in ["", "_b"]:
			fauna.apply(t if suffix.is_empty() else t + (0.25 if leaping else 2.5), fauna.rider_path_m)
			var now: Vector3 = fauna.positions(kind)[0]
			if small and suffix.is_empty():
				eye = now + towards * distance + Vector3.UP * 0.4
			camera.global_position = eye
			camera.look_at(now + Vector3.UP * (0.15 if kind == "Katzen" else 0.0 if small or leaping else 0.6), Vector3.UP)
			await _frames(4)
			_save(out_dir.path_join("fauna_%s%s.png" % [kind, suffix]))
		_ride.set_process(true)
	fauna.set_process(true)


## Fahrer an Position `d`, Kamera sofort dahinter. Mit `--hud`: Tempo des Fahrmodells, Strecke und Zeit bis hier
## (Beispiel: Ø 22 km/h); mit `--laps` in Runde 2 nach einer Beispielrunde mit neuer Bestzeit.
func _place(d: float) -> void:
	_ride.model.distance_m = d
	if _hud:
		_ride.model.speed_mps = _ride.model.target_speed_mps(_cadence, _ride.current_grade())
		_ride.stats.distance_m = d
		_ride.stats.ride_time_s = d / (22.0 / 3.6)
	if _hud and _laps >= 0:
		var lap: float = _ride.track.length_m()
		_ride.lap_timing = LapTiming.new(lap, 0.0, _laps, LAP_SAMPLES_S[0])
		_ride.lap_timing.advance(lap, LAP_SAMPLES_S[2])
		_ride.lap_timing.advance(lap + d, d / (22.0 / 3.6))
		_ride.model.distance_m = lap + d
		_ride.stats.ride_time_s += LAP_SAMPLES_S[2]
		_ride.stats.distance_m += lap
		_ride.hud.celebrate("Neue Bestzeit!  %s" % _ride.format_time(LAP_SAMPLES_S[2], true))
	if not is_nan(_ghost_s):
		if not (_hud and _laps >= 0):  # sonst steht die Rundenwertung schon in Runde 2 bei `d`
			_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 1)
			_ride.lap_timing.advance(d, d / (22.0 / 3.6))
		_ride.ghost = _sample_ghost(22.0 / 3.6)
		_ride.ghost_rider.visible = true
	_ride._update_view()
	_ride._update_camera(0.0, true)


## Beispiel-Ghost mit festem Tempo `mps`, gegen den ein Fahrer mit demselben Tempo `_ghost_s` Sekunden zurückliegt.
func _sample_ghost(mps: float) -> Ghost:
	var lap: float = _ride.track.length_m()
	var ghost := Ghost.new(lap)
	if _ghost_s >= 0.0:
		ghost.record(mps * (1.0 + _ghost_s), 1.0)  # vorweg: in der ersten Sekunde den Vorsprung herausgefahren
	else:
		ghost.record(0.0, -_ghost_s)  # zurück: steht so lange an der Linie
	ghost.finish(lap / mps - _ghost_s)
	return ghost


## Ergebnis einer Rundfahrt über `--laps` Runden (endlos: drei Runden, dann „Fahrt beenden“) mit Beispielzeiten.
func _result_shot(out_dir: String) -> void:
	var lap: float = _ride.track.length_m()
	var count := _laps if _laps > 0 else 3
	_ride.lap_timing = LapTiming.new(lap, 0.0, _laps, LAP_SAMPLES_S[0], _ride.track.segments)
	_ride.stats = RideStats.new()
	for i in range(count):
		var t: float = LAP_SAMPLES_S[1 + i % (LAP_SAMPLES_S.size() - 1)]
		_ride.lap_timing.advance(lap * (i + 1), t)
		_ride.stats.add(t, 86.0, lap)
	_ride.model.distance_m = lap * count
	_ride._finish_ride()  # wie im Spiel: Einblendung aus, Spielstand nur im Speicher (save_path "")
	_ride.get_node("Hud/Message").modulate = Color.WHITE
	_ride._update_view()
	_ride._update_camera(0.0, true)
	await _frames(8)
	_save_image(out_dir.path_join("result.png"))


## Je Segment: Fahrer bei 40 % des Segments (HUD mit Live-Zeit), dann 15 m hinter dem Ende (Ergebnis beim
## Verlassen). Beispielfahrt: das Segment in knapp der Silber-Zeit, vorher 22 km/h.
func _segment_shots(out_dir: String) -> void:
	var celebration: Control = _ride.hud.get_node("%Celebration")
	for segment in _ride.track.segments:
		var start: float = segment["start_m"]
		var length: float = segment["end_m"] - start
		var inside_mps: float = length / (_ride.medal_limits[segment["id"]][Medals.SILVER] - 1.0)
		var timing := LapTiming.new(_ride.track.length_m(), 0.0, 0, INF, _ride.track.segments)
		timing.advance(start, start / (22.0 / 3.6))
		timing.advance(start + 0.4 * length, 0.4 * length / inside_mps)
		_place(start + 0.4 * length)  # setzt mit `--laps` eine eigene Rundenwertung – danach ersetzen
		_ride.lap_timing = timing
		_ride.model.distance_m = start + 0.4 * length
		celebration.hide()
		_ride._update_view()
		_pedal(1.0)
		await _frames(8)
		_save_image(out_dir.path_join("segment_%s.png" % segment["id"]))
		timing.advance(segment["end_m"], 0.6 * length / inside_mps)
		timing.advance(segment["end_m"] + 15.0, 15.0 / inside_mps)
		_place(segment["end_m"] + 15.0)
		_ride.lap_timing = timing
		_ride.model.distance_m = segment["end_m"] + 15.0
		_ride.hud.celebrate(_ride.segment_result_text(timing.segments.results[-1]))
		_ride._update_view()
		_ride._update_camera(0.0, true)
		_pedal(0.2)
		await _frames(8)
		_save_image(out_dir.path_join("segment_%s_result.png" % segment["id"]))


func _frames(count: int) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw


## Fährt von `from` bis `to` mit `speed` m/s (eigener Vorschub, das Fahrmodell steht ohne Bus) und misst die
## Frame-Zeiten. Die erste Sekunde (Aufwärmen) zählt nicht.
func _measure(from: float, to: float, speed: float) -> void:
	_place(from)
	if not is_nan(_ghost_s):  # Ghost im Tempo der Messfahrt; die Rundenwertung läuft mit, damit er mitfährt
		_ride.ghost = _sample_ghost(speed)
		_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 1)
		_ride.lap_timing.advance(from, from / speed)
	await _frames(30)
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var d := from
	var warmup := 1.0
	while d < to:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		d += speed * dt
		_ride.model.distance_m = d
		if not is_nan(_ghost_s):
			_ride.lap_timing.advance(d, dt)
		var grade: float = _ride.current_grade()
		_model.update(_cadence, speed, grade, _ride.current_curvature(), false, dt)
		if warmup > 0.0:
			warmup -= dt
			continue
		times.append(dt)
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var worst := sorted[sorted.size() - 1]
	var low_1 := sorted[int(sorted.size() * 0.99)]
	var slow := 0
	for t in times:
		if t > 1.0 / 50.0:
			slow += 1
	print("FPS from=%.0f to=%.0f speed_kmh=%.0f frames=%d mean=%.1f min=%.1f low1pct=%.1f below50=%d size=%s vsync=%s adapter=%s" % [
		from, to, speed * 3.6, times.size(), times.size() / total, 1.0 / worst, 1.0 / low_1, slow,
		DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), RenderingServer.get_video_adapter_name()])
