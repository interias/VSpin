## Die Bausteine Durchbruch und Jagd als reine Logik (#47): Balken füllen bzw. Verfolger abhängen – Erfolg, weiches
## Scheitern, Pause, Kadenzbereich-Wächter für die Schwelle (Positiv- und Gegenprobe), Ausrüstung nur über der Schwelle,
## Stufen und die Einbindung in Begegnungen (Daten) und Arcade-Lauf (Punkte, Beute).
extends GutTest

const DT := 0.1


func _feed(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


# --- Durchbruch ----------------------------------------------------------------------------------------------------


func test_breakthrough_fills_above_the_threshold_and_succeeds() -> void:
	var block := Breakthrough.new(108.0, 120.0, 6.0, 18.0)
	_feed(block, 115.0, 3.0)
	assert_almost_eq(block.progress(), 0.5, 0.001, "halbe Füllzeit = halber Balken")
	assert_eq(block.state, ChallengeBlock.RUNNING)
	_feed(block, 115.0, 3.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)
	assert_eq(block.progress(), 1.0)
	assert_almost_eq(block.elapsed_s, 6.0, 0.001, "Erfolg genau mit dem vollen Balken")
	_feed(block, 0.0, 30.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "nach dem Ende wirkungslos")


func test_breakthrough_threshold_counts_and_cadence_above_the_range_too() -> void:
	var block := Breakthrough.new(108.0, 120.0, 10.0, 20.0)
	_feed(block, 108.0, 2.0)
	assert_almost_eq(block.progress(), 0.2, 0.001, "die Schwelle selbst zählt")
	_feed(block, 140.0, 2.0)
	assert_almost_eq(block.progress(), 0.4, 0.001, "mehr als der Bereich zählt weiter, schneller wird es nicht")


func test_breakthrough_sinks_slowly_below_the_threshold_and_not_below_zero() -> void:
	var block := Breakthrough.new(108.0, 120.0, 10.0, 60.0, 0.5)
	_feed(block, 115.0, 4.0)
	_feed(block, 107.9, 4.0)
	assert_almost_eq(block.progress(), 0.2, 0.001, "darunter sinkt er mit halber Füllrate: 0,4 − 4 × 0,05")
	_feed(block, 0.0, 30.0)
	assert_eq(block.progress(), 0.0, "nie unter null")
	assert_eq(block.state, ChallengeBlock.RUNNING)


func test_breakthrough_fails_softly_when_the_window_runs_out() -> void:
	var block := Breakthrough.new(108.0, 120.0, 6.0, 12.0)
	_feed(block, 115.0, 3.0)
	_feed(block, 100.0, 20.0)
	assert_eq(block.state, ChallengeBlock.FAILED, "Zeitfenster vorbei, nicht voll")
	assert_almost_eq(block.elapsed_s, 12.0, 0.001, "endet genau am Fenster")
	assert_lt(block.progress(), 1.0)
	var weak := Breakthrough.new(108.0, 120.0, 6.0, 12.0)
	_feed(weak, 107.0, 20.0)
	assert_eq(weak.state, ChallengeBlock.FAILED, "zu schwach: verfehlt")
	assert_eq(weak.progress(), 0.0)


func test_breakthrough_counts_a_step_over_the_end_partially_and_pauses_with_no_update() -> void:
	var block := Breakthrough.new(100.0, 120.0, 1.0, 3.0)
	block.update(110.0, 0.7)
	block.update(110.0, 0.7)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)
	assert_almost_eq(block.elapsed_s, 1.0, 0.001)
	var paused := Breakthrough.new(100.0, 120.0, 6.0, 12.0)
	_feed(paused, 110.0, 2.0)
	var before := [paused.progress(), paused.remaining_s(), paused.state]
	paused.update(110.0, 0.0)
	assert_eq([paused.progress(), paused.remaining_s(), paused.state], before, "Pause: nichts läuft weiter")


