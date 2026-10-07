## Tag/Nacht und Wetter (G6): Sonnenstand für Mallorca aus Datum und Uhrzeit (MEZ/MESZ), Zeitmodi, simuliertes
## Wetter mit weichen Übergängen, Lichtwerte als reine Funktion (Forward+ und Web-Profil) und das Zusammenspiel in
## der Hauptszene (Lichter nachts, Regen, Wolken, Nebel) – alles ohne Echtzeit geprüft.
extends "res://tests/support/bus_test.gd"

## Toleranz für Sonnenauf-/-untergang (Stunden).
const TIMES_TOLERANCE_H := 0.25


func _ride_with_sky(track: String = RideConfig.TRACK_ISLAND) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	var config := config_for(bus, RideConfig.DEFAULT_PATH, track)
	config.sky_time_mode = DayNight.MODE_FIXED
	config.sky_fixed_hour = 13.0
	config.sky_weather_mode = Weather.MODE_FIXED
	config.sky_weather = Weather.CLEAR
	return spawn_ride(bus, 0.0, config)


func _hm(hours: float) -> String:
	return "%d:%02d" % [int(hours), roundi(fmod(hours, 1.0) * 60.0)]


func test_sun_high_in_the_south_at_summer_noon_and_below_horizon_at_midnight() -> void:
	var noon := DayNight.sun_position(DayNight.local_to_unix(2026, 6, 21, 14.0))
	assert_between(noon.x, 70.0, 75.0, "21.06. 14:00 MESZ: Sonne ~73° hoch (%.1f°)" % noon.x)
	assert_between(noon.y, 160.0, 215.0, "im Süden (Azimut %.1f°)" % noon.y)
	var midnight := DayNight.sun_position(DayNight.local_to_unix(2026, 6, 21, 0.0))
	assert_lt(midnight.x, -15.0, "Mitternacht unter dem Horizont (%.1f°)" % midnight.x)
	var morning := DayNight.sun_position(DayNight.local_to_unix(2026, 6, 21, 8.0))
	assert_between(morning.y, 60.0, 100.0, "morgens im Osten (Azimut %.1f°)" % morning.y)
	var winter := DayNight.sun_position(DayNight.local_to_unix(2026, 12, 21, 13.0))
	assert_between(winter.x, 24.0, 28.0, "21.12. Mittag nur ~27° hoch (%.1f°)" % winter.x)


func test_sunrise_and_sunset_match_palma() -> void:
	# Bekannte Werte für Palma: Juni ≈ 6:20/21:20 MESZ, Dezember ≈ 8:10/17:30 MEZ
	var june := DayNight.sun_times(2026, 6, 21)
	assert_almost_eq(june.x, 6.0 + 20.0 / 60.0, TIMES_TOLERANCE_H, "Aufgang Juni %s" % _hm(june.x))
	assert_almost_eq(june.y, 21.0 + 20.0 / 60.0, TIMES_TOLERANCE_H, "Untergang Juni %s" % _hm(june.y))
	var december := DayNight.sun_times(2026, 12, 21)
	assert_almost_eq(december.x, 8.0 + 10.0 / 60.0, TIMES_TOLERANCE_H, "Aufgang Dezember %s" % _hm(december.x))
	assert_almost_eq(december.y, 17.5, TIMES_TOLERANCE_H, "Untergang Dezember %s" % _hm(december.y))
	# Unabhängig gerechnet (USNO-Algorithmus): 20.03. 6:54/19:01 MEZ, 07.10. 7:51/19:23 MESZ, Umstellungstag
	# 29.03. 7:39/20:10 MESZ (Ortszeit, nicht Stunden ab Mitternacht)
	for check in [[3, 20, 6.9, 19.02], [10, 7, 7.85, 19.38], [3, 29, 7.65, 20.17]]:
		var times := DayNight.sun_times(2026, check[0], check[1])
		assert_almost_eq(times.x, check[2], 0.1, "Aufgang %d.%d. %s" % [check[1], check[0], _hm(times.x)])
		assert_almost_eq(times.y, check[3], 0.1, "Untergang %d.%d. %s" % [check[1], check[0], _hm(times.y)])


