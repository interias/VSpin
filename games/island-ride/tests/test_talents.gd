## Talente, Arcade-Level und legendäre Effekte (#53): reine Logik. Das Arcade-Level wächst mit den Punkten der Läufe und
## liefert Talentpunkte; der Baum (15 Knoten, drei Äste) hat Voraussetzungen, Verteilen, kostenloses Zurücksetzen und
## bleibt im Spielstand (alte Stände laden). **Talente und Effekte verändern Fähigkeiten**: Wert in `defs` vorher/nachher
## und die Wirkung im Baustein. Gegenproben: ohne Kadenz kein Fortschritt, die Zielzone bleibt im Kadenzbereich (Wächter),
## der Würfel vergibt den Effekt nur bei legendär, ältere legendäre Teile ohne Effekt bleiben gültig.
extends GutTest

const DT := 0.1
const ZONE := {"id": "t_zone", "block": "zone_hold", "name": "Zone halten", "zone_rpm": [80, 100], "hold_s": 20.0,
		"window_s": 60.0, "points": 100}
const BREAK := {"id": "t_break", "block": "breakthrough", "name": "Durchbruch", "threshold_at": 0.5, "fill_s": 10.0,
		"window_s": 60.0, "decay": 1.0, "points": 100}
const CHASE := {"id": "t_chase", "block": "chase", "name": "Jagd", "threshold_at": 0.5, "escape_s": 20.0,
		"catch_s": 20.0, "window_s": 120.0, "start_gap": 0.5, "points": 100}
var SAVE_PATH := TestIsolation.path("test_talents_savegame.json")

## Eine Herausforderung, die nicht in wenigen Sekunden endet.
const LONG_ZONE := {"id": "t_long", "block": "zone_hold", "name": "Zone halten", "zone_rpm": [80, 100], "hold_s": 400.0,
		"window_s": 600.0, "points": 100}

var _meters := 100.0


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Spielstand auf Arcade-Level `level` (Punkte genau am Beginn des Levels).
func _save_at(level: int) -> SaveGame:
	var save := SaveGame.new()
	ArcadeLevel.add_points(save, ArcadeLevel.points_for(level))
	return save


func _item(slot: String, rarity: String, effect: String = "", stats: Dictionary = {"luck_pct": 5}) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


func _wear(save: SaveGame, item: Dictionary) -> void:
	Inventory.equip(save, Inventory.add(save, item)["id"])


## Lauf mit einer Herausforderung, schon begonnen, dazu Fähigkeiten und Muster; `changes` angewendet (wie der Hook der Bühne).
func _start(definition: Dictionary, changes: Array = [], gear: Dictionary = {}) -> Dictionary:
	_meters = 100.0
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000000.0, 0.0, 1, [definition])
	run.gear = gear
	var env := {"run": run, "abilities": Abilities.new(), "patterns": CadencePatterns.new()}
	env["applied"] = BuildEffects.apply(changes, run, env["abilities"], env["patterns"])
	run.advance(_meters, 70.0, DT)
	assert_false(run.active.is_empty(), "die Herausforderung läuft")
	env["abilities"].step(run, [], DT)
	return env


func _step(env: Dictionary, cadence: float, patterns: Array = []) -> Array:
	_meters += 1.0
	env["run"].advance(_meters, cadence, DT)
	return env["abilities"].step(env["run"], patterns, DT)


func _ride(env: Dictionary, cadence: float, seconds: float, patterns: Array = []) -> void:
	for i in range(roundi(seconds / DT)):
		_step(env, cadence, patterns if i == 0 else [])


func _block(env: Dictionary) -> ChallengeBlock:
	return env["run"].active["block"]


# --- Arcade-Level --------------------------------------------------------------------------------------------------


func test_arcade_level_curve() -> void:
	assert_eq(ArcadeLevel.points_for(1), 0)
	assert_eq(ArcadeLevel.points_for(2), 400)
	assert_eq(ArcadeLevel.points_for(3), 1000)
	assert_eq(ArcadeLevel.points_for(4), 1800)
	assert_eq(ArcadeLevel.points_for(ArcadeLevel.MAX_LEVEL), 15400)
	assert_eq(ArcadeLevel.level_for(0), 1)
	assert_eq(ArcadeLevel.level_for(399), 1, "eine Stufe darunter")
	assert_eq(ArcadeLevel.level_for(400), 2)
	assert_eq(ArcadeLevel.level_for(999), 2)
	assert_eq(ArcadeLevel.level_for(1000), 3)
	assert_eq(ArcadeLevel.level_for(10000000), ArcadeLevel.MAX_LEVEL, "Höchstlevel")
	assert_eq(ArcadeLevel.points_to_next(0), 400)
	assert_eq(ArcadeLevel.points_to_next(450), 550)
	assert_eq(ArcadeLevel.points_to_next(10000000), 0)
	assert_eq(ArcadeLevel.talent_points_for(1), 0, "Level 1: kein Talentpunkt")
	assert_eq(ArcadeLevel.talent_points_for(5), 4)
	assert_lt(ArcadeLevel.talent_points_for(ArcadeLevel.MAX_LEVEL), Talents.NODES.size(), "der Baum füllt sich nie ganz")


