## Herausforderungen des Bausteins Takt-Tore (RhythmGates, #48) als Daten. Eintrag in `EncounterRegistry.TYPES`.
## Zielzone wie bei Zone halten (`zone_at`, Breite aus der Stufe, Ausrüstung, Wächter – `Encounters.zone_for`). Dazu:
##   beats        Zahl der Tore (× Dauer-Faktor der Stufe)
##   need         nötige Treffer (× Dauer-Faktor, höchstens `beats`)
##   first_s      Zeit bis zum ersten Taktschlag nach dem Start (s)
##   interval_s   Abstand der Taktschläge (s)
##   tolerance_s  halbe Breite des Zeitfensters um einen Schlag (s): so lange vor/nach dem Schlag zählt ein Treffer
## Zwischen den Schlägen ist die Kadenz frei – nur im Fenster um den Schlag muss sie in der Zielzone liegen.
extends RefCounted

const ID := "rhythm_gates"
const CHALLENGES := [
	# Ruhiger Takt: weiter Abstand, großzügiges Fenster, Zone eher locker.
	{"id": "takt_ruhig", "block": ID, "name": "Takt-Tore", "zone_at": 0.4, "beats": 5, "need": 4, "first_s": 6.0,
		"interval_s": 5.0, "tolerance_s": 1.0, "points": 120},
	# Flotter Takt: dichter, engeres Fenster, Zone höher.
	{"id": "takt_flott", "block": ID, "name": "Takt-Tore", "zone_at": 0.65, "beats": 6, "need": 5, "first_s": 6.0,
		"interval_s": 4.0, "tolerance_s": 0.8, "points": 160},
]


## Baustein zur Herausforderung `definition` auf der Stufe `level` (ArcadeTiers.level) mit der schon begrenzten
## Zielzone `zone` (Encounters.zone_for, Wächter). Nur über `Encounters.build` aufrufen.
static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock:
	var factor: float = level["duration_factor"]
	var beats := maxi(roundi(float(definition["beats"]) * factor), 1)
	var need := clampi(roundi(float(definition["need"]) * factor), 1, beats)
	return RhythmGates.new(zone.x, zone.y, beats, need, float(definition["first_s"]), float(definition["interval_s"]),
			float(definition["tolerance_s"]))
