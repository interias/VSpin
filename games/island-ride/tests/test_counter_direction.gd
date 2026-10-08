## Gegenrichtung (#34) als reine Logik: derselbe Insel-Rundkurs rückwärts – gleiche Länge, Steigungsprofil gespiegelt
## (grade_ccw(d) = −grade_cw(L − d)), Stationen in umgekehrter Reihenfolge, Serpentinen als Abfahrt und langer Anstieg
## über den Osthang, Segmente als Daten innerhalb ihrer Stationen und Medaillen-Schwellen je Richtung aus dem Fahrmodell.
extends GutTest

var cw: Track
var ccw: Track


func before_all() -> void:
	cw = Track.new()
	IslandCourse.apply_to(cw)
	ccw = Track.new()
	IslandCourse.apply_to(ccw, Track.DIRECTION_CCW)


func after_all() -> void:
	cw.free()
	ccw.free()


## Mittlere Steigung zwischen zwei Fahrtpositionen (Höhendifferenz / Weg).
func _mean_grade(track: Track, from_m: float, to_m: float) -> float:
	return (track.ride_position_at(to_m).y - track.ride_position_at(from_m).y) / (to_m - from_m)


## Bereich [start, ende) der Station `id` in Fahrtposition.
func _ride_range(track: Track, id: String) -> Vector2:
	var stations := track.ride_stations()
	for i in range(stations.size()):
		if stations[i]["id"] == id:
			var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else track.length_m()
			return Vector2(stations[i]["start_m"], end)
	return Vector2.ZERO


func test_same_lap_length_in_both_directions() -> void:
	assert_eq(ccw.length_m(), cw.length_m(), "derselbe Pfad")
	# Die Fahrt gegen den Uhrzeigersinn legt dieselbe Strecke zurück: Weg über die Fahrtpositionen einer Runde.
	var path := 0.0
	var steps := 2000
	for i in range(steps):
		var d := ccw.length_m() * i / steps
		path += ccw.ride_position_at(d).distance_to(ccw.ride_position_at(ccw.length_m() * (i + 1) / steps))
	assert_almost_eq(path, cw.length_m(), cw.length_m() * 0.002, "abgefahrene Länge gleich der Rundenlänge")
	assert_true(ccw.ride_position_at(0.0).is_equal_approx(cw.position_at(0.0)), "Start/Ziel bleibt im Hafen")


func test_grade_profile_is_mirrored() -> void:
	var length := cw.length_m()
	var checked := 0
	for i in range(1, 60):
		var d := length * i / 60.0 + 7.3
		assert_almost_eq(ccw.grade_at(d), -cw.grade_at(length - d), 0.0005, "grade_ccw(%d) = −grade_cw(L − %d)" % [d, d])
		checked += 1
	assert_eq(checked, 59)
	assert_almost_eq(ccw.grade_at(length + 500.0), ccw.grade_at(500.0), 0.0001, "nächste Runde wie die erste")
	assert_almost_eq(cw.path_distance(1234.0), 1234.0, 0.001, "im Uhrzeigersinn Pfad = Fahrt")
	assert_almost_eq(ccw.path_distance(1234.0), length - 1234.0, 0.001, "gegen ihn L − d")


func test_stations_in_reverse_order_with_matching_ranges() -> void:
	var forward: Array = cw.ride_stations().map(func(s): return s["id"])
	var backward: Array = ccw.ride_stations().map(func(s): return s["id"])
	var reversed_ids := forward.duplicate()
	reversed_ids.reverse()
	assert_eq(backward, reversed_ids, "Stationen in umgekehrter Reihenfolge")
	assert_eq(ccw.ride_stations()[0]["start_m"], 0.0, "erste Station ab Start/Ziel")
	for id in forward:
		var a := _ride_range(cw, id)
		var b := _ride_range(ccw, id)
		assert_almost_eq(b.y - b.x, a.y - a.x, 0.01, "%s: gleich lang" % id)
		assert_almost_eq(b.x, cw.length_m() - a.y, 0.01, "%s: beginnt, wo sie im Uhrzeigersinn endet" % id)
		var mid := (b.x + b.y) / 2.0
		assert_eq(ccw.ride_station_at(mid)["id"], id, "%s: station_at in Fahrtposition" % id)
	assert_eq(ccw.ride_station_at(100.0)["name"], "Osthang", "die Abfahrt heißt rückwärts Osthang")
	assert_eq(cw.ride_station_at(cw.length_m() - 100.0)["name"], "Abfahrt", "im Uhrzeigersinn unverändert")
	assert_eq(ccw.ride_station_at(ccw.length_m() - 100.0)["id"], "hafen", "Ziel im Hafen")


