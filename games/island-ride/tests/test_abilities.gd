## Fähigkeiten (#50): Windböe, Fokus, Schild und Kombo wirken im laufenden Baustein – nur mit laufender Herausforderung, nur
## auf Fortschritt mit Kadenz in der Zone bzw. als Rücknahme eines Verlusts, mit Abklingzeit, als Daten veränderbar und
## ohne je die Zielzone anzufassen. Reine Logik ohne Szene: `ArcadeRun` mit einer einzigen Herausforderung im Pool.
extends GutTest

const DT := 0.1
const ZONE := {"id": "t_zone", "block": "zone_hold", "name": "Zone halten", "zone_rpm": [80, 100], "hold_s": 20.0,
		"window_s": 60.0, "points": 100}
const BREAK := {"id": "t_break", "block": "breakthrough", "name": "Durchbruch", "threshold_at": 0.5, "fill_s": 10.0,
		"window_s": 60.0, "decay": 1.0, "points": 100}
const CHASE := {"id": "t_chase", "block": "chase", "name": "Jagd", "threshold_at": 0.5, "escape_s": 20.0,
		"catch_s": 20.0, "window_s": 120.0, "start_gap": 0.5, "points": 100}
## Schwelle der beiden Schwellen-Bausteine im Bereich 60–120 rpm.
const THRESHOLD := 90.0

var _meters := 100.0


## Lauf mit der einen Herausforderung `definition`, schon begonnen; dazu die Fähigkeiten.
func _start(definition: Dictionary, gear: Dictionary = {}) -> Dictionary:
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000000.0, 0.0, 1, [definition])
	run.gear = gear
	run.advance(_meters, 70.0, DT)  # der Baustein entsteht im Schritt, in dem der Startpunkt erreicht wird
	assert_false(run.active.is_empty(), "die Herausforderung läuft")
	var env := {"run": run, "abilities": Abilities.new()}
	env["abilities"].step(run, [], DT)
	return env


## Ein Fahrschritt wie in der Bühne: Lauf, dann Fähigkeiten (mit den in diesem Schritt erkannten Mustern).
func _step(env: Dictionary, cadence: float, patterns: Array = []) -> Array:
	_meters += 1.0
	env["run"].advance(_meters, cadence, DT)
	return env["abilities"].step(env["run"], patterns, DT)


func _ride(env: Dictionary, cadence: float, seconds: float, patterns: Array = []) -> void:
	for i in range(roundi(seconds / DT)):
		_step(env, cadence, patterns if i == 0 else [])


func _block(env: Dictionary) -> ChallengeBlock:
	return env["run"].active["block"]


# --- Windböe und Fokus: Faktor auf den Fortschritt in der Zone ------------------------------------------------------


func test_windboe_speeds_up_progress_in_the_zone_for_a_short_time() -> void:
	var plain := _start(ZONE)
	var gust := _start(ZONE)
	_ride(plain, 90.0, 5.0)
	_ride(gust, 90.0, 5.0, [CadencePatterns.ANTRITT])
	assert_almost_eq(_block(plain).progress(), 5.0 / 20.0, 0.01)
	assert_almost_eq(_block(gust).progress(), (2.5 * 3.0 + 2.5) / 20.0, 0.02, "2,5 s mit dreifachem Fortschritt")
	assert_eq(gust["abilities"].counts["windboe"], 1)


func test_fokus_gives_a_smaller_but_longer_boost() -> void:
	var focus := _start(ZONE)
	_ride(focus, 90.0, 10.0, [CadencePatterns.GLEICHMASS])
	assert_almost_eq(_block(focus).progress(), (8.0 * 1.5 + 2.0) / 20.0, 0.02, "8 s mit anderthalbfachem Fortschritt")


func test_the_boost_replaces_no_pedalling() -> void:
	for definition in [ZONE, BREAK, CHASE]:
		var env := _start(definition)
		var before := _block(env).progress()
		_ride(env, 40.0, 3.0, [CadencePatterns.ANTRITT])  # unter der Zone: nichts entsteht
		assert_lte(_block(env).progress(), before + 1e-9, "%s: Windböe ohne Treten hilft nicht" % definition["id"])
		_ride(env, 40.0, 3.0, [CadencePatterns.GLEICHMASS])
		assert_lte(_block(env).progress(), before + 1e-9, "%s: Fokus auch nicht" % definition["id"])


func test_the_boost_adds_to_the_factor_of_the_gear_and_goes_away_again() -> void:
	var env := _start(ZONE, {"progress_pct": 20})
	var block := _block(env)
	assert_almost_eq(block.progress_factor, 1.2, 1e-6, "Ausrüstung #49")
	_step(env, 90.0, [CadencePatterns.ANTRITT])
	assert_almost_eq(block.progress_factor, 3.2, 1e-6, "Ausrüstung + Windböe")
	_ride(env, 90.0, 3.0)
	assert_almost_eq(block.progress_factor, 1.2, 1e-6, "nach 2,5 s wieder nur die Ausrüstung")


