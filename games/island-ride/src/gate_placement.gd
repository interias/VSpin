## Lage eines zeitgebundenen Tors auf der Strecke (#58) – reine Logik, ohne Szene und ohne Bezug zum Training.
## Ein Ereignis kommt nach einer Restzeit (s, z. B. der Phasenwechsel im Training); das Tor steht dort, wo der Fahrer
## beim aktuellen Tempo dann ankommt:
##
##   Lage = Fahrtposition + Restzeit × Tempo
##
## Alle Positionen sind Fahrtpositionen (wie `RideModel.distance_m`, in beiden Richtungen steigend, #34); auf den Pfad
## bildet sie Track.path_distance ab. Nachgeführt wird, bis das Tor höchstens LOCK_AHEAD_M voraus steht und das
## Ereignis höchstens LOCK_S entfernt ist; danach steht es fest und springt nicht mehr – das Tempo der letzten Meter
## bestimmt die Abweichung der Durchfahrt vom Ereignis. Zu sehen ist es nur fest oder weiter als LOCK_AHEAD_M voraus
## (`shown`): dort ist es klein und verschiebt sich mit dem ruhigen Tempo (Trägheit) stetig. Ein noch nicht festes Tor
## nah am Fahrer – im Stand oder beim Anfahren, wenn das Tempo noch nichts über die Ankunft sagt – bleibt verborgen.
## Je Tor eine Instanz; `reset()` für das nächste Ereignis. Auch für „Takt-Tore“ (#48).
class_name GatePlacement
extends RefCounted

## Festsetzen erst, wenn das Tor höchstens so weit voraus steht (m) …
const LOCK_AHEAD_M := 40.0
## … und das Ereignis höchstens so weit entfernt ist (s).
const LOCK_S := 10.0

## Fahrtposition des Tors (NAN = noch nicht gesetzt).
var position_m := NAN
## Steht das Tor fest?
var locked := false


## Lage beim aktuellen Tempo: Fahrtposition `ride_m` plus Restzeit `remaining_s` mal Tempo `speed_mps`.
static func target_m(ride_m: float, remaining_s: float, speed_mps: float) -> float:
	return ride_m + maxf(remaining_s, 0.0) * maxf(speed_mps, 0.0)


## Einen Schritt nachführen und die Lage liefern: solange das Tor nicht fest steht, auf die Lage beim aktuellen Tempo;
## steht es dann höchstens LOCK_AHEAD_M voraus und ist das Ereignis höchstens LOCK_S entfernt, bleibt es dort.
func update(ride_m: float, remaining_s: float, speed_mps: float) -> float:
	if not locked:
		position_m = target_m(ride_m, remaining_s, speed_mps)
		locked = position_m - ride_m <= LOCK_AHEAD_M and remaining_s <= LOCK_S
	return position_m


## Darf das Tor bei Fahrtposition `ride_m` zu sehen sein? Fest oder weiter als LOCK_AHEAD_M voraus.
func shown(ride_m: float) -> bool:
	return locked or (not is_nan(position_m) and position_m - ride_m > LOCK_AHEAD_M)


## Für ein neues Ereignis vergessen.
func reset() -> void:
	position_m = NAN
	locked = false
