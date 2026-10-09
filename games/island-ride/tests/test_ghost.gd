## Ghost als reine Logik (#32): Aufzeichnen (Strecke über Zeit, nur volle Runden), Abspielen (interpoliert, über das
## Rundenende hinaus), Abstand (Vorzeichen, 0 bei identischer Fahrt) und Speichern ohne Rohtelemetrie.
extends GutTest

const DT := 1.0 / 60.0
const LAP_M := 900.0
var SAVE_PATH := TestIsolation.path("test_ghost_savegame.json")
const MAIN := preload("res://scenes/main.gd")


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Fährt in Schritten von DT `seconds` Sekunden lang; das Tempo (m/s) wechselt nur zu vollen Sekunden: `mps(sekunde)`.
## Gibt die neue Position zurück.
func _ride(timing: LapTiming, from_m: float, mps: Callable, seconds: float) -> float:
	var d := from_m
	var t := 0.0
	for i in range(int(round(seconds / DT))):
		d += mps.call(floori(t + 0.000001)) * DT
		t += DT
		timing.advance(d, DT)
	return d


## Tempo-Verlauf zum Aufzeichnen: abwechselnd 8 und 12 m/s, jede Sekunde ein anderes.
func _uneven(second: int) -> float:
	return 8.0 if second % 2 == 0 else 12.0


func test_records_position_over_time_of_full_laps() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 2)
	_ride(timing, 0.0, func(_s): return 10.0, 95.0)
	assert_eq(timing.lap_times.size(), 1)
	var ghost: Ghost = timing.last_ghost
	assert_not_null(ghost, "erste Runde aufgezeichnet")
	assert_true(ghost.complete())
	assert_almost_eq(ghost.time_s, 90.0, 0.001, "Rundenzeit wie die Rundenwertung")
	assert_eq(ghost.distance_m.size(), 91, "ein Stützpunkt je Sekunde, 0 bis 90 s")
	assert_eq(ghost.distance_m[0], 0.0)
	assert_almost_eq(ghost.distance_m[10], 100.0, 0.001, "nach 10 s bei 100 m")
	assert_almost_eq(ghost.distance_m[90], LAP_M, 0.001, "Ende an der Linie")
	assert_eq(timing.best_ghost, ghost, "einzige Runde: auch die schnellste")
	# Runde 2 schneller: neue schnellste und letzte.
	_ride(timing, LAP_M + 50.0, func(_s): return 20.0, 60.0)
	assert_true(timing.finished())
	assert_ne(timing.last_ghost, ghost, "letzte Runde ist Runde 2")
	assert_eq(timing.best_ghost, timing.last_ghost, "Runde 2 ist die schnellste")
	assert_almost_eq(timing.best_ghost.time_s, timing.lap_times[1], 0.001)
	assert_almost_eq(timing.best_ghost.position_at(10.0), 5.0 * 10.0 + 5.0 * 20.0, 0.001,
			"Runde 2 beginnt an der Linie (Position ab 0)")


func test_a_shortened_first_lap_is_not_recorded() -> void:
	var timing := LapTiming.new(LAP_M, 450.0, 0)
	var d := _ride(timing, 450.0, func(_s): return 10.0, 50.0)
	assert_eq(timing.lap_times.size(), 1, "verkürzte erste Runde zu Ende")
	assert_null(timing.last_ghost, "keine volle Runde: kein Ghost")
	_ride(timing, d, func(_s): return 10.0, 91.0)
	assert_eq(timing.lap_times.size(), 2)
	assert_not_null(timing.last_ghost, "die erste volle Runde wird aufgezeichnet")
	assert_almost_eq(timing.last_ghost.time_s, 90.0, 0.001)
	assert_eq(timing.best_ghost, timing.last_ghost, "die schnellste volle Runde, nicht die verkürzte")


func test_playback_interpolates_and_runs_on_past_the_lap_end() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 1)
	_ride(timing, 0.0, _uneven, 100.0)
	var ghost: Ghost = timing.last_ghost
	assert_almost_eq(ghost.time_s, 90.0, 0.001, "im Mittel 10 m/s")
	assert_eq(ghost.position_at(0.0), 0.0)
	assert_eq(ghost.position_at(-3.0), 0.0, "vor dem Start an der Linie")
	assert_almost_eq(ghost.position_at(1.0), 8.0, 0.001)
	assert_almost_eq(ghost.position_at(2.0), 20.0, 0.001)
	assert_almost_eq(ghost.position_at(1.5), 14.0, 0.001, "zwischen den Stützpunkten linear")
	assert_almost_eq(ghost.position_at(89.5), LAP_M - 6.0, 0.001)
	assert_almost_eq(ghost.position_at(90.0), LAP_M, 0.001, "zur Rundenzeit an der Linie")
	assert_almost_eq(ghost.position_at(91.5), LAP_M + 14.0, 0.001, "danach fährt er seine Runde von vorn weiter")
	assert_almost_eq(ghost.position_at(185.0), 2.0 * LAP_M + 48.0, 0.001, "auch über mehrere Runden")
	assert_almost_eq(ghost.time_at(14.0), 1.5, 0.001, "Umkehrung: wann er an einer Position war")
	assert_almost_eq(ghost.time_at(LAP_M), 90.0, 0.001)
	assert_eq(ghost.time_at(0.0), 0.0)