func test_summer_time_follows_the_eu_rule() -> void:
	# 2026: MESZ vom 29.03. 01:00 UTC bis 25.10. 01:00 UTC
	var spring := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 3, "day": 29, "hour": 1, "minute": 0, "second": 0}))
	assert_eq(DayNight.madrid_utc_offset_h(spring - 60.0), 1, "vor der Umstellung MEZ")
	assert_eq(DayNight.madrid_utc_offset_h(spring + 60.0), 2, "danach MESZ")
	var autumn := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 25, "hour": 1, "minute": 0, "second": 0}))
	assert_eq(DayNight.madrid_utc_offset_h(autumn - 60.0), 2, "vor der Rückstellung MESZ")
	assert_eq(DayNight.madrid_utc_offset_h(autumn + 60.0), 1, "danach MEZ")
	assert_almost_eq(DayNight.local_hour_of(DayNight.local_to_unix(2026, 7, 1, 9.5)), 9.5, 0.001, "Ortszeit hin und zurück (Sommer)")
	assert_almost_eq(DayNight.local_hour_of(DayNight.local_to_unix(2026, 1, 15, 22.25)), 22.25, 0.001, "Ortszeit hin und zurück (Winter)")


func test_time_modes() -> void:
	var now := DayNight.local_to_unix(2026, 6, 21, 10.0)
	var clock := DayNight.new(DayNight.MODE_REALTIME, 13.0, 24.0, now)
	assert_almost_eq(clock.local_hour(), 10.0, 0.001, "Echtzeit: Systemuhr")
	clock.advance(1.0, now + 3600.0)
	assert_almost_eq(clock.local_hour(), 11.0, 0.001, "Echtzeit folgt der Uhr")
	clock.set_mode(DayNight.MODE_FIXED, 21.5, now)
	assert_almost_eq(clock.local_hour(), 21.5, 0.001, "feste Stunde")
	clock.advance(600.0, now + 600.0)
	assert_almost_eq(clock.local_hour(), 21.5, 0.001, "feste Stunde steht")
	clock.set_mode(DayNight.MODE_TIMELAPSE, 6.0, now)
	clock.timelapse_day_min = 24.0
	clock.advance(60.0, now)
	assert_almost_eq(clock.local_hour(), 7.0, 0.001, "Zeitraffer: 1 Tag in 24 min → 1 h je Minute")
	clock.advance(17.5 * 60.0, now)
	assert_almost_eq(clock.local_hour(), 0.5, 0.001, "Zeitraffer läuft über Mitternacht")
	clock.set_mode("nonsense", NAN, now)
	assert_eq(clock.mode, DayNight.MODE_REALTIME, "unbekannter Modus → Echtzeit")


func test_weather_fixed_mode_blends_softly() -> void:
	var weather := Weather.new(Weather.MODE_FIXED, Weather.CLEAR, 7)
	assert_eq(weather.params(), Weather.STATES[Weather.CLEAR], "Start ohne Überblendung")
	weather.advance(3600.0)
	assert_eq(weather.state, Weather.CLEAR, "fest bleibt fest")
	weather.set_mode(Weather.MODE_FIXED, Weather.RAIN)
	assert_almost_eq(weather.params()["rain"], 0.0, 0.001, "Überblendung beginnt beim alten Wetter")
	var last := 0.0
	for k in range(10):
		weather.advance(Weather.MANUAL_TRANSITION_S / 10.0)
		var rain: float = weather.params()["rain"]
		assert_true(rain >= last, "Regen nimmt stetig zu")
		assert_lt(rain - last, 0.3, "keine Sprünge")
		last = rain
	for key in Weather.STATES[Weather.RAIN]:
		assert_almost_eq(float(weather.params()[key]), float(Weather.STATES[Weather.RAIN][key]), 0.0001, "am Ende Regen (%s)" % key)
	assert_false(weather.changing(), "Überblendung fertig")


