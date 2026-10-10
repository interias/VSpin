## Jahreszeiten (#39): die Jahreszeit folgt dem Datum auf Mallorca (Grenzen, Schaltjahr, Mandelblüte, Ortszeit), ist
## im Menü umstellbar (echt/fest) und nach einem Neustart wirksam; ein Wechsel färbt Vegetation, Boden und
## Kenney-Modelle um, ohne die Welt neu zu bauen; Mandelblüte, Mohn und Felder je Jahreszeit; das Erfolgs-Ereignis
## `season` fällt beim Fahren und ergibt den richtigen Erfolg.
extends "res://tests/support/bus_test.gd"

var TEMP_PATH := TestIsolation.path("test_seasons.cfg")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


## Palette und Kenney-Tönung sind statisch: nach diesen Tests zurück auf den Standard, damit andere Dateien nicht von
## der zuletzt gesetzten Jahreszeit abhängen.
func after_all() -> void:
	IslandVegetation.set_palette(IslandVegetation.PALETTE)
	IslandWorld.tint_nature({})


func _island() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	return spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))


## Hauptszene (Insel) mit eigener Einstellungsdatei.
func _spawn_with_settings() -> Node:
	var ride := MAIN_SCENE.instantiate()
	var bus := start_fake_bus([FakeBusServer.status()])
	ride.config = config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	ride.quit_on_request = false
	ride.settings_path = TEMP_PATH
	ride.save_path = ""
	ride.start_in_menu = false
	add_child_autofree(ride)
	return ride


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func _albedo(kind: String) -> Color:
	return (IslandVegetation.mesh(kind).surface_get_material(0) as ShaderMaterial).get_shader_parameter("albedo")


func test_season_follows_the_date_with_mallorcan_boundaries() -> void:
	var cases := [[1, 1, Season.WINTER], [1, 24, Season.WINTER], [1, 25, Season.ALMOND], [2, 14, Season.ALMOND],
			[3, 9, Season.ALMOND], [3, 10, Season.SPRING], [4, 25, Season.SPRING], [5, 31, Season.SPRING],
			[6, 1, Season.SUMMER], [8, 15, Season.SUMMER], [9, 15, Season.SUMMER], [9, 16, Season.AUTUMN],
			[11, 30, Season.AUTUMN], [12, 1, Season.WINTER], [12, 31, Season.WINTER]]
	for entry in cases:
		assert_eq(Season.of_date(entry[0], entry[1]), entry[2], "%d.%d." % [entry[1], entry[0]])
	# Schaltjahr: der 29. Februar liegt in der Mandelblüte, die Grenze im März bleibt beim Datum
	assert_eq(Season.at_unix(DayNight.local_to_unix(2028, 2, 29, 12.0)), Season.ALMOND, "29.02.2028")
	assert_eq(Season.at_unix(DayNight.local_to_unix(2028, 3, 9, 23.9)), Season.ALMOND, "09.03.2028 spät")
	assert_eq(Season.at_unix(DayNight.local_to_unix(2028, 3, 10, 0.1)), Season.SPRING, "10.03.2028 früh")
	# Ortszeit Mallorca, nicht UTC: 31.05. 22:30 UTC ist dort schon der 1. Juni (MESZ)
	var utc := float(Time.get_unix_time_from_datetime_dict({"year": 2027, "month": 5, "day": 31, "hour": 22,
			"minute": 30, "second": 0}))
	assert_eq(Season.at_unix(utc), Season.SUMMER, "Mitternacht auf Mallorca")
	assert_eq(Season.at_unix(utc - 3600.0), Season.SPRING, "eine Stunde vorher")


func test_almond_blossom_counts_as_spring_for_achievements() -> void:
	for phase in Season.PHASES:
		assert_has(Achievements.SEASONS, Season.achievement_season(phase), phase)
	assert_eq(Season.achievement_season(Season.ALMOND), "spring")
	var unlocked := Achievements.check({"type": Achievements.EVENT_SEASON,
			"season": Season.achievement_season(Season.ALMOND)}, {})
	assert_eq(unlocked.map(func(a): return a["name"]), ["Mandelblüte"])


