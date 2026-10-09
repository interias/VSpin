## Rundenwertung der Rundfahrt (#31) – reine Logik ohne Szene und Bus: gefüttert mit Streckenposition und Fahrzeit,
## liefert sie Rundenzeiten und die Bestzeit. Nur Kadenz und Steigung bestimmen über das Fahrmodell die Position,
## sonst nichts (ADR-0010).
##
##   Runde      von einem Überfahren der Start/Ziel-Linie (Streckenposition = Vielfaches der Rundenlänge) zum
##              nächsten; die erste Runde beginnt an der Startposition.
##   Zeit       nur die übergebene Fahrzeit (der Besitzer ruft `advance` in Pausen nicht auf). Überquert ein
##              Zeitschritt die Linie, wird er anteilig aufgeteilt (lineare Bewegung innerhalb des Schritts).
##   Ziel       nach `laps` Runden; `laps` = 0 heißt endlos.
##   Bestzeit   schnellste abgeschlossene Runde je Strecke und Richtung; eine angefangene Runde zählt nicht.
##              `best_before_s` ist die gespeicherte Bestzeit vor der Fahrt (INF = noch keine).
##   Segmente   (#33) `segments` (SegmentTiming) läuft in `advance` mit: dieselbe Position und Fahrzeit, bis zum Ziel.
##   Ghost      (#32) jede volle Runde (Beginn an der Start/Ziel-Linie) wird als Ghost (Strecke über Zeit) mitgeschnitten:
##              `best_ghost` die schnellste, `last_ghost` die letzte dieser Fahrt.
## Medaillen bewertet Medals (#33); Gegenrichtung (#34) erweitert dieses Modul.
class_name LapTiming
extends RefCounted

## Richtung einer Runde (CONTEXT.md: im Uhrzeigersinn); Schlüssel der Bestzeit. Gegenrichtung kommt mit #34.
const DIRECTION_CW := "cw"

## Länge einer Runde in Metern.
var lap_length_m := 0.0
## Rundenzahl der Fahrt; 0 = endlos.
var laps := 1
## Gespeicherte Bestzeit vor dieser Fahrt in Sekunden (INF = keine).
var best_before_s := INF
## Zeiten der abgeschlossenen Runden in Sekunden, erste zuerst.
var lap_times: Array[float] = []
## Fahrzeit der laufenden Runde in Sekunden.
var lap_time_s := 0.0
## Segmentzeiten dieser Fahrt (#33).
var segments: SegmentTiming
## Aufzeichnung der schnellsten bzw. letzten vollen Runde dieser Fahrt (#32; null = noch keine).
var best_ghost: Ghost = null
var last_ghost: Ghost = null

## Streckenposition seit dem letzten Schritt.
var _distance_m := 0.0
## Streckenposition der nächsten Start/Ziel-Linie.
var _next_line_m := INF
## Streckenposition, an der die laufende Runde begann.
var _lap_start_m := 0.0
## Streckenposition des Ziels (INF = endlos).
var _finish_m := INF
## Aufzeichnung der laufenden Runde (null = keine volle Runde, z. B. Start mitten auf der Strecke).
var _ghost: Ghost = null


## `segment_list`: Segmente der Strecke (Track.segments), `segment_best`: ihre gespeicherten Bestzeiten (ID → s).
func _init(lap_length: float, start_distance_m: float = 0.0, lap_count: int = 1, best_s: float = INF,
		segment_list: Array = [], segment_best: Dictionary = {}) -> void:
	segments = SegmentTiming.new(lap_length, start_distance_m, segment_list, segment_best)
	lap_length_m = lap_length
	laps = maxi(lap_count, 0)
	best_before_s = best_s
	_distance_m = start_distance_m
	_lap_start_m = start_distance_m
	if lap_length_m > 0.0:
		_next_line_m = (floorf(start_distance_m / lap_length_m) + 1.0) * lap_length_m
		if laps > 0:
			_finish_m = _next_line_m + (laps - 1) * lap_length_m
		if is_zero_approx(fposmod(start_distance_m, lap_length_m)):
			_ghost = Ghost.new(lap_length_m)


## Fahrer ist in `delta_s` Sekunden Fahrzeit bis Streckenposition `distance_m` gekommen. Gibt die Zahl der dabei
## abgeschlossenen Runden zurück. Nach dem Ziel ändert sich nichts mehr.
func advance(distance_m: float, delta_s: float) -> int:
	if finished() or delta_s <= 0.0:
		return 0
	var completed := 0
	var from_m := _distance_m
	var left_s := delta_s
	var used_s := delta_s
	while distance_m >= _next_line_m and not finished():
		var share := (_next_line_m - from_m) / (distance_m - from_m) if distance_m > from_m else 1.0
		var to_line_s := left_s * clampf(share, 0.0, 1.0)
		lap_times.append(lap_time_s + to_line_s)
		_finish_ghost(lap_times[-1])
		completed += 1
		if finished():
			lap_time_s = lap_times[-1]  # im Ziel bleibt die letzte Runde stehen
			used_s = delta_s - left_s + to_line_s
			break
		lap_time_s = 0.0
		left_s -= to_line_s
		from_m = _next_line_m
		_lap_start_m = _next_line_m
		_next_line_m += lap_length_m
		_ghost = Ghost.new(lap_length_m)
	if not finished():
		lap_time_s += left_s
		if _ghost != null:
			_ghost.record(distance_m - _lap_start_m, lap_time_s)
	_distance_m = minf(distance_m, _finish_m)
	segments.advance(_distance_m, used_s)
	return completed


## Alle Runden gefahren? (Endlos nie.)
func finished() -> bool:
	return laps > 0 and lap_times.size() >= laps


## Nummer der laufenden Runde (ab 1); im Ziel die letzte.
func lap_number() -> int:
	return lap_times.size() if finished() else lap_times.size() + 1


## Streckenposition, an der die laufende Runde begann bzw. an der sie endet (Fortschrittsanzeige; im Ziel die
## letzte Runde).
func lap_start_m() -> float:
	return _lap_start_m


func lap_end_m() -> float:
	return _next_line_m


## Streckenposition in der laufenden Runde (m ab ihrem Beginn; im Ziel das Ende der letzten Runde).
func lap_distance_m() -> float:
	return _distance_m - _lap_start_m


## Streckenposition des Ziels der Fahrt (INF = endlos).
func finish_m() -> float:
	return _finish_m


## Schnellste abgeschlossene Runde dieser Fahrt (INF = noch keine).
func ride_best_s() -> float:
	var best := INF
	for t in lap_times:
		best = minf(best, t)
	return best


## Bestzeit einschließlich dieser Fahrt (INF = noch keine).
func best_s() -> float:
	return minf(best_before_s, ride_best_s())


## Hat diese Fahrt die Bestzeit unterboten?
func new_best() -> bool:
	return ride_best_s() < best_before_s


## War die zuletzt abgeschlossene Runde eine neue Bestzeit (schneller als alles davor, auch in dieser Fahrt)?
func last_lap_is_new_best() -> bool:
	if lap_times.is_empty():
		return false
	var before := best_before_s
	for i in range(lap_times.size() - 1):
		before = minf(before, lap_times[i])
	return lap_times[-1] < before


## Aufzeichnung der laufenden Runde abschließen (Rundenzeit `time_s`) und als letzte bzw. schnellste merken.
func _finish_ghost(time_s: float) -> void:
	if _ghost == null:
		return
	_ghost.finish(time_s)
	last_ghost = _ghost
	if best_ghost == null or time_s < best_ghost.time_s:
		best_ghost = _ghost
