## Gegenrichtung (#34) gegen den Fake-Bus auf der Insel: Richtung im Startmenü wählen, eine Runde gegen den
## Uhrzeigersinn fahren – Rundenzeit, Bestzeit, alle drei Segmente, Medaillen und Ghosts landen unter "ccw", der
## Uhrzeigersinn bleibt unberührt. Fahrer, Ghost, Torbögen und HUD schauen in Fahrtrichtung.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_counter_direction_savegame.json")
## Schnelles Rad wie in test_segments_and_medals.gd: 120 rpm · 10 km/h je rpm.
const FAST_K := 10.0
const DT := 1.0 / 60.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) auf der Insel am Fake-Bus, Test-Spielstand, schnelles Rad ohne Trägheit.
func _spawn_game() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 60.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Rundfahrt“ öffnen und die Richtung wählen (Index wie StartMenu.DIRECTION_CHOICES), wie mit der Maus.
func _choose_direction(game: Node, index: int) -> void:
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	var option: OptionButton = game.start_menu.options["direction"]
	option.select(index)
	option.item_selected.emit(index)


## Losfahren und warten, bis gefahren wird; danach Bild für Bild (DT) bis ins Ziel, unabhängig von der Bildrate.
func _ride_one_lap(game: Node) -> void:
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence == 120.0, 3.0), "fährt los")
	game.set_process(false)
	for i in range(100000):
		if game.state == "finished":
			break
		game._ride(DT)
	game.set_process(true)
	assert_eq(game.state, "finished", "Ziel nach einer Runde")


func test_ccw_lap_records_everything_under_ccw_and_leaves_cw_untouched() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	var island := RideConfig.TRACK_ISLAND
	var ccw := Track.DIRECTION_CCW
	var cw := Track.DIRECTION_CW
	_choose_direction(game, 1)
	var option: OptionButton = game.start_menu.options["direction"]
	assert_true(option.is_visible_in_tree(), "Richtung auf der Seite „Rundfahrt“")
	assert_eq([option.get_item_text(0), option.get_item_text(1)], ["Im Uhrzeigersinn", "Gegen den Uhrzeigersinn"])
	assert_eq(game.start_menu.ride_direction(), ccw)
	await _ride_one_lap(game)
	assert_eq(game.track.direction, ccw, "gegen den Uhrzeigersinn gefahren")
	var lap: float = game.lap_timing.lap_times[0]
	var expected: Dictionary = Medals.simulate_lap(game.track, game.config, 120.0)
	assert_almost_eq(lap, expected[Medals.LAP], 0.1, "Rundenzeit wie das Fahrmodell gegen den Uhrzeigersinn")
	assert_eq(game.lap_timing.segments.results.map(func(r): return r["id"]), ["bergwertung", "dorfsprint", "kuestenwelle"],
			"drei Segmente in Fahrtfolge")
	assert_string_contains(game.status_message(), "Medaille: Gold", "120 rpm: Gold")
	game.return_to_menu()
	assert_eq(game.state, "menu")
	var saved := SaveGame.load_file(SAVE_PATH)
	assert_almost_eq(saved.best_time_s(island, ccw), lap, 0.001, "Bestzeit unter ccw")
	assert_eq(saved.best_medal(island, ccw, Medals.LAP), Medals.GOLD, "Rundenmedaille unter ccw")
	for id in ["bergwertung", "dorfsprint", "kuestenwelle"]:
		assert_almost_eq(saved.segment_best_s(island, ccw, id), expected[id], 0.1, "%s: Segmentzeit unter ccw" % id)
		assert_eq(saved.best_medal(island, ccw, id), Medals.GOLD, "%s: Medaille unter ccw" % id)
		assert_eq(saved.segment_best_s(island, cw, id), INF, "%s: cw unberührt" % id)
		assert_eq(saved.best_medal(island, cw, id), Medals.NONE)
	assert_not_null(saved.ghost(island, ccw, Ghost.BEST), "Bestzeit-Ghost unter ccw")
	assert_not_null(saved.ghost(island, ccw, Ghost.LAST), "letzte Fahrt unter ccw")
	assert_eq(saved.best_time_s(island, cw), INF, "cw: keine Bestzeit")
	assert_eq(saved.best_medal(island, cw, Medals.LAP), Medals.NONE, "cw: keine Medaille")
	assert_null(saved.ghost(island, cw, Ghost.BEST), "cw: kein Ghost")
	assert_null(saved.ghost(island, cw, Ghost.LAST))
	# Menü: Bestzeit und Ghosts je Richtung.
	var ghost: OptionButton = game.start_menu.options["ghost"]
	var best_label: Label = game.start_menu.find_child("BestTime", true, false)
	_choose_direction(game, 1)
	assert_string_contains(best_label.text, game.format_time(lap, true), "ccw: Bestzeit im Menü")
	assert_false(ghost.is_item_disabled(1), "ccw: Bestzeit-Ghost wählbar")
	assert_eq(game.start_menu.ghost_choice(), Ghost.BEST)
	_choose_direction(game, 0)
	assert_string_contains(best_label.text, "noch keine", "cw: keine Bestzeit")
	assert_true(ghost.is_item_disabled(1) and ghost.is_item_disabled(2), "cw: kein Ghost")
	assert_eq(game.start_menu.ghost_choice(), "")