func test_points_of_runs_raise_the_arcade_level_and_stay_separate_from_the_driver_level() -> void:
	var save := SaveGame.new()
	assert_eq(ArcadeLevel.level(save), 1)
	assert_eq(ArcadeLevel.add_points(save, 300), 300)
	assert_eq(ArcadeLevel.level(save), 1)
	assert_eq(ArcadeLevel.add_points(save, 150), 450)
	assert_eq(ArcadeLevel.level(save), 2, "400 Punkte: Level 2")
	assert_eq(ArcadeLevel.add_points(save, 0), 450, "ein Lauf ohne Punkte ändert nichts")
	assert_eq(ArcadeLevel.add_points(save, -20), 450)
	assert_eq(DriverLevel.level_for(save.total_km()), 1, "das Fahrerlevel folgt allein den Kilometern")


func test_arcade_level_ignores_garbage_in_the_save() -> void:
	for garbage in ["viel", -5, null, [1], {"a": 1}]:
		var save := SaveGame.new()
		save.arcade()["points_total"] = garbage
		assert_eq(ArcadeLevel.total_points(save), 0, "%s zählt 0" % str(garbage))
		assert_eq(ArcadeLevel.level(save), 1)


# --- Baum: Aufbau, Punkte, Voraussetzungen, Verteilen, Zurücksetzen -----------------------------------------------------


func test_tree_has_fifteen_nodes_in_three_branches_with_prerequisites_inside_the_branch() -> void:
	assert_eq(Talents.NODES.size(), 15)
	assert_eq(Talents.BRANCHES.keys(), ["sprinter", "kletterer", "ausdauer"])
	var seen := []
	for branch in Talents.BRANCHES:
		var nodes := Talents.nodes_of(branch)
		assert_eq(nodes.size(), 5, "%s: fünf Knoten" % branch)
		assert_eq(nodes.filter(func(id): return Talents.NODES[id]["requires"] == "").size(), 1, "%s: eine Wurzel" % branch)
	for id in Talents.NODES:
		var node: Dictionary = Talents.NODES[id]
		if node["requires"] != "":
			assert_true(seen.has(node["requires"]), "%s: Vorgänger steht davor" % id)
			assert_eq(Talents.NODES[node["requires"]]["branch"], node["branch"], "%s: Vorgänger im selben Ast" % id)
		seen.append(id)
		assert_false(node["name"].is_empty() or node["text"].is_empty(), "%s: Name und Beschreibung" % id)
		assert_false(node["changes"].is_empty(), "%s: wirkt auf etwas" % id)


func test_every_change_in_the_data_is_well_formed() -> void:
	var all := []
	for id in Talents.NODES:
		all.append_array(Talents.NODES[id]["changes"])
	for effect in Loot.EFFECTS:
		all.append_array(Loot.EFFECTS[effect]["changes"])
	for change in all:
		if change.has("ability"):
			assert_true(Abilities.DEFS.has(change["ability"]), "bekannte Fähigkeit %s" % change["ability"])
			assert_true(BuildEffects.ABILITY_KEYS.has(change["key"]))
			assert_true(Abilities.DEFS[change["ability"]].has(change["key"]), "%s hat %s" % [change["ability"], change["key"]])
			assert_true(change.has("add") or change.has("mul"))
		elif change.has("pattern"):
			assert_true(CadencePatterns.THRESHOLDS.has(change["pattern"]), "bekannte Schwelle %s" % change["pattern"])
		elif change.has("gear"):
			assert_true(Loot.STATS.has(change["gear"]), "bekannter Wert %s" % change["gear"])
		else:
			assert_true(change.has("knockback"), "bekannte Form: %s" % str(change))


func test_talent_points_come_from_the_arcade_level() -> void:
	var fresh := SaveGame.new()
	assert_eq(Talents.available(fresh), 0, "Level 1: keine Punkte")
	assert_eq(Talents.blocked_by(fresh, "sprinter_antritt"), "points")
	assert_false(Talents.learn(fresh, "sprinter_antritt"))
	assert_eq(Talents.learned(fresh), [])
	var save := _save_at(3)
	assert_eq(Talents.available(save), 2, "Level 3: zwei Punkte")
	assert_true(Talents.learn(save, "sprinter_antritt"))
	assert_eq(Talents.available(save), 1)
	assert_eq(Talents.spent(save), 1)
	assert_true(Talents.learn(save, "kletterer_zaeh"))
	assert_eq(Talents.available(save), 0)
	assert_false(Talents.learn(save, "ausdauer_gleichmass"), "keine Punkte mehr")
	assert_eq(Talents.blocked_by(save, "ausdauer_gleichmass"), "points")
	ArcadeLevel.add_points(save, 800)  # Level 4
	assert_eq(Talents.available(save), 1, "das nächste Level gibt einen weiteren Punkt")


