## Begegnungen des Arcade-Modus (#46, Spec #27): Herausforderungen als **Daten**, die Bausteine (ChallengeBlock)
## kombinieren – neue Herausforderungen, Elite-Eigenschaften (#52) und Boss-Phasen (#51) entstehen als Einträge, nicht
## als Sonderlogik. Hier gibt es die Bausteine Zone halten (ZoneHold), Durchbruch (Breakthrough) und Jagd (Chase, #47);
## Daten und Bauanleitung je Typ stehen in `src/challenges/`, angemeldet in `EncounterRegistry.TYPES` (#63) – Takt-Tore
## und Sammeln (#48) kommen als eigene Datei plus eine Zeile dort dazu (Anleitung im Kopf von `encounter_registry.gd`).
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
## Bosse (#51) kombinieren Bausteine: `phases` ist eine Liste von Herausforderungen (je ein Baustein mit seinen
## Parametern). `build` baut jede Phase wie jede Herausforderung (Wächter, Stufe, Ausrüstung) und gibt sie dem Typ
## (`build_phases(definition, phases)`, src/challenges/boss_challenges.gd); Ziel und Zieltext vor dem Start sind die der
## ersten Phase.
## Elite-Gruppen (#52, src/elite_groups.gd) sind ebenso Phasenfolgen (`block` = "elite"): Anführer und Gefolge. Ihre
## Eigenschaften haben die Daten der Phasen schon verändert, bevor sie hier ankommen. Eine Phase mit `wander` (*Wankelmütig*)
## hat eine **wandernde** Zone: ihre Lage schwingt um `amplitude_at` (Anteil des Bereichs) mit der Dauer `period_s`;
## `zone_for(…, at_s)` liefert die Zone zur Phasenzeit `at_s` – auch sie durch den Wächter.
##
## `build` ist die einzige Stelle, an der aus Daten ein Baustein wird; dort wird jede Zielzone auf den persönlichen
## Kadenzbereich begrenzt (CadenceRange.limit_zone) – nach allem, was Stufe, Ausrüstung (#49) und Elite-Eigenschaften
## (#52, auch in jedem Augenblick einer wandernden Zone) an ihr ändern.
##
## Ausrüstung (#49): `gear` sind die Modifikatoren der angelegten Beute (Loot.modifiers, {} = keine). Sie verbreitert die
## Zielzone um `zone_width_rpm` (je zur Hälfte nach unten und oben, danach der Wächter) und setzt den Faktor auf den
## Fortschritt in der Zone (`progress_pct`, ChallengeBlock.progress_factor). Nur der Arcade-Lauf reicht sie herein.
class_name Encounters
extends RefCounted

const ZONE_HOLD := "zone_hold"
const BREAKTHROUGH := "breakthrough"
const CHASE := "chase"
## Die Herausforderungen, aus denen der Arcade-Lauf je Abschnitt würfelt: die Daten aller Typen aus
## `EncounterRegistry.TYPES` in deren Reihenfolge (#63; bis dahin eine Konstante an dieser Stelle).
static var CHALLENGES: Array = EncounterRegistry.challenges()


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
	var type := EncounterRegistry.type_of(definition.get("block"))
	if type == null:
		push_warning("Encounters: unbekannter Baustein %s" % definition.get("block"))
		return null
	var block: ChallengeBlock
	if definition.get("phases") is Array:  # Boss (#51): Phasen aus Bausteinen, jede hier gebaut (Wächter, Stufe, Ausrüstung)
		var phases := []
		for phase in definition["phases"]:
			phases.append(build(phase, tier, cadence_range, gear))
		block = type.build_phases(definition, phases)
		if block is EliteGroup:  # Elite (#52): wandernde Zonen je Augenblick durch zone_for (Wächter)
			var steps: Array = definition["phases"]
			block.zone_path = func(index: int, at_s: float) -> Vector2:
				return zone_for(steps[index], tier, cadence_range, gear, at_s)
	else:
		block = type.build(definition, ArcadeTiers.get_tier(tier), zone_for(definition, tier, cadence_range, gear))
	if block == null:
		return null
	block.progress_factor = 1.0 + maxf(float(gear.get("progress_pct", 0)), 0.0) / 100.0
	return block


