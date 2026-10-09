## Beute und Ausrüstung als reine Logik (#49): Beute-Würfel (Platz, Seltenheitsverteilung mit Seed und Qualität, Werte
## je Seltenheit, Platz für den legendären Effekt), Inventar im Spielstand (anlegen, vergleichen, verwerten, alter Stand
## lädt) und die Ausrüstung im Arcade-Lauf: Werte wirken nur mit Kadenz in der Zone (Positiv- und Gegenprobe), eine
## verbreiterte Zone bleibt im Kadenzbereich (Wächter), Beute nach geschafft/verfehlt.
extends GutTest

const DT := 0.1
var SAVE_PATH := TestIsolation.path("test_loot_savegame.json")


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _item(slot: String, rarity: String, stats: Dictionary) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": ""}


func _hold(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


# --- Beute-Würfel --------------------------------------------------------------------------------------------------


func test_six_slots_and_four_rarities_in_diablo_colours() -> void:
	assert_eq(Loot.SLOTS.keys(), ["rahmen", "laufraeder", "trikot", "helm", "schuhe", "talisman"])
	assert_eq(Loot.SLOTS.values().map(func(s): return s["name"]),
			["Rahmen", "Laufräder", "Trikot", "Helm", "Schuhe", "Talisman"])
	assert_eq(Loot.RARITIES.keys(), [Loot.COMMON, Loot.MAGIC, Loot.RARE, Loot.LEGENDARY])
	var common := Loot.color_of(Loot.COMMON)
	assert_almost_eq(common.s, 0.0, 0.05, "gewöhnlich: weiß/grau")
	assert_gt(common.v, 0.7)
	assert_almost_eq(Loot.color_of(Loot.MAGIC).h * 360.0, 225.0, 15.0, "magisch: blau")
	assert_almost_eq(Loot.color_of(Loot.RARE).h * 360.0, 50.0, 10.0, "selten: gelb")
	assert_almost_eq(Loot.color_of(Loot.LEGENDARY).h * 360.0, 30.0, 8.0, "legendär: orange")


func test_roll_is_reproducible_with_a_seed() -> void:
	var a := []
	var b := []
	var rng_a := _rng(42)
	var rng_b := _rng(42)
	for i in range(50):
		a.append(Loot.roll(rng_a))
		b.append(Loot.roll(rng_b))
	assert_eq(a, b, "gleicher Seed → gleiche Beute")
	assert_ne(Loot.roll(_rng(1)), Loot.roll(_rng(2)), "anderer Seed → andere Beute")


func test_rarity_distribution_with_seed_and_quality() -> void:
	var counts := {}
	var slots := {}
	var rng := _rng(7)
	var n := 20000
	for i in range(n):
		var item := Loot.roll(rng)
		counts[item["rarity"]] = counts.get(item["rarity"], 0) + 1
		slots[item["slot"]] = slots.get(item["slot"], 0) + 1
	var total := 0.0
	for rarity in Loot.RARITIES:
		total += Loot.RARITIES[rarity]["weight"]
	for rarity in Loot.RARITIES:
		assert_almost_eq(float(counts.get(rarity, 0)) / n, Loot.RARITIES[rarity]["weight"] / total, 0.015,
				"Anteil %s nach Gewicht" % rarity)
	assert_gt(counts[Loot.COMMON], counts[Loot.MAGIC])
	assert_gt(counts[Loot.MAGIC], counts[Loot.RARE])
	assert_gt(counts[Loot.RARE], counts[Loot.LEGENDARY], "legendär am seltensten")
	assert_gt(counts[Loot.LEGENDARY], 0, "aber es kommt vor")
	for slot in Loot.SLOTS:
		assert_almost_eq(float(slots[slot]) / n, 1.0 / 6.0, 0.015, "Platz %s gleichverteilt" % slot)
	# Qualität (später Stufe, Elite-Gruppe; hier Beute-Glück) hebt die Seltenheit.
	var lucky := {}
	rng = _rng(7)
	for i in range(n):
		var rarity := Loot.roll_rarity(rng, 2.0)
		lucky[rarity] = lucky.get(rarity, 0) + 1
	assert_gt(lucky[Loot.LEGENDARY], counts[Loot.LEGENDARY] * 3, "Qualität 2: viel mehr Legendäres")
	assert_lt(lucky[Loot.COMMON], counts[Loot.COMMON], "weniger Gewöhnliches")
	assert_eq(Loot.rarity_weights(1.0).values(), Loot.RARITIES.values().map(func(r): return r["weight"]),
			"Qualität 1: Grundgewichte")


func test_values_per_rarity_and_slot() -> void:
	var rng := _rng(3)
	var best := {}
	for i in range(4000):
		var item := Loot.roll(rng)
		var level: Dictionary = Loot.RARITIES[item["rarity"]]
		assert_eq(item["stats"].size(), level["stats"], "%s: Zahl der Werte nach Seltenheit" % item["rarity"])
		assert_true(item["stats"].has(Loot.SLOTS[item["slot"]]["stat"]), "Hauptwert des Platzes %s" % item["slot"])
		assert_eq(item["effect"] != "", item["rarity"] == Loot.LEGENDARY, "den Effekt (#53) bekommen nur legendäre Teile")
		assert_true(item["effect"] == "" or Loot.EFFECTS.has(item["effect"]), "ein Effekt aus den Daten")
		assert_true(Loot.valid(item))
		for stat in item["stats"]:
			var info: Dictionary = Loot.STATS[stat]
			var value: int = item["stats"][stat]
			assert_between(value, maxi(roundi(info["min"] * level["factor"]), 1), roundi(info["max"] * level["factor"]),
					"%s %s im Bereich" % [item["rarity"], stat])
			var key := "%s %s" % [item["rarity"], stat]
			best[key] = maxi(best.get(key, 0), value)
	for stat in Loot.STATS:
		assert_gt(best["%s %s" % [Loot.LEGENDARY, stat]], best["%s %s" % [Loot.COMMON, stat]],
				"legendär stärker als gewöhnlich (%s)" % stat)


func test_names_and_texts() -> void:
	assert_eq(Loot.item_name(_item("helm", Loot.MAGIC, {})), "Magischer Helm")
	assert_eq(Loot.item_name(_item("laufraeder", Loot.RARE, {})), "Seltene Laufräder")
	assert_eq(Loot.item_name(_item("trikot", Loot.LEGENDARY, {})), "Legendäres Trikot")
	assert_eq(Loot.item_name(_item("schuhe", Loot.COMMON, {})), "Gewöhnliche Schuhe")
	assert_eq(Loot.item_name(_item("talisman", Loot.LEGENDARY, {})), "Legendärer Talisman")
	assert_eq(Loot.stats_text(_item("helm", Loot.MAGIC, {"points_pct": 8, "zone_width_rpm": 3})),
			"+3 rpm Zonenbreite · +8 % Punkte")


func test_drop_chance_success_sure_failure_by_progress() -> void:
	assert_eq(Loot.drop_chance(true, 1.0), 1.0, "geschafft: sicher Beute")
	assert_eq(Loot.drop_chance(false, 0.0), 0.0, "ohne Fortschritt (keine Kadenz in der Zone): nie")
	assert_almost_eq(Loot.drop_chance(false, 0.5), 0.25, 0.001, "knapp verfehlt: weniger")
	assert_lt(Loot.drop_chance(false, 0.99), Loot.drop_chance(true, 1.0))


func test_modifiers_sum_and_are_capped() -> void:
	var items := [_item("helm", Loot.RARE, {"zone_width_rpm": 4, "points_pct": 10}),
			_item("schuhe", Loot.MAGIC, {"zone_width_rpm": 3}), {"slot": "kaputt"}]
	assert_eq(Loot.modifiers(items), {"zone_width_rpm": 7, "progress_pct": 0, "points_pct": 10, "luck_pct": 0},
			"Summe; ungültige zählen nicht")
	assert_eq(Loot.modifiers([]), {"zone_width_rpm": 0, "progress_pct": 0, "points_pct": 0, "luck_pct": 0})
	var many := []
	for i in range(6):
		many.append(_item("helm", Loot.LEGENDARY, {"zone_width_rpm": 6, "progress_pct": 18}))
	var capped := Loot.modifiers(many)
	assert_eq(capped["zone_width_rpm"], Loot.STATS["zone_width_rpm"]["cap"], "Obergrenze Zonenbreite")
	assert_eq(capped["progress_pct"], Loot.STATS["progress_pct"]["cap"], "Obergrenze Fortschritt")


func test_compare_candidate_with_equipped() -> void:
	var candidate := _item("helm", Loot.RARE, {"zone_width_rpm": 4, "luck_pct": 12})
	var worn := _item("helm", Loot.MAGIC, {"zone_width_rpm": 5, "points_pct": 6})
	assert_eq(Loot.compare(candidate, worn), [
		{"stat": "zone_width_rpm", "candidate": 4, "current": 5, "delta": -1},
		{"stat": "points_pct", "candidate": 0, "current": 6, "delta": -6},
		{"stat": "luck_pct", "candidate": 12, "current": 0, "delta": 12},
	])
	assert_eq(Loot.compare(candidate, {}).map(func(r): return r["delta"]), [4, 12], "nichts angelegt: alles besser")


# --- Inventar und Spielstand ---------------------------------------------------------------------------------------


func test_inventory_add_equip_compare_and_salvage() -> void:
	var save := SaveGame.new()
	assert_eq(Inventory.items(save), [], "neuer Stand: leer")
	assert_eq(Inventory.shards(save), 0)
	var old := Inventory.add(save, _item("helm", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 6}))
	var new := Inventory.add(save, _item("helm", Loot.RARE, {"zone_width_rpm": 5, "points_pct": 4, "luck_pct": 9}))
	var boots := Inventory.add(save, _item("schuhe", Loot.COMMON, {"zone_width_rpm": 2}))
	assert_eq([old["id"], new["id"], boots["id"]], [1, 2, 3], "eigene ids")
	assert_true(Inventory.equip(save, old["id"]))
	assert_true(Inventory.equip(save, boots["id"]))
	assert_false(Inventory.equip(save, 99), "unbekannt")
	assert_eq(Inventory.equipped(save).keys(), ["helm", "schuhe"])
	assert_eq(Inventory.modifiers(save)["zone_width_rpm"], 5)
	assert_eq(Inventory.compare(save, new["id"]).map(func(r): return r["delta"]), [2, -2, 9],
			"Kandidat gegen den angelegten Helm")
	assert_true(Inventory.equip(save, new["id"]), "anlegen ersetzt den Helm")
	assert_eq(Inventory.equipped(save)["helm"]["id"], new["id"])
	assert_eq(Inventory.items(save).size(), 3, "der alte bleibt im Inventar")
	assert_eq(Inventory.salvage(save, new["id"]), 0, "angelegt: nicht verwertbar")
	assert_eq(Inventory.salvage(save, old["id"]), Loot.RARITIES[Loot.MAGIC]["shards"], "überzählig: zu Splittern")
	assert_eq(Inventory.shards(save), 3)
	assert_eq(Inventory.items(save).map(func(i): return i["id"]), [new["id"], boots["id"]])
	assert_eq(Inventory.salvage(save, old["id"]), 0, "schon verwertet")
	assert_eq(Inventory.add(save, _item("rahmen", Loot.COMMON, {"progress_pct": 3}))["id"], 4, "ids nie doppelt")


