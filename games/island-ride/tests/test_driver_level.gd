## Fahrerlevel (#35): die Kurve, Aufstieg über Fahrtgrenzen hinweg, Kilometer aus jedem Modus, Freischaltung nur von
## Kosmetik – und ADR-0010: ein höheres Level ändert Rundenzeit, Medaille und Bestzeit nicht.
extends "res://tests/support/bus_test.gd"

const DT := 1.0 / 60.0


## Zusammenfassung einer Fahrt über `km` im Modus `mode`.
func _ride(km: float, mode: String = SaveGame.MODE_ROUND_TRIP) -> Dictionary:
	var stats := RideStats.new()
	stats.add(km * 150.0, 85.0, km * 1000.0)
	return SaveGame.ride_entry(mode, RideConfig.TRACK_ISLAND, false, 0, stats, "2026-10-07T18:00:00Z")


func test_curve() -> void:
	assert_eq(DriverLevel.km_for(1), 0.0, "Level 1 ab dem ersten Meter")
	assert_eq(DriverLevel.km_for(2), 10.0)
	assert_eq(DriverLevel.km_for(3), 25.0)
	assert_eq(DriverLevel.km_for(5), 70.0)
	assert_eq(DriverLevel.km_for(10), 270.0)
	assert_eq(DriverLevel.level_for(0.0), 1)
	assert_eq(DriverLevel.level_for(9.99), 1)
	assert_eq(DriverLevel.level_for(10.0), 2)
	assert_eq(DriverLevel.level_for(24.9), 2)
	assert_eq(DriverLevel.level_for(25.0), 3)
	var step := 0.0
	for level in range(2, DriverLevel.MAX_LEVEL + 1):
		var next := DriverLevel.km_for(level) - DriverLevel.km_for(level - 1)
		assert_gt(next, step, "jeder Schritt etwas länger (Level %d)" % level)
		step = next
		assert_eq(DriverLevel.level_for(DriverLevel.km_for(level)), level, "Level %d genau an seiner Schwelle" % level)
	assert_eq(DriverLevel.level_for(1.0e9), DriverLevel.MAX_LEVEL, "höchstens MAX_LEVEL")
	assert_eq(DriverLevel.km_to_next(4.0), 6.0, "noch 6 km bis Level 2")
	assert_eq(DriverLevel.km_to_next(1.0e9), INF, "auf dem höchsten Level kein nächstes")


func test_level_rises_across_ride_boundaries() -> void:
	var save := SaveGame.new()
	save.add_ride(_ride(6.0))
	assert_eq(DriverLevel.level_for(save.total_km()), 1, "6 km: Level 1")
	save.add_ride(_ride(6.0))
	assert_eq(DriverLevel.level_for(save.total_km()), 2, "zwei Fahrten zu 6 km: Level 2 – die km zählen über Fahrten")
	save.add_ride(_ride(13.5))
	assert_eq(DriverLevel.level_for(save.total_km()), 3, "25,5 km: Level 3")


func test_km_from_every_mode_count() -> void:
	var save := SaveGame.new()
	for mode in [SaveGame.MODE_ROUND_TRIP, "training", "arcade"]:
		save.add_ride(_ride(10.0, mode))
	assert_almost_eq(save.total_km(), 30.0, 0.001, "jeder Modus zählt")
	assert_eq(DriverLevel.level_for(save.total_km()), 3)
	save.rides().append({"mode": "training", "distance_km": "kaputt"})
	assert_almost_eq(save.total_km(), 30.0, 0.001, "ungültige Einträge zählen nicht")


func test_level_unlocks_only_cosmetics() -> void:
	for item in DriverLevel.UNLOCKS:
		assert_true(item.begins_with("trikot_") or item.begins_with("radfarbe_") or item.begins_with("helm_"),
				"%s ist Kosmetik (Trikot, Radfarbe, Helm)" % item)
		var level: int = DriverLevel.unlock_level(item)
		assert_between(level, 1, DriverLevel.MAX_LEVEL)
		assert_false(DriverLevel.unlocked(item, level - 1), "%s vor Level %d gesperrt" % [item, level])
		assert_true(DriverLevel.unlocked(item, level), "%s ab Level %d frei" % [item, level])
	for item in Wardrobe.DEFAULTS.values():
		assert_eq(DriverLevel.unlock_level(item), 1, "Grundausstattung %s ab Level 1" % item)
	assert_eq(DriverLevel.unlock_level("unbekannt"), 1, "unbekannte Teile ab Level 1")


## Eine Runde Graybox mit fester Kadenz, Schritt für Schritt (wie tests/test_round_trip.gd). Liefert die Hauptszene.
func _lap(ride: Node) -> Node:
	ride.set_process(false)
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
	for i in range(100000):
		if not ride.lap_timing.lap_times.is_empty():
			break
		ride._ride(DT)
	assert_eq(ride.lap_timing.lap_times.size(), 1, "Runde zu Ende gefahren")
	return ride


func _riding() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == 90.0, 3.0))
	return ride


func test_higher_level_changes_neither_lap_time_medal_nor_best_time() -> void:
	var beginner := _lap(await _riding())
	var veteran_ride := await _riding()
	for i in range(40):
		veteran_ride.save_game.add_ride(_ride(50.0))  # 2000 km
	var veteran := _lap(veteran_ride)
	assert_gt(veteran.ride_level, 20, "Fahrerlevel hoch")
	assert_eq(beginner.ride_level, 1)
	assert_eq(veteran.lap_timing.lap_times[0], beginner.lap_timing.lap_times[0], "gleiche Rundenzeit (ADR-0010)")
	assert_eq(veteran.lap_medal(0), beginner.lap_medal(0), "gleiche Medaille")
	assert_eq(veteran.medal_limits, beginner.medal_limits, "gleiche Medaillen-Schwellen")
	for ride in [beginner, veteran]:
		ride._save_ride()
	assert_eq(veteran.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW),
			beginner.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), "gleiche Bestzeit")
