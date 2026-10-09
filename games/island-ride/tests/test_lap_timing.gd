## Rundenwertung als reine Logik (#31): Streckenposition und Fahrzeit rein → Rundenzeiten und Bestzeit raus.
## Bestzeit je Strecke und Richtung im Spielstand, eine angefangene Runde zählt nicht, endlos.
extends GutTest

const DT := 1.0 / 60.0
const LAP_M := 900.0


## Fährt mit fester Geschwindigkeit `mps` für `seconds` Sekunden in Schritten von DT; gibt die neue Position zurück.
func _ride(timing: LapTiming, from_m: float, mps: float, seconds: float) -> float:
	var d := from_m
	for i in range(int(round(seconds / DT))):
		d += mps * DT
		timing.advance(d, DT)
	return d


func test_lap_times_are_exact_across_the_line() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 2)
	var d := _ride(timing, 0.0, 10.0, 89.0)
	assert_eq(timing.lap_times.size(), 0, "nach 890 m noch keine Runde")
	assert_eq(timing.lap_number(), 1)
	assert_eq(timing.advance(d + 15.0, 1.5), 1, "der Schritt über die Linie schließt die Runde ab")
	assert_almost_eq(timing.lap_times[0], 90.0, 0.001, "anteilig bis zur Linie: 900 m bei 10 m/s")
	assert_almost_eq(timing.lap_time_s, 0.5, 0.001, "der Rest des Schritts zählt für Runde 2")
	assert_eq(timing.lap_number(), 2)
	assert_almost_eq(timing.lap_start_m(), LAP_M, 0.001)
	assert_almost_eq(timing.lap_end_m(), 2.0 * LAP_M, 0.001)
	_ride(timing, d + 15.0, 20.0, 60.0)
	assert_true(timing.finished(), "Ziel nach zwei Runden")
	assert_eq(timing.lap_times.size(), 2, "zwei Rundenzeiten")
	assert_almost_eq(timing.lap_times[1], 0.5 + 895.0 / 20.0, 0.001)
	assert_eq(timing.lap_number(), 2, "im Ziel bleibt die letzte Runde")
	assert_almost_eq(timing.lap_time_s, timing.lap_times[1], 0.001, "Rundenzeit bleibt im Ziel stehen")
	assert_eq(timing.advance(5000.0, 10.0), 0, "nach dem Ziel ändert sich nichts")
	assert_eq(timing.lap_times.size(), 2)


func test_one_step_over_several_lines() -> void:
	var timing := LapTiming.new(100.0, 0.0, 0)
	assert_eq(timing.advance(250.0, 25.0), 2, "ein langer Schritt über zwei Linien")
	assert_almost_eq(timing.lap_times[0], 10.0, 0.001)
	assert_almost_eq(timing.lap_times[1], 10.0, 0.001)
	assert_almost_eq(timing.lap_time_s, 5.0, 0.001)


func test_best_time_is_fastest_full_lap_and_started_lap_does_not_count() -> void:
	var timing := LapTiming.new(LAP_M, 0.0, 0)
	var d := _ride(timing, 0.0, 10.0, 90.5)  # Runde 1: 90 s
	d = _ride(timing, d, 12.5, 72.0)  # Runde 2: 0,5 s + 895 m / 12,5 m/s = 72,1 s
	_ride(timing, d, 50.0, 10.0)  # Runde 3 angefangen: 500 m in 10 s – wäre die schnellste
	assert_eq(timing.lap_times.size(), 2, "nur volle Runden")
	assert_almost_eq(timing.ride_best_s(), 72.1, 0.001, "schnellste volle Runde")
	assert_almost_eq(timing.best_s(), 72.1, 0.001)
	assert_true(timing.new_best(), "ohne frühere Bestzeit ist die schnellste Runde neu")
	assert_false(timing.finished(), "endlos: kein Ziel")


func test_endless_never_finishes() -> void:
	var timing := LapTiming.new(100.0, 0.0, 0)
	_ride(timing, 0.0, 50.0, 30.5)
	assert_eq(timing.lap_times.size(), 15)
	assert_false(timing.finished())
	assert_eq(timing.lap_number(), 16)
	assert_eq(timing.finish_m(), INF, "kein Ziel")
	assert_eq(LapTiming.new(100.0, 0.0, 3).finish_m(), 300.0, "Ziel nach drei Runden")


func test_new_best_against_saved_best() -> void:
	var slower := LapTiming.new(LAP_M, 0.0, 1, 60.0)
	_ride(slower, 0.0, 10.0, 91.0)
	assert_true(slower.finished())
	assert_false(slower.new_best(), "90 s schlagen 60 s nicht")
	assert_false(slower.last_lap_is_new_best())
	assert_eq(slower.best_s(), 60.0, "gespeicherte Bestzeit bleibt")
	var faster := LapTiming.new(LAP_M, 0.0, 3, 80.0)
	var d := _ride(faster, 0.0, 10.0, 90.5)
	assert_false(faster.last_lap_is_new_best(), "Runde 1: 90 s")
	d = _ride(faster, d, 12.5, 72.0)
	assert_true(faster.last_lap_is_new_best(), "Runde 2: 72,1 s < 80 s")
	_ride(faster, d, 12.0, 76.0)
	assert_false(faster.last_lap_is_new_best(), "Runde 3: 75 s, schneller als gespeichert, aber nicht als Runde 2")
	assert_true(faster.new_best())
	assert_almost_eq(faster.best_s(), 72.1, 0.001)


func test_first_lap_starts_at_start_position() -> void:
	var timing := LapTiming.new(LAP_M, LAP_M - 12.0, 1)
	assert_eq(timing.finish_m(), LAP_M, "Ziel an der nächsten Linie")
	_ride(timing, LAP_M - 12.0, 6.0, 2.5)
	assert_true(timing.finished())
	assert_almost_eq(timing.lap_times[0], 2.0, 0.001)


func test_best_time_per_track_and_direction_in_save_game() -> void:
	var save := SaveGame.new()
	assert_eq(save.best_time_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW), INF, "noch keine Bestzeit")
	assert_true(save.record_best_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, 1234.5))
	assert_false(save.record_best_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, 1300.0), "langsamer: bleibt")
	assert_true(save.record_best_time(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, 90.0), "andere Strecke")
	assert_true(save.record_best_time(RideConfig.TRACK_ISLAND, "ccw", 1500.0), "andere Richtung (#34)")
	assert_false(save.record_best_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, INF), "keine Runde")
	assert_eq(save.best_time_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW), 1234.5)
	assert_eq(save.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), 90.0)
	assert_eq(save.best_time_s(RideConfig.TRACK_ISLAND, "ccw"), 1500.0)
	assert_eq(save.profile()["best_times"], {"island": {"cw": 1234.5, "ccw": 1500.0}, "graybox": {"cw": 90.0}},
			"Schlüssel: Strecke, dann Richtung")
	assert_true(save.record_best_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, 1200.0), "schneller: neu")
	assert_eq(save.best_time_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW), 1200.0)
