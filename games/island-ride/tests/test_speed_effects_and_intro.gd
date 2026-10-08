## Tempo-Effekte und Kamera-Intro (#42): Geschwindigkeitslinien und Sichtfeld-Kick erst ab etwa 35 km/h, stetig
## steigend, im Einstellungsmenü abschaltbar und gespeichert; das Kamera-Intro beim Fahrtstart endet nach seiner Zeit,
## in beiden Richtungen und im Training, und lässt Fahrmodell und Rundenzeit unberührt (ADR-0010).
extends "res://tests/support/bus_test.gd"

const SETTINGS_PATH := "user://test_speed_effects_settings.cfg"
const DT := 1.0 / 60.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func test_strength_is_zero_below_35_kmh_and_rises_smoothly_above() -> void:
	for kmh in [0.0, 12.0, 25.0, 34.9, 35.0]:
		assert_eq(SpeedEffects.strength_for(kmh), 0.0, "%.1f km/h: aus" % kmh)
	assert_gt(SpeedEffects.strength_for(40.0), 0.0, "40 km/h: an")
	assert_eq(SpeedEffects.strength_for(SpeedEffects.FULL_KMH), 1.0, "voll ab FULL_KMH")
	assert_eq(SpeedEffects.strength_for(90.0), 1.0)
	var before := 0.0
	var worst := 0.0
	for i in range(1, 801):
		var now := SpeedEffects.strength_for(i * 0.1)
		assert_true(now >= before, "steigt mit dem Tempo (%.1f km/h)" % (i * 0.1))
		worst = maxf(worst, now - before)
		before = now
	assert_lt(worst, 0.01, "ohne Sprünge (je 0,1 km/h)")
	assert_between(SpeedEffects.FOV_KICK_DEG, 2.0, 8.0, "leichter Kick: wenige Grad")


func test_effects_glide_and_switch_off_at_once() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	var effects := SpeedEffects.new()
	add_child_autofree(effects)
	effects.setup(camera)
	var base := camera.fov
	effects.update(25.0, 1.0)
	assert_eq(effects.strength, 0.0, "25 km/h: keine Linien")
	assert_false(effects.lines.visible)
	assert_eq(camera.fov, base, "Sichtfeld wie eingestellt")
	effects.update(55.0, DT)
	assert_between(effects.strength, 0.0001, 0.2, "weich statt Sprung")
	for i in range(120):
		effects.update(55.0, DT)
	assert_almost_eq(effects.strength, SpeedEffects.strength_for(55.0), 0.01, "55 km/h: fast volle Stärke")
	assert_true(effects.lines.visible, "Linien sichtbar")
	assert_almost_eq(camera.fov, base + SpeedEffects.FOV_KICK_DEG * effects.strength, 0.001, "Kick nach Stärke")
	effects.enabled = false
	effects.update(55.0, DT)
	assert_eq(effects.strength, 0.0, "abgeschaltet: sofort aus")
	assert_false(effects.lines.visible)
	assert_eq(camera.fov, base)


## Hauptszene auf der Graybox am Fake-Bus mit eigener Einstellungsdatei; 90 rpm ohne Trägheit, `k` km/h je rpm.
func _spawn(k: float) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 30.0))
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = k
	var ride := MAIN_SCENE.instantiate()
	ride.config = config
	ride.quit_on_request = false
	ride.settings_path = SETTINGS_PATH
	ride.save_path = ""
	ride.start_in_menu = false
	add_child_autofree(ride)
	return ride


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func test_ride_shows_effects_from_speed_and_menu_switch_is_saved() -> void:
	var ride := _spawn(0.6)  # 90 rpm → 54 km/h
	var camera: Camera3D = ride.camera
	var base: float = ride.speed_effects.base_fov
	assert_true(ride.speed_effects.enabled, "Standard: an")
	assert_true(await run_until(func(): return ride.state == "riding", 3.0), "fährt")
	await run_for(1.5)
	assert_almost_eq(ride.model.speed_kmh(), 54.0, 0.5, "Tempo nur aus Kadenz (ADR-0010)")
	assert_gt(ride.speed_effects.strength, 0.8, "54 km/h: Linien")
	assert_gt(camera.fov, base + 3.0, "Sichtfeld weiter")
	_choose(ride.settings_menu, "speed_effects", false)
	await run_for(0.1)
	assert_eq(ride.speed_effects.strength, 0.0, "im Menü abgeschaltet")
	assert_eq(camera.fov, base)
	assert_almost_eq(ride.model.speed_kmh(), 54.0, 0.5, "Fahrt unverändert")
	assert_false(GraphicsSettings.load_file(SETTINGS_PATH).speed_effects, "gespeichert")
	remove_child(ride)
	ride.free()
	var again := _spawn(0.6)
	assert_false(again.speed_effects.enabled, "nach Neustart aus")
	assert_eq(again.settings_menu.options["speed_effects"].selected, 1, "Menü zeigt „Aus“")
	_choose(again.settings_menu, "speed_effects", true)
	assert_true(again.speed_effects.enabled)
	assert_true(GraphicsSettings.load_file(SETTINGS_PATH).speed_effects)


