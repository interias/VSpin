## Sehenswürdigkeiten und Kleindetails (G2): die Landmarken stehen benannt unter `World/Landmarks`, die animierbaren
## Teile (Windmühlenflügel, Leuchtturm-Lampe) sind eigene Knoten, und keine Platzierung liegt auf der Fahrbahn – geprüft
## über die Platzierungsdaten (`IslandLandmarks.placements`; headless liefern MultiMeshes keine Transforms).
## Lizenznachweis der Modelldateien: `test_every_model_file_is_licensed_in_assets_md` (test_harbour_and_coast.gd).
extends "res://tests/support/bus_test.gd"

const LANDMARKS := ["leuchtturm", "cala", "talaia", "ermita", "burg", "aquaedukt", "windmuehlen"]


func _world() -> IslandWorld:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return ride.get_node("World")


func test_landmarks_are_named_nodes_spread_over_the_course() -> void:
	var world := _world()
	var landmarks := world.get_node("Landmarks")
	var stations := {}
	for id in LANDMARKS:
		var node := landmarks.get_node_or_null(id)
		assert_not_null(node, id)
		if node == null:
			continue
		assert_true(node.has_meta("landmark_name"), "Name %s" % id)
		if node.has_meta("distance_m"):
			stations[world.track.station_at(node.get_meta("distance_m"))["id"]] = true
	assert_eq(landmarks.get_node("windmuehlen").get_child_count(), 3, "drei Windmühlen")
	assert_gte(stations.size(), 4, "Landmarken auf mindestens vier Stationen verteilt: %s" % [stations.keys()])


func test_moving_parts_are_own_nodes_for_animation() -> void:
	var landmarks := _world().get_node("Landmarks")
	for mill in landmarks.get_node("windmuehlen").get_children():
		var blades := mill.get_node_or_null("Fluegel") as Node3D
		assert_not_null(blades, "Flügel %s" % mill.name)
		if blades != null:
			assert_gt(blades.get_child_count(), 0, "Flügel haben ein Mesh")
	assert_not_null(landmarks.get_node_or_null("leuchtturm/Lampe"), "Leuchtturm-Lampe")


func test_nothing_is_placed_on_the_road() -> void:
	var world := _world()
	var placements := world.landmarks.placements
	assert_gt(placements.size(), 200, "Landmarken und Kleindetails")
	var road := PackedVector2Array()
	for q in world.track.curve.get_baked_points():
		road.append(Vector2(q.x, q.z))
	var too_close := []
	for entry in placements:
		var clearance: float = _road_distance(road, entry["at"]) - entry["radius_m"]
		if clearance < 3.8:
			too_close.append("%s bei %s (%.1f m)" % [entry["id"], entry["at"], clearance])
	assert_eq(too_close, [], "Abstand zur Straßenmitte − Radius ≥ 3,8 m (Mauer)")


func test_details_line_the_course() -> void:
	var details := _world().get_node("Details")
	assert_eq(details.get_node("Kilometersteine").get_child_count(), 9, "Kilometersteine 1–9")
	for key in ["Agaven", "AgavenBluete", "Feigenkakteen", "Schafe", "Ziegen"]:
		var node := details.get_node_or_null(key) as MultiMeshInstance3D
		assert_not_null(node, key)
		if node != null:
			assert_gt(node.multimesh.instance_count, 5, key)
	assert_gte(details.get_node("Boote").get_child_count(), 6, "Boote und Bojen in den Buchten")
	assert_not_null(details.get_node_or_null("Bushaltestelle"), "Bushaltestelle")


## Horizontaler Abstand von `p` zur Straßenmitte (Kurvenpunkte alle 1 m), unabhängig von IslandLandmarks.
func _road_distance(road: PackedVector2Array, p: Vector3) -> float:
	var at := Vector2(p.x, p.z)
	var best := INF
	for q in road:
		best = minf(best, at.distance_squared_to(q))
	return sqrt(best)
