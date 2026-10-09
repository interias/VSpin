## Stufen des Arcade-Modus (#46, #54, Spec #27; CONTEXT.md „Stufe“, „Empfohlene Stärke“, „Runde“): der gewählte
## Schwierigkeitsgrad als **Daten**, wie Diablos Qualstufen. Eine Stufe bestimmt die Breite der Zielzonen, die Dauer der
## Herausforderungen, wie zäh die Bosse sind, die Punkte und die Qualität der Beute. Die Herausforderungen lesen eine Stufe
## nur über `Encounters.build` (als `level`), also bleibt jede Stufe im Kadenzbereich (Wächter `limit_zone`).
##
## Freischalten (#54): Die ersten START_UNLOCKED Stufen sind von Anfang an wählbar. Eine Stufe ist **abgeschlossen**, wenn
## auf ihr jeder Boss des Rundkurses (die festen Begegnungen, `ArcadeRun.fixed_from_types`) mindestens einmal besiegt
## wurde – über beliebig viele Läufe gesammelt. Der Abschluss der höchsten freien Stufe schaltet die nächste frei. Bosse
## sind die schwersten Begegnungen einer Runde (längste Fenster, höchste Schwellen); wer sie auf einer Stufe besiegt, ist
## für die nächste bereit – und das Ziel ist auf der Seite „Arcade“ und in der Zusammenfassung ablesbar.
##
## Empfohlene Stärke (#54): Jede Stufe nennt eine Stärke, die sie voraussetzt. Die eigene Stärke ergibt sich aus den
## Ausrüstungswerten des Laufs (angelegte Beute plus Talente, gedeckelt wie im Lauf): nur die Werte, die das Lösen
## erleichtern – Zonenbreite und Fortschritt in der Zone (STRENGTH_WEIGHTS); Punkte und Beute-Glück machen lohnender,
## nicht stärker. Sie ist eine **Empfehlung, keine Sperre**: Ausrüstung ersetzt nie das Treten, also darf auch Fitness
## allein eine Stufe tragen (Freischalten geht nur über den Abschluss, nicht über die Ausrüstung).
##
## Rundensteigerung (#54): Jede weitere Runde im selben Lauf wird etwas härter und lohnender (ROUND_* unten: Zone
## schmaler bis zu einer Grenze, Dauer länger bis zu einer Grenze, Punkte und Beute-Qualität höher). `level(tier, lap_index)`
## ist die eine Stelle, an der Stufe und Runde zu den Parametern eines Bausteins werden.
## Gewählt wird im Startmenü; Wahl und Freischaltung stehen im Spielstand (`arcade.tier`, `arcade.unlocked`,
## `arcade.defeated`). Wirkt nur im Arcade-Modus (ADR-0010).
class_name ArcadeTiers
extends RefCounted

## Je Stufe: Nummer, Name, Beschreibung, Breite der Zielzone (rpm), Faktor auf die Dauern der Herausforderungen, Faktor auf
## ihre Punkte, Grundqualität der Beute (Faktor, ArcadeRun.loot_quality), zusätzlicher Faktor auf die Dauern der
## Boss-Phasen (zähere Bosse) und die empfohlene Stärke.
const LIST := [
	{"tier": 1, "name": "Stufe 1", "description": "Breite Zonen (20 rpm), kurze Herausforderungen",
		"zone_width_rpm": 20.0, "duration_factor": 1.0, "points_factor": 1.0, "loot_quality": 1.0, "boss_factor": 1.0,
		"strength": 0},
	{"tier": 2, "name": "Stufe 2", "description": "Zonen 14 rpm, länger halten, doppelte Punkte",
		"zone_width_rpm": 14.0, "duration_factor": 1.25, "points_factor": 2.0, "loot_quality": 1.25, "boss_factor": 1.0,
		"strength": 10},
	{"tier": 3, "name": "Stufe 3", "description": "Schmale Zonen (10 rpm), lange halten, dreifache Punkte",
		"zone_width_rpm": 10.0, "duration_factor": 1.5, "points_factor": 3.0, "loot_quality": 1.5, "boss_factor": 1.0,
		"strength": 20},
	{"tier": 4, "name": "Stufe 4", "description": "Zonen 9 rpm, zähere Bosse, vierfache Punkte",
		"zone_width_rpm": 9.0, "duration_factor": 1.6, "points_factor": 4.0, "loot_quality": 1.8, "boss_factor": 1.1,
		"strength": 35},
	{"tier": 5, "name": "Stufe 5", "description": "Zonen 8 rpm, zähe Bosse, fünffache Punkte",
		"zone_width_rpm": 8.0, "duration_factor": 1.7, "points_factor": 5.0, "loot_quality": 2.2, "boss_factor": 1.2,
		"strength": 50},
	{"tier": 6, "name": "Stufe 6", "description": "Zonen 7 rpm, zäheste Bosse, sechsfache Punkte",
		"zone_width_rpm": 7.0, "duration_factor": 1.8, "points_factor": 6.0, "loot_quality": 2.7, "boss_factor": 1.3,
		"strength": 70},
]
const DEFAULT := 1
## So viele Stufen sind ohne Abschluss wählbar.
const START_UNLOCKED := 3
## Gewicht je Ausrüstungswert (Loot.STATS) in der Stärke; fehlende Werte zählen nicht. Mit den Obergrenzen (10 rpm, 60 %)
## reicht die Stärke von 0 bis 100.
const STRENGTH_WEIGHTS := {"zone_width_rpm": 4, "progress_pct": 1}

