## Baustein einer Herausforderung (#46, Spec #27): gemeinsame, schmale Schnittstelle aller Bausteine – Zone halten
## (ZoneHold), später Durchbruch, Takt-Tore, Jagd, Sammeln (#47, #48) und die Phasen der Bosse (#51). Reine Logik:
## Eingabe ist der Kadenzverlauf über die Zeit (`update(kadenz, zeit)` je Fahrschritt, in Pausen nicht), Ausgabe der
## Fortschritt (0..1) und der Zustand (läuft, geschafft, verfehlt). Scheitern ist weich: ein verfehlter Baustein ist
## nur zu Ende, die Fahrt geht weiter (das entscheidet der Arcade-Lauf, nicht der Baustein).
##
## Bausteine entstehen aus Daten (Encounters.build) – dort sitzt auch der Wächter des Kadenzbereichs. Ein Baustein
## kennt nur seine fertigen Parameter (z. B. die schon begrenzte Zielzone), keine Stufe und keinen Kadenzbereich.
class_name ChallengeBlock
extends RefCounted

## Zustand.
const RUNNING := "running"
const SUCCEEDED := "succeeded"
const FAILED := "failed"

var state := RUNNING
## Gefahrene Zeit im Baustein (s, ohne Pausen).
var elapsed_s := 0.0


## Einen Fahrschritt von `delta_s` Sekunden mit Kadenz `cadence_rpm` werten. Nach dem Ende wirkungslos.
func update(cadence_rpm: float, delta_s: float) -> void:
	if state != RUNNING or delta_s <= 0.0:
		return
	_step(cadence_rpm, delta_s)


## Fortschritt 0..1 (1 = geschafft).
func progress() -> float:
	return 0.0


## Restzeit bis zum Verfallen (s); INF ohne Zeitgrenze.
func remaining_s() -> float:
	return INF


## Zielzone (min, max) in rpm für die Anzeige; (NAN, NAN) ohne Zone.
func zone() -> Vector2:
	return Vector2(NAN, NAN)


func finished() -> bool:
	return state != RUNNING


## Ein Schritt im Zustand RUNNING (Bausteine überschreiben das).
func _step(_cadence_rpm: float, _delta_s: float) -> void:
	pass
