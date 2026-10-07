## Ausgestaltung von Hafen und Küstenstraße (#15): die Welt lädt die Modelle (Boote, Häuser, Vegetation, Klippen),
## jede Modelldatei ist mit Lizenz in ASSETS.md nachgewiesen, und an der Küstenstraße liegt das Meer nah an der
## Seeseite der Straße.
extends "res://tests/support/bus_test.gd"

const ASSET_ROOT := "res://assets/kenney/"


func _island_ride() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	return spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))


## Kinder von `node`, deren Szene aus `folder` (unter ASSET_ROOT) stammt.
func _models_from(node: Node, folder: String) -> Array:
	return node.get_children().filter(func(child): return child.scene_file_path.begins_with(ASSET_ROOT + folder + "/"))


## Instanzen aller MultiMeshes unter `node` mit diesen Namen.
func _instances(node: Node, names: Array) -> int:
	var count := 0
	for child in node.get_children():
		if child is MultiMeshInstance3D and String(child.name) in names:
			count += child.multimesh.instance_count
	return count


func test_harbour_has_quay_boats_and_houses() -> void:
	var harbour: Node = _island_ride().get_node("World/Props/hafen")
	assert_not_null(harbour.get_node_or_null("Kai0"), "Kai")
	assert_not_null(harbour.get_node_or_null("MoleOst"), "Mole")
	assert_gte(_models_from(harbour, "watercraft").size(), 15, "Boote, Bojen, Ladung")
	assert_gte(_models_from(harbour, "city-suburban").size(), 12, "Häuserzeile")
	assert_gte(_instances(harbour, ["tree_palmTall", "tree_palmBend"]), 20, "Palmen")


func test_coast_road_has_cliffs_vegetation_and_wall() -> void:
	var coast: Node = _island_ride().get_node("World/Props/kueste")
	assert_gte(_instances(coast, IslandWorld.COAST_CLIFFS), 50, "Klippen an der Wasserlinie")
	assert_gte(_instances(coast, IslandWorld.COAST_PINES), 100, "Pinien")
	assert_gte(_instances(coast, IslandWorld.COAST_BUSHES), 200, "Büsche")
	assert_gte(_instances(coast, ["Mauer"]), 400, "Mauer am seeseitigen Straßenrand")


## Felsküste im Blick: zusätzlich zu den Klippen an der Wasserlinie (vom Fahrer aus hinter der Hangkante) steht ein
## dichtes Felsband auf dem Hang zwischen Straße und Meer.
func test_rocky_coast_stands_on_the_visible_slope() -> void:
	var coast: Node = _island_ride().get_node("World/Props/kueste")
	var names := IslandWorld.COAST_CLIFFS.map(func(model): return IslandWorld.SLOPE_ROCK_PREFIX + model)
	assert_gte(_instances(coast, names), 300, "Felsen auf dem Hang zur See")


func test_every_model_file_is_licensed_in_assets_md() -> void:
	var assets_md := FileAccess.get_file_as_string("res://ASSETS.md")
	var folders := DirAccess.get_directories_at(ASSET_ROOT)
	assert_gt(folders.size(), 0)
	for folder in folders:
		var dir := ASSET_ROOT + folder
		assert_true(FileAccess.file_exists(dir + "/License.txt"), "Lizenzdatei in %s" % dir)
		assert_string_contains(assets_md, "`kenney/%s/" % folder, "Quelle %s in ASSETS.md" % folder)
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".glb"):
				assert_string_contains(assets_md, "`%s`" % file.get_basename(), "%s/%s in ASSETS.md" % [folder, file])


func test_sea_is_close_to_the_seaward_side_of_the_coast_road() -> void:
	var track: Track = autofree(Track.new())
	IslandCourse.apply_to(track)
	var terrain := IslandTerrain.for_course()
	var start: float = track.stations[1]["start_m"]
	var end: float = track.stations[2]["start_m"]
	assert_eq(track.stations[1]["id"], "kueste")
	var d := start + 50.0
	while d < end - 250.0:  # das letzte Stück biegt ins Land zu den Serpentinen
		var p := track.position_at(d)
		var ahead := track.position_at(d + 1.0)
		var left := Vector3(ahead.z - p.z, 0.0, -(ahead.x - p.x)).normalized()
		var water_m := INF
		for m in range(10, 150, 5):
			var q := p + left * m
			if terrain.height_at(q.x, q.z) < 0.0:
				water_m = m
				break
		assert_lt(water_m, 120.0, "Meer links der Küstenstraße bei %d m" % d)
		d += 100.0
