## Leistungsmodell und Wertung je Geräteart (Spec #75, ADR-0010 Nachtrag) als reine Logik: Tempo aus Watt und
## Streckensteigung (mit Gegenprobe gegen die Gleichung), Wattausfall, Geräteart, 3-s-Mittel, Medaillen-Schwellen je
## Geräteart und ein Spielstand im alten Format, der unverändert als Kadenzmodell gilt.
extends GutTest

const DT := 1.0 / 60.0
var TEMP_PATH := TestIsolation.path("test_power_savegame.json")


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _settled_kmh(watts: float, grade: float, config: RideConfig = RideConfig.new()) -> float:
	var model := RideModel.new(config)
	for i in range(int(round(30.0 / DT))):
		model.step_power(watts, grade, DT)
	return model.speed_kmh()


## Leistung, die die Gleichung P = v·m·g·(sin θ + Crr·cos θ) + ½·ρ·CdA·v³ für `v_mps` auf `grade` verlangt.
func _power_for(v_mps: float, grade: float, config: RideConfig) -> float:
	var theta := atan(grade)
	return v_mps * config.power_mass_kg * 9.81 * (sin(theta) + config.power_crr * cos(theta)) \
			+ 0.5 * config.power_air_density * config.power_cda_m2 * pow(v_mps, 3.0)


func test_more_watts_is_faster() -> void:
	assert_gt(_settled_kmh(250.0, 0.0), _settled_kmh(150.0, 0.0))
	assert_gt(_settled_kmh(300.0, 0.06), _settled_kmh(200.0, 0.06))


func test_more_grade_is_slower() -> void:
	var flat := _settled_kmh(200.0, 0.0)
	var climb := _settled_kmh(200.0, 0.04)
	var steep := _settled_kmh(200.0, 0.08)
	assert_lt(climb, flat, "bergauf langsamer")
	assert_lt(steep, climb, "steiler noch langsamer")
	assert_gt(_settled_kmh(200.0, -0.04), flat, "bergab schneller")


func test_zero_watts_on_the_flat_comes_to_a_stop() -> void:
	var model := RideModel.new()
	model.speed_mps = 8.0
	for i in range(int(round(20.0 / DT))):
		model.step_power(0.0, 0.0, DT)
	assert_almost_eq(model.speed_mps, 0.0, 0.001, "0 W in der Ebene: Stillstand")
	assert_eq(model.target_speed_power_mps(0.0, 0.03), 0.0, "0 W bergauf: kein Tempo")


## Gegenprobe: Das Tempo erfüllt die Gleichung mit der Streckensteigung – rot, wenn das Modell die Steigung ignoriert
## (dann wäre das Tempo bei 6 % das der Ebene und verlangte viel mehr Leistung).
func test_speed_solves_the_power_equation_with_the_track_grade() -> void:
	var config := RideConfig.new()
	var model := RideModel.new(config)
	for grade in [0.0, 0.06, 0.1, -0.03]:
		var v := model.target_speed_power_mps(200.0, grade)
		assert_almost_eq(_power_for(v, grade, config), 200.0, 0.01, "200 W bei %.0f %%: v = %.3f m/s" % [grade * 100.0, v])
	assert_almost_eq(model.target_speed_power_mps(200.0, 0.0) * RideModel.KMH_PER_MPS, 34.2, 0.3,
			"Standardwerte: 200 W in der Ebene ≈ 34 km/h")
	assert_lt(model.target_speed_power_mps(200.0, 0.06), 0.5 * model.target_speed_power_mps(200.0, 0.0),
			"6 % halbieren das Tempo bei 200 W mindestens")


func test_downhill_rolls_without_watts_and_stays_below_the_cap() -> void:
	var config := RideConfig.new()
	var model := RideModel.new(config)
	var v := model.target_speed_power_mps(0.0, -0.03)
	assert_gt(v, 5.0, "−3 % rollt man auch ohne Treten")
	assert_almost_eq(_power_for(v, -0.03, config), 0.0, 0.01, "Rollen: Hangabtrieb = Roll- + Luftwiderstand")
	assert_almost_eq(model.target_speed_power_mps(0.0, -0.3) * RideModel.KMH_PER_MPS, config.power_max_kmh, 0.001,
			"steile Abfahrt: höchstens power_max_kmh")
	assert_almost_eq(model.target_speed_power_mps(5000.0, 0.0) * RideModel.KMH_PER_MPS, config.power_max_kmh, 0.001)
	assert_eq(model.target_speed_power_mps(NAN, 0.0), 0.0, "kein Wert = 0 W")
	assert_eq(model.target_speed_power_mps(-50.0, 0.0), 0.0, "negative Watt = 0 W")


