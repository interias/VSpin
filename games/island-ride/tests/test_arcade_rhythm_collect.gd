## Die Bausteine Takt-Tore und Sammeln (#48) als reine Logik: Treffer im Takt bzw. Magnetradius aus der Kadenz – Erfolg,
## weiches Scheitern, Pause, Kadenzbereich-Wächter für Zone und Rampe (Positiv- und Gegenprobe), Ausrüstung wirkt nur
## mit Kadenz (Gegenprobe), Stufen, Begegnungen als Daten und der Arcade-Lauf (Punkte, Beute). Die Darstellung und die
## Simulator-Szenarien stehen in test_arcade_rhythm_collect_ride.gd.
extends GutTest

const DT := 0.1


## Kadenz `cadence` für `seconds` in festen Schritten.
func _feed(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


## Fährt `seconds` und gibt zu jeder Zeit `cadence_at.call(t)` (t = Zeit im Baustein) vor.
func _play(block: ChallengeBlock, seconds: float, cadence_at: Callable) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence_at.call(block.elapsed_s), DT)


# --- Takt-Tore -----------------------------------------------------------------------------------------------------


## 5 Tore, 4 nötig, Zone 80–100 rpm, erster Schlag bei 6 s, alle 5 s, Fenster ±1 s.
func _rhythm(need: int = 4) -> RhythmGates:
	return RhythmGates.new(80.0, 100.0, 5, need, 6.0, 5.0, 1.0)


## Kadenz im Takt: `high` im Fenster (±1 s) um jeden Schlag von `block`, sonst `low`.
func _on_the_beat(block: RhythmGates, high: float, low: float) -> Callable:
	return func(t: float) -> float:
		for k in range(block.beats):
			if absf(t - block.beat_time(k)) <= 1.0:
				return high
		return low


func test_rhythm_hits_every_gate_in_the_zone_and_succeeds_at_the_end() -> void:
	var block := _rhythm()
	_feed(block, 90.0, 4.8)
	assert_eq(block.state, ChallengeBlock.RUNNING)
	assert_eq(block.progress(), 0.0, "vor dem Fenster des ersten Schlags kein Treffer")
	_feed(block, 90.0, 0.4)
	assert_eq(block.state_of(0), RhythmGates.HIT, "im Fenster in der Zone: getroffen")
	assert_almost_eq(block.progress(), 0.25, 0.001, "ein Treffer von vier nötigen")
	_feed(block, 90.0, 25.0)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)
	assert_eq(block.hits, 5)
	assert_eq(block.progress(), 1.0)
	assert_almost_eq(block.elapsed_s, block.end_s(), 0.001, "Erfolg erst mit dem Ende der Folge")
	assert_eq(block.remaining_s(), 0.0)


func test_rhythm_is_free_between_the_beats_but_the_beat_counts() -> void:
	# Der Takt zählt, nicht das Halten: locker 65 rpm zwischen den Schlägen, im Fenster 90 rpm.
	var block := _rhythm(5)
	_play(block, 40.0, _on_the_beat(block, 90.0, 65.0))
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "alle fünf im Takt")
	assert_eq(block.hits, 5)
	# Gegenprobe: dieselbe Kadenz stetig bei 65 rpm trifft kein Tor – nur das Fenster zählt, nicht irgendwann.
	var steady := _rhythm(5)
	_feed(steady, 65.0, 40.0)
	assert_eq(steady.hits, 0)
	# Gegenprobe: im Takt versetzt (zwischen den Schlägen hoch, im Fenster niedrig) trifft ebenfalls nichts.
	var off := _rhythm(1)
	_play(off, 40.0, func(t: float) -> float: return 65.0 if absf(fposmod(t - 6.0, 5.0) - 2.5) > 1.0 else 90.0)
	assert_eq(off.hits, 0, "verkehrt herum: nie im Fenster in der Zone")
	assert_eq(off.state, ChallengeBlock.FAILED)