func test_prerequisites_inside_a_branch() -> void:
	var save := _save_at(8)
	assert_eq(Talents.blocked_by(save, "sprinter_spurt"), "requires")
	assert_false(Talents.learn(save, "sprinter_spurt"), "ohne Vorgänger")
	assert_eq(Talents.blocked_by(save, "nein"), "unknown")
	assert_false(Talents.learn(save, "nein"))
	assert_true(Talents.learn(save, "sprinter_antritt"))
	assert_eq(Talents.blocked_by(save, "sprinter_antritt"), "learned")
	assert_false(Talents.learn(save, "sprinter_antritt"), "nicht zweimal")
	assert_eq(Talents.spent(save), 1, "ein zweiter Versuch kostet nichts")
	assert_false(Talents.learn(save, "kletterer_atem"), "ein anderer Ast hilft nicht")
	assert_true(Talents.learn(save, "sprinter_atem"))
	assert_true(Talents.learn(save, "sprinter_spurt"), "Kette Wurzel → Atem → Spurt")
	assert_eq(Talents.learned(save), ["sprinter_antritt", "sprinter_atem", "sprinter_spurt"], "in der Reihenfolge des Erlernens")
	assert_true(Talents.can_learn(save, "sprinter_reflex"), "der zweite Zweig steht offen")


func test_reset_is_free_and_returns_every_point() -> void:
	var save := _save_at(5)
	for id in ["sprinter_antritt", "sprinter_atem", "kletterer_zaeh"]:
		assert_true(Talents.learn(save, id))
	assert_eq(Talents.available(save), 1)
	assert_eq(Talents.reset(save), 3, "drei Punkte zurück")
	assert_eq(Talents.learned(save), [])
	assert_eq(Talents.available(save), 4, "alle Punkte frei")
	assert_eq(ArcadeLevel.level(save), 5, "das Level bleibt")
	assert_eq(Talents.reset(save), 0, "nichts zu tun")
	assert_true(Talents.learn(save, "ausdauer_gleichmass"), "neu verteilen")


func test_talents_are_saved_and_old_saves_load() -> void:
	var save := _save_at(4)
	Talents.learn(save, "sprinter_antritt")
	Talents.learn(save, "sprinter_reflex")
	assert_eq(save.save_file(SAVE_PATH), OK)
	var loaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(ArcadeLevel.total_points(loaded), 1800)
	assert_eq(Talents.learned(loaded), ["sprinter_antritt", "sprinter_reflex"], "nach dem Laden dieselben Talente")
	assert_eq(Talents.available(loaded), 1)
	assert_eq(loaded.profile()["arcade"].get("talents").size(), 2)
	# Zurücksetzen wird gespeichert
	Talents.reset(loaded)
	loaded.save_file(SAVE_PATH)
	assert_eq(Talents.learned(SaveGame.load_file(SAVE_PATH)), [])
	# Ein Stand ohne diese Felder (vor #53) lädt: Level 1, keine Talente, Ausrüstung unberührt.
	var old := SaveGame.new()
	old.arcade()["tier"] = 2
	old.arcade()["best_points"] = {"1": 100}
	old.save_file(SAVE_PATH)
	var upgraded := SaveGame.load_file(SAVE_PATH)
	assert_eq(ArcadeLevel.level(upgraded), 1)
	assert_eq(Talents.learned(upgraded), [])
	assert_eq(Talents.available(upgraded), 0)
	assert_eq(upgraded.best_arcade_points(1), 100)
	assert_eq(SaveGame.VERSION, 1, "die Formatversion bleibt")


func test_invalid_talents_from_disk_do_not_count() -> void:
	var save := _save_at(3)  # zwei Punkte
	save.arcade()["talents"] = ["gibt_es_nicht", 7, "sprinter_druck", "sprinter_antritt", "sprinter_antritt", "sprinter_atem",
			"kletterer_zaeh"]
	assert_eq(Talents.learned(save), ["sprinter_antritt", "sprinter_atem"],
			"unbekannt, Zahl, ohne Vorgänger, doppelt und über den Punkten zählen nicht")
	assert_eq(Talents.available(save), 0)
	var broke := SaveGame.new()
	broke.arcade()["talents"] = ["sprinter_antritt"]
	assert_eq(Talents.learned(broke), [], "Level 1 hat keine Punkte")
	broke.arcade()["talents"] = "viel"
	assert_eq(Talents.learned(broke), [])
	broke.arcade()["talents"] = null
	assert_eq(Talents.changes(broke), [])


func test_gear_bonus_of_talents_for_the_recommended_strength() -> void:
	var save := _save_at(8)
	assert_eq(Talents.gear_bonus(save), {"zone_width_rpm": 0, "progress_pct": 0, "points_pct": 0, "luck_pct": 0})
	for id in ["kletterer_zaeh", "kletterer_ruhe", "kletterer_gipfel", "ausdauer_gleichmass", "ausdauer_breit"]:
		assert_true(Talents.learn(save, id), id)
	assert_eq(Talents.gear_bonus(save), {"zone_width_rpm": 2, "progress_pct": 4, "points_pct": 8, "luck_pct": 0})


# --- Talente verändern Fähigkeiten -----------------------------------------------------------------------------------


func test_every_talent_changes_something() -> void:
	for id in Talents.NODES:
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
		var abilities := Abilities.new()
		var patterns := CadencePatterns.new()
		BuildEffects.apply(Talents.NODES[id]["changes"], run, abilities, patterns)
		var changed: bool = abilities.defs != Abilities.DEFS or patterns.thresholds != CadencePatterns.THRESHOLDS \
				or not run.gear.is_empty()
		assert_true(changed, "%s verändert Fähigkeiten, Schwellen oder Werte" % id)
		assert_eq(Abilities.DEFS["windboe"]["power"], 2.0, "die Standarddaten bleiben")