## Zielzone (min, max) in rpm der Herausforderung auf Stufe `tier`: feste Zone oder Lage im Bereich mit der Breite der
## Stufe (Mitte auf ganze rpm), mit Ausrüstung `gear` um `zone_width_rpm` breiter – immer begrenzt auf
## `cadence_range` (Wächter, CadenceRange.limit_zone). Bei einer Schwelle (`threshold_at`, #47) ist es
## [Schwelle, obere Grenze des Bereichs]; die Schwelle liegt nie über dieser Grenze, die Ausrüstung senkt sie um die
## halbe Zonenbreite. `at_s`: Zeit in der Herausforderung (s) – nur für eine wandernde Zone (`wander`, #52) von Belang,
## ihre Lage verschiebt sich vor dem Wächter.
static func zone_for(definition: Dictionary, tier: int, cadence_range: CadenceRange,
		gear: Dictionary = {}, at_s: float = 0.0) -> Vector2:
	if definition.get("phases") is Array and not definition["phases"].is_empty():  # Boss (#51): Ziel der ersten Phase
		return zone_for(definition["phases"][0], tier, cadence_range, gear)
	var zone: Vector2
	var shift := wander_shift(definition, at_s)
	if definition.has("threshold_at"):
		var lift: float = (float(ArcadeTiers.LIST[0]["zone_width_rpm"]) - ArcadeTiers.get_tier(tier)["zone_width_rpm"]) / 2.0
		var threshold := minf(roundf(cadence_range.at(float(definition["threshold_at"]) + shift)) + lift,
				cadence_range.maximum)
		var lower := threshold - maxf(float(gear.get("zone_width_rpm", 0)), 0.0) / 2.0
		return cadence_range.limit_zone(lower, cadence_range.maximum)
	if definition.get("zone_rpm") is Array:
		var moved := shift * (cadence_range.maximum - cadence_range.minimum)
		zone = Vector2(float(definition["zone_rpm"][0]) + moved, float(definition["zone_rpm"][1]) + moved)
	else:
		var center := roundf(cadence_range.at(float(definition.get("zone_at", 0.5)) + shift))
		var half: float = ArcadeTiers.get_tier(tier)["zone_width_rpm"] / 2.0
		zone = Vector2(center - half, center + half)
	var wider := maxf(float(gear.get("zone_width_rpm", 0)), 0.0) / 2.0
	return cadence_range.limit_zone(zone.x - wider, zone.y + wider)


## Wandernde Zone (#52, `wander` = {amplitude_at, period_s}): Verschiebung der Lage (Anteil des Bereichs) zur Zeit `at_s`;
## 0 ohne `wander` und zu Beginn.
static func wander_shift(definition: Dictionary, at_s: float) -> float:
	var wander = definition.get("wander")
	if not wander is Dictionary or float(wander.get("period_s", 0.0)) <= 0.0:
		return 0.0
	return float(wander.get("amplitude_at", 0.0)) * sin(TAU * at_s / float(wander["period_s"]))


## Ziel der Herausforderung für Anzeige und Starttor: „80–100 rpm“, bei einer Schwelle „ab 111 rpm“ (#47).
static func target_text(definition: Dictionary, zone: Vector2) -> String:
	if definition.get("phases") is Array and not definition["phases"].is_empty():  # Boss (#51): Format der ersten Phase
		return target_text(definition["phases"][0], zone)
	if definition.has("threshold_at"):
		return "ab %d rpm" % roundi(zone.x)
	return RideHud.zone_range_text(zone.x, zone.y)


## Punkte für das Schaffen der Herausforderung auf Stufe `tier`.
static func points_for(definition: Dictionary, tier: int) -> int:
	return roundi(float(definition.get("points", 0)) * ArcadeTiers.get_tier(tier)["points_factor"])