func test_the_boost_helps_breakthrough_and_chase_too() -> void:
	for definition in [BREAK, CHASE]:
		var plain := _start(definition)
		var gust := _start(definition)
		_ride(plain, 100.0, 4.0)
		_ride(gust, 100.0, 4.0, [CadencePatterns.ANTRITT])
		assert_gt(_block(gust).progress(), _block(plain).progress() + 0.05, definition["id"])


# --- Nur in Herausforderungen, Abklingzeit -------------------------------------------------------------------------


func test_a_pattern_without_a_running_challenge_does_nothing_and_keeps_the_ability_ready() -> void:
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000000.0, 0.0, 1, [ZONE])  # noch nichts begonnen
	var abilities := Abilities.new()
	var triggered := abilities.step(run, [CadencePatterns.ANTRITT, CadencePatterns.RHYTHMUS], DT)
	assert_eq(triggered, [])
	assert_true(abilities.is_ready("windboe"), "nicht verbraucht")
	assert_eq(abilities.counts["windboe"], 0)
	assert_eq(run.points, 0, "kein Kombo außerhalb")


func test_an_ability_cools_down_after_use() -> void:
	var env := _start(ZONE)
	var abilities: Abilities = env["abilities"]
	assert_true(abilities.is_ready("windboe"))
	assert_eq(_step(env, 90.0, [CadencePatterns.ANTRITT]), ["windboe"])
	assert_eq(abilities.state_of("windboe"), "active")
	_ride(env, 70.0, 3.0)  # unter der Zone: die Herausforderung bleibt offen
	assert_eq(abilities.state_of("windboe"), "cooldown")
	assert_eq(_step(env, 90.0, [CadencePatterns.ANTRITT]), [], "noch nicht wieder bereit")
	assert_eq(abilities.counts["windboe"], 1)
	_ride(env, 70.0, 15.0)
	assert_true(abilities.is_ready("windboe"), "18 s nach der Auslösung")
	assert_eq(_step(env, 90.0, [CadencePatterns.ANTRITT]), ["windboe"])


func test_each_pattern_triggers_its_own_ability() -> void:
	var env := _start(ZONE)
	var triggered := _step(env, 90.0, [CadencePatterns.ANTRITT, CadencePatterns.GLEICHMASS, CadencePatterns.INNEHALTEN,
			CadencePatterns.RHYTHMUS])
	assert_eq(triggered, ["windboe", "fokus", "schild", "kombo"])
	assert_eq(env["abilities"].ability_for("unbekannt"), "")


# --- Schild: kein Fortschrittsverlust ------------------------------------------------------------------------------


func test_schild_keeps_the_chaser_from_closing_in() -> void:
	var open := _start(CHASE)
	var shielded := _start(CHASE)
	_ride(open, 60.0, 5.0)
	_ride(shielded, 60.0, 5.0, [CadencePatterns.INNEHALTEN])
	assert_almost_eq(_block(open).progress(), 0.5 - 5.0 / 20.0, 0.02, "ohne Schild holt er auf")
	assert_almost_eq(_block(shielded).progress(), 0.5, 0.005, "mit Schild bleibt der Abstand")
	_ride(shielded, 60.0, 3.0)  # das Schild (6 s) ist abgelaufen
	assert_lt(_block(shielded).progress(), 0.5 - 0.02, "danach geht der Verlust weiter")


func test_schild_keeps_the_breakthrough_bar() -> void:
	var open := _start(BREAK)
	var shielded := _start(BREAK)
	for env in [open, shielded]:
		_ride(env, 100.0, 5.0)  # Balken halb voll
	assert_almost_eq(_block(shielded).progress(), 0.5, 0.02)
	_ride(open, 60.0, 3.0)
	_ride(shielded, 60.0, 3.0, [CadencePatterns.INNEHALTEN])
	assert_lt(_block(open).progress(), 0.3, "der Balken sinkt")
	assert_almost_eq(_block(shielded).progress(), 0.5, 0.02, "unter dem Schild nicht")


func test_schild_lets_gains_through_and_time_runs_on() -> void:
	var env := _start(CHASE)
	_step(env, 60.0, [CadencePatterns.INNEHALTEN])
	var elapsed := _block(env).elapsed_s
	_ride(env, 100.0, 3.0)  # über der Schwelle: der Abstand wächst auch unter dem Schild
	assert_gt(_block(env).progress(), 0.5 + 0.1, "Gewinne zählen")
	assert_almost_eq(_block(env).elapsed_s, elapsed + 3.0, 0.05, "die Zeit läuft weiter")