func test_talents_change_the_values_of_the_abilities() -> void:
	var save := _save_at(12)
	for id in ["sprinter_antritt", "sprinter_atem", "sprinter_spurt", "kletterer_zaeh", "kletterer_atem", "kletterer_rast",
			"ausdauer_gleichmass", "ausdauer_fokus", "ausdauer_takt"]:
		assert_true(Talents.learn(save, id), id)
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	var abilities := Abilities.new()
	var before := abilities.defs.duplicate(true)
	BuildEffects.apply(BuildEffects.changes_for(save), run, abilities, CadencePatterns.new())
	assert_almost_eq(float(before["windboe"]["power"]), 2.0, 1e-9)
	assert_almost_eq(float(abilities.defs["windboe"]["power"]), 2.5, 1e-9, "Windböe stärker")
	assert_almost_eq(float(abilities.defs["windboe"]["cooldown_s"]), 14.0, 1e-9, "Windböe lädt schneller")
	assert_almost_eq(float(abilities.defs["windboe"]["duration_s"]), 3.5, 1e-9, "Windböe wirkt länger")
	assert_almost_eq(float(abilities.defs["schild"]["duration_s"]), 8.0, 1e-9, "Schild hält länger")
	assert_almost_eq(float(abilities.defs["schild"]["cooldown_s"]), 24.0, 1e-9)
	assert_almost_eq(float(abilities.defs["fokus"]["power"]), 0.75, 1e-9, "Fokus stärker")
	assert_almost_eq(float(abilities.defs["kombo"]["power"]), 45.0, 1e-9, "Kombo gibt mehr Punkte")
	assert_eq(run.gear["progress_pct"], 4, "Fortschritt in der Zone")
	assert_eq(abilities.defs["fokus"]["duration_s"], before["fokus"]["duration_s"], "was kein Talent berührt, bleibt")


func test_talents_move_the_thresholds_of_the_patterns() -> void:
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	var patterns := CadencePatterns.new()
	var applied := BuildEffects.apply(Talents.NODES["sprinter_reflex"]["changes"] + Talents.NODES["ausdauer_gleichmass"]["changes"]
			+ Talents.NODES["kletterer_ruhe"]["changes"], run, null, patterns)
	assert_almost_eq(float(patterns.thresholds["antritt_rise_rpm"]), 20.0, 1e-9)
	assert_almost_eq(float(patterns.thresholds["steady_hold_s"]), 8.0, 1e-9)
	assert_almost_eq(float(patterns.thresholds["pause_hold_s"]), 1.5, 1e-9)
	assert_eq(applied["thresholds"].size(), 3)
	assert_eq(CadencePatterns.THRESHOLDS["antritt_rise_rpm"], 25.0, "die Standardwerte bleiben")
	# Wirkung: ein Anstieg von 22 rpm in 2 s ist mit dem Talent ein Antritt, ohne nicht.
	var plain := CadencePatterns.new()
	var spry := CadencePatterns.new()
	spry.thresholds["antritt_rise_rpm"] = 20.0
	var seen_plain := []
	var seen_spry := []
	for i in range(20):
		seen_plain.append_array(plain.feed(70.0, DT))
		seen_spry.append_array(spry.feed(70.0, DT))
	for i in range(5):
		seen_plain.append_array(plain.feed(92.0, DT))
		seen_spry.append_array(spry.feed(92.0, DT))
	assert_does_not_have(seen_plain, CadencePatterns.ANTRITT, "+22 rpm: ohne Talent kein Antritt")
	assert_has(seen_spry, CadencePatterns.ANTRITT, "+22 rpm: mit „Wacher Antritt“ ein Antritt")


func test_stronger_windboe_makes_more_progress_in_the_block() -> void:
	var plain := _start(ZONE)
	var strong := _start(ZONE, Talents.NODES["sprinter_antritt"]["changes"])
	_ride(plain, 90.0, 5.0, [CadencePatterns.ANTRITT])
	_ride(strong, 90.0, 5.0, [CadencePatterns.ANTRITT])
	assert_almost_eq(_block(plain).progress(), (2.5 * 3.0 + 2.5) / 20.0, 0.02, "Standard: ×3 für 2,5 s")
	assert_almost_eq(_block(strong).progress(), (2.5 * 3.5 + 2.5) / 20.0, 0.02, "mit Talent: ×3,5 für 2,5 s")


func test_longer_windboe_and_shorter_cooldown_in_the_block() -> void:
	var changes: Array = Talents.NODES["sprinter_atem"]["changes"] + Talents.NODES["sprinter_spurt"]["changes"]
	var plain := _start(LONG_ZONE)
	var quick := _start(LONG_ZONE, changes)
	_step(plain, 90.0, [CadencePatterns.ANTRITT])
	_step(quick, 90.0, [CadencePatterns.ANTRITT])
	_ride(plain, 90.0, 3.0)
	_ride(quick, 90.0, 3.0)
	assert_false(plain["abilities"].is_active("windboe"), "ohne Talent nach 3 s vorbei (2,5 s)")
	assert_true(quick["abilities"].is_active("windboe"), "mit „Langer Spurt“ noch aktiv (3,5 s)")
	_ride(plain, 90.0, 12.0)  # 15 s nach dem Auslösen: bei 18 s Abklingzeit noch nicht wieder bereit
	_ride(quick, 90.0, 12.0)
	assert_false(plain["abilities"].is_ready("windboe"))
	assert_true(quick["abilities"].is_ready("windboe"), "mit „Kurze Pause“ (14 s) bereit")
	assert_eq(_step(quick, 90.0, [CadencePatterns.ANTRITT]), ["windboe"], "und löst wieder aus")
	assert_eq(_step(plain, 90.0, [CadencePatterns.ANTRITT]), [], "ohne Talent noch nicht")


