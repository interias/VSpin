## Insel-Rundkurs (#14, ADR-0006): Länge, geschlossene Runde, Stationen in Reihenfolge, realistisches
## Steigungsprofil, Gelände unter der Straße und Inselform – geprüft an der Strecke, wie das Spiel sie nutzt.
extends GutTest

const STATION_ORDER := ["hafen", "kueste", "serpentinen", "hain", "bergdorf", "abfahrt"]
## Abtastabstand für Profilprüfungen (m).
const STEP_M := 5.0

var track: Track


func before_each() -> void:
	track = autofree(Track.new())
	IslandCourse.apply_to(track)


func _section(id: String) -> Vector2:
	for i in range(track.stations.size()):
		if track.stations[i]["id"] == id:
			var end: float = track.stations[i + 1]["start_m"] if i + 1 < track.stations.size() else track.length_m()
			return Vector2(track.stations[i]["start_m"], end)
	return Vector2.ZERO


## Steigungen in [from, to) im Abstand STEP_M.
func _grades(from: float, to: float) -> PackedFloat32Array:
	var grades := PackedFloat32Array()
	var d := from
	while d < to:
		grades.append(track.grade_at(d))
		d += STEP_M
	return grades


func _mean(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()


func test_course_is_8_to_10_km() -> void:
	assert_between(track.length_m(), 8000.0, 10000.0)


func test_course_is_a_closed_loop() -> void:
	assert_almost_eq(track.position_at(0.0).distance_to(track.position_at(track.length_m())), 0.0, 0.5,
			"Start = Ziel")
	assert_almost_eq(track.position_at(-1.0).distance_to(track.position_at(1.0)), 2.0, 0.5,
			"kein Sprung über die Start/Ziel-Linie")
	assert_almost_eq(track.grade_at(-3.0), track.grade_at(track.length_m() - 3.0), 0.0001)


func test_stations_exist_in_order_along_the_path() -> void:
	var ids := track.stations.map(func(s): return s["id"])
	assert_eq(ids, STATION_ORDER)
	assert_eq(track.stations[0]["start_m"], 0.0, "Start/Ziel im Hafen")
	for i in range(1, track.stations.size()):
		assert_gt(track.stations[i]["start_m"], track.stations[i - 1]["start_m"] + 200.0,
				"%s nach %s, mindestens 200 m Abschnitt" % [ids[i], ids[i - 1]])
	assert_lt(track.stations[-1]["start_m"], track.length_m() - 1000.0, "Abfahrt hat Länge")
	for station in track.stations:
		var middle := (_section(station["id"]).x + _section(station["id"]).y) / 2.0
		assert_eq(track.station_at(middle)["id"], station["id"], "station_at in %s" % station["id"])
	assert_eq(track.station_at(track.length_m())["id"], "hafen", "Ziel = Hafen")


func test_viewpoint_is_at_the_top_of_the_serpentines() -> void:
	var serpentines := _section("serpentinen")
	var view: Dictionary = IslandCourse.landmarks()[0]
	assert_eq(view["id"], "aussichtspunkt")
	assert_between(view["distance_m"], (serpentines.x + serpentines.y) / 2.0, serpentines.y)
	assert_gt(track.position_at(view["distance_m"]).y, track.position_at(serpentines.x).y + 120.0, "oben")


func test_harbour_is_at_sea_level_next_to_the_water() -> void:
	var start := track.position_at(0.0)
	assert_between(start.y, 0.5, 8.0, "Kai knapp über dem Meer")
	var terrain := IslandTerrain.for_course()
	var water_near := false
	for angle in range(0, 360, 15):
		var p := start + Vector3(cos(deg_to_rad(angle)), 0.0, sin(deg_to_rad(angle))) * 120.0
		water_near = water_near or terrain.height_at(p.x, p.z) < 0.0
	assert_true(water_near, "Meer höchstens 120 m vom Start/Ziel")


func test_grade_profile_is_bounded_and_smooth() -> void:
	var grades := _grades(0.0, track.length_m())
	var max_abs := 0.0
	var max_jump := 0.0
	for i in range(grades.size()):
		max_abs = maxf(max_abs, absf(grades[i]))
		if i > 0:
			max_jump = maxf(max_jump, absf(grades[i] - grades[i - 1]))
	assert_lte(max_abs, 0.10, "höchstens ~10 %% Steigung/Gefälle (gemessen: %.1f %%)" % (max_abs * 100.0))
	assert_lte(max_jump, 0.01, "keine Sprünge: höchstens 1 Prozentpunkt je %d m (gemessen: %.2f)" % [STEP_M, max_jump * 100.0])


func test_serpentines_climb_steadily() -> void:
	var section := _section("serpentinen")
	var grades := _grades(section.x, section.y)
	var min_grade := 1.0
	var max_grade := -1.0
	for g in grades:
		min_grade = minf(min_grade, g)
		max_grade = maxf(max_grade, g)
	assert_gt(min_grade, 0.03, "durchgehend bergauf")
	assert_between(_mean(grades), 0.05, 0.08, "typisch 5–8 %")
	assert_lte(max_grade, 0.10)
	assert_gt(track.position_at(section.y).y - track.position_at(section.x).y, 120.0, "deutlicher Höhengewinn")


func test_last_section_descends_to_the_harbour() -> void:
	var section := _section("abfahrt")
	var grades := _grades(section.x, section.y)
	assert_between(_mean(grades), -0.08, -0.05, "Abfahrt im Mittel 5–8 %")
	assert_gt(track.position_at(section.x).y - track.position_at(section.y).y, 150.0, "deutlicher Höhenverlust")
	assert_lt(Array(grades).max(), 0.0, "durchgehend bergab")


func test_flat_and_rolling_sections_stay_moderate() -> void:
	for id in ["hafen", "kueste", "hain", "bergdorf"]:
		var section := _section(id)
		var grades := Array(_grades(section.x, section.y))
		assert_lte(maxf(grades.max(), -grades.min()), 0.05, "%s: höchstens 5 %%" % id)


func test_road_does_not_cross_itself() -> void:
	var samples := IslandCourse.samples()
	var count := samples.size() - 1
	var min_gap := INF
	for i in range(0, count, 2):
		var a := Vector2(samples[i].x, samples[i].z)
		for j in range(i + 40, count, 2):
			if count - j + i < 40:
				continue  # entlang der Strecke nah (über Start/Ziel)
			min_gap = minf(min_gap, a.distance_to(Vector2(samples[j].x, samples[j].z)))
	assert_gt(min_gap, 30.0, "getrennte Streckenteile (auch Kehren) liegen mindestens 30 m auseinander")


func test_terrain_lies_under_the_road() -> void:
	var terrain := IslandTerrain.for_course()
	var worst_center := 0.0
	var worst_edge := 0.0
	var d := 0.0
	while d < track.length_m():
		var p := track.position_at(d)
		worst_center = maxf(worst_center, absf(terrain.height_at(p.x, p.z) - p.y))
		var ahead := track.position_at(d + 1.0)
		var side := Vector2(-(ahead.z - p.z), ahead.x - p.x).normalized() * (Track.ROAD_WIDTH_M / 2.0)
		for s in [-1.0, 1.0]:
			worst_edge = maxf(worst_edge, absf(terrain.height_at(p.x + s * side.x, p.z + s * side.y) - p.y))
		d += 10.0
	assert_lt(worst_center, 0.3, "Straßenmitte: Gelände auf Straßenhöhe (max. Abweichung %.2f m)" % worst_center)
	assert_lt(worst_edge, 0.5, "Straßenrand: weder schwebend noch vergraben (max. Abweichung %.2f m)" % worst_edge)


func test_road_runs_over_land() -> void:
	var over_water := []
	for p in IslandCourse.samples():
		if IslandTerrain.land(p.x, p.z) <= 0.0:
			over_water.append(p)
	assert_eq(over_water, [], "alle Straßenpunkte an Land (natürliche Küstenlinie)")


func test_island_is_about_2_by_3_km_with_sea_around() -> void:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for x in range(-1300, 1301, 20):
		for z in range(-1800, 1801, 20):
			if IslandTerrain.land(x, z) > 0.0:
				min_p = Vector2(minf(min_p.x, x), minf(min_p.y, z))
				max_p = Vector2(maxf(max_p.x, x), maxf(max_p.y, z))
	var size := max_p - min_p
	assert_between(size.x, 1800.0, 2400.0, "Breite ~2 km")
	assert_between(size.y, 2700.0, 3400.0, "Länge ~3 km")
	var terrain := IslandTerrain.for_course()
	var edge := IslandTerrain.ORIGIN
	for corner in [edge, edge + Vector2(IslandTerrain.SIZE.x, 0.0), edge + IslandTerrain.SIZE, edge + Vector2(0.0, IslandTerrain.SIZE.y)]:
		assert_lt(terrain.height_at(corner.x, corner.y), 0.0, "Meer am Rand bei %s" % corner)


func test_hand_made_heightmap_can_replace_the_generator() -> void:
	var image := Image.create(32, 48, false, Image.FORMAT_RF)
	for y in range(48):
		for x in range(32):
			image.set_pixel(x, y, Color(0.25 + 0.5 * x / 31.0, 0.0, 0.0))
	var terrain := IslandTerrain.from_image(image)
	assert_almost_eq(terrain.height_at(IslandTerrain.ORIGIN.x, 0.0), lerpf(IslandTerrain.IMAGE_MIN_M, IslandTerrain.IMAGE_MAX_M, 0.25), 1.0)
	assert_almost_eq(terrain.height_at(IslandTerrain.ORIGIN.x + IslandTerrain.SIZE.x, 0.0), lerpf(IslandTerrain.IMAGE_MIN_M, IslandTerrain.IMAGE_MAX_M, 0.75), 1.0)
	terrain.fit_to_road(IslandCourse.samples())
	var p := track.position_at(_section("serpentinen").x + 500.0)
	assert_almost_eq(terrain.height_at(p.x, p.z), p.y, 0.3, "auch eine Höhenkarte wird unter die Straße geformt")