func test_inventory_survives_save_and_load_additively() -> void:
	var save := SaveGame.new()
	ArcadeTiers.choose(save, 2)
	var helm := Inventory.add(save, _item("helm", Loot.LEGENDARY, {"zone_width_rpm": 6, "progress_pct": 12,
			"points_pct": 20, "luck_pct": 25}))
	Inventory.equip(save, helm["id"])
	Inventory.add(save, _item("talisman", Loot.COMMON, {"luck_pct": 7}))
	assert_eq(Inventory.salvage(save, 2), 1)
	assert_eq(save.save_file(SAVE_PATH), OK)
	var loaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(loaded.version(), 1, "Formatversion bleibt")
	assert_eq(ArcadeTiers.selection(loaded), 2, "Arcade-Stand von #46 bleibt")
	assert_eq(Inventory.items(loaded).size(), 1)
	assert_eq(Inventory.equipped(loaded)["helm"]["stats"]["progress_pct"], 12.0)
	assert_eq(Inventory.modifiers(loaded), {"zone_width_rpm": 6, "progress_pct": 12, "points_pct": 20, "luck_pct": 25})
	assert_eq(Inventory.shards(loaded), 1)
	assert_eq(Inventory.add(loaded, _item("rahmen", Loot.COMMON, {"progress_pct": 3}))["id"], 3, "nach dem Laden weiter")


