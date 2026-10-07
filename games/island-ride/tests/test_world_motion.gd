## Bewegung, Effekte und Licht (G3): WorldMotion bewegt Windmühlen, Leuchtturm-Lampe, Boote, Segler, Vögel und
## Wolken als Funktion der Zeit (`apply(t)` – ohne Echtzeit geprüft); Meer und Vegetation haben Shader, das
## Environment Himmel und Tonemapping. Die Welt lebt auch in der Verbindungspause weiter.
extends "res://tests/support/bus_test.gd"

var _ride: Node


func _world() -> IslandWorld:
	var bus := start_fake_bus([FakeBusServer.status()])
	_ride = spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return _ride.get_node("World")


func test_windmill_blades_and_lamp_turn_with_time() -> void:
	var motion := _world().motion
	assert_eq(motion.mills.size(), 3, "drei Mühlen")
	motion.apply(0.0)
	var blades: Array[float] = []
	for mill in motion.mills:
		blades.append(mill["node"].rotation.z)
	var lamp := motion.lamp.rotation.y
	motion.apply(2.0)
	var speeds := {}
	for k in range(motion.mills.size()):
		var turned := absf(angle_difference(blades[k], motion.mills[k]["node"].rotation.z))
		assert_between(turned, 0.8, 2.0, "Mühle %d dreht in 2 s um 0,8–2 rad" % (k + 1))
		speeds[snappedf(turned, 0.001)] = true
	assert_eq(speeds.size(), 3, "jede Mühle mit eigener Drehzahl")
	assert_almost_eq(absf(angle_difference(lamp, motion.lamp.rotation.y)), 1.8, 0.01, "Lampe dreht")
	assert_not_null(motion.lamp.get_node_or_null("Kegel"), "Lichtkegel an der Lampe")


func test_boats_rock_within_bounds() -> void:
	var motion := _world().motion
	assert_gt(motion.boats.size(), 30, "Hafenboote, Bojen und Boote in den Buchten")
	var moved := 0
	for t in [0.0, 1.3, 2.7, 4.1, 9.6]:
		motion.apply(t)
		for boat in motion.boats:
			var base: Transform3D = boat["base"]
			var now: Transform3D = boat["node"].transform
			assert_lte(absf(now.origin.y - base.origin.y), WorldMotion.BOB_M + 0.001, "Hub %s" % boat["node"].name)
			assert_almost_eq(Vector2(now.origin.x, now.origin.z), Vector2(base.origin.x, base.origin.z), Vector2(0.001, 0.001), "bleibt vor Anker")
			var up := now.basis.y.normalized()
			assert_lte(up.angle_to(base.basis.y.normalized()), WorldMotion.ROCK_RAD * 1.7, "Neigung %s" % boat["node"].name)
			if t > 0.0 and absf(now.origin.y - base.origin.y) > 0.01:
				moved += 1
	assert_gt(moved, motion.boats.size(), "Boote schaukeln")


func test_sailing_boats_cruise_on_open_water() -> void:
	var world := _world()
	var motion := world.motion
	assert_eq(motion.sailers.size(), 2, "zwei Segler")
	for sailer in motion.sailers:
		for k in range(24):
			var p: Vector3 = motion.sailer_point(sailer, TAU * k / 24.0)
			assert_lt(world.terrain.height_at(p.x, p.z), -3.0, "%s im tiefen Wasser bei %s" % [sailer["node"].name, p])
		motion.apply(0.0)
		var start: Vector3 = sailer["node"].position
		motion.apply(10.0)
		assert_between(start.distance_to(sailer["node"].position), 15.0, 55.0, "%s fährt im Mittel ~3,5 m/s" % sailer["node"].name)