func test_breakthrough_gear_speeds_up_only_above_the_threshold() -> void:
	var plain := Breakthrough.new(108.0, 120.0, 10.0, 30.0)
	var geared := Breakthrough.new(108.0, 120.0, 10.0, 30.0)
	geared.progress_factor = 2.0
	_feed(plain, 115.0, 2.0)
	_feed(geared, 115.0, 2.0)
	assert_almost_eq(geared.progress(), plain.progress() * 2.0, 0.001, "über der Schwelle schneller")
	assert_almost_eq(geared.elapsed_s, plain.elapsed_s, 0.001, "Zeitfenster unberührt")
	# Gegenprobe: ohne Kadenz über der Schwelle macht die Ausrüstung nichts – gleiche Verläufe mit und ohne.
	for cadence in [0.0, 60.0, 107.9]:
		var a := Breakthrough.new(108.0, 120.0, 10.0, 30.0)
		var b := Breakthrough.new(108.0, 120.0, 10.0, 30.0)
		b.progress_factor = 3.0
		_feed(a, cadence, 30.0)
		_feed(b, cadence, 30.0)
		assert_eq([b.progress(), b.state], [a.progress(), a.state], "%d rpm: Ausrüstung ersetzt nie das Treten" % cadence)
		assert_eq(b.progress(), 0.0)
		assert_eq(b.state, ChallengeBlock.FAILED)


# --- Jagd ----------------------------------------------------------------------------------------------------------


func test_chase_is_escaped_above_the_threshold() -> void:
	var block := Chase.new(93.0, 120.0, 12.0, 12.0, 30.0, 0.4)
	assert_almost_eq(block.progress(), 0.4, 0.001, "Vorsprung am Anfang")
	_feed(block, 100.0, 6.0)
	assert_almost_eq(block.progress(), 0.9, 0.001, "wächst mit 1/12 pro Sekunde")
	_feed(block, 100.0, 2.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "abgehängt")
	assert_almost_eq(block.elapsed_s, 7.2, 0.001, "Erfolg genau bei Abstand 1")
	assert_almost_eq(block.loot_progress(), 1.0, 0.001)


func test_chase_is_caught_below_the_threshold_softly() -> void:
	var block := Chase.new(93.0, 120.0, 12.0, 12.0, 30.0, 0.4)
	_feed(block, 92.9, 3.0)
	assert_almost_eq(block.progress(), 0.15, 0.001, "darunter schrumpft der Abstand")
	_feed(block, 92.9, 10.0)
	assert_eq(block.state, ChallengeBlock.FAILED, "eingeholt")
	assert_eq(block.progress(), 0.0)
	assert_almost_eq(block.elapsed_s, 4.8, 0.001, "endet genau beim Einholen")
	assert_eq(block.loot_progress(), 0.0, "geschenkter Vorsprung zählt nicht für die Beute")


func test_chase_fails_when_time_is_up_and_loot_counts_only_earned_distance() -> void:
	var block := Chase.new(93.0, 120.0, 20.0, 40.0, 10.0, 0.4)
	_feed(block, 100.0, 4.0)  # 0,4 → 0,6
	_feed(block, 90.0, 6.0)  # 0,6 → 0,45
	assert_eq(block.state, ChallengeBlock.FAILED, "Zeitfenster vorbei")
	assert_almost_eq(block.progress(), 0.45, 0.001)
	assert_almost_eq(block.loot_progress(), (0.6 - 0.4) / 0.6, 0.001, "größter erreichter Abstand über dem Start")
	var idle := Chase.new(93.0, 120.0, 20.0, 400.0, 10.0, 0.4)  # fast kein Einholen im Fenster
	_feed(idle, 0.0, 10.0)
	assert_eq(idle.state, ChallengeBlock.FAILED)
	assert_gt(idle.progress(), 0.0, "der Vorsprung bleibt sichtbar")
	assert_eq(idle.loot_progress(), 0.0, "ohne Treten über der Schwelle nie Beute")


func test_chase_gear_speeds_up_only_above_the_threshold_and_pause_stands_still() -> void:
	var plain := Chase.new(93.0, 120.0, 20.0, 20.0, 40.0, 0.4)
	var geared := Chase.new(93.0, 120.0, 20.0, 20.0, 40.0, 0.4)
	geared.progress_factor = 2.0
	_feed(plain, 100.0, 2.0)
	_feed(geared, 100.0, 2.0)
	assert_almost_eq(geared.progress() - 0.4, (plain.progress() - 0.4) * 2.0, 0.001, "über der Schwelle schneller")
	var a := Chase.new(93.0, 120.0, 20.0, 20.0, 40.0, 0.4)
	var b := Chase.new(93.0, 120.0, 20.0, 20.0, 40.0, 0.4)
	b.progress_factor = 3.0
	_feed(a, 50.0, 5.0)
	_feed(b, 50.0, 5.0)
	assert_eq(b.progress(), a.progress(), "unter der Schwelle hilft die Ausrüstung nicht")
	var before := [b.progress(), b.remaining_s(), b.state]
	b.update(100.0, 0.0)
	assert_eq([b.progress(), b.remaining_s(), b.state], before, "Pause: nichts läuft weiter")


