## Baustein „Takt-Tore“ (#48): Markierungen auf der Straße im vorgegebenen Takt durchfahren.
## Lesart (Kadenz ist die einzige Eingabe): Die Tore sind Taktschläge – der erste `first_s` Sekunden nach Beginn, dann
## alle `interval_s` Sekunden. Ein Tor ist **getroffen**, wenn die Kadenz im Zeitfenster `±tolerance_s` um seinen Schlag
## in der Zielzone liegt (Grenzen eingeschlossen); zwischen den Schlägen ist die Kadenz frei (lockere Phasen, Anlauf).
## Die Tore stehen dort, wo der Fahrer zum Schlag ankommt (GatePlacement, siehe RhythmGatesProp): das Tempo aus der
## Kadenz bestimmt die Ankunftszeit, wer im Takt bleibt, fährt durch die Tore. Wird das Fenster ohne Kadenz in der
## Zone verlassen, ist das Tor **verpasst**.
## Geschafft, wenn nach dem letzten Schlag mindestens `need` Tore getroffen sind (Erfolg also erst am Ende der Folge);
## verfehlt, sobald `need` nicht mehr erreichbar ist (weich: nur diese Herausforderung ist zu Ende) oder am Ende zu wenig.
## Ausrüstung (#49): `progress_factor` zählt jeden Treffer mehrfach (Gutschrift `credit`) – nur ein Treffer mit Kadenz in
## der Zone bringt etwas, ohne Kadenz bleibt die Gutschrift 0.
## Das Kadenzmuster „Rhythmus“ (#50) ist etwas anderes: dort wird ein Muster im Kadenzverlauf erkannt, hier ist es der Baustein.
class_name RhythmGates
extends ChallengeBlock

## Zustand eines Tors.
const PENDING := 0
const HIT := 1
const MISSED := -1

var zone_min := 0.0
var zone_max := 0.0
## Zahl der Tore und nötige Treffer.
var beats := 1
var need := 1
## Zeit bis zum ersten Schlag, Abstand der Schläge, halbe Breite des Zeitfensters (s).
var first_s := 0.0
var interval_s := 1.0
var tolerance_s := 0.5
## Treffer und angerechnete Gutschrift (Treffer × progress_factor).
var hits := 0
var credit := 0.0

var _states: Array[int] = []
## Das Tor, dessen Zeitfenster noch nicht vorbei ist.
var _open := 0


func _init(lower_rpm: float, upper_rpm: float, beat_count: int, needed: int, first: float, interval: float,
		tolerance: float) -> void:
	zone_min = lower_rpm
	zone_max = upper_rpm
	beats = maxi(beat_count, 1)
	need = clampi(needed, 1, beats)
	first_s = maxf(first, 0.0)
	tolerance_s = maxf(tolerance, 0.05)
	interval_s = maxf(interval, 2.0 * tolerance_s + 0.1)  # die Fenster überlappen nie
	_states.resize(beats)
	_states.fill(PENDING)


func in_zone(cadence_rpm: float) -> bool:
	return cadence_rpm >= zone_min and cadence_rpm <= zone_max


## Zeitpunkt (s seit Beginn) des Schlags `index`.
func beat_time(index: int) -> float:
	return first_s + index * interval_s


## Zustand des Tors `index` (PENDING, HIT, MISSED).
func state_of(index: int) -> int:
	return _states[index]


## Das Tor, dessen Zeitfenster als nächstes endet (-1 = alle vorbei).
func next_open() -> int:
	return _open if _open < beats else -1


## Zeit bis zum Schlag `index` (s; negativ = schon vorbei).
func time_to_beat(index: int) -> float:
	return beat_time(index) - elapsed_s


func progress() -> float:
	return clampf(credit / float(need), 0.0, 1.0)


## Ende des Zeitfensters des letzten Tors.
func end_s() -> float:
	return beat_time(beats - 1) + tolerance_s


func remaining_s() -> float:
	return maxf(end_s() - elapsed_s, 0.0)


func zone() -> Vector2:
	return Vector2(zone_min, zone_max)


func score_caption() -> String:
	return "Takte"


func _step(cadence_rpm: float, delta_s: float) -> void:
	var from := elapsed_s
	var to := from + delta_s
	elapsed_s = to
	var inside := in_zone(cadence_rpm)
	while _open < beats:
		var beat := beat_time(_open)
		if to <= beat - tolerance_s:
			break  # Fenster noch nicht erreicht
		if inside and from < beat + tolerance_s and _states[_open] == PENDING:
			_states[_open] = HIT
			hits += 1
			credit += progress_factor
		if to < beat + tolerance_s - 1e-9:
			break  # Fenster läuft noch
		if _states[_open] == PENDING:
			_states[_open] = MISSED
		_open += 1
	var pending := 0
	for gate_state in _states:
		if gate_state == PENDING:
			pending += 1
	if _open >= beats:
		elapsed_s = minf(elapsed_s, end_s())
		state = SUCCEEDED if credit >= need - 1e-6 else FAILED
	elif credit + pending * progress_factor < need - 1e-6:
		state = FAILED  # nicht mehr erreichbar
