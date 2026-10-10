## Wirkung von Talenten und legendärer Beute auf den Arcade-Lauf (#53, Spec #27 Story 15): ein gemeinsames Vokabular von
## **Änderungen** (`changes`, Daten in Talents.NODES und Loot.EFFECTS) und ihre Anwendung auf die Fähigkeiten (#50), die
## Muster-Schwellen und die Ausrüstungswerte `run.gear` des Laufs. Reine Logik, nur Arcade (ADR-0010: aufgerufen aus dem
## `run_hook` der Bühne, Rundfahrt und Training sehen nichts davon).
##
## Eine Änderung ist ein Dictionary in genau einer dieser Formen:
##   {"ability": id, "key": "power"|"duration_s"|"cooldown_s", "add": Zahl}  oder  "mul": Faktor  – `abilities.defs[id][key]`
##   {"pattern": Schlüssel aus CadencePatterns.THRESHOLDS, "add": Zahl}      – `patterns.thresholds`
##   {"gear": Wert aus Loot.STATS, "add": ganze Zahl}                         – `run.gear` (additiv, gedeckelt durch `cap`)
##   {"knockback": {"chase_gap": Anteil, "breakthrough_fill": Anteil}}        – Rückstoß, wenn die Windböe auslöst
## Reihenfolge: erst die Talente, dann die Beute (`changes_for`); `add` und `mul` wirken in dieser Reihenfolge.
##
## **Grenzen** (Implementation Decisions #27): nichts hier erzeugt Fortschritt ohne Kadenz oder ändert eine Zielzone – es
## werden nur Daten der Fähigkeiten (die selbst nur mit Kadenz in der Zone wirken), Schwellen der Muster und Modifikatoren
## in `run.gear` verschoben; die Zonenbreite läuft weiter durch `Encounters.zone_for` und den Wächter `limit_zone`.
## Abklingzeiten fallen nie unter MIN_COOLDOWN_S, Schwellen nie unter MIN_THRESHOLD; der Rückstoß hilft nur bei Kadenz über
## der Schwelle und lässt immer ein Stück bis zum Erfolg offen (KNOCK_CEILING).
class_name BuildEffects
extends RefCounted

const MIN_COOLDOWN_S := 3.0
const MIN_THRESHOLD := 1.0
## Der Rückstoß schiebt Abstand/Balken höchstens bis hierher; den Rest muss die Kadenz leisten.
const KNOCK_CEILING := 0.95
const ABILITY_KEYS := ["power", "duration_s", "cooldown_s"]


## Alle Änderungen des Spielstands für einen Arcade-Lauf: erst die erlernten Talente, dann die Effekte der **angelegten**
## legendären Teile (derselbe Effekt zählt nur einmal, auch bei zwei Teilen).
static func changes_for(save: SaveGame) -> Array:
	var result: Array = Talents.changes(save)
	result.append_array(effect_changes(save))
	return result


## Die Änderungen der Effekte angelegter legendärer Teile (in Reihenfolge der Plätze, jeder Effekt einmal).
static func effect_changes(save: SaveGame) -> Array:
	var result := []
	var seen := []
	var worn := Inventory.equipped(save)
	for slot in Loot.SLOTS:
		if not worn.has(slot):
			continue
		var effect := Loot.effect_of(worn[slot])
		if effect != "" and not seen.has(effect):
			seen.append(effect)
			result.append_array(Loot.EFFECTS[effect]["changes"])
	return result


## Wendet `changes` auf die Fähigkeiten `abilities`, die Muster `patterns` (beide dürfen null sein – dann entfallen ihre
## Änderungen) und `run.gear` an. Liefert {"knockback": {chase_gap, breakthrough_fill} (Summe, {} = keiner),
## "thresholds": [geänderte Schlüssel der Muster]}.
static func apply(changes: Array, run: ArcadeRun, abilities: Abilities, patterns: CadencePatterns) -> Dictionary:
	var knockback := {}
	var thresholds := []
	for change in changes:
		if change.has("ability"):
			if abilities != null:
				_change_ability(abilities, change)
		elif change.has("pattern"):
			if patterns != null and patterns.thresholds.has(change["pattern"]):
				patterns.thresholds[change["pattern"]] = maxf(float(patterns.thresholds[change["pattern"]])
						+ float(change["add"]), MIN_THRESHOLD)
				if not thresholds.has(change["pattern"]):
					thresholds.append(change["pattern"])
		elif change.has("gear"):
			_change_gear(run, change)
		elif change.has("knockback"):
			for key in change["knockback"]:
				knockback[key] = float(knockback.get(key, 0.0)) + float(change["knockback"][key])
	return {"knockback": knockback, "thresholds": thresholds}


## Rückstoß auf den laufenden Baustein `block` (die Windböe hat ausgelöst, `cadence_rpm` ist die Kadenz dieses Schritts): die
## Jagd bekommt `chase_gap` mehr Abstand, der Durchbruch `breakthrough_fill` mehr Balken – nur bei Kadenz über der Schwelle
## und höchstens bis KNOCK_CEILING (der Erfolg bleibt dem Treten vorbehalten). Alle anderen Bausteine: nichts. Liefert, ob
## etwas geschoben wurde.
static func knock_back(block: ChallengeBlock, cadence_rpm: float, knockback: Dictionary) -> bool:
	if block == null or block.state != ChallengeBlock.RUNNING:
		return false
	if block is Chase and block.above(cadence_rpm) and knockback.get("chase_gap", 0.0) > 0.0:
		var pushed := maxf(block.gap, minf(block.gap + float(knockback["chase_gap"]), KNOCK_CEILING))
		block.gap = pushed
		block.best_gap = maxf(block.best_gap, pushed)
		return true
	if block is Breakthrough and block.above(cadence_rpm) and knockback.get("breakthrough_fill", 0.0) > 0.0:
		block.level = maxf(block.level, minf(block.level + float(knockback["breakthrough_fill"]), KNOCK_CEILING))
		return true
	return false


static func _change_ability(abilities: Abilities, change: Dictionary) -> void:
	var id: String = change["ability"]
	var key: String = change["key"]
	if not abilities.defs.has(id) or not ABILITY_KEYS.has(key) or not abilities.defs[id].has(key):
		return
	var value := float(abilities.defs[id][key])
	value = value * float(change["mul"]) if change.has("mul") else value + float(change.get("add", 0.0))
	abilities.defs[id][key] = maxf(value, MIN_COOLDOWN_S if key == "cooldown_s" else 0.0)


static func _change_gear(run: ArcadeRun, change: Dictionary) -> void:
	var stat: String = change["gear"]
	if not Loot.STATS.has(stat):
		return
	run.gear[stat] = clampi(int(run.gear.get(stat, 0)) + int(change["add"]), 0, int(Loot.STATS[stat]["cap"]))
