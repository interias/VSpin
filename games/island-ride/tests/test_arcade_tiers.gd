## Stufen mit empfohlener Stärke (#54) als reine Logik: Stufen als Daten (engere Zonen, zähere Bosse, bessere Beute, mehr
## Punkte), Freischalten durch Abschluss (alle Bosse einer Stufe besiegt, über Läufe gesammelt; nur die höchste freie
## schaltet die nächste frei), Empfohlene Stärke aus Ausrüstung und Talenten, Rundensteigerung im Lauf (härter und
## lohnender, Würfe unverändert), Spielstand (additiv, alter Stand lädt) und der Wächter des Kadenzbereichs über alle
## Stufen × Runden × wählbare Bereiche × alle Bausteintypen samt Boss-Phasen und Elite-Gruppen (Positiv- und Gegenprobe).
extends GutTest

const DT := 0.25
const BOSSES := preload("res://src/challenges/boss_challenges.gd")
const LONG := [{"name": "Lang", "start_m": 0.0, "end_m": 600.0}]
var TEMP_PATH := TestIsolation.path("test_arcade_tiers_savegame.json")
## Zonen außerhalb des Bereichs (Wächter-Probe; leer erwartet).
var _outside: Array = []


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _tiers() -> Array:
	return ArcadeTiers.LIST.map(func(t): return t["tier"])


## Lauf auf Stufe `tier`, dessen Ergebnisse `results` sind (wie ArcadeRun.results; nur `id`, `boss`, `succeeded` zählen).
func _finished_run(tier: int, results: Array) -> ArcadeRun:
	var run := ArcadeRun.new(tier, CadenceRange.new(), LONG, 600.0, 0.0, 1, [Encounters.find("zone_mitte")], [])
	run.results = results
	return run


func _boss_result(id: String, won: bool = true) -> Dictionary:
	return {"id": id, "name": id, "boss": true, "succeeded": won}


# --- Stufen als Daten ------------------------------------------------------------------------------------------------


func test_tiers_as_data_get_harder_and_more_rewarding() -> void:
	assert_eq(_tiers(), [1, 2, 3, 4, 5, 6], "drei Startstufen und drei freischaltbare")
	assert_eq(ArcadeTiers.START_UNLOCKED, 3)
	for i in range(1, ArcadeTiers.LIST.size()):
		var lower: Dictionary = ArcadeTiers.LIST[i - 1]
		var higher: Dictionary = ArcadeTiers.LIST[i]
		var label: String = higher["name"]
		assert_lt(higher["zone_width_rpm"], lower["zone_width_rpm"], label + ": engere Zonen")
		assert_gt(higher["duration_factor"], lower["duration_factor"], label + ": länger")
		assert_gt(higher["points_factor"], lower["points_factor"], label + ": mehr Punkte")
		assert_gt(higher["loot_quality"], lower["loot_quality"], label + ": bessere Beute")
		assert_gte(higher["boss_factor"], lower["boss_factor"], label + ": Bosse nicht weicher")
		assert_gt(higher["strength"], lower["strength"], label + ": höhere empfohlene Stärke")
	# Die drei Stufen aus #46 bleiben, wie sie waren (Zonen, Dauer, Punkte, Bosse).
	assert_eq(ArcadeTiers.LIST.slice(0, 3).map(func(t): return [t["zone_width_rpm"], t["duration_factor"],
			t["points_factor"], t["boss_factor"]]), [[20.0, 1.0, 1.0, 1.0], [14.0, 1.25, 2.0, 1.0], [10.0, 1.5, 3.0, 1.0]])
	assert_eq(ArcadeTiers.recommended_strength(1), 0, "Stufe 1 setzt nichts voraus")


