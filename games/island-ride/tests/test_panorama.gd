## Panorama-Momente (#43): An jeder vorhandenen Sehenswürdigkeit schwenkt die Kamera einmal je Runde kurz aus und das
## HUD blendet den Namen ein – in beiden Richtungen, nicht mit Ghost, nicht im Training, nicht während des Intros und
## nicht, wenn im Einstellungsmenü abgeschaltet (gespeichert). Die Kamera kehrt ohne Sprung hinter den Fahrer zurück;
## Fahrmodell und Rundenzeiten bleiben unberührt (ADR-0010, Gegenprobe mit abgeschalteten Panoramen).
extends "res://tests/support/bus_test.gd"

var SETTINGS_PATH := TestIsolation.path("test_panorama_settings.cfg")
## Zeitschritt der Fahrten (s): grob genug für zwei Runden je Richtung, fein genug für einen Schwenk (40 Schritte).
const DT := 0.1


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


## Hauptszene wie beim Spielstart auf der Insel am Fake-Bus: 90 rpm, 0,4 km/h je rpm (36 km/h flach). Die Trägheit
## bleibt wie in config.cfg – ohne sie überschriebe jeder Schritt die Geschwindigkeit, und ein Bremsen im Panorama fiele
## nicht auf.
func _spawn_game(settings_path: String = "") -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 600.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.k_kmh_per_rpm = 0.4
	game.config = config
	game.quit_on_request = false
	game.settings_path = settings_path
	game.save_path = ""
	add_child_autofree(game)
	return game


## Fahrtposition des Auslösepunkts einer Sehenswürdigkeit in der gewählten Richtung.
func _ride_m(game: Node, spot: Dictionary) -> float:
	return game.track.path_distance(spot["path_m"])


## Fährt die laufende Fahrt Schritt für Schritt (DT) bis ins Ziel, mit einem Fahrmodell ohne Kamera daneben.
## Ergebnis: {panoramas: [{id, name, lap, label}], intro_end_m, worst_step_m, worst_return_m, behind_after,
## model_drift_m}. `model_drift_m`: größte Abweichung der Fahrtposition vom Fahrmodell daneben bis ins Ziel.
## `worst_step_m`: größte Bewegung der Kamera relativ zum Fahrer in einem Schritt während eines Panoramas;
## `worst_return_m`: wie viel diese Bewegung beim Wechsel zurück in die Folgekamera und im Schritt danach gegenüber dem
## Schritt davor zunimmt (ein Sprung wäre ein plötzlich großer Schritt; die Glättung klingt dagegen nur ab).
func _drive(game: Node) -> Dictionary:
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	game.set_process(false)
	var reference := RideModel.new(game.config, game.model.distance_m)
	reference.speed_mps = game.model.speed_mps
	var result := {"panoramas": [], "worst_step_m": 0.0, "worst_return_m": 0.0, "behind_after": true,
			"intro_end_m": NAN if game.camera_mode == game.CAMERA_INTRO else game.model.distance_m, "model_drift_m": 0.0}
	var mode: String = game.camera_mode
	var camera: Vector3 = game.camera.global_position
	var rider := _rider_at(game)
	var returning := 0
	var last_relative := 0.0
	var steps := 0
	while game.state == "riding" and steps < 60000:
		game._ride(DT)
		reference.step(90.0, game.track.grade_at(reference.distance_m), DT)
		game._update_camera(DT)
		steps += 1
		if game.state == "riding":
			result["model_drift_m"] = maxf(result["model_drift_m"], absf(game.model.distance_m - reference.distance_m))
		var now_rider := _rider_at(game)
		var relative: float = ((game.camera.global_position - camera) - (now_rider - rider)).length()
		camera = game.camera.global_position
		rider = now_rider
		if mode == game.CAMERA_INTRO and game.camera_mode != game.CAMERA_INTRO:
			result["intro_end_m"] = game.model.distance_m
		if game.camera_mode == game.CAMERA_PANORAMA and mode != game.CAMERA_PANORAMA:
			result["panoramas"].append({"id": game.panorama["id"], "name": game.panorama["name"],
					"lap": game.lap_timing.lap_number(), "label": game.hud.landmark()})
		elif game.camera_mode == game.CAMERA_PANORAMA:
			result["worst_step_m"] = maxf(result["worst_step_m"], relative)
		if mode == game.CAMERA_PANORAMA and game.camera_mode == game.CAMERA_FOLLOW:
			returning = 2
		if returning > 0:
			result["worst_return_m"] = maxf(result["worst_return_m"], relative - last_relative)
			returning -= 1
			if returning == 0:
				for i in range(30):  # danach ruhig wieder hinter dem Fahrer (3 s Folgekamera ohne Fahrt)
					game._update_camera(DT)
				result["behind_after"] = result["behind_after"] and _camera_ahead(game) < -3.0
				camera = game.camera.global_position
		mode = game.camera_mode
		last_relative = relative
	game.set_process(true)
	return result