# --- Wächter, Begegnungen als Daten, Stufen ------------------------------------------------------------------------


func _threshold_definitions() -> Array:
	return Encounters.CHALLENGES.filter(func(d): return d.has("threshold_at"))


func test_encounters_have_both_new_blocks_as_data() -> void:
	var blocks := Encounters.CHALLENGES.map(func(d): return d["block"])
	assert_has(blocks, Encounters.BREAKTHROUGH)
	assert_has(blocks, Encounters.CHASE)
	var personal := CadenceRange.new()
	assert_true(Encounters.build(Encounters.find("durchbruch_bruecke"), 1, personal) is Breakthrough)
	assert_true(Encounters.build(Encounters.find("jagd_verfolger"), 1, personal) is Chase)
	assert_eq(Encounters.target_text(Encounters.find("durchbruch_bruecke"), Vector2(108.0, 120.0)), "ab 108 rpm")
	assert_eq(Encounters.target_text(Encounters.find("zone_mitte"), Vector2(80.0, 100.0)), "80–100 rpm")


func test_threshold_is_guarded_by_the_personal_range() -> void:
	# Positivprobe: jede Schwelle jeder Herausforderung auf jeder Stufe in jedem wählbaren Bereich, mit und ohne
	# Ausrüstungsbreite, liegt im Bereich und nie über dem Maximum.
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for definition in _threshold_definitions():
				for tier in [1, 2, 3]:
					for width in [0, 4, 10]:
						var zone := Encounters.zone_for(definition, tier, range_, {"zone_width_rpm": width})
						var block := Encounters.build(definition, tier, range_, {"zone_width_rpm": width})
						assert_true(range_.contains_zone(zone.x, zone.y), "%s Stufe %d in %s" % [definition["id"],
								tier, range_.text()])
						assert_eq(block.zone(), zone, "Baustein und Anzeige stimmen überein")
						assert_lte(zone.x, upper, "Schwelle nie über dem Maximum")
	# Gegenprobe: eine Lage 1,4 läge ohne Wächter bei 168 rpm – sie landet auf dem Maximum; eine Lage unter dem
	# Minimum auf dem ganzen Bereich.
	var personal := CadenceRange.new(60.0, 120.0)
	assert_gt(personal.at(1.4), 120.0, "ohne Wächter wäre die Schwelle außerhalb")
	for kind in [Encounters.BREAKTHROUGH, Encounters.CHASE]:
		var high := {"id": "x", "block": kind, "name": "X", "threshold_at": 1.4, "fill_s": 5.0, "escape_s": 5.0,
				"catch_s": 5.0, "window_s": 10.0, "points": 1}
		assert_eq(Encounters.build(high, 3, personal).zone(), Vector2(120.0, 120.0), "Schwelle höchstens am Maximum")
		var low := high.duplicate()
		low["threshold_at"] = -2.0
		assert_eq(Encounters.build(low, 1, personal).zone(), Vector2(60.0, 120.0), "nicht unter dem Minimum")
	# Ausrüstung macht die Schwelle nachsichtiger (− halbe Breite), aber nie unter das Minimum.
	var bridge := Encounters.find("durchbruch_bruecke")
	assert_eq(Encounters.zone_for(bridge, 1, personal).x, 108.0)
	assert_eq(Encounters.zone_for(bridge, 1, personal, {"zone_width_rpm": 6}).x, 105.0, "− halbe Breite")
	assert_eq(Encounters.zone_for(bridge, 1, CadenceRange.new(60.0, 100.0), {"zone_width_rpm": 10}).x, 87.0)
	var bottom := {"id": "y", "block": Encounters.CHASE, "name": "Y", "threshold_at": 0.0, "escape_s": 5.0,
			"catch_s": 5.0, "window_s": 10.0, "points": 1}
	assert_eq(Encounters.zone_for(bottom, 1, personal, {"zone_width_rpm": 10}).x, 60.0, "Gegenprobe: nicht unter 60")


