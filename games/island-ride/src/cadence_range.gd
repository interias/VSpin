## Persönlicher Kadenzbereich (#46, Spec #27): der Bereich, in dem der Fahrer treten kann und will (Standard 60–120 rpm),
## im Startmenü auf der Seite „Arcade“ einstellbar und im Spielstand (`arcade.cadence_range`). Er ist ein **Wächter**:
## keine Zielzone einer Herausforderung liegt außerhalb – auch nicht durch Stufe (#54) oder Elite-Eigenschaft (#52).
## Die eine Stelle dafür ist `limit_zone`; Encounters.build ruft sie für jeden Baustein auf, der aus Daten entsteht.
##
## Begrenzen heißt verschieben, nicht abschneiden: Eine Zone, die über eine Grenze ragt, rückt mit ihrer Breite in den
## Bereich (ihre Schwierigkeit bleibt); nur eine Zone, die breiter ist als der ganze Bereich, wird auf ihn gekürzt.
## Eine Zone innerhalb bleibt unverändert. Reine Logik.
class_name CadenceRange
extends RefCounted

const DEFAULT_MIN := 60.0
const DEFAULT_MAX := 120.0
## Auswahl im Menü (rpm): untere und obere Grenze. Jede Kombination lässt mindestens 20 rpm Platz.
const MIN_CHOICES := [40.0, 45.0, 50.0, 55.0, 60.0, 65.0, 70.0, 75.0, 80.0]
const MAX_CHOICES := [100.0, 105.0, 110.0, 115.0, 120.0, 125.0, 130.0, 135.0, 140.0, 145.0, 150.0]
## Plausibilitätsgrenze der Kadenz (ADR-0004); gespeicherte Werte außerhalb gelten nicht.
const LIMIT_RPM := 200.0

var minimum := DEFAULT_MIN
var maximum := DEFAULT_MAX


func _init(lower: float = DEFAULT_MIN, upper: float = DEFAULT_MAX) -> void:
	minimum = lower
	maximum = upper


## Die Zone `zone_min`..`zone_max` (rpm) im Bereich: ragt sie hinaus, rückt sie mit gleicher Breite hinein; ist sie
## breiter als der Bereich, wird sie der ganze Bereich. Ergebnis (min, max).
func limit_zone(zone_min: float, zone_max: float) -> Vector2:
	var width := zone_max - zone_min
	if width >= maximum - minimum:
		return Vector2(minimum, maximum)
	var shift := 0.0
	if zone_max > maximum:
		shift = maximum - zone_max
	elif zone_min < minimum:
		shift = minimum - zone_min
	return Vector2(zone_min + shift, zone_max + shift)


## Kadenz an der Stelle `fraction` des Bereichs (0 = untere Grenze, 1 = obere), z. B. 0.5 → Mitte.
func at(fraction: float) -> float:
	return lerpf(minimum, maximum, fraction)


## Liegt die Zone ganz im Bereich (Grenzen eingeschlossen)?
func contains_zone(zone_min: float, zone_max: float) -> bool:
	return zone_min >= minimum - 1e-6 and zone_max <= maximum + 1e-6


func to_dict() -> Dictionary:
	return {"min": minimum, "max": maximum}


## Bereich aus dem Spielstand-Eintrag `value` ({"min", "max"}); fehlt er oder ist er ungültig (keine Zahlen, außerhalb
## 0–LIMIT_RPM, min ≥ max), der Standard.
static func from_dict(value) -> CadenceRange:
	if value is Dictionary:
		var lower = value.get("min")
		var upper = value.get("max")
		if (lower is float or lower is int) and (upper is float or upper is int) and lower >= 0.0 \
				and upper <= LIMIT_RPM and lower < upper:
			return CadenceRange.new(float(lower), float(upper))
	return CadenceRange.new()


## Bereich laut Spielstand (`arcade.cadence_range`).
static func selection(save: SaveGame) -> CadenceRange:
	return from_dict(save.arcade().get("cadence_range"))


## Bereich in den Spielstand schreiben (nicht auf die Platte).
static func choose(save: SaveGame, range_: CadenceRange) -> void:
	save.arcade()["cadence_range"] = range_.to_dict()


## Für die Anzeige, z. B. „60–120 rpm“.
func text() -> String:
	return "%d–%d rpm" % [roundi(minimum), roundi(maximum)]