func test_rhythm_window_edges_and_zone_edges() -> void:
	var early := _rhythm(1)
	_feed(early, 60.0, 5.0)  # bis 5,0 s: Fensteranfang (6 − 1) – noch außerhalb
	_feed(early, 80.0, 0.2)  # Zone-Grenze 80 rpm zählt, 5,0–5,2 s liegt im Fenster
	assert_eq(early.state_of(0), RhythmGates.HIT, "Grenze eingeschlossen, im Fenster")
	var before := _rhythm(1)
	_feed(before, 90.0, 4.8)  # nur vor dem Fenster in der Zone
	_feed(before, 79.9, 2.0)
	assert_eq(before.state_of(0), RhythmGates.PENDING, "79,9 rpm ist außerhalb, davor zählt nicht")
	var after := _rhythm(1)
	_feed(after, 60.0, 7.0)
	_feed(after, 90.0, 0.2)
	assert_eq(after.state_of(0), RhythmGates.MISSED, "nach dem Fenster zu spät")
	assert_eq(after.hits, 0)


func test_rhythm_fails_softly_as_soon_as_the_need_cannot_be_reached() -> void:
	var block := _rhythm(4)
	_feed(block, 60.0, 17.0)  # zwei Schläge verpasst (7, 12): von 5 nur noch 3 möglich, nötig 4
	assert_eq(block.state, ChallengeBlock.FAILED, "vor dem Ende verfehlt")
	assert_lt(block.elapsed_s, block.end_s(), "sofort, nicht erst am Ende")
	assert_eq(block.progress(), 0.0)
	assert_eq(block.hits, 0)
	_feed(block, 90.0, 20.0)
	assert_eq(block.hits, 0, "nach dem Ende wirkungslos")
	# Genau verfehlt: drei von fünf bei nötigen vier.
	var close := _rhythm(4)
	_play(close, 40.0, func(t: float) -> float:
		return 90.0 if absf(t - 6.0) <= 1.0 or absf(t - 11.0) <= 1.0 or absf(t - 16.0) <= 1.0 else 60.0)
	assert_eq(close.state, ChallengeBlock.FAILED)
	assert_eq(close.hits, 3)
	assert_almost_eq(close.progress(), 0.75, 0.001)


func test_rhythm_pause_changes_nothing() -> void:
	var block := _rhythm()
	_feed(block, 90.0, 6.5)
	var elapsed := block.elapsed_s
	var hits := block.hits
	for i in range(1000):
		block.update(0.0, 0.0)  # Pause: kein Zeitschritt
	assert_eq([block.elapsed_s, block.hits, block.state], [elapsed, hits, ChallengeBlock.RUNNING])
	assert_eq(block.time_to_beat(1), 11.0 - elapsed)


func test_rhythm_gear_counts_hits_more_but_only_with_cadence_in_the_zone() -> void:
	var plain := _rhythm(4)
	_play(plain, 40.0, func(t: float) -> float: return 90.0 if t < 12.0 else 60.0)  # Schläge 1 und 2
	assert_eq(plain.state, ChallengeBlock.FAILED, "ohne Ausrüstung: 2 von nötigen 4")
	var geared := _rhythm(4)
	geared.progress_factor = 2.0
	_play(geared, 40.0, func(t: float) -> float: return 90.0 if t < 12.0 else 60.0)
	assert_eq(geared.state, ChallengeBlock.SUCCEEDED, "mit Ausrüstung zählen zwei Treffer doppelt")
	assert_eq(geared.hits, 2)
	assert_almost_eq(geared.credit, 4.0, 0.001)
	# Gegenprobe: ohne Kadenz in der Zone ändert die Ausrüstung nichts – weder Fortschritt noch Erfolg.
	for cadence in [0.0, 60.0, 79.9, 100.1, 140.0]:
		var without := _rhythm(4)
		var geared_off := _rhythm(4)
		geared_off.progress_factor = 3.0
		_feed(without, cadence, 40.0)
		_feed(geared_off, cadence, 40.0)
		assert_eq([geared_off.state, geared_off.progress(), geared_off.hits, geared_off.credit],
				[without.state, without.progress(), without.hits, without.credit], "%s rpm" % cadence)
		assert_eq(geared_off.state, ChallengeBlock.FAILED)
		assert_eq(geared_off.progress(), 0.0)
		assert_eq(geared_off.loot_progress(), 0.0, "keine Beute")


func test_rhythm_windows_never_overlap_and_the_need_is_clamped() -> void:
	var block := RhythmGates.new(80.0, 100.0, 3, 9, 2.0, 0.5, 2.0)
	assert_gte(block.interval_s, 2.0 * block.tolerance_s, "Fenster überlappen nicht")
	assert_eq(block.need, 3, "nötig höchstens so viele wie Tore")
	assert_eq(RhythmGates.new(80.0, 100.0, 0, 0, 1.0, 5.0, 1.0).beats, 1, "mindestens ein Tor")


