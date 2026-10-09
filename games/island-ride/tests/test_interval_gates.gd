## Zielkadenzbereich und Intervall-Tore (#58) als reine Logik: Lage eines Tors aus Restzeit und Tempo (GatePlacement)
## samt Nachführen und Durchfahrt am Ereignis (±1 s, auch bei Tempowechsel im Anlauf), Tore der Einheiten
## (Training.gates: nur an Belastungen, nicht an Aufwärmen/Ausrollen), der Tor-Knoten quer zur Fahrt in beiden
## Richtungen (CourseGate, #34) und der Zustand des Zonenbalkens aus Kadenz und Bereich (ZoneBar).
extends GutTest

const DT := 0.05


func test_gate_lies_at_remaining_time_times_speed() -> void:
	assert_eq(GatePlacement.target_m(100.0, 10.0, 8.0), 180.0, "100 m + 10 s × 8 m/s")
	assert_eq(GatePlacement.target_m(100.0, 0.0, 8.0), 100.0, "beim Ereignis: an der Fahrtposition")
	assert_eq(GatePlacement.target_m(100.0, 10.0, 0.0), 100.0, "im Stand: am Fahrer")
	assert_eq(GatePlacement.target_m(100.0, -2.0, 8.0), 100.0, "Restzeit nie negativ")
	var placement := GatePlacement.new()
	assert_eq(placement.update(0.0, 30.0, 8.0), 240.0)
	assert_false(placement.locked, "weit voraus: wird nachgeführt")
	assert_true(placement.shown(0.0), "weit voraus: zu sehen")
	# Bei gleichem Tempo steht das Tor still, obwohl es nachgeführt wird.
	assert_almost_eq(placement.update(80.0, 20.0, 8.0), 240.0, 1e-9)
	# Langsamer: das Tor rückt näher.
	assert_almost_eq(placement.update(80.0, 20.0, 6.0), 200.0, 1e-9)
	placement.reset()
	assert_true(is_nan(placement.position_m), "reset vergisst die Lage")


func test_gate_stops_following_within_the_lock_distance() -> void:
	var placement := GatePlacement.new()
	var at := placement.update(0.0, 4.0, 8.0)  # 32 m und 4 s voraus: schon beim ersten Mal fest
	assert_eq(at, 32.0)
	assert_true(placement.locked)
	assert_true(placement.shown(0.0))
	assert_eq(placement.update(1.0, 3.9, 12.0), 32.0, "fest: ein Tempowechsel verschiebt das Tor nicht mehr")
	assert_eq(placement.update(20.0, 1.0, 2.0), 32.0)
	assert_true(placement.shown(20.0), "fest: bleibt zu sehen")
	placement.reset()
	assert_false(placement.locked)
	assert_almost_eq(placement.update(0.0, GatePlacement.LOCK_S + 0.1, 3.0), 30.3, 1e-9, "nah, aber das Ereignis noch weit: folgt")
	assert_false(placement.locked)
	assert_false(placement.shown(0.0), "nah und noch nicht fest: verborgen")
	assert_eq(placement.update(10.0, GatePlacement.LOCK_S, 3.0), 40.0)
	assert_true(placement.locked, "höchstens LOCK_AHEAD_M und LOCK_S entfernt: fest")


func test_gate_at_standstill_follows_hidden_until_the_rider_is_moving() -> void:
	# Beim Start der Einheit steht der Fahrer: das Tor stünde an seiner Position – es wartet verborgen.
	var placement := GatePlacement.new()
	assert_eq(placement.update(0.0, 20.0, 0.0), 0.0)
	assert_false(placement.locked, "im Stand nicht festsetzen")
	assert_false(placement.shown(0.0))
	assert_eq(placement.update(1.0, 19.0, 4.0), 77.0, "beim Anfahren nachgeführt")
	assert_true(placement.shown(1.0), "weit genug voraus: zu sehen")
	assert_almost_eq(placement.update(40.0, 9.0, 8.0), 112.0, 1e-9)
	assert_false(placement.locked)


