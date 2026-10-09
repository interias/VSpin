## Bosse (#51) als reine Logik: Boss-Phasen als Daten aus vorhandenen Bausteinen, der Lebensbalken sinkt nur mit Kadenz
## in der Zielzone, Sieg und Entkommen (weich), Pause, Kadenzbereich-Wächter für jede Phase (Positiv- und Gegenprobe),
## Ausrüstung und Fähigkeiten nur mit Kadenz, Schild; die Planung an festen Orten (Küstenstraße, Serpentinen, Bergdorf –
## nicht im Würfel-Pool, übrige Würfe unverändert, keine auf der Graybox), Punkte, Boss-Beute und Zusammenfassung im Lauf.
extends GutTest

const DT := 0.1
const BOSSES := preload("res://src/challenges/boss_challenges.gd")
## Abschnitte der Bosse auf dem Rundkurs (Stationsnamen, IslandCourse).
const PLACES := {"tramuntana": "Küstenstraße", "drac": "Serpentinen", "dimonis": "Bergdorf"}


func _boss(id: String, tier: int = 1, range_: CadenceRange = CadenceRange.new(), gear: Dictionary = {}) -> BossFight:
	return Encounters.build(BOSSES.find(id), tier, range_, gear) as BossFight


func _feed(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


## Tramuntana auf Stufe 1, 60–120 rpm: Gegenwind 80–100 rpm (10 s), Böe ab 105 rpm (5 s), Sturmfront 86–106 rpm (12 s).
func _defeat_tramuntana(boss: BossFight) -> void:
	_feed(boss, 90.0, 10.5)
	_feed(boss, 110.0, 5.5)
	_feed(boss, 96.0, 12.5)


func _island_sections() -> Array:
	return ArcadeRun.sections_from_stations(IslandCourse.stations(), IslandCourse.curve().get_baked_length())


## Lauf mit nur dem Boss `id` im Pool (Graybox-artig: ein Abschnitt), Startpunkt bei 50 m.
func _boss_run(id: String, seed_value: int = 3) -> ArcadeRun:
	return ArcadeRun.new(1, CadenceRange.new(), [], 100000.0, 0.0, seed_value, [BOSSES.find(id)], [])


func _ride(run: ArcadeRun, from_m: float, cadence: float, seconds: float) -> float:
	var d := from_m
	for i in range(roundi(seconds / DT)):
		d += 6.0 * DT
		run.advance(d, cadence, DT)
	return d


# --- Daten ---------------------------------------------------------------------------------------------------------


func test_three_bosses_are_data_made_of_existing_blocks() -> void:
	assert_eq(BOSSES.FIXED.map(func(d): return d["id"]), ["tramuntana", "drac", "dimonis"])
	var classes := {"zone_hold": ZoneHold, "breakthrough": Breakthrough, "chase": Chase}
	for definition in BOSSES.FIXED:
		assert_eq(definition["block"], BOSSES.ID)
		assert_eq(definition["section"], PLACES[definition["id"]], "fester Ort")
		assert_true(definition["boss"])
		var boss := _boss(definition["id"])
		assert_true(boss is BossFight, definition["id"])
		assert_eq(boss.boss_name, definition["name"])
		assert_eq(boss.phase_count(), definition["phases"].size())
		assert_gt(boss.phase_count(), 1, "ein Boss kombiniert mehrere Bausteine")
		for i in range(boss.phase_count()):
			var phase: Dictionary = definition["phases"][i]
			assert_true(is_instance_of(boss.phases[i], classes[phase["block"]]), phase["id"])
	# Charakter: Tramuntana hält die Zone gegen Böen, der Drache ist der große Kampf, die Dimonis sind eine Jagd.
	var blocks := func(id: String) -> Array: return BOSSES.find(id)["phases"].map(func(p): return p["block"])
	assert_eq(blocks.call("tramuntana"), ["zone_hold", "breakthrough", "zone_hold"])
	assert_eq(blocks.call("drac").size(), 4, "der größte Kampf")
	assert_eq(blocks.call("dimonis").filter(func(b): return b == "chase").size(), 2, "Jagd durchs Dorf")


func test_bosses_are_not_in_the_dice_pool() -> void:
	assert_eq(BOSSES.CHALLENGES, [], "Bosse werden nicht gewürfelt")
	assert_eq(Encounters.CHALLENGES.size(), 11, "Würfel-Pool unverändert")
	assert_false(Encounters.CHALLENGES.any(func(d): return d["block"] == BOSSES.ID))
	assert_eq(Encounters.find("tramuntana"), {}, "nicht im Pool")


func test_a_boss_definition_with_an_unknown_phase_builds_nothing() -> void:
	var broken := {"id": "x", "block": BOSSES.ID, "name": "X", "phases": [{"id": "p", "block": "gibt_es_nicht"}]}
	assert_null(Encounters.build(broken, 1, CadenceRange.new()))
	assert_null(Encounters.build({"id": "y", "block": BOSSES.ID, "name": "Y", "phases": []}, 1, CadenceRange.new()))


# --- Lebensbalken, Sieg, Entkommen ---------------------------------------------------------------------------------


func test_the_life_bar_sinks_only_with_cadence_in_the_zone() -> void:
	var boss := _boss("tramuntana")
	assert_eq(boss.health(), 1.0, "voll zu Beginn")
	assert_eq(boss.zone(), Vector2(80.0, 100.0), "Zone der ersten Phase")
	for cadence in [0.0, 70.0, 79.9, 100.1, 130.0]:
		_feed(boss, cadence, 2.0)
		assert_eq(boss.health(), 1.0, "%.1f rpm außerhalb der Zone: der Balken bleibt" % cadence)
	_feed(boss, 90.0, 5.0)
	assert_almost_eq(boss.health(), 1.0 - 0.5 / 3.0, 0.001, "halbe Phase von drei")
	_feed(boss, 70.0, 2.0)
	assert_almost_eq(boss.health(), 1.0 - 0.5 / 3.0, 0.001, "außerhalb steht er wieder")


func test_phases_run_in_order_and_the_boss_is_defeated() -> void:
	var boss := _boss("tramuntana")
	_feed(boss, 90.0, 10.5)
	assert_eq(boss.phase_number(), 2, "nach dem Gegenwind die Böe")
	assert_eq(boss.zone(), Vector2(105.0, 120.0), "ab 105 rpm")
	assert_almost_eq(boss.health(), 2.0 / 3.0, 0.001)
	assert_almost_eq(boss.current_phase().elapsed_s, 0.5, 0.001, "die neue Phase beginnt bei 0")
	_feed(boss, 110.0, 5.5)
	assert_eq(boss.phase_number(), 3)
	assert_false(boss.finished())
	_feed(boss, 96.0, 12.5)
	assert_eq(boss.state, ChallengeBlock.SUCCEEDED, "besiegt")
	assert_eq(boss.health(), 0.0, "Lebensbalken leer")
	assert_eq(boss.progress(), 1.0)
	var before := boss.elapsed_s
	boss.update(90.0, DT)
	assert_eq(boss.elapsed_s, before, "nach dem Ende wirkungslos")


func test_a_failed_phase_lets_the_boss_escape() -> void:
	var boss := _boss("tramuntana")
	_feed(boss, 90.0, 10.5)
	_feed(boss, 100.0, 15.0)  # unter der Böen-Schwelle 105: der Balken bleibt leer, das Fenster läuft ab
	assert_eq(boss.state, ChallengeBlock.FAILED, "der Boss entkommt")
	assert_almost_eq(boss.health(), 2.0 / 3.0, 0.001, "nur die erste Phase hat ihn getroffen")
	assert_almost_eq(boss.loot_progress(), 1.0 / 3.0, 0.001, "für die Beute zählt der Schaden")
	var idle := _boss("drac")
	_feed(idle, 0.0, 30.0)
	assert_eq(idle.state, ChallengeBlock.FAILED, "ohne Treten entkommt er")
	assert_eq(idle.loot_progress(), 0.0, "ohne Kadenz kein Schaden – keine Beute")


func test_the_dimonis_head_start_does_not_hurt_them() -> void:
	var boss := _boss("dimonis")
	assert_true(boss.current_phase() is Chase)
	assert_gt(boss.progress(), 0.0, "der Stand der Jagd zeigt den Vorsprung")
	assert_eq(boss.health(), 1.0, "der Lebensbalken nicht: geschenkter Vorsprung ist kein Schaden")
	_feed(boss, 100.0, 3.0)  # über 93 rpm: aufholen
	assert_lt(boss.health(), 1.0)
	var caught := _boss("dimonis")
	_feed(caught, 80.0, 6.0)  # unter der Schwelle: sie entwischen (Vorsprung 0,4 in 12 s × 0,4 = 4,8 s)
	assert_eq(caught.state, ChallengeBlock.FAILED, "entwischt: die Dimonis entkommen")
	assert_eq(caught.loot_progress(), 0.0)


func test_a_pause_changes_nothing() -> void:
	var boss := _boss("drac")
	_feed(boss, 90.0, 3.0)
	var health := boss.health()
	var elapsed := boss.elapsed_s
	for i in range(50):
		boss.update(90.0, 0.0)
	assert_eq(boss.health(), health)
	assert_eq(boss.elapsed_s, elapsed)
	assert_eq(boss.remaining_s(), boss.current_phase().remaining_s() + 18.0 + 24.0 + 16.0, "Restzeit: Phase plus folgende")


# --- Wächter, Ausrüstung, Fähigkeiten ------------------------------------------------------------------------------


func test_every_phase_zone_is_guarded_by_the_personal_range() -> void:
	# Positivprobe: jede Phase jedes Bosses auf jeder Stufe in jedem wählbaren Bereich, mit und ohne Ausrüstungsbreite.
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for tier in [1, 2, 3]:
				for gear in [{}, {"zone_width_rpm": 10}]:
					for definition in BOSSES.FIXED:
						var boss := _boss(definition["id"], tier, range_, gear)
						for phase in boss.phases:
							var zone: Vector2 = phase.zone()
							assert_true(range_.contains_zone(zone.x, zone.y),
									"%s %d–%d Stufe %d: %s" % [definition["id"], lower, upper, tier, zone])
	# Gegenprobe: eine Phase mit einer Lage weit über dem Bereich (1,4 → 144 rpm) landet durch den Wächter im Bereich –
	# die Phasen laufen durch Encounters.build, nicht an ihm vorbei.
	var personal := CadenceRange.new(60.0, 120.0)
	assert_gt(personal.at(1.4), 120.0, "ohne Wächter läge die Zone außerhalb")
	var wild := {"id": "wild", "block": BOSSES.ID, "name": "Wild", "phases": [
			{"id": "w1", "block": "zone_hold", "name": "W", "zone_at": 1.4, "hold_s": 5.0, "window_s": 10.0},
			{"id": "w2", "block": "breakthrough", "name": "B", "threshold_at": 1.4, "fill_s": 5.0, "window_s": 10.0}]}
	var boss := Encounters.build(wild, 3, personal, {"zone_width_rpm": 10}) as BossFight
	assert_eq(boss.phases[0].zone(), Vector2(100.0, 120.0), "Zone (20 rpm breit) hineingeschoben")
	assert_eq(boss.phases[1].zone(), Vector2(115.0, 120.0), "Schwelle nicht über dem Maximum")
	assert_eq(Encounters.zone_for(wild, 3, personal, {"zone_width_rpm": 10}), boss.phases[0].zone(),
			"Ankündigung: Ziel der ersten Phase")


func test_gear_and_abilities_only_help_with_cadence_in_the_zone() -> void:
	# Ausrüstung (+50 % Fortschritt) und Windböe (Faktor + 2) wirken über progress_factor auf die laufende Phase.
	var geared := _boss("tramuntana", 1, CadenceRange.new(), {"progress_pct": 50})
	assert_eq(geared.progress_factor, 1.5)
	# Gegenprobe: ohne Kadenz in der Zone mit und ohne Faktor gleich – nichts.
	for cadence in [0.0, 70.0, 104.0]:
		var plain := _boss("tramuntana")
		var strong := _boss("tramuntana")
		strong.progress_factor = 3.0
		_feed(plain, cadence, 4.0)
		_feed(strong, cadence, 4.0)
		assert_eq(strong.health(), plain.health(), "%.0f rpm: der Faktor ersetzt nie das Treten" % cadence)
		assert_eq(strong.health(), 1.0)
	var plain := _boss("tramuntana")
	var strong := _boss("tramuntana")
	strong.progress_factor = 3.0
	_feed(plain, 90.0, 2.0)
	_feed(strong, 90.0, 2.0)
	assert_eq(strong.current_phase().progress_factor, 3.0, "der Kampf reicht den Faktor an die Phase weiter")
	assert_almost_eq(1.0 - strong.health(), 3.0 * (1.0 - plain.health()), 0.001, "in der Zone dreifach")
	assert_eq(strong.zone(), plain.zone(), "die Zielzone bleibt")
	assert_eq(strong.current_phase().elapsed_s, plain.current_phase().elapsed_s, "die Zeit bleibt")


func test_the_windboe_reaches_the_boss_phase() -> void:
	var run := _boss_run("tramuntana")
	var abilities := Abilities.new()
	var d := _ride(run, 0.0, 90.0, 9.0)
	assert_true(run.active.get("block") is BossFight, "der Kampf läuft")
	abilities.step(run, [], DT)
	var boss: BossFight = run.active["block"]
	abilities.step(run, [CadencePatterns.ANTRITT], DT)
	assert_eq(boss.progress_factor, 3.0, "Windböe auf dem Bosskampf")
	var health := boss.health()
	_ride(run, d, 90.0, 0.5)
	assert_eq(boss.current_phase().progress_factor, 3.0, "… und auf seiner Phase")
	assert_almost_eq(health - boss.health(), 3.0 * 0.5 / 10.0 / 3.0, 0.001, "0,5 s in der Zone zählen dreifach")


func test_the_shield_takes_back_the_boss_recovering() -> void:
	var run := _boss_run("tramuntana")
	var abilities := Abilities.new()
	var d := _ride(run, 0.0, 90.0, 9.0)
	var boss: BossFight = run.active["block"]
	d = _ride(run, d, 90.0, 10.5)  # Gegenwind geschafft
	assert_eq(boss.phase_number(), 2)
	d = _ride(run, d, 110.0, 2.0)  # Böe: Balken bei 0,4
	var level: float = boss.current_phase().progress()
	assert_almost_eq(level, 0.4, 0.02)
	abilities.step(run, [], DT)
	abilities.step(run, [CadencePatterns.INNEHALTEN], DT)
	assert_true(abilities.is_active("schild"))
	var elapsed: float = boss.current_phase().elapsed_s
	for i in range(10):  # 1 s unter der Schwelle: der Balken sänke, der Boss erholte sich
		d += 6.0 * DT
		run.advance(d, 60.0, DT)
		abilities.step(run, [], DT)
	assert_almost_eq(boss.current_phase().progress(), level, 0.001, "das Schild nimmt das Sinken zurück")
	assert_almost_eq(boss.current_phase().elapsed_s, elapsed + 1.0, 0.001, "die Zeit der Phase läuft weiter")
	var bare := _boss_run("tramuntana")
	var e := _ride(bare, 0.0, 90.0, 19.5)
	e = _ride(bare, e, 110.0, 2.0)
	_ride(bare, e, 60.0, 1.0)
	assert_lt(bare.active["block"].current_phase().progress(), level - 0.05, "Gegenprobe: ohne Schild sinkt er")


# --- Planung an festen Orten ---------------------------------------------------------------------------------------


func test_bosses_wait_at_their_places_every_lap() -> void:
	var sections := _island_sections()
	var length := IslandCourse.curve().get_baked_length()
	var run := ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, 1)
	for lap in [0, 1]:
		for id in PLACES:
			var section: Dictionary = sections.filter(func(s): return s["name"] == PLACES[id])[0]
			var here := run.planned.filter(func(e): return e["lap"] == lap and e["section"] == PLACES[id])
			assert_eq(here.size(), 1, "Runde %d: nur der Boss in %s" % [lap, PLACES[id]])
			assert_eq(here[0]["definition"]["id"], id)
			assert_almost_eq(here[0]["at_m"], lap * length + section["start_m"] + ArcadeRun.START_LEAD_M, 0.001,
					"am Anfang des Abschnitts")
	assert_false(run.planned.any(func(e): return e["definition"]["block"] == BOSSES.ID and e["section"] == "Hafen"))


