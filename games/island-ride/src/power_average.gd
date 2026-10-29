## 3-s-Mittel der Leistung (Spec #75, CONTEXT.md) für die Anzeige: zeitgewichteter Mittelwert der Wattwerte der letzten
## WINDOW_S Sekunden. Reine Logik; die Hauptszene füttert je Bild `add(watts, delta_s)`. Bilder ohne Wert (NAN) zählen
## als Lücke: sie gehen nicht ein, schieben das Fenster aber weiter – ganz ohne Wert ist das Mittel NAN.
class_name PowerAverage
extends RefCounted

const WINDOW_S := 3.0

## Proben im Fenster, älteste zuerst: [[watt | NAN, dauer_s], …].
var _samples: Array = []
var _span_s := 0.0


func add(watts: float, delta_s: float) -> void:
	if delta_s <= 0.0:
		return
	_samples.append([watts, delta_s])
	_span_s += delta_s
	while _span_s - _samples[0][1] >= WINDOW_S:
		_span_s -= _samples[0][1]
		_samples.pop_front()


## Mittel in Watt; NAN ohne Wert im Fenster.
func value() -> float:
	var sum := 0.0
	var time := 0.0
	for sample in _samples:
		if not is_nan(sample[0]):
			sum += sample[0] * sample[1]
			time += sample[1]
	return sum / time if time > 0.0 else NAN


func reset() -> void:
	_samples.clear()
	_span_s = 0.0