func _rider_at(game: Node) -> Vector3:
	return game.track.to_global(game.track.ride_position_at(game.model.distance_m))


## Kamera vor (+) oder hinter (−) dem Fahrer, in Fahrtrichtung gemessen.
func _camera_ahead(game: Node) -> float:
	var d: float = game.model.distance_m
	var at: Vector3 = game.track.to_global(game.track.ride_position_at(d))
	var forward: Vector3 = (game.track.to_global(game.track.ride_position_at(d + 1.0)) - at).normalized()
	return (game.camera.global_position - at).dot(forward)


## Zwei Runden: in Runde 2 jede Sehenswürdigkeit genau einmal, in Runde 1 jede höchstens einmal und jede hinter dem
## Intro; Name im HUD, Rückkehr ohne Sprung, Fahrmodell unberührt.
func _check_two_laps(game: Node, label: String) -> Array:
	var run := await _drive(game)
	var spots: Array = game.panorama_spots
	assert_eq(game.state, "finished", "%s: im Ziel" % label)
	assert_almost_eq(run["model_drift_m"], 0.0, 0.0001, "%s: Fahrmodell unberührt (ADR-0010)" % label)
	for lap in [1, 2]:
		for spot in spots:
			var count := 0
			for p in run["panoramas"]:
				if p["lap"] == lap and p["id"] == spot["id"]:
					count += 1
					assert_eq(p["label"], spot["name"], "%s: Name eingeblendet (%s)" % [label, spot["id"]])
			var expected := 1 if lap == 2 or _ride_m(game, spot) > run["intro_end_m"] + 1.0 else 0
			assert_eq(count, expected, "%s Runde %d: %s" % [label, lap, spot["id"]])
	assert_gt(run["worst_step_m"], 0.3, "%s: die Kamera schwenkt aus" % label)
	assert_lt(run["worst_step_m"], 3.0, "%s: weich, ohne Sprung" % label)
	assert_lt(run["worst_return_m"], 0.05, "%s: Rückkehr in die Folgekamera ohne Sprung" % label)
	assert_true(run["behind_after"], "%s: danach wieder hinter dem Fahrer" % label)
	return game.lap_timing.lap_times.duplicate()


func test_panorama_once_per_lap_at_every_landmark_in_both_directions_and_off_changes_no_time() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	var ids: Array = game.panorama_spots.map(func(s): return s["id"])
	for id in ["aussichtspunkt", "leuchtturm", "cala", "talaia", "ermita", "burg", "aquaedukt", "windmuehlen"]:
		assert_has(ids, id, "Sehenswürdigkeit %s" % id)
	assert_eq(ids.size(), 8, "nur die vorhandenen Sehenswürdigkeiten")
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 2, "", {}, Track.DIRECTION_CW)
	var with_panorama := await _check_two_laps(game, "cw")
	game.return_to_menu()
	game.return_to_menu()
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 2, "", {}, Track.DIRECTION_CCW)
	await _check_two_laps(game, "ccw")
	game.return_to_menu()
	game.return_to_menu()
	# Gegenprobe: abgeschaltet kein einziges Panorama, dieselben Rundenzeiten
	game.panorama_enabled = false
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 2, "", {}, Track.DIRECTION_CW)
	var run := await _drive(game)
	assert_eq(run["panoramas"].size(), 0, "abgeschaltet: kein Panorama")
	assert_eq(game.lap_timing.lap_times.size(), 2)
	for i in range(2):
		assert_almost_eq(game.lap_timing.lap_times[i], with_panorama[i], 0.0001,
				"Runde %d: gleiche Zeit mit und ohne Panorama (ADR-0010)" % (i + 1))