func test_stronger_fokus_and_longer_schild_and_bigger_kombo() -> void:
	var plain := _start(ZONE)
	var focused := _start(ZONE, Talents.NODES["ausdauer_fokus"]["changes"])
	_ride(plain, 90.0, 10.0, [CadencePatterns.GLEICHMASS])
	_ride(focused, 90.0, 10.0, [CadencePatterns.GLEICHMASS])
	assert_almost_eq(_block(plain).progress(), (8.0 * 1.5 + 2.0) / 20.0, 0.02)
	assert_almost_eq(_block(focused).progress(), (8.0 * 1.75 + 2.0) / 20.0, 0.02, "Fokus ×1,75")
	var steady := _start(CHASE, Talents.NODES["kletterer_atem"]["changes"])
	_step(steady, 100.0, [CadencePatterns.INNEHALTEN])
	_ride(steady, 100.0, 7.0)
	assert_true(steady["abilities"].is_active("schild"), "Schild nach 7 s noch aktiv (8 s)")
	var combo := _start(ZONE, Talents.NODES["ausdauer_takt"]["changes"])
	_step(combo, 90.0, [CadencePatterns.RHYTHMUS])
	assert_eq(combo["run"].points, 45, "Kombo: 30 + 15 Punkte")


func test_gear_talents_widen_the_zone_but_stay_inside_the_cadence_range() -> void:
	var range_ := CadenceRange.new(60, 120)
	var save := _save_at(8)
	Talents.learn(save, "ausdauer_gleichmass")
	Talents.learn(save, "ausdauer_breit")
	var run := ArcadeRun.new(1, range_, [], 1000.0)
	BuildEffects.apply(BuildEffects.changes_for(save), run, null, null)
	assert_eq(run.gear["zone_width_rpm"], 2)
	var edge := {"id": "t_edge", "block": "zone_hold", "name": "Rand", "zone_rpm": [116, 120], "hold_s": 5.0, "window_s": 20.0,
			"points": 10}
	var wide := Encounters.zone_for(edge, 1, range_, run.gear)
	var plain := Encounters.zone_for(edge, 1, range_, {})
	assert_gt(wide.y - wide.x, plain.y - plain.x - 1e-9, "breiter oder gleich")
	assert_true(range_.contains_zone(wide.x, wide.y), "auch mit Talent im Kadenzbereich: Wächter")
	run.gear = {"zone_width_rpm": 10}
	for definition in Encounters.CHALLENGES:
		var zone := Encounters.zone_for(definition, 3, range_, run.gear)
		assert_true(range_.contains_zone(zone.x, zone.y), "%s: Zone im Bereich" % definition["id"])


func test_talent_gear_stays_under_the_caps_of_the_values() -> void:
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	run.gear = Loot.modifiers([_item("rahmen", Loot.LEGENDARY, "", {"progress_pct": 58})])
	BuildEffects.apply(Talents.NODES["sprinter_druck"]["changes"], run, null, null)
	assert_eq(run.gear["progress_pct"], Loot.STATS["progress_pct"]["cap"], "58 + 6 gedeckelt auf 60")


# --- Gegenproben: Talente und Effekte ersetzen nie das Treten --------------------------------------------------------------


func _everything() -> Array:
	var save := _save_at(ArcadeLevel.MAX_LEVEL)
	for id in Talents.NODES:
		Talents.learn(save, id)
	for slot_effect in [["rahmen", "rueckstoss"], ["trikot", "tiefer_atem"], ["helm", "kombo_ernte"],
			["schuhe", "im_fluss"], ["talisman", "auf_dem_sprung"]]:
		_wear(save, _item(slot_effect[0], Loot.LEGENDARY, slot_effect[1]))
	return BuildEffects.changes_for(save)


func test_without_cadence_nothing_progresses_even_with_everything() -> void:
	var changes := _everything()
	for definition in [ZONE, BREAK, CHASE]:
		var env := _start(definition, changes, {"progress_pct": 60})
		var block := _block(env)
		var before := block.progress()
		var triggers := [CadencePatterns.ANTRITT, CadencePatterns.GLEICHMASS, CadencePatterns.INNEHALTEN]
		for i in range(300):  # 30 s mit allen Mustern ohne Treten / unterhalb der Zone
			_step(env, 0.0 if i % 2 == 0 else 40.0, triggers)
			if i % 20 == 0:
				BuildEffects.knock_back(block, 0.0, env["applied"]["knockback"])
		assert_lte(block.progress(), before + 1e-9, "%s: ohne Kadenz kein Fortschritt" % definition["id"])
		assert_ne(block.state, ChallengeBlock.SUCCEEDED, "%s: nicht geschafft" % definition["id"])
		assert_eq(env["run"].points, 0, "%s: keine Punkte" % definition["id"])


