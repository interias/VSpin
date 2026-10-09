## Begegnungen des Arcade-Modus (#46, Spec #27): Herausforderungen als **Daten**, die Bausteine (ChallengeBlock)
## kombinieren – neue Herausforderungen, Elite-Eigenschaften (#52) und Boss-Phasen (#51) entstehen als Einträge, nicht
## als Sonderlogik. Hier gibt es die Bausteine Zone halten (ZoneHold), Durchbruch (Breakthrough) und Jagd (Chase, #47);
## Takt-Tore und Sammeln (#48) kommen als weiterer Baustein in `build` und als Einträge in CHALLENGES dazu.
##
## Eine Herausforderung: {id, block, name, points, …Parameter des Bausteins}. Zone halten:
##   zone_at   Lage der Zielzone im persönlichen Kadenzbereich (0 = untere Grenze, 1 = obere; Breite aus der Stufe)
##   zone_rpm  stattdessen eine feste Zone [min, max] in rpm
##   hold_s    so lange muss die Kadenz in der Zone liegen; window_s  Zeitfenster dafür (beides × Dauer-Faktor der Stufe)
## Durchbruch und Jagd haben statt einer Zone eine **Schwelle** (#47): `threshold_at` ist ihre Lage im persönlichen
## Bereich (0..1); die Zone der Anzeige ist [Schwelle, obere Grenze des Bereichs], die Schwelle liegt also nie darüber.
## Höhere Stufen heben die Schwelle (je schmalerer Stufenzone um die halbe Differenz zur Breite von Stufe 1).
##   Durchbruch: fill_s  Zeit über der Schwelle bis der Balken voll ist, window_s  Zeitfenster (beides × Dauer-Faktor),
##               decay  Sinkrate unter der Schwelle (Anteil der Füllrate)
##   Jagd:       escape_s  Zeit über der Schwelle, bis der Verfolger abgehängt ist (× Dauer-Faktor), catch_s  Zeit unter
##               der Schwelle, bis er einholt, window_s  Zeitfenster (× Dauer-Faktor), start_gap  Vorsprung am Anfang
##
## `build` ist die einzige Stelle, an der aus Daten ein Baustein wird; dort wird jede Zielzone auf den persönlichen
## Kadenzbereich begrenzt (CadenceRange.limit_zone) – nach allem, was Stufe, Ausrüstung (#49) (und später
## Eigenschaften) an ihr ändern.
##
## Ausrüstung (#49): `gear` sind die Modifikatoren der angelegten Beute (Loot.modifiers, {} = keine). Sie verbreitert die
## Zielzone um `zone_width_rpm` (je zur Hälfte nach unten und oben, danach der Wächter) und setzt den Faktor auf den
## Fortschritt in der Zone (`progress_pct`, ChallengeBlock.progress_factor). Nur der Arcade-Lauf reicht sie herein.
class_name Encounters
extends RefCounted