func test_old_save_without_gear_loads() -> void:
	# Stand von #46: Bereich `arcade` ohne Inventar, Splitter, Angelegtes.
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "active_profile": "0123456789abcdef", "profiles": {
			"0123456789abcdef": {"created": "2026-10-01T10:00:00Z", "rides": [],
				"arcade": {"tier": 3, "cadence_range": {"min": 70, "max": 130}, "best_points": {"3": 900}}}}}))
	file.close()
	var save := SaveGame.load_file(SAVE_PATH)
	assert_eq(save.version(), 1)
	assert_eq(save.best_arcade_points(3), 900, "Arcade-Stand bleibt")
	assert_eq(Inventory.items(save), [])
	assert_eq(Inventory.equipped(save), {})
	assert_eq(Inventory.shards(save), 0)
	assert_eq(Inventory.modifiers(save), Loot.modifiers([]))
	assert_eq(Inventory.add(save, _item("helm", Loot.COMMON, {"zone_width_rpm": 1}))["id"], 1, "Inventar entsteht")


func test_broken_entries_on_disk_do_not_count() -> void:
	var save := SaveGame.new()
	save.arcade()["inventory"] = [{"id": 1, "slot": "helm", "rarity": "selten", "stats": {"zone_width_rpm": 3}},
			{"id": 2, "slot": "fluegel", "rarity": "selten", "stats": {}},
			{"id": 3, "slot": "helm", "rarity": "selten", "stats": {"unbekannt": 99}}, "Müll",
			{"slot": "helm", "rarity": "magisch", "stats": {}}]
	save.arcade()["equipped"] = {"helm": 3, "schuhe": 1, "rahmen": "x"}
	save.arcade()["shards"] = "viele"
	assert_eq(Inventory.items(save).map(func(i): return i["id"]), [1], "nur gültige Teile mit id")
	assert_eq(Inventory.equipped(save), {}, "Verweis auf ungültiges Teil oder falschen Platz zählt nicht")
	assert_eq(Inventory.shards(save), 0)