func test_missing_watts_hold_until_the_cadence_timeout_then_zero() -> void:
	var model := RideModel.new()
	for i in range(int(round(10.0 / DT))):
		model.step_power(200.0, 0.0, DT)
	var riding := model.speed_mps
	for i in range(int(round(2.0 / DT))):
		model.step_power(NAN, 0.0, DT)
	assert_almost_eq(model.speed_mps, riding, 0.01, "kurzer Aussetzer (< 2,5 s): Tempo bleibt")
	for i in range(int(round(10.0 / DT))):
		model.step_power(NAN, 0.0, DT)
	assert_lt(model.speed_mps, 0.1 * riding, "länger ohne Wert: 0 W, das Rad läuft aus")


func test_inertia_is_the_same_as_in_the_cadence_model() -> void:
	var model := RideModel.new()
	var target := model.target_speed_power_mps(200.0, 0.0)
	var t := 0.0
	while t < model.config.inertia_s - DT / 2.0:
		model.step_power(200.0, 0.0, DT)
		t += DT
	assert_almost_eq(model.speed_mps / target, 1.0 - exp(-1.0), 0.01, "nach inertia_s 63 % des Wegs")


func test_device_kind_needs_measured_power() -> void:
	assert_eq(RideModel.kind_for(212.0, false), RideModel.KIND_POWER, "Trainer mit gemessener Leistung")
	assert_eq(RideModel.kind_for(150.0, true), RideModel.KIND_CADENCE, "geschätzte Leistung (Simulator)")
	assert_eq(RideModel.kind_for(NAN, false), RideModel.KIND_CADENCE, "ohne Leistung")
	var model := RideModel.new()
	model.step_kind(RideModel.KIND_CADENCE, 90.0, 400.0, 0.0, 1.0)
	var cadence := RideModel.new()
	cadence.step(90.0, 0.0, 1.0)
	assert_eq(model.speed_mps, cadence.speed_mps, "Kadenzmodell ignoriert die Watt")


func test_config_reads_the_power_section() -> void:
	var file := ConfigFile.new()
	file.set_value("power", "mass_kg", 70.0)
	file.set_value("power", "cda_m2", 0.25)
	file.set_value("power", "crr", 0.005)
	file.set_value("power", "air_density", 1.1)
	file.set_value("power", "max_kmh", 60.0)
	var path := TestIsolation.path("test_power_config.cfg")
	file.save(path)
	var config := RideConfig.load_file(path)
	DirAccess.remove_absolute(path)
	assert_eq([config.power_mass_kg, config.power_cda_m2, config.power_crr, config.power_air_density,
			config.power_max_kmh], [70.0, 0.25, 0.005, 1.1, 60.0])
	var game := RideConfig.load_file()
	assert_eq([game.power_mass_kg, game.power_cda_m2, game.power_crr, game.power_air_density, game.power_max_kmh],
			[85.0, 0.32, 0.004, 1.225, 70.0], "config.cfg = Standardwerte")


func test_three_second_average() -> void:
	var average := PowerAverage.new()
	assert_true(is_nan(average.value()), "ohne Wert NAN")
	for i in range(180):
		average.add(200.0, DT)
	assert_almost_eq(average.value(), 200.0, 0.001)
	for i in range(90):
		average.add(300.0, DT)
	assert_almost_eq(average.value(), 250.0, 2.0, "1,5 s 200 W + 1,5 s 300 W")
	for i in range(240):
		average.add(300.0, DT)
	assert_almost_eq(average.value(), 300.0, 0.001, "ältere Werte fallen aus dem Fenster")
	for i in range(240):
		average.add(NAN, DT)
	assert_true(is_nan(average.value()), "3 s ohne Wert: NAN")


func test_power_display_with_three_second_average() -> void:
	var main: GDScript = load("res://scenes/main.gd")
	assert_eq(main.format_power(212.4, false, 205.0), "212 W · Ø3s 205 W")
	assert_eq(main.format_power(212.4, false), "212 W", "ohne Mittel nur der Wert")
	assert_eq(main.format_power(150.0, true, 150.0), "~150 W", "geschätzt: ohne Mittel, mit „~“")
	assert_eq(main.format_power(NAN, false, 205.0), "")