func test_the_boosts_do_not_touch_the_target_zone() -> void:
	for definition in [ZONE, BREAK, CHASE]:
		var plain := _start(definition)
		var full := _start(definition, _everything())
		var zone: Vector2 = _block(plain).zone()
		_ride(full, 90.0, 0.5, [CadencePatterns.ANTRITT, CadencePatterns.GLEICHMASS])
		assert_eq(_block(full).zone(), zone, "%s: Zone unverändert (ohne Zonenbreite aus der Ausrüstung)" % definition["id"])


# --- Legendäre Effekte -----------------------------------------------------------------------------------------------------


func test_the_roll_gives_an_effect_only_to_legendary_items() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var found := {}
	var legendary := 0
	for i in range(2000):
		var item := Loot.roll(rng, 40.0)  # hohe Qualität: viele seltene Funde
		assert_true(Loot.valid(item))
		if item["rarity"] == Loot.LEGENDARY:
			legendary += 1
			assert_true(Loot.EFFECTS.has(item["effect"]), "legendär: ein Effekt aus den Daten")
			assert_eq(Loot.effect_of(item), item["effect"])
			found[item["effect"]] = true
		else:
			assert_eq(item["effect"], "", "%s: kein Effekt" % item["rarity"])
			assert_eq(Loot.effect_of(item), "")
	assert_gt(legendary, 100)
	assert_eq(found.size(), Loot.EFFECTS.size(), "jeder Effekt kommt vor")
	# Grundverteilung: weit überwiegend ohne Effekt
	var plain := RandomNumberGenerator.new()
	plain.seed = 3
	var with_effect := 0
	for i in range(1000):
		if Loot.roll(plain)["effect"] != "":
			with_effect += 1
	assert_lt(with_effect, 80, "legendär ist selten (2 %)")


func test_the_roll_is_reproducible_with_the_effect() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i in range(300):
		assert_eq(Loot.roll(a, 30.0), Loot.roll(b, 30.0))


func test_older_legendary_items_without_effect_stay_valid_and_do_nothing() -> void:
	var old := _item("trikot", Loot.LEGENDARY, "")
	assert_true(Loot.valid(old))
	assert_eq(Loot.effect_of(old), "")
	assert_eq(Loot.effect_name(old), "")
	var no_field := old.duplicate()
	no_field.erase("effect")
	assert_true(Loot.valid(no_field), "auch ohne das Feld (Stände vor #49)")
	assert_eq(Loot.effect_of(no_field), "")
	var save := SaveGame.new()
	_wear(save, old)
	assert_eq(BuildEffects.effect_changes(save), [])
	assert_eq(Inventory.modifiers(save)["luck_pct"], 5, "Werte wirken weiter")
	# Zusammen mit dem Stand von der Platte
	save.save_file(SAVE_PATH)
	var loaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(Inventory.items(loaded).size(), 1)
	assert_eq(BuildEffects.effect_changes(loaded), [])


func test_only_known_effects_of_legendary_items_count() -> void:
	assert_eq(Loot.effect_of(_item("helm", Loot.RARE, "rueckstoss")), "", "ein seltenes Teil mit Effekt (manipuliert)")
	assert_eq(Loot.effect_of(_item("helm", Loot.LEGENDARY, "gibt_es_nicht")), "", "unbekannter Effekt")
	assert_eq(Loot.effect_of({"rarity": Loot.LEGENDARY, "effect": 5}), "", "kein Text")
	assert_eq(Loot.effect_of(_item("helm", Loot.LEGENDARY, "rueckstoss")), "rueckstoss")
	assert_eq(Loot.effect_name(_item("helm", Loot.LEGENDARY, "rueckstoss")), "Rückstoß")
	assert_string_contains(Loot.effect_text(_item("helm", Loot.LEGENDARY, "rueckstoss")), "Windböe wirft Gegner zurück")
	var save := SaveGame.new()
	_wear(save, _item("helm", Loot.RARE, "tiefer_atem"))
	assert_eq(BuildEffects.effect_changes(save), [], "ohne legendär kein Effekt")


func test_the_effect_survives_the_save() -> void:
	var save := SaveGame.new()
	_wear(save, _item("rahmen", Loot.LEGENDARY, "kombo_ernte"))
	save.save_file(SAVE_PATH)
	var loaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(Loot.effect_of(Inventory.equipped(loaded)["rahmen"]), "kombo_ernte")


func test_every_effect_changes_the_abilities_and_only_worn_ones_count() -> void:
	for effect in Loot.EFFECTS:
		var save := SaveGame.new()
		var item := Inventory.add(save, _item("helm", Loot.LEGENDARY, effect))
		assert_eq(BuildEffects.effect_changes(save), [], "%s: im Inventar, nicht angelegt: keine Wirkung" % effect)
		Inventory.equip(save, item["id"])
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
		var abilities := Abilities.new()
		var applied := BuildEffects.apply(BuildEffects.changes_for(save), run, abilities, CadencePatterns.new())
		assert_true(abilities.defs != Abilities.DEFS or not applied["knockback"].is_empty(), "%s verändert Fähigkeiten" % effect)
		assert_false(Loot.EFFECTS[effect]["name"].is_empty() or Loot.EFFECTS[effect]["text"].is_empty())
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	var abilities := Abilities.new()
	var save := SaveGame.new()
	_wear(save, _item("helm", Loot.LEGENDARY, "tiefer_atem"))
	BuildEffects.apply(BuildEffects.changes_for(save), run, abilities, null)
	assert_almost_eq(float(abilities.defs["schild"]["duration_s"]), 10.0, 1e-9, "Schild hält 4 s länger")
	assert_almost_eq(float(Abilities.DEFS["schild"]["duration_s"]), 6.0, 1e-9, "Standard bleibt")