# --- Sammeln -------------------------------------------------------------------------------------------------------


## Rampe 80–120 rpm: Radius 1 m bei 80, 5 m bei 120; 6 Objekte alle 2 s ab 2 s, nötig 4.
func _collect(need: int = 4) -> Collect:
	return Collect.new(80.0, 120.0, 1.0, 5.0, [0.5, -2.0, 3.0, -4.0, 1.0, 4.5], need, 2.0, 2.0)


func test_collect_radius_grows_linearly_with_the_cadence() -> void:
	var block := _collect()
	assert_eq(block.radius_for(0.0), 0.0, "ohne Kadenz kein Magnet")
	assert_eq(block.radius_for(79.9), 0.0, "unter der Rampe kein Magnet")
	assert_almost_eq(block.radius_for(80.0), 1.0, 0.001)
	assert_almost_eq(block.radius_for(100.0), 3.0, 0.001, "Mitte der Rampe: Mitte der Radien")
	assert_almost_eq(block.radius_for(110.0), 4.0, 0.001)
	assert_almost_eq(block.radius_for(120.0), 5.0, 0.001)
	assert_almost_eq(block.radius_for(150.0), 5.0, 0.001, "darüber nicht größer")
	assert_lt(block.radius_for(90.0), block.radius_for(95.0), "monoton")


func test_collect_picks_up_what_lies_in_the_radius_when_riding_past() -> void:
	var block := _collect(4)
	_feed(block, 100.0, 2.0)  # Radius 3: Objekt 0 (0,5 m) bei 2 s
	assert_eq(block.state_of(0), Collect.COLLECTED)
	assert_eq(block.collected, 1)
	_feed(block, 100.0, 2.0)  # Objekt 1 (2 m): ja bei 4 s
	_feed(block, 100.0, 2.0)  # Objekt 2 (3 m): Grenze eingeschlossen
	assert_eq([block.state_of(1), block.state_of(2)], [Collect.COLLECTED, Collect.COLLECTED])
	_feed(block, 100.0, 2.0)  # Objekt 3 (4 m): zu weit
	assert_eq(block.state_of(3), Collect.MISSED, "außerhalb des Radius bleibt liegen")
	assert_eq(block.state, ChallengeBlock.RUNNING)
	_feed(block, 100.0, 4.0)  # Objekt 4 (1 m) ja, Objekt 5 (4,5 m) nein
	assert_eq(block.collected, 4)
	assert_eq(block.state, ChallengeBlock.SUCCEEDED, "4 von nötigen 4 – am Ende der Folge")
	assert_almost_eq(block.elapsed_s, 12.0, 0.001)
	assert_eq(block.progress(), 1.0)


func test_collect_uses_the_radius_at_the_moment_of_passing() -> void:
	# Hoch nur im Moment des Vorbeifahrens: die Kadenz zum Zeitpunkt zählt, nicht ein Durchschnitt.
	var block := _collect(3)
	_play(block, 20.0, func(t: float) -> float:
		return 120.0 if [4.0, 6.0, 8.0].any(func(p: float): return absf(t - p) <= 0.25) else 80.0)
	# Bei 80 rpm (Radius 1 m): Objekte 0 (0,5) und 4 (1) landen; bei 120 (5 m): 1, 2, 3 landen alle.
	assert_eq(block.state_of(1), Collect.COLLECTED)
	assert_eq(block.state_of(2), Collect.COLLECTED)
	assert_eq(block.state_of(3), Collect.COLLECTED)
	assert_eq(block.state_of(5), Collect.MISSED, "4,5 m bei 80 rpm: liegen geblieben")
	assert_eq(block.state, ChallengeBlock.SUCCEEDED)


