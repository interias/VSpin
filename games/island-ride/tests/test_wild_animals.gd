## Tiere an Meer, Himmel und Wegrand (#41): Delfine und Fische auf Meereshöhe in den Buchten vom Weg aus sichtbar,
## Geier hoch über den Serpentinen, Schmetterlinge am Wegrand, Eidechsen auf der Mauer – nie auf der Fahrbahn; alle
## bewegen sich als Funktion der Zeit; die Regel für Tag/Nacht, Wetter und Jahreszeit (IslandFauna.shown) und ihr
## Durchgriff über den SkyController; der Browser-Pfad baut abgespeckt ohne Fehler.
extends "res://tests/support/bus_test.gd"

const NEW_KINDS := ["Delfine", "Fische", "Geier", "Schmetterlinge", "Eidechsen"]
## Vom Weg aus sichtbar: höchstens so weit (m, waagerecht) von der Straße entfernt.
const SEA_IN_VIEW_M := 300.0
## Geier mindestens so hoch (m) über der Straße unter ihnen.
const VULTURE_ABOVE_ROAD_M := 40.0
## Eidechsen auf der Mauerkrone: Abstand zur Straßenmitte (Innen- bis Außenkante der Mauer) und Höhe über der Straße.
const WALL_FROM_M := 3.5
const WALL_TO_M := 4.1
const WALL_TOP_M := 0.6
## Wetter-Kennwerte wie Weather.STATES, fest für die Regel-Tests.
const CLEAR := {"cloud": 0.25, "haze": 0.0, "rain": 0.0, "wind": 1.0}
const OVERCAST := {"cloud": 0.9, "haze": 0.55, "rain": 0.0, "wind": 1.7}
const RAIN := {"cloud": 1.0, "haze": 0.8, "rain": 1.0, "wind": 2.2}


func _ride() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	return spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))


## Waagerechter Abstand von `at` zum nächsten Punkt der Straße (Stichproben alle 5 m) und dieser Punkt.
func _nearest_road(track: Track, at: Vector3) -> Array:
	var best := INF
	var best_m := 0.0
	var d := 0.0
	while d < track.length_m():
		var p := track.position_at(d)
		var gap := Vector2(p.x - at.x, p.z - at.z).length()
		if gap < best:
			best = gap
			best_m = d
		d += 5.0
	return [best, best_m]


func test_sea_sky_and_roadside_animals_stand_at_fitting_places() -> void:
	var world: IslandWorld = _ride().world
	var fauna := world.fauna
	var track := world.track
	var wrong := []
	for kind in NEW_KINDS:
		assert_not_null(world.get_node_or_null("Fauna/" + kind), "Gruppe Fauna/%s" % kind)
	# Delfine: der ganze Kreis über tiefem Wasser, vom Weg aus zu sehen; Höhe zwischen Tauchtiefe und Sprunghöhe
	for dolphin in fauna.dolphins:
		var centre: Vector3 = dolphin["centre"]
		for k in range(12):
			var a := k * TAU / 12.0
			var p: Vector3 = centre + Vector3(cos(a), 0.0, sin(a)) * dolphin["radius"]
			if world.terrain.height_at(p.x, p.z) > -3.0:
				wrong.append("Delfin bei %s über flachem Wasser oder Land" % p)
		if _nearest_road(track, centre)[0] > SEA_IN_VIEW_M:
			wrong.append("Delfine bei %s außer Sicht der Straße" % centre)
	# Fische: im Wasser nah am Ufer unter der Straße
	for entry in fauna.fish:
		var spot: Vector3 = entry["spot"]
		if world.terrain.height_at(spot.x, spot.z) > -1.0:
			wrong.append("Fisch bei %s nicht im Wasser" % spot)
		if _nearest_road(track, spot)[0] > 120.0:
			wrong.append("Fisch bei %s außer Sicht der Straße" % spot)
	# Geier: über den Serpentinen, hoch über der Straße
	for vulture in fauna.vultures:
		var at: Vector3 = vulture["node"].position
		var nearest: Array = _nearest_road(track, at)
		if track.station_at(nearest[1])["id"] != "serpentinen":
			wrong.append("Geier bei %s nicht über den Serpentinen" % at)
		if at.y - track.position_at(nearest[1]).y < VULTURE_ABOVE_ROAD_M:
			wrong.append("Geier bei %s zu tief" % at)
	# Schmetterlinge: am Wegrand, über die ganze Flugbahn nicht auf der Fahrbahn und keinem Feld
	var radius: float = IslandFauna.RADIUS_M["Schmetterlinge"]
	for butterfly in fauna.butterflies:
		if world.landmarks.road_clearance(butterfly["base"]) > IslandFauna.BUTTERFLY_ROADSIDE_M:
			wrong.append("Schmetterling bei %s nicht am Wegrand" % butterfly["base"])
		for k in range(20):
			var p := IslandFauna.flutter_point(butterfly, k * 1.7)
			if world.landmarks.road_clearance(p) - radius < IslandVegetation.ROAD_CLEARANCE_M or fauna.on_field(p, radius):
				wrong.append("Schmetterling bei %s auf Fahrbahn oder Feld" % p)
			if p.y < world.terrain.height_at(p.x, p.z) - 0.3:
				wrong.append("Schmetterling bei %s im Boden" % p)
	# Eidechsen: zu jeder Zeit auf der Mauerkrone neben der Fahrbahn, an Küstenstraße und Serpentinen
	for t in [0.0, 2.3, 5.1, 9.8]:
		fauna.apply(t)
		for lizard in fauna.lizards:
			var at: Vector3 = lizard["node"].position
			var d := track.curve.get_closest_offset(at)
			var side := Vector2(at.x - track.position_at(d).x, at.z - track.position_at(d).z).length()
			if side < WALL_FROM_M or side > WALL_TO_M:
				wrong.append("Eidechse bei %s nicht auf der Mauer (%.2f m)" % [at, side])
			if absf(at.y - track.position_at(d).y - WALL_TOP_M) > 0.15:
				wrong.append("Eidechse bei %s nicht auf der Mauerkrone" % at)
			if track.station_at(d)["id"] not in ["kueste", "serpentinen"]:
				wrong.append("Eidechse bei %s außerhalb von Küste und Serpentinen" % at)
	assert_eq(wrong, [], "Tiere an Meer, Himmel und Wegrand an passenden Orten")