func test_the_same_effect_on_two_items_counts_once() -> void:
	var save := SaveGame.new()
	_wear(save, _item("helm", Loot.LEGENDARY, "tiefer_atem"))
	_wear(save, _item("schuhe", Loot.LEGENDARY, "tiefer_atem"))
	assert_eq(BuildEffects.effect_changes(save).size(), 1)
	var abilities := Abilities.new()
	BuildEffects.apply(BuildEffects.changes_for(save), ArcadeRun.new(1, CadenceRange.new(), [], 1000.0), abilities, null)
	assert_almost_eq(float(abilities.defs["schild"]["duration_s"]), 10.0, 1e-9, "nicht 14 s")


func test_effects_make_the_shield_last_and_the_combo_pay_more() -> void:
	var save := SaveGame.new()
	_wear(save, _item("helm", Loot.LEGENDARY, "tiefer_atem"))
	_wear(save, _item("rahmen", Loot.LEGENDARY, "kombo_ernte"))
	var env := _start(CHASE, BuildEffects.changes_for(save))
	_step(env, 100.0, [CadencePatterns.INNEHALTEN])
	_ride(env, 100.0, 8.0)
	assert_true(env["abilities"].is_active("schild"), "nach 8 s noch aktiv (10 s)")
	var plain := _start(CHASE)
	_step(plain, 100.0, [CadencePatterns.INNEHALTEN])
	_ride(plain, 100.0, 8.0)
	assert_false(plain["abilities"].is_active("schild"), "ohne Effekt nach 6 s vorbei")
	var combo := _start(CHASE, BuildEffects.changes_for(save))
	_step(combo, 100.0, [CadencePatterns.RHYTHMUS])
	assert_eq(combo["run"].points, 60, "Kombo-Ernte: doppelte Punkte (2 × 30)")


func test_fluss_and_sprung_effects_change_fokus_and_windboe() -> void:
	var save := SaveGame.new()
	_wear(save, _item("helm", Loot.LEGENDARY, "im_fluss"))
	_wear(save, _item("rahmen", Loot.LEGENDARY, "auf_dem_sprung"))
	var env := _start(ZONE, BuildEffects.changes_for(save))
	var defs: Dictionary = env["abilities"].defs
	assert_almost_eq(float(defs["fokus"]["power"]), 1.0, 1e-9, "Fokus doppelt so stark")
	assert_almost_eq(float(defs["fokus"]["duration_s"]), 12.0, 1e-9, "und 4 s länger")
	assert_almost_eq(float(defs["windboe"]["cooldown_s"]), 10.0, 1e-9, "Windböe lädt 8 s schneller")


func test_talents_come_first_then_the_loot() -> void:
	var save := _save_at(8)
	Talents.learn(save, "ausdauer_gleichmass")
	Talents.learn(save, "ausdauer_fokus")
	Talents.learn(save, "ausdauer_takt")
	_wear(save, _item("rahmen", Loot.LEGENDARY, "kombo_ernte"))
	var abilities := Abilities.new()
	BuildEffects.apply(BuildEffects.changes_for(save), ArcadeRun.new(1, CadenceRange.new(), [], 1000.0), abilities, null)
	assert_almost_eq(float(abilities.defs["kombo"]["power"]), 90.0, 1e-9, "(30 + 15) × 2")


func test_cooldowns_and_thresholds_have_a_floor() -> void:
	var abilities := Abilities.new()
	var patterns := CadencePatterns.new()
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	BuildEffects.apply([{"ability": "windboe", "key": "cooldown_s", "add": -100.0}, {"ability": "schild", "key": "duration_s", "add": -100.0},
			{"pattern": "pause_hold_s", "add": -100.0}, {"ability": "gibt_es_nicht", "key": "power", "add": 1.0},
			{"ability": "windboe", "key": "name", "add": 1.0}, {"pattern": "gibt_es_nicht", "add": 1.0},
			{"gear": "gibt_es_nicht", "add": 1}], run, abilities, patterns)
	assert_eq(abilities.defs["windboe"]["cooldown_s"], BuildEffects.MIN_COOLDOWN_S)
	assert_eq(abilities.defs["schild"]["duration_s"], 0.0)
	assert_eq(patterns.thresholds["pause_hold_s"], BuildEffects.MIN_THRESHOLD)
	assert_eq(abilities.defs["windboe"]["name"], "Windböe", "Texte bleiben")
	assert_eq(run.gear, {})


# --- Rückstoß: „Antritt wirft Gegner zurück“ -------------------------------------------------------------------------------


