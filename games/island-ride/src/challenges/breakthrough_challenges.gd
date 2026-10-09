## Herausforderungen des Bausteins Durchbruch (Breakthrough, #47) als Daten – verschoben aus `Encounters` (#63),
## unverändert. Eintrag in der Liste `EncounterRegistry.TYPES`. Format und Parameter: Kopf von `encounters.gd`.
extends RefCounted

const ID := "breakthrough"
const CHALLENGES := [
	# Durchbruch: kurze harte Anstrengung hoch im Bereich (Zugbrücke).
	{"id": "durchbruch_bruecke", "block": ID, "name": "Durchbruch", "threshold_at": 0.8, "fill_s": 6.0,
		"window_s": 18.0, "decay": 0.5, "points": 140},
	{"id": "durchbruch_spurt", "block": ID, "name": "Durchbruch", "threshold_at": 0.9, "fill_s": 4.0,
		"window_s": 14.0, "decay": 0.5, "points": 160},
]


## Baustein zur Herausforderung `definition` auf der Stufe `level` (ArcadeTiers.get_tier) mit der schon begrenzten
## Zielzone `zone` (Encounters.zone_for, Wächter). Nur über `Encounters.build` aufrufen.
static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock:
	var factor: float = level["duration_factor"]
	return Breakthrough.new(zone.x, zone.y, float(definition["fill_s"]) * factor,
			float(definition["window_s"]) * factor, float(definition.get("decay", 0.5)))