func test_weather_changing_mode_is_mostly_sunny() -> void:
	var weather := Weather.new(Weather.MODE_CHANGING, Weather.CLEAR, 4242)
	var seen := {}
	var sunny := 0.0
	var rainy := 0.0
	var steps := 48 * 60  # 48 h in Minuten
	var max_step := 0.0
	var before: float = weather.params()["cloud"]
	for k in range(steps):
		weather.advance(60.0)
		seen[weather.state] = true
		var cloud: float = weather.params()["cloud"]
		max_step = maxf(max_step, absf(cloud - before))
		before = cloud
		if weather.state in [Weather.CLEAR, Weather.LIGHT_CLOUDS]:
			sunny += 1.0
		elif weather.state == Weather.RAIN:
			rainy += 1.0
	assert_gt(seen.size(), 2, "das Wetter wechselt (%s)" % [seen.keys()])
	assert_gt(sunny / steps, 0.6, "meist sonnig (%.0f %%)" % (sunny / steps * 100.0))
	assert_lt(rainy / steps, 0.15, "selten Regen (%.0f %%)" % (rainy / steps * 100.0))
	assert_lt(max_step, 0.35, "Übergänge über Minuten (größter Schritt je Minute %.2f)" % max_step)
	assert_eq(Weather.next_state(Weather.CLEAR, 0.0), Weather.LIGHT_CLOUDS)
	assert_eq(Weather.next_state(Weather.CLEAR, 0.99), Weather.OVERCAST)
	for state in Weather.NEXT:
		assert_false(Weather.next_state(state, 0.5) == state, "Wechsel führt woandershin (%s)" % state)