## Anlauf auf ein Ereignis nach `event_s` mit Tempo `speed_at(t)` (m/s) über das Fahrmodell mit Trägheit; jeden
## Schritt wird das Tor nachgeführt, dann gefahren. Liefert die Zeit (s), zu der der Fahrer das Tor durchfährt, und
## die größte Verschiebung des Tors nach dem Festsetzen (m).
func _approach(event_s: float, speed_at: Callable, inertia_s: float = 1.5) -> Array:
	var config := RideConfig.new()
	config.k_kmh_per_rpm = 1.0
	config.inertia_s = inertia_s
	var model := RideModel.new(config)
	model.speed_mps = speed_at.call(0.0)
	var placement := GatePlacement.new()
	var t := 0.0
	var locked_at := NAN
	var drift := 0.0
	while t < event_s + 30.0:
		var gate := placement.update(model.distance_m, event_s - t, model.speed_mps)
		if placement.locked:
			if is_nan(locked_at):
				locked_at = gate
			drift = maxf(drift, absf(gate - locked_at))
		var before := model.distance_m
		model.step(speed_at.call(t) * RideModel.KMH_PER_MPS, 0.0, DT)  # k = 1 km/h je rpm: „Kadenz“ = Tempo in km/h
		if before < gate and model.distance_m >= gate:
			return [t + DT * (gate - before) / (model.distance_m - before), drift]
		t += DT
	return [INF, drift]


func test_passage_coincides_with_the_event_also_after_a_speed_change() -> void:
	var cases := {
		"gleiches Tempo": func(_t): return 8.0,
		"mitten im Anlauf langsamer (8 → 5 m/s)": func(t): return 8.0 if t < 12.0 else 5.0,
		"mitten im Anlauf schneller (6 → 10 m/s)": func(t): return 6.0 if t < 15.0 else 10.0,
		"mehrfach wechselnd": func(t): return 7.0 + 3.0 * sin(t * 0.4) if t < 22.0 else 7.0,
	}
	for name in cases:
		var result := _approach(30.0, cases[name])
		assert_almost_eq(result[0], 30.0, 1.0, "%s: Durchfahrt ±1 s am Ereignis (%.2f s)" % [name, result[0]])
		assert_eq(result[1], 0.0, "%s: festgesetzt springt das Tor nicht" % name)
	# Ohne Nachführen (Lage nur einmal zu Beginn) verfehlte ein Tempowechsel das Ereignis deutlich – die Gegenprobe.
	var once := GatePlacement.target_m(0.0, 30.0, 8.0)
	var slow_after := 12.0 * 8.0 + 18.0 * 5.0  # 8 m/s bis 12 s, dann 5 m/s
	assert_gt(absf(once - slow_after) / 5.0, 5.0, "ohne Nachführen > 5 s daneben")


func test_gate_stands_where_the_rider_passes_in_both_directions() -> void:
	for direction in [Track.DIRECTION_CW, Track.DIRECTION_CCW]:
		var track := Track.new()
		IslandCourse.apply_to(track, direction)
		add_child_autofree(track)
		var gate := CourseGate.new()
		track.add_child(gate)
		gate.configure(CourseGate.KIND_START, "Start  95–105 rpm")
		for ride_m in [500.0, 3000.0, 7400.0]:
			gate.place(track, ride_m)
			assert_eq(gate.ride_m, ride_m)
			assert_true(gate.position.is_equal_approx(track.ride_position_at(ride_m)), "%s: auf der Fahrerposition" % direction)
			# Das Tor schaut mit -Z in Fahrtrichtung, das Banner (+Z) zum anfahrenden Fahrer.
			var forward := track.ride_position_at(ride_m + 5.0) - track.ride_position_at(ride_m)
			var facing := -gate.basis.z
			assert_gt(Vector2(facing.x, facing.z).normalized().dot(Vector2(forward.x, forward.z).normalized()), 0.98,
					"%s %d m: quer zur Fahrt, Banner zum Fahrer" % [direction, ride_m])
		# GatePlacement rechnet in Fahrtposition: in beiden Richtungen landet das Tor dort, wo der Fahrer ankommt.
		var placement := GatePlacement.new()
		var at := placement.update(1000.0, 20.0, 8.0)
		gate.place(track, at)
		assert_true(gate.position.is_equal_approx(track.ride_position_at(1000.0 + 160.0)), "%s: 160 m voraus" % direction)


