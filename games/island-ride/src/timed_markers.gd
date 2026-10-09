## Lage zeitgebundener Markierungen auf der Strecke (#48): Takt-Tore und Sammelobjekte stehen dort, wo der Fahrer zu ihrem
## Zeitpunkt ankommt (GatePlacement: Lage = Fahrtposition + Restzeit × Tempo, je Markierung eine Instanz). Das Tempo
## kennt die Anzeige nicht aus dem Fahrmodell, sondern aus der Fahrt selbst: zurückgelegte Strecke je gefahrener
## Baustein-Sekunde (`measure`, in Pausen steht der Baustein und das Tempo bleibt). Reine Anzeigehilfe (ADR-0010).
class_name TimedMarkers
extends RefCounted

## Anteil des neu gemessenen Tempos am geglätteten Wert je Anzeigeschritt.
const SMOOTHING := 0.35
## Unter diesem Tempo (m/s) sagt die Fahrt noch nichts über die Ankunft: Markierungen werden nicht gesetzt (sonst fiele
## ein Tor im Stand oder beim Anfahren mit der Restzeit unter LOCK_S auf den Fahrer und bliebe dort fest).
const MIN_SPEED_MPS := 0.5

## Geglättetes Tempo (m/s) und die Lage je Markierung.
var speed_mps := 0.0
var placements: Array[GatePlacement] = []

var _last_d := NAN
var _last_t := NAN


func reset(count: int) -> void:
	speed_mps = 0.0
	_last_d = NAN
	_last_t = NAN
	placements.clear()
	for i in range(count):
		placements.append(GatePlacement.new())


## Tempo aus der Fahrtposition `ride_m` bei Baustein-Zeit `block_s` nachführen.
func measure(ride_m: float, block_s: float) -> void:
	if not is_nan(_last_t) and block_s > _last_t + 1e-6:
		var raw := maxf((ride_m - _last_d) / (block_s - _last_t), 0.0)
		speed_mps = lerpf(speed_mps, raw, SMOOTHING) if speed_mps > 0.0 else raw
	_last_d = ride_m
	_last_t = block_s


## Lage der Markierung `index`, die in `seconds_left` Sekunden erreicht wird (fest, sobald das Tor festsitzt); NAN, solange
## sie noch nie gesetzt werden konnte (Tempo unbekannt).
func position_of(index: int, ride_m: float, seconds_left: float) -> float:
	var placement := placements[index]
	if not placement.locked and speed_mps < MIN_SPEED_MPS:
		return placement.position_m
	return placement.update(ride_m, seconds_left, speed_mps)
