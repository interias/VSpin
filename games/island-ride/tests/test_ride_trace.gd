## Angaben zur Fahrt für `save_ride` (Spec #84, RideTrace): ride_id, Beginn erst beim Fahren, Spur mit etwa 1 Hz in
## Bridge-Zeit (t_ms streng steigend, Meter nie fallend, Pausen als Stillstand), Rundenenden, Ende, Bridge-Zeit rückwärts,
## Ausdünnen unter dem 1-MiB-Limit und der Befehl `save_ride`.
extends GutTest


func _ridden(seconds: int = 4) -> RideTrace:
	var trace := RideTrace.new()
	for s in range(seconds + 1):
		trace.sample(5000 + s * 1000, s * 8.1, true)
	return trace


func test_ride_id_is_valid_unique_and_stable() -> void:
	var a := RideTrace.new()
	var b := RideTrace.new()
	assert_true(RideTrace.is_valid_id(a.ride_id), "erfüllt [A-Za-z0-9_-]{1,64}: %s" % a.ride_id)
	assert_true(RideTrace.is_valid_id(b.ride_id))
	assert_ne(a.ride_id, b.ride_id, "eindeutig je Fahrt")
	a.sample(1000, 0.0, true)
	a.sample(2000, 5.0, true)
	a.finish(2500, 6.0)
	assert_eq(a.save_message(true)["ride_id"], a.ride_id, "stabil über die Fahrt")
	assert_eq(RideTrace.new("abc-DEF_123").ride_id, "abc-DEF_123", "ausdrückliche ride_id")
	assert_false(RideTrace.is_valid_id(""))
	assert_false(RideTrace.is_valid_id("a b"))
	assert_false(RideTrace.is_valid_id("x".repeat(65)))
	assert_true(RideTrace.is_valid_id("x".repeat(64)))


func test_start_counts_only_when_riding() -> void:
	var trace := RideTrace.new()
	trace.sample(1000, 0.0, false)
	assert_false(trace.started(), "Pause vor dem ersten Fahren ist kein Beginn")
	trace.sample(-1, 0.0, true)
	assert_false(trace.started(), "ohne Bridge-Zeit kein Beginn")
	trace.sample(2000, 0.0, true)
	assert_eq(trace.start_t_ms, 2000)
	assert_eq(trace.distance, [[2000, 0.0]], "die Spur beginnt bei 0 m")


func test_trace_is_about_1_hz_strictly_rising_and_never_falling() -> void:
	var trace := RideTrace.new()
	trace.sample(10000, 0.0, true)
	trace.sample(10250, 2.0, true)
	trace.sample(10500, 4.0, true)
	assert_eq(trace.distance.size(), 1, "unter einer Sekunde kein neuer Punkt")
	trace.sample(11000, 8.04, true)
	trace.sample(11990, 12.0, true)
	trace.sample(12000, 16.26, true)
	trace.sample(13000, 3.0, true)  # Strecke fiel (z. B. Rundung): bleibt stehen
	assert_eq(trace.distance, [[10000, 0.0], [11000, 8.0], [12000, 16.3], [13000, 16.3]], "auf 0,1 m gerundet, nie fallend")
	for i in range(1, trace.distance.size()):
		assert_gt(trace.distance[i][0], trace.distance[i - 1][0], "t_ms streng steigend")
		assert_true(trace.distance[i][1] >= trace.distance[i - 1][1], "Meter fallen nie")


func test_pauses_stay_in_the_trace_as_standstill() -> void:
	var trace := RideTrace.new()
	trace.sample(1000, 0.0, true)
	trace.sample(2000, 10.0, true)
	trace.sample(3000, 10.0, false)  # manuelle Pause: Telemetrie läuft, die Strecke steht
	trace.sample(4000, 10.0, false)
	trace.sample(5000, 14.0, true)
	assert_eq(trace.distance, [[1000, 0.0], [2000, 10.0], [3000, 10.0], [4000, 10.0], [5000, 14.0]])