func test_collect_fails_softly_with_too_little_cadence() -> void:
	var block := _collect(3)
	_feed(block, 85.0, 30.0)  # Radius 1,5 m: nur 0,5 und 1,0
	assert_eq(block.state, ChallengeBlock.FAILED, "am Ende zu wenig")
	assert_eq(block.collected, 2)
	assert_almost_eq(block.progress(), 2.0 / 3.0, 0.001)
	assert_almost_eq(block.elapsed_s, block.pass_time(5), 0.001, "erst mit dem letzten Objekt")
	# Ohne Kadenz nichts.
	var idle := _collect(1)
	_feed(idle, 0.0, 30.0)
	assert_eq(idle.state, ChallengeBlock.FAILED)
	assert_eq(idle.collected, 0)
	assert_eq(idle.progress(), 0.0)
	assert_eq(idle.loot_progress(), 0.0)
	# Früh scheitern, sobald es nicht mehr reicht: vier Objekte nötig, drei nacheinander liegengelassen.
	var early := _collect(4)
	_feed(early, 60.0, 8.0)
	assert_eq(early.state, ChallengeBlock.FAILED, "mit 3 Objekten übrig sind 4 nicht mehr zu erreichen")
	assert_lt(early.elapsed_s, early.pass_time(5), "vor dem letzten Objekt")


func test_collect_pause_changes_nothing() -> void:
	var block := _collect()
	_feed(block, 100.0, 3.0)
	var snapshot := [block.elapsed_s, block.collected, block.radius_m, block.state]
	for i in range(1000):
		block.update(120.0, 0.0)
	assert_eq([block.elapsed_s, block.collected, block.radius_m, block.state], snapshot)


func test_collect_gear_enlarges_the_radius_only_where_cadence_gives_one() -> void:
	var plain := _collect(4)
	var geared := _collect(4)
	geared.progress_factor = 1.5
	assert_almost_eq(geared.radius_for(100.0), 4.5, 0.001, "Radius × Faktor")
	_feed(plain, 90.0, 30.0)
	_feed(geared, 90.0, 30.0)
	assert_eq(plain.state, ChallengeBlock.FAILED, "90 rpm: Radius 2 m, nur 3 Objekte von nötigen 4")
	assert_eq(geared.state, ChallengeBlock.SUCCEEDED, "mit Ausrüstung 3 m: 4 Objekte")
	# Gegenprobe: ohne Kadenz in der Rampe bleibt der Radius 0 – mit und ohne Ausrüstung dasselbe Ergebnis.
	for cadence in [0.0, 40.0, 79.9]:
		var without := _collect(1)
		var huge := _collect(1)
		huge.progress_factor = 5.0
		_feed(without, cadence, 30.0)
		_feed(huge, cadence, 30.0)
		assert_eq(huge.radius_for(cadence), 0.0, "%s rpm: kein Radius" % cadence)
		assert_eq([huge.state, huge.collected, huge.progress()], [without.state, without.collected, without.progress()])
		assert_eq(huge.collected, 0)


func test_collect_needs_at_least_one_object_and_clamps_the_need() -> void:
	var block := Collect.new(80.0, 120.0, 1.0, 5.0, [], 5, 1.0, 1.0)
	assert_eq(block.count(), 1, "mindestens ein Objekt")
	assert_eq(block.need, 1)
	var flat := Collect.new(100.0, 90.0, 1.0, 4.0, [2.0], 1, 1.0, 1.0)
	assert_eq(flat.ramp_max, 100.0, "Rampe nie rückwärts")
	assert_eq(flat.radius_for(100.0), 4.0, "Rampe ohne Breite: ab ihrer Stelle der größte Radius")


# --- Wächter, Begegnungen als Daten, Stufen ------------------------------------------------------------------------


func _definitions(block_id: String) -> Array:
	return Encounters.CHALLENGES.filter(func(d): return d["block"] == block_id)


func test_both_blocks_are_data_in_the_registry_and_the_pool() -> void:
	assert_true(EncounterRegistry.TYPES.has("rhythm_gates"))
	assert_true(EncounterRegistry.TYPES.has("collect"))
	assert_eq(_definitions("rhythm_gates").map(func(d): return d["id"]), ["takt_ruhig", "takt_flott"])
	assert_eq(_definitions("collect").map(func(d): return d["id"]), ["sammeln_wiese", "sammeln_ufer"])
	var personal := CadenceRange.new()
	assert_true(Encounters.build(Encounters.find("takt_ruhig"), 1, personal) is RhythmGates)
	assert_true(Encounters.build(Encounters.find("sammeln_wiese"), 1, personal) is Collect)
	assert_eq(Encounters.target_text(Encounters.find("takt_ruhig"), Vector2(74.0, 94.0)), "74–94 rpm")
	assert_eq(Encounters.target_text(Encounters.find("sammeln_wiese"), Vector2(75.0, 120.0)), "ab 75 rpm")