## Fahrer kurz vor den Auslösepunkt von `spot` setzen, im Tempo von 90 rpm (ohne dass der Sprung selbst etwas auslöst).
func _warp_before(game: Node, spot: Dictionary) -> void:
	game.model.distance_m = _ride_m(game, spot) - 20.0
	game.model.speed_mps = game.model.target_speed_mps(90.0, 0.0)
	game._update_camera(0.0, true)


## `steps` Schritte (DT) fahren; true, wenn dabei ein Panorama lief.
func _panorama_within(game: Node, steps: int) -> bool:
	var seen := false
	for i in range(steps):
		game._ride(DT)
		game._update_camera(DT)
		seen = seen or game.camera_mode == game.CAMERA_PANORAMA
	return seen


func test_no_panorama_with_ghost_in_training_or_during_the_intro() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	var spots := {}
	for spot in game.panorama_spots:
		spots[spot["id"]] = spot
	# Ghost: keiner – Gegenprobe ohne Ghost an der nächsten Sehenswürdigkeit
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CW)
	var ghost := Ghost.new(game.track.length_m())
	ghost.finish(game.track.length_m() / 10.0)
	game.ghost = ghost
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	await run_until(func(): return game.camera_mode == game.CAMERA_FOLLOW, 5.0)
	game.set_process(false)
	assert_true(game.ghost_active())
	_warp_before(game, spots["talaia"])
	assert_false(_panorama_within(game, 60), "mit Ghost: kein Panorama")
	game.ghost = null
	_warp_before(game, spots["aussichtspunkt"])
	assert_true(_panorama_within(game, 60), "Gegenprobe ohne Ghost: Panorama")
	game.set_process(true)
	game.return_to_menu()
	game.return_to_menu()
	# Training (im Uhrzeigersinn)
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_all()[0])
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Training fährt")
	await run_until(func(): return game.camera_mode == game.CAMERA_FOLLOW, 5.0)
	game.set_process(false)
	assert_true(game.training_active())
	_warp_before(game, spots["talaia"])
	assert_false(_panorama_within(game, 60), "im Training: kein Panorama")
	game.set_process(true)
	game.return_to_menu()
	game.return_to_menu()
	# Intro: der Auslösepunkt liegt im Intro – kein Panorama, auch nicht nachgeholt
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CW)
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	game.set_process(false)
	assert_eq(game.camera_mode, game.CAMERA_INTRO, "Intro läuft")
	_warp_before(game, spots["leuchtturm"])
	game.camera_shot_s = 0.0  # das Intro beginnt hier von vorn (3 s ≈ 30 m)
	assert_false(_panorama_within(game, 80), "während des Intros: kein Panorama, danach nicht nachgeholt")
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW, "Intro vorbei")
	game.set_process(true)


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func test_switch_in_settings_menu_is_saved() -> void:
	var game := _spawn_game(SETTINGS_PATH)
	assert_true(game.panorama_enabled, "Standard: an")
	assert_eq(game.settings_menu.options["panorama"].selected, 0, "Menü zeigt „An“")
	_choose(game.settings_menu, "panorama", false)
	assert_false(game.panorama_enabled, "im Menü abgeschaltet")
	assert_false(GraphicsSettings.load_file(SETTINGS_PATH).panorama, "gespeichert")
	remove_child(game)
	game.free()
	var again := _spawn_game(SETTINGS_PATH)
	assert_false(again.panorama_enabled, "nach Neustart aus")
	assert_eq(again.settings_menu.options["panorama"].selected, 1, "Menü zeigt „Aus“")
	_choose(again.settings_menu, "panorama", true)
	assert_true(again.panorama_enabled)
	assert_true(GraphicsSettings.load_file(SETTINGS_PATH).panorama)