func test_lap_ends_end_and_message() -> void:
	var trace := _ridden(4)
	trace.lap_end(6500)
	trace.lap_end(6500)  # doppelt zählt nicht
	trace.lap_end(5000)  # nicht nach dem Start
	trace.lap_end(8000)
	assert_false(trace.exportable(), "ohne Ende nicht exportierbar")
	trace.finish(9400, 40.0)
	assert_true(trace.exportable())
	assert_eq(trace.end_t_ms, 9400)
	assert_eq(trace.distance[-1], [9400, 40.0], "das Ende ist der letzte Punkt der Spur")
	trace.finish(9900, 99.0)
	assert_eq(trace.end_t_ms, 9400, "ein zweites Ende ändert nichts")
	trace.lap_end(9400)
	assert_eq(trace.lap_end_t_ms, [6500, 8000], "nach dem Ende keine Runde mehr")
	var message := trace.save_message(false)
	assert_eq(message["type"], "save_ride")
	assert_eq(message["start_t_ms"], 5000)
	assert_eq(message["end_t_ms"], 9400)
	assert_eq(message["lap_end_t_ms"], [6500, 8000])
	assert_eq(message["upload"], false)
	assert_eq(message["distance"].size(), trace.distance.size())
	assert_eq(trace.save_message(true)["upload"], true)
	assert_false(message.has("v"), "`v` ergänzt der BusClient")


func test_end_on_the_last_sample_keeps_times_strictly_rising() -> void:
	var trace := RideTrace.new()
	trace.sample(1000, 0.0, true)
	trace.sample(2000, 5.0, true)
	trace.finish(2000, 5.4)
	assert_eq(trace.distance, [[1000, 0.0], [2000, 5.4]], "Ende = letzter Punkt: Meter nachgezogen, kein doppeltes t_ms")
	assert_true(trace.exportable())


func test_end_must_come_after_the_start() -> void:
	var trace := RideTrace.new()
	trace.sample(1000, 0.0, true)
	trace.finish(1000, 0.0)
	assert_false(trace.exportable(), "Ende = Beginn: die Bridge lehnt ab")
	var never_rode := RideTrace.new()
	never_rode.finish(5000, 0.0)
	assert_false(never_rode.exportable(), "nie gefahren")


func test_bridge_time_running_backwards_makes_the_ride_unexportable() -> void:
	var trace := _ridden(3)
	trace.sample(2000, 30.0, true)  # Bridge neu gestartet: Zeit beginnt wieder bei 0
	assert_false(trace.valid)
	trace.finish(9000, 40.0)
	assert_false(trace.exportable())
	var late := _ridden(3)
	late.finish(100, 30.0)
	assert_false(late.exportable(), "auch ein Ende vor dem letzten Punkt")


func test_long_traces_are_thinned_below_the_frame_limit() -> void:
	var trace := RideTrace.new()
	trace.sample(0, 0.0, true)
	var seconds := RideTrace.MAX_POINTS * 3
	for s in range(1, seconds + 1):
		trace.sample(s * 1000, s * 7.5, true)
	assert_lte(trace.distance.size(), RideTrace.MAX_POINTS, "höchstens MAX_POINTS Punkte")
	assert_eq(trace.distance[0], [0, 0.0], "der Beginn bleibt")
	for i in range(1, trace.distance.size()):
		assert_gt(trace.distance[i][0], trace.distance[i - 1][0], "t_ms streng steigend")
		assert_true(trace.distance[i][1] >= trace.distance[i - 1][1])
	trace.finish(seconds * 1000 + 400, seconds * 7.5 + 3.0)
	assert_eq(trace.distance[-1][0], seconds * 1000 + 400, "das Ende bleibt")
	assert_true(trace.exportable())
	var frame := JSON.stringify(trace.save_message(true))
	assert_lt(frame.length(), 1024 * 1024, "unter 1 MiB (%d Zeichen)" % frame.length())