func test_zone_and_ramp_are_guarded_by_the_personal_range() -> void:
	# Positivprobe: jede Zone der Takt-Tore und jede Rampe des Sammelns auf jeder Stufe in jedem wählbaren Bereich,
	# mit und ohne Ausrüstungsbreite, liegt im Bereich; Baustein und Anzeige stimmen überein.
	var definitions := _definitions("rhythm_gates") + _definitions("collect")
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for definition in definitions:
				for tier in [1, 2, 3]:
					for width in [0, 4, 10]:
						var gear := {"zone_width_rpm": width}
						var zone := Encounters.zone_for(definition, tier, range_, gear)
						assert_true(range_.contains_zone(zone.x, zone.y), "%s Stufe %d in %s" % [definition["id"],
								tier, range_.text()])
						assert_eq(Encounters.build(definition, tier, range_, gear).zone(), zone)
	# Gegenprobe: außerhalb liegende Daten werden in den Bereich geholt – eine Zone bei Lage 1,4 (168 rpm) und eine Rampe
	# unter dem Minimum.
	var personal := CadenceRange.new(60.0, 120.0)
	assert_gt(personal.at(1.4), 120.0, "ohne Wächter läge die Zone außerhalb")
	var high: Dictionary = _definitions("rhythm_gates")[0].duplicate()
	high["zone_at"] = 1.4
	assert_true(personal.contains_zone(Encounters.build(high, 1, personal).zone().x,
			Encounters.build(high, 1, personal).zone().y))
	assert_eq(Encounters.build(high, 1, personal).zone(), Vector2(100.0, 120.0), "Zone rückt mit ihrer Breite hinein")
	var low: Dictionary = _definitions("collect")[0].duplicate()
	low["threshold_at"] = -2.0
	assert_eq(Encounters.build(low, 1, personal).zone(), Vector2(60.0, 120.0), "Rampe nie unter dem Minimum")
	low["threshold_at"] = 1.5
	assert_eq(Encounters.build(low, 1, personal).zone(), Vector2(120.0, 120.0), "Rampe nie über dem Maximum")
	# Eigener Bereich: Rampe und Radius beziehen sich auf ihn, nicht auf feste rpm.
	var narrow := CadenceRange.new(45.0, 100.0)
	var ramp := Encounters.zone_for(Encounters.find("sammeln_wiese"), 1, narrow)
	assert_eq(ramp, Vector2(59.0, 100.0), "Schwelle 25 % von 45–100 (rund 59), Ende am Maximum")
	var block := Encounters.build(Encounters.find("sammeln_wiese"), 1, narrow) as Collect
	assert_eq(block.radius_for(100.0), 5.0, "oberes Bereichsende: größter Radius")
	assert_eq(block.radius_for(58.0), 0.0, "unter der Rampe nichts")


func test_tiers_scale_duration_points_and_zone_width() -> void:
	var personal := CadenceRange.new()
	var calm := Encounters.find("takt_ruhig")
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(calm, t, personal) as RhythmGates).beats), [5, 6, 8])
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(calm, t, personal) as RhythmGates).need), [4, 5, 6])
	assert_eq([1, 2, 3].map(func(t): return Encounters.zone_for(calm, t, personal)), [Vector2(74.0, 94.0),
			Vector2(77.0, 91.0), Vector2(79.0, 89.0)], "schmalere Zonen")
	assert_eq([1, 2, 3].map(func(t): return Encounters.points_for(calm, t)), [120, 240, 360])
	var meadow := Encounters.find("sammeln_wiese")
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(meadow, t, personal) as Collect).count()), [8, 10, 12])
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(meadow, t, personal) as Collect).need), [5, 6, 8])
	assert_eq([1, 2, 3].map(func(t): return (Encounters.build(meadow, t, personal) as Collect).ramp_min),
			[75.0, 78.0, 80.0], "höhere Stufe, spätere Rampe")
	assert_eq([1, 2, 3].map(func(t): return Encounters.points_for(meadow, t)), [110, 220, 330])


func test_build_gives_the_equipment_factor_to_both_blocks() -> void:
	var personal := CadenceRange.new()
	for id in ["takt_ruhig", "takt_flott", "sammeln_wiese", "sammeln_ufer"]:
		var block := Encounters.build(Encounters.find(id), 1, personal, {"progress_pct": 50})
		assert_almost_eq(block.progress_factor, 1.5, 0.001, id)
		assert_almost_eq(Encounters.build(Encounters.find(id), 1, personal).progress_factor, 1.0, 0.001)