func test_start_and_finish_gates_look_different() -> void:
	var start := CourseGate.new()
	add_child_autofree(start)
	start.configure(CourseGate.KIND_START, "Start  95–105 rpm")
	var finish := CourseGate.new()
	add_child_autofree(finish)
	finish.configure(CourseGate.KIND_FINISH, "Ziel")
	assert_not_null(start.find_child("Banner", true, false), "Starttor: durchgehendes Banner")
	assert_null(finish.find_child("Banner", true, false))
	assert_not_null(finish.find_child("Karo0_1", true, false), "Zieltor: kariertes Banner")
	assert_eq((start.find_child("Text", true, false) as Label3D).text, "Start  95–105 rpm")
	assert_ne(CourseGate.COLOR_START, CourseGate.COLOR_FINISH)
	# Anders als die Segment-Torbögen (#33): blau und mit weißem Banner.
	for color in [CourseGate.COLOR_START, CourseGate.COLOR_FINISH]:
		assert_ne(color, Color(0.12, 0.3, 0.62))
	finish.configure(CourseGate.KIND_START, "Start  87–93 rpm")
	assert_not_null(finish.find_child("Banner", true, false), "Art wechselt: neu gebaut")
	assert_null(finish.find_child("Karo0_1", true, false))


## Tore aller drei Einheiten: Starttor zu Beginn jeder Belastung, Zieltor an ihrem Ende; keins an Aufwärmen/Ausrollen
## allein und keins an einer Erholung, die keine Belastung beginnt oder beendet.
func test_gates_only_at_work_phases_for_all_three_units() -> void:
	var units := Training.load_all()
	assert_eq(units.size(), 3)
	var expected := {
		"Intervalle kurz": 20,  # 10 × Start und Ziel
		"Pyramide": 8,  # 7 Starttore (das nächste Intervall beginnt, wo das vorige endet) und 1 Zieltor
		"Tempo-Blöcke": 6,
	}
	for unit in units:
		var training := Training.new(unit)
		var gates := training.gates()
		assert_eq(gates.size(), expected[unit["name"]], unit["name"])
		var ends := []
		var end := 0.0
		for phase in training.phases:
			end += phase["duration_s"]
			ends.append(end)
		for gate in gates:
			var i: int = gate["phase"]
			var before: Dictionary = training.phases[i - 1]
			var after: Dictionary = training.phases[i]
			assert_eq(gate["time_s"], ends[i - 1], "%s: am Phasenwechsel" % unit["name"])
			if gate["kind"] == Training.GATE_START:
				assert_eq(after["kind"], Training.KIND_WORK, "%s: Starttor vor einer Belastung" % unit["name"])
				assert_eq(gate["text"], "Start  %s" % Training.target_text(after))
			else:
				assert_eq(gate["kind"], Training.GATE_FINISH)
				assert_eq(before["kind"], Training.KIND_WORK, "%s: Zieltor nach einer Belastung" % unit["name"])
				assert_ne(after["kind"], Training.KIND_WORK)
				assert_eq(gate["text"], "Ziel")
		# Jede Belastung hat vorn ein Tor, und eins am Ende (Zieltor oder das Starttor der nächsten).
		var times := gates.map(func(g): return g["time_s"])
		for i in range(training.phases.size()):
			if training.phases[i]["kind"] == Training.KIND_WORK:
				assert_has(times, ends[i - 1], "%s: Tor vor %s" % [unit["name"], training.phases[i]["name"]])
				assert_has(times, ends[i], "%s: Tor nach %s" % [unit["name"], training.phases[i]["name"]])
		assert_does_not_have(times, ends[-1], "%s: kein Tor am Ende der Einheit" % unit["name"])
	# Intervalle kurz: Start → Ziel abwechselnd, das erste nach dem Aufwärmen.
	var short := Training.new(units[0]).gates()
	assert_eq(short[0], {"time_s": 480.0, "kind": Training.GATE_START, "text": "Start  95–105 rpm", "phase": 1})
	assert_eq(short[1], {"time_s": 510.0, "kind": Training.GATE_FINISH, "text": "Ziel", "phase": 2})
	assert_eq(short[-1]["time_s"], 480.0 + 19 * 30.0, "Zieltor des 10. Intervalls")
	assert_eq(CourseGate.KIND_START, Training.GATE_START)
	assert_eq(CourseGate.KIND_FINISH, Training.GATE_FINISH)


