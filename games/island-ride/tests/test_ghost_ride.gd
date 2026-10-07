## Ghost in der Rundfahrt (#32) gegen den Fake-Bus: Fahrt 1 setzt die Bestzeit und speichert ihre Runde als Ghost;
## nach einem Neustart fährt Fahrt 2 mit anderer Kadenz gegen den Bestzeit-Ghost – halbtransparent an der richtigen
## Streckenposition, das HUD zeigt den Abstand mit Vorzeichen (+ = dahinter); danach die Auswahl „letzte Fahrt“.
extends "res://tests/support/bus_test.gd"

const SAVE_PATH := "user://test_ghost_ride_savegame.json"
## Schnelles Rad wie in test_round_trip.gd: eine Graybox-Runde in wenigen Sekunden.
const FAST_K := 10.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus mit Kadenz `cadence`, Test-Spielstand, ohne Trägheit.
func _spawn_game(cadence: float) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 60.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Rundfahrt“ öffnen; liefert die Ghost-Auswahl.
func _open_round_trip(game: Node) -> OptionButton:
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	return game.start_menu.options["ghost"]


## Losfahren (eine Runde) und warten, bis gefahren wird.
func _start(game: Node) -> void:
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Rundfahrt fährt los")


func test_best_time_ghost_after_restart_and_last_ride() -> void:
	# Fahrt 1: noch kein Ghost – die Auswahl ist ausgegraut, Standard „Aus“.
	var first := _spawn_game(120.0)
	await run_for(0.2)
	var choice := _open_round_trip(first)
	assert_true(choice.is_visible_in_tree(), "Ghost-Auswahl auf der Seite „Rundfahrt“")
	assert_eq([choice.get_item_text(0), choice.get_item_text(1), choice.get_item_text(2)], ["Aus", "Bestzeit", "Letzte Fahrt"])
	assert_true(choice.is_item_disabled(1) and choice.is_item_disabled(2), "ohne Aufzeichnung ausgegraut")
	assert_eq(first.start_menu.ghost_choice(), "", "Standard ohne Aufzeichnung: aus")
	await _start(first)
	assert_false(first.ghost_active(), "ohne Ghost gefahren")
	assert_false(first.ghost_rider.visible)
	assert_false(first.hud.readout().contains("Ghost"), "kein Abstand ohne Ghost")
	assert_true(await run_until(func(): return first.state == "finished", 10.0), "Ziel")
	var best_lap: float = first.lap_timing.lap_times[0]
	var saved: Ghost = first.save_game.ghost(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, Ghost.BEST)
	assert_not_null(saved, "Bestzeit-Runde als Ghost gespeichert")
	assert_almost_eq(saved.time_s, best_lap, 0.001)
	assert_not_null(first.save_game.ghost(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, Ghost.LAST), "letzte Fahrt")

	# Neustart, Fahrt 2 mit weniger Kadenz: Standard ist jetzt der Bestzeit-Ghost.
	var second := _spawn_game(90.0)
	await run_for(0.2)
	choice = _open_round_trip(second)
	assert_false(choice.is_item_disabled(1) or choice.is_item_disabled(2), "beide Ghosts wählbar")
	assert_eq(second.start_menu.ghost_choice(), Ghost.BEST, "Standard: Bestzeit, sobald es sie gibt")
	await _start(second)
	assert_true(second.ghost_active(), "Ghost fährt mit (abfragbar, z. B. für Panorama-Momente)")
	assert_almost_eq(second.ghost.time_s, best_lap, 0.001, "der Bestzeit-Ghost aus dem Spielstand")
	assert_true(await run_until(func(): return second.lap_timing.lap_time_s > 1.5, 5.0))
	var gap: float = second.ghost_gap_s()
	assert_gt(gap, 0.0, "langsamer als die Bestzeit: hinter dem Ghost, Abstand positiv")
	assert_string_contains(second.hud.readout(), "Ghost: %s s" % second.format_gap(gap), "HUD zeigt den Abstand")
	assert_string_contains(second.hud.readout(), "Ghost: +", "mit Vorzeichen +")
	# Mitfahrer: halbtransparent, vor dem Fahrer an der Position, die der Ghost zur Rundenzeit erreicht hatte.
	assert_true(second.ghost_rider.is_visible_in_tree(), "Mitfahrer sichtbar")
	var at: float = second.ghost.position_at(second.lap_timing.lap_time_s)
	assert_almost_eq(second.ghost_distance_m(), second.lap_timing.lap_start_m() + at, 0.001)
	assert_almost_eq(second.ghost_rider.progress, second.track.wrap_distance(second.ghost_distance_m()), 0.5,
			"Mitfahrer an der Streckenposition des Ghosts")
	assert_gt(second.ghost_distance_m(), second.model.distance_m, "der schnellere Ghost liegt vorn")
	var mesh: MeshInstance3D = second.ghost_model.find_children("*", "MeshInstance3D", true, false)[0]
	var material: StandardMaterial3D = mesh.material_override
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "halbtransparent")
	assert_lt(material.albedo_color.a, 1.0)
	assert_eq(second.rider_model.find_children("*", "MeshInstance3D", true, false)[0].material_override.transparency,
			BaseMaterial3D.TRANSPARENCY_DISABLED, "der eigene Fahrer bleibt deckend")
	assert_true(await run_until(func(): return second.state == "finished", 10.0), "Ziel")
	var slower_lap: float = second.lap_timing.lap_times[0]
	assert_almost_eq(second.ghost_gap_s(), slower_lap - best_lap, 0.01, "im Ziel: Unterschied der Rundenzeiten")
	assert_eq(second.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), snappedf(best_lap, 0.001),
			"Bestzeit unverändert")
	assert_almost_eq(second.save_game.ghost(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, Ghost.BEST).time_s,
			best_lap, 0.001, "der Bestzeit-Ghost bleibt")
	assert_almost_eq(second.save_game.ghost(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, Ghost.LAST).time_s,
			slower_lap, 0.001, "„letzte Fahrt“ ist jetzt Fahrt 2")

	# Fahrt 3 gegen „letzte Fahrt“ (Fahrt 2), diesmal schneller übersetzt: vor dem Ghost, Abstand negativ.
	await press_key(KEY_ENTER)
	assert_eq(second.state, "menu")
	assert_false(second.ghost_active(), "im Menü kein Ghost")
	assert_false(second.ghost_rider.visible)
	choice.select(2)
	assert_eq(second.start_menu.ghost_choice(), Ghost.LAST)
	second.config.k_kmh_per_rpm = FAST_K * 1.5
	await _start(second)
	assert_almost_eq(second.ghost.time_s, slower_lap, 0.001, "Ghost der letzten Fahrt")
	assert_true(await run_until(func(): return second.lap_timing.lap_time_s > 1.0, 5.0))
	gap = second.ghost_gap_s()
	assert_lt(gap, 0.0, "schneller als die letzte Fahrt: vor dem Ghost, Abstand negativ")
	assert_string_contains(second.hud.readout(), "Ghost: -", "mit Vorzeichen −")
	assert_lt(second.ghost_distance_m(), second.model.distance_m, "der Ghost liegt zurück")
