## Farbstimmung und Höhennebel (#42): je Tageszeit und Wetter verschieden, stetig ohne Sprünge, die Jahreszeit-Tönung
## (#39) bleibt ein Faktor obendrauf, Höhennebel je Profil an oder aus, im Compatibility-Renderer ohne Fehler.
extends "res://tests/support/bus_test.gd"

## Sonnenstand (Höhe, Azimut): Morgen im Osten, Mittag im Süden, Abend im Westen.
const MORNING := Vector2(8.0, 100.0)
const NOON := Vector2(50.0, 180.0)
const EVENING := Vector2(8.0, 260.0)


func _look(sun: Vector2, weather: String = Weather.CLEAR, season: String = "", compat: bool = false) -> Dictionary:
	return SkyController.look(sun.x, Weather.STATES[weather], compat, season, sun.y)


## Größte Änderung zwischen zwei Lichtwerten [Betrag, Schlüssel]: Zahlen und Farbkanäle, Nebeldichte relativ, Höhennebel
## relativ zur vollen Dichte; Schalter wie `lights_on` zählen nicht.
func _jump(a: Dictionary, b: Dictionary) -> Array:
	var worst := [0.0, ""]
	for key in a:
		var diff := 0.0
		if a[key] is float:
			diff = absf(a[key] - b[key])
			if key == "fog_density":
				diff /= maxf(a[key], b[key])
			elif key == "fog_height_density":
				diff /= SkyController.HEIGHT_FOG_DENSITY
		elif a[key] is Color:
			var ca: Color = a[key]
			var cb: Color = b[key]
			diff = maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
		if diff > worst[0]:
			worst = [diff, key]
	return worst


## Größter Sprung entlang einer Folge von Lichtwerten [Betrag, Schlüssel, Index].
func _worst_jump(looks: Array) -> Array:
	var worst := [0.0, "", 0]
	for i in range(1, looks.size()):
		var jump := _jump(looks[i - 1], looks[i])
		if jump[0] > worst[0]:
			worst = [jump[0], jump[1], i]
	return worst


func _warmth(color: Color) -> float:
	return color.r - color.b


func test_mood_differs_by_time_of_day_and_weather() -> void:
	var morning := _look(MORNING)
	var noon := _look(NOON)
	var evening := _look(EVENING)
	var rain := _look(NOON, Weather.RAIN)
	assert_gt(_warmth(evening["sun_color"]), _warmth(morning["sun_color"]) + 0.05, "abends goldener als morgens")
	assert_gt(_warmth(morning["sun_color"]), _warmth(noon["sun_color"]), "morgens wärmer als mittags")
	assert_gt(_warmth(evening["ambient_color"]), _warmth(morning["ambient_color"]), "Umgebungslicht abends warm")
	assert_gt(morning["fog_density"], evening["fog_density"] * 1.3, "Morgendunst")
	assert_gt(evening["saturation"], morning["saturation"], "abends satter")
	assert_lt(_warmth(rain["ambient_color"]), _warmth(noon["ambient_color"]), "Regen kühler")
	assert_lt(rain["contrast"], noon["contrast"], "Regen flauer")
	var colors := [morning["fog_color"], noon["fog_color"], evening["fog_color"], rain["fog_color"]]
	for i in range(colors.size()):
		for j in range(i + 1, colors.size()):
			assert_false((colors[i] as Color).is_equal_approx(colors[j]), "Nebelfarben verschieden (%d/%d)" % [i, j])
	# Mittag bei klarem Himmel bleibt der Stand aus G3 (test_day_night_weather prüft ihn gegen main.tscn)
	assert_eq(noon["sun_color"], SkyController.SUN_COLOR_DAY, "Mittag neutral")
	assert_eq(noon["ambient_color"], SkyController.AMBIENT_DAY)


func test_mood_changes_smoothly() -> void:
	var clear: Dictionary = Weather.STATES[Weather.CLEAR]
	# Tageslauf in Schritten von 0,05°, morgens und abends
	for azimuth in [100.0, 260.0]:
		var looks := []
		for i in range(1901):
			looks.append(SkyController.look(-25.0 + i * 0.05, clear, false, "", azimuth))
		var worst := _worst_jump(looks)
		assert_lt(worst[0], 0.02, "Azimut %.0f°: %s springt bei %.2f°" % [azimuth, worst[1], -25.0 + worst[2] * 0.05])
	# Tiefe Sonne einmal um den Horizont (auch über Norden zurück auf 0°)
	var around := []
	for i in range(722):
		around.append(SkyController.look(5.0, clear, false, "", fmod(i * 0.5, 360.0)))
	var worst := _worst_jump(around)
	assert_lt(worst[0], 0.02, "Azimut: %s springt bei %.1f°" % [worst[1], worst[2] * 0.5])
	# Wetterwechsel klar → Regen, wie Weather überblendet
	var blend := []
	for i in range(501):
		var w := Weather.blend(clear, Weather.STATES[Weather.RAIN], i / 500.0)
		blend.append(SkyController.look(MORNING.x, w, false, "", MORNING.y))
	worst = _worst_jump(blend)
	assert_lt(worst[0], 0.02, "Wetter: %s springt bei %.1f %%" % [worst[1], worst[2] / 5.0])


