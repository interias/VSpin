## Training (#37) als reine Logik: Ablauf einer Einheit (Phasenfolge, Restzeit, nächste Phase, Zeitpunkt der Ansage,
## Ende nach dem Ausrollen), Bewertung je Phase und gesamt (auch als Teilbewertung), das Dateiformat und die drei
## Einheiten aus `res://trainings` laut Beschreibung.
extends GutTest

const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const BROKEN_PATH := "user://test_training_broken.json"


func after_each() -> void:
	if FileAccess.file_exists(BROKEN_PATH):
		DirAccess.remove_absolute(BROKEN_PATH)


## Einheit aus Phasen (Name, Dauer, Zielbereich), ohne Datei.
func _unit(phases: Array) -> Dictionary:
	var result := []
	for p in phases:
		result.append({"name": p[0], "kind": p[3] if p.size() > 3 else Training.KIND_WORK, "duration_s": float(p[1]),
				"cadence_min": float(p[2][0]), "cadence_max": float(p[2][1]), "announcement": "Ansage %s" % p[0],
				"group": ""})
	return {"name": "Test", "description": "", "phases": result}


func _short() -> Training:
	return Training.new(Training.load_file(SHORT_UNIT))


func test_phases_follow_in_order_with_remaining_time_and_next_phase() -> void:
	var training := _short()
	assert_eq(training.duration_s(), 60.0)
	assert_eq(training.phase()["name"], "Aufwärmen", "Beginn mit dem Aufwärmen")
	assert_eq(training.next_phase()["name"], "Hart")
	assert_eq(training.remaining_s(), 20.0)
	training.advance(90.0, 7.5)
	assert_eq(training.phase_index(), 0)
	assert_almost_eq(training.remaining_s(), 12.5, 0.0001, "Restzeit der Phase")
	assert_almost_eq(training.remaining_total_s(), 52.5, 0.0001, "Restzeit der Einheit")
	training.advance(90.0, 12.5)
	assert_eq(training.phase()["name"], "Hart", "genau an der Grenze: nächste Phase")
	assert_eq(training.remaining_s(), 20.0)
	assert_eq(training.next_phase()["name"], "Ausrollen")
	training.advance(90.0, 20.0)
	assert_eq(training.phase()["name"], "Ausrollen")
	assert_eq(training.next_phase(), {}, "nach dem Ausrollen kommt nichts mehr")
	assert_false(training.finished())


func test_a_step_over_a_phase_boundary_is_split() -> void:
	var training := _short()
	training.advance(90.0, 18.0)
	training.advance(100.0, 4.0)  # 2 s Aufwärmen (im Bereich), 2 s Hart (im Bereich)
	assert_almost_eq(training.ridden_s[0], 20.0, 0.0001)
	assert_almost_eq(training.ridden_s[1], 2.0, 0.0001, "der Rest des Schritts zählt für die nächste Phase")
	assert_almost_eq(training.on_target_s[1], 2.0, 0.0001)
	training.advance(90.0, 50.0)  # über zwei Grenzen und das Ende hinaus
	assert_almost_eq(training.ridden_s[1], 20.0, 0.0001)
	assert_almost_eq(training.ridden_s[2], 20.0, 0.0001)
	assert_almost_eq(training.elapsed_s, 60.0, 0.0001, "nicht über das Ende hinaus")