# --- Ausrüstung wirkt nur mit Kadenz in der Zone -------------------------------------------------------------------


func test_gear_speeds_up_progress_only_in_the_zone() -> void:
	var definition := Encounters.find("zone_mitte")
	var gear := Loot.modifiers([_item("rahmen", Loot.LEGENDARY, {"progress_pct": 50})])
	var plain := Encounters.build(definition, 1, CadenceRange.new())
	var geared := Encounters.build(definition, 1, CadenceRange.new(), gear)
	assert_eq(geared.progress_factor, 1.5)
	assert_eq(geared.zone(), plain.zone(), "Fortschritt ändert die Zone nicht")
	# Positivprobe: in der Zone schneller.
	_hold(plain, 90.0, 5.0)
	_hold(geared, 90.0, 5.0)
	assert_almost_eq(plain.progress(), 5.0 / 15.0, 0.001)
	assert_almost_eq(geared.progress(), 7.5 / 15.0, 0.001, "× 1,5 in der Zone")
	_hold(geared, 90.0, 5.0)
	assert_eq(geared.state, ChallengeBlock.SUCCEEDED, "nach 10 statt 15 s geschafft")
	assert_almost_eq(geared.elapsed_s, 10.0, 0.001)
	# Gegenprobe: außerhalb der Zone null Fortschritt – gleich wie ohne Ausrüstung, auch ohne Treten.
	for cadence in [0.0, 60.0, 110.0]:
		var without := Encounters.build(definition, 1, CadenceRange.new())
		var with := Encounters.build(definition, 1, CadenceRange.new(), gear)
		_hold(without, cadence, 40.0)
		_hold(with, cadence, 40.0)
		assert_eq(with.progress(), 0.0, "%d rpm außerhalb: kein Fortschritt trotz Ausrüstung" % cadence)
		assert_eq([with.state, with.elapsed_s], [without.state, without.elapsed_s], "%d rpm: wie ohne" % cadence)
		assert_eq(with.state, ChallengeBlock.FAILED)


