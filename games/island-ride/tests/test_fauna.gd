## Weide- und Dorftiere (#40): alle Arten (mit denen aus #41, Einzelheiten in test_wild_animals.gd) stehen an
## passenden Orten (Station, Abstand zur Fahrbahn, nicht auf Feldern, nicht in Häusern), bewegen sich als Funktion der Zeit, die Ziegen räumen die Fahrbahn rechtzeitig vor dem
## Fahrer – in beiden Richtungen –, die Tiere wirken nicht auf die Fahrt (ADR-0010) und der Browser-Pfad baut ohne
## Fehler. Geprüft über die Lagen in IslandFauna (headless liefern MultiMeshes keine Transforms).
extends "res://tests/support/bus_test.gd"

## Stationen je Art.
const STATIONS := {"Schafe": ["hain", "abfahrt"], "Ziegen": ["serpentinen", "kueste"], "Esel": ["abfahrt"],
		"Katzen": ["bergdorf"], "Delfine": ["hafen", "kueste"], "Fische": ["hafen", "kueste"], "Geier": ["serpentinen"],
		"Schmetterlinge": ["kueste", "serpentinen", "hain", "abfahrt"], "Eidechsen": ["kueste", "serpentinen"]}
const MIN_COUNT := {"Schafe": 10, "Ziegen": 10, "Esel": 3, "Katzen": 6, "Delfine": 6, "Fische": 6, "Geier": 3,
		"Schmetterlinge": 12, "Eidechsen": 10}
## Eidechsen sitzen auf der Mauer am Straßenrand (Innenkante 3,55 m von der Mitte) – neben, nicht auf der Fahrbahn.
const WALL_INNER_M := 3.5
## Spätestens so weit (m) vor dem Fahrer ist die Fahrbahn frei – fest, unabhängig von IslandFauna.CROSSING_CLEAR_M.
const ROAD_FREE_AHEAD_M := 30.0


func _world() -> IslandWorld:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return ride.get_node("World")


## Abstand von `at` zum nächsten Getreidehalm (#39), INF ohne Felder.
func _field_distance(world: IslandWorld, at: Vector3) -> float:
	var best := INF
	for station in world.vegetation.placements:
		for p in world.vegetation.placements[station].get("Getreide", PackedVector3Array()):
			best = minf(best, Vector2(p.x - at.x, p.z - at.z).length())
	return best


func test_all_kinds_stand_at_fitting_places() -> void:
	var world := _world()
	var fauna := world.fauna
	var village := world._station_range("bergdorf")
	var square := (village.x + village.y) / 2.0
	var wrong := []
	for kind in IslandFauna.KINDS:
		var at_all := fauna.positions(kind)
		assert_gte(at_all.size(), MIN_COUNT[kind], "%s vorhanden" % kind)
		var radius: float = IslandFauna.RADIUS_M[kind]
		for at in at_all:
			var d := world.track.curve.get_closest_offset(at)
			var station: String = world.track.station_at(d)["id"]
			if station not in STATIONS[kind]:
				wrong.append("%s bei %s auf %s" % [kind, at, station])
			var clearance := world.landmarks.road_clearance(at) - radius
			if clearance < (WALL_INNER_M if kind == "Eidechsen" else IslandVegetation.ROAD_CLEARANCE_M):
				wrong.append("%s bei %s auf der Fahrbahn (%.1f m)" % [kind, at, clearance])
			if station == "abfahrt" and _field_distance(world, at) < radius:
				wrong.append("%s bei %s auf einem Feld" % [kind, at])
			if kind == "Katzen":
				# nicht in den Häuserzeilen (6,6–18 m beidseits), außer auf dem Kirchplatz rechts
				var side := world._side_offset(d, 1.0).dot(at - world.track.position_at(d))
				var on_square := side > 0.0 and absf(d - square) < 22.0
				if absf(side) > 6.6 and absf(side) < 18.0 and not on_square:
					wrong.append("Katze bei %s in einem Haus (%.1f m seitlich)" % [at, side])
		if kind == "Esel":
			for at in at_all:
				for finca in fauna._fincas:
					if Vector2(at.x - finca.x, at.z - finca.z).length() < IslandFauna.FINCA_RADIUS_M:
						wrong.append("Esel bei %s im Finca-Haus" % at)
	assert_eq(wrong, [], "Tiere an passenden Orten")
	assert_not_null(world.get_node_or_null("Details/Schafe/Koepfe"), "Köpfe der Herde als eigenes MultiMesh")
	assert_gte(fauna.bell_herds.size(), 2, "Glocken-Knoten je Schafherde (#44)")
	for herd in fauna.bell_herds:
		assert_gt(herd["node"].get_meta("count"), 0, "Schafe an %s" % herd["node"].name)