func test_announcement_comes_ahead_of_the_change_and_at_the_change() -> void:
	var training := _short()
	assert_eq(training.announcement(), "Widerstand leicht, locker einrollen", "zu Beginn die eigene Ansage")
	training.advance(90.0, Training.ANNOUNCE_HOLD_S)
	assert_eq(training.announcement(), "", "danach Ruhe")
	training.advance(90.0, 20.0 - Training.ANNOUNCE_AHEAD_S - Training.ANNOUNCE_HOLD_S - 0.1)
	assert_eq(training.announcement(), "", "kurz vor der Vorankündigung noch nichts")
	training.advance(90.0, 0.1)
	assert_eq(training.phase()["name"], "Aufwärmen")
	assert_eq(training.announcement(), "In 10 s: Widerstand 2 Stufen hoch, 100 rpm halten",
			"ANNOUNCE_AHEAD_S vor dem Wechsel: die Ansage der nächsten Phase")
	training.advance(90.0, 7.5)
	assert_eq(training.announcement(), "In 3 s: Widerstand 2 Stufen hoch, 100 rpm halten", "Countdown aufgerundet")
	training.advance(90.0, 2.5)
	assert_eq(training.phase()["name"], "Hart")
	assert_eq(training.announcement(), "Widerstand 2 Stufen hoch, 100 rpm halten", "beim Wechsel noch einmal")
	training.advance(90.0, 40.0)
	assert_eq(training.announcement(), "", "nach dem Ende keine Ansage")


func test_announcement_ahead_wins_in_short_phases() -> void:
	var training := Training.new(_unit([["A", 30, [80, 90]], ["B", 8, [90, 100]], ["C", 30, [80, 90]]]))
	training.advance(85.0, 30.0)
	assert_eq(training.announcement(), "In 8 s: Ansage C", "eine kurze Phase kündigt sofort die nächste an")


func test_ends_after_the_cooldown() -> void:
	var training := _short()
	training.advance(90.0, 59.9)
	assert_false(training.finished(), "noch im Ausrollen")
	assert_eq(training.phase()["kind"], Training.KIND_COOLDOWN)
	training.advance(90.0, 0.1)
	assert_true(training.finished(), "nach dem Ausrollen zu Ende")
	var before := training.on_target_s.duplicate()
	training.advance(90.0, 10.0)
	assert_eq(training.on_target_s, before, "nach dem Ende zählt nichts mehr")
	assert_eq(training.phase()["name"], "Ausrollen", "die letzte Phase bleibt stehen")
	assert_eq(training.remaining_s(), 0.0)


func test_exactly_in_range_scores_100_and_outside_scores_0() -> void:
	var unit := _unit([["A", 10, [85, 90]], ["B", 10, [85, 90]], ["C", 10, [85, 90]], ["D", 10, [85, 90]]])
	var training := Training.new(unit)
	training.advance(85.0, 10.0)  # untere Grenze
	training.advance(90.0, 10.0)  # obere Grenze
	training.advance(84.9, 10.0)  # knapp darunter
	training.advance(90.1, 10.0)  # knapp darüber
	assert_eq(training.phase_score(0), 1.0, "auf der unteren Grenze: 100 %")
	assert_eq(training.phase_score(1), 1.0, "auf der oberen Grenze: 100 %")
	assert_eq(training.phase_score(2), 0.0, "darunter: 0 %")
	assert_eq(training.phase_score(3), 0.0, "darüber: 0 %")
	assert_eq(training.total_score(), 0.5)
	assert_eq(Training.percent_text(1.0), "100 %")
	assert_eq(Training.percent_text(0.0), "0 %")


func test_score_per_phase_and_total_weighted_by_time() -> void:
	var training := Training.new(_unit([["A", 30, [80, 90]], ["B", 10, [95, 105]]]))
	training.advance(85.0, 15.0)
	training.advance(70.0, 15.0)  # A: halb getroffen
	training.advance(100.0, 10.0)  # B: ganz
	assert_almost_eq(training.phase_score(0), 0.5, 0.0001)
	assert_almost_eq(training.phase_score(1), 1.0, 0.0001)
	assert_almost_eq(training.total_score(), 25.0 / 40.0, 0.0001, "gesamt nach Zeit gewichtet, nicht Mittel der Phasen")
	assert_eq(training.phase_summary(), "A 50 % · B 100 %")