func test_serpentines_descend_and_east_slope_climbs() -> void:
	var serpentines := _ride_range(ccw, "serpentinen")
	assert_lt(_mean_grade(ccw, serpentines.x, serpentines.y), -0.06, "Serpentinen als Abfahrt")
	var east := _ride_range(ccw, "abfahrt")
	assert_gt(_mean_grade(ccw, 330.0, east.y), 0.06, "langer Anstieg über den Osthang")
	assert_gt(east.y - 330.0, 2500.0, "lang")
	assert_gt(ccw.grade_at(1500.0), 0.04, "mitten im Osthang bergauf")
	assert_lt(ccw.grade_at(serpentines.x + 1000.0), -0.04, "mitten in den Serpentinen bergab")


func test_ccw_segments_are_data_inside_their_stations() -> void:
	var expected := {"bergwertung": "abfahrt", "dorfsprint": "bergdorf", "kuestenwelle": "kueste"}
	assert_eq(ccw.segments.size(), 3, "drei Segmente auch gegen den Uhrzeigersinn")
	assert_eq(ccw.segments, IslandCourse.segments(Track.DIRECTION_CCW), "Track trägt die Segmente der Richtung")
	assert_eq(cw.segments, IslandCourse.segments(Track.DIRECTION_CW))
	var previous_end := 0.0
	for segment in ccw.segments:
		var station := _ride_range(ccw, expected[segment["id"]])
		assert_gt(segment["start_m"], previous_end, "%s: steigende Meter, ohne Überlappung" % segment["id"])
		assert_lt(segment["start_m"], segment["end_m"], segment["id"])
		assert_true(segment["start_m"] >= station.x and segment["end_m"] <= station.y,
				"%s liegt in %s (%s)" % [segment["id"], expected[segment["id"]], station])
		previous_end = segment["end_m"]
	assert_lt(previous_end, ccw.length_m(), "kein Segment über die Start/Ziel-Linie")
	var climb: Dictionary = ccw.segments.filter(func(s): return s["id"] == "bergwertung")[0]
	assert_gt(_mean_grade(ccw, climb["start_m"], climb["end_m"]), 0.06, "Bergwertung ist die lange Steigung")


func test_direction_switches_segments_and_back() -> void:
	var track: Track = autofree(Track.new())
	IslandCourse.apply_to(track)
	var forward := track.grade_at(3000.0)
	track.set_direction(Track.DIRECTION_CCW)
	assert_true(track.reversed())
	assert_eq(track.segments, IslandCourse.segments(Track.DIRECTION_CCW))
	track.set_direction(Track.DIRECTION_CW)
	assert_false(track.reversed())
	assert_eq(track.segments, IslandCourse.segments(Track.DIRECTION_CW))
	assert_eq(track.grade_at(3000.0), forward, "zurück im Uhrzeigersinn wie vorher")


func test_medal_thresholds_per_direction_from_the_ride_model() -> void:
	var config := RideConfig.new()
	var forward := Medals.thresholds(cw, config)
	var backward := Medals.thresholds(ccw, config)
	assert_eq(backward.keys(), [Medals.LAP, "bergwertung", "dorfsprint", "kuestenwelle"], "Runde und Segmente in Fahrtfolge")
	for medal in Medals.ORDER:
		var times := Medals.simulate_lap(ccw, config, Medals.CADENCE_RPM[medal])
		for key in backward:
			assert_eq(backward[key][medal], times[key], "%s %s: Zeit des Fahrmodells gegen den Uhrzeigersinn" % [key, medal])
	assert_ne(backward[Medals.LAP], forward[Medals.LAP], "Rundenschwellen je Richtung")
	assert_ne(backward["bergwertung"], forward["bergwertung"], "Bergwertung je Richtung")
	# Ehrliche Wertung (ADR-0010): nur Kadenz und Steigung – ein anderes Fahrmodell gibt andere Schwellen.
	var slower := RideConfig.new()
	slower.k_kmh_per_rpm = config.k_kmh_per_rpm * 0.8
	assert_gt(Medals.thresholds(ccw, slower)[Medals.LAP][Medals.GOLD], backward[Medals.LAP][Medals.GOLD])