func test_medal_thresholds_per_device_kind() -> void:
	var track: Track = autofree(Track.new())
	IslandCourse.apply_to(track)
	var config := RideConfig.new()
	var cadence := Medals.thresholds(track, config)
	var power := Medals.thresholds(track, config, RideModel.KIND_POWER)
	assert_eq(cadence, Medals.thresholds(track, config, RideModel.KIND_CADENCE), "Standard bleibt das Kadenzmodell")
	assert_almost_eq(cadence[Medals.LAP][Medals.GOLD], Medals.simulate_lap(track, config, 95.0)[Medals.LAP], 0.001,
			"Kadenz: Gold bei 95 rpm wie bisher")
	assert_almost_eq(power[Medals.LAP][Medals.SILVER],
			Medals.simulate_lap(track, config, 200.0, RideModel.KIND_POWER)[Medals.LAP], 0.001, "Leistung: Silber bei 200 W")
	assert_lt(power[Medals.LAP][Medals.GOLD], power[Medals.LAP][Medals.SILVER])
	assert_lt(power[Medals.LAP][Medals.SILVER], power[Medals.LAP][Medals.BRONZE])
	assert_ne(power[Medals.LAP][Medals.GOLD], cadence[Medals.LAP][Medals.GOLD], "eigene Schwellen je Geräteart")


func test_old_save_stays_valid_as_cadence_and_power_is_separate() -> void:
	var old := {"version": 1, "active_profile": "0123456789abcdef", "profiles": {"0123456789abcdef": {
		"created": "2026-09-01T10:00:00Z", "rides": [],
		"best_times": {"island": {"cw": 884.7}},
		"segment_best_times": {"island": {"cw": {"dorfsprint": 49.4}}},
		"medals": {"island": {"cw": {"lap": "silver"}}},
		"ghosts": {"island": {"cw": {"best": {"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 2.0,
				"distance_m": [0.0, 5.0, 10.0]}}}}}}}
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var save := SaveGame.load_file(TEMP_PATH)
	assert_eq(save.version(), 1, "kein Versionssprung")
	var cw := LapTiming.DIRECTION_CW
	assert_eq(save.best_time_s("island", cw), 884.7, "alte Bestzeit gilt als Kadenzmodell")
	assert_eq(save.best_time_s("island", cw, RideModel.KIND_CADENCE), 884.7)
	assert_eq(save.segment_best_s("island", cw, "dorfsprint"), 49.4)
	assert_eq(save.best_medal("island", cw, Medals.LAP), Medals.SILVER)
	assert_not_null(save.ghost("island", cw, Ghost.BEST), "alter Ghost gilt als Kadenzmodell")
	assert_eq(save.best_time_s("island", cw, RideModel.KIND_POWER), INF, "Leistungsmodell: noch keine Bestzeit")
	assert_eq(save.segment_best_s("island", cw, "dorfsprint", RideModel.KIND_POWER), INF)
	assert_eq(save.best_medal("island", cw, Medals.LAP, RideModel.KIND_POWER), Medals.NONE)
	assert_null(save.ghost("island", cw, Ghost.BEST, RideModel.KIND_POWER), "Ghosts nur gegen dieselbe Geräteart")
	# Eine Leistungsfahrt schreibt nur ihre Bereiche; die alten Schlüssel bleiben, wie sie waren.
	assert_true(save.record_best_time("island", cw, 900.0, RideModel.KIND_POWER), "eigene Bestzeit, auch langsamer")
	assert_true(save.record_segment_time("island", cw, "dorfsprint", 47.0, RideModel.KIND_POWER))
	assert_true(save.record_medal("island", cw, Medals.LAP, Medals.BRONZE, RideModel.KIND_POWER))
	save.record_ghost("island", cw, Ghost.LAST, Ghost.from_dict(old["profiles"]["0123456789abcdef"]["ghosts"]["island"]["cw"]["best"]),
			RideModel.KIND_POWER)
	save.save_file(TEMP_PATH)
	var written := JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH)) as Dictionary
	var profile: Dictionary = written["profiles"]["0123456789abcdef"]
	var before: Dictionary = old["profiles"]["0123456789abcdef"]
	for area in ["best_times", "segment_best_times", "medals", "ghosts"]:
		assert_eq(JSON.stringify(profile[area]), JSON.stringify(before[area]), "%s unverändert" % area)
	assert_eq(JSON.stringify(profile["measured_best_times"]), JSON.stringify({"island": {"cw": 900.0}}))
	assert_eq(JSON.stringify(profile["measured_segment_best_times"]), JSON.stringify({"island": {"cw": {"dorfsprint": 47.0}}}))
	assert_eq(JSON.stringify(profile["measured_medals"]), JSON.stringify({"island": {"cw": {"lap": "bronze"}}}))
	assert_true(profile["measured_ghosts"]["island"]["cw"].has("last"))
	var reloaded := SaveGame.load_file(TEMP_PATH)
	assert_eq(reloaded.best_time_s("island", cw), 884.7)
	assert_eq(reloaded.best_time_s("island", cw, RideModel.KIND_POWER), 900.0)
	assert_eq(reloaded.best_medal("island", cw, Medals.LAP), Medals.SILVER, "Kadenz-Medaille bleibt Silber")
