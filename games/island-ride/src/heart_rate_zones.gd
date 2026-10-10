## Pulszonen – reine Logik: fünf Zonen (Z1–Z5) aus LTHR oder Maximalpuls, plus feste Zonenfarben.
##
## Quelle der Zonen (LTHR hat Vorrang):
##   LTHR         Friel (Rad): Z1 < 81 %, Z2 81–89 %, Z3 90–93 %, Z4 94–99 %, Z5 ≥ 100 % der LTHR
##   Maximalpuls  Z1 50–60 %, Z2 60–70 %, Z3 70–80 %, Z4 80–90 %, Z5 90–100 % der HFmax
##   beides fehlt oder ist unplausibel: keine Zonen (`has_zones() == false`, `zone_for` liefert 0)
##
## Ganze bpm: Die untere Grenze jeder Zone ist `roundi(Basis · Prozent)` (kaufmännisch gerundet).
## Die obere Grenze ist die nächste untere Grenze − 1. Jeder bpm-Wert liegt so in genau einer Zone.
## Unter Z1 zählt als Z1, über Z5 als Z5 (nach unten und oben offen, wie bei Friel).
##
## Plausibel (sonst gilt der Wert als „nicht gesetzt“): LTHR 80–220 bpm, Maximalpuls 100–230 bpm.
class_name HeartRateZones
extends RefCounted

## Anzahl der Zonen.
const ZONE_COUNT := 5
## Offenes Ende in `zone_range` (Z5 bei LTHR hat keine obere Grenze).
const OPEN := -1

const LTHR_MIN := 80
const LTHR_MAX := 220
const MAX_HR_MIN := 100
const MAX_HR_MAX := 230

## Quelle der Zonen.
enum Source { NONE, LTHR, MAX_HR }

## Untere Grenzen als Anteil der Basis für Z1 bis Z5.
const LTHR_LOWER: Array[float] = [0.0, 0.81, 0.90, 0.94, 1.00]
const MAX_HR_LOWER: Array[float] = [0.50, 0.60, 0.70, 0.80, 0.90]

## Feste Zonenfarben (Anlehnung an Garmin), Index 0 = Z1. Hell genug für das dunkle HUD.
const COLORS: Array[Color] = [
	Color(0.68, 0.70, 0.74),  # Z1 grau
	Color(0.38, 0.65, 1.0),  # Z2 blau
	Color(0.45, 0.88, 0.45),  # Z3 grün
	Color(1.0, 0.65, 0.22),  # Z4 orange
	Color(1.0, 0.32, 0.30),  # Z5 rot
]

var _source := Source.NONE
var _lower: Array[int] = []  # untere bpm-Grenze je Zone
var _max_bpm := 0  # nominelles Ende von Z5 (nur Maximalpuls)


## `lthr_bpm` und `max_hr_bpm` dürfen 0 (nicht gesetzt) sein; Unplausibles zählt als nicht gesetzt.
func _init(lthr_bpm: float = 0.0, max_hr_bpm: float = 0.0) -> void:
	if lthr_bpm >= LTHR_MIN and lthr_bpm <= LTHR_MAX:
		_source = Source.LTHR
		_lower = _lower_bounds(lthr_bpm, LTHR_LOWER)
	elif max_hr_bpm >= MAX_HR_MIN and max_hr_bpm <= MAX_HR_MAX:
		_source = Source.MAX_HR
		_lower = _lower_bounds(max_hr_bpm, MAX_HR_LOWER)
		_max_bpm = roundi(max_hr_bpm)


static func _lower_bounds(base: float, fractions: Array[float]) -> Array[int]:
	var out: Array[int] = []
	for f in fractions:
		out.append(roundi(base * f))
	return out


## Gibt es Zonen? Sonst liefern `zone_for` 0 und `zone_range` (0, 0).
func has_zones() -> bool:
	return _source != Source.NONE


## Woraus die Zonen stammen (`Source.NONE`, `Source.LTHR`, `Source.MAX_HR`).
func source() -> Source:
	return _source


## Zone (1–5) zu einem Puls in bpm; 0 ohne Zonen. Unter Z1 → 1, über Z5 → 5.
func zone_for(bpm: float) -> int:
	if _source == Source.NONE:
		return 0
	var rounded := roundi(bpm)
	var zone := 1
	for i in range(1, ZONE_COUNT):
		if rounded >= _lower[i]:
			zone = i + 1
	return zone


## Bereich einer Zone (1–5) als (untere, obere) bpm-Grenze, beide eingeschlossen.
## Ohne Zonen oder bei ungültiger Zone: (0, 0).
## LTHR: Z1 beginnt bei 0, Z5 hat kein Ende (`OPEN`). Maximalpuls: Z1 ab 50 %, Z5 bis HFmax.
func zone_range(zone: int) -> Vector2i:
	if _source == Source.NONE or zone < 1 or zone > ZONE_COUNT:
		return Vector2i.ZERO
	var upper: int
	if zone < ZONE_COUNT:
		upper = _lower[zone] - 1
	else:
		upper = _max_bpm if _source == Source.MAX_HR else OPEN
	return Vector2i(_lower[zone - 1], upper)


## Farbe einer Zone (1–5); für 0 (keine Zone) und Ungültiges Weiß.
static func color_for(zone: int) -> Color:
	if zone < 1 or zone > ZONE_COUNT:
		return Color.WHITE
	return COLORS[zone - 1]
