## Zielkadenzbereich und Intervall-Tore (#58) gegen den Fake-Bus: Training mit der kurzen Test-Einheit (je 20 s
## Aufwärmen, Hart, Ausrollen) durch die Hauptszene – Zonenbalken mit Zustand und Treffer der Phase, Starttor vor und
## Zieltor nach der harten Phase, Durchfahrt ±1 s am Phasenwechsel auch nach einem Tempowechsel im Anlauf. Dazu die
## ehrliche Wertung (ADR-0010): Fahrmodell und Bewertung sind mit Anzeige genau so wie ohne Szene gerechnet; die
## Gegenprobe zeigt, dass der Vergleich eine Abweichung fände.
## Gefahren wird in festen Schritten (DT) wie in test_training_ride.gd; den Tempowechsel macht die Kadenz am Bus-Client.
extends "res://tests/support/bus_test.gd"

const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const DT := 0.1


func _spawn_game(cadence: float) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 30.0))
	var game := spawn_ride(bus)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence == cadence, 3.0), "fährt")
	game.set_process(false)
	return game


## Kadenz je Fahrzeit der Einheit: 90 rpm, im Anlauf auf das Starttor ab 12 s 72 rpm, auf das Zieltor ab 31 s 104 rpm,
## im Ausrollen 80 rpm.
static func _cadence_at(elapsed_s: float) -> float:
	var t := snappedf(elapsed_s, DT)  # die Fahrzeit wächst in Schritten von DT; ohne Rundungsrest wechseln
	if t < 12.0:
		return 90.0
	if t < 20.0:
		return 72.0
	if t < 31.0:
		return 98.0
	return 104.0 if t < 40.0 else 80.0


func test_zone_bar_and_gates_over_the_bus() -> void:
	var game := await _spawn_game(90.0)
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(SHORT_UNIT))
	var gates: Array = game.training.gates()
	assert_eq(gates.map(func(g): return [g["time_s"], g["kind"]]), [[20.0, "start"], [40.0, "finish"]])
	# Fahrtpositionen je Schritt (Zeit der Einheit, Strecke), dazu die Lage jedes Tors beim Phasenwechsel.
	var trace := [[0.0, game.model.distance_m]]
	var gate_at := {}
	var seen := {}
	var index: int = game._gate_index
	while game.state == "riding":
		game.bus.cadence = _cadence_at(game.training.elapsed_s)
		game._ride(DT)
		game._update_view()
		trace.append([game.training.elapsed_s, game.model.distance_m])
		if game.gate_next.visible:
			seen[game.gate_next.kind] = true
		if game._gate_index != index:
			if index >= 0 and index < gates.size():
				assert_true(game.gate_passed.visible, "durchfahrenes Tor bleibt stehen")
				gate_at[index] = game.gate_passed.ride_m
			index = game._gate_index
		var readout: String = game.hud.readout()
		if is_equal_approx(game.training.elapsed_s, 15.0):  # Aufwärmen 80–100 rpm, 72 rpm
			assert_string_contains(readout, "Zone: zu niedrig (80–100 rpm, 72 rpm)")
			assert_string_contains(readout, "Treffer: 80 %", "12 von 15 s im Bereich – die Bewertung aus #37")
			assert_eq(game.gate_next.kind, CourseGate.KIND_START, "vor der harten Phase: Starttor")
			assert_eq(game.gate_next.text, "Start  95–105 rpm")
			assert_true(game.gate_next.visible)
		elif is_equal_approx(game.training.elapsed_s, 25.0):  # Hart 95–105 rpm, 98 rpm
			assert_string_contains(readout, "Zone: im Bereich (95–105 rpm, 98 rpm)")
			assert_string_contains(readout, "Treffer: 100 %")
			assert_eq(game.gate_next.kind, CourseGate.KIND_FINISH, "in der harten Phase: Zieltor voraus")
			assert_eq(game.gate_next.text, "Ziel")
		elif is_equal_approx(game.training.elapsed_s, 35.0):  # 104 rpm: noch im Bereich, dann 80 rpm im Ausrollen
			assert_string_contains(readout, "Zone: im Bereich (95–105 rpm, 104 rpm)")
		elif is_equal_approx(game.training.elapsed_s, 50.0):  # Ausrollen 70–95 rpm, 80 rpm
			assert_string_contains(readout, "Zone: im Bereich (70–95 rpm, 80 rpm)")
			assert_false(game.gate_next.visible, "nach dem letzten Intervall kein Tor mehr")
	assert_eq(game.state, "finished")
	assert_eq(seen.keys(), [CourseGate.KIND_START, CourseGate.KIND_FINISH], "beide Tore zu sehen")
	assert_false(game.hud.readout().contains("Zone:"), "im Ergebnis kein Zonenbalken")
	# Durchfahrt: wann erreichte der Fahrer die (festgesetzte) Lage jedes Tors? Am Phasenwechsel ±1 s.
	assert_eq(gate_at.size(), 2)
	for i in gate_at:
		var crossed := _time_at(trace, gate_at[i])
		assert_almost_eq(crossed, gates[i]["time_s"], 1.0,
				"%s-Tor: Durchfahrt %.2f s, Phasenwechsel %.0f s – trotz Tempowechsel" % [gates[i]["kind"], crossed, gates[i]["time_s"]])
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")
	assert_false(game.gate_next.visible or game.gate_passed.visible, "im Menü keine Tore")
	assert_false(game.hud.readout().contains("Zone:"))


