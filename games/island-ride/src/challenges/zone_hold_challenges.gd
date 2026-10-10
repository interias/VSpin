## Herausforderungen des Bausteins Zone halten (ZoneHold, #46) als Daten – verschoben aus `Encounters` (#63), unverändert.
## Eintrag in der Liste `EncounterRegistry.TYPES`. Format und Parameter: Kopf von `encounters.gd`.
extends RefCounted

const ID := "zone_hold"
const CHALLENGES := [
	{"id": "zone_mitte", "block": ID, "name": "Zone halten", "zone_at": 0.5, "hold_s": 15.0, "window_s": 30.0,
		"points": 100},
	{"id": "zone_ruhig", "block": ID, "name": "Zone halten", "zone_at": 0.35, "hold_s": 20.0, "window_s": 35.0,
		"points": 120},
	{"id": "zone_zuegig", "block": ID, "name": "Zone halten", "zone_at": 0.62, "hold_s": 12.0, "window_s": 25.0,
		"points": 120},
]


## Baustein zur Herausforderung `definition` auf der Stufe `level` (ArcadeTiers.get_tier) mit der schon begrenzten
## Zielzone `zone` (Encounters.zone_for, Wächter). Nur über `Encounters.build` aufrufen.
static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock:
	var factor: float = level["duration_factor"]
	return ZoneHold.new(zone.x, zone.y, float(definition["hold_s"]) * factor, float(definition["window_s"]) * factor)