func test_the_dice_draw_both_new_types() -> void:
	var seen := {}
	for seed_value in range(1, 40):
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, seed_value)
		for entry in run.planned:
			seen[entry["definition"]["block"]] = true
	assert_true(seen.has("rhythm_gates") and seen.has("collect"), "Takt-Tore und Sammeln im Standardpool")


# --- Lage der Markierungen (TimedMarkers) ---------------------------------------------------------------------------


## Fährt `steps` Schritte mit `speed` m/s ab Fahrtposition `from_m`, Baustein-Zeit ab `from_s`; Rückgabe: Fahrtposition.
func _drive_markers(markers: TimedMarkers, from_m: float, from_s: float, speed: float, steps: int) -> float:
	var d := from_m
	for i in range(steps):
		d += speed * DT
		markers.measure(d, from_s + (i + 1) * DT)
	return d


func test_markers_stand_where_the_rider_arrives_and_stay_unset_while_standing() -> void:
	var markers := TimedMarkers.new()
	markers.reset(3)
	markers.measure(100.0, 0.0)
	var d := _drive_markers(markers, 100.0, 0.0, 0.0, 20)  # im Stand
	assert_eq(markers.speed_mps, 0.0)
	assert_true(is_nan(markers.position_of(0, d, 3.0)), "im Stand keine Lage, auch nicht mit Restzeit unter LOCK_S")
	assert_false(markers.placements[0].locked, "und nicht festgesetzt")
	d = _drive_markers(markers, d, 2.0, 8.0, 5)  # fährt an
	assert_almost_eq(markers.speed_mps, 8.0, 0.01)
	assert_almost_eq(markers.position_of(0, d, 20.0), d + 160.0, 0.1, "Lage = Fahrtposition + Restzeit × Tempo")
	assert_false(markers.placements[0].locked, "noch weit voraus: wird nachgeführt")
	var at: float = markers.position_of(1, d, 4.0)
	assert_almost_eq(at, d + 32.0, 0.1)
	assert_true(markers.placements[1].locked, "innerhalb von 40 m und 10 s: fest")


func test_markers_survive_standing_and_restarting_and_a_pause() -> void:
	var markers := TimedMarkers.new()
	markers.reset(2)
	markers.measure(0.0, 0.0)
	var d := _drive_markers(markers, 0.0, 0.0, 8.0, 10)
	var fixed: float = markers.position_of(0, d, 3.0)  # fest
	var open: float = markers.position_of(1, d, 20.0)  # weit voraus, noch nachgeführt
	assert_true(markers.placements[0].locked)
	# Stehen bleiben: das Tempo fällt unter MIN_SPEED_MPS, feste und offene Lage bleiben wie sie waren.
	d = _drive_markers(markers, d, 1.0, 0.0, 40)
	assert_lt(markers.speed_mps, TimedMarkers.MIN_SPEED_MPS)
	assert_eq(markers.position_of(0, d, 0.0), fixed, "festes Tor springt nicht")
	assert_eq(markers.position_of(1, d, 2.0), open, "ein noch nicht festes Tor wird im Stand nicht auf den Fahrer gesetzt")
	# Pause: der Baustein steht (gleiche Zeit), die Fahrtposition ändert sich – das Tempo bleibt, kein Sprung.
	var before := markers.speed_mps
	markers.measure(d + 50.0, 5.0)
	markers.measure(d + 50.0, 5.0)
	assert_eq(markers.speed_mps, before, "in der Pause bleibt das Tempo")
	# Wieder anfahren: das Tempo kommt aus der Fahrt, nicht aus dem Weg der Pause.
	d = _drive_markers(markers, d + 50.0, 5.0, 8.0, 8)
	assert_almost_eq(markers.speed_mps, 8.0, 1.0, "Tempo der Fahrt (geglättet), nicht 50 m in einem Schritt")
	assert_true(markers.speed_mps >= TimedMarkers.MIN_SPEED_MPS)
	assert_almost_eq(markers.position_of(1, d, 20.0), d + 20.0 * markers.speed_mps, 0.1, "wieder nachgeführt")


# --- im Arcade-Lauf ------------------------------------------------------------------------------------------------


