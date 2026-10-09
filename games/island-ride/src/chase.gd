## Baustein „Jagd“ (#47, nach Lanebreaks „Verfolgung“): einen Verfolger abhängen. Der Abstand (`gap`, 0 = auf den Fersen,
## 1 = abgehängt) wächst, solange die Kadenz über der Schwelle liegt (in `escape_s` von 0 auf 1), und schrumpft darunter
## (in `catch_s` von 1 auf 0). Er beginnt bei `start_gap`. Abstand 1 → geschafft (abgehängt). Abstand 0 (eingeholt) oder
## Zeitfenster `window_s` vorbei → verfehlt – weich: der Verfolger zieht ab, die Fahrt geht weiter. Der Abstand ist reine
## Spiellogik; er wirkt nie auf das Fahrmodell.
## Ausrüstung (#49): `progress_factor` beschleunigt nur das Wachsen mit Kadenz über der Schwelle. Für die Beute zählt nur
## der **erarbeitete** Abstand (`loot_progress`: größter erreichter Abstand über dem Start), nicht der geschenkte Vorsprung.
class_name Chase
extends ChallengeBlock

var threshold_rpm := 0.0
var upper_rpm := 0.0
var escape_s := 1.0
var catch_s := 1.0
var window_s := 1.0
var start_gap := 0.0
## Aktueller Abstand 0..1 und der größte bisher erreichte.
var gap := 0.0
var best_gap := 0.0


func _init(threshold: float, upper: float, escape: float, catch_time: float, window: float, start: float = 0.35) -> void:
	threshold_rpm = threshold
	upper_rpm = maxf(upper, threshold)
	escape_s = maxf(escape, 0.001)
	catch_s = maxf(catch_time, 0.001)
	window_s = maxf(window, 0.001)
	start_gap = clampf(start, 0.05, 0.95)
	gap = start_gap
	best_gap = start_gap


func above(cadence_rpm: float) -> bool:
	return cadence_rpm >= threshold_rpm


## Anzeige: der Abstand.
func progress() -> float:
	return clampf(gap, 0.0, 1.0)


## Beute: nur was über dem Startvorsprung erarbeitet wurde.
func loot_progress() -> float:
	return clampf((best_gap - start_gap) / (1.0 - start_gap), 0.0, 1.0)


func remaining_s() -> float:
	return maxf(window_s - elapsed_s, 0.0)


func zone() -> Vector2:
	return Vector2(threshold_rpm, upper_rpm)


func score_caption() -> String:
	return "Abstand"


func _step(cadence_rpm: float, delta_s: float) -> void:
	var step := minf(delta_s, remaining_s())
	if above(cadence_rpm):
		var rate := progress_factor / escape_s
		step = minf(step, (1.0 - gap) / rate)
		gap += step * rate
		best_gap = maxf(best_gap, gap)
	else:
		var rate := 1.0 / catch_s
		step = minf(step, gap / rate)
		gap -= step * rate
	elapsed_s += step
	if gap >= 1.0 - 1e-6:
		gap = 1.0
		state = SUCCEEDED
	elif gap <= 1e-6:
		gap = 0.0
		state = FAILED
	elif remaining_s() <= 1e-6:
		state = FAILED