func test_the_other_sections_keep_their_rolls() -> void:
	var sections := _island_sections()
	var length := IslandCourse.curve().get_baked_length()
	for seed_value in [1, 2, 7]:
		var with_bosses := ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, seed_value)
		var without := ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, seed_value,
				Encounters.CHALLENGES, [])
		var others := func(run: ArcadeRun) -> Array:
			return run.planned.filter(func(e): return not PLACES.values().has(e["section"])).map(
					func(e): return [e["definition"]["id"], e["at_m"], e["lap"]])
		assert_eq(others.call(with_bosses), others.call(without), "Seed %d: gleiche Würfe außerhalb der Boss-Orte" % seed_value)
		assert_false(without.planned.any(func(e): return e["definition"]["block"] == BOSSES.ID), "ohne feste keine Bosse")


func test_no_boss_on_the_graybox() -> void:
	for seed_value in range(1, 20):
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 900.0, 0.0, seed_value)
		assert_false(run.planned.any(func(e): return e["definition"]["block"] == BOSSES.ID), "keine Stationen, kein Boss")
	assert_eq(ArcadeRun.fixed_from_types(), BOSSES.FIXED, "feste Begegnungen aus den Typdateien")


# --- Im Lauf: Punkte, Beute, Zusammenfassung -----------------------------------------------------------------------