func test_gap_is_positive_behind_and_negative_ahead() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 1)
	_ride(timing, 0.0, func(_s): return 10.0, 95.0)
	var ghost: Ghost = timing.last_ghost
	assert_almost_eq(ghost.gap_s(100.0, 11.0), 1.0, 0.001, "später an derselben Stelle: hinter dem Ghost, +1 s")
	assert_almost_eq(ghost.gap_s(100.0, 9.0), -1.0, 0.001, "früher: vor dem Ghost, −1 s")
	assert_almost_eq(ghost.gap_s(LAP_M, 92.5), 2.5, 0.001, "an der Linie: Unterschied der Rundenzeiten")
	assert_eq(MAIN.format_gap(1.04), "+1.0")
	assert_eq(MAIN.format_gap(-0.76), "-0.8")
	assert_eq(MAIN.format_gap(0.03), "0.0", "gleichauf ohne Vorzeichen")


func test_gap_is_zero_on_an_identical_ride() -> void:
	var first := LapTiming.new(LAP_M, 0.0, 1)
	_ride(first, 0.0, _uneven, 100.0)
	var ghost: Ghost = first.last_ghost
	var again := LapTiming.new(LAP_M, 0.0, 1)
	var d := 0.0
	var t := 0.0
	var largest := 0.0
	while not again.finished():
		d += _uneven(floori(t + 0.000001)) * DT
		t += DT
		again.advance(d, DT)
		largest = maxf(largest, absf(ghost.gap_s(again.lap_distance_m(), again.lap_time_s)))
	assert_almost_eq(largest, 0.0, 0.000001, "dieselbe Fahrt: in jedem Schritt gleichauf")
	assert_almost_eq(ghost.gap_s(again.lap_distance_m(), again.lap_time_s), 0.0, 0.000001, "auch im Ziel")
	# Aus dem Spielstand gelesen (Positionen auf 1 cm gerundet) bleibt der Abstand unter einer Hundertstelsekunde.
	var loaded := Ghost.from_dict(JSON.parse_string(JSON.stringify(ghost.to_dict())))
	assert_almost_eq(loaded.gap_s(450.0, ghost.time_at(450.0)), 0.0, 0.01)


func test_saved_ghost_is_track_position_over_time_only() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 1)
	_ride(timing, 0.0, _uneven, 100.0)
	var save := SaveGame.new()
	assert_null(save.ghost("island", LapTiming.DIRECTION_CW, Ghost.BEST), "noch kein Ghost")
	save.record_ghost("island", LapTiming.DIRECTION_CW, Ghost.BEST, timing.best_ghost)
	save.record_ghost("island", LapTiming.DIRECTION_CW, Ghost.LAST, timing.last_ghost)
	assert_eq(save.save_file(SAVE_PATH), OK)
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var stored: Dictionary = JSON.parse_string(text)["profiles"].values()[0]["ghosts"]["island"]["cw"]
	assert_eq(stored.keys(), [Ghost.BEST, Ghost.LAST])
	for kind in stored:
		var keys: Array = stored[kind].keys()
		keys.sort()
		assert_eq(keys, ["distance_m", "lap_length_m", "sample_s", "time_s"], "nur Strecke über Zeit")
	for raw in ["cadence", "power", "watt", "speed", "heart", "rpm", "kmh"]:
		assert_false(text.containsn(raw), "keine Rohtelemetrie im Spielstand: %s" % raw)
	var loaded := SaveGame.load_file(SAVE_PATH).ghost("island", LapTiming.DIRECTION_CW, Ghost.BEST)
	assert_not_null(loaded, "übersteht einen Neustart")
	assert_almost_eq(loaded.time_s, timing.best_ghost.time_s, 0.001)
	assert_almost_eq(loaded.position_at(1.5), 14.0, 0.01)
	assert_null(save.ghost("island", "ccw", Ghost.BEST), "je Richtung")
	assert_null(save.ghost("graybox", LapTiming.DIRECTION_CW, Ghost.BEST), "je Strecke")


func test_unreadable_ghost_is_ignored() -> void:
	var good := {"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 90.0, "distance_m": [0.0, 10.0, 20.0]}
	assert_not_null(Ghost.from_dict(good))
	for broken in [null, "x", {}, {"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 90.0},
			{"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 0.0, "distance_m": [0.0]},
			{"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 90.0, "distance_m": []},
			{"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 90.0, "distance_m": [0.0, 20.0, 10.0]},
			{"lap_length_m": 900.0, "sample_s": 1.0, "time_s": 90.0, "distance_m": [0.0, "a"]}]:
		assert_null(Ghost.from_dict(broken), "ungültig: %s" % [broken])