func test_tiers_raise_threshold_and_scale_duration_and_points() -> void:
	var personal := CadenceRange.new()
	var bridge := Encounters.find("durchbruch_bruecke")
	assert_eq([1, 2, 3].map(func(t): return Encounters.zone_for(bridge, t, personal).x), [108.0, 111.0, 113.0],
			"höhere Stufe, höhere Schwelle")
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(bridge, t, personal) as Breakthrough).fill_s),
			[6.0, 7.5, 9.0], "höhere Stufe, länger über der Schwelle")
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(bridge, t, personal) as Breakthrough).window_s),
			[18.0, 22.5, 27.0])
	var hunt := Encounters.find("jagd_verfolger")
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(hunt, t, personal) as Chase).escape_s), [12.0, 15.0, 18.0])
	assert_eq([1, 2, 3].map(func(t): return Encounters.points_for(hunt, t)), [140, 280, 420])


func test_build_gives_the_equipment_factor_to_the_new_blocks() -> void:
	var personal := CadenceRange.new()
	for id in ["durchbruch_bruecke", "jagd_verfolger"]:
		var block := Encounters.build(Encounters.find(id), 1, personal, {"progress_pct": 50})
		assert_almost_eq(block.progress_factor, 1.5, 0.001, id)


# --- im Arcade-Lauf ------------------------------------------------------------------------------------------------


func _ride(run: ArcadeRun, from_m: float, cadence: float, seconds: float) -> float:
	var d := from_m
	for i in range(roundi(seconds / DT)):
		d += 8.0 * DT
		run.advance(d, cadence, DT)
	return d


func _run(id: String, seed_value: int = 2) -> ArcadeRun:
	return ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0, 0.0,
			seed_value, [Encounters.find(id)])


func test_the_dice_draw_the_new_types_too() -> void:
	var seen := {}
	for seed_value in range(1, 30):
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, seed_value)
		for entry in run.planned:
			seen[entry["definition"]["block"]] = true
	assert_eq(seen.keys().size(), 3, "Zone halten, Durchbruch und Jagd im Pool")


func test_run_breakthrough_success_gives_points_and_failure_none() -> void:
	var run := _run("durchbruch_bruecke")
	var d := _ride(run, 0.0, 90.0, 6.4)
	assert_true(run.active["block"] is Breakthrough)
	_ride(run, d, 114.0, 6.2)
	assert_eq(run.results.size(), 1)
	assert_true(run.results[0]["succeeded"], "6 s über 108 rpm")
	assert_eq(run.points, 140)
	var weak := _run("durchbruch_bruecke")
	d = _ride(weak, 0.0, 90.0, 6.4)
	_ride(weak, d, 100.0, 18.2)
	assert_false(weak.results[0]["succeeded"], "100 rpm unter der Schwelle: weich verfehlt")
	assert_eq(weak.points, 0)
	assert_eq(weak.results[0]["loot"], {}, "ohne Fortschritt keine Beute")
	assert_false(weak.planned.is_empty(), "der Lauf geht weiter")


func test_run_chase_escaped_gives_points_and_loot_caught_none() -> void:
	var run := _run("jagd_verfolger")
	var d := _ride(run, 0.0, 90.0, 6.4)
	assert_true(run.active["block"] is Chase)
	_ride(run, d, 100.0, 8.0)
	assert_true(run.results[0]["succeeded"], "abgehängt")
	assert_eq(run.points, 140)
	assert_false(run.results[0]["loot"].is_empty(), "geschafft gibt sicher Beute")
	var caught := _run("jagd_verfolger")
	d = _ride(caught, 0.0, 90.0, 6.4)
	_ride(caught, d, 80.0, 6.0)
	assert_false(caught.results[0]["succeeded"], "eingeholt")
	assert_eq(caught.points, 0)
	assert_eq(caught.results[0]["loot"], {}, "eingeholt ohne Treten über der Schwelle: keine Beute")
	assert_eq(caught.summary_lines()[2], "Jagd 0/1")


