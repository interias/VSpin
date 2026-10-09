## Arcade als reine Logik (#46): Baustein Zone halten (Fortschritt, Erfolg, weiches Scheitern), der Kadenzbereich als
## Wächter aller Zielzonen (Positiv- und Gegenprobe), Begegnungen als Daten mit Stufen und der Arcade-Lauf
## (Herausforderungen je Abschnitt, jede Runde neu gewürfelt, Punkte, Zusammenfassung).
extends GutTest

const DT := 0.1
## Würfel, mit dem der erste Abschnitt zwei Herausforderungen bekommt.
const SEED_TWO_IN_FIRST := 4


func _hold(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


# --- Zone halten ---------------------------------------------------------------------------------------------------


func test_zone_hold_succeeds_after_hold_time_in_zone() -> void:
	var block := ZoneHold.new(80.0, 100.0, 10.0, 20.0)
	assert_eq(block.state, ChallengeBlock.RUNNING)
	_hold(block, 90.0, 5.0)
	assert_almost_eq(block.progress(), 0.5, 0.001, "halbe Haltezeit = halber Fortschritt")
	assert_almost_eq(block.remaining_s(), 15.0, 0.001)
	_hold(block, 90.0, 5.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)
	assert_eq(block.progress(), 1.0)
	_hold(block, 0.0, 30.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "nach dem Ende wirkungslos")


func test_zone_hold_limits_are_inside_and_progress_does_not_sink_outside() -> void:
	var block := ZoneHold.new(80.0, 100.0, 10.0, 30.0)
	_hold(block, 80.0, 2.0)
	_hold(block, 100.0, 2.0)
	assert_almost_eq(block.progress(), 0.4, 0.001, "Grenzen zählen zur Zone")
	_hold(block, 79.9, 5.0)
	_hold(block, 100.1, 5.0)
	assert_almost_eq(block.progress(), 0.4, 0.001, "außerhalb steht der Fortschritt, er sinkt nicht")
	assert_almost_eq(block.elapsed_s, 14.0, 0.001, "die Zeit läuft trotzdem")


func test_zone_hold_fails_softly_when_window_runs_out() -> void:
	var block := ZoneHold.new(80.0, 100.0, 10.0, 20.0)
	_hold(block, 90.0, 6.0)
	_hold(block, 103.0, 20.0)
	assert_eq(block.state, ChallengeBlock.FAILED, "Zeitfenster vorbei, nicht voll")
	assert_almost_eq(block.progress(), 0.6, 0.001, "der erreichte Fortschritt bleibt sichtbar")
	assert_almost_eq(block.elapsed_s, 20.0, 0.001, "endet genau am Fenster")


func test_zone_hold_counts_a_step_over_the_end_partially() -> void:
	var block := ZoneHold.new(80.0, 100.0, 1.0, 2.0)
	block.update(90.0, 0.7)
	block.update(90.0, 0.7)  # nur 0,3 s davon fehlen noch
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)
	assert_almost_eq(block.elapsed_s, 1.0, 0.001, "Erfolg genau nach der Haltezeit")


func test_without_update_nothing_runs() -> void:
	# Pausen: die Hauptszene ruft in Pausen nichts auf – ein Baustein läuft nur über `update`.
	var block := ZoneHold.new(80.0, 100.0, 10.0, 20.0)
	_hold(block, 90.0, 3.0)
	var before := [block.progress(), block.remaining_s(), block.state]
	block.update(90.0, 0.0)
	assert_eq([block.progress(), block.remaining_s(), block.state], before)


# --- Kadenzbereich (Wächter) ---------------------------------------------------------------------------------------


func test_cadence_range_guard_limits_zone_that_would_stick_out() -> void:
	var personal := CadenceRange.new(60.0, 120.0)
	assert_eq(personal.limit_zone(110.0, 130.0), Vector2(100.0, 120.0), "oben herausragend: rückt mit Breite hinein")
	assert_eq(personal.limit_zone(50.0, 64.0), Vector2(60.0, 74.0), "unten herausragend: rückt hinein")
	assert_eq(personal.limit_zone(40.0, 140.0), Vector2(60.0, 120.0), "breiter als der Bereich: der ganze Bereich")
	assert_eq(CadenceRange.new(70.0, 90.0).limit_zone(150.0, 160.0), Vector2(80.0, 90.0), "ganz außerhalb")


func test_cadence_range_guard_leaves_zone_inside_unchanged() -> void:
	var personal := CadenceRange.new(60.0, 120.0)
	assert_eq(personal.limit_zone(80.0, 100.0), Vector2(80.0, 100.0))
	assert_eq(personal.limit_zone(60.0, 120.0), Vector2(60.0, 120.0), "genau der Bereich")
	assert_eq(personal.limit_zone(100.0, 120.0), Vector2(100.0, 120.0), "an der Grenze")