func test_menu_choice_applies_at_once_is_saved_and_survives_restart() -> void:
	var ride := _spawn_with_settings()
	assert_eq(ride.sky.season_mode, Season.MODE_REAL, "Standard: nach dem Datum")
	assert_eq(ride.sky.season(), Season.at_unix(ride.sky.clock.unix_s))
	_choose(ride.settings_menu, "season", [Season.MODE_FIXED, Season.SUMMER])
	assert_eq(ride.sky.season(), Season.SUMMER, "wirkt sofort")
	assert_eq(_albedo("Gras"), Season.LOOKS[Season.SUMMER]["palette"]["Gras"], "Welt im Sommer")
	remove_child(ride)
	ride.free()
	var again := _spawn_with_settings()
	assert_eq(again.sky.season_mode, Season.MODE_FIXED, "nach Neustart gespeicherter Wert")
	assert_eq(again.sky.season(), Season.SUMMER)
	var option: OptionButton = again.settings_menu.options["season"]
	again.settings_menu.open()
	assert_eq(option.get_item_text(option.selected), "Sommer", "Menü zeigt die Wahl")
	_choose(again.settings_menu, "season", [Season.MODE_REAL, ""])
	assert_eq(again.sky.season(), Season.at_unix(again.sky.clock.unix_s), "wieder nach dem Datum")
	assert_eq(GraphicsSettings.load_file(TEMP_PATH).season_mode, Season.MODE_REAL, "gespeichert")


func test_real_mode_follows_the_clock_date() -> void:
	var ride := _spawn_with_settings()
	ride.sky.clock.set_mode(DayNight.MODE_FIXED)
	ride.sky.clock.unix_s = DayNight.local_to_unix(2027, 2, 10, 13.0)
	ride.sky.apply_now()
	assert_eq(ride.sky.season(), Season.ALMOND, "Februar: Mandelblüte")
	ride.sky.clock.unix_s = DayNight.local_to_unix(2027, 7, 10, 13.0)
	ride.sky.apply_now()
	assert_eq(ride.sky.season(), Season.SUMMER, "Juli: Sommer")
	assert_eq(_albedo("Getreide"), Season.LOOKS[Season.SUMMER]["palette"]["Getreide"], "Welt folgt dem Datum")


func test_season_recolours_vegetation_ground_and_kenney_models_without_rebuild() -> void:
	var ride := _island()
	var world: IslandWorld = ride.get_node("World")
	var olives := world.get_node("Props/hain/tree_fat") as MultiMeshInstance3D
	var terrain := world.get_node("Terrain") as MeshInstance3D
	var texture: Texture2D = terrain.material_override.detail_albedo
	var leaves: Array = []
	for entry in IslandWorld._nature_materials:
		if entry[1] == "leafsGreen" and entry[0] is ShaderMaterial:
			leaves.append(entry)
	assert_gt(leaves.size(), 3, "Laub der Kenney-Bäume ist registriert")
	var leaf: Array = leaves[0]
	var ground := {}
	for phase in Season.PHASES:
		ride.sky.set_season_mode(Season.MODE_FIXED, phase)
		var look: Dictionary = Season.LOOKS[phase]
		for kind in IslandVegetation.KINDS + IslandVegetation.SEASON_KINDS:
			assert_eq(_albedo(kind), look["palette"][kind], "%s: %s" % [phase, kind])
		assert_eq(leaf[0].get_shader_parameter("albedo"), leaf[2] * look["nature"]["leafsGreen"], "%s: Laub" % phase)
		ground[phase] = IslandVegetation.ground_image.get_pixel(40, 40)
	assert_ne(ground[Season.SUMMER], ground[Season.WINTER], "Boden im Sommer anders als im Winter")
	assert_true(is_instance_valid(olives) and olives.get_parent() != null, "dieselben Knoten – kein Neubau")
	assert_eq(terrain.material_override.detail_albedo, texture, "dieselbe Bodentextur")
	var summer: Color = Season.LOOKS[Season.SUMMER]["palette"]["Gras"]
	var winter: Color = Season.LOOKS[Season.WINTER]["palette"]["Gras"]
	assert_gt(summer.r - summer.g, 0.0, "Sommergras goldgelb")
	assert_gt(winter.g - winter.r, 0.1, "Wintergras grün")