func test_schild_does_not_stop_the_window_from_running_out() -> void:
	var short := {"id": "t_short", "block": "chase", "name": "Jagd", "threshold_at": 0.5, "escape_s": 20.0,
			"catch_s": 20.0, "window_s": 4.0, "start_gap": 0.5, "points": 100}
	var env := _start(short)
	_step(env, 60.0, [CadencePatterns.INNEHALTEN])
	_ride(env, 60.0, 5.0)
	assert_true(env["run"].active.is_empty(), "das Zeitfenster ist vorbei")
	assert_false(env["run"].results[0]["succeeded"], "verfehlt, weich")


# --- Kombo ---------------------------------------------------------------------------------------------------------


func test_kombo_pays_points_and_more_after_other_abilities() -> void:
	var env := _start(ZONE)
	var abilities: Abilities = env["abilities"]
	_step(env, 90.0, [CadencePatterns.RHYTHMUS])
	assert_eq(env["run"].points, 30, "allein: Grundwert")
	_ride(env, 90.0, 16.0)  # Kombo ist wieder bereit, es liegt keine andere Fähigkeit in der Kette
	_step(env, 90.0, [CadencePatterns.ANTRITT])
	_step(env, 90.0, [CadencePatterns.RHYTHMUS])
	assert_eq(env["run"].points, 30 + 60, "nach einer Windböe: doppelt")
	assert_eq(abilities.combo_points, 90)
	assert_eq(abilities.counts["kombo"], 2)


func test_a_kombo_chain_does_not_count_the_kombo_itself_or_old_abilities() -> void:
	var env := _start(ZONE)
	_step(env, 90.0, [CadencePatterns.ANTRITT])
	_ride(env, 70.0, 25.0)  # die Windböe liegt länger als 20 s zurück
	_step(env, 90.0, [CadencePatterns.RHYTHMUS])
	assert_eq(env["run"].points, 30)
	_ride(env, 70.0, 16.0)
	_step(env, 90.0, [CadencePatterns.RHYTHMUS])
	assert_eq(env["run"].points, 60, "der erste Kombo ist keine „andere“ Fähigkeit")


# --- Daten, Zonen ------------------------------------------------------------------------------------------------


func test_abilities_are_data_a_run_can_change_without_touching_the_defaults() -> void:
	var env := _start(ZONE)
	var abilities: Abilities = env["abilities"]
	abilities.defs["fokus"]["power"] = 1.0
	abilities.defs["windboe"]["cooldown_s"] = 4.0
	_step(env, 90.0, [CadencePatterns.GLEICHMASS, CadencePatterns.ANTRITT])
	assert_almost_eq(_block(env).progress_factor, 1.0 + 1.0 + 2.0, 1e-6, "Fokus stärker")
	_ride(env, 90.0, 4.5)
	assert_true(abilities.is_ready("windboe"), "kürzere Abklingzeit")
	assert_eq(Abilities.DEFS["fokus"]["power"], 0.5, "die Standarddaten bleiben")
	abilities.reset()
	assert_eq(abilities.defs["fokus"]["power"], 0.5, "ein neuer Lauf beginnt mit den Standarddaten")


func test_no_ability_changes_the_target_zone() -> void:
	for definition in [ZONE, BREAK, CHASE]:
		var env := _start(definition)
		var zone := _block(env).zone()
		_step(env, 90.0, [CadencePatterns.ANTRITT, CadencePatterns.GLEICHMASS, CadencePatterns.INNEHALTEN,
				CadencePatterns.RHYTHMUS])
		_ride(env, 90.0, 2.0)
		assert_eq(_block(env).zone(), zone, "%s: die Zielzone bleibt" % definition["id"])
		assert_gte(zone.x, CadenceRange.DEFAULT_MIN)
		assert_lte(zone.y, CadenceRange.DEFAULT_MAX, "und im Kadenzbereich")


func test_a_new_challenge_starts_with_its_own_factor() -> void:
	var env := _start(ZONE, {"progress_pct": 10})
	_step(env, 90.0, [CadencePatterns.ANTRITT])
	var first := _block(env)
	assert_almost_eq(first.progress_factor, 3.1, 1e-6)
	var next := Encounters.build(ZONE, 1, CadenceRange.new(), {"progress_pct": 40})  # die nächste Herausforderung beginnt
	env["run"].active = {"block": next, "definition": ZONE}
	_step(env, 90.0)
	assert_almost_eq(next.progress_factor, 1.4 + 2.0, 1e-6, "die Böe wirkt weiter, aufgesetzt auf den Ausgangsfaktor des neuen")
	_ride(env, 90.0, 3.0)
	assert_almost_eq(next.progress_factor, 1.4, 1e-6)
