## Fahrt auf dem Insel-Rundkurs gegen den Fake-Bus (#14): Standardstrecke ist die Insel, die Welt hat alle
## Stationen, die Steigung je Position wirkt im Fahrmodell und geht per `set_grade` an den Bus, die Runde endet
## im Hafen, die Kamera folgt ruhig. Kurze Fahrten ab passenden Streckenpositionen – nicht 9 km in Echtzeit.
extends "res://tests/support/bus_test.gd"

const STATIONS := ["hafen", "kueste", "serpentinen", "hain", "bergdorf", "abfahrt"]


func _steady(cadence: float, until_s: float = 10.0) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, until_s)


func _island(bus: FakeBusServer) -> RideConfig:
	return config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)


## Mitte des Abschnitts `id` auf dem Insel-Rundkurs (Streckenposition).
func _middle_of(id: String) -> float:
	var stations := IslandCourse.stations()
	for i in range(stations.size()):
		if stations[i]["id"] == id:
			var track: Track = autofree(Track.new())
			IslandCourse.apply_to(track)
			var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else track.length_m()
			return (stations[i]["start_m"] + end) / 2.0
	return 0.0


func test_island_is_the_default_track() -> void:
	assert_eq(RideConfig.load_file().track, RideConfig.TRACK_ISLAND, "config.cfg: [world] track")
	assert_eq(RideConfig.new().track, RideConfig.TRACK_ISLAND, "Standardwert")
	var bus := start_fake_bus(_steady(80.0))
	var ride := spawn_ride(bus, 0.0, _island(bus))
	assert_between(ride.track.length_m(), 8000.0, 10000.0)
	assert_not_null(ride.get_node_or_null("World/Terrain"), "Gelände")
	assert_not_null(ride.get_node_or_null("World/Sea"), "Meer")
	assert_not_null(ride.get_node_or_null("World/Road"), "Fahrbahn")


func test_world_marks_all_stations_in_order() -> void:
	var bus := start_fake_bus(_steady(80.0))
	var ride := spawn_ride(bus, 0.0, _island(bus))
	var last := -1.0
	for id in STATIONS + ["aussichtspunkt"]:
		var marker: Node3D = ride.get_node_or_null("World/Stations/" + id)
		assert_not_null(marker, "Marker %s" % id)
		if marker == null:
			continue
		var label: Label3D = marker.get_node("Label")
		assert_eq(label.text, marker.get_meta("station_name"))
		# Marker liegt auf der Strecke; Reihenfolge entlang des Pfads
		var along: float = ride.track.curve.get_closest_offset(ride.track.to_local(marker.global_position))
		assert_almost_eq(along, float(marker.get_meta("distance_m")), 1.0, "%s auf der Strecke" % id)
		if id != "aussichtspunkt":
			assert_gt(along + 0.001, last, "%s nach dem vorigen" % id)
			last = along
		if id in STATIONS:
			var props: Node = ride.get_node_or_null("World/Props/" + id)
			assert_true(props != null and props.get_child_count() > 0, "Grundform/Deko für %s" % id)
	var serpentines: float = ride.get_node("World/Stations/serpentinen").get_meta("distance_m")
	var grove: float = ride.get_node("World/Stations/hain").get_meta("distance_m")
	assert_between(float(ride.get_node("World/Stations/aussichtspunkt").get_meta("distance_m")), serpentines, grove,
			"Aussichtspunkt gehört zu den Serpentinen")


func test_short_ride_on_serpentines_progresses_and_reports_grade() -> void:
	var bus := start_fake_bus(_steady(80.0))
	var start_m := _middle_of("serpentinen")
	var ride := spawn_ride(bus, start_m, _island(bus))
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	assert_true(await run_until(func(): return not bus.received_of_type("set_grade").is_empty(), 3.0))
	await run_for(2.0)
	assert_gt(ride.model.distance_m, start_m + 4.0, "Fahrer kommt voran")
	var grade: float = bus.received_of_type("set_grade")[-1]["message"]["grade"]
	assert_between(grade, 0.04, 0.10, "Serpentinen: Steigung gemeldet")
	assert_almost_eq(grade, ride.current_grade(), 0.006, "gemeldet = Steigung an der Fahrerposition")
	assert_string_contains(ride.get_node("Hud").readout(), "Abschnitt: Serpentinen")
	assert_string_contains(ride.get_node("Hud").readout(), "Steigung: +")


func test_grade_by_position_changes_speed() -> void:
	var up_bus := start_fake_bus(_steady(80.0))
	var down_bus := start_fake_bus(_steady(80.0))
	var up := spawn_ride(up_bus, _middle_of("serpentinen"), _island(up_bus))
	var down := spawn_ride(down_bus, _middle_of("abfahrt"), _island(down_bus))
	await run_for(3.0)
	assert_between(up.current_grade(), 0.03, 0.10, "bergauf")
	assert_lt(down.current_grade(), -0.03, "bergab")
	assert_gt(down.model.speed_kmh(), up.model.speed_kmh() * 1.4, "gleiche Kadenz: bergab deutlich schneller")
	assert_string_contains(down.get_node("Hud").readout(), "Abschnitt: Abfahrt")
	var sent: Array = down_bus.received_of_type("set_grade")
	assert_false(sent.is_empty())
	if not sent.is_empty():
		assert_lt(sent[-1]["message"]["grade"], -0.03, "Gefälle wird als negative Steigung gemeldet")


func test_lap_finishes_at_the_harbour() -> void:
	var bus := start_fake_bus(_steady(90.0))
	var config := _island(bus)
	config.inertia_s = 0.0
	var probe: Track = autofree(Track.new())
	IslandCourse.apply_to(probe)
	var ride := spawn_ride(bus, probe.length_m() - 15.0, config)
	assert_true(await run_until(func(): return ride.state == "finished", 6.0), "Ziellinie überfahren")
	assert_eq(ride.track.station_at(ride.model.distance_m)["id"], "hafen", "Ziel im Hafen")
	assert_almost_eq(ride.track.position_at(ride.model.distance_m).distance_to(ride.track.position_at(0.0)), 0.0, 0.5)


func test_camera_follows_behind_and_is_smoothed() -> void:
	var bus := start_fake_bus(_steady(90.0))
	var ride := spawn_ride(bus, _middle_of("kueste"), _island(bus))
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	await run_for(1.5)
	var camera: Camera3D = ride.get_node("Camera")
	var rider: Node3D = ride.get_node("Track/Rider")
	var gap := camera.global_position.distance_to(rider.global_position)
	assert_between(gap, 5.0, 15.0, "Kamera hinter dem Fahrer")
	assert_gt(camera.global_position.y, rider.global_position.y + 1.5, "Kamera über dem Fahrer")
	var forward := -camera.global_transform.basis.z
	assert_gt(forward.dot((rider.global_position - camera.global_position).normalized()), 0.8, "Kamera blickt auf den Fahrer")
	# Sprung um 100 m (z. B. großer Zeitschritt): die Kamera gleitet hinterher, statt zu springen.
	var before := camera.global_position
	ride.model.distance_m += 100.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(camera.global_position.distance_to(before), 30.0, "geglättet: kein Sprung")
	await run_for(3.0)
	assert_between(camera.global_position.distance_to(rider.global_position), 5.0, 15.0, "holt wieder auf")
