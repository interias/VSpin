## Virtuelle Gänge (Spec #75, Story 8) – reine Logik. Der Fahrer schaltet in VSpin (Tastatur); der Gang verschiebt die
## Steigung, die das Spiel per `set_grade` an den Trainer meldet: effektive Steigung = Strecke + f(Gang) mit
## f(Gang) = (Gang − neutraler Gang) × Schritt, höherer Gang = schwerer. Das Zwift-Protokoll bleibt außen vor.
## Gänge zählen von 1 bis `count`; am oberen und unteren Ende bleibt der Gang stehen. Das Fahrmodell kennt keine
## Gänge – sie wirken nur auf den Widerstand am Trainer.
##
##   gears.shift_up() / gears.shift_down()    ein Gang schwerer bzw. leichter (false = Ende oder gesperrt)
##   gears.effective_grade(track_grade)       Steigung für `set_grade`
class_name Gears
extends RefCounted

## Anzahl der Gänge, neutraler Gang (f = 0) und Schritt in Anteil je Gang (0.005 = 0,5 Prozentpunkte).
var count := 24
var neutral := 12
var step := 0.005
## Aktueller Gang (1…count).
var gear := 12
## Gesperrt = es wird nicht geschaltet. Setzt der ERG-Modus (P7); hier setzt es niemand.
var locked := false


## `step_pp` in Prozentpunkten je Gang; ungültige Werte (Anzahl < 1, Schritt < 0) werden zurechtgerückt.
func _init(gear_count: int = 24, neutral_gear: int = 12, step_pp: float = 0.5) -> void:
	count = maxi(gear_count, 1)
	neutral = clampi(neutral_gear, 1, count)
	step = maxf(step_pp, 0.0) / 100.0
	gear = neutral


## Ein Gang schwerer. false, wenn gesperrt oder schon im höchsten Gang.
func shift_up() -> bool:
	return _shift(1)


## Ein Gang leichter. false, wenn gesperrt oder schon im niedrigsten Gang.
func shift_down() -> bool:
	return _shift(-1)


## Zurück in den neutralen Gang (jede Fahrt beginnt dort).
func reset() -> void:
	gear = neutral


## Steigungsanteil des Gangs (negativ = leichter als neutral).
func offset() -> float:
	return (gear - neutral) * step


## Steigung (Anteil), die an den Trainer geht: Strecke plus Gangoffset.
func effective_grade(track_grade: float) -> float:
	return track_grade + offset()


## Anzeige „12/24“.
func text() -> String:
	return "%d/%d" % [gear, count]


func _shift(direction: int) -> bool:
	var next := clampi(gear + direction, 1, count)
	if locked or next == gear:
		return false
	gear = next
	return true