func test_season_tint_stays_a_factor_on_top() -> void:
	for sun in [MORNING, NOON, EVENING]:
		for weather in [Weather.CLEAR, Weather.RAIN]:
			var plain := _look(sun, weather)
			for phase in Season.PHASES:
				var tinted := _look(sun, weather, phase)
				var mood: Dictionary = SkyController.SEASON_MOOD[phase]
				var label := "%s/%s/%s" % [sun, weather, phase]
				assert_true((tinted["sun_color"] as Color).is_equal_approx(plain["sun_color"] * mood["sun"]), label)
				assert_true((tinted["ambient_color"] as Color).is_equal_approx(plain["ambient_color"] * mood["ambient"]), label)
				assert_almost_eq(tinted["saturation"], plain["saturation"] * mood["saturation"], 0.0001, label)
				assert_true((tinted["fog_color"] as Color).is_equal_approx(plain["fog_color"] * SkyController.SEASON_FOG[phase]),
						label)
				assert_almost_eq(tinted["fog_height_density"], plain["fog_height_density"], 0.000001, "Nebel bleibt")
	assert_eq(SkyController.SEASON_FOG.keys(), SkyController.SEASON_MOOD.keys(), "Nebelton je Jahreszeit")


func test_height_fog_on_and_off_per_profile() -> void:
	assert_eq(_look(NOON)["fog_height_density"], 0.0, "klarer Mittag: kein Höhennebel")
	assert_eq(_look(Vector2(-30.0, 0.0))["fog_height_density"], 0.0, "klare Nacht: keiner")
	var morning: float = _look(MORNING)["fog_height_density"]
	var evening: float = _look(EVENING)["fog_height_density"]
	var rain: float = _look(NOON, Weather.RAIN)["fog_height_density"]
	assert_gt(morning, 0.0, "Morgendunst")
	assert_gt(morning, evening, "morgens dichter als abends")
	assert_gt(rain, _look(NOON, Weather.OVERCAST)["fog_height_density"], "Regen dichter als bewölkt")
	assert_gt(rain, 0.5 * SkyController.HEIGHT_FOG_DENSITY, "Regen: deutlicher Höhennebel")
	assert_gt(_look(NOON, Weather.RAIN)["fog_height"], _look(MORNING)["fog_height"], "Regen reicht höher")
	for weather in Weather.STATES:
		for sun in [MORNING, NOON, EVENING, Vector2(-30.0, 0.0)]:
			assert_between(_look(sun, weather)["fog_height_density"], 0.0, SkyController.HEIGHT_FOG_DENSITY)


func test_compatibility_profile_has_the_same_mood() -> void:
	for sun in [MORNING, NOON, EVENING]:
		for weather in Weather.STATES:
			var forward := _look(sun, weather)
			var web := _look(sun, weather, "", true)
			assert_eq(web.keys(), forward.keys(), "gleiche Werte in beiden Profilen")
			assert_almost_eq(web["fog_height_density"], forward["fog_height_density"], 0.000001, "Höhennebel auch im Web")


func test_scene_applies_mood_and_height_fog_in_both_profiles() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.sky_time_mode = DayNight.MODE_FIXED
	config.sky_fixed_hour = 13.0
	config.sky_weather_mode = Weather.MODE_FIXED
	config.sky_weather = Weather.CLEAR
	var ride := spawn_ride(bus, 0.0, config)
	var sky: SkyController = ride.sky
	var environment: Environment = ride.get_node("WorldEnvironment").environment
	assert_eq(environment.fog_height_density, 0.0, "13 Uhr klar: kein Höhennebel")
	sky.set_time_mode(DayNight.MODE_FIXED, 7.5)
	assert_lt(sky.sun_angles.y, 180.0, "7:30: Sonne im Osten")
	assert_gt(environment.fog_height_density, 0.0, "Morgendunst gesetzt")
	assert_almost_eq(environment.fog_height_density, sky.current["fog_height_density"], 0.000001)
	assert_almost_eq(environment.fog_height, sky.current["fog_height"], 0.0001)
	assert_true(environment.fog_light_color.is_equal_approx(sky.current["fog_color"]), "Nebelfarbe gesetzt")
	var morning_sun: Color = ride.get_node("Sun").light_color
	sky.set_time_mode(DayNight.MODE_FIXED, 19.5)
	assert_gt(_warmth(ride.get_node("Sun").light_color), _warmth(morning_sun), "abends goldener")
	sky.set_compatibility(true)
	sky.set_weather_mode(Weather.MODE_FIXED, Weather.RAIN)
	sky.weather.snap()
	sky.apply_now()
	await run_for(0.2)
	assert_gt(environment.fog_height_density, 0.0, "Compatibility: Höhennebel ohne Fehler gesetzt")
	assert_almost_eq(environment.fog_height_density, sky.current["fog_height_density"], 0.000001)
	sky.set_compatibility(false)
