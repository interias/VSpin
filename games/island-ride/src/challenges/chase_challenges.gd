## Herausforderungen des Bausteins Jagd (Chase, #47) als Daten – verschoben aus `Encounters` (#63), unverändert.
## Eintrag in der Liste `EncounterRegistry.TYPES`. Format und Parameter: Kopf von `encounters.gd`.
extends RefCounted

const ID := "chase"
const CHALLENGES := [
	# Jagd: länger, mittlere Schwelle; wer nachlässt, wird eingeholt.
	{"id": "jagd_verfolger", "block": ID, "name": "Jagd", "threshold_at": 0.55, "escape_s": 12.0, "catch_s": 12.0,
		"window_s": 30.0, "start_gap": 0.4, "points": 140},
	{"id": "jagd_wild", "block": ID, "name": "Jagd", "threshold_at": 0.65, "escape_s": 10.0, "catch_s": 8.0,
		"window_s": 28.0, "start_gap": 0.35, "points": 170},
]


## Baustein zur Herausforderung `definition` auf der Stufe `level` (ArcadeTiers.get_tier) mit der schon begrenzten
## Zielzone `zone` (Encounters.zone_for, Wächter). Nur über `Encounters.build` aufrufen.
static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock:
	var factor: float = level["duration_factor"]
	return Chase.new(zone.x, zone.y, float(definition["escape_s"]) * factor, float(definition["catch_s"]),
			float(definition["window_s"]) * factor, float(definition.get("start_gap", 0.35)))
