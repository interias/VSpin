## Entscheidet, wann das Spiel die virtuelle Steigung per `set_grade` meldet (ADR-0007) – reine Logik.
##
##   - erste Meldung sofort (nach Verbindungsaufbau bzw. nach `reset()`)
##   - danach nur, wenn sich die Steigung um mindestens THRESHOLD (0,5 Prozentpunkte) geändert hat
##   - höchstens alle MIN_INTERVAL_S Sekunden (2 pro Sekunde); eine gedrosselte Änderung wird
##     nachgeholt, sobald das Intervall um ist – mit dem dann aktuellen Wert
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
## Auflösung der gemeldeten Steigung (Anteil); glättet Rechenrauschen der Streckengeometrie.
const RESOLUTION := 0.0001

## Zuletzt gemeldete Steigung (NAN = noch keine seit Start/`reset()`).
var last_sent := NAN

var _since_sent_s := INF


## Steigung so, wie sie gemeldet wird (auf RESOLUTION gerundet).
static func quantize(grade: float) -> float:
	return snappedf(grade, RESOLUTION) + 0.0  # + 0.0 macht aus −0.0 eine 0.0


## Zeit vergeht (auch in Pausen – die Drosselung gilt über Pausen hinweg).
func tick(delta_s: float) -> void:
	_since_sent_s += delta_s


## Soll `grade` jetzt gemeldet werden?
func wants_to_send(grade: float) -> bool:
	if _since_sent_s < MIN_INTERVAL_S:
		return false
	return is_nan(last_sent) or absf(quantize(grade) - last_sent) >= THRESHOLD - 1e-9


## `grade` wurde gemeldet.
func sent(grade: float) -> void:
	last_sent = quantize(grade)
	_since_sent_s = 0.0


## Nach Verbindungsverlust: die nächste Steigung wird wieder gemeldet, auch wenn sie gleich ist.
func reset() -> void:
	last_sent = NAN