func test_birds_fly_and_flap() -> void:
	var motion := _world().motion
	assert_gte(motion.birds.size(), 15, "Möwen und Greifvögel")
	motion.apply(0.0)
	var before: Array[Vector3] = []
	var wings: Array[float] = []
	for bird in motion.birds:
		before.append(bird["node"].position)
		wings.append(bird["wings"][0].rotation.z)
	motion.apply(1.5)
	var flapped := 0
	for k in range(motion.birds.size()):
		var bird: Dictionary = motion.birds[k]
		var travelled: float = before[k].distance_to(bird["node"].position)
		assert_between(travelled, 5.0, 16.0, "%s fliegt (%.1f m in 1,5 s)" % [bird["node"].name, travelled])
		assert_gt(bird["node"].position.y, 10.0, "%s in der Luft" % bird["node"].name)
		if absf(bird["wings"][0].rotation.z - wings[k]) > 0.05:
			flapped += 1
		assert_almost_eq(bird["wings"][1].rotation.z, -bird["wings"][0].rotation.z, 0.0001, "Flügel symmetrisch")
	assert_gt(flapped, motion.birds.size() / 3, "Flügelschlag")


func test_clouds_drift_and_wrap() -> void:
	var motion := _world().motion
	assert_gte(motion.clouds.size(), 10, "Wolken")
	motion.apply(0.0)
	var cloud: Node3D = motion.clouds[0]["node"]
	var start := cloud.position
	motion.apply(20.0)
	assert_almost_eq(cloud.position.distance_to(start), (WorldMotion.CLOUD_WIND * 20.0).length(), 0.01, "zieht mit dem Wind")
	motion.apply(5000.0)
	for entry in motion.clouds:
		var p: Vector3 = entry["node"].position
		assert_true(absf(p.x) <= WorldMotion.CLOUD_EXTENT_M and absf(p.z) <= WorldMotion.CLOUD_EXTENT_M, "läuft am Rand um")
		assert_gt(p.y, 300.0, "hoch am Himmel")


func test_world_keeps_living_during_connection_pause() -> void:
	var motion := _world().motion
	await run_for(0.5)
	assert_eq(_ride.state, _ride.STATE_PAUSED_CONNECTION, "ohne Daten pausiert")
	assert_gt(motion.time_s, 0.2, "Animation läuft trotz Pause weiter")


func test_sea_and_vegetation_use_shaders() -> void:
	var world := _world()
	var sea := world.get_node("Sea") as MeshInstance3D
	assert_true(sea.material_override is ShaderMaterial, "Meer mit Shader")
	assert_not_null(sea.material_override.get_shader_parameter("shore"), "Höhenkarte für Flachwasser/Brandung")
	var swaying := 0
	for path in ["Props/kueste/tree_simple", "Props/kueste/plant_bush", "Props/hafen/tree_palmTall", "Props/hain/tree_fat",
			"Props/abfahrt/Zypressen"]:
		var node := world.get_node_or_null(path) as MultiMeshInstance3D
		assert_not_null(node, path)
		if node == null:
			continue
		var mesh := node.multimesh.mesh
		for s in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(s)
			assert_true(material is ShaderMaterial and material.shader == WorldMotion.WIND_SHADER, "%s Fläche %d im Wind" % [path, s])
			swaying += 1
	assert_gt(swaying, 5)
	assert_true(world.get_node("Details/Agaven").material_override is ShaderMaterial, "Agaven im Wind")
	for path in ["Props/kueste/" + IslandWorld.SLOPE_ROCK_PREFIX + "rock_tallA", "Props/serpentinen/stone_tallA"]:
		var rock := world.get_node(path) as MultiMeshInstance3D
		assert_false(rock.multimesh.mesh.surface_get_material(0) is ShaderMaterial, "%s bleibt starr" % path)


func test_environment_has_sky_and_tonemapping() -> void:
	_world()
	var environment: Environment = _ride.get_node("WorldEnvironment").environment
	assert_eq(environment.background_mode, Environment.BG_SKY, "Himmel als Hintergrund")
	assert_true(environment.sky.sky_material is ProceduralSkyMaterial, "prozeduraler Himmel")
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_SKY, "Umgebungslicht aus dem Himmel")
	assert_ne(environment.tonemap_mode, Environment.TONE_MAPPER_LINEAR, "Tonemapping statt linear")
	assert_true(environment.fog_enabled, "Dunst")
	var terrain := _ride.get_node("World/Terrain") as MeshInstance3D
	assert_true(terrain.material_override.vertex_color_is_srgb, "Geländefarben als sRGB (nicht überbelichtet)")