func test_zone_state_from_cadence_and_range_with_inclusive_limits() -> void:
	assert_eq(ZoneBar.zone_state(94.9, 95.0, 105.0), ZoneBar.BELOW)
	assert_eq(ZoneBar.zone_state(95.0, 95.0, 105.0), ZoneBar.INSIDE, "untere Grenze gehört dazu")
	assert_eq(ZoneBar.zone_state(100.0, 95.0, 105.0), ZoneBar.INSIDE)
	assert_eq(ZoneBar.zone_state(105.0, 95.0, 105.0), ZoneBar.INSIDE, "obere Grenze gehört dazu")
	assert_eq(ZoneBar.zone_state(105.1, 95.0, 105.0), ZoneBar.ABOVE)
	assert_eq(ZoneBar.zone_state(90.0, 90.0, 90.0), ZoneBar.INSIDE, "Bereich aus einem Wert")
	# Gleich der Bewertung des Trainings (#37): im Bereich ⇔ Training.on_target.
	var phase := {"cadence_min": 95.0, "cadence_max": 105.0}
	for rpm in [0.0, 94.99, 95.0, 99.5, 105.0, 105.01, 140.0]:
		assert_eq(ZoneBar.zone_state(rpm, 95.0, 105.0) == ZoneBar.INSIDE, Training.on_target(phase, rpm), "%s rpm" % rpm)


func test_zone_state_differs_in_color_and_shape() -> void:
	var colors := {}
	var shapes := {}
	var texts := {}
	for zone in [ZoneBar.BELOW, ZoneBar.INSIDE, ZoneBar.ABOVE]:
		colors[ZoneBar.state_color(zone)] = zone
		shapes[ZoneBar.marker_shape(zone)] = zone
		texts[ZoneBar.state_text(zone)] = zone
	assert_eq(colors.size(), 3, "drei Farben")
	assert_eq(shapes.size(), 3, "drei Formen")
	assert_eq(texts.size(), 3, "drei Wörter")
	assert_eq(ZoneBar.marker_shape(ZoneBar.BELOW), ZoneBar.SHAPE_ARROW_UP, "darunter: Pfeil hoch")
	assert_eq(ZoneBar.marker_shape(ZoneBar.INSIDE), ZoneBar.SHAPE_CHECK, "im Bereich: Haken")
	assert_eq(ZoneBar.marker_shape(ZoneBar.ABOVE), ZoneBar.SHAPE_ARROW_DOWN, "darüber: Pfeil runter")


func test_zone_scale_reaches_beyond_the_range_and_clamps_the_marker() -> void:
	assert_eq(ZoneBar.scale_range(95.0, 105.0), Vector2(83.0, 117.0), "mindestens MIN_MARGIN zu beiden Seiten")
	assert_eq(ZoneBar.scale_range(75.0, 95.0), Vector2(55.0, 115.0), "sonst um die Breite des Bereichs")
	assert_almost_eq(ZoneBar.value_x(100.0, 95.0, 105.0, 340.0), 170.0, 1e-4, "Mitte des Bereichs in der Mitte")
	assert_eq(ZoneBar.value_x(0.0, 95.0, 105.0, 340.0), 0.0, "weit darunter: am linken Rand")
	assert_eq(ZoneBar.value_x(200.0, 95.0, 105.0, 340.0), 340.0, "weit darüber: am rechten Rand")
	assert_lt(ZoneBar.value_x(94.0, 95.0, 105.0, 340.0), ZoneBar.value_x(95.0, 95.0, 105.0, 340.0))
	var bar := ZoneBar.new()
	add_child_autofree(bar)
	bar.show_zone(95.0, 105.0, 92.0)
	assert_eq(bar.state(), ZoneBar.BELOW)
	bar.show_zone(95.0, 105.0, 110.0)
	assert_eq(bar.state(), ZoneBar.ABOVE)