func test_run_chase_time_up_without_pedalling_gives_no_loot_despite_the_head_start() -> void:
	# Der Vorsprung bleibt am Fensterende groß (Abstand ~0,88); der Lauf darf ihn nicht als Fortschritt für die Beute
	# werten (`loot_progress`, nicht `progress`) – über viele Würfel, damit ein falscher Wert sicher auffiele.
	var idle := {"id": "jagd_still", "block": Encounters.CHASE, "name": "Jagd", "threshold_at": 0.55, "escape_s": 12.0,
			"catch_s": 400.0, "window_s": 10.0, "start_gap": 0.9, "points": 140}
	for seed_value in range(1, 21):
		var run := ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0,
				0.0, seed_value, [idle])
		var d := _ride(run, 0.0, 90.0, 6.4)
		_ride(run, d, 90.0, 10.4)
		assert_eq(run.results.size(), 1, "Seed %d" % seed_value)
		assert_false(run.results[0]["succeeded"])
		assert_gt(run.results[0]["progress"], 0.8, "der Abstand bleibt sichtbar")
		assert_eq(run.results[0]["loot"], {}, "Seed %d: ohne Treten über der Schwelle keine Beute" % seed_value)


# --- Darstellung: Zugbrücke und Verfolger (Logik der Anzeige) --------------------------------------------------------


func test_drawbridge_leaf_geometry_and_motion() -> void:
	assert_almost_eq(Drawbridge.leaf_angle(0.0), PI / 2.0, 0.0001, "zu: Klappe steht senkrecht")
	assert_almost_eq(Drawbridge.leaf_angle(1.0), 0.0, 0.0001, "offen: Klappe liegt")
	var closed := Drawbridge.leaf_tip(0.0)
	assert_almost_eq(closed.y, Drawbridge.LEAF_LIFT_M + Drawbridge.LEAF_LENGTH_M, 0.001)
	assert_almost_eq(closed.z, 0.0, 0.001)
	var open := Drawbridge.leaf_tip(1.0)
	assert_almost_eq(open.y, Drawbridge.LEAF_LIFT_M, 0.001)
	assert_almost_eq(open.z, -Drawbridge.LEAF_LENGTH_M, 0.001, "liegt in Fahrtrichtung auf der Straße")
	var bridge := Drawbridge.new()
	add_child_autofree(bridge)
	bridge.follow(0.4)
	assert_eq([bridge.target, bridge.speed], [0.4, Drawbridge.FOLLOW_SPEED])
	bridge.release(false)
	assert_eq([bridge.target, bridge.speed], [1.0, Drawbridge.FAIL_SPEED], "nach Scheitern langsamer")
	bridge.release(true)
	assert_eq(bridge.speed, Drawbridge.SUCCESS_SPEED)
	bridge._process(10.0)
	assert_eq(bridge.open, 1.0)
	bridge.reset()
	assert_eq([bridge.open, bridge.target], [0.0, 0.0], "für den nächsten Durchbruch wieder zu")


func test_pursuer_distance_follows_the_gap_and_leaves() -> void:
	var pursuer := Pursuer.new()
	add_child_autofree(pursuer)
	assert_false(pursuer.visible, "ohne Jagd unsichtbar")
	pursuer.reset(0.4)
	assert_false(pursuer.active)
	assert_almost_eq(pursuer.behind_m, lerpf(Pursuer.CLOSE_M, Pursuer.FAR_M, 0.4), 0.001)
	var track := Track.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0))
	curve.add_point(Vector3(0.0, 0.0, -400.0))
	track.curve = curve
	add_child_autofree(track)
	pursuer.follow(track, 100.0, 0.0)
	assert_eq(pursuer.target_behind_m, Pursuer.CLOSE_M, "Abstand 0: auf den Fersen")
	pursuer.follow(track, 100.0, 1.0)
	assert_eq(pursuer.target_behind_m, Pursuer.FAR_M, "Abstand 1: abgehängt")
	pursuer.dismiss()
	assert_true(pursuer.leaving)
	pursuer._process(10.0)
	assert_false(pursuer.visible, "nach dem Abhängen außer Sicht")
	pursuer.reset(0.2)
	pursuer.follow(track, 100.0, 0.2)
	assert_true(pursuer.visible, "neue Jagd: wieder da")