func test_partial_score_after_abort_counts_only_ridden_phases() -> void:
	var training := _short()
	assert_true(is_nan(training.total_score()), "nichts gefahren: keine Bewertung")
	assert_eq(Training.percent_text(training.total_score()), "–")
	training.advance(90.0, 20.0)
	training.advance(90.0, 5.0)  # Hart angefangen, mit 90 rpm daneben
	assert_true(is_nan(training.phase_score(2)), "Ausrollen nicht gefahren")
	assert_almost_eq(training.total_score(), 20.0 / 25.0, 0.0001, "Teilbewertung über die gefahrene Zeit")
	assert_eq(training.phase_summary(), "Aufwärmen 100 % · Hart 0 %", "nur die gefahrenen Phasen")


func test_score_depends_only_on_cadence() -> void:
	# ADR-0010: `advance` bekommt nur Kadenz und Zeit – dieselbe Kadenzfolge ergibt dieselbe Bewertung, egal womit
	# sie zustande kam; eine andere Kadenz eine andere.
	var a := _short()
	var b := _short()
	var c := _short()
	for cadence in [90.0, 100.0, 80.0, 96.0, 75.0, 99.0]:
		a.advance(cadence, 10.0)
		b.advance(cadence, 10.0)
		c.advance(cadence - 6.0, 10.0)
	assert_eq(a.on_target_s, b.on_target_s)
	assert_eq(a.total_score(), b.total_score())
	assert_ne(a.total_score(), c.total_score(), "andere Kadenz, andere Bewertung")


func test_file_format_with_repeat_blocks() -> void:
	var file := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"name": "Block", "phases": [
		{"name": "Auf", "kind": "warmup", "duration_s": 60, "cadence_rpm": [80, 90], "announcement": "los"},
		{"repeat": 3, "phases": [
			{"name": "Hart", "kind": "work", "duration_s": 30, "cadence_rpm": [95, 105], "announcement": "hoch"},
			{"name": "Locker", "kind": "recovery", "duration_s": 30, "cadence_rpm": [80, 90], "announcement": "runter"},
		]},
		{"name": "Aus", "kind": "cooldown", "duration_s": 60, "cadence_rpm": [70, 80]},
	]}))
	file.close()
	var unit := Training.load_file(BROKEN_PATH)
	var names := []
	for phase in unit["phases"]:
		names.append(phase["name"])
	assert_eq(names, ["Auf", "Hart 1/3", "Locker 1/3", "Hart 2/3", "Locker 2/3", "Hart 3/3", "Locker 3/3", "Aus"])
	assert_eq(unit["phases"][3]["group"], "Hart")
	assert_eq(unit["phases"][3]["cadence_min"], 95.0)
	assert_eq(unit["phases"][-1]["announcement"], "", "Ansage ist freiwillig")
	assert_eq(unit["description"], "")
	var training := Training.new(unit)
	for cadence in [85.0, 100.0, 85.0, 90.0, 70.0, 100.0, 85.0, 75.0]:
		training.advance(cadence, 60.0 if training.phase_index() in [0, 7] else 30.0)
	assert_true(training.finished())
	assert_eq(training.phase_summary(), "Auf 100 % · Hart 100 · 0 · 100 % · Locker 100 · 0 · 100 % · Aus 100 %",
			"Wiederholungen je Block zusammengefasst")


func test_invalid_files_give_no_unit() -> void:
	var cases := [
		"kein json",
		JSON.stringify({"phases": []}),
		JSON.stringify({"name": "Leer", "phases": []}),
		JSON.stringify({"name": "Verdreht", "phases": [{"name": "A", "kind": "work", "duration_s": 10,
				"cadence_rpm": [90, 80]}]}),
		JSON.stringify({"name": "Ohne Dauer", "phases": [{"name": "A", "kind": "work", "cadence_rpm": [80, 90]}]}),
		JSON.stringify({"name": "Unbekannte Art", "phases": [{"name": "A", "kind": "sprint", "duration_s": 10,
				"cadence_rpm": [80, 90]}]}),
		JSON.stringify({"name": "Null mal", "phases": [{"repeat": 0, "phases": [{"name": "A", "kind": "work",
				"duration_s": 10, "cadence_rpm": [80, 90]}]}]}),
	]
	for text in cases:
		var file := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		assert_eq(Training.load_file(BROKEN_PATH), {}, "ungültig: %s" % text)
	assert_eq(Training.load_file("res://tests/fixtures/gibt_es_nicht.json"), {}, "fehlende Datei")