func _run(id: String, seed_value: int = 2) -> ArcadeRun:
	return ArcadeRun.new(1, CadenceRange.new(), [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}], 5000.0, 0.0,
			seed_value, [Encounters.find(id)])


## Fährt mit Kadenz `cadence_at(t)` (t = Laufzeit) bis `seconds` und bei 8 m/s; Rückgabe: Fahrtposition.
func _ride_run(run: ArcadeRun, seconds: float, cadence_at: Callable) -> float:
	var d := 0.0
	for i in range(roundi(seconds / DT)):
		d += 8.0 * DT
		run.advance(d, cadence_at.call(run.elapsed_s), DT)
	return d


func test_run_rhythm_gates_success_gives_points_and_loot_failure_none() -> void:
	var run := _run("takt_ruhig")
	# Der Baustein beginnt am Startpunkt (50 m bei 8 m/s = ~6,3 s); im Fenster der Schläge 85 rpm, sonst locker.
	_ride_run(run, 60.0, func(t: float) -> float:
		if run.active.is_empty():
			return 70.0
		var block: RhythmGates = run.active["block"]
		for k in range(block.beats):
			if absf(block.elapsed_s - block.beat_time(k)) <= 0.9:
				return 85.0
		return 70.0)
	assert_eq(run.results.size(), 1)
	assert_true(run.results[0]["succeeded"], "alle fünf im Takt")
	assert_eq(run.points, 120)
	assert_false(run.results[0]["loot"].is_empty(), "geschafft gibt sicher Beute")
	assert_eq(run.results[0]["progress"], 1.0)
	var missed := _run("takt_ruhig")
	_ride_run(missed, 60.0, func(_t: float) -> float: return 65.0)
	assert_false(missed.results[0]["succeeded"], "65 rpm unter der Zone 74–94: nie getroffen")
	assert_eq(missed.points, 0)
	assert_eq(missed.results[0]["loot"], {}, "ohne einen Treffer keine Beute")
	assert_false(missed.planned.is_empty(), "weich: der Lauf geht weiter")


func test_run_collect_success_gives_points_and_loot_failure_none() -> void:
	var run := _run("sammeln_wiese")
	_ride_run(run, 60.0, func(_t: float) -> float: return 108.0)  # Radius 4,7 m: 7 von 8
	assert_true(run.results[0]["succeeded"])
	assert_eq(run.points, 110)
	assert_false(run.results[0]["loot"].is_empty(), "geschafft gibt sicher Beute")
	var few := _run("sammeln_wiese")
	_ride_run(few, 60.0, func(_t: float) -> float: return 78.0)  # Radius 1,3 m: nur 2 von 8
	assert_false(few.results[0]["succeeded"], "zu wenig Kadenz: zu wenig gesammelt")
	assert_eq(few.points, 0)
	assert_gt(few.results[0]["progress"], 0.0, "etwas gesammelt")
	assert_false(few.planned.is_empty(), "weich: der Lauf geht weiter")
	# Ohne Treten: keine Punkte, keine Beute, über viele Würfel.
	for seed_value in range(1, 21):
		var idle := _run("sammeln_wiese", seed_value)
		_ride_run(idle, 60.0, func(_t: float) -> float: return 0.0)
		assert_eq(idle.results.size(), 1, "Seed %d" % seed_value)
		assert_false(idle.results[0]["succeeded"])
		assert_eq(idle.results[0]["loot"], {}, "Seed %d: ohne Kadenz keine Beute" % seed_value)
		assert_eq(idle.points, 0)


func test_run_gear_without_cadence_gives_nothing_for_both_blocks() -> void:
	# Ausrüstung ersetzt nie das Treten: mit hohem progress_pct, aber ohne Kadenz bleibt alles leer.
	for id in ["takt_flott", "sammeln_ufer"]:
		for seed_value in range(1, 11):
			var run := _run(id, seed_value)
			run.gear = {"progress_pct": 60, "zone_width_rpm": 10, "points_pct": 100, "luck_pct": 100}
			_ride_run(run, 80.0, func(_t: float) -> float: return 0.0)
			assert_eq(run.results.size(), 1, "%s Seed %d" % [id, seed_value])
			assert_false(run.results[0]["succeeded"])
			assert_eq(run.points, 0)
			assert_eq(run.results[0]["loot"], {}, "%s: keine Beute ohne Kadenz" % id)