func test_wider_zone_is_more_forgiving_but_still_needs_the_zone() -> void:
	var definition := Encounters.find("zone_mitte")
	var gear := Loot.modifiers([_item("helm", Loot.RARE, {"zone_width_rpm": 6})])
	assert_eq(Encounters.zone_for(definition, 1, CadenceRange.new()), Vector2(80.0, 100.0))
	assert_eq(Encounters.zone_for(definition, 1, CadenceRange.new(), gear), Vector2(77.0, 103.0), "+6 rpm breiter")
	var block := Encounters.build(definition, 1, CadenceRange.new(), gear)
	_hold(block, 102.0, 15.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "102 rpm liegt jetzt in der Zone")
	var outside := Encounters.build(definition, 1, CadenceRange.new(), gear)
	_hold(outside, 104.0, 40.0)
	assert_eq(outside.progress(), 0.0, "104 rpm bleibt außerhalb: nichts")


func test_widened_zone_stays_inside_the_cadence_range() -> void:
	# Wächter: auch eine durch Ausrüstung verbreiterte Zone läuft durch CadenceRange.limit_zone.
	var personal := CadenceRange.new(60.0, 120.0)
	var huge := {"zone_width_rpm": 500}
	assert_eq(Encounters.zone_for(Encounters.find("zone_mitte"), 1, personal, huge), Vector2(60.0, 120.0),
			"breiter als der Bereich: der ganze Bereich, nicht mehr")
	var edge := {"id": "rand", "block": Encounters.ZONE_HOLD, "name": "Rand", "zone_rpm": [110.0, 120.0],
			"hold_s": 5.0, "window_s": 10.0, "points": 1}
	assert_eq(Encounters.zone_for(edge, 1, personal, {"zone_width_rpm": 10}), Vector2(100.0, 120.0),
			"am Rand: rückt mit voller Breite hinein")
	var cap := {"zone_width_rpm": Loot.STATS["zone_width_rpm"]["cap"]}
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for definition in Encounters.CHALLENGES:
				for tier in [1, 2, 3]:
					var zone := (Encounters.build(definition, tier, range_, cap) as ChallengeBlock).zone()
					assert_true(range_.contains_zone(zone.x, zone.y), "%s Stufe %d in %s" % [definition["id"], tier,
							range_.text()])


# --- Arcade-Lauf: Beute und Ausrüstung -----------------------------------------------------------------------------


func _run(seed_value: int, gear: Dictionary = {}) -> ArcadeRun:
	var run := ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0, 0.0,
			seed_value, [Encounters.find("zone_mitte")])
	run.gear = gear
	return run