func test_animals_move_as_a_function_of_time() -> void:
	var fauna: IslandFauna = _ride().world.fauna
	var snapshot := func() -> Array:
		var state := []
		for kind in NEW_KINDS:
			for node in fauna.groups[kind].find_children("*", "Node3D", true, false):
				state.append([node.get_path(), node.transform])
		return state
	fauna.apply(3.0)
	var early: Array = snapshot.call()
	fauna.apply(8.7)
	var late: Array = snapshot.call()
	var moved := {}
	for k in range(early.size()):
		if early[k][1] != late[k][1]:
			var kind: String = str(early[k][0]).get_slice("/Fauna/", 1).get_slice("/", 0)
			moved[kind] = moved.get(kind, 0) + 1
	for kind in NEW_KINDS:
		assert_gt(moved.get(kind, 0), 0, "%s bewegen sich zwischen t1 und t2" % kind)
	fauna.apply(3.0)
	assert_eq(snapshot.call(), early, "derselbe Zeitpunkt ergibt denselben Stand")
	# Sprünge: Delfine und Fische tauchen in 20 s auf und wieder ab
	var dolphin_up := 0.0
	var fish_seen := 0
	var dashes := 0
	fauna.apply(0.0)
	var starts := []
	for lizard in fauna.lizards:
		starts.append(lizard["node"].position)
	for step in range(200):
		fauna.apply(step * 0.1)
		for dolphin in fauna.dolphins:
			dolphin_up = maxf(dolphin_up, dolphin["node"].position.y)
		for entry in fauna.fish:
			if entry["node"].visible:
				fish_seen += 1
	for k in range(fauna.lizards.size()):
		if starts[k].distance_to(fauna.lizards[k]["node"].position) > 0.5:
			dashes += 1
	assert_gt(dolphin_up, 0.3, "Delfine springen aus dem Wasser")
	assert_lt(dolphin_up, IslandFauna.LEAP_M - IslandFauna.DIVE_M + 0.01, "und bleiben über dem Meer")
	assert_gt(fish_seen, 0, "Fische springen")
	assert_gt(dashes, 0, "Eidechsen huschen")


