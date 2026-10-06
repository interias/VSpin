## Fahrmodell der Inselfahrt – reine Logik ohne Darstellung (ADR-0006).
##
## Eingaben je Zeitschritt: Kadenz (rpm), Steigung (Anteil, 0.06 = 6 %), Zeitschritt (s),
## Parameter aus RideConfig. Ausgaben: Geschwindigkeit und Streckenposition (Meter entlang des Pfads).
##
##   v_ziel = k · Kadenz · Steigungsfaktor
##   Steigungsfaktor = 1 / (1 + uphill_damping · Steigung)   bergauf (gedämpft)
##                   = 1 + downhill_boost · |Steigung|        bergab (leicht verstärkt)
##   Trägheit: v nähert sich v_ziel exponentiell mit Zeitkonstante inertia_s.
class_name RideModel
extends RefCounted

const KMH_PER_MPS := 3.6

var config: RideConfig
## Aktuelle Geschwindigkeit in m/s.
var speed_mps := 0.0
## Zurückgelegte Strecke in Metern seit Start (Streckenposition, nicht modulo Rundenlänge).
var distance_m := 0.0


func _init(ride_config: RideConfig = null, start_distance_m: float = 0.0) -> void:
	config = ride_config if ride_config != null else RideConfig.new()
	distance_m = start_distance_m


## Zielgeschwindigkeit in m/s für Kadenz und Steigung, ohne Trägheit.
func target_speed_mps(cadence_rpm: float, grade: float) -> float:
	var flat_kmh := config.k_kmh_per_rpm * maxf(cadence_rpm, 0.0)
	return flat_kmh * grade_factor(grade) / KMH_PER_MPS


## Faktor, um den die Steigung die Zielgeschwindigkeit verändert (1.0 = flach).
func grade_factor(grade: float) -> float:
	if grade > 0.0:
		return 1.0 / (1.0 + config.uphill_damping * grade)
	return 1.0 + config.downhill_boost * -grade


## Rückt das Modell um `delta_s` Sekunden vor.
func step(cadence_rpm: float, grade: float, delta_s: float) -> void:
	if delta_s <= 0.0:
		return
	var target := target_speed_mps(cadence_rpm, grade)
	if config.inertia_s <= 0.0:
		speed_mps = target
	else:
		speed_mps += (target - speed_mps) * (1.0 - exp(-delta_s / config.inertia_s))
	distance_m += speed_mps * delta_s


func speed_kmh() -> float:
	return speed_mps * KMH_PER_MPS
