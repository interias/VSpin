## Segmentzeiten als reine Logik (#33): Streckenposition und Fahrzeit rein → Segmentzeiten raus. Ein- und Ausfahrt
## anteilig wie bei den Runden, nur ganz durchfahrene Segmente zählen, jede Runde neu, Bestzeit je Segment; die
## Rundenwertung führt die Segmente mit. Dazu die Segmente der Insel als Daten.
extends GutTest

const DT := 1.0 / 60.0
const LAP_M := 1000.0
const SEGMENTS := [
	{"id": "a", "name": "Anstieg", "start_m": 100.0, "end_m": 300.0},
	{"id": "b", "name": "Bucht", "start_m": 600.0, "end_m": 650.0},
]


## Fährt mit fester Geschwindigkeit `mps` für `seconds` Sekunden in Schritten von DT; gibt die neue Position zurück.
func _ride(timing, from_m: float, mps: float, seconds: float) -> float:
	var d := from_m
	for i in range(int(round(seconds / DT))):
		d += mps * DT
		timing.advance(d, DT)
	return d


func test_segment_time_is_exact_across_entry_and_exit() -> void:
	var timing := SegmentTiming.new(LAP_M, 0.0, SEGMENTS)
	assert_eq(timing.advance(95.0, 9.5), 0)
	assert_eq(timing.current(), {}, "vor dem Segment")
	assert_eq(timing.advance(110.0, 1.5), 0, "Schritt über die Einfahrt")
	assert_eq(timing.current()["id"], "a")
	assert_almost_eq(timing.current()["time_s"], 1.0, 0.001, "anteilig ab der Einfahrt: 10 m bei 10 m/s")
	assert_eq(timing.advance(310.0, 10.0), 1, "Schritt über die Ausfahrt wertet das Segment")
	assert_almost_eq(timing.results[0]["time_s"], 1.0 + 9.5, 0.001, "anteilig bis zur Ausfahrt: 190 von 200 m")
	assert_eq(timing.results[0]["name"], "Anstieg")
	assert_true(timing.results[0]["new_best"], "ohne frühere Zeit neu")
	assert_eq(timing.current(), {}, "nach dem Segment")


func test_one_step_over_a_whole_segment_and_beyond() -> void:
	var timing := SegmentTiming.new(LAP_M, 0.0, SEGMENTS)
	assert_eq(timing.advance(700.0, 70.0), 2, "ein langer Schritt über beide Segmente")
	assert_almost_eq(timing.results[0]["time_s"], 20.0, 0.001)
	assert_almost_eq(timing.results[1]["time_s"], 5.0, 0.001)


func test_only_segments_ridden_in_full_count() -> void:
	var started_inside := SegmentTiming.new(LAP_M, 150.0, SEGMENTS)
	_ride(started_inside, 150.0, 10.0, 20.0)  # bis 350 m
	assert_eq(started_inside.results, [], "Start mitten im Segment: nicht gewertet")
	var ended_inside := SegmentTiming.new(LAP_M, 0.0, SEGMENTS)
	_ride(ended_inside, 0.0, 10.0, 25.0)  # bis 250 m
	assert_eq(ended_inside.results, [], "Fahrtende im Segment: nicht gewertet")
	assert_eq(ended_inside.current()["id"], "a", "das Segment läuft noch")
	assert_almost_eq(ended_inside.current()["time_s"], 15.0, 0.01, "Live-Zeit seit der Einfahrt")
	var at_entry := SegmentTiming.new(LAP_M, 100.0, SEGMENTS)
	_ride(at_entry, 100.0, 10.0, 21.0)
	assert_eq(at_entry.results.size(), 1, "Start genau auf der Einfahrt zählt")
	assert_almost_eq(at_entry.results[0]["time_s"], 20.0, 0.01)