func test_blossoms_poppies_and_fields_by_season() -> void:
	var ride := _island()
	var world: IslandWorld = ride.get_node("World")
	var placements: Dictionary = world.vegetation.placements
	for station in world.track.stations:
		var id: String = station["id"]
		assert_gt(placements[id]["Mohn"].size(), 20, "%s: Mohn am Wegrand" % id)
		var trees: int = placements[id]["Mandelbaum"].size()
		var fields: int = placements[id]["Getreide"].size()
		if id in ["hain", "abfahrt"]:
			assert_gt(trees, 15, "%s: Mandelbäume" % id)
		else:
			assert_eq(trees, 0, "%s: keine Mandelbäume" % id)
		if id == "abfahrt":
			assert_gt(fields, 1000, "Felder an der Abfahrt")
		else:
			assert_eq(fields, 0, "%s: keine Felder" % id)
	var poppies := world.find_children("Mohn*", "MultiMeshInstance3D", true, false)
	assert_gt(poppies.size(), 20, "Mohn in Stücken")
	ride.sky.set_season_mode(Season.MODE_FIXED, Season.SPRING)
	assert_true(poppies.all(func(n): return n.visible), "Mohn blüht im Frühling")
	assert_gt(_albedo("Getreide").g, _albedo("Getreide").r, "junges Getreide grün")
	for phase in [Season.ALMOND, Season.SUMMER, Season.AUTUMN, Season.WINTER]:
		ride.sky.set_season_mode(Season.MODE_FIXED, phase)
		assert_false(poppies.any(func(n): return n.visible), "kein Mohn: %s" % phase)
	ride.sky.set_season_mode(Season.MODE_FIXED, Season.ALMOND)
	var blossom := _albedo("Mandelbaum")
	assert_gt(minf(blossom.r, minf(blossom.g, blossom.b)), 0.8, "Mandelblüte weiß-rosa")
	assert_gt(blossom.r, blossom.g, "rosa Hauch")
	ride.sky.set_season_mode(Season.MODE_FIXED, Season.SUMMER)
	var grain := _albedo("Getreide")
	assert_gt(grain.r, 0.85, "Felder goldgelb im Sommer")
	assert_true(grain.r > grain.g and grain.g > grain.b, "gelb")
	assert_gt(_albedo("Mandelbaum").g, _albedo("Mandelbaum").r, "Mandelbäume im Sommer grün")


func test_season_plants_keep_off_the_road() -> void:
	var ride := _island()
	var world: IslandWorld = ride.get_node("World")
	var too_close := []
	for id in world.vegetation.placements:
		for kind in IslandVegetation.SEASON_KINDS:
			var radius: float = IslandVegetation.RADIUS_M[kind] * IslandVegetation.SCALE[kind].y
			for at in world.vegetation.placements[id][kind]:
				if world.vegetation.road_clearance(at) - radius < Track.ROAD_WIDTH_M / 2.0 + 0.8:
					too_close.append("%s/%s bei %s" % [id, kind, at])
	assert_eq(too_close, [], "Abstand zur Straße")


func test_mood_tints_light_slightly_per_season() -> void:
	var w: Dictionary = Weather.STATES[Weather.CLEAR]
	var plain := SkyController.look(40.0, w)
	assert_eq(SkyController.look(40.0, w, false, "").hash(), plain.hash(), "ohne Jahreszeit unverändert")
	var summer := SkyController.look(40.0, w, false, Season.SUMMER)
	var winter := SkyController.look(40.0, w, false, Season.WINTER)
	assert_gt((summer["sun_color"] as Color).r - (summer["sun_color"] as Color).b,
			(winter["sun_color"] as Color).r - (winter["sun_color"] as Color).b, "Sommer wärmer als Winter")
	assert_lt(winter["saturation"], plain["saturation"], "Winter blasser")
	for phase in Season.PHASES:
		var look := SkyController.look(40.0, w, false, phase)
		assert_almost_eq(look["saturation"], plain["saturation"], 0.07, "%s: dezent" % phase)
		assert_almost_eq((look["sun_color"] as Color).b, (plain["sun_color"] as Color).b, 0.12, "%s: dezent" % phase)


func test_riding_sends_the_season_event_and_unlocks_its_achievement() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 20.0))
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = 10.0
	var ride := spawn_ride(bus, 0.0, config)
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 0)  # endlos: die Graybox-Runde ist kürzer als 1 km
	ride.sky.set_season_mode(Season.MODE_FIXED, Season.ALMOND)
	assert_has(ride._km_events(), {"type": Achievements.EVENT_SEASON, "season": "spring"}, "Ereignis je km")
	assert_true(await run_until(func(): return ride.save_game.achievements().has("spring"), 10.0),
			"Mandelblüte nach dem ersten Kilometer")
	assert_false(ride.save_game.achievements().has("winter"), "nur die gefahrene Jahreszeit")
	var names: Array = ride.ride_achievements.map(func(a): return a["name"])
	assert_has(names, "Mandelblüte")
