## Fahrt im Leistungsmodell gegen den Fake-Bus (Spec #75): Trainer mit gemessener Leistung → Tempo aus Watt und
## Streckensteigung, Watt mit 3-s-Mittel im HUD, die Geräteart steht mit der ersten Telemetrie fest; Segmentzeit und
## Medaille landen nur in den Bereichen des Leistungsmodells. Simulator (geschätzte Leistung) bleibt beim Kadenzmodell.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_power_ride_savegame.json")
const MEASURED := {"power_w": 250.0, "power_estimated": false}
## Kurz vor dem Dorfsprint (5700–6010 m), wie tests/test_segments_and_medals.gd.
const BEFORE_VILLAGE_M := 5600.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _telemetry(cadence: float, fields: Dictionary, until_s: float = 10.0) -> Array:
	return [FakeBusServer.status("connected", "ble")] + FakeBusServer.steady_cadence(cadence, 0.0, until_s, 0.25, fields)


func test_measured_power_drives_the_speed_and_shows_the_average() -> void:
	var bus := start_fake_bus(_telemetry(80.0, MEASURED))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	assert_eq(ride.ride_kind, RideModel.KIND_POWER, "gemessene Leistung → Leistungsmodell")
	await run_for(6.0)  # Trägheit 1,5 s: eingeschwungen
	var expected: float = ride.model.target_speed_power_mps(250.0, ride.current_grade())
	assert_almost_eq(ride.model.speed_mps, expected, 0.05 * expected, "Tempo aus 250 W, nicht aus 80 rpm")
	assert_gt(absf(ride.model.speed_mps - ride.model.target_speed_mps(80.0, ride.current_grade())), 1.0,
			"Kadenzmodell wäre deutlich anders")
	assert_string_contains(ride.get_node("Hud").readout(), "Leistung: 250 W · Ø3s 250 W")


func test_device_kind_stays_for_the_whole_ride() -> void:
	var steps := [FakeBusServer.status("connected", "ble")] + FakeBusServer.steady_cadence(80.0, 0.0, 1.0, 0.25, MEASURED) \
			+ FakeBusServer.steady_cadence(80.0, 1.25, 6.0, 0.25, {"power_w": 150.0, "power_estimated": true})
	var bus := start_fake_bus(steps)
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	await run_for(2.0)
	assert_eq(ride.ride_kind, RideModel.KIND_POWER, "Geräteart wechselt in der Fahrt nicht")


func test_simulator_estimate_stays_with_the_cadence_model() -> void:
	var bus := start_fake_bus(_telemetry(80.0, {"power_w": 150.0, "power_estimated": true}))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	await run_for(6.0)  # Trägheit 1,5 s: eingeschwungen
	assert_eq(ride.ride_kind, RideModel.KIND_CADENCE)
	var expected: float = ride.model.target_speed_mps(ride.bus.cadence, ride.current_grade())
	assert_almost_eq(ride.model.speed_mps, expected, 0.05 * expected, "Tempo aus der (geglätteten) Kadenz")
	var hud: String = ride.get_node("Hud").readout()
	assert_string_contains(hud, "Leistung: ~150 W")
	assert_false(hud.contains("Ø3s"), "geschätzte Leistung ohne 3-s-Mittel")


## Leistungsfahrt durch den Dorfsprint: Segmentzeit wie die Simulation mit konstanter Leistung, gespeichert nur im
## Leistungsmodell; die Bereiche des Kadenzmodells bleiben leer.
func test_power_ride_records_only_in_the_power_areas() -> void:
	var watts := 8000.0
	var bus := start_fake_bus(_telemetry(90.0, {"power_w": watts, "power_estimated": false}, 30.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.inertia_s = 0.0
	config.power_cda_m2 = 0.01  # schnelles Rad: der Dorfsprint in wenigen Sekunden
	config.power_max_kmh = 400.0
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	game.start_distance_m = BEFORE_VILLAGE_M
	add_child_autofree(game)
	await run_for(0.3)
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Rundfahrt fährt los")
	assert_eq(game.ride_kind, RideModel.KIND_POWER)
	assert_true(await run_until(func(): return not game.lap_timing.segments.results.is_empty(), 8.0), "Segment verlassen")
	var result: Dictionary = game.lap_timing.segments.results[0]
	var expected: float = Medals.simulate_lap(game.track, config, watts, RideModel.KIND_POWER)["dorfsprint"]
	assert_almost_eq(result["time_s"], expected, 0.05, "Zeit wie das Leistungsmodell bei konstanten Watt")
	game.settings_menu.ride_end_requested.emit()
	var save := SaveGame.load_file(SAVE_PATH)
	var cw := LapTiming.DIRECTION_CW
	assert_almost_eq(save.segment_best_s(RideConfig.TRACK_ISLAND, cw, "dorfsprint", RideModel.KIND_POWER),
			result["time_s"], 0.001, "Segment-Bestzeit im Leistungsmodell")
	assert_eq(save.best_medal(RideConfig.TRACK_ISLAND, cw, "dorfsprint", RideModel.KIND_POWER), Medals.GOLD)
	assert_eq(save.segment_best_s(RideConfig.TRACK_ISLAND, cw, "dorfsprint"), INF, "Kadenzmodell unberührt")
	assert_eq(save.best_medal(RideConfig.TRACK_ISLAND, cw, "dorfsprint"), Medals.NONE)