func test_slow_ride_and_pause_show_no_effects() -> void:
	var ride := _spawn(0.28)  # 90 rpm → 25 km/h
	assert_true(await run_until(func(): return ride.state == "riding", 3.0), "fährt")
	await run_for(1.0)
	assert_almost_eq(ride.model.speed_kmh(), 25.2, 0.5)
	assert_eq(ride.speed_effects.strength, 0.0, "25 km/h: keine Effekte")
	assert_eq(ride.camera.fov, ride.speed_effects.base_fov)


## Hauptszene wie beim Spielstart (Startmenü) auf der Insel am Fake-Bus, ohne Trägheit.
func _spawn_game() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 30.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.inertia_s = 0.0
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = ""
	add_child_autofree(game)
	return game


## Kamera vor (+) oder hinter (−) dem Fahrer, in Fahrtrichtung gemessen.
func _camera_ahead(game: Node) -> float:
	var d: float = game.model.distance_m
	var at: Vector3 = game.track.to_global(game.track.ride_position_at(d))
	var forward: Vector3 = (game.track.to_global(game.track.ride_position_at(d + 1.0)) - at).normalized()
	return (game.camera.global_position - at).dot(forward)


## Fahrtstart mit Intro: Kamera beginnt vor dem Fahrer; dann Bild für Bild (DT) fahren, bis das Intro vorbei ist –
## Fahrmodell und Rundenzeit wie ein Fahrmodell ohne Kamera, danach folgt die Kamera von hinten.
func _check_intro(game: Node, label: String) -> void:
	assert_eq(game.camera_mode, game.CAMERA_INTRO, "%s: Intro beginnt" % label)
	assert_gt(_camera_ahead(game), 2.0, "%s: Kamera zuerst vor dem Fahrer" % label)
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "%s: fährt während des Intros los" % label)
	assert_eq(game.camera_mode, game.CAMERA_INTRO, "%s: Intro läuft noch" % label)
	game.set_process(false)
	var reference := RideModel.new(game.config, game.model.distance_m)
	reference.speed_mps = game.model.speed_mps
	var lap_time: float = game.lap_timing.lap_time_s
	var shown: float = game.camera_shot_s
	var steps := 0
	while game.camera_mode == game.CAMERA_INTRO and steps < 1000:
		game._ride(DT)
		reference.step(90.0, game.track.grade_at(reference.distance_m), DT)
		game._update_camera(DT)
		steps += 1
	assert_almost_eq(shown + steps * DT, game.CAMERA_INTRO_S, DT * 1.01, "%s: Intro endet nach seiner Zeit" % label)
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW, "%s: danach Folgekamera" % label)
	assert_almost_eq(game.model.distance_m, reference.distance_m, 0.0001, "%s: Fahrmodell unberührt" % label)
	assert_almost_eq(game.lap_timing.lap_time_s, lap_time + steps * DT, 0.0001, "%s: Rundenzeit läuft normal" % label)
	assert_lt(_camera_ahead(game), -3.0, "%s: Kamera hinter dem Fahrer" % label)
	game.set_process(true)


func test_camera_intro_on_ride_start_in_both_directions_and_in_training() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW, "Titelbild: kein Intro")
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CW)
	await _check_intro(game, "cw")
	game.return_to_menu()
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CCW)
	await _check_intro(game, "ccw")
	game.return_to_menu()
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_all()[0])
	await _check_intro(game, "Training")