## Rundensteigerung je weitere Runde im Lauf (Runde 2 = ein Schritt): Zone schmaler (rpm) bis höchstens ROUND_ZONE_MAX_RPM
## und nie schmaler als ROUND_ZONE_FLOOR_RPM, Dauer länger (Anteil) bis höchstens ROUND_DURATION_MAX, Punkte höher
## (Anteil, ohne Grenze), Beute-Qualität höher (Anteil) bis höchstens ROUND_LOOT_MAX.
const ROUND_ZONE_STEP_RPM := 1.0
const ROUND_ZONE_MAX_RPM := 3.0
const ROUND_ZONE_FLOOR_RPM := 6.0
const ROUND_DURATION_STEP := 0.04
const ROUND_DURATION_MAX := 0.2
const ROUND_POINTS_STEP := 0.1
const ROUND_LOOT_STEP := 0.05
const ROUND_LOOT_MAX := 0.5


## Stufe `tier` (unbekannt → Stufe DEFAULT).
static func get_tier(tier: int) -> Dictionary:
	for entry in LIST:
		if entry["tier"] == tier:
			return entry
	return LIST[0]


## Gültige Stufennummer (unbekannt → DEFAULT).
static func valid(tier) -> int:
	return int(get_tier(int(tier) if tier is float or tier is int else DEFAULT)["tier"])


## Parameter für einen Baustein auf Stufe `tier` in der Runde `lap_index` des Laufs (0 = erste Runde): die Stufe mit der
## Rundensteigerung (`zone_width_rpm`, `duration_factor`, `points_factor`, `loot_quality`).
## `boss`: Phase eines Bosses – die Dauer zusätzlich × `boss_factor` der Stufe.
static func level(tier: int, lap_index: int = 0, boss: bool = false) -> Dictionary:
	var result := get_tier(tier).duplicate()
	var bonus := round_bonus(lap_index)
	var width: float = result["zone_width_rpm"]
	result["zone_width_rpm"] = maxf(width - bonus["narrower_rpm"], minf(width, ROUND_ZONE_FLOOR_RPM))
	result["duration_factor"] = float(result["duration_factor"]) * bonus["duration_factor"] \
			* (float(result["boss_factor"]) if boss else 1.0)
	result["points_factor"] = float(result["points_factor"]) * bonus["points_factor"]
	result["loot_quality"] = float(result["loot_quality"]) * bonus["loot_factor"]
	return result


## Rundensteigerung der Runde `lap_index` (0 = erste, keine Steigerung): {narrower_rpm, duration_factor, points_factor,
## loot_factor}.
static func round_bonus(lap_index: int) -> Dictionary:
	var steps := float(maxi(lap_index, 0))
	return {"narrower_rpm": minf(steps * ROUND_ZONE_STEP_RPM, ROUND_ZONE_MAX_RPM),
			"duration_factor": 1.0 + minf(steps * ROUND_DURATION_STEP, ROUND_DURATION_MAX),
			"points_factor": 1.0 + steps * ROUND_POINTS_STEP,
			"loot_factor": 1.0 + minf(steps * ROUND_LOOT_STEP, ROUND_LOOT_MAX)}


