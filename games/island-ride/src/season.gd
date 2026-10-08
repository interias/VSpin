## Jahreszeit der Insel (#39): folgt wie die Tageszeit dem echten Datum auf Mallorca (dieselbe Uhr, DayNight) oder
## steht fest (Menü). Fünf Phasen, Grenzen nach dem mallorquinischen Jahr (Tag/Monat, Ortszeit; Schaltjahre ohne
## Sonderfall, der 29.02. liegt in der Mandelblüte):
##   almond  Mandelblüte  25.01.–09.03.  Mandelbäume blühen weiß-rosa (Höhepunkt Februar), Wiesen grün
##   spring  Frühling     10.03.–31.05.  saftig grün, Mohn am Wegrand (April/Mai), junges Getreide
##   summer  Sommer       01.06.–15.09.  Ernte im Juni, danach trocken: Gras und Felder goldgelb
##   autumn  Herbst       16.09.–30.11.  nach den ersten Herbstregen: Stoppelfelder, ockerfarbenes Gras
##   winter  Winter       01.12.–24.01.  Regenzeit: grün, frisch gesäte Felder
## Für die Erfolge (Achievements.SEASONS, vier Werte) zählt die Mandelblüte als Frühling – der Erfolg „spring“ heißt
## dort „Mandelblüte“.
## `LOOKS` hält je Phase die Farben der Welt (siehe `IslandWorld.set_season`): Vegetation und Boden
## (`IslandVegetation.set_palette`), Faktoren auf die Kenney-Vegetation nach Materialname (`IslandWorld.tint_nature`)
## und ob der Mohn blüht. Die Farbstimmung des Lichts steht an einer Stelle in `SkyController.SEASON_MOOD`.
class_name Season
extends RefCounted

const ALMOND := "almond"
const SPRING := "spring"
const SUMMER := "summer"
const AUTUMN := "autumn"
const WINTER := "winter"
const PHASES := [ALMOND, SPRING, SUMMER, AUTUMN, WINTER]
## Modus: nach dem Datum (echt) oder eine gewählte Phase (fest).
const MODE_REAL := "real"
const MODE_FIXED := "fixed"
const MODES := [MODE_REAL, MODE_FIXED]
## Beginn je Phase: [Monat, Tag, Phase], nach Datum sortiert; vor dem ersten Eintrag gilt der letzte (Winter).
const STARTS := [[1, 25, ALMOND], [3, 10, SPRING], [6, 1, SUMMER], [9, 16, AUTUMN], [12, 1, WINTER]]
## Namen im Menü.
const NAMES := {ALMOND: "Mandelblüte", SPRING: "Frühling", SUMMER: "Sommer", AUTUMN: "Herbst", WINTER: "Winter"}

## Farben je Phase. palette: Schlüssel wie IslandVegetation.PALETTE; nature: Faktor je Materialname der
## Kenney-Modelle (Gras, Laub); poppies: Mohn sichtbar.
const LOOKS := {
	ALMOND: {
		"palette": {"Gras": Color(0.44, 0.6, 0.28), "Unterholz": Color(0.37, 0.5, 0.24), "Strauch": Color(0.28, 0.42, 0.2),
			"Boden_Erde": Color(1.0, 0.96, 0.91), "Boden_Gras": Color(0.88, 1.0, 0.84), "Mohn": Color(1.0, 1.0, 1.0),
			"Mandelbaum": Color(1.0, 0.86, 0.9), "Getreide": Color(0.46, 0.64, 0.3)},
		"nature": {"grass": Color(0.96, 1.1, 0.96), "leafsGreen": Color(0.97, 1.03, 0.98)},
		"poppies": false,
	},
	SPRING: {
		"palette": {"Gras": Color(0.46, 0.66, 0.26), "Unterholz": Color(0.38, 0.55, 0.22), "Strauch": Color(0.3, 0.45, 0.2),
			"Boden_Erde": Color(1.0, 0.96, 0.9), "Boden_Gras": Color(0.86, 1.0, 0.8), "Mohn": Color(1.0, 1.0, 1.0),
			"Mandelbaum": Color(0.42, 0.56, 0.26), "Getreide": Color(0.5, 0.68, 0.28)},
		"nature": {"grass": Color(0.98, 1.15, 0.92), "leafsGreen": Color(0.98, 1.06, 0.96)},
		"poppies": true,
	},
	SUMMER: {
		"palette": {"Gras": Color(0.84, 0.7, 0.38), "Unterholz": Color(0.62, 0.55, 0.3), "Strauch": Color(0.36, 0.42, 0.22),
			"Boden_Erde": Color(1.0, 0.93, 0.82), "Boden_Gras": Color(1.0, 0.92, 0.74), "Mohn": Color(1.0, 1.0, 1.0),
			"Mandelbaum": Color(0.46, 0.52, 0.28), "Getreide": Color(0.96, 0.78, 0.38)},
		"nature": {"grass": Color(1.55, 1.2, 0.75), "leafsGreen": Color(1.06, 1.0, 0.88)},
		"poppies": false,
	},
	AUTUMN: {
		"palette": {"Gras": Color(0.68, 0.62, 0.34), "Unterholz": Color(0.56, 0.44, 0.26), "Strauch": Color(0.34, 0.41, 0.21),
			"Boden_Erde": Color(1.0, 0.92, 0.84), "Boden_Gras": Color(0.96, 0.95, 0.82), "Mohn": Color(1.0, 1.0, 1.0),
			"Mandelbaum": Color(0.62, 0.5, 0.28), "Getreide": Color(0.78, 0.66, 0.46)},
		"nature": {"grass": Color(1.28, 1.08, 0.8), "leafsGreen": Color(1.08, 0.98, 0.86)},
		"poppies": false,
	},
	WINTER: {
		"palette": {"Gras": Color(0.42, 0.58, 0.28), "Unterholz": Color(0.36, 0.48, 0.25), "Strauch": Color(0.28, 0.41, 0.21),
			"Boden_Erde": Color(0.98, 0.95, 0.91), "Boden_Gras": Color(0.88, 0.99, 0.86), "Mohn": Color(1.0, 1.0, 1.0),
			"Mandelbaum": Color(0.42, 0.39, 0.34), "Getreide": Color(0.44, 0.62, 0.3)},
		"nature": {"grass": Color(0.95, 1.08, 0.97), "leafsGreen": Color(0.95, 1.0, 0.98)},
		"poppies": false,
	},
}


## Phase an einem Datum (Monat, Tag).
static func of_date(month: int, day: int) -> String:
	var phase: String = STARTS[-1][2]
	for start in STARTS:
		if month > start[0] or (month == start[0] and day >= start[1]):
			phase = start[2]
	return phase


## Phase zu `utc_s` (UTC-Sekunden) nach dem Ortsdatum auf Mallorca (MEZ/MESZ wie DayNight).
static func at_unix(utc_s: float) -> String:
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(int(floor(utc_s + DayNight.madrid_utc_offset_h(utc_s) * 3600.0)))
	return of_date(local["month"], local["day"])


## Wert für das Erfolgs-Ereignis `season` (Achievements.SEASONS): die Mandelblüte zählt als Frühling.
static func achievement_season(phase: String) -> String:
	return SPRING if phase == ALMOND else phase
