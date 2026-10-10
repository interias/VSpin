## Baustein „Durchbruch“ (#47, nach Lanebreaks „Sprint“): einen Balken füllen, indem die Kadenz über einer Schwelle liegt
## – kurze, harte Anstrengung, z. B. eine Zugbrücke öffnen. Jede Sekunde mit Kadenz ≥ Schwelle füllt den Balken um
## 1/`fill_s`; darunter sinkt er langsam (um `decay` × Füllrate), damit ein kurzes Nachlassen kostet, ein Einbruch aber
## nicht alles. Voll → geschafft. Läuft vorher das Zeitfenster `window_s` ab → verfehlt (weich: nur diese
## Herausforderung verfällt, die Fahrt geht weiter). Schritte über das Ende werden anteilig gezählt.
## Ausrüstung (#49): `progress_factor` vervielfacht nur das Füllen mit Kadenz über der Schwelle – darunter hilft sie nie.
## Die Schwelle ist eine Zone [Schwelle, oberes Ende des Kadenzbereichs]; Encounters.build begrenzt sie (Wächter).
class_name Breakthrough
extends ChallengeBlock

var threshold_rpm := 0.0
## Obere Grenze der Anzeige-Zone (Ende des persönlichen Kadenzbereichs); die Kadenz darüber zählt weiter.
var upper_rpm := 0.0
## Zeit über der Schwelle bis zum vollen Balken (s), Zeitfenster (s) und Sinkrate unter der Schwelle (Anteil der Füllrate).
var fill_s := 1.0
var window_s := 1.0
var decay := 0.0
## Balken 0..1.
var level := 0.0


func _init(threshold: float, upper: float, fill: float, window: float, sink: float = 0.5) -> void:
	threshold_rpm = threshold
	upper_rpm = maxf(upper, threshold)
	fill_s = maxf(fill, 0.001)
	window_s = maxf(window, fill_s)
	decay = maxf(sink, 0.0)


## Zählt diese Kadenz? Die Schwelle gehört dazu.
func above(cadence_rpm: float) -> bool:
	return cadence_rpm >= threshold_rpm


func progress() -> float:
	return clampf(level, 0.0, 1.0)


func remaining_s() -> float:
	return maxf(window_s - elapsed_s, 0.0)


func zone() -> Vector2:
	return Vector2(threshold_rpm, upper_rpm)


func score_caption() -> String:
	return "Balken"


func _step(cadence_rpm: float, delta_s: float) -> void:
	var step := minf(delta_s, remaining_s())
	if above(cadence_rpm):
		var rate := progress_factor / fill_s
		step = minf(step, (1.0 - level) / rate)  # nur bis zum Erfolg
		level += step * rate
	else:
		level = maxf(level - step * decay / fill_s, 0.0)
	elapsed_s += step
	if level >= 1.0 - 1e-6:
		level = 1.0
		state = SUCCEEDED
	elif remaining_s() <= 1e-6:
		state = FAILED