func _ride(run: ArcadeRun, cadence: float, seconds: float, from_m: float = 0.0, speed_mps: float = 8.0) -> float:
	var d := from_m
	for i in range(roundi(seconds / DT)):
		d += speed_mps * DT
		run.advance(d, cadence, DT)
	return d


func test_loot_drops_after_a_won_challenge_and_shows_in_the_summary() -> void:
	var run := _run(2)
	_ride(run, 90.0, 6.4 + 15.2)
	assert_eq(run.results.size(), 1)
	assert_true(run.results[0]["succeeded"])
	var loot: Dictionary = run.results[0]["loot"]
	assert_true(Loot.valid(loot), "geschafft: Beute")
	assert_eq(run.found, [loot])
	assert_eq(run.summary_lines()[-1], "Beute: " + Loot.item_name(loot), "Fund in der Zusammenfassung")
	var again := _run(2)
	_ride(again, 90.0, 6.4 + 15.2)
	assert_eq(again.found, run.found, "gleicher Seed → gleiche Beute")


func test_no_loot_without_cadence_in_the_zone_and_less_when_just_missed() -> void:
	var run := _run(2)
	_ride(run, 103.0, 6.4 + 30.2)
	assert_false(run.results[0]["succeeded"])
	assert_eq(run.results[0]["loot"], {}, "Fortschritt 0: keine Beute")
	assert_eq(run.found, [])
	assert_eq(run.summary_lines().size(), 3, "keine Beute-Zeile")
	# Knapp verfehlt (halber Fortschritt): Beute nur mit Chance – über viele Läufe seltener als nach Erfolg.
	var drops := 0
	for seed_value in range(200):
		var partial := _run(seed_value)
		var d := _ride(partial, 90.0, 6.4 + 7.5)
		_ride(partial, 0.0, 25.0, d)
		assert_false(partial.results[0]["succeeded"])
		drops += partial.found.size()
	assert_between(drops, 25, 75, "etwa jede vierte (0,5 × Fortschritt 0,5)")


func test_gear_in_the_run_points_zone_and_counterproof() -> void:
	var gear := Loot.modifiers([_item("trikot", Loot.RARE, {"points_pct": 20}),
			_item("helm", Loot.RARE, {"zone_width_rpm": 6})])
	var run := _run(2, gear)
	_ride(run, 102.0, 6.4 + 15.2)  # ohne Ausrüstung knapp daneben (80–100), mit ihr in der Zone (77–103)
	assert_true(run.results[0]["succeeded"], "nachsichtiger: breitere Zone")
	assert_eq(run.results[0]["points"], 120, "lohnender: +20 % Punkte")
	# Die nächste liegt in Runde 2 des Laufs: Rundensteigerung (#54) 1 rpm schmaler, 90 ± (19 + 6) / 2.
	var next := run.next_challenge()
	assert_eq(run.lap_index_of(next), 1)
	assert_eq(run.zone_of(next), Vector2(77.5, 102.5), "Anzeige zeigt dieselbe Zone wie der Baustein")
	assert_eq(run.zone_of(next), Encounters.build(next["definition"], 1, run.cadence_range, gear, 1).zone())
	# Gegenprobe: außerhalb der (breiteren) Zone nichts – keine Punkte, kein Fortschritt, keine Beute; wie ohne.
	var outside := _run(2, gear)
	var plain := _run(2)
	_ride(outside, 110.0, 6.4 + 30.2)
	_ride(plain, 110.0, 6.4 + 30.2)
	for r in [outside, plain]:
		assert_false(r.results[0]["succeeded"])
		assert_eq(r.results[0]["progress"], 0.0)
		assert_eq(r.points, 0)
		assert_eq(r.found, [])
	assert_eq(outside.planned.map(func(e): return e["at_m"]), plain.planned.map(func(e): return e["at_m"]),
			"Ausrüstung und Beute ändern die Planung nicht")
