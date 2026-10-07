## Segmentzeiten der Rundfahrt (#33) – reine Logik ohne Szene und Bus, wie die Rundenwertung (LapTiming, die sie
## über `advance` mitführt): gefüttert mit Streckenposition und Fahrzeit, liefert sie die Zeiten der Segmente. Nur
## Kadenz und Steigung bestimmen über das Fahrmodell die Position, sonst nichts (ADR-0010).
##
##   Segment    fester Abschnitt einer Runde [start_m, end_m] (Track.segments, Daten aus IslandCourse.SEGMENTS);
##              in jeder Runde neu – Streckenposition = Vielfaches der Rundenlänge + start_m bzw. end_m.
##   Zeit       von der Einfahrt über start_m bis zur Ausfahrt über end_m derselben Runde; ein Zeitschritt über eine
##              dieser Linien wird anteilig aufgeteilt (lineare Bewegung innerhalb des Schritts, wie bei den Runden).
##   gewertet   nur ganz durchfahrene Segmente: Start mitten im Segment oder Fahrtende darin zählt nicht.
##   Bestzeit   schnellste Zeit je Segment; `best_before` sind die gespeicherten Bestzeiten vor der Fahrt.
class_name SegmentTiming
extends RefCounted

## Länge einer Runde in Metern.
var lap_length_m := 0.0
## Segmente [{id, name, start_m, end_m}] innerhalb einer Runde, start_m < end_m.
var segments: Array = []
## Gespeicherte Segment-Bestzeiten vor dieser Fahrt: Segment-ID → Sekunden (fehlt = keine).
var best_before: Dictionary = {}
## Gewertete Segmente dieser Fahrt in Fahrtreihenfolge: [{id, name, time_s, new_best}]; `new_best` = schneller als
## alles davor (gespeichert und in dieser Fahrt).
var results: Array = []

## Fahrzeit seit Fahrtbeginn und Streckenposition seit dem letzten Schritt.
var _time_s := 0.0
var _distance_m := 0.0
## Laufendes Segment: {index, entered_s, exit_m} (exit_m = Streckenposition der Ausfahrt), {} = keins.
var _active: Dictionary = {}


func _init(lap_length: float, start_distance_m: float = 0.0, segment_list: Array = [], best: Dictionary = {}) -> void:
	lap_length_m = lap_length
	segments = segment_list
	best_before = best
	_distance_m = start_distance_m
	if lap_length_m <= 0.0:
		return
	for i in range(segments.size()):  # Start genau auf der Einfahrt: das Segment läuft ab jetzt
		var lap_m := start_distance_m - fposmod(start_distance_m, lap_length_m)
		if is_equal_approx(lap_m + segments[i]["start_m"], start_distance_m):
			_active = {"index": i, "entered_s": 0.0, "exit_m": lap_m + segments[i]["end_m"]}


## Fahrer ist in `delta_s` Sekunden Fahrzeit bis Streckenposition `distance_m` gekommen. Gibt die Zahl der dabei
## gewerteten Segmente zurück (neue Einträge am Ende von `results`).
func advance(distance_m: float, delta_s: float) -> int:
	if delta_s <= 0.0:
		return 0
	var from := _distance_m
	var completed := 0
	if distance_m > from and lap_length_m > 0.0:
		for line: Dictionary in _lines(from, distance_m):
			var at_m: float = line["at_m"]
			var at_s := _time_s + delta_s * (at_m - from) / (distance_m - from)
			var index: int = line["index"]
			if line["exit"]:
				if not _active.is_empty() and _active["index"] == index and is_equal_approx(_active["exit_m"], at_m):
					_add_result(index, at_s - _active["entered_s"])
					completed += 1
					_active = {}
			else:
				_active = {"index": index, "entered_s": at_s,
						"exit_m": at_m - segments[index]["start_m"] + segments[index]["end_m"]}
	_time_s += delta_s
	_distance_m = distance_m
	return completed


## Laufendes Segment {id, name, time_s} mit der Zeit seit der Einfahrt, {} außerhalb.
func current() -> Dictionary:
	if _active.is_empty():
		return {}
	var segment: Dictionary = segments[_active["index"]]
	return {"id": segment["id"], "name": segment["name"], "time_s": _time_s - _active["entered_s"]}


## Schnellste gewertete Zeit von Segment `id` in dieser Fahrt (INF = keine).
func ride_best_s(id: String) -> float:
	var best := INF
	for result in results:
		if result["id"] == id:
			best = minf(best, result["time_s"])
	return best


## Bestzeit von Segment `id` einschließlich dieser Fahrt (INF = keine).
func best_s(id: String) -> float:
	return minf(best_before.get(id, INF), ride_best_s(id))


func _add_result(index: int, time_s: float) -> void:
	var segment: Dictionary = segments[index]
	var new_best := time_s < best_s(segment["id"])
	results.append({"id": segment["id"], "name": segment["name"], "time_s": time_s, "new_best": new_best})


## Ein- und Ausfahrtslinien aller Segmente in (from_m, to_m], nach Position sortiert; bei gleicher Position die
## Ausfahrt zuerst (ein Segment kann dort enden, wo das nächste beginnt).
func _lines(from_m: float, to_m: float) -> Array:
	var lines := []
	for i in range(segments.size()):
		for exit in [false, true]:
			var offset: float = segments[i]["end_m" if exit else "start_m"]
			var k := floorf((from_m - offset) / lap_length_m) + 1.0
			while k * lap_length_m + offset <= to_m:
				if k * lap_length_m + offset > from_m:  # gegen Rundungsfehler: eine Linie auf from_m zählte schon
					lines.append({"at_m": k * lap_length_m + offset, "index": i, "exit": exit})
				k += 1.0
	lines.sort_custom(func(a, b): return a["at_m"] < b["at_m"] or (a["at_m"] == b["at_m"] and a["exit"] and not b["exit"]))
	return lines
