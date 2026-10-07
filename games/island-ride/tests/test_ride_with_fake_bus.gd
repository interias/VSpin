## Spiel end-to-end gegen den Fake-Bus: Drehbuch rein → Geschwindigkeit/Position der Hauptszene raus.
extends "res://tests/support/bus_test.gd"

const FLAT_M := 20.0
const CLIMB_M := 200.0
const DESCENT_M := 560.0
const RIDE_S := 3.0


func _steady(cadence: float) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, RIDE_S + 2.0)


func test_more_cadence_is_faster() -> void:
	var slow := spawn_ride(start_fake_bus(_steady(60.0)), FLAT_M)
	var fast := spawn_ride(start_fake_bus(_steady(90.0)), FLAT_M)
	await run_for(RIDE_S)
	assert_eq(slow.bus.cadence, 60.0)
	assert_eq(fast.bus.cadence, 90.0)
	assert_gt(slow.model.speed_kmh(), 5.0, "fährt los")
	assert_gt(fast.model.speed_kmh(), slow.model.speed_kmh() * 1.3, "mehr Kadenz → schneller")
	assert_gt(fast.model.distance_m - FLAT_M, slow.model.distance_m - FLAT_M, "und weiter")


func test_same_cadence_slower_uphill_faster_downhill() -> void:
	var bus := start_fake_bus(_steady(80.0))
	var flat := spawn_ride(bus, FLAT_M)
	var up := spawn_ride(bus, CLIMB_M)
	var down := spawn_ride(bus, DESCENT_M)
	await run_for(RIDE_S)
	assert_almost_eq(flat.current_grade(), 0.0, 0.001)
	assert_gt(up.current_grade(), 0.05, "Fahrer ist noch im Anstieg")
	assert_lt(down.current_grade(), -0.05, "Fahrer ist noch in der Abfahrt")
	assert_lt(up.model.speed_kmh(), flat.model.speed_kmh() * 0.8, "bergauf langsamer")
	assert_gt(down.model.speed_kmh(), flat.model.speed_kmh(), "bergab schneller")
	assert_lt(down.model.speed_kmh(), flat.model.speed_kmh() * 1.3, "bergab nur etwas schneller")


func test_speed_has_inertia() -> void:
	var bus := start_fake_bus(_steady(90.0))
	var ride := spawn_ride(bus, FLAT_M)
	assert_true(await run_until(func(): return ride.bus.cadence == 90.0, 3.0))
	var target_kmh: float = ride.model.target_speed_mps(90.0, 0.0) * RideModel.KMH_PER_MPS
	assert_lt(ride.model.speed_kmh(), target_kmh * 0.5, "kurz nach Kadenzbeginn noch langsam")
	var early: float = ride.model.speed_kmh()
	await run_for(0.5)
	assert_gt(ride.model.speed_kmh(), early, "beschleunigt allmählich")
	await run_for(RIDE_S)
	assert_almost_eq(ride.model.speed_kmh(), target_kmh, target_kmh * 0.15, "nähert sich v_ziel")


func test_cadence_drop_slows_down_gradually() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 3.0) \
			+ FakeBusServer.steady_cadence(30.0, 3.25, 8.0)
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	assert_true(await run_until(func(): return ride.bus.cadence == 30.0, 6.0))
	var before: float = ride.model.speed_kmh()
	await run_for(0.3)
	assert_lt(ride.model.speed_kmh(), before, "wird langsamer")
	assert_gt(ride.model.speed_kmh(), 30.0 * 0.33 * 1.2, "aber nicht schlagartig")


func test_config_file_changes_ride_feel() -> void:
	var bus := start_fake_bus(_steady(80.0))
	var standard := spawn_ride(bus, FLAT_M)
	var high_k := spawn_ride(bus, FLAT_M, config_for(bus, "res://tests/fixtures/high_k.cfg"))
	await run_for(RIDE_S)
	assert_gt(high_k.model.speed_kmh(), standard.model.speed_kmh() * 1.3, "höheres k aus der Datei → schneller")


func test_rider_follows_the_path_and_hud_shows_values() -> void:
	var ride := spawn_ride(start_fake_bus(_steady(90.0)), FLAT_M)
	await run_for(2.0)
	var rider: PathFollow3D = ride.get_node("Track/Rider")
	assert_almost_eq(rider.progress, ride.track.wrap_distance(ride.model.distance_m), 0.01)
	assert_gt(rider.progress, FLAT_M)
	var hud: String = ride.get_node("Hud").readout()
	assert_string_contains(hud, "Kadenz: 90 rpm")
	assert_string_contains(hud, "%.1f km/h" % ride.model.speed_kmh())