func test_a_defeated_boss_gives_points_boss_loot_and_a_summary_line() -> void:
	# Ein Seed, bei dem der Fund mit Qualität 2 ein anderer ist als mit 1 (derselbe Würfel wie im Lauf: Seed + 1, erst
	# der Fundwurf) – so zeigt das Ergebnis, dass die Boss-Beute die höhere Qualität hatte.
	var seed_value := -1
	var boss_item := {}
	var plain_item := {}
	for candidate in range(1, 60):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate + 1
		rng.randf()
		var state := rng.state
		boss_item = Loot.roll(rng, 2.0)
		rng.state = state
		plain_item = Loot.roll(rng, 1.0)
		if boss_item != plain_item:
			seed_value = candidate
			break
	assert_gt(seed_value, 0)
	var run := _boss_run("tramuntana", seed_value)
	var d := _ride(run, 0.0, 90.0, 9.0)
	assert_true(run.active.get("block") is BossFight)
	d = _ride(run, d, 90.0, 10.5)
	d = _ride(run, d, 110.0, 5.5)
	_ride(run, d, 96.0, 12.5)
	assert_eq(run.results.size(), 1)
	var result: Dictionary = run.results[0]
	assert_true(result["boss"])
	assert_true(result["succeeded"])
	assert_eq(result["points"], 400)
	assert_eq(run.points, 400)
	assert_false(result["loot"].is_empty(), "besiegt: sicher Beute")
	assert_eq(result["loot"], boss_item, "Boss-Beute mit Qualität 2 (Tramuntana)")
	assert_ne(result["loot"], plain_item, "Gegenprobe: nicht die Grundqualität")
	var lines := run.summary_lines()
	assert_has(lines, "Bosse: Tramuntana besiegt")
	assert_false(lines.any(func(l): return l.begins_with("Tramuntana ")), "nicht unter den Herausforderungen je Name")
	assert_eq(run.to_entry(), {"tier": 1, "points": 400, "won": 1, "failed": 0}, "Fahrteintrag wie bisher")


func test_an_escaped_boss_gives_nothing_and_the_ride_goes_on() -> void:
	var run := _boss_run("tramuntana")
	var d := _ride(run, 0.0, 70.0, 9.0)
	assert_true(run.active.get("block") is BossFight)
	_ride(run, d, 70.0, 21.0)
	assert_eq(run.results.size(), 1)
	var result: Dictionary = run.results[0]
	assert_false(result["succeeded"], "entkommen")
	assert_eq(result["points"], 0)
	assert_eq(result["loot"], {}, "ohne Schaden keine Beute")
	assert_eq(run.points, 0)
	assert_has(run.summary_lines(), "Bosse: Tramuntana entkommen")
	assert_false(run.planned.is_empty(), "die Fahrt geht weiter")


func test_points_scale_with_the_tier() -> void:
	assert_eq(Encounters.points_for(BOSSES.find("drac"), 3), 1800)
	var boss := _boss("tramuntana", 3)
	assert_eq(boss.phases[0].hold_s, 15.0, "Dauer × 1,5")
	assert_eq(boss.phases[0].zone(), Vector2(85.0, 95.0), "Zone 10 rpm breit")
