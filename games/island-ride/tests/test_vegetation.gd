## Vegetation und Bodentexturen (#38): jede Station hat Gras, Unterholz und Sträucher in messbarer Dichte, keine
## Pflanze steht auf der Fahrbahn (geprüft über die Lagen in `IslandVegetation.placements`; headless liefern
## MultiMeshes keine Transforms), Gelände und Straße tragen eine Detailtextur, die Farben lassen sich zentral
## umstellen (#39) und der Browser-Pfad (Compatibility-Profil) baut abgespeckt ohne Fehler.
extends "res://tests/support/bus_test.gd"

## Mindestdichte je Art: Pflanzen je 100 m Strecke auf jeder Station (Forward+).
const MIN_PER_100M := {"Gras": 75.0, "Unterholz": 20.0, "Strauch": 8.0}
## Fahrbahnhälfte plus Rand (Mauer bis 3,8 m).
const ROAD_EDGE_M := Track.ROAD_WIDTH_M / 2.0 + 0.8


func _world() -> IslandWorld:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return ride.get_node("World")


## Instanzen aller MultiMeshes einer Art unter `node`.
func _instances(node: Node, kind: String) -> int:
	var count := 0
	for child in node.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with(kind):
			count += child.multimesh.instance_count
	return count


func test_every_section_has_dense_grass_underbrush_and_shrubs() -> void:
	var world := _world()
	for station in world.track.stations:
		var id: String = station["id"]
		var range_m := world._station_range(id)
		var node := world.get_node_or_null("Vegetation/" + id)
		assert_not_null(node, "Vegetation %s" % id)
		if node == null:
			continue
		for kind in IslandVegetation.KINDS:
			var count: int = world.vegetation.placements[id][kind].size()
			var per_100m := count * 100.0 / (range_m.y - range_m.x)
			assert_gte(per_100m, MIN_PER_100M[kind], "%s: %s je 100 m" % [id, kind])
			assert_eq(_instances(node, kind), count, "%s: %s als MultiMesh" % [id, kind])