func test_animals_move_as_a_function_of_time() -> void:
	var fauna := _world().fauna
	var snapshot := func() -> Array:
		var state := []
		for grazer in fauna.grazers:
			state.append([grazer["now"], grazer["head"]])
		for donkey in fauna.donkeys:
			state.append([donkey["head"].rotation, donkey["tail"].rotation])
		for cat in fauna.cats:
			state.append([cat["node"].position, cat["head"].rotation, cat["tail"].rotation])
		for crossing in fauna.crossings:
			for goat in crossing["goats"]:
				state.append([goat["head"].rotation])
		return state
	fauna.apply(3.0)
	var early: Array = snapshot.call()
	fauna.apply(8.7)
	var late: Array = snapshot.call()
	var moved := 0
	for k in range(early.size()):
		if early[k] != late[k]:
			moved += 1
	assert_gt(float(moved), early.size() * 0.8, "Tiere bewegen sich zwischen t1 und t2 (%d von %d)" % [moved, early.size()])
	var walked := 0
	for cat in fauna.cats:
		if cat["walk_m"] > 0.0:
			fauna.apply(0.0)
			var start: Vector3 = cat["node"].position
			fauna.apply(6.0)
			if start.distance_to(cat["node"].position) > 0.5:
				walked += 1
	assert_gt(walked, 1, "Katzen streifen umher")
	fauna.apply(3.0)
	assert_eq(snapshot.call(), early, "derselbe Zeitpunkt ergibt denselben Stand")


func test_goats_clear_the_road_before_the_rider_in_both_directions() -> void:
	var world := _world()
	var fauna := world.fauna
	var track := world.track
	assert_eq(fauna.crossings.size(), IslandFauna.CROSSINGS_M.size(), "Querungen")
	for direction in [Track.DIRECTION_CW, Track.DIRECTION_CCW]:
		track.set_direction(direction)
		world.set_direction(direction)
		for crossing in fauna.crossings:
			var spot_ride_m := track.path_distance(crossing["path_m"])
			var on_road := false
			var sides := {}
			var gap := 400.0
			while gap >= -80.0:
				fauna.apply(gap, track.path_distance(spot_ride_m - gap))
				var nearest := INF
				for goat in crossing["goats"]:
					var at: Vector3 = crossing["node"].position + goat["node"].position
					nearest = minf(nearest, world.landmarks.road_clearance(at))
					var d := track.curve.get_closest_offset(at)
					sides[signf(world._side_offset(d, 1.0).dot(at - track.position_at(d)))] = true
				if nearest < Track.ROAD_WIDTH_M / 2.0:
					on_road = true
				if gap <= ROAD_FREE_AHEAD_M:
					assert_gt(nearest, IslandVegetation.ROAD_CLEARANCE_M + IslandFauna.RADIUS_M["Ziegen"],
							"%s %s: Fahrbahn frei bei %.0f m Abstand (%.1f m)" % [direction, crossing["node"].name, gap, nearest])
				gap -= 2.0
			assert_true(on_road, "%s %s: Ziegen queren die Straße" % [direction, crossing["node"].name])
			assert_eq(sides.size(), 2, "%s %s: von einer Seite auf die andere" % [direction, crossing["node"].name])
	track.set_direction(Track.DIRECTION_CW)
	world.set_direction(Track.DIRECTION_CW)


## ADR-0010: Die Querung bremst nicht und ändert weder Strecke noch Steigung – mit und ohne Tiere fährt der Fahrer
## gleich; im Spiel (Fahrerposition aus `Track/Rider`) ist die Fahrbahn frei, wenn er die Querung passiert.
func test_animals_do_not_affect_the_ride() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 12.0)
	var bus := start_fake_bus(steps)
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	var spot: float = IslandFauna.CROSSINGS_M[0]
	var start := spot - 30.0
	var with_animals := spawn_ride(bus, start, config)
	var without := spawn_ride(bus, start, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	var fauna: IslandFauna = with_animals.world.fauna
	var grade_before: float = with_animals.track.grade_at(spot)
	without.world.fauna.free()
	var crossing: Dictionary = fauna.crossings[0]
	var blocked := []
	var passed := func() -> bool: return with_animals.model.distance_m > spot + 5.0
	var deadline := Time.get_ticks_msec() + 15000
	while not passed.call() and Time.get_ticks_msec() < deadline:
		await run_for(0.05)
		if with_animals.state == with_animals.STATE_RIDING and absf(with_animals.model.distance_m - spot) < 10.0:
			for goat in crossing["goats"]:
				var at: Vector3 = crossing["node"].position + goat["node"].position
				if with_animals.world.landmarks.road_clearance(at) < IslandVegetation.ROAD_CLEARANCE_M:
					blocked.append(at)
	assert_true(passed.call(), "Fahrer passiert die Querung")
	assert_eq(blocked, [], "keine Ziege auf der Fahrbahn, wenn der Fahrer vorbeikommt")
	assert_almost_eq(with_animals.track.grade_at(spot), grade_before, 0.0001, "Steigung unverändert")
	assert_almost_eq(with_animals.model.distance_m, without.model.distance_m, 3.0, "gleich weit wie ohne Tiere")
	assert_almost_eq(with_animals.model.speed_kmh(), without.model.speed_kmh(), 1.0, "gleich schnell wie ohne Tiere")
	assert_almost_eq(fauna.rider_path_m, with_animals.rider.progress, 0.001, "Fahrerposition aus Track/Rider")


## Browser-Pfad: die Welt im Compatibility-Profil baut mit allen Tieren ohne Fehler.
func test_browser_profile_builds_the_animals() -> void:
	var track := Track.new()
	IslandCourse.apply_to(track)
	add_child_autofree(track)
	var world := IslandWorld.new()
	world.compatibility = true
	add_child_autofree(world)
	world.build(track)
	for kind in IslandFauna.KINDS:
		assert_gte(world.fauna.positions(kind).size(), MIN_COUNT[kind], "%s im Browser" % kind)
	world.fauna.apply(5.0, 100.0)
	await run_for(0.2)
	assert_gt(world.fauna.time_s, 5.0, "Tiere leben im Browser-Profil")
