## Kameraperspektiven (#59): Nah, Verfolger (Standard) und Weit als Daten; `C` blättert der Reihe nach mit Einblendung
## des Namens, das Einstellungsmenü wählt dasselbe, die Wahl steht im Spielstand (additiv, übersteht einen Neustart).
## In allen Perspektiven und beiden Richtungen bleibt die Kamera über die ganze Runde mindestens 1,5 m über dem Gelände;
## Intro und Panorama enden in der gewählten Perspektive, der Sichtfeld-Kick wirkt in allen. `C` stört kein Menü.
## Das Fahrmodell sieht davon nichts (ADR-0010: Fahrmodell daneben ohne Kamera, Vergleichsrunde ohne Wechsel).
extends "res://tests/support/bus_test.gd"

const SAVE_PATH := "user://test_camera_views_savegame.json"
## Zeitschritt der Fahrten (s).
const DT := 0.1


func after_each() -> void:
	super.after_each()
	for path in [SAVE_PATH, SAVE_PATH + SaveGame.BROKEN_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Hauptszene auf der Insel am Fake-Bus (90 rpm, 36 km/h flach); `menu`: mit Startmenü wie beim Spielstart.
func _spawn_game(save_path: String = "", menu: bool = false) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 600.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.k_kmh_per_rpm = 0.4
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = save_path
	game.start_in_menu = menu
	add_child_autofree(game)
	return game


## Taste wie ein Spieler (Zeichen und physische Position).
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


## Was das Feld „Kamera“ im Einstellungsmenü zeigt, wenn man es öffnet.
func _menu_text(game: Node) -> String:
	game.settings_menu.open()
	var option: OptionButton = game.settings_menu.options["camera_view"]
	var text := option.get_item_text(option.selected)
	game.settings_menu.close()
	return text


## Waagrechter Abstand der Folgekamera hinter dem Fahrer an Fahrtposition `d`.
func _behind(game: Node, d: float) -> float:
	var target: Vector3 = game.camera_follow_view(d)[0]
	var at: Vector3 = game.track.to_global(game.track.ride_position_at(d))
	return Vector2(target.x - at.x, target.z - at.z).length()


func test_views_are_data_with_wide_from_config() -> void:
	assert_eq(CameraViews.IDS, [CameraViews.NEAR, CameraViews.CHASE, CameraViews.WIDE], "Reihenfolge Nah, Verfolger, Weit")
	assert_eq(CameraViews.DEFAULT, CameraViews.CHASE, "Standard: Verfolger")
	assert_eq(CameraViews.next(CameraViews.NEAR), CameraViews.CHASE)
	assert_eq(CameraViews.next(CameraViews.CHASE), CameraViews.WIDE)
	assert_eq(CameraViews.next(CameraViews.WIDE), CameraViews.NEAR, "nach Weit wieder Nah")
	assert_eq(CameraViews.valid("drohne"), CameraViews.DEFAULT, "Unbekanntes → Standard")
	assert_eq(CameraViews.valid(3), CameraViews.DEFAULT)
	var config := RideConfig.load_file()
	var near := CameraViews.values(CameraViews.NEAR, config)
	var chase := CameraViews.values(CameraViews.CHASE, config)
	var wide := CameraViews.values(CameraViews.WIDE, config)
	assert_almost_eq(float(near["behind_m"]), 3.5, 0.3, "Nah etwa 3,5 m")
	assert_almost_eq(float(chase["behind_m"]), 4.5, 0.3, "Verfolger etwa 4,5 m")
	assert_eq(wide["behind_m"], 5.5, "Weit 5,5 m wie bisher (config.cfg)")
	assert_eq(wide["height_m"], 2.4, "Weit 2,4 m hoch wie bisher")
	assert_lt(near["height_m"], chase["height_m"], "Nah etwas tiefer")
	assert_lt(chase["height_m"], wide["height_m"])
	for view in [near, chase, wide]:
		assert_eq(view["look_ahead_m"], config.camera_look_ahead_m, "Blickpunkt voraus aus [camera] für alle")
		assert_eq(view["look_height_m"], config.camera_look_height_m)
	# Eine bestehende Konfiguration bricht nicht: [camera] behind_m/height_m bleiben die Kamera „Weit“.
	var custom := RideConfig.new()
	custom.camera_behind_m = 7.0
	custom.camera_height_m = 3.0
	custom.camera_look_ahead_m = 14.0
	assert_eq(CameraViews.values(CameraViews.WIDE, custom)["behind_m"], 7.0)
	assert_eq(CameraViews.values(CameraViews.WIDE, custom)["height_m"], 3.0)
	assert_eq(CameraViews.values(CameraViews.NEAR, custom)["behind_m"], near["behind_m"], "Nah bleibt fest")
	assert_eq(CameraViews.values(CameraViews.NEAR, custom)["look_ahead_m"], 14.0)


func test_save_game_is_additive() -> void:
	# Stand von vor #59 (ohne Bereich `camera`): lädt mit Standard, alles andere bleibt, Version bleibt 1.
	var old := {"version": 1, "active_profile": "0123456789abcdef", "profiles": {"0123456789abcdef": {
			"created": "2026-10-01T10:00:00Z", "rides": [{"date": "2026-10-01T10:30:00Z", "mode": "rundfahrt"}],
			"wardrobe": {"helm": "helm_schwarz"}}}}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var save := SaveGame.load_file(SAVE_PATH)
	assert_eq(save.version(), 1, "Format bleibt Version 1")
	assert_eq(save.rides().size(), 1, "Fahrten bleiben")
	assert_eq(save.wardrobe(), {"helm": "helm_schwarz"}, "Garderobe bleibt")
	assert_eq(CameraViews.selection(save), CameraViews.CHASE, "ohne Wahl: Verfolger")
	CameraViews.choose(save, CameraViews.NEAR)
	assert_eq(save.save_file(SAVE_PATH), OK)
	assert_eq(CameraViews.selection(SaveGame.load_file(SAVE_PATH)), CameraViews.NEAR, "gespeichert")
	save.camera()["view"] = "drohne"
	assert_eq(CameraViews.selection(save), CameraViews.CHASE, "ungültig → Verfolger")
	save.profile()["camera"] = "kaputt"
	assert_eq(save.save_file(SAVE_PATH), OK)
	assert_eq(CameraViews.selection(SaveGame.load_file(SAVE_PATH)), CameraViews.CHASE, "kaputter Bereich → Verfolger")
	assert_eq(CameraViews.selection(SaveGame.new()), CameraViews.CHASE, "neuer Stand: Verfolger")


func test_c_cycles_with_name_menu_field_and_survives_restart() -> void:
	var game := _spawn_game(SAVE_PATH)
	await run_for(0.2)
	assert_eq(game.camera_view, CameraViews.CHASE, "Standard: Verfolger")
	assert_eq(_menu_text(game), "Verfolger", "Menü zeigt Verfolger")
	var d: float = game.model.distance_m + 50.0
	var expected := [[CameraViews.WIDE, "Weit"], [CameraViews.NEAR, "Nah"], [CameraViews.CHASE, "Verfolger"],
			[CameraViews.WIDE, "Weit"]]
	var behind := {}
	for step in expected:
		await _press(KEY_C)
		assert_eq(game.camera_view, step[0], "C → %s" % step[1])
		assert_eq(game.hud.camera_view(), "Kamera: %s" % step[1], "Name eingeblendet")
		assert_eq(CameraViews.selection(SaveGame.load_file(SAVE_PATH)), step[0], "im Spielstand gespeichert")
		assert_eq(_menu_text(game), step[1], "Einstellungsmenü zeigt die Wahl")
		behind[step[0]] = _behind(game, d)
	assert_lt(behind[CameraViews.NEAR], behind[CameraViews.CHASE], "Nah näher als Verfolger")
	assert_lt(behind[CameraViews.CHASE], behind[CameraViews.WIDE], "Verfolger näher als Weit")
	await run_for(RideHud.CAMERA_VIEW_S + 0.3)
	assert_eq(game.hud.camera_view(), "", "Einblendung nur kurz")
	# Einstellungsfeld wirkt und speichert (ohne Einblendung – das Menü zeigt die Wahl).
	_choose(game.settings_menu, "camera_view", CameraViews.NEAR)
	assert_eq(game.camera_view, CameraViews.NEAR, "im Menü gewählt")
	assert_eq(CameraViews.selection(SaveGame.load_file(SAVE_PATH)), CameraViews.NEAR, "gespeichert")
	assert_almost_eq(_behind(game, d), behind[CameraViews.NEAR], 0.001, "Kamera in der gewählten Lage")
	remove_child(game)
	game.free()
	var again := _spawn_game(SAVE_PATH)
	await run_for(0.2)
	assert_eq(again.camera_view, CameraViews.NEAR, "nach Neustart: Nah")
	assert_eq(_menu_text(again), "Nah")
	assert_almost_eq(_behind(again, d), behind[CameraViews.NEAR], 0.001)
	await _press(KEY_C)
	assert_eq(again.camera_view, CameraViews.CHASE, "Nah → Verfolger")


func test_c_does_not_disturb_menus() -> void:
	var game := _spawn_game("", true)
	await run_for(0.2)
	var viewport := game.get_viewport()
	assert_eq(game.state, "menu")
	var focus := viewport.gui_get_focus_owner()
	await _press(KEY_C)
	assert_eq(game.camera_view, CameraViews.CHASE, "Startmenü: C wirkt nicht")
	assert_true(game.start_menu.visible, "Startmenü bleibt offen")
	assert_eq(viewport.gui_get_focus_owner(), focus, "Fokus bleibt")
	assert_eq(game.hud.camera_view(), "", "keine Einblendung")
	game.open_logbook()
	await _press(KEY_C)
	assert_true(game.logbook.visible, "Fahrtenbuch bleibt offen")
	assert_eq(game.camera_view, CameraViews.CHASE, "Fahrtenbuch: C wirkt nicht")
	await _press(KEY_ESCAPE)
	assert_false(game.logbook.visible, "Fahrtenbuch mit Esc zu – bedienbar")
	game.open_wardrobe()
	await _press(KEY_C)
	assert_true(game.wardrobe.visible, "Garderobe bleibt offen")
	assert_eq(game.camera_view, CameraViews.CHASE, "Garderobe: C wirkt nicht")
	await _press(KEY_ESCAPE)
	assert_false(game.wardrobe.visible, "Garderobe mit Esc zu – bedienbar")
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
	await run_for(0.1)
	await _press(KEY_ESCAPE)
	assert_true(game.settings_menu.visible, "Einstellungen offen")
	await _press(KEY_C)
	assert_true(game.settings_menu.visible, "Einstellungen bleiben offen")
	assert_eq(game.camera_view, CameraViews.CHASE, "bei offenem Menü wirkt C nicht")
	await _press(KEY_ESCAPE)
	assert_false(game.settings_menu.visible)
	await _press(KEY_C)
	assert_eq(game.camera_view, CameraViews.WIDE, "in der Fahrt wirkt C")
	await _press(KEY_P)
	assert_eq(game.state, "paused_manual", "P pausiert weiter")
	await _press(KEY_C)
	assert_eq(game.camera_view, CameraViews.NEAR, "auch in der Pause")
	assert_eq(game.state, "paused_manual", "C ändert den Zustand nicht")


func test_camera_stays_above_terrain_in_every_view_over_the_whole_lap_in_both_directions() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	game.set_process(false)
	game.panorama_enabled = false  # nur die Folgekamera; Panoramen haben ihre eigene Mindesthöhe
	var length: float = game.track.length_m()
	var speed := 36.0 / 3.6
	for direction in [Track.DIRECTION_CW, Track.DIRECTION_CCW]:
		game._set_direction(direction)
		for id in CameraViews.IDS:
			game.set_camera_view(id, false)
			game.model.distance_m = 0.0
			game._update_camera(0.0, true)
			var lowest := INF
			var lowest_m := 0.0
			var d := 0.0
			while d <= length:
				d += speed * DT
				game.model.distance_m = d
				game._update_camera(DT)
				var at: Vector3 = game.camera.global_position
				var clearance: float = at.y - game.world.terrain.height_at(at.x, at.z)
				if clearance < lowest:
					lowest = clearance
					lowest_m = d
			assert_gte(lowest, game.CAMERA_TERRAIN_CLEARANCE_M - 0.01,
					"%s %s: mindestens 1,5 m über dem Gelände (tiefste Stelle %.0f m: %.2f m)" % [direction, id, lowest_m,
					lowest])
	game.set_process(true)


## Fahrt starten, bis das Intro vorbei ist (Fahrer steht); dann ein Panorama an der ersten Sehenswürdigkeit. Beide
## enden genau in der Folgekamera der gewählten Perspektive.
func _check_intro_and_panorama(game: Node, id: String, mode: String, direction: String) -> void:
	game.set_camera_view(id, false)
	if mode == SaveGame.MODE_TRAINING:
		game.start_ride(mode, 0, "", Training.load_all()[0])
	else:
		game.start_ride(mode, 1, "", {}, direction)
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	game.set_process(false)
	assert_eq(game.camera_mode, game.CAMERA_INTRO, "Intro läuft")
	var label := "%s %s %s" % [id, mode, direction]
	var d: float = game.model.distance_m
	var target: Vector3 = game.camera_follow_view(d)[0]
	for i in range(int(game.CAMERA_INTRO_S / DT) + 2):
		game._update_camera(DT)
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW, "%s: Intro vorbei" % label)
	assert_lt(game.camera.global_position.distance_to(target), 0.05, "%s: Intro endet in der Perspektive" % label)
	game.panorama = game.panorama_spots[0]
	game._set_camera_mode(game.CAMERA_PANORAMA)
	var widest := 0.0
	for i in range(int(game.CAMERA_PANORAMA_S / DT) + 2):
		game._update_camera(DT)
		widest = maxf(widest, game.camera.global_position.distance_to(target))
	for i in range(30):
		game._update_camera(DT)
	assert_eq(game.camera_mode, game.CAMERA_FOLLOW, "%s: Panorama vorbei" % label)
	assert_gt(widest, 2.0, "%s: Panorama schwenkt aus" % label)
	assert_lt(game.camera.global_position.distance_to(target), 0.05, "%s: zurück in der Perspektive" % label)
	game._end_panorama()
	game.set_process(true)
	game.return_to_menu()
	game.return_to_menu()