func test_cadence_range_default_and_validation() -> void:
	var standard := CadenceRange.new()
	assert_eq([standard.minimum, standard.maximum], [60.0, 120.0], "Standard 60–120 rpm")
	assert_eq(CadenceRange.from_dict({"min": 70, "max": 110}).to_dict(), {"min": 70.0, "max": 110.0})
	for broken in [null, {}, {"min": 120, "max": 60}, {"min": "60", "max": 120}, {"min": -5, "max": 120},
			{"min": 60, "max": 260}]:
		assert_eq(CadenceRange.from_dict(broken).to_dict(), {"min": 60.0, "max": 120.0}, "ungültig: %s" % [broken])
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			assert_gte(upper - lower, ArcadeTiers.LIST[0]["zone_width_rpm"], "jede Auswahl hat Platz für eine Zone")


# --- Begegnungen und Stufen ----------------------------------------------------------------------------------------


func test_three_tiers_narrow_zones_and_raise_duration_and_points() -> void:
	assert_eq(ArcadeTiers.LIST.map(func(t): return t["tier"]), [1, 2, 3])
	var definition := Encounters.find("zone_mitte")
	var personal := CadenceRange.new()
	var widths := []
	for tier in [1, 2, 3]:
		var zone := Encounters.zone_for(definition, tier, personal)
		widths.append(zone.y - zone.x)
		assert_almost_eq((zone.x + zone.y) / 2.0, 90.0, 0.001, "Mitte des Bereichs")
	assert_eq(widths, [20.0, 14.0, 10.0], "höhere Stufe, schmalere Zone")
	var holds := [1, 2, 3].map(func(t): return (Encounters.build(definition, t, personal) as ZoneHold).hold_s)
	assert_eq(holds, [15.0, 18.75, 22.5], "höhere Stufe, länger halten")
	assert_eq([1, 2, 3].map(func(t): return Encounters.points_for(definition, t)), [100, 200, 300])
	assert_eq(ArcadeTiers.valid(7), ArcadeTiers.DEFAULT, "unbekannte Stufe → Standard")


func test_zone_follows_personal_range_and_build_applies_the_guard() -> void:
	var mitte := Encounters.find("zone_mitte")
	assert_eq(Encounters.zone_for(mitte, 1, CadenceRange.new(80.0, 150.0)), Vector2(105.0, 125.0),
			"relativ zum Bereich: Mitte 115 rpm")
	# Eine feste Zone, die herausragen würde (z. B. später durch eine Elite-Eigenschaft), wird begrenzt …
	var fixed := {"id": "fest", "block": Encounters.ZONE_HOLD, "name": "Zone halten", "zone_rpm": [110.0, 130.0],
			"hold_s": 5.0, "window_s": 10.0, "points": 10}
	var block := Encounters.build(fixed, 1, CadenceRange.new()) as ZoneHold
	assert_eq(block.zone(), Vector2(100.0, 120.0), "Wächter in Encounters.build")
	# … eine innen bleibt, wie sie ist.
	fixed["zone_rpm"] = [85.0, 95.0]
	assert_eq((Encounters.build(fixed, 3, CadenceRange.new()) as ZoneHold).zone(), Vector2(85.0, 95.0))
	# Jede Herausforderung auf jeder Stufe in jedem wählbaren Bereich liegt im Bereich.
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var personal := CadenceRange.new(lower, upper)
			for definition in Encounters.CHALLENGES:
				for tier in [1, 2, 3]:
					var zone := (Encounters.build(definition, tier, personal) as ZoneHold).zone()
					assert_true(personal.contains_zone(zone.x, zone.y), "%s Stufe %d in %s" % [definition["id"], tier,
							personal.text()])


func test_new_challenge_is_only_data() -> void:
	var pool := [{"id": "zone_hoch", "block": Encounters.ZONE_HOLD, "name": "Hochzone", "zone_at": 0.9, "hold_s": 2.0,
			"window_s": 4.0, "points": 7}]
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, 3, pool)
	_ride(run, 0.0, 60.0, 112.0, 5.0)
	assert_eq(run.results[0]["name"], "Hochzone", "eine neue Herausforderung aus Daten, ohne neuen Code")
	assert_true(run.results[0]["succeeded"])
	assert_eq(run.points, 7)


# --- Arcade-Lauf ---------------------------------------------------------------------------------------------------


## Lauf von `from_m` mit `speed_mps` und Kadenz `cadence` für `seconds`; liefert die Fahrtposition am Ende.
func _ride(run: ArcadeRun, from_m: float, speed_mps: float, cadence: float, seconds: float) -> float:
	var d := from_m
	for i in range(roundi(seconds / DT)):
		d += speed_mps * DT
		run.advance(d, cadence, DT)
	return d


func _sections() -> Array:
	return [{"name": "A", "start_m": 0.0, "end_m": 400.0}, {"name": "B", "start_m": 400.0, "end_m": 1000.0}]


