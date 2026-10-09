## Begegnungen des Arcade-Modus (#46, Spec #27): Herausforderungen als **Daten**, die Bausteine (ChallengeBlock)
## kombinieren – neue Herausforderungen, Elite-Eigenschaften (#52) und Boss-Phasen (#51) entstehen als Einträge, nicht
## als Sonderlogik. Hier gibt es den Baustein Zone halten (ZoneHold); Durchbruch, Takt-Tore, Jagd und Sammeln (#47, #48)
## kommen als weiterer Baustein in `build` und als Einträge in CHALLENGES dazu.
##
## Eine Herausforderung: {id, block, name, points, …Parameter des Bausteins}. Zone halten:
##   zone_at   Lage der Zielzone im persönlichen Kadenzbereich (0 = untere Grenze, 1 = obere; Breite aus der Stufe)
##   zone_rpm  stattdessen eine feste Zone [min, max] in rpm
##   hold_s    so lange muss die Kadenz in der Zone liegen; window_s  Zeitfenster dafür (beides × Dauer-Faktor der Stufe)
##
## `build` ist die einzige Stelle, an der aus Daten ein Baustein wird; dort wird jede Zielzone auf den persönlichen
## Kadenzbereich begrenzt (CadenceRange.limit_zone) – nach allem, was Stufe (und später Eigenschaften) an ihr ändern.
class_name Encounters
extends RefCounted

const ZONE_HOLD := "zone_hold"
## Die Herausforderungen, aus denen der Arcade-Lauf je Abschnitt würfelt.
const CHALLENGES := [
	{"id": "zone_mitte", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.5, "hold_s": 15.0, "window_s": 30.0,
		"points": 100},
	{"id": "zone_ruhig", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.35, "hold_s": 20.0, "window_s": 35.0,
		"points": 120},
	{"id": "zone_zuegig", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.62, "hold_s": 12.0, "window_s": 25.0,
		"points": 120},
]


## Herausforderung `id` aus `pool` ({} = unbekannt).
static func find(id: String, pool: Array = CHALLENGES) -> Dictionary:
	for definition in pool:
		if definition["id"] == id:
			return definition
	return {}


## `count` Herausforderungen aus `pool`, mit `rng` gewürfelt (Wiederholungen möglich).
static func roll(rng: RandomNumberGenerator, count: int, pool: Array = CHALLENGES) -> Array:
	var result := []
	if pool.is_empty():
		return result
	for i in range(count):
		result.append(pool[rng.randi_range(0, pool.size() - 1)])
	return result


## Baustein der Herausforderung `definition` auf Stufe `tier` im Kadenzbereich `cadence_range` (null bei unbekanntem
## Baustein).
static func build(definition: Dictionary, tier: int, cadence_range: CadenceRange) -> ChallengeBlock:
	var level := ArcadeTiers.get_tier(tier)
	match definition.get("block"):
		ZONE_HOLD:
			var zone := zone_for(definition, tier, cadence_range)
			var factor: float = level["duration_factor"]
			return ZoneHold.new(zone.x, zone.y, float(definition["hold_s"]) * factor,
					float(definition["window_s"]) * factor)
	push_warning("Encounters: unbekannter Baustein %s" % definition.get("block"))
	return null


## Zielzone (min, max) in rpm der Herausforderung auf Stufe `tier`: feste Zone oder Lage im Bereich mit der Breite der
## Stufe (Mitte auf ganze rpm) – immer begrenzt auf `cadence_range` (Wächter, CadenceRange.limit_zone).
static func zone_for(definition: Dictionary, tier: int, cadence_range: CadenceRange) -> Vector2:
	var zone: Vector2
	if definition.get("zone_rpm") is Array:
		zone = Vector2(float(definition["zone_rpm"][0]), float(definition["zone_rpm"][1]))
	else:
		var center := roundf(cadence_range.at(float(definition.get("zone_at", 0.5))))
		var half: float = ArcadeTiers.get_tier(tier)["zone_width_rpm"] / 2.0
		zone = Vector2(center - half, center + half)
	return cadence_range.limit_zone(zone.x, zone.y)


## Punkte für das Schaffen der Herausforderung auf Stufe `tier`.
static func points_for(definition: Dictionary, tier: int) -> int:
	return roundi(float(definition.get("points", 0)) * ArcadeTiers.get_tier(tier)["points_factor"])