func test_look_by_day_keeps_the_g3_light() -> void:
	var day := SkyController.look(50.0, Weather.STATES[Weather.CLEAR])
	assert_almost_eq(day["sun_energy"], 1.25, 0.001)
	assert_eq(day["sun_color"], SkyController.SUN_COLOR_DAY)
	assert_eq(day["sky_top"], SkyController.SKY_TOP_DAY)
	assert_eq(day["sky_horizon"], SkyController.HORIZON_DAY)
	assert_almost_eq(day["ambient_energy"], 1.0, 0.001)
	assert_almost_eq(day["ambient_sky"], 0.5, 0.001)
	assert_almost_eq(day["fog_density"], 0.00022, 0.000001)
	assert_almost_eq(day["exposure"], 1.0, 0.001)
	assert_almost_eq(day["saturation"], 1.12, 0.001)
	assert_eq(day["tint"], Color.WHITE, "Forward+: keine Tönung")
	assert_false(day["lights_on"], "Lichter tagsüber aus")
	assert_almost_eq(day["moon_energy"], 0.0, 0.001, "kein Mond am Tag")
	assert_true(day["birds"], "Vögel fliegen")
	# Gegen die Werte der Szene selbst (frisch geladen, unberührt von SkyController)
	var scene: Node = (ResourceLoader.load("res://scenes/main.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var environment: Environment = (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky := environment.sky.sky_material as ProceduralSkyMaterial
	var sun := scene.get_node("Sun") as DirectionalLight3D
	assert_almost_eq(day["sun_energy"], sun.light_energy, 0.001, "Sonne wie main.tscn")
	assert_eq(day["sun_color"], sun.light_color)
	assert_eq(day["sky_top"], sky.sky_top_color)
	assert_eq(day["sky_horizon"], sky.sky_horizon_color)
	assert_eq(day["ground_bottom"], sky.ground_bottom_color)
	assert_eq(day["ambient_color"], environment.ambient_light_color)
	assert_almost_eq(day["ambient_energy"], environment.ambient_light_energy, 0.001)
	assert_almost_eq(day["ambient_sky"], environment.ambient_light_sky_contribution, 0.001)
	assert_eq(day["fog_color"], environment.fog_light_color)
	assert_almost_eq(day["fog_density"], environment.fog_density, 0.000001)
	assert_almost_eq(day["fog_sun_scatter"], environment.fog_sun_scatter, 0.001)
	assert_almost_eq(day["exposure"], environment.tonemap_exposure, 0.001)
	assert_almost_eq(day["saturation"], environment.adjustment_saturation, 0.001)
	assert_almost_eq(day["contrast"], environment.adjustment_contrast, 0.001)
	scene.free()


func test_look_at_dusk_and_night() -> void:
	var clear: Dictionary = Weather.STATES[Weather.CLEAR]
	var dusk := SkyController.look(2.0, clear)
	assert_gt(dusk["sun_color"].g, 0.0)
	assert_lt(dusk["sun_color"].b, 0.5, "tiefe Sonne: Abendrot")
	assert_gt(dusk["sky_horizon"].r, dusk["sky_horizon"].b, "Horizont rötlich")
	assert_true(dusk["lights_on"], "in der Dämmerung Licht an")
	var night := SkyController.look(-20.0, clear)
	assert_almost_eq(night["sun_energy"], 0.0, 0.001, "Sonne aus")
	assert_gt(night["moon_energy"], 0.15, "Mondlicht")
	assert_gt(night["ambient_energy"], 0.4, "Umgebungslicht nicht schwarz – Strecke erkennbar")
	assert_gt(night["ambient_color"].b, 0.4, "bläuliches Nachtlicht")
	assert_true(night["lights_on"])
	assert_almost_eq(night["beacon"], 1.0, 0.001, "Leuchtturm voll an")
	assert_gt(night["stars"], 0.5, "Sterne bei klarem Himmel")
	assert_false(night["birds"], "nachts keine Vögel")
	var previous := 999.0
	for e in [40.0, 20.0, 10.0, 5.0, 0.0, -4.0, -8.0, -15.0]:
		var energy: float = SkyController.look(e, clear)["sun_energy"] + SkyController.look(e, clear)["ambient_energy"]
		assert_true(energy <= previous + 0.001, "Licht nimmt zur Nacht hin stetig ab (%.0f°)" % e)
		previous = energy


func test_look_for_weather() -> void:
	var sunny := SkyController.look(50.0, Weather.STATES[Weather.CLEAR])
	var overcast := SkyController.look(50.0, Weather.STATES[Weather.OVERCAST])
	var rain := SkyController.look(50.0, Weather.STATES[Weather.RAIN])
	assert_lt(overcast["sun_energy"], sunny["sun_energy"] * 0.5, "bedeckt: kaum direkte Sonne")
	assert_lt(overcast["sky_top"].s, sunny["sky_top"].s, "grauer Himmel")
	assert_gt(rain["fog_density"], sunny["fog_density"] * 4.0, "Regen: dichter Dunst")
	assert_lt(rain["saturation"], sunny["saturation"], "Regen: entsättigt")
	assert_lt(rain["sea_deep"].s, sunny["sea_deep"].s, "Meer grauer")
	assert_almost_eq(rain["rain"], 1.0, 0.001)
	assert_false(rain["birds"], "bei Regen keine Vögel")
	assert_almost_eq(SkyController.look(-20.0, Weather.STATES[Weather.RAIN])["stars"], 0.0, 0.001, "bei Regen keine Sterne")
	assert_true(SkyController.look(6.0, Weather.STATES[Weather.RAIN])["lights_on"], "bei Regen früher Licht")
	assert_false(SkyController.look(6.0, Weather.STATES[Weather.CLEAR])["lights_on"], "bei klarem Himmel noch nicht")


func test_compatibility_profile() -> void:
	var clear: Dictionary = Weather.STATES[Weather.CLEAR]
	for e in [50.0, 2.0, -20.0]:
		var forward := SkyController.look(e, clear, false)
		var web := SkyController.look(e, clear, true)
		assert_eq(web.keys(), forward.keys(), "gleiche Werte in beiden Profilen")
		assert_lt(web["exposure"], forward["exposure"], "Web: Belichtung niedriger (%.0f°)" % e)
		assert_true(web["sun_energy"] <= forward["sun_energy"], "Web: Sonne schwächer")
		assert_eq(web["tint"], SkyController.COMPAT_TINT, "Web: untexturierte Flächen getönt")


func test_scene_switches_lights_between_night_and_day() -> void:
	var ride := _ride_with_sky()
	var sky: SkyController = ride.sky
	var motion: WorldMotion = ride.world.motion
	assert_not_null(ride.get_node_or_null("Track/Rider/Model/Lean/Bike/Frontlicht"), "Frontlicht am Rad")
	assert_not_null(ride.get_node_or_null("Track/Rider/Model/Lean/Bike/Ruecklicht"), "Rücklicht am Rad")
	assert_gt(sky.lights.points.size(), 30, "Laternen im Dorf und am Hafen, Leuchtfeuer")
	sky.set_time_mode(DayNight.MODE_FIXED, 23.5)
	assert_lt(sky.sun_angles.x, -5.0, "23:30 ist auf Mallorca Nacht")
	assert_true(sky.lights.on, "nachts Licht an")
	assert_true(sky.lights.front_light.visible and sky.lights.rear_light.visible, "Fahrradlicht an")
	assert_true(sky.lights.glows.visible, "Laternen leuchten")
	assert_false(ride.get_node("Sun").visible, "Sonne aus")
	assert_true(sky.moon.visible, "Mond an")
	assert_true(motion.beacon_lights[0].visible, "Leuchtturm-Licht an")
	var beam := (motion.lamp.get_node("Kegel") as MeshInstance3D).material_override as ShaderMaterial
	assert_gt(beam.get_shader_parameter("intensity"), 0.6, "Lichtkegel hell")
	assert_false(motion.get_node("Voegel").visible, "keine Vögel")
	assert_gt(ride.get_node("WorldEnvironment").environment.ambient_light_energy, 0.4, "nicht schwarz")
	# Echte Lichter wandern zu den Laternen nahe der Kamera (Dorfplatz)
	var village: Vector3 = sky.lights.points[sky.lights.points.size() - 1]["position"]
	sky.lights.follow(village)
	assert_true(sky.lights.pool[0].visible, "Laternenlicht nahe der Kamera")
	assert_lt(sky.lights.pool[0].position.distance_to(village), 1.0, "an der nächsten Laterne")
	sky.set_time_mode(DayNight.MODE_FIXED, 13.0)
	assert_false(sky.lights.on, "tagsüber Licht aus")
	assert_false(sky.lights.front_light.visible, "Fahrradlicht aus")
	assert_false(sky.lights.pool[0].visible, "Laternenlichter aus")
	assert_false(motion.beacon_lights[0].visible, "Leuchtturm-Licht aus")
	assert_almost_eq(float(beam.get_shader_parameter("intensity")), WorldMotion.BEAM_DAY, 0.001, "Kegel wie am Tag (G3)")
	assert_true(ride.get_node("Sun").visible and not sky.moon.visible, "Sonne statt Mond")
	assert_true(motion.get_node("Voegel").visible, "Vögel wieder da")


func test_scene_weather_sets_clouds_fog_and_rain() -> void:
	var ride := _ride_with_sky()
	var sky: SkyController = ride.sky
	var motion: WorldMotion = ride.world.motion
	var environment: Environment = ride.get_node("WorldEnvironment").environment
	var shown := func() -> int: return motion.clouds.filter(func(c): return c["node"].visible).size()
	var clear_clouds: int = shown.call()
	var clear_fog := environment.fog_density
	assert_false(sky.rain.visible, "klar: kein Regen")
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.RAIN)
	assert_false(sky.rain.visible, "Übergang beginnt beim alten Wetter")
	sky.weather.advance(Weather.MANUAL_TRANSITION_S)
	sky.apply_now()
	assert_true(sky.rain.visible, "Regen fällt")
	assert_gt(shown.call(), clear_clouds, "mehr Wolken")
	assert_gt(environment.fog_density, clear_fog * 4.0, "dichter Dunst")
	var road := ride.world.get_node("Road").material_override as StandardMaterial3D
	assert_lt(road.roughness, 0.5, "nasse Straße glänzt")
	assert_gt(motion.wind, 1.5, "mehr Wind")
	assert_false(motion.get_node("Voegel").visible, "keine Vögel im Regen")
	motion.apply(10.0)
	var cloud: Node3D = motion.clouds[0]["node"]
	var at := cloud.position
	motion.apply(10.0 + 1.0)
	assert_almost_eq(cloud.position.distance_to(at), (WorldMotion.CLOUD_WIND * motion.wind).length(), 0.01, "Wolken ziehen schneller")
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.CLEAR)
	sky.weather.snap()
	sky.apply_now()
	assert_false(sky.rain.visible, "Regen vorbei")
	assert_eq(shown.call(), clear_clouds, "Bedeckung zurück")
	assert_almost_eq(road.roughness, 0.95, 0.001, "Straße trocken")


