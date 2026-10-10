## Balancing-Simulation (#55) als reine Logik: Kadenzverläufe als Daten im Standardbereich, Reproduzierbarkeit mit Seed
## (gleicher Seed → derselbe Bericht, anderer Seed → anderer), der Bericht nennt alle Kennzahlen (Häufigkeit je Seltenheit,
## Dauer je Boss, Erfolgsquote je Herausforderung und Stufe samt Elite und Boss-Phasen, Erreichbarkeit der Stufen), die
## Laufbahn arbeitet nur im Speicher, und die Ausrüstung der Variante „empfohlen“ ergibt genau die Empfohlene Stärke.
## Kleine Läufe (kurze Fahrten), die volle Simulation startet `tools/balancing_sim.gd`.
extends GutTest

const SMALL := {"seed": 7, "runs": 2, "gear_runs": 1, "careers": 1, "career_max_runs": 3, "ride_s": 600.0}


func test_profiles_are_data_in_the_standard_range() -> void:
	assert_eq(Balancing.IDS, ["einsteiger", "trainierter", "sprinter"])
	var range_ := CadenceRange.new()
	for id in Balancing.IDS:
		var p: Dictionary = Balancing.PROFILES[id]
		assert_between(p["base_rpm"], range_.minimum, range_.maximum, id + ": Grundkadenz im Standardbereich")
		assert_gte(p["peak_rpm"], p["base_rpm"], id + ": Spitze nicht unter der Grundkadenz")
		assert_between(p["follow"], 0.0, 1.0, id + ": Gewicht des Ziels")
		assert_gt(p["lag_s"], 0.0)
		assert_ne(p["text"], "", id + ": beschrieben")


func test_rider_cadence_stays_within_zero_and_peak() -> void:
	for id in Balancing.IDS:
		var rider := Balancing.Rider.new(Balancing.PROFILES[id], 3)
		var highest := 0.0
		for i in range(2000):
			var cadence := rider.step(0.5, 120.0 if i % 200 < 100 else NAN)
			highest = maxf(highest, cadence)
			assert_between(cadence, 0.0, Balancing.PROFILES[id]["peak_rpm"], id)
		assert_gt(highest, 60.0, id + ": tritt überhaupt")


func test_run_seeds_are_stable_and_distinct() -> void:
	var a := Balancing.run_seed(1, "trainierter", 2, Balancing.GEAR_NONE, 5)
	assert_eq(a, Balancing.run_seed(1, "trainierter", 2, Balancing.GEAR_NONE, 5))
	var others := [Balancing.run_seed(2, "trainierter", 2, Balancing.GEAR_NONE, 5), Balancing.run_seed(1, "sprinter", 2, Balancing.GEAR_NONE, 5),
			Balancing.run_seed(1, "trainierter", 3, Balancing.GEAR_NONE, 5), Balancing.run_seed(1, "trainierter", 2, Balancing.GEAR_RECOMMENDED, 5),
			Balancing.run_seed(1, "trainierter", 2, Balancing.GEAR_NONE, 6)]
	for other in others:
		assert_ne(other, a)
	assert_gte(a, 0)


func test_recommended_gear_gives_exactly_the_recommended_strength() -> void:
	for entry in ArcadeTiers.LIST:
		var gear := Balancing.recommended_gear(entry["tier"])
		assert_eq(ArcadeTiers.strength_of(gear), entry["strength"], "Stufe %d" % entry["tier"])


func test_course_has_the_island_sections_and_bosses_sit_in_them() -> void:
	var info := Balancing.course()
	assert_gt(info["length"], 1000.0)
	var names: Array = info["sections"].map(func(s): return s["name"])
	for boss in ArcadeRun.fixed_from_types():
		assert_has(names, boss["section"], "%s hat seinen Abschnitt" % boss["name"])


func test_a_ride_is_reproducible_and_records_challenges() -> void:
	var first := Balancing.ride(Balancing.new_run(1, 11), "trainierter", 11, 900.0)
	var second := Balancing.ride(Balancing.new_run(1, 11), "trainierter", 11, 900.0)
	assert_eq(first, second, "gleicher Seed, gleiche Fahrt")
	assert_gt(first["records"].size(), 0, "Herausforderungen wurden gefahren")
	assert_gt(first["laps"], 0.0)
	for record in first["records"]:
		assert_has(["normal", "elite", "boss"], record["kind"])
		assert_gt(record["duration_s"], 0.0)
	var other := Balancing.ride(Balancing.new_run(1, 12), "trainierter", 12, 900.0)
	assert_ne(first, other, "anderer Seed, andere Fahrt")


