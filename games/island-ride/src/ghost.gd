## Ghost der Rundfahrt (#32) – reine Logik ohne Szene und Bus: eine aufgezeichnete Runde als „Strecke über Zeit“,
## zum Abspielen (Position zu einer Rundenzeit) und für den Abstand zum Fahrer in Sekunden.
##
##   Aufzeichnen  `record(position, rundenzeit)` je Zeitschritt, `finish(rundenzeit)` an der Start/Ziel-Linie. Gespeichert
##                wird nur die Streckenposition in der Runde alle SAMPLE_S Sekunden (linear zwischen den Schritten
##                genommen) – keine Rohtelemetrie (ADR-0008 Nachtrag): keine Kadenz, keine Watt, kein Tempo.
##   Abspielen    `position_at(t)`: linear zwischen den Stützpunkten. Nach dem Rundenende fährt der Ghost seine Runde
##                von vorn weiter (Position > Rundenlänge); der Besitzer startet ihn mit jeder Runde neu.
##   Abstand      `gap_s(position, rundenzeit)`: an der Position des Fahrers dessen Rundenzeit minus die Zeit, zu der
##                der Ghost dieselbe Position erreichte. **Positiv = hinter dem Ghost** (wie „+1.4 s“ in Rennspielen),
##                negativ = vor ihm, 0 = gleichauf.
## Wer die Runden mitschneidet, ist LapTiming (`best_ghost`, `last_ghost`); gespeichert wird im Spielstand (SaveGame).
class_name Ghost
extends RefCounted

## Ghost-Auswahl: Bestzeit-Runde bzw. letzte Fahrt (Schlüssel im Spielstand); "" = aus.
const BEST := "best"
const LAST := "last"
## Abstand der Stützpunkte (s).
const SAMPLE_S := 1.0

## Länge der Runde (m).
var lap_length_m := 0.0
## Abstand der Stützpunkte (s).
var sample_s := SAMPLE_S
## Rundenzeit (s); INF, solange die Runde noch aufgezeichnet wird.
var time_s := INF
## Streckenposition in der Runde (m) zur Zeit i · sample_s, erster Wert 0.
var distance_m: Array[float] = [0.0]

## Letzter aufgezeichneter Punkt (Rundenzeit, Position).
var _last_t := 0.0
var _last_d := 0.0


func _init(lap_length: float = 0.0, sample: float = SAMPLE_S) -> void:
	lap_length_m = lap_length
	sample_s = sample


## Runde fertig aufgezeichnet?
func complete() -> bool:
	return is_finite(time_s)


## Fahrer war zur Rundenzeit `lap_time_s` an Position `lap_distance_m` (in der Runde). Legt die Stützpunkte bis dahin an.
func record(lap_distance_m: float, lap_time_s: float) -> void:
	if complete() or lap_time_s <= _last_t:
		return
	var d := clampf(lap_distance_m, _last_d, lap_length_m)
	while distance_m.size() * sample_s <= lap_time_s:
		var t := distance_m.size() * sample_s
		distance_m.append(lerpf(_last_d, d, (t - _last_t) / (lap_time_s - _last_t)))
	_last_t = lap_time_s
	_last_d = d


## Runde an der Start/Ziel-Linie zur Rundenzeit `lap_time_s` abgeschlossen.
func finish(lap_time_s: float) -> void:
	record(lap_length_m, lap_time_s)
	time_s = lap_time_s


## Position des Ghosts (m ab Rundenstart) zur Rundenzeit `t`; nach dem Rundenende in seiner nächsten Runde.
func position_at(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if complete() and t >= time_s:
		var laps := floorf(t / time_s)
		return laps * lap_length_m + position_at(t - laps * time_s)
	var i := int(t / sample_s)
	if i >= distance_m.size() - 1:
		if not complete():
			return distance_m[-1]
		return _lerp_point(t, (distance_m.size() - 1) * sample_s, distance_m[-1], time_s, lap_length_m)
	return _lerp_point(t, i * sample_s, distance_m[i], (i + 1) * sample_s, distance_m[i + 1])


## Rundenzeit, zu der der Ghost Position `lap_distance_m` zuerst erreichte (Rundenlänge und mehr: seine Rundenzeit).
func time_at(lap_distance_m: float) -> float:
	if lap_distance_m <= 0.0:
		return 0.0
	if lap_distance_m >= lap_length_m:
		return time_s
	# erster Stützpunkt, der die Position erreicht (die Positionen steigen nie)
	var low := 0
	var high := distance_m.size()
	while low < high:
		@warning_ignore("integer_division")
		var mid := (low + high) / 2
		if distance_m[mid] >= lap_distance_m:
			high = mid
		else:
			low = mid + 1
	if low >= distance_m.size():
		var last_t := (distance_m.size() - 1) * sample_s
		return _lerp_point(lap_distance_m, distance_m[-1], last_t, lap_length_m, time_s)
	return _lerp_point(lap_distance_m, distance_m[low - 1], (low - 1) * sample_s, distance_m[low], low * sample_s)


## Abstand in Sekunden: Fahrer zur Rundenzeit `lap_time_s` an Position `lap_distance_m`. Positiv = hinter dem Ghost.
func gap_s(lap_distance_m: float, lap_time_s: float) -> float:
	return lap_time_s - time_at(lap_distance_m)


## Für den Spielstand (JSON): nur Rundenlänge, Stützpunktabstand, Rundenzeit und Positionen.
func to_dict() -> Dictionary:
	return {
		"lap_length_m": snappedf(lap_length_m, 0.01),
		"sample_s": sample_s,
		"time_s": snappedf(time_s, 0.001),
		"distance_m": distance_m.map(func(d): return snappedf(d, 0.01)),
	}


## Aus dem Spielstand; null, wenn der Eintrag fehlt oder ungültig ist (dann gibt es keinen Ghost).
static func from_dict(value) -> Ghost:
	if not (value is Dictionary) or not (value.get("distance_m") is Array) or value["distance_m"].is_empty():
		return null
	for key in ["lap_length_m", "sample_s", "time_s"]:
		if not (value.get(key) is float or value.get(key) is int):
			return null
	var points: Array = value["distance_m"]
	var ghost := Ghost.new(float(value["lap_length_m"]), float(value["sample_s"]))
	ghost.time_s = float(value["time_s"])
	if ghost.lap_length_m <= 0.0 or ghost.sample_s <= 0.0 or ghost.time_s <= 0.0:
		return null
	ghost.distance_m.clear()
	var before := 0.0
	for point in points:
		if not (point is float or point is int) or point < before or point > ghost.lap_length_m:
			return null
		before = float(point)
		ghost.distance_m.append(before)
	return ghost


## Gerade durch (x0, y0) und (x1, y1) an der Stelle x.
static func _lerp_point(x: float, x0: float, y0: float, x1: float, y1: float) -> float:
	return y0 if x1 <= x0 else lerpf(y0, y1, clampf((x - x0) / (x1 - x0), 0.0, 1.0))
