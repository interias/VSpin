## Entscheidet, wann das Spiel die virtuelle Steigung per `set_grade` meldet (ADR-0007) – reine Logik.
##
##   - erste Meldung sofort (nach Verbindungsaufbau bzw. nach `reset()`)
##   - danach nur, wenn sich die Steigung um mindestens THRESHOLD (0,5 Prozentpunkte) geändert hat
##   - höchstens alle MIN_INTERVAL_S Sekunden (2 pro Sekunde); eine gedrosselte Änderung wird
##     nachgeholt, sobald das Intervall um ist – mit dem dann aktuellen Wert
##   - Endwert nachsenden: weicht die Steigung (unter der Schwelle) vom gemeldeten Wert ab und hat sie sich
##     SETTLE_S lang nicht um THRESHOLD bewegt, wird der aktuelle Wert einmal nachgesendet; erst eine neue
##     Bewegung um THRESHOLD erlaubt das nächste Nachsenden (keine Dauermeldungen bei langsamer Drift)
##
##   reporter.tick(delta_s)
##   if reporter.wants_to_send(grade) and bus.send_message(...) == OK:
##       reporter.sent(grade)
class_name GradeReporter
extends RefCounted

## Mindeständerung der Steigung (Anteil) für eine neue Meldung: 0,5 Prozentpunkte.
const THRESHOLD := 0.005
## Mindestabstand zweier Meldungen in Sekunden (höchstens 2 pro Sekunde).
const MIN_INTERVAL_S := 0.5
## Ruhezeit in Sekunden, nach der ein abweichender Endwert nachgesendet wird.
const SETTLE_S := 1.0
## Auflösung der gemeldeten Steigung (Anteil); glättet Rechenrauschen der Streckengeometrie.
const RESOLUTION := 0.0001

## Zuletzt gemeldete Steigung (NAN = noch keine seit Start/`reset()`).
var last_sent := NAN

var _since_sent_s := INF
## Steigung zu Beginn der laufenden Ruhephase (NAN = keine Abweichung vom gemeldeten Wert) und deren Dauer.
var _settle_ref := NAN
var _settle_s := 0.0
## In dieser Ruhephase schon nachgesendet?
var _settled := false


## Steigung so, wie sie gemeldet wird (auf RESOLUTION gerundet).
static func quantize(grade: float) -> float:
	return snappedf(grade, RESOLUTION) + 0.0  # + 0.0 macht aus −0.0 eine 0.0


## Zeit vergeht (auch in Pausen – die Drosselung gilt über Pausen hinweg).
func tick(delta_s: float) -> void:
	_since_sent_s += delta_s
	_settle_s += delta_s


## Soll `grade` jetzt gemeldet werden? (Jeden Frame aufrufen – verfolgt auch die Ruhephase.)
func wants_to_send(grade: float) -> bool:
	var q := quantize(grade)
	if is_nan(last_sent) or q == last_sent:
		_settle_ref = NAN
	elif is_nan(_settle_ref) or absf(q - _settle_ref) >= THRESHOLD - 1e-9:
		if not is_nan(_settle_ref):
			_settled = false  # neue Bewegung über die Schwelle → neue Ruhephase
		_settle_ref = q
		_settle_s = 0.0
	if _since_sent_s < MIN_INTERVAL_S:
		return false
	if is_nan(last_sent) or absf(q - last_sent) >= THRESHOLD - 1e-9:
		return true
	return not is_nan(_settle_ref) and _settle_s >= SETTLE_S and not _settled


## `grade` wurde gemeldet.
func sent(grade: float) -> void:
	var q := quantize(grade)
	# Nachsenden (Abweichung unter der Schwelle) zählt für die Ruhephase; eine Schwellen-Meldung beginnt neu.
	_settled = not is_nan(last_sent) and absf(q - last_sent) < THRESHOLD - 1e-9
	last_sent = q
	_since_sent_s = 0.0
	_settle_ref = NAN


## Nach Verbindungsverlust: die nächste Steigung wird wieder gemeldet, auch wenn sie gleich ist.
func reset() -> void:
	last_sent = NAN
	_settle_ref = NAN
	_settled = false