func test_knockback_pushes_the_chaser_back_only_with_cadence_above_the_threshold() -> void:
	var knock: Dictionary = Loot.EFFECTS["rueckstoss"]["changes"][0]["knockback"]
	var env := _start(CHASE)
	var chase: Chase = _block(env)
	var gap := chase.gap
	assert_false(BuildEffects.knock_back(chase, 40.0, knock), "unter der Schwelle: nichts")
	assert_eq(chase.gap, gap)
	assert_true(BuildEffects.knock_back(chase, 100.0, knock))
	assert_almost_eq(chase.gap, gap + 0.15, 1e-9, "+15 % Abstand")
	assert_gte(chase.best_gap, chase.gap)
	for i in range(20):
		BuildEffects.knock_back(chase, 100.0, knock)
	assert_almost_eq(chase.gap, BuildEffects.KNOCK_CEILING, 1e-9, "nie ganz bis zum Erfolg")
	assert_lt(chase.gap, 1.0, "ein Stück bleibt offen: der Erfolg gehört dem Treten")
	assert_eq(chase.state, ChallengeBlock.RUNNING, "geschafft wird es nur durch Treten")
	_ride(env, 0.0, 3.0)  # ohne Treten holt der Verfolger auf, geschafft wird nichts
	assert_ne(chase.state, ChallengeBlock.SUCCEEDED)
	assert_lt(chase.gap, BuildEffects.KNOCK_CEILING)


func test_knockback_reaches_the_running_phase_of_a_boss_or_an_elite_group() -> void:
	var knock: Dictionary = Loot.EFFECTS["rueckstoss"]["changes"][0]["knockback"]
	var bosses := preload("res://src/challenges/boss_challenges.gd")
	var dimonis := Encounters.build(bosses.find("dimonis"), 1, CadenceRange.new()) as BossFight
	var chase := dimonis.current_phase() as Chase
	var gap := chase.gap
	assert_false(BuildEffects.knock_back(dimonis, 40.0, knock), "unter der Schwelle der Phase: nichts")
	assert_true(BuildEffects.knock_back(dimonis, 100.0, knock), "die Jagd-Phase der Dimonis bekommt den Rückstoß")
	assert_almost_eq(chase.gap, gap + 0.15, 1e-9)
	for i in range(20):
		BuildEffects.knock_back(dimonis, 100.0, knock)
	assert_almost_eq(chase.gap, BuildEffects.KNOCK_CEILING, 1e-9, "auch im Bosskampf nie ganz bis zum Erfolg")
	assert_eq(dimonis.state, ChallengeBlock.RUNNING)
	var tramuntana := Encounters.build(bosses.find("tramuntana"), 1, CadenceRange.new()) as BossFight
	assert_false(BuildEffects.knock_back(tramuntana, 100.0, knock), "Phase Zone halten: kein Rückstoß")
	var elite_def := EliteGroups.make(Encounters.find("durchbruch_bruecke"), EliteGroups.CHAMPION, [])
	var elite := Encounters.build(elite_def, 1, CadenceRange.new()) as BossFight
	assert_true(BuildEffects.knock_back(elite, 110.0, knock), "der Durchbruch einer Elite-Gruppe bekommt den Rückstoß")
	assert_almost_eq((elite.current_phase() as Breakthrough).level, 0.10, 1e-9)
	dimonis.state = ChallengeBlock.FAILED
	assert_false(BuildEffects.knock_back(dimonis, 100.0, knock), "nach dem Kampf nichts")


func test_knockback_fills_the_breakthrough_bar_and_leaves_other_blocks_alone() -> void:
	var knock: Dictionary = Loot.EFFECTS["rueckstoss"]["changes"][0]["knockback"]
	var env := _start(BREAK)
	var bar: Breakthrough = _block(env)
	assert_false(BuildEffects.knock_back(bar, 40.0, knock), "unter der Schwelle: nichts")
	assert_true(BuildEffects.knock_back(bar, 100.0, knock))
	assert_almost_eq(bar.level, 0.10, 1e-9, "+10 % Balken")
	for i in range(20):
		BuildEffects.knock_back(bar, 100.0, knock)
	assert_almost_eq(bar.level, BuildEffects.KNOCK_CEILING, 1e-9, "auch der Balken füllt sich nie ganz")
	assert_lt(bar.level, 1.0)
	assert_eq(bar.state, ChallengeBlock.RUNNING)
	var zone := _start(ZONE)
	assert_false(BuildEffects.knock_back(_block(zone), 90.0, knock), "Zone halten: kein Rückstoß")
	assert_eq(_block(zone).progress(), 0.0)
	assert_false(BuildEffects.knock_back(null, 90.0, knock))
	assert_false(BuildEffects.knock_back(bar, 100.0, {}), "ohne Effekt nichts")
	bar.state = ChallengeBlock.FAILED
	assert_false(BuildEffects.knock_back(bar, 100.0, knock), "nach dem Ende nichts")


func test_knockback_data_comes_from_the_equipped_effect() -> void:
	var save := SaveGame.new()
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0)
	assert_eq(BuildEffects.apply(BuildEffects.changes_for(save), run, null, null)["knockback"], {})
	_wear(save, _item("helm", Loot.LEGENDARY, "rueckstoss"))
	var knock: Dictionary = BuildEffects.apply(BuildEffects.changes_for(save), run, null, null)["knockback"]
	assert_almost_eq(float(knock["chase_gap"]), 0.15, 1e-9)
	assert_almost_eq(float(knock["breakthrough_fill"]), 0.10, 1e-9)
