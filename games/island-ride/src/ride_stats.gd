## Fahrtstatistik einer Runde – reine Logik: Fahrzeit, Strecke, Durchschnitte.
## Nur Zeit, in der gefahren wird, zählt (der Besitzer ruft `add` in Pausen nicht auf).
##
##   Ø Kadenz = zeitgewichtetes Mittel der Kadenz über die Fahrzeit
##   Ø Tempo  = Strecke / Fahrzeit
class_name RideStats
extends RefCounted

## Fahrzeit in Sekunden (ohne Pausen).
var ride_time_s := 0.0
## Gefahrene Strecke in Metern.
var distance_m := 0.0

var _cadence_seconds := 0.0  # Σ Kadenz · Δt


## `delta_s` Sekunden gefahren, mit `cadence_rpm`, dabei `distance_delta_m` Meter zurückgelegt.
func add(delta_s: float, cadence_rpm: float, distance_delta_m: float) -> void:
	if delta_s <= 0.0:
		return
	ride_time_s += delta_s
	_cadence_seconds += maxf(cadence_rpm, 0.0) * delta_s
	distance_m += distance_delta_m


## Durchschnittliche Kadenz in rpm (0 ohne Fahrzeit).
func avg_cadence() -> float:
	return _cadence_seconds / ride_time_s if ride_time_s > 0.0 else 0.0


## Durchschnittsgeschwindigkeit in km/h (0 ohne Fahrzeit).
func avg_speed_kmh() -> float:
	return distance_m / ride_time_s * RideModel.KMH_PER_MPS if ride_time_s > 0.0 else 0.0
