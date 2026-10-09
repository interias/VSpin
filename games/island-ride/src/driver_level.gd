## Fahrerlevel (#35, CONTEXT.md): wächst mit jedem gefahrenen Kilometer in jedem Modus und schaltet **nur Kosmetik**
## frei (Trikots, Radfarben, Helme; ADR-0010). Reine Logik: das Level folgt allein aus den Gesamt-Kilometern; es wirkt
## nicht auf Fahrmodell, Rundenzeit, Bestzeit oder Medaille.
##
## Kurve: Level 1 ab 0 km, der Schritt von Level n zu n + 1 kostet FIRST_STEP_KM + (n − 1) · STEP_GROWTH_KM, also
## Level 2 ab 10 km, 3 ab 25 km, 4 ab 45 km, 5 ab 70 km, 10 ab 270 km, 20 ab 1045 km; höchstens MAX_LEVEL.
##
## Freischaltung (für die Garderobe, #36): `unlock_level(teil)` sagt, ab welchem Level ein Kosmetik-Teil frei ist.
## Namen und Farben der Teile stehen in Wardrobe.PARTS; `UNLOCKS` ist die Tabelle der Level (unbekannte Teile: ab
## Level 1). Je Kategorie ist der heutige Look ab Level 1 frei, die übrigen Teile verteilen sich über die Levelkurve.
class_name DriverLevel
extends RefCounted

const MAX_LEVEL := 50
const FIRST_STEP_KM := 10.0
const STEP_GROWTH_KM := 5.0
## Kosmetik-Teil → Level, ab dem es frei ist (Präfix: trikot_, radfarbe_, helm_). Pflegt die Garderobe (#36).
const UNLOCKS := {
	"trikot_blau": 1, "trikot_weiss": 2, "trikot_rot": 4, "trikot_gelb": 6, "trikot_gruen": 10, "trikot_schwarz": 15,
	"radfarbe_rot": 1, "radfarbe_blau": 3, "radfarbe_gruen": 5, "radfarbe_orange": 8, "radfarbe_weiss": 12,
	"radfarbe_gold": 20,
	"helm_weiss": 1, "helm_rot": 3, "helm_schwarz": 7, "helm_gelb": 11, "helm_tuerkis": 14, "helm_gold": 18,
}


## Gesamt-Kilometer, ab denen `level` erreicht ist (Level 1: 0 km).
static func km_for(level: int) -> float:
	var n := clampi(level, 1, MAX_LEVEL) - 1
	return FIRST_STEP_KM * n + STEP_GROWTH_KM * n * (n - 1) / 2.0


## Level bei `total_km` gefahrenen Kilometern.
static func level_for(total_km: float) -> int:
	var level := 1
	while level < MAX_LEVEL and total_km >= km_for(level + 1):
		level += 1
	return level


## Kilometer bis zum nächsten Level (INF auf MAX_LEVEL).
static func km_to_next(total_km: float) -> float:
	var level := level_for(total_km)
	return INF if level >= MAX_LEVEL else km_for(level + 1) - total_km


## Ab welchem Level ist das Kosmetik-Teil `item` frei?
static func unlock_level(item: String) -> int:
	return UNLOCKS.get(item, 1)


## Ist `item` auf `level` frei?
static func unlocked(item: String, level: int) -> bool:
	return level >= unlock_level(item)
