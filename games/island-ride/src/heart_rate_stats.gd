## Pulsstatistik einer Fahrt – reine Logik: Ø-Puls, Max-Puls, Sekunden je Zone.
## Nur Zeit, in der gefahren wird, zählt (der Besitzer ruft `add` in Pausen nicht auf).
## Lücken ohne Puls (`null`, Gerät weg, `stale`) zählen weder in Ø noch in eine Zone.
##
## Die Zonen gibt der Besitzer beim Anlegen mit: die zur Fahrt gültigen, sie werden nicht neu gerechnet.
## Ohne Zonen (null oder `has_zones() == false`) bleibt die Zeit je Zone leer; Ø und Max gibt es trotzdem.
class_name HeartRateStats
extends RefCounted

## Sekunden, in denen ein Puls vorlag.
var pulse_time_s := 0.0
## Höchster Puls der Fahrt in bpm (0 ohne Puls).
var max_bpm := 0

var _zones: HeartRateZones
var _bpm_seconds := 0.0  # Σ Puls · Δt
var _zone_seconds: Array[float] = []


func _init(zones: HeartRateZones = null) -> void:
	_zones = zones
	if _zones != null and _zones.has_zones():
		_zone_seconds.resize(HeartRateZones.ZONE_COUNT)
		_zone_seconds.fill(0.0)


## `delta_s` Sekunden gefahren, mit `bpm` (Zahl) oder ohne Puls (`null`, 0, negativ, NaN, unendlich).
func add(delta_s: float, bpm: Variant = null) -> void:
	if not is_finite(delta_s) or delta_s <= 0.0:
		return
	if not (bpm is float or bpm is int) or not is_finite(bpm) or bpm <= 0:
		return
	pulse_time_s += delta_s
	_bpm_seconds += float(bpm) * delta_s
	max_bpm = maxi(max_bpm, roundi(bpm))
	if not _zone_seconds.is_empty():
		_zone_seconds[_zones.zone_for(bpm) - 1] += delta_s


## Kam während der Fahrt überhaupt Puls?
func has_pulse() -> bool:
	return pulse_time_s > 0.0


## Zeitgewichteter Ø-Puls in bpm über die Zeit mit Puls (0 ohne Puls).
func avg_bpm() -> float:
	return _bpm_seconds / pulse_time_s if pulse_time_s > 0.0 else 0.0


## Sekunden je Zone, Index 0 = Z1 (fünf Werte); leer ohne Zonen.
func zone_seconds() -> Array[float]:
	return _zone_seconds.duplicate()
