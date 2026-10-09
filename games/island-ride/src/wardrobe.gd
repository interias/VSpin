## Garderobe (#36): Trikots, Radfarben und Helme für den Fahrer. Reine Logik über dem Spielstand; **nur Kosmetik**
## (ADR-0010): die Teile färben Materialien des Fahrermodells (RiderModel.wear) und wirken nicht auf Fahrmodell,
## Rundenzeit, Bestzeit, Medaille oder Training.
##
## Ein Teil ist eine Farbvariante am vorhandenen Modell (keine neuen Modelldateien): Trikot = Trikot und Brustband,
## Radfarbe = Rahmen, Helm = Schale und Streifen. Frei wird es mit dem Fahrerlevel (DriverLevel.UNLOCKS); gesperrte Teile
## sind nicht wählbar. Gespeichert wird das gewählte Teil je Kategorie (SaveGame.wardrobe); fehlt es, ist es unbekannt
## oder (z. B. nach einem zurückgesetzten Stand) gesperrt, gilt der Standard der Kategorie – der Look vor der Garderobe.
class_name Wardrobe
extends RefCounted

## Kategorien in Reihenfolge der Garderobe: Schlüssel (= Präfix der Teil-IDs ohne „_“) → Überschrift.
const CATEGORIES := {"trikot": "Trikot", "radfarbe": "Radfarbe", "helm": "Helm"}
## Standard je Kategorie, ab Level 1 frei.
const DEFAULTS := {"trikot": "trikot_blau", "radfarbe": "radfarbe_rot", "helm": "helm_weiss"}
const _WHITE := Color(0.95, 0.95, 0.95)
const _GOLD := Color(0.86, 0.68, 0.22)
## Teile je Kategorie in Reihenfolge der Freischaltung: ID → Name und Farbe je Material des Fahrermodells.
const PARTS := {
	"trikot_blau": {"name": "Inselblau", "colors": {"jersey": RiderModel.JERSEY_COLOR, "jersey_band": _WHITE}},
	"trikot_weiss": {"name": "Kalkweiß", "colors": {"jersey": Color(0.93, 0.92, 0.88), "jersey_band": RiderModel.JERSEY_COLOR}},
	"trikot_rot": {"name": "Terrakotta", "colors": {"jersey": Color(0.74, 0.3, 0.18), "jersey_band": Color(0.96, 0.9, 0.78)}},
	"trikot_gelb": {"name": "Zitronengelb", "colors": {"jersey": Color(0.98, 0.8, 0.12), "jersey_band": Color(0.08, 0.08, 0.1)}},
	"trikot_gruen": {"name": "Olivgrün", "colors": {"jersey": Color(0.35, 0.45, 0.2), "jersey_band": Color(0.9, 0.84, 0.6)}},
	"trikot_schwarz": {"name": "Nachtschwarz", "colors": {"jersey": Color(0.09, 0.09, 0.12), "jersey_band": _GOLD}},
	"radfarbe_rot": {"name": "Rennrot", "colors": {"frame": RiderModel.FRAME_COLOR}},
	"radfarbe_blau": {"name": "Meerblau", "colors": {"frame": Color(0.08, 0.28, 0.72)}},
	"radfarbe_gruen": {"name": "Piniengrün", "colors": {"frame": Color(0.1, 0.42, 0.24)}},
	"radfarbe_orange": {"name": "Orange", "colors": {"frame": Color(0.95, 0.48, 0.08)}},
	"radfarbe_weiss": {"name": "Weiß", "colors": {"frame": Color(0.92, 0.92, 0.9)}},
	"radfarbe_gold": {"name": "Gold", "colors": {"frame": _GOLD}},
	"helm_weiss": {"name": "Weiß", "colors": {"helmet": Color(0.97, 0.97, 0.97), "helmet_stripe": RiderModel.FRAME_COLOR}},
	"helm_rot": {"name": "Rot", "colors": {"helmet": Color(0.8, 0.12, 0.1), "helmet_stripe": _WHITE}},
	"helm_schwarz": {"name": "Schwarz", "colors": {"helmet": Color(0.1, 0.1, 0.11), "helmet_stripe": Color(0.98, 0.8, 0.12)}},
	"helm_gelb": {"name": "Gelb", "colors": {"helmet": Color(0.98, 0.8, 0.12), "helmet_stripe": Color(0.08, 0.08, 0.1)}},
	"helm_tuerkis": {"name": "Türkis", "colors": {"helmet": Color(0.1, 0.68, 0.66), "helmet_stripe": _WHITE}},
	"helm_gold": {"name": "Gold", "colors": {"helmet": _GOLD, "helmet_stripe": Color(0.09, 0.09, 0.12)}},
}


## Kategorie eines Teils („trikot_gelb“ → „trikot“).
static func category_of(item: String) -> String:
	return item.get_slice("_", 0)


## Teile der Kategorie `category` in Reihenfolge der Freischaltung.
static func parts(category: String) -> Array:
	return PARTS.keys().filter(func(item): return category_of(item) == category)


## Name des Teils für die Anzeige.
static func part_name(item: String) -> String:
	return PARTS[item]["name"] if PARTS.has(item) else item


## Fahrerlevel des Stands (aus den Gesamt-Kilometern).
static func level(save: SaveGame) -> int:
	return DriverLevel.level_for(save.total_km())


## Gewählte Teile: Kategorie → Teil-ID. Nur bekannte, freie Teile der richtigen Kategorie, sonst der Standard.
static func selection(save: SaveGame) -> Dictionary:
	var stored := save.wardrobe()
	var current := level(save)
	var result := {}
	for category in CATEGORIES:
		var item = stored.get(category)
		var valid: bool = item is String and PARTS.has(item) and category_of(item) == category \
				and DriverLevel.unlocked(item, current)
		result[category] = item if valid else DEFAULTS[category]
	return result


## Wählt `item` im Stand `save`, wenn es bekannt und auf dem aktuellen Level frei ist. Gibt zurück, ob es gewählt
## wurde. Schreibt nicht auf die Platte (das macht `SaveGame.save_file`).
static func choose(save: SaveGame, item: String) -> bool:
	if not PARTS.has(item) or not DriverLevel.unlocked(item, level(save)):
		return false
	save.wardrobe()[category_of(item)] = item
	return true


## Farben je Material des Fahrermodells für die Auswahl `chosen` (Kategorie → Teil-ID), für RiderModel.wear.
static func outfit(chosen: Dictionary) -> Dictionary:
	var colors := {}
	for category in CATEGORIES:
		var item: String = chosen.get(category, DEFAULTS[category])
		colors.merge(PARTS.get(item, PARTS[DEFAULTS[category]])["colors"], true)
	return colors