## Die Regel steht an einer Stelle (IslandFauna.SHOWN_WHEN/shown) – geprüft als reine Funktion.
func test_day_night_weather_and_season_rule() -> void:
	var day := 45.0
	var night := -20.0
	for kind in NEW_KINDS:
		assert_true(IslandFauna.shown(kind, day, CLEAR, Season.SPRING), "%s an einem klaren Frühlingstag" % kind)
	assert_false(IslandFauna.shown("Schmetterlinge", day, RAIN, Season.SPRING), "keine Schmetterlinge bei Regen")
	assert_false(IslandFauna.shown("Schmetterlinge", night, CLEAR, Season.SPRING), "keine Schmetterlinge nachts")
	assert_false(IslandFauna.shown("Schmetterlinge", day, CLEAR, Season.WINTER), "keine Schmetterlinge im Winter")
	assert_false(IslandFauna.shown("Eidechsen", night, CLEAR, Season.SUMMER), "Eidechsen nachts weg")
	assert_false(IslandFauna.shown("Eidechsen", day, OVERCAST, Season.SUMMER), "Eidechsen nur bei Sonne")
	assert_false(IslandFauna.shown("Geier", night, CLEAR, Season.SUMMER), "Geier nur tagsüber")
	for kind in ["Delfine", "Fische", "Schmetterlinge"]:
		assert_true(IslandFauna.shown(kind, day, OVERCAST, Season.AUTUMN), "%s auch bei Bewölkung" % kind)
	assert_true(IslandFauna.shown("Delfine", day, RAIN, Season.AUTUMN), "Delfine auch bei Regen")
	for kind in ["Schafe", "Ziegen", "Esel", "Katzen"]:
		assert_true(IslandFauna.shown(kind, night, RAIN, Season.WINTER), "%s (#40) bleiben" % kind)


## Der SkyController stellt die Arten nach Uhr, Wetter und Jahreszeit (Abnahme: keine Schmetterlinge bei Regen).
func test_sky_controller_applies_the_rule() -> void:
	var ride := _ride()
	var sky: SkyController = ride.sky
	var groups: Dictionary = ride.world.fauna.groups
	sky.set_season_mode(Season.MODE_FIXED, Season.SPRING)
	sky.set_time_mode(DayNight.MODE_FIXED, 13.0)
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.CLEAR)
	sky.weather.snap()
	sky.apply_now()
	for kind in NEW_KINDS:
		assert_true(groups[kind].visible, "%s mittags bei Sonne" % kind)
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.RAIN)
	sky.weather.snap()
	sky.apply_now()
	assert_false(groups["Schmetterlinge"].visible, "keine Schmetterlinge bei Regen")
	assert_false(groups["Eidechsen"].visible, "keine Eidechsen bei Regen")
	assert_true(groups["Delfine"].visible, "Delfine auch bei Regen")
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.CLEAR)
	sky.weather.snap()
	sky.set_time_mode(DayNight.MODE_FIXED, 1.0)
	for kind in NEW_KINDS:
		assert_false(groups[kind].visible, "%s nachts nicht zu sehen" % kind)
	sky.set_time_mode(DayNight.MODE_FIXED, 13.0)
	sky.set_season_mode(Season.MODE_FIXED, Season.WINTER)
	assert_false(groups["Schmetterlinge"].visible, "keine Schmetterlinge im Winter")
	assert_true(groups["Eidechsen"].visible, "Eidechsen an einem sonnigen Wintermittag")


## Browser-Pfad: abgespeckt (weniger Schmetterlinge, Fische, Eidechsen), baut und bewegt sich ohne Fehler.
func test_browser_profile_builds_fewer_animals() -> void:
	var track := Track.new()
	IslandCourse.apply_to(track)
	add_child_autofree(track)
	var world := IslandWorld.new()
	world.compatibility = true
	add_child_autofree(world)
	world.build(track)
	var fauna := world.fauna
	for kind in NEW_KINDS:
		assert_gt(fauna.positions(kind).size(), 0, "%s im Browser" % kind)
	assert_lt(fauna.butterflies.size(), IslandFauna.BUTTERFLY_STATIONS.size() * IslandFauna.BUTTERFLY_SPOTS * IslandFauna.BUTTERFLY_PAIR,
			"weniger Schmetterlinge im Browser")
	assert_lt(fauna.fish.size(), IslandFauna.FISH_SPOTS.size() * 2, "weniger Fische im Browser")
	fauna.set_conditions(30.0, CLEAR, Season.SUMMER)
	fauna.apply(5.0, 100.0)
	await run_for(0.2)
	assert_gt(fauna.time_s, 5.0, "Tiere leben im Browser-Profil")