func test_ccw_ride_faces_the_other_way_with_its_own_ghost_and_gates() -> void:
	var game := _spawn_game()
	await run_for(0.2)
	var length: float = game.track.length_m()
	var ghost := Ghost.new(length)
	ghost.record(0.0, 0.0)
	ghost.finish(30.0)
	game.save_game.record_ghost(RideConfig.TRACK_ISLAND, Track.DIRECTION_CCW, Ghost.BEST, ghost)
	_choose_direction(game, 1)
	assert_eq(game.start_menu.ghost_choice(), Ghost.BEST, "Ghost der Gegenrichtung")
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding", 3.0))
	game.set_process(false)
	for i in range(240):  # 4 s Fahrt in den Osthang
		game._ride(DT)
	game._update_view()
	var d: float = game.model.distance_m
	assert_gt(d, 300.0)
	assert_almost_eq(game.rider.progress, length - d, 0.01, "Pfad rückwärts: L − d")
	assert_gt(game.current_grade(), 0.03, "Osthang bergauf")
	assert_eq(game.current_station(), "Osthang")
	# Fahrer schaut in Fahrtrichtung: sein Vorne (−Z des Modells) zeigt zum nächsten Punkt der Fahrt.
	var ahead: Vector3 = game.track.to_global(game.track.ride_position_at(d + 5.0)) - game.rider_model.global_position
	var forward: Vector3 = -game.rider_model.global_basis.z
	assert_gt(Vector2(forward.x, forward.z).normalized().dot(Vector2(ahead.x, ahead.z).normalized()), 0.9,
			"Fahrer schaut in Fahrtrichtung")
	assert_true(game.ghost_rider.visible, "Ghost fährt mit")
	var g: float = game.ghost_distance_m()
	var on_road: Vector3 = game.track.to_global(game.track.ride_position_at(g))
	var ghost_way: Vector3 = (game.track.to_global(game.track.ride_position_at(g + 5.0)) - on_road).normalized()
	var left := Vector3.UP.cross(ghost_way).normalized()  # links in Fahrtrichtung am Ghost
	assert_gt((game.ghost_model.global_position - on_road).dot(left), 1.0, "Ghost links in Fahrtrichtung")
	var ghost_forward: Vector3 = -game.ghost_model.global_basis.z
	assert_gt(ghost_forward.dot(ghost_way), 0.8, "Ghost schaut auch in Fahrtrichtung")
	# Torbögen der Gegenrichtung sichtbar, mit dem Banner zur anfahrenden Kamera.
	assert_false((game.world.get_node("Segments") as Node3D).visible, "cw-Bögen verborgen")
	var gates: Node3D = game.world.get_node("SegmentsCcw")
	assert_true(gates.visible)
	assert_eq(gates.get_child_count(), 3)
	for segment in game.track.segments:
		var gate: Node3D = gates.get_node(NodePath(segment["id"]))
		var at: Vector3 = game.track.to_global(game.track.ride_position_at(segment["start_m"]))
		assert_lt(gate.global_position.distance_to(at), 0.01, "%s: Bogen am Start in Fahrtrichtung" % segment["id"])
		var before: Vector3 = game.track.to_global(game.track.ride_position_at(segment["start_m"] - 20.0))
		var label: Label3D = gate.get_node("Name")
		assert_gt(label.global_basis.z.dot(before - at), 0.0, "%s: Name zur anfahrenden Kamera" % segment["id"])
	# Stationsschild am Beginn der Station in Fahrtrichtung, mit dem Namen dieser Richtung.
	var sign: Node3D = game.world.get_node("Stations/abfahrt")
	assert_eq((sign.get_node("Label") as Label3D).text, "Osthang")
	assert_lt(sign.global_position.distance_to(game.track.to_global(game.track.ride_position_at(0.0))), 0.01)
	assert_true((game.world.get_node("Details/KilometersteineCcw") as Node3D).visible, "Kilometer der Gegenrichtung")
	# Zurück im Uhrzeigersinn steht alles wie vorher.
	game.return_to_menu()
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
	assert_eq(game.track.direction, Track.DIRECTION_CW)
	assert_true((game.world.get_node("Segments") as Node3D).visible)
	assert_false(gates.visible)
	assert_eq((sign.get_node("Label") as Label3D).text, "Abfahrt")
	assert_almost_eq(game.ghost_rider.h_offset, game.GHOST_OFFSET_M, 0.001)
	assert_almost_eq(game.rider_model.rotation.y, 0.0, 0.001)