func test_every_lap_counts_with_best_time_per_segment() -> void:
	var timing := LapTiming.new(LAP_M, 150.0, 3, INF, SEGMENTS, {"a": 18.0})
	var d := _ride(timing, 150.0, 10.0, 85.0 + 25.0)  # Rest von Runde 1, dann Runde 2 bis 1250 m
	assert_eq(timing.segments.results.size(), 1, "Runde 1: nur Segment b (Start in a)")
	assert_eq(timing.segments.results[0]["id"], "b")
	d = _ride(timing, d, 10.0, 80.0)  # bis 2050 m: Runde 2 fertig
	var a_times := timing.segments.results.filter(func(r): return r["id"] == "a")
	assert_eq(a_times.size(), 1, "Runde 2: Segment a")
	assert_almost_eq(a_times[0]["time_s"], 20.0, 0.01)
	assert_false(a_times[0]["new_best"], "langsamer als die gespeicherte Bestzeit")
	d = _ride(timing, d, 20.0, 15.0)  # Runde 3 mit 20 m/s bis 2350 m
	a_times = timing.segments.results.filter(func(r): return r["id"] == "a")
	assert_eq(a_times.size(), 2, "Runde 3: Segment a erneut")
	assert_almost_eq(a_times[1]["time_s"], 10.0, 0.01)
	assert_true(a_times[1]["new_best"], "schneller als gespeichert")
	assert_almost_eq(timing.segments.ride_best_s("a"), 10.0, 0.01)
	assert_almost_eq(timing.segments.best_s("b"), 5.0, 0.01, "b ohne gespeicherte Zeit: schnellste der Fahrt")
	assert_eq(timing.segments.ride_best_s("x"), INF)


func test_lap_timing_carries_segments_up_to_the_finish() -> void:
	var finish_segment := [{"id": "z", "name": "Zielsprint", "start_m": 900.0, "end_m": 1000.0}]
	var timing := LapTiming.new(LAP_M, 0.0, 1, INF, finish_segment)
	_ride(timing, 0.0, 10.0, 99.0)  # bis 990 m
	assert_eq(timing.advance(1010.0, 2.0), 1, "der Schritt über die Ziellinie beendet die Fahrt")
	assert_eq(timing.segments.results.size(), 1, "das Segment endet auf der Ziellinie")
	assert_almost_eq(timing.segments.results[0]["time_s"], 10.0, 0.001, "nur die Zeit bis zur Linie")
	timing.advance(1200.0, 20.0)
	assert_eq(timing.segments.results.size(), 1, "nach dem Ziel ändert sich nichts")


func test_island_segments_are_data_inside_their_stations() -> void:
	var track: Track = autofree(Track.new())
	IslandCourse.apply_to(track)
	var expected := {"kuestenwelle": "kueste", "bergwertung": "serpentinen", "dorfsprint": "bergdorf"}
	assert_eq(track.segments.map(func(s): return s["id"]), expected.keys(), "drei Segmente im Uhrzeigersinn")
	assert_eq(track.segments.map(func(s): return s["name"]), ["Küstenwelle", "Bergwertung", "Dorfsprint"])
	var stations := {}
	for i in range(track.stations.size()):
		var end: float = track.stations[i + 1]["start_m"] if i + 1 < track.stations.size() else track.length_m()
		stations[track.stations[i]["id"]] = Vector2(track.stations[i]["start_m"], end)
	for segment in track.segments:
		var station: Vector2 = stations[expected[segment["id"]]]
		assert_gt(segment["end_m"], segment["start_m"], "%s: Start vor Ende" % segment["id"])
		assert_true(segment["start_m"] >= station.x and segment["end_m"] <= station.y,
				"%s liegt in der Station %s (%s)" % [segment["id"], expected[segment["id"]], station])
	var bergwertung: Dictionary = track.segments[1]
	assert_almost_eq(bergwertung["end_m"], IslandCourse.landmarks()[0]["distance_m"], 5.0,
			"Bergwertung endet an der Kuppe mit dem Aussichtspunkt")
	assert_eq(IslandCourse.segments("ccw").size(), 3, "Gegenrichtung (#34): drei Segmente, siehe test_counter_direction.gd")