func test_a_rider_who_does_not_pedal_scores_nothing() -> void:
	var idle := Balancing.PROFILES["einsteiger"].duplicate()
	idle["base_rpm"] = 0.0
	idle["peak_rpm"] = 0.0
	var run := Balancing.new_run(1, 4)
	# Stehend: kein Tempo, also nie ein Starttor – Ausrüstung ändert daran nichts (Ausrüstung ersetzt nie das Treten).
	run.gear = Balancing.recommended_gear(6)
	var rider := Balancing.Rider.new(idle, 4)
	var distance := 0.0
	for i in range(200):
		var cadence := rider.step(0.5, 100.0)
		assert_eq(cadence, 0.0)
		run.advance(distance, cadence, 0.5)
	assert_eq(run.results.size(), 0)
	assert_eq(run.points, 0)


func test_report_is_reproducible_and_depends_on_the_seed() -> void:
	var meta := {"command": "`test`", "commit": "abc1234", "date": "2026-10-09"}
	var text := Balancing.report(Balancing.simulate(SMALL), SMALL, meta)
	assert_eq(text, Balancing.report(Balancing.simulate(SMALL), SMALL, meta), "gleicher Seed, derselbe Bericht")
	var other_options := SMALL.duplicate()
	other_options["seed"] = 8
	assert_ne(text, Balancing.report(Balancing.simulate(other_options), other_options, meta), "anderer Seed, anderer Bericht")


func test_report_names_all_key_figures() -> void:
	var meta := {"command": "`test`", "commit": "abc1234", "date": "2026-10-09"}
	var text := Balancing.report(Balancing.simulate(SMALL), SMALL, meta)
	for part in ["Seed: 7", "Befehl: `test`", "Stand (Commit): abc1234", "Datum: 2026-10-09",
			"### Häufigkeit je Seltenheit", "### Erfolgsquote je Herausforderung und Stufe", "### Erfolgsquote der Boss-Phasen",
			"### Dauer je Boss", "### Mit Empfohlener Stärke", "## Erreichbarkeit der Stufen"]:
		assert_string_contains(text, part)
	for id in Balancing.IDS:
		assert_string_contains(text, "## " + Balancing.PROFILES[id]["name"])
	for rarity in Loot.RARITIES:
		assert_string_contains(text, Loot.RARITIES[rarity]["name"])
	for tier in range(1, 7):
		assert_string_contains(text, "Stufe %d" % tier)
	for boss in ArcadeRun.fixed_from_types():
		assert_string_contains(text, "Boss: " + boss["name"])
		for phase in boss["phases"]:
			assert_string_contains(text, phase["name"])
	for definition in Encounters.CHALLENGES:
		if definition["block"] != EliteGroups.ID:
			assert_string_contains(text, definition["id"])
	for rank in EliteGroups.RANKS:
		assert_string_contains(text, "Elite: " + EliteGroups.RANKS[rank]["name"])
	assert_string_contains(text, "Sieg: Median s")


func test_career_runs_in_memory_and_reports_progress() -> void:
	var career := Balancing.career("trainierter", 5, 0, 3, 600.0)
	assert_eq(career, Balancing.career("trainierter", 5, 0, 3, 600.0), "Laufbahn mit Seed reproduzierbar")
	assert_between(career["runs"], 1, 3)
	assert_gte(career["final_level"], 1)
	for key in career["unlocked"]:
		assert_between(int(key), ArcadeTiers.START_UNLOCKED + 1, ArcadeTiers.LIST.size(), "nur freischaltbare Stufen")


func test_quantile_uses_nearest_rank() -> void:
	assert_eq(Balancing.quantile([4.0, 1.0, 3.0, 2.0], 0.5), 2.0)
	assert_eq(Balancing.quantile([4.0, 1.0, 3.0, 2.0], 0.9), 4.0)
	assert_true(is_nan(Balancing.quantile([], 0.5)))