func test_higher_tiers_narrow_zones_toughen_bosses_and_improve_loot() -> void:
	var personal := CadenceRange.new()
	var mitte := Encounters.find("zone_mitte")
	var widths := _tiers().map(func(t):
		var zone := Encounters.zone_for(mitte, t, personal)
		return zone.y - zone.x)
	assert_eq(widths, [20.0, 14.0, 10.0, 9.0, 8.0, 7.0], "engere Zielzonen")
	# Zähere Bosse: jede Phase länger als dieselbe Herausforderung außerhalb des Bosses (Boss-Faktor ab Stufe 4).
	var tramuntana := BOSSES.find("tramuntana")
	var gegenwind: Dictionary = tramuntana["phases"][0]
	for tier in _tiers():
		var boss := Encounters.build(tramuntana, tier, personal) as BossFight
		var alone := Encounters.build(gegenwind, tier, personal) as ZoneHold
		var phase := boss.phases[0] as ZoneHold
		var factor: float = ArcadeTiers.get_tier(tier)["boss_factor"]
		assert_almost_eq(phase.hold_s, alone.hold_s * factor, 1e-6, "Stufe %d: Boss-Phase × %.1f" % [tier, factor])
		assert_almost_eq(phase.window_s, alone.window_s * factor, 1e-6, "Fenster wächst mit (lösbar)")
	var windows := _tiers().map(func(t): return (Encounters.build(tramuntana, t, personal) as BossFight).remaining_s())
	for i in range(1, windows.size()):
		assert_gt(windows[i], windows[i - 1], "Stufe %d: der Kampf dauert länger" % (i + 1))
	# Bessere Beute: Grundqualität des Laufs je Stufe, mit Boss-Qualität multipliziert.
	for tier in _tiers():
		var run := ArcadeRun.new(tier, personal, LONG, 600.0, 0.0, 1, [mitte], [])
		assert_eq(run.loot_quality, float(ArcadeTiers.get_tier(tier)["loot_quality"]), "Stufe %d" % tier)
		var entry := {"definition": tramuntana, "lap": 0}
		assert_almost_eq(run.loot_quality_of(entry), run.loot_quality * 2.0, 1e-9, "Boss-Beute × Stufe")
	assert_eq(Encounters.points_for(mitte, 6), 600, "sechsfache Punkte")


# --- Freischalten ----------------------------------------------------------------------------------------------------


func test_three_tiers_are_open_from_the_start() -> void:
	var save := SaveGame.new()
	assert_eq(ArcadeTiers.unlocked(save), 3)
	assert_eq(_tiers().map(func(t): return ArcadeTiers.is_unlocked(save, t)), [true, true, true, false, false, false])
	ArcadeTiers.choose(save, 5)
	assert_eq(ArcadeTiers.selection(save), 3, "eine gesperrte Wahl gilt als die höchste freie")
	for broken in ["vier", -2, 99, null]:
		save.arcade()["unlocked"] = broken
		assert_eq(ArcadeTiers.unlocked(save), clampi(int(broken) if broken is int else 3, 3, 6), "ungültig: %s" % [broken])


func test_completing_the_highest_open_tier_unlocks_the_next() -> void:
	var save := SaveGame.new()
	assert_eq(ArcadeTiers.bosses(), ["tramuntana", "drac", "dimonis"], "die Bosse des Rundkurses")
	# Lauf 1 auf Stufe 3: zwei Bosse besiegt, einer entkommen, dazu eine normale Herausforderung – noch nicht abgeschlossen.
	var first := _finished_run(3, [_boss_result("tramuntana"), _boss_result("drac"), _boss_result("dimonis", false),
			{"id": "zone_mitte", "name": "Zone halten", "boss": false, "succeeded": true}])
	assert_eq(ArcadeTiers.record_run(save, first), 0)
	assert_eq(ArcadeTiers.defeated(save, 3), ["tramuntana", "drac"])
	assert_false(ArcadeTiers.completed(save, 3))
	assert_eq(ArcadeTiers.unlocked(save), 3)
	# Lauf 2: der letzte fehlende Boss – über Läufe gesammelt ist Stufe 3 abgeschlossen, Stufe 4 frei.
	assert_eq(ArcadeTiers.record_run(save, _finished_run(3, [_boss_result("dimonis")])), 4)
	assert_true(ArcadeTiers.completed(save, 3))
	assert_eq(ArcadeTiers.unlocked(save), 4)
	assert_true(ArcadeTiers.is_unlocked(save, 4))
	assert_false(ArcadeTiers.is_unlocked(save, 5), "nur die nächste")
	assert_eq(ArcadeTiers.record_run(save, _finished_run(3, [_boss_result("dimonis")])), 0, "nur einmal neu")
	# Gegenprobe: Abschluss einer niedrigeren Stufe schaltet nichts über die nächste hinaus frei.
	for tier in [1, 2]:
		var all := _finished_run(tier, ArcadeTiers.bosses().map(func(id): return _boss_result(id)))
		assert_eq(ArcadeTiers.record_run(save, all), 0, "Stufe %d abgeschlossen" % tier)
		assert_true(ArcadeTiers.completed(save, tier))
	assert_eq(ArcadeTiers.unlocked(save), 4)
	# Bis zur letzten Stufe; danach gibt es nichts mehr freizuschalten.
	for tier in [4, 5]:
		var all := _finished_run(tier, ArcadeTiers.bosses().map(func(id): return _boss_result(id)))
		assert_eq(ArcadeTiers.record_run(save, all), tier + 1)
	var last := _finished_run(6, ArcadeTiers.bosses().map(func(id): return _boss_result(id)))
	assert_eq(ArcadeTiers.record_run(save, last), 0)
	assert_eq(ArcadeTiers.unlocked(save), 6)