func test_vegetation_is_chunked_with_view_distance_and_sways() -> void:
	var world := _world()
	var chunks := world.get_node("Vegetation/kueste").get_children()
	assert_gt(chunks.size(), 3 * 30, "Stücke je %d m Strecke" % IslandVegetation.CHUNK_M)
	for chunk in chunks:
		var instance := chunk as MultiMeshInstance3D
		var kind: String = String(chunk.name).rstrip("0123456789")
		assert_eq(instance.visibility_range_end, IslandVegetation.RANGE_M[kind], "%s mit Sichtweite" % chunk.name)
		assert_eq(instance.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s ohne Schatten" % chunk.name)
	for kind in IslandVegetation.KINDS:
		var material := IslandVegetation.mesh(kind).surface_get_material(0) as ShaderMaterial
		assert_not_null(material, kind)
		if material != null:
			assert_eq(material.shader, WorldMotion.WIND_SHADER, "%s im Wind" % kind)


func test_no_plant_stands_on_the_road() -> void:
	var world := _world()
	var buckets := {}
	for q in world.track.curve.get_baked_points():
		var key := Vector2i(floori(q.x / 10.0), floori(q.z / 10.0))
		if not buckets.has(key):
			buckets[key] = PackedVector2Array()
		buckets[key].append(Vector2(q.x, q.z))
	var too_close := []
	var checked := 0
	for id in world.vegetation.placements:
		for kind in IslandVegetation.KINDS:
			var radius: float = IslandVegetation.RADIUS_M[kind] * IslandVegetation.SCALE[kind].y
			for at in world.vegetation.placements[id][kind]:
				checked += 1
				var key := Vector2i(floori(at.x / 10.0), floori(at.z / 10.0))
				var best := INF
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						for r in buckets.get(key + Vector2i(dx, dz), PackedVector2Array()):
							best = minf(best, Vector2(at.x, at.z).distance_to(r))
				if best - radius <= ROAD_EDGE_M:
					too_close.append("%s/%s bei %s (%.1f m)" % [id, kind, at, best - radius])
	assert_gt(checked, 10000, "alle Pflanzen geprüft")
	assert_eq(too_close, [], "Abstand zur Straßenmitte − Radius > %.1f m" % ROAD_EDGE_M)


func test_ground_and_road_carry_a_texture() -> void:
	var world := _world()
	for path in ["Terrain", "Road"]:
		var material := (world.get_node(path) as MeshInstance3D).material_override as StandardMaterial3D
		assert_true(material.detail_enabled, "%s mit Detailtextur" % path)
		assert_eq(material.detail_blend_mode, BaseMaterial3D.BLEND_MODE_MUL, "%s: Textur färbt die Grundfarbe" % path)
		assert_true(material.uv2_world_triplanar, "%s: weltfest projiziert (ohne UVs)" % path)
		assert_true(material.vertex_color_use_as_albedo, "%s: Vertex-Farben bleiben" % path)
		var texture := material.detail_albedo
		assert_not_null(texture, "%s: Textur" % path)
		if texture == null:
			continue
		var image := texture.get_image()
		var low := 1.0
		var high := 0.0
		for k in range(64):
			var v := image.get_pixel(k * 3, k * 2).get_luminance()
			low = minf(low, v)
			high = maxf(high, v)
		assert_gt(high - low, 0.04, "%s: Muster statt Fläche" % path)
		assert_lte(high, 1.0, "%s: Textur dunkelt höchstens ab" % path)


func test_palette_recolours_vegetation_and_ground_centrally() -> void:
	var world := _world()
	var material := IslandVegetation.mesh("Gras").surface_get_material(0) as ShaderMaterial
	var texture := (world.get_node("Terrain") as MeshInstance3D).material_override.detail_albedo as Texture2D
	IslandVegetation.set_palette(IslandVegetation.PALETTE)  # Palette ist statisch: die Welt startet in der Jahreszeit des Datums (#39)
	var before := IslandVegetation.ground_image.get_pixel(10, 10)
	IslandVegetation.set_palette({"Gras": Color(0.8, 0.6, 0.2), "Boden_Erde": Color(0.95, 0.8, 0.6),
			"Boden_Gras": Color(0.95, 0.85, 0.6)})
	assert_eq(material.get_shader_parameter("albedo"), Color(0.8, 0.6, 0.2), "Gras umgefärbt")
	assert_ne(IslandVegetation.ground_image.get_pixel(10, 10), before, "Bodentextur umgefärbt")
	assert_eq((world.get_node("Terrain") as MeshInstance3D).material_override.detail_albedo, texture,
			"dieselbe Textur, ohne die Welt neu zu bauen")
	IslandVegetation.set_palette(IslandVegetation.PALETTE)
	assert_eq(material.get_shader_parameter("albedo"), IslandVegetation.PALETTE["Gras"], "zurück")
	assert_eq(IslandVegetation.ground_image.get_pixel(10, 10), before, "Bodentextur zurück")


## Browser-Pfad: dieselbe Welt im Compatibility-Profil (wie im Web-Export) – lädt ohne Fehler, weniger Gras und
## Unterholz, kürzere Sichtweite, aber auf jeder Station von jeder Art etwas; Texturen wie in Forward+.
func test_browser_profile_builds_a_lighter_world_without_errors() -> void:
	var full := _world()
	var track := Track.new()
	IslandCourse.apply_to(track)
	add_child_autofree(track)
	var world := IslandWorld.new()
	world.compatibility = true
	add_child_autofree(world)
	world.build(track)
	for station in track.stations:
		var id: String = station["id"]
		for kind in IslandVegetation.KINDS:
			var lite: int = world.vegetation.placements[id][kind].size()
			assert_gt(lite, 0, "%s: %s im Browser" % [id, kind])
			if kind != "Strauch":
				assert_lt(lite, full.vegetation.placements[id][kind].size(), "%s: weniger %s im Browser" % [id, kind])
	var chunk := world.get_node("Vegetation/hain").get_child(0) as MultiMeshInstance3D
	var kind: String = String(chunk.name).rstrip("0123456789")
	assert_lt(chunk.visibility_range_end, IslandVegetation.RANGE_M[kind], "kürzere Sichtweite im Browser")
	var road := (world.get_node("Road") as MeshInstance3D).material_override as StandardMaterial3D
	assert_not_null(road.detail_albedo, "Straßentextur im Browser")