func test_scene_compatibility_profile_is_injectable() -> void:
	var ride := _ride_with_sky()
	var sky: SkyController = ride.sky
	var environment: Environment = ride.get_node("WorldEnvironment").environment
	var road := ride.world.get_node("Road").material_override as StandardMaterial3D
	assert_false(sky.compatibility, "Tests laufen nicht im Compatibility-Renderer")
	var exposure := environment.tonemap_exposure
	sky.set_compatibility(true)
	assert_almost_eq(environment.tonemap_exposure, exposure * SkyController.COMPAT_EXPOSURE, 0.001, "Web-Belichtung")
	assert_eq(road.albedo_color, SkyController.COMPAT_TINT, "Straße getönt")
	var kai := (ride.world.get_node("Props/hafen/Kai0") as MeshInstance3D).material_override as StandardMaterial3D
	assert_lt(kai.albedo_color.r, 0.6, "einfarbige Flächen getönt")
	sky.set_compatibility(false)
	assert_almost_eq(environment.tonemap_exposure, exposure, 0.001, "zurück auf Forward+")
	assert_eq(road.albedo_color, Color.WHITE, "Tönung aufgehoben")
	assert_almost_eq(kai.albedo_color.r, 0.6, 0.001, "Grundfarbe zurück")


func test_graybox_has_sky_and_bike_lights_without_world() -> void:
	var ride := _ride_with_sky(RideConfig.TRACK_GRAYBOX)
	var sky: SkyController = ride.sky
	sky.set_time_mode(DayNight.MODE_FIXED, 23.5)
	assert_true(sky.lights.front_light.visible, "Fahrradlicht auch auf der Graybox")
	assert_eq(sky.lights.points.size(), 0, "keine Laternen")
	await run_for(0.3)
	assert_true(sky.lights.on, "läuft ohne Welt weiter")