func test_losing_to_bosses_or_winning_only_normal_challenges_unlocks_nothing() -> void:
	var save := SaveGame.new()
	var lost := _finished_run(3, ArcadeTiers.bosses().map(func(id): return _boss_result(id, false)))
	assert_eq(ArcadeTiers.record_run(save, lost), 0)
	var normal := _finished_run(3, [{"id": "tramuntana", "name": "Zone halten", "boss": false, "succeeded": true}])
	assert_eq(ArcadeTiers.record_run(save, normal), 0)
	assert_eq(ArcadeTiers.defeated(save, 3), [], "nur besiegte Bosse zählen")
	# Ein besiegter Boss auf Stufe 2 zählt nicht für Stufe 3.
	ArcadeTiers.record_run(save, _finished_run(2, [_boss_result("tramuntana")]))
	assert_eq(ArcadeTiers.defeated(save, 3), [])
	assert_eq(ArcadeTiers.defeated(save, 2), ["tramuntana"])


func test_unlocks_survive_restart_and_an_old_save_loads() -> void:
	var save := SaveGame.new()
	ArcadeTiers.record_run(save, _finished_run(3, [_boss_result("drac")]))
	ArcadeTiers.record_run(save, _finished_run(3, [_boss_result("tramuntana"), _boss_result("dimonis")]))
	ArcadeTiers.record_run(save, _finished_run(4, [_boss_result("dimonis")]))
	ArcadeTiers.choose(save, 4)
	assert_eq(save.save_file(TEMP_PATH), OK)
	var loaded := SaveGame.load_file(TEMP_PATH)
	assert_eq(loaded.version(), 1, "additiv: die Formatversion bleibt")
	assert_eq(ArcadeTiers.unlocked(loaded), 4)
	assert_eq(ArcadeTiers.selection(loaded), 4)
	assert_eq(ArcadeTiers.defeated(loaded, 3), ["tramuntana", "drac", "dimonis"])
	assert_eq(ArcadeTiers.defeated(loaded, 4), ["dimonis"])
	# Ein Stand von vor #54 (Stufe 3 gewählt, Bestpunktzahl, Beute) lädt: drei Stufen frei, nichts besiegt, Wahl bleibt.
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "active_profile": "00112233aabbccdd", "profiles": {"00112233aabbccdd": {'
			+ '"created": "2026-10-01T08:00:00Z", "rides": [], "arcade": {"tier": 3, "best_points": {"3": 900},'
			+ '"cadence_range": {"min": 70, "max": 130}, "inventory": [], "equipped": {}}}}}')
	file.close()
	var old := SaveGame.load_file(TEMP_PATH)
	assert_eq(ArcadeTiers.unlocked(old), 3)
	assert_eq(ArcadeTiers.selection(old), 3)
	assert_eq(ArcadeTiers.defeated(old, 3), [])
	assert_eq(old.best_arcade_points(3), 900)
	assert_eq(ArcadeTiers.strength(old), 0)
	# Kaputte Einträge zählen nicht.
	old.arcade()["defeated"] = {"3": "alle", "2": ["tramuntana", "unbekannt", 7]}
	assert_eq(ArcadeTiers.defeated(old, 3), [])
	assert_eq(ArcadeTiers.defeated(old, 2), ["tramuntana"])


# --- Empfohlene Stärke -----------------------------------------------------------------------------------------------


func test_strength_counts_zone_width_and_progress_of_gear_and_talents() -> void:
	assert_eq(ArcadeTiers.strength_of({}), 0)
	assert_eq(ArcadeTiers.strength_of({"zone_width_rpm": 3, "progress_pct": 7, "points_pct": 50, "luck_pct": 40}), 19,
			"4 je rpm Zonenbreite + 1 je % Fortschritt; Punkte und Glück machen lohnender, nicht stärker")
	assert_eq(ArcadeTiers.strength_of({"zone_width_rpm": 99, "progress_pct": 999}), 100, "gedeckelt wie im Lauf")
	assert_eq(ArcadeTiers.strength_of({"zone_width_rpm": -5, "progress_pct": 4}), 4, "nie negativ")
	var save := SaveGame.new()
	assert_eq(ArcadeTiers.strength(save), 0, "ohne Ausrüstung und Talente")
	var shoes := Inventory.add(save, {"id": 0, "slot": "schuhe", "rarity": Loot.MAGIC, "stats": {"zone_width_rpm": 3},
			"effect": ""})
	var wheels := Inventory.add(save, {"id": 0, "slot": "laufraeder", "rarity": Loot.RARE,
			"stats": {"progress_pct": 9, "luck_pct": 8}, "effect": ""})
	assert_eq(ArcadeTiers.strength(save), 0, "nur angelegte Teile zählen")
	Inventory.equip(save, shoes["id"])
	Inventory.equip(save, wheels["id"])
	assert_eq(ArcadeTiers.strength(save), 3 * 4 + 9)
	# Talente: Arcade-Level mit Talentpunkten, „Breiter Tritt“ (+2 rpm) und „Zäher Kletterer“ (Fortschritt).
	ArcadeLevel.add_points(save, ArcadeLevel.points_for(5))
	for id in ["ausdauer_gleichmass", "ausdauer_breit", "kletterer_zaeh"]:
		assert_true(Talents.learn(save, id), id)
	var bonus := Talents.gear_bonus(save)
	assert_gt(bonus["zone_width_rpm"], 0)
	assert_gt(bonus["progress_pct"], 0)
	assert_eq(ArcadeTiers.strength(save), (3 + bonus["zone_width_rpm"]) * 4 + 9 + bonus["progress_pct"],
			"Ausrüstung plus Talente")
	# Wie im Lauf gedeckelt (BuildEffects: Inventar + Talent ≤ Obergrenze): volle Zonenbreite schon aus der Ausrüstung.
	var helm := Inventory.add(save, {"id": 0, "slot": "helm", "rarity": Loot.LEGENDARY, "stats": {"zone_width_rpm": 9},
			"effect": ""})
	Inventory.equip(save, helm["id"])
	assert_eq(ArcadeTiers.strength(save), 10 * 4 + 9 + bonus["progress_pct"])


func test_recommended_strength_is_a_recommendation_not_a_lock() -> void:
	var recommended := _tiers().map(func(t): return ArcadeTiers.recommended_strength(t))
	assert_eq(recommended, [0, 10, 20, 35, 50, 70])
	# Ohne jede Ausrüstung ist jede freie Stufe wählbar und fährt (nur der Abschluss schaltet frei).
	var save := SaveGame.new()
	assert_eq(ArcadeTiers.strength(save), 0)
	ArcadeTiers.choose(save, 3)
	assert_eq(ArcadeTiers.selection(save), 3, "Stärke 0 < empfohlen 20: trotzdem wählbar")
	var run := ArcadeRun.new(ArcadeTiers.selection(save), CadenceRange.new(), LONG, 600.0, 0.0, 1,
			[Encounters.find("zone_mitte")], [])
	_ride(run, 90.0, 60.0)
	assert_true(run.results[0]["succeeded"], "Kadenz allein trägt die Stufe")
	# Die höchste Empfehlung ist mit voller Ausrüstung erreichbar.
	assert_gte(ArcadeTiers.strength_of({"zone_width_rpm": 10, "progress_pct": 60}), recommended.max())


# --- Rundensteigerung ------------------------------------------------------------------------------------------------


func _ride(run: ArcadeRun, cadence: float, seconds: float, from_m: float = 0.0, speed_mps: float = 8.0) -> float:
	var d := from_m
	for i in range(roundi(seconds / DT)):
		d += speed_mps * DT
		run.advance(d, cadence, DT)
	return d


func test_each_round_is_a_bit_harder_and_more_rewarding() -> void:
	var levels := range(8).map(func(r): return ArcadeTiers.level(1, r))
	assert_eq(levels.map(func(l): return l["zone_width_rpm"]), [20.0, 19.0, 18.0, 17.0, 17.0, 17.0, 17.0, 17.0],
			"je Runde 1 rpm schmaler, höchstens 3")
	var durations: Array = levels.map(func(l): return roundi(l["duration_factor"] * 100.0))
	assert_eq(durations, [100, 104, 108, 112, 116, 120, 120, 120], "je Runde 4 % länger, höchstens 20 %")
	var points: Array = levels.map(func(l): return roundi(l["points_factor"] * 100.0))
	assert_eq(points, [100, 110, 120, 130, 140, 150, 160, 170], "je Runde 10 % mehr Punkte")
	var loot := range(13).map(func(r): return roundi(ArcadeTiers.level(1, r)["loot_quality"] * 100.0))
	assert_eq(loot.slice(0, 3), [100, 105, 110], "je Runde bessere Beute")
	assert_eq(loot[12], 150, "höchstens + 50 %")
	assert_eq(ArcadeTiers.level(6, 20)["zone_width_rpm"], 6.0, "nie schmaler als 6 rpm")
	for key in ["zone_width_rpm", "duration_factor", "points_factor", "loot_quality"]:
		assert_eq(float(ArcadeTiers.level(4, 0)[key]), float(ArcadeTiers.get_tier(4)[key]), "Runde 1 = die Stufe: " + key)
	# Am Baustein: dieselbe Herausforderung in Runde 3 enger, länger, mehr Punkte, bessere Beute.
	var mitte := Encounters.find("zone_mitte")
	var personal := CadenceRange.new()
	var first := Encounters.build(mitte, 2, personal) as ZoneHold
	var third := Encounters.build(mitte, 2, personal, {}, 2) as ZoneHold
	assert_eq(Vector2(first.zone_min, first.zone_max), Vector2(83.0, 97.0))
	assert_eq(Vector2(third.zone_min, third.zone_max), Vector2(84.0, 96.0), "2 rpm schmaler")
	assert_almost_eq(third.hold_s, first.hold_s * 1.08, 1e-6)
	assert_eq([Encounters.points_for(mitte, 2), Encounters.points_for(mitte, 2, 2)], [200, 240])
	# Schwelle: der Hub wächst mit der schmaleren Zone (Zugbrücke 108 → 109 → 110 rpm auf Stufe 1).
	var bridge := Encounters.find("durchbruch_bruecke")
	assert_eq([0, 1, 2, 3].map(func(r): return Encounters.zone_for(bridge, 1, personal, {}, 0.0, r).x),
			[108.0, 109.0, 109.0, 110.0], "Hub auf ganze rpm gerundet")


func test_the_run_escalates_per_round_but_rolls_the_same() -> void:
	var mitte := Encounters.find("zone_mitte")
	var run := ArcadeRun.new(1, CadenceRange.new(), LONG, 600.0, 0.0, 3, [mitte], [])
	var d := 0.0
	var zones := {}
	while d < 600.0 * 3.0 - 10.0:
		d = _ride(run, 90.0, DT, d)
		if not run.active.is_empty():
			var block: ZoneHold = run.active["block"]
			zones[run.active["lap"]] = block.zone_max - block.zone_min
	assert_eq(zones.keys(), [0, 1, 2], "in jeder Runde gespielt")
	assert_eq(zones.values(), [20.0, 19.0, 18.0], "die Zone der zweiten Runde ist enger")
	var by_lap := {}
	for result in run.results:
		assert_true(result["succeeded"], "90 rpm trifft jede Runde")
		by_lap[result["lap"]] = result["points"]
	assert_eq(by_lap, {0: 100, 1: 110, 2: 120}, "und lohnender")
	assert_eq(run.lap_index_at(0.0), 0)
	assert_eq(run.lap_index_at(1250.0), 2)
	# Ein Lauf, der in Runde 5 des Rundkurses beginnt, beginnt trotzdem mit der ersten Runde im Lauf.
	var late := ArcadeRun.new(1, CadenceRange.new(), LONG, 600.0, 3000.0, 3, [mitte], [])
	assert_eq(late.lap_index_of(late.next_challenge()), 0)
	assert_eq(late.zone_of(late.next_challenge()), Vector2(80.0, 100.0))
	# Würfe: Auswahl, Lage, Elite-Gruppen bei gleichem Seed gleich – auf jeder Stufe, mit jeder Runde (nur Parameter).
	# (Der Lauf plant beim Start die erste und die zweite Runde: beide Runden im Vergleich.)
	var six := range(6).map(func(k): return {"name": "A%d" % k, "start_m": k * 100.0, "end_m": (k + 1) * 100.0})
	var plans := []
	for tier in _tiers():
		var standard := ArcadeRun.new(tier, CadenceRange.new(), six, 600.0, 0.0, 7, Encounters.CHALLENGES, [], 0.5)
		plans.append(standard.planned.map(func(e): return [e["definition"]["id"], e["at_m"], e["lap"]]))
	for i in range(1, plans.size()):
		assert_eq(plans[i], plans[0], "Stufe %d würfelt wie Stufe 1" % (i + 1))
	assert_gt(plans[0].size(), 12)
	assert_true(plans[0].any(func(p): return p[1] >= 600.0), "auch die zweite Runde")
	assert_true(plans[0].any(func(p): return str(p[0]).begins_with("champion_") or str(p[0]).begins_with("selten_")),
			"mit Elite-Gruppen")


func test_later_rounds_drop_better_loot() -> void:
	var run := _finished_run(2, [])
	var mitte := Encounters.find("zone_mitte")
	var qualities := [0, 1, 4, 10, 40].map(func(r): return run.loot_quality_of({"definition": mitte, "lap": r}))
	assert_almost_eq(qualities[0], 1.25, 1e-9, "Stufe 2")
	for i in range(1, qualities.size()):
		assert_gte(qualities[i], qualities[i - 1])
	assert_almost_eq(qualities[-1], 1.25 * 1.5, 1e-9, "gedeckelt")
	# Bessere Beute heißt öfter seltene Teile: über viele Würfe mehr Rang mit höherer Qualität (gleiche Würfel).
	var ranks := []
	for quality in [qualities[0], qualities[-1]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var sum := 0
		for i in range(400):
			sum += Loot.RARITIES.keys().find(Loot.roll_rarity(rng, quality))
		ranks.append(sum)
	assert_gt(ranks[1], ranks[0])


# --- Wächter: Kadenzbereich auf jeder Stufe, in jeder Runde ----------------------------------------------------------


## Alle Definitionen, die ein Lauf bauen kann: gewürfelte Herausforderungen, Bosse und je Typ eine Elite-Gruppe mit allen
## Eigenschaften (darunter die wandernde Zone) als Champions und als Seltene.
func _all_definitions() -> Array:
	var result: Array = Encounters.CHALLENGES.duplicate()
	result.append_array(BOSSES.FIXED)
	for definition in Encounters.CHALLENGES:
		for rank in EliteGroups.RANKS:
			result.append(EliteGroups.make(definition, rank, EliteGroups.affixes_for(definition["block"])))
	return result


## Prüft jede Zone, nach der der Baustein von `definition` wertet (alle Phasen, die wandernde in mehreren Augenblicken),
## und die Ankündigung; liefert die Zahl der geprüften Zonen.
func _check_zones(definition: Dictionary, tier: int, range_: CadenceRange, lap: int, gear: Dictionary) -> int:
	var label := "%s Stufe %d Runde %d %s %s" % [definition["id"], tier, lap + 1, range_.text(), gear]
	var block := Encounters.build(definition, tier, range_, gear, lap)
	var zones := [Encounters.zone_for(definition, tier, range_, gear, 0.0, lap)]
	if block is BossFight:
		for i in range(block.phases.size()):
			zones.append(block.phases[i].zone())
			if block is EliteGroup and block.definitions[i].has("wander"):
				var period: float = block.definitions[i]["wander"]["period_s"]
				for k in range(4):
					zones.append(block.zone_path.call(i, (2 * k + 1) * period / 8.0))
	else:
		zones.append(block.zone())
	for zone in zones:
		if not range_.contains_zone(zone.x, zone.y):
			_outside.append("%s → %s" % [label, zone])
	return zones.size()


func test_no_zone_leaves_the_personal_range_on_any_tier_in_any_round() -> void:
	# Positivprobe: alle Stufen × Runden 1–21 × alle wählbaren Bereiche × jeder Bausteintyp, Boss-Phasen, Elite-Gruppen
	# (auch wandernd), mit und ohne volle Zonenbreite der Ausrüstung.
	var definitions := _all_definitions()
	var checked := 0
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for tier in _tiers():
				for lap in range(21):
					for definition in definitions:
						checked += _check_zones(definition, tier, range_, lap, {})
	# Die Ausrüstungsbreite in den äußersten Lagen (engster und weitester Bereich, letzte Stufe, späte Runde).
	for range_ in [CadenceRange.new(80.0, 100.0), CadenceRange.new(40.0, 150.0)]:
		for definition in definitions:
			checked += _check_zones(definition, 6, range_, 20, {"zone_width_rpm": 10})
	assert_gt(checked, 1000000, "geprüfte Zonen")
	assert_eq(_outside.size(), 0, "außerhalb des Bereichs: %s" % [_outside.slice(0, 5)])


func test_the_guard_catches_what_tier_and_round_would_push_out() -> void:
	# Gegenprobe: ohne Wächter lägen die Ziele späterer Runden höherer Stufen außerhalb des Bereichs.
	var personal := CadenceRange.new()
	var spurt := Encounters.find("durchbruch_spurt").duplicate()
	spurt["threshold_at"] = 0.9  # Schwelle bei 90 % = 114 rpm (der Pool hat seit #55 85 %; die Gegenprobe braucht eine, die ohne Wächter überschießt)
	var level := ArcadeTiers.level(6, 3)
	var lift := roundf((20.0 - float(level["zone_width_rpm"])) / 2.0)
	assert_gt(roundf(personal.at(0.9)) + lift, 120.0, "ohne Wächter über dem Bereich")
	assert_eq(Encounters.zone_for(spurt, 6, personal, {}, 0.0, 3), Vector2(120.0, 120.0), "Schwelle am oberen Ende")
	var block := Encounters.build(spurt, 6, personal, {}, 3) as Breakthrough
	assert_eq(block.threshold_rpm, 120.0, "der Baustein bekommt dieselbe, nie darüber")
	# Eine Zone am Rand (Lage 1,0 → Mitte 120 rpm): halb hinaus, mit gleicher Breite hineingeschoben.
	var edge := {"id": "rand", "block": Encounters.ZONE_HOLD, "name": "Rand", "zone_at": 1.0, "hold_s": 5.0,
			"window_s": 10.0, "points": 10}
	var zone := Encounters.zone_for(edge, 6, personal, {}, 0.0, 5)
	assert_eq(zone, Vector2(114.0, 120.0), "6 rpm breit, im Bereich")
	# Die Runde erreicht auch die Phasen eines Bosses und die wandernde Zone einer Elite-Gruppe (rekursiv durchgereicht).
	var boss := Encounters.build(BOSSES.find("drac"), 3, personal, {}, 2) as BossFight
	var ansturm := boss.phases[3] as Breakthrough
	assert_eq(ansturm.threshold_rpm, minf(111.0 + 6.0, 120.0), "Letzter Ansturm: Hub der Runde 3 auf Stufe 3")
	var hold := boss.phases[0] as ZoneHold
	assert_eq(hold.zone_max - hold.zone_min, 8.0, "Feueratem 10 − 2 rpm")
	var group := Encounters.build(EliteGroups.make(Encounters.find("zone_zuegig"), "champion",
			["wankelmuetig", "gegenwind"]), 1, personal, {}, 3) as EliteGroup
	var quarter: float = EliteGroups.WANDER["period_s"] / 4.0
	var leader: Dictionary = group.definitions[0]
	var center := roundf(personal.at(float(leader["zone_at"]) + Encounters.wander_shift(leader, quarter)))
	assert_gt(center + 17.0 / 2.0, 120.0, "ohne Wächter über dem Bereich")
	assert_eq(group.zone_path.call(0, quarter), Vector2(103.0, 120.0), "wandernd, Runde 4 (17 rpm): hineingeschoben")