## Zeit, zu der die Spur (Zeit, Strecke) die Strecke `ride_m` erreicht (linear zwischen zwei Schritten).
static func _time_at(trace: Array, ride_m: float) -> float:
	for i in range(1, trace.size()):
		if trace[i][1] >= ride_m:
			var a: Array = trace[i - 1]
			var b: Array = trace[i]
			return a[0] + (b[0] - a[0]) * (ride_m - a[1]) / maxf(b[1] - a[1], 1e-9)
	return INF


## Fahrt ohne jede Anzeige: dasselbe Fahrmodell, dieselbe Strecke, dieselbe Einheit, dieselbe Kadenz, dieselben
## Schritte wie `_ride` der Hauptszene – nur ohne Szene, HUD und Tore. Liefert [Strecke, Tempo, Bewertung je Phase …].
func _bare_ride(config: RideConfig, track: Track, cadence_at: Callable) -> Array:
	var model := RideModel.new(config, 0.0)
	var training := Training.new(Training.load_file(SHORT_UNIT))
	while not training.finished():
		var cadence: float = cadence_at.call(training.elapsed_s)
		var before := model.distance_m
		model.step(cadence, track.grade_at(model.distance_m), DT)
		var used := DT
		if training.remaining_total_s() < used:
			model.distance_m = before + (model.distance_m - before) * training.remaining_total_s() / DT
			used = training.remaining_total_s()
		training.advance(cadence, used)
	var result := [model.distance_m, model.speed_mps]
	for i in range(training.phases.size()):
		result.append(training.phase_score(i))
	return result


func test_display_has_no_effect_on_ride_model_and_score() -> void:
	var game := await _spawn_game(90.0)
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(SHORT_UNIT))
	var shown := {"zone": false, "gate": false}
	while game.state == "riding":
		game.bus.cadence = _cadence_at(game.training.elapsed_s)
		game._ride(DT)
		game._update_view()
		shown["zone"] = shown["zone"] or game.hud.readout().contains("Zone:")
		shown["gate"] = shown["gate"] or game.gate_next.visible
	assert_true(shown["zone"] and shown["gate"], "Zonenbalken und Tore waren zu sehen")
	var with_display := [game.model.distance_m, game.model.speed_mps]
	for i in range(game.training.phases.size()):
		with_display.append(game.training.phase_score(i))
	var without := _bare_ride(game.config, game.track, _cadence_at)
	assert_eq(with_display, without, "mit Anzeige exakt wie ohne Szene: Strecke, Tempo, Bewertung (ADR-0010)")
	assert_almost_eq(game.training.total_score(), (20.0 * 0.6 + 20.0 * 1.0 + 20.0 * 1.0) / 60.0, 1e-6)
	# Gegenprobe: wirkte etwas auf die Fahrt – hier 6 rpm mehr –, fände der Vergleich es.
	var other := _bare_ride(game.config, game.track, func(t): return _cadence_at(t) + 6.0)
	assert_ne(other[0], without[0], "Gegenprobe: andere Fahrt → andere Strecke")
	assert_ne(other.slice(2), without.slice(2), "Gegenprobe: andere Fahrt → andere Bewertung")