func test_sky_settings_from_config() -> void:
	var config := RideConfig.load_file("res://tests/fixtures/sky.cfg")
	assert_eq(config.sky_time_mode, DayNight.MODE_TIMELAPSE)
	assert_eq(config.sky_fixed_hour, 21.5)
	assert_eq(config.sky_timelapse_day_min, 12.0)
	assert_eq(config.sky_weather_mode, Weather.MODE_FIXED)
	assert_eq(config.sky_weather, Weather.RAIN)
	# Spiel-Konfiguration = eingebaute Standardwerte (Echtzeit, wechselndes Wetter ab klar)
	var game := RideConfig.load_file()
	var defaults := RideConfig.new()
	for key in ["sky_time_mode", "sky_fixed_hour", "sky_timelapse_day_min", "sky_weather_mode", "sky_weather"]:
		assert_eq(game.get(key), defaults.get(key), "config.cfg [sky] %s" % key)
	assert_eq(defaults.sky_time_mode, DayNight.MODE_REALTIME)
	assert_eq(defaults.sky_weather_mode, Weather.MODE_CHANGING)
	var partial := RideConfig.load_file("res://tests/fixtures/partial.cfg")
	assert_eq(partial.sky_time_mode, defaults.sky_time_mode, "ohne [sky] → Standard")
	# Leere/ungültige Werte: Zahlen fallen auf den Standard zurück, Modi und Wetter prüfen DayNight/Weather
	var broken := RideConfig.load_file("res://tests/fixtures/sky_broken.cfg")
	assert_eq(broken.sky_fixed_hour, defaults.sky_fixed_hour, "fixed_hour leer → Standard (nicht Mitternacht)")
	assert_eq(broken.sky_timelapse_day_min, defaults.sky_timelapse_day_min, "timelapse_day_min Text → Standard")
	assert_eq(DayNight.new(broken.sky_time_mode).mode, DayNight.MODE_REALTIME)
	var weather := Weather.new(broken.sky_weather_mode, broken.sky_weather)
	assert_eq([weather.mode, weather.state], [Weather.MODE_CHANGING, Weather.CLEAR])