const ZONE_HOLD := "zone_hold"
const BREAKTHROUGH := "breakthrough"
const CHASE := "chase"
## Die Herausforderungen, aus denen der Arcade-Lauf je Abschnitt würfelt.
const CHALLENGES := [
	{"id": "zone_mitte", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.5, "hold_s": 15.0, "window_s": 30.0,
		"points": 100},
	{"id": "zone_ruhig", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.35, "hold_s": 20.0, "window_s": 35.0,
		"points": 120},
	{"id": "zone_zuegig", "block": ZONE_HOLD, "name": "Zone halten", "zone_at": 0.62, "hold_s": 12.0, "window_s": 25.0,
		"points": 120},
	# Durchbruch: kurze harte Anstrengung hoch im Bereich (Zugbrücke).
	{"id": "durchbruch_bruecke", "block": BREAKTHROUGH, "name": "Durchbruch", "threshold_at": 0.8, "fill_s": 6.0,
		"window_s": 18.0, "decay": 0.5, "points": 140},
	{"id": "durchbruch_spurt", "block": BREAKTHROUGH, "name": "Durchbruch", "threshold_at": 0.9, "fill_s": 4.0,
		"window_s": 14.0, "decay": 0.5, "points": 160},
	# Jagd: länger, mittlere Schwelle; wer nachlässt, wird eingeholt.
	{"id": "jagd_verfolger", "block": CHASE, "name": "Jagd", "threshold_at": 0.55, "escape_s": 12.0, "catch_s": 12.0,
		"window_s": 30.0, "start_gap": 0.4, "points": 140},
	{"id": "jagd_wild", "block": CHASE, "name": "Jagd", "threshold_at": 0.65, "escape_s": 10.0, "catch_s": 8.0,
		"window_s": 28.0, "start_gap": 0.35, "points": 170},
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


## Baustein der Herausforderung `definition` auf Stufe `tier` im Kadenzbereich `cadence_range` mit der Ausrüstung
## `gear` (null bei unbekanntem Baustein).
static func build(definition: Dictionary, tier: int, cadence_range: CadenceRange,
		gear: Dictionary = {}) -> ChallengeBlock:
	var level := ArcadeTiers.get_tier(tier)
	var block: ChallengeBlock = null
	match definition.get("block"):
		ZONE_HOLD:
			var zone := zone_for(definition, tier, cadence_range, gear)
			var factor: float = level["duration_factor"]
			block = ZoneHold.new(zone.x, zone.y, float(definition["hold_s"]) * factor,
					float(definition["window_s"]) * factor)
		BREAKTHROUGH:
			var zone := zone_for(definition, tier, cadence_range, gear)
			var factor: float = level["duration_factor"]
			block = Breakthrough.new(zone.x, zone.y, float(definition["fill_s"]) * factor,
					float(definition["window_s"]) * factor, float(definition.get("decay", 0.5)))
		CHASE:
			var zone := zone_for(definition, tier, cadence_range, gear)
			var factor: float = level["duration_factor"]
			block = Chase.new(zone.x, zone.y, float(definition["escape_s"]) * factor, float(definition["catch_s"]),
					float(definition["window_s"]) * factor, float(definition.get("start_gap", 0.35)))
	if block == null:
		push_warning("Encounters: unbekannter Baustein %s" % definition.get("block"))
		return null
	block.progress_factor = 1.0 + maxf(float(gear.get("progress_pct", 0)), 0.0) / 100.0
	return block


## Zielzone (min, max) in rpm der Herausforderung auf Stufe `tier`: feste Zone oder Lage im Bereich mit der Breite der
## Stufe (Mitte auf ganze rpm), mit Ausrüstung `gear` um `zone_width_rpm` breiter – immer begrenzt auf
## `cadence_range` (Wächter, CadenceRange.limit_zone). Bei einer Schwelle (`threshold_at`, #47) ist es
## [Schwelle, obere Grenze des Bereichs]; die Schwelle liegt nie über dieser Grenze, die Ausrüstung senkt sie um die
## halbe Zonenbreite.
static func zone_for(definition: Dictionary, tier: int, cadence_range: CadenceRange,
		gear: Dictionary = {}) -> Vector2:
	var zone: Vector2
	if definition.has("threshold_at"):
		var lift: float = (float(ArcadeTiers.LIST[0]["zone_width_rpm"]) - ArcadeTiers.get_tier(tier)["zone_width_rpm"]) / 2.0
		var threshold := minf(roundf(cadence_range.at(float(definition["threshold_at"]))) + lift, cadence_range.maximum)
		var lower := threshold - maxf(float(gear.get("zone_width_rpm", 0)), 0.0) / 2.0
		return cadence_range.limit_zone(lower, cadence_range.maximum)
	if definition.get("zone_rpm") is Array:
		zone = Vector2(float(definition["zone_rpm"][0]), float(definition["zone_rpm"][1]))
	else:
		var center := roundf(cadence_range.at(float(definition.get("zone_at", 0.5))))
		var half: float = ArcadeTiers.get_tier(tier)["zone_width_rpm"] / 2.0
		zone = Vector2(center - half, center + half)
	var wider := maxf(float(gear.get("zone_width_rpm", 0)), 0.0) / 2.0
	return cadence_range.limit_zone(zone.x - wider, zone.y + wider)


## Ziel der Herausforderung für Anzeige und Starttor: „80–100 rpm“, bei einer Schwelle „ab 111 rpm“ (#47).
static func target_text(definition: Dictionary, zone: Vector2) -> String:
	if definition.has("threshold_at"):
		return "ab %d rpm" % roundi(zone.x)
	return RideHud.zone_range_text(zone.x, zone.y)


## Punkte für das Schaffen der Herausforderung auf Stufe `tier`.
static func points_for(definition: Dictionary, tier: int) -> int:
	return roundi(float(definition.get("points", 0)) * ArcadeTiers.get_tier(tier)["points_factor"])
