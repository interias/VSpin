## Baustein „Sammeln“ (#48): Sammelobjekte auf und neben der Strecke; die **Kadenz bestimmt den Magnetradius**.
## Objekt `k` hat einen seitlichen Abstand `offsets[k]` (m, negativ = links der Straßenmitte) und wird `first_s +
## k × interval_s` Sekunden nach Beginn passiert (die Objekte stehen dort, wo der Fahrer dann ankommt, GatePlacement –
## wie bei den Takt-Toren). Im Vorbeifahren ist eingesammelt, was im Radius liegt: `|offset| ≤ Radius`.
## Radius: unter `ramp_min` rpm 0, dort `radius_min_m`, linear wachsend bis `radius_max_m` bei `ramp_max` rpm und darüber.
## Die Rampe liegt immer im persönlichen Kadenzbereich (Wächter: Encounters.zone_for, `limit_zone`); wer nicht tritt,
## hat keinen Magneten. Geschafft, wenn nach dem letzten Objekt mindestens `need` eingesammelt sind; verfehlt, sobald das
## nicht mehr erreichbar ist (weich) oder am Ende zu wenig. Ein lockerer Abschnitt: keine Zone, mehr Kadenz = mehr Reichweite.
## Ausrüstung (#49): `progress_factor` vergrößert den Radius – nur dort, wo die Kadenz schon einen Radius ergibt.
class_name Collect
extends ChallengeBlock

const PENDING := 0
const COLLECTED := 1
const MISSED := -1

var ramp_min := 0.0
var ramp_max := 0.0
var radius_min_m := 0.0
var radius_max_m := 0.0
var offsets: Array[float] = []
var need := 1
var first_s := 0.0
var interval_s := 1.0
## Eingesammelt bisher und der Radius des letzten Schritts (m; Anzeige).
var collected := 0
var radius_m := 0.0

var _states: Array[int] = []
var _next := 0


func _init(ramp_from: float, ramp_to: float, radius_min: float, radius_max: float, object_offsets: Array, needed: int,
		first: float, interval: float) -> void:
	ramp_min = ramp_from
	ramp_max = maxf(ramp_to, ramp_from)
	radius_min_m = maxf(radius_min, 0.0)
	radius_max_m = maxf(radius_max, radius_min_m)
	for offset in object_offsets:
		offsets.append(float(offset))
	if offsets.is_empty():
		offsets.append(0.0)
	need = clampi(needed, 1, offsets.size())
	first_s = maxf(first, 0.0)
	interval_s = maxf(interval, 0.1)
	_states.resize(offsets.size())
	_states.fill(PENDING)


## Magnetradius (m) bei Kadenz `cadence_rpm`: 0 ohne Kadenz in der Rampe, sonst linear, mit Ausrüstung größer.
func radius_for(cadence_rpm: float) -> float:
	if cadence_rpm <= 0.0 or cadence_rpm < ramp_min:
		return 0.0
	var fraction := 1.0 if ramp_max <= ramp_min else clampf((cadence_rpm - ramp_min) / (ramp_max - ramp_min), 0.0, 1.0)
	return lerpf(radius_min_m, radius_max_m, fraction) * progress_factor


func count() -> int:
	return offsets.size()


## Zeitpunkt (s seit Beginn), zu dem der Fahrer Objekt `index` passiert.
func pass_time(index: int) -> float:
	return first_s + index * interval_s


## Zustand des Objekts `index` (PENDING, COLLECTED, MISSED).
func state_of(index: int) -> int:
	return _states[index]


## Das nächste noch nicht passierte Objekt (-1 = keins mehr).
func next_open() -> int:
	return _next if _next < offsets.size() else -1


func progress() -> float:
	return clampf(float(collected) / float(need), 0.0, 1.0)


func remaining_s() -> float:
	return maxf(pass_time(offsets.size() - 1) - elapsed_s, 0.0)


func zone() -> Vector2:
	return Vector2(ramp_min, ramp_max)


func score_caption() -> String:
	return "Gesammelt"


func _step(cadence_rpm: float, delta_s: float) -> void:
	elapsed_s += delta_s
	radius_m = radius_for(cadence_rpm)
	while _next < offsets.size() and pass_time(_next) <= elapsed_s + 1e-9:
		if absf(offsets[_next]) <= radius_m + 1e-9:
			_states[_next] = COLLECTED
			collected += 1
		else:
			_states[_next] = MISSED
		_next += 1
	if _next >= offsets.size():
		elapsed_s = minf(elapsed_s, pass_time(offsets.size() - 1))
		state = SUCCEEDED if collected >= need else FAILED
	elif collected + (offsets.size() - _next) < need:
		state = FAILED
