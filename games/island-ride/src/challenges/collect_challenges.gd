## Herausforderungen des Bausteins Sammeln (Collect, #48) als Daten. Eintrag in `EncounterRegistry.TYPES`.
## Der Magnetradius wächst mit der Kadenz von `radius_min_m` bis `radius_max_m`; die **Rampe** dafür ist wie bei
## Durchbruch und Jagd eine Schwelle (`threshold_at`, Lage 0..1 im persönlichen Bereich): sie reicht von der Schwelle
## bis zur oberen Grenze des Bereichs (Encounters.zone_for, Stufe, Ausrüstung, Wächter), liegt also nie außerhalb.
##   offsets      seitlicher Abstand der Sammelobjekte von der Straßenmitte (m, negativ = links); ihre Zahl wird mit dem
##                Dauer-Faktor der Stufe (reihum wiederholt) vervielfacht
##   need         nötige Zahl eingesammelter Objekte (× Dauer-Faktor, höchstens Zahl der Objekte)
##   first_s      Zeit bis zum ersten Objekt nach dem Start (s), interval_s der Abstand der Objekte (s)
##   radius_min_m, radius_max_m   Magnetradius bei der Schwelle bzw. am oberen Bereichsende
extends RefCounted

const ID := "collect"
const CHALLENGES := [
	# Wiese: lockerer Abschnitt, Objekte nah an der Straße; schon mäßige Kadenz sammelt einiges.
	{"id": "sammeln_wiese", "block": ID, "name": "Sammeln", "threshold_at": 0.25, "first_s": 5.0, "interval_s": 3.0,
		"offsets": [1.0, -2.5, 3.0, -1.5, 4.0, 0.5, -3.5, 2.0], "need": 5, "radius_min_m": 1.0, "radius_max_m": 5.0,
		"points": 110},
	# Ufer: mehr Objekte, weiter draußen; ohne hohe Kadenz bleibt der Rand liegen.
	{"id": "sammeln_ufer", "block": ID, "name": "Sammeln", "threshold_at": 0.4, "first_s": 5.0, "interval_s": 2.5,
		"offsets": [2.0, -3.5, 1.0, 4.5, -2.5, 5.0, 0.5, -4.0, 3.0, -1.5], "need": 6, "radius_min_m": 1.0,
		"radius_max_m": 5.5, "points": 150},
]


## Baustein zur Herausforderung `definition` auf der Stufe `level` (ArcadeTiers.level) mit der schon begrenzten
## Rampe `zone` (Encounters.zone_for, Wächter). Nur über `Encounters.build` aufrufen.
static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock:
	var factor: float = level["duration_factor"]
	var base: Array = definition["offsets"]
	var offsets := []
	for i in range(maxi(roundi(base.size() * factor), 1)):
		offsets.append(base[i % base.size()])
	return Collect.new(zone.x, zone.y, float(definition["radius_min_m"]), float(definition["radius_max_m"]), offsets,
			roundi(float(definition["need"]) * factor), float(definition["first_s"]), float(definition["interval_s"]))