func test_intro_and_panorama_return_to_the_chosen_view_and_fov_kick_works_in_all() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	for id in CameraViews.IDS:
		await _check_intro_and_panorama(game, id, SaveGame.MODE_ROUND_TRIP, Track.DIRECTION_CW)
	await _check_intro_and_panorama(game, CameraViews.NEAR, SaveGame.MODE_ROUND_TRIP, Track.DIRECTION_CCW)
	await _check_intro_and_panorama(game, CameraViews.WIDE, SaveGame.MODE_TRAINING, Track.DIRECTION_CW)
	for id in CameraViews.IDS:
		game.set_camera_view(id, false)
		game.speed_effects.reset()
		for i in range(30):
			game.speed_effects.update(60.0, DT)
		assert_gt(game.camera.fov, game.speed_effects.base_fov + 1.0, "%s: Sichtfeld-Kick wirkt" % id)


## Eine Runde mit dem Fahrmodell und einem Fahrmodell ohne Kamera daneben; `switch_every`: alle so viele Schritte `C`
## (0 = nie). Ergebnis: [Rundenzeit, größte Abweichung vom Fahrmodell daneben].
func _drive_lap(game: Node, switch_every: int) -> Array:
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CW)
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	game.set_process(false)
	var reference := RideModel.new(game.config, game.model.distance_m)
	reference.speed_mps = game.model.speed_mps
	var drift := 0.0
	var steps := 0
	while game.state == "riding" and steps < 20000:
		if switch_every > 0 and steps % switch_every == 0:
			game.cycle_camera_view()
		game._ride(DT)
		reference.step(90.0, game.track.grade_at(reference.distance_m), DT)
		game._update_camera(DT)
		steps += 1
		if game.state == "riding":
			drift = maxf(drift, absf(game.model.distance_m - reference.distance_m))
	game.set_process(true)
	assert_eq(game.state, "finished", "im Ziel")
	var lap: float = game.lap_timing.lap_times[0]
	game.return_to_menu()
	return [lap, drift]


func test_views_do_not_touch_the_ride_model() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	var switching := await _drive_lap(game, 150)
	assert_almost_eq(switching[1], 0.0, 0.0001, "mit Wechseln: Fahrmodell unberührt (ADR-0010)")
	# Vergleich: dieselbe Runde ohne einen einzigen Wechsel, in der Standard-Perspektive
	game.set_camera_view(CameraViews.CHASE, false)
	var steady := await _drive_lap(game, 0)
	assert_almost_eq(steady[1], 0.0, 0.0001)
	assert_almost_eq(switching[0], steady[0], 0.0001, "gleiche Rundenzeit mit und ohne Perspektivwechsel")