## Gewählte Stufe laut Spielstand (`arcade.tier`), höchstens die höchste freigeschaltete.
static func selection(save: SaveGame) -> int:
	return mini(valid(save.arcade().get("tier", DEFAULT)), unlocked(save))


## Stufe in den Spielstand schreiben (nicht auf die Platte).
static func choose(save: SaveGame, tier: int) -> void:
	save.arcade()["tier"] = valid(tier)


# --- Freischalten ----------------------------------------------------------------------------------------------------


## Höchste wählbare Stufe laut Spielstand (`arcade.unlocked`; fehlt oder ungültig → START_UNLOCKED).
static func unlocked(save: SaveGame) -> int:
	var value = save.arcade().get("unlocked")
	var count := int(value) if value is float or value is int else START_UNLOCKED
	return clampi(count, START_UNLOCKED, LIST.size())


static func is_unlocked(save: SaveGame, tier: int) -> bool:
	return tier >= 1 and tier <= unlocked(save)


## Ids der Bosse, die eine Stufe zum Abschluss besiegt haben muss (feste Begegnungen mit `boss`, Registry-Reihenfolge).
static func bosses() -> Array:
	return ArcadeRun.fixed_from_types().filter(func(d): return d.get("boss", false)).map(func(d): return d["id"])


## Auf Stufe `tier` schon besiegte Bosse (Ids in Reihenfolge von `bosses`; `arcade.defeated["<stufe>"]`, Ungültiges zählt
## nicht).
static func defeated(save: SaveGame, tier: int) -> Array:
	var all = save.arcade().get("defeated")
	var list = all.get(str(tier)) if all is Dictionary else null
	if not list is Array:
		return []
	return bosses().filter(func(id): return list.has(id))


## Stufe `tier` abgeschlossen: jeder Boss auf ihr mindestens einmal besiegt.
static func completed(save: SaveGame, tier: int) -> bool:
	return not bosses().is_empty() and defeated(save, tier).size() == bosses().size()


## Trägt die im Lauf `run` besiegten Bosse für seine Stufe ein und schaltet die nächste Stufe frei, wenn die Stufe damit
## abgeschlossen und die höchste freie ist. Liefert die neu freigeschaltete Stufe (0 = keine). Schreibt nicht auf die Platte.
static func record_run(save: SaveGame, run: ArcadeRun) -> int:
	var won: Array = run.results.filter(func(r): return r.get("boss", false) and r["succeeded"]).map(func(r): return r["id"])
	if won.is_empty():
		return 0
	if not (save.arcade().get("defeated") is Dictionary):
		save.arcade()["defeated"] = {}
	var list := defeated(save, run.tier)
	for id in won:
		if not list.has(id):
			list.append(id)
	save.arcade()["defeated"][str(run.tier)] = list
	var next := run.tier + 1
	if not completed(save, run.tier) or next > LIST.size() or next <= unlocked(save):
		return 0
	save.arcade()["unlocked"] = next
	return next


# --- Empfohlene Stärke -----------------------------------------------------------------------------------------------


## Stärke aus Ausrüstungswerten `modifiers` (Format Loot.modifiers): Summe der Werte × STRENGTH_WEIGHTS, jeder Wert erst auf
## 0..Obergrenze (Loot.STATS) begrenzt.
static func strength_of(modifiers: Dictionary) -> int:
	var total := 0
	for stat in STRENGTH_WEIGHTS:
		var cap := int(Loot.STATS[stat]["cap"])
		total += clampi(int(modifiers.get(stat, 0)), 0, cap) * int(STRENGTH_WEIGHTS[stat])
	return total


## Eigene Stärke laut Spielstand: angelegte Ausrüstung plus Talente, je Wert gedeckelt – so, wie sie im Lauf wirken.
static func strength(save: SaveGame) -> int:
	var gear := Inventory.modifiers(save)
	var talents := Talents.gear_bonus(save)
	var combined := {}
	for stat in Loot.STATS:
		combined[stat] = int(gear.get(stat, 0)) + int(talents.get(stat, 0))
	return strength_of(combined)


## Empfohlene Stärke der Stufe `tier`.
static func recommended_strength(tier: int) -> int:
	return int(get_tier(tier)["strength"])
