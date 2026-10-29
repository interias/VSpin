## Angaben zur laufenden Fahrt für `save_ride` (Spec #84, docs/bus-protocol.md „Fahrt speichern“): Start und Ende, die
## Enden der vollen Runden und die Streckenspur – alles in **Bridge-Zeit** (`telemetry.t_ms`, `BusClient.last_telemetry_t_ms`).
## Das Spiel führt Strecke und Geschwindigkeit, weil der JC312 keine Geschwindigkeit sendet und nur das Spiel die
## virtuelle Strecke kennt. Das ist eine Angabe zur Fahrt, keine Telemetrie-Aufzeichnung (ADR-0008, Nachtrag #84): Die Bridge
## loggt weiter allein.
##
## Die Spur ist `[t_ms, Meter]` mit etwa 1 Hz: `t_ms` steigt streng, die Meter (gefahrene Strecke der Fahrt ab 0, wie die
## Zusammenfassung sie zeigt, auf 0,1 m gerundet) fallen nie. Pausen bleiben als Stillstand in der Spur. Läuft die
## Bridge-Zeit rückwärts (die Bridge wurde mitten in der Fahrt neu gestartet), ist die Fahrt nicht mehr exportierbar.
## Die Spur bleibt unter dem 1-MiB-Limit eines Frames: Wird sie zu lang (viele Stunden), verdoppelt sich der Abstand
## und die vorhandenen Punkte werden halbiert.
class_name RideTrace
extends RefCounted

## Abstand der Punkte der Spur in ms (Bridge-Zeit); wächst nur, wenn die Spur zu lang würde.
const SAMPLE_INTERVAL_MS := 1000
## Ab so vielen Punkten wird die Spur ausgedünnt (ein Punkt ist etwa 22 Byte: 30 000 bleiben deutlich unter 1 MiB).
const MAX_POINTS := 30000
## Zulässige `ride_id` (Regel der Bridge: 1–64 Zeichen aus `A-Z a-z 0-9 _ -`).
const ID_PATTERN := "^[A-Za-z0-9_-]{1,64}$"

## Eindeutig je Fahrt und für die Fahrt stabil: erneutes Speichern meint dieselbe Fahrt.
var ride_id := ""
## Beginn der Fahrt (erstes Fahren) und Ende in Bridge-Zeit; -1 = noch nicht.
var start_t_ms := -1
var end_t_ms := -1
## Ende jeder vollen Runde (Bridge-Zeit).
var lap_end_t_ms: Array[int] = []
## Streckenspur: Einträge [t_ms (int), Meter (float)].
var distance: Array = []
## Falsch, sobald die Bridge-Zeit rückwärts lief.
var valid := true

var _interval_ms := SAMPLE_INTERVAL_MS


func _init(id: String = "") -> void:
	ride_id = id if not id.is_empty() else new_ride_id()


## Neue `ride_id` aus UTC-Zeit und Zufall, z. B. `20261028T180412Z-3fa91c0e`.
static func new_ride_id() -> String:
	var now := Time.get_datetime_dict_from_system(true)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%04d%02d%02dT%02d%02d%02dZ-%08x" % [now["year"], now["month"], now["day"], now["hour"], now["minute"],
			now["second"], rng.randi()]


static func is_valid_id(id: String) -> bool:
	var regex := RegEx.create_from_string(ID_PATTERN)
	return regex.search(id) != null


func started() -> bool:
	return start_t_ms >= 0


func ended() -> bool:
	return end_t_ms >= 0


## Kann die Bridge die Fahrt schreiben? Sie hat einen Beginn in Bridge-Zeit, ein späteres Ende, und die Zeit lief nie zurück.
func exportable() -> bool:
	return valid and started() and ended() and end_t_ms > start_t_ms


## Ein Bild lang: `t_ms` ist die Bridge-Zeit der letzten Telemetrie, `distance_m` die gefahrene Strecke der Fahrt,
## `riding` ob gerade gefahren wird. Der Beginn zählt erst, wenn gefahren wird; danach auch in Pausen (Stillstand).
func sample(t_ms: int, distance_m: float, riding: bool) -> void:
	if t_ms < 0 or ended() or not valid:
		return
	if not started():
		if not riding:
			return
		start_t_ms = t_ms
		distance.append([t_ms, 0.0])
		return
	var last_t: int = distance[-1][0]
	if t_ms < last_t:
		valid = false
		return
	if t_ms >= last_t + _interval_ms:
		_append(t_ms, distance_m)


## Eine volle Runde ist jetzt zu Ende.
func lap_end(t_ms: int) -> void:
	if not started() or ended() or not valid or t_ms <= start_t_ms:
		return
	if lap_end_t_ms.is_empty() or t_ms > lap_end_t_ms[-1]:
		lap_end_t_ms.append(t_ms)


## Die Fahrt endet jetzt; ein zweiter Aufruf ändert nichts. Der letzte Punkt der Spur ist das Ende.
func finish(t_ms: int, distance_m: float) -> void:
	if ended() or not started():
		return
	if t_ms < distance[-1][0]:
		valid = false
		return
	end_t_ms = t_ms
	if t_ms > distance[-1][0]:
		_append(t_ms, distance_m)
	else:
		distance[-1][1] = maxf(distance[-1][1], _meters(distance_m))


## Der Befehl `save_ride` (ohne `v`, das ergänzt `BusClient.send_message`). Runden außerhalb von (Start, Ende] entfallen.
func save_message(upload: bool) -> Dictionary:
	var laps: Array = []
	for t in lap_end_t_ms:
		if t > start_t_ms and t <= end_t_ms:
			laps.append(t)
	return {"type": "save_ride", "ride_id": ride_id, "start_t_ms": start_t_ms, "end_t_ms": end_t_ms,
			"lap_end_t_ms": laps, "distance": distance.duplicate(true), "upload": upload}


func _append(t_ms: int, distance_m: float) -> void:
	distance.append([t_ms, maxf(_meters(distance_m), distance[-1][1])])
	if distance.size() > MAX_POINTS:
		_thin()


## Jeder zweite Punkt, der erste und der letzte bleiben; ab jetzt gilt der doppelte Abstand.
func _thin() -> void:
	var kept: Array = []
	for i in range(distance.size()):
		if i % 2 == 0 or i == distance.size() - 1:
			kept.append(distance[i])
	distance = kept
	_interval_ms *= 2


static func _meters(value: float) -> float:
	return roundf(maxf(value, 0.0) * 10.0) / 10.0
