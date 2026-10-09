## Baustein „Zone halten“ (#46, nach Lanebreaks „Streams“): die Kadenz eine Zeit lang in einer Zielzone halten. Jede
## Sekunde in der Zone (Grenzen eingeschlossen, wie Training.on_target) füllt den Fortschritt um 1/`hold_s`; außerhalb
## steht er, er sinkt nicht. Voll → geschafft. Läuft vorher das Zeitfenster `window_s` ab → verfehlt (weich: nur diese
## Herausforderung verfällt). Schritte über eine Grenze werden anteilig gezählt, damit Ergebnis und Zeit genau sind.
class_name ZoneHold
extends ChallengeBlock

var zone_min := 0.0
var zone_max := 0.0
## Benötigte Zeit in der Zone (s) und Zeitfenster dafür (s).
var hold_s := 1.0
var window_s := 1.0
## Zeit in der Zone bisher (s).
var in_zone_s := 0.0


func _init(lower_rpm: float, upper_rpm: float, hold: float, window: float) -> void:
	zone_min = lower_rpm
	zone_max = upper_rpm
	hold_s = maxf(hold, 0.001)
	window_s = maxf(window, hold_s)


func in_zone(cadence_rpm: float) -> bool:
	return cadence_rpm >= zone_min and cadence_rpm <= zone_max


func progress() -> float:
	return clampf(in_zone_s / hold_s, 0.0, 1.0)


func remaining_s() -> float:
	return maxf(window_s - elapsed_s, 0.0)


func zone() -> Vector2:
	return Vector2(zone_min, zone_max)


func _step(cadence_rpm: float, delta_s: float) -> void:
	var step := minf(delta_s, remaining_s())
	if in_zone(cadence_rpm):
		step = minf(step, hold_s - in_zone_s)  # nur bis zum Erfolg
		in_zone_s += step
	elapsed_s += step
	if in_zone_s >= hold_s - 1e-6:
		in_zone_s = hold_s
		state = SUCCEEDED
	elif remaining_s() <= 1e-6:
		state = FAILED
