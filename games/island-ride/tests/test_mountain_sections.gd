## Ausgestaltung von Serpentinen, Hain, Bergdorf und Abfahrt (#16): jede Station lädt ihre Modelle (Mauern, Felsen,
## Bäume, Häuser, Kirche) und der Aussichtspunkt hat eine Plattform mit Brüstung an der Strecke. Lizenznachweis der
## Modelldateien: `test_every_model_file_is_licensed_in_assets_md` (test_harbour_and_coast.gd).
extends "res://tests/support/bus_test.gd"

const ASSET_ROOT := "res://assets/kenney/"


## Deko-Knoten der Station `id` in einer frisch gestarteten Inselfahrt.
func _props(id: String) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return ride.get_node("World/Props/" + id)


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


## Sa-Calobra-Stil: Natursteinmauer, Randsteine in den Kehren, Kalkfelsen am Hang und eine Felsnadel je Kehre (5).
func test_serpentines_have_walls_rocks_and_a_spire_in_every_hairpin() -> void:
	var serpentines := _props("serpentinen")
	assert_gte(_instances(serpentines, ["Mauer"]), 500, "Mauer am Straßenrand")
	assert_gte(_instances(serpentines, ["Randsteine"]), 100, "Randsteine innen in den Kehren")
	assert_gte(_instances(serpentines, IslandWorld.SERPENTINE_ROCKS), 150, "Kalkfelsen am Hang")
	var spires := IslandWorld.SERPENTINE_ROCKS.map(func(model): return IslandWorld.SPIRE_PREFIX + model)
	assert_eq(_instances(serpentines, spires), 5, "eine Felsnadel je Kehre")
	assert_gte(_instances(serpentines, IslandWorld.COAST_PINES + IslandWorld.COAST_BUSHES), 300, "Macchia und Pinien")


func test_viewpoint_has_a_walled_platform_beside_the_road() -> void:
	var serpentines := _props("serpentinen")
	var platform := serpentines.get_node_or_null("Plattform") as MeshInstance3D
	assert_not_null(platform, "Plattform")
	for part in ["Bruestung", "BruestungVorn", "BruestungHinten", "Bank", "Fernrohr"]:
		assert_not_null(serpentines.get_node_or_null(part), part)
	var track: Track = serpentines.get_node("../../..").track
	var road := track.position_at(IslandCourse.landmarks()[0]["distance_m"])
	var top := platform.position.y + (platform.mesh as BoxMesh).size.y / 2.0
	assert_lt(Vector2(platform.position.x - road.x, platform.position.z - road.z).length(), 15.0, "Plattform am Aussichtspunkt")
	assert_almost_eq(top, road.y, 0.5, "Plattform auf Straßenhöhe")


func test_grove_has_olive_rows_pines_and_terrace_walls() -> void:
	var grove := _props("hain")
	assert_gte(_instances(grove, IslandWorld.OLIVE_TREES), 300, "Olivenbäume")
	assert_gte(_instances(grove, IslandWorld.GROVE_PINES), 150, "Pinien")
	assert_gte(_instances(grove, ["Trockenmauer"]), 100, "Trockenmauern vor den Olivenreihen")


func test_village_has_houses_a_church_and_a_square() -> void:
	var village := _props("bergdorf")
	assert_gte(_instances(village, ["Haus_wall-doorway-round"]), 20, "Häuser (je eine Tür)")
	assert_gte(_instances(village, ["Haus_roof-high"]), 150, "Terrakotta-Dächer")
	var church := village.get_node_or_null("Kirche")
	assert_not_null(church, "Kirche")
	assert_eq(_instances(church, ["roof-high-point"]), 1, "Glockenturm mit Zeltdach")
	assert_gte(_instances(church, ["wall-window-round"]), 8, "Rundfenster")
	assert_eq(_models_from(village, "fantasy-town").filter(func(m): return m.scene_file_path.ends_with("/fountain-round.glb")).size(), 1, "Brunnen")
	assert_gte(_instances(village, ["Laternen"]), 10, "Laternen")


func test_descent_has_wall_trees_and_fincas() -> void:
	var descent := _props("abfahrt")
	assert_gte(_instances(descent, ["Mauer"]), 600, "Mauer talseitig")
	assert_gte(_instances(descent, IslandWorld.COAST_PINES), 200, "Pinien")
	assert_gte(_instances(descent, ["Zypressen"]), 50, "Zypressen")
	assert_gte(_instances(descent, IslandWorld.OLIVE_TREES), 50, "Olivenhaine")
	assert_gte(_instances(descent, ["tree_palmTall"]), 20, "Palmen vor dem Hafen")
	assert_gte(_models_from(descent, "city-suburban").size(), 4, "Fincas")