## Mitte des Zielbereichs einer Phase (rpm).
func _center(phase: Dictionary) -> float:
	return (phase["cadence_min"] + phase["cadence_max"]) / 2.0


func _assert_frame(unit: Dictionary) -> void:
	var phases: Array = unit["phases"]
	assert_eq(phases[0]["kind"], Training.KIND_WARMUP, "%s: beginnt mit dem Aufwärmen" % unit["name"])
	assert_eq(phases[0]["name"], "Aufwärmen")
	assert_eq(phases[-1]["kind"], Training.KIND_COOLDOWN, "%s: endet mit dem Ausrollen" % unit["name"])
	assert_eq(phases[-1]["name"], "Ausrollen")
	for i in range(1, phases.size() - 1):
		assert_true(phases[i]["kind"] in [Training.KIND_WORK, Training.KIND_RECOVERY], "%s: Hauptteil" % phases[i]["name"])
	for phase in phases:
		assert_string_contains(phase["announcement"], "Widerstand", "%s: Ansage zum Widerstandsknopf" % phase["name"])
		assert_string_contains(phase["announcement"], "rpm", "%s: mit Kadenz" % phase["name"])
	var minutes := Training.new(unit).duration_s() / 60.0
	assert_between(minutes, 20.0, 40.0, "%s: 20–40 min" % unit["name"])


## Die Phasen des Hauptteils (ohne Aufwärmen und Ausrollen).
func _main_part(unit: Dictionary) -> Array:
	return unit["phases"].slice(1, unit["phases"].size() - 1)


func test_three_units_load_from_files_as_described() -> void:
	var units := Training.load_all()
	var names := units.map(func(u): return u["name"])
	assert_eq(names, ["Intervalle kurz", "Pyramide", "Tempo-Blöcke"], "drei Einheiten aus res://trainings")
	for unit in units:
		_assert_frame(unit)
	# Intervalle kurz: 10 × 30 s hart / 30 s locker.
	var intervals: Array = _main_part(units[0])
	assert_eq(intervals.size(), 20)
	for i in range(10):
		var hard: Dictionary = intervals[2 * i]
		var easy: Dictionary = intervals[2 * i + 1]
		assert_eq([hard["name"], hard["kind"], hard["duration_s"]], ["Hart %d/10" % (i + 1), Training.KIND_WORK, 30.0])
		assert_eq([easy["name"], easy["kind"], easy["duration_s"]], ["Locker %d/10" % (i + 1), Training.KIND_RECOVERY, 30.0])
		assert_gt(_center(hard), _center(easy), "hart über locker")
	# Pyramide: 70 → 80 → 90 → 100 → zurück.
	var steps: Array = _main_part(units[1]).map(func(p): return roundi(_center(p)))
	assert_eq(steps, [70, 80, 90, 100, 90, 80, 70])
	# Tempo-Blöcke: 3 × 8 min bei 85–90 rpm, dazwischen Erholung.
	var blocks: Array = _main_part(units[2]).filter(func(p): return p["kind"] == Training.KIND_WORK)
	assert_eq(blocks.size(), 3)
	for block in blocks:
		assert_eq([block["duration_s"], block["cadence_min"], block["cadence_max"]], [480.0, 85.0, 90.0])
	assert_eq(_main_part(units[2]).map(func(p): return p["kind"]), [Training.KIND_WORK, Training.KIND_RECOVERY,
			Training.KIND_WORK, Training.KIND_RECOVERY, Training.KIND_WORK])
	assert_eq(Training.target_text(blocks[0]), "85–90 rpm")