func test_one_or_two_challenges_per_section_rolled_new_each_lap() -> void:
	var run := ArcadeRun.new(1, CadenceRange.new(), _sections(), 1000.0, 0.0, 11)
	var laps := {}
	for entry in run.planned:
		var key := "%d %s" % [entry["lap"], entry["section"]]
		laps[key] = laps.get(key, 0) + 1
		assert_lt(entry["at_m"], entry["end_m"], "Start im Abschnitt")
	assert_eq(laps.keys().size(), 4, "laufende und nächste Runde gewürfelt, je zwei Abschnitte")
	for key in laps:
		assert_between(laps[key], 1, 2, key)
	assert_eq(run.planned[0]["at_m"], ArcadeRun.START_LEAD_M, "erste kurz nach dem Abschnittsbeginn")
	# Jede Runde neu ausgewürfelt: über viele Runden unterscheiden sich die Abfolgen.
	var long := ArcadeRun.new(1, CadenceRange.new(), _sections(), 1000.0, 0.0, 5)
	var orders := {}
	for lap in range(12):
		long._plan_until((lap + 1) * 1000.0)
	for entry in long.planned:
		orders[entry["lap"]] = orders.get(entry["lap"], "") + entry["definition"]["id"] + " "
	assert_gt(orders.values().reduce(func(acc, o): return acc if acc.has(o) else acc + [o], []).size(), 1,
			"nicht jede Runde gleich")
	var same := ArcadeRun.new(1, CadenceRange.new(), _sections(), 1000.0, 0.0, 11)
	assert_eq(same.planned.map(func(e): return e["definition"]["id"]),
			run.planned.map(func(e): return e["definition"]["id"]), "gleicher Würfel → gleicher Lauf")


func test_without_stations_the_lap_is_one_section() -> void:
	var run := ArcadeRun.new(1, CadenceRange.new(), [], 900.0, 0.0, 1)
	assert_eq(run.sections, [{"name": "", "start_m": 0.0, "end_m": 900.0}])
	assert_false(run.planned.is_empty())


func test_challenges_succeed_and_fail_softly_and_the_run_continues() -> void:
	var pool := [Encounters.find("zone_mitte")]
	var run := ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0, 0.0,
			2, pool)
	var d := _ride(run, 0.0, 8.0, 90.0, 6.4)  # bis zum Start (50 m)
	assert_false(run.active.is_empty(), "am Startpunkt beginnt sie")
	d = _ride(run, d, 8.0, 90.0, 15.2)
	assert_eq(run.results.size(), 1)
	assert_true(run.results[0]["succeeded"], "15 s in der Zone: geschafft")
	assert_eq(run.points, 100)
	# Die zweite Herausforderung des Abschnitts (falls gewürfelt) knapp daneben: weich verfehlt, keine Punkte.
	run = ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0, 0.0, 2,
			pool)
	d = _ride(run, 0.0, 8.0, 103.0, 6.4 + 30.2)
	assert_eq(run.results.size(), 1)
	assert_false(run.results[0]["succeeded"], "103 rpm bei 80–100: verfehlt")
	assert_eq(run.results[0]["points"], 0, "verfehlt: keine Punkte")
	assert_eq(run.points, 0)
	assert_false(run.planned.is_empty(), "der Lauf geht weiter")


func test_a_pending_challenge_waits_for_the_running_one_and_expires_with_its_section() -> void:
	var pool := [Encounters.find("zone_mitte")]
	var sections := [{"name": "Kurz", "start_m": 0.0, "end_m": 120.0}, {"name": "Lang", "start_m": 120.0,
			"end_m": 2000.0}]
	var run := ArcadeRun.new(1, CadenceRange.new(), sections, 2000.0, 0.0, SEED_TWO_IN_FIRST, pool)
	# Im kurzen Abschnitt liegt die zweite Herausforderung bei 85 m – die erste läuft dann noch.
	assert_eq(run.planned.filter(func(e): return e["lap"] == 0 and e["section"] == "Kurz").map(
			func(e): return e["at_m"]), [50.0, 85.0], "zwei im kurzen Abschnitt gewürfelt")
	var d := _ride(run, 0.0, 10.0, 0.0, 10.0)  # 100 m, ohne Treten: die erste läuft, nichts geschafft
	assert_eq(run.active["section"], "Kurz")
	d = _ride(run, d, 10.0, 0.0, 3.0)  # Abschnitt verlassen: eine wartende verfällt ungespielt
	for entry in run.planned.filter(func(e): return e["lap"] == 0):
		assert_eq(entry["section"], "Lang", "in dieser Runde nur noch Herausforderungen späterer Abschnitte")
	_ride(run, d, 10.0, 0.0, 30.0)
	assert_eq(run.results[0]["section"], "Kurz", "die laufende endet regulär")
	assert_false(run.results[0]["succeeded"])


func test_summary_lines() -> void:
	var run := ArcadeRun.new(2, CadenceRange.new(), [], 1000.0)
	run.results = [{"name": "Zone halten", "succeeded": true}, {"name": "Zone halten", "succeeded": false},
			{"name": "Zone halten", "succeeded": true}]
	run.points = 400
	assert_eq(run.summary_lines(), ["Punkte: 400", "Herausforderungen: 2 geschafft · 1 verfehlt", "Zone halten 2/3"])
	assert_eq(run.to_entry(), {"tier": 2, "points": 400, "won": 2, "failed": 1})
