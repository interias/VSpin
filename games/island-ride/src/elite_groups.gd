## Elite-Gruppen des Arcade (#52, Spec #27 Story 12; CONTEXT.md „Elite-Gruppe“) als **Daten**: Eine Elite-Gruppe ist eine
## gewöhnliche Herausforderung aus dem Würfel-Pool (beliebiger Bausteintyp) mit einer **Elite-Stufe** – blau = Champions,
## gelb = Seltene mit Gefolge – und 1–3 gewürfelten **Eigenschaften**. Jede Eigenschaft verschiebt Parameter der
## Herausforderung (Änderungen je Bausteintyp, unten in `AFFIXES`) oder fügt eine Phase an; daraus entsteht eine neue
## Definition (`make`) mit dem Baustein `elite` (src/challenges/elite_challenges.gd): eine Folge von Phasen wie bei den
## Bossen (#51) – der Anführer (die veränderte Herausforderung), danach das **Gefolge** (kleine Herausforderungen aus
## `RETINUE`). Keine Sonderlogik je Gegner: alles, was gebaut wird, sind vorhandene Bausteine.
##
## Kadenzbereich-Wächter: Eigenschaften ändern nur die **Daten** (Lage `zone_at`/`threshold_at`, Dauern, Zahlen); die
## Zielzone entsteht danach wie bei jeder Herausforderung in `Encounters.zone_for` → `CadenceRange.limit_zone`. Auch die
## wandernde Zone (*Wankelmütig*) läuft in jedem Augenblick dort durch (`Encounters.zone_for` mit der Phasenzeit).
##
## Zufall: `ArcadeRun` würfelt mit einem eigenen Würfel (`roll`) je gewürfelter Herausforderung, ob sie als Elite-Gruppe
## kommt – die Würfe des Pools bleiben bei gleichem Seed gleich. Bosse werden nie zu Elite-Gruppen.
## Bessere Beute: die Definition trägt `loot_quality` der Elite-Stufe (ArcadeRun._finish hebt damit die Grundqualität).
class_name EliteGroups
extends RefCounted

const ID := "elite"
const CHAMPION := "champion"
const RARE := "selten"

## Chance je gewürfelter Herausforderung, dass sie als Elite-Gruppe kommt, und der Anteil der Seltenen darunter.
const CHANCE := 0.15
const RARE_SHARE := 0.35

## Elite-Stufen: Name, Farbe (Seltenheit der Beute als Diablo-Farbcode: magisch = blau, selten = gelb), Zahl der
## Eigenschaften [min, max], Zahl der Gefolgs-Phasen, Faktor auf die Punkte des Anführers, Beute-Qualität (Faktor auf die
## Grundqualität; Bosse 2–2,5).
const RANKS := {
	CHAMPION: {"name": "Champions", "rarity": "magisch", "affixes": [1, 2], "retinue": 0, "points_factor": 1.5,
		"loot_quality": 1.5},
	RARE: {"name": "Seltene", "rarity": "selten", "affixes": [2, 3], "retinue": 1, "points_factor": 2.0,
		"loot_quality": 2.0},
}

## Wandern der Zone (*Wankelmütig*): Ausschlag als Anteil des persönlichen Bereichs (±) und Dauer einer Schwingung (s).
const WANDER := {"amplitude_at": 0.2, "period_s": 16.0}

## Eigenschaften: Name, Beschreibung und Änderungen je Bausteintyp (`"*"` = jeder Typ). Eine Eigenschaft ohne Eintrag für
## einen Typ wird für ihn nicht gewürfelt. Änderungen:
##   {"key", "mul"}        Parameter × Faktor          {"key", "add", "max"?}   Parameter + Wert (höchstens max)
##   {"key", "set"}        Parameter setzen            {"retinue": n}           n Gefolgs-Phasen mehr
##   {"tempo": f}          Taktwechsel: die zweite Hälfte der Takt-Tore als eigene Phase im Abstand × f
## Jede Eigenschaft bleibt mit Kadenz allein lösbar (tests/test_elite_groups.gd spielt jede auf jeder Stufe durch).
const AFFIXES := {
	# Weniger Zeit: kürzeres Zeitfenster; der Verfolger holt schneller auf und ist schwerer abzuhängen; engere Takt-Fenster.
	"windschnell": {"name": "Windschnell", "text": "weniger Zeit, schnellere Verfolger", "changes": {
		"zone_hold": [{"key": "window_s", "mul": 0.8}],
		"breakthrough": [{"key": "window_s", "mul": 0.8}],
		"chase": [{"key": "escape_s", "mul": 1.25}, {"key": "catch_s", "mul": 0.8}],
		"rhythm_gates": [{"key": "tolerance_s", "mul": 0.7}],
	}},
	# Die Zielzone wandert während der Herausforderung auf und ab (nur Bausteine mit Zone; eine Schwelle ist „ab N rpm“,
	# wer weit darüber tritt, merkte vom Wandern nichts).
	"wankelmuetig": {"name": "Wankelmütig", "text": "die Zielzone wandert", "changes": {
		"zone_hold": [{"key": "wander", "set": WANDER}],
		"rhythm_gates": [{"key": "wander", "set": WANDER}],
	}},
	# Zone bzw. Schwelle liegt höher im Bereich.
	"gegenwind": {"name": "Gegenwind", "text": "Zone und Schwelle höher", "changes": {
		"zone_hold": [{"key": "zone_at", "add": 0.1, "max": 0.85}],
		"rhythm_gates": [{"key": "zone_at", "add": 0.1, "max": 0.85}],
		"breakthrough": [{"key": "threshold_at", "add": 0.06, "max": 0.93}],
		"chase": [{"key": "threshold_at", "add": 0.08, "max": 0.85}],
		"collect": [{"key": "threshold_at", "add": 0.1, "max": 0.6}],
	}},
	# Mehr Ausdauer: länger halten, mehr Balken, weniger Vorsprung, ein Treffer bzw. ein Objekt mehr.
	"zaeh": {"name": "Zäh", "text": "länger halten, mehr Balken", "changes": {
		"zone_hold": [{"key": "hold_s", "mul": 1.3}],
		"breakthrough": [{"key": "fill_s", "mul": 1.3}],
		"chase": [{"key": "start_gap", "mul": 0.75}],
		"rhythm_gates": [{"key": "need", "add": 1}],
		"collect": [{"key": "need", "add": 1}],
	}},
	# Der Takt der Takt-Tore wechselt: die zweite Hälfte der Tore kommt schneller.
	"taktwechsel": {"name": "Taktwechsel", "text": "der Takt wird schneller", "changes": {
		"rhythm_gates": [{"tempo": 0.7}],
	}},
	# Ein Gefolge mehr (Champions bringen eins mit, Seltene ein zweites).
	"rudelfuehrer": {"name": "Rudelführer", "text": "ein Gefolge mehr", "changes": {
		"*": [{"retinue": 1}],
	}},
}

## Gefolge: kleine Herausforderungen, die nach dem Anführer folgen. Gewählt wird eine im **Zielformat** des Anführers (Zone
## bzw. Schwelle), damit Ziel und Anzeige der Gruppe einheitlich bleiben. Ohne Eigenschaften.
const RETINUE := [
	{"id": "gefolge_zone", "block": "zone_hold", "name": "Gefolge", "zone_at": 0.45, "hold_s": 6.0, "window_s": 12.0,
		"points": 40},
	{"id": "gefolge_durchbruch", "block": "breakthrough", "name": "Gefolge", "threshold_at": 0.7, "fill_s": 3.0,
		"window_s": 9.0, "decay": 0.5, "points": 40},
	{"id": "gefolge_jagd", "block": "chase", "name": "Gefolge", "threshold_at": 0.5, "escape_s": 6.0, "catch_s": 8.0,
		"window_s": 14.0, "start_gap": 0.4, "points": 40},
]


## Würfelt mit `rng`, ob die gewürfelte Herausforderung `definition` als Elite-Gruppe kommt (Chance `chance`), und wenn ja,
## Stufe, Eigenschaften und Gefolge. Ohne Elite die Definition selbst. `chance` ≤ 0 würfelt nichts.
static func roll(rng: RandomNumberGenerator, definition: Dictionary, chance: float) -> Dictionary:
	if chance <= 0.0:
		return definition
	var hit := rng.randf() < chance
	if not hit or not eligible(definition):
		return definition
	var rank := RARE if rng.randf() < RARE_SHARE else CHAMPION
	var span: Array = RANKS[rank]["affixes"]
	var pick := affixes_for(definition.get("block", ""))
	var count := mini(rng.randi_range(span[0], span[1]), pick.size())
	var chosen := []
	for i in range(count):
		chosen.append(pick.pop_at(rng.randi_range(0, pick.size() - 1)))
	chosen.sort_custom(func(a, b): return AFFIXES.keys().find(a) < AFFIXES.keys().find(b))
	return make(definition, rank, chosen, rng)


## Kann `definition` eine Elite-Gruppe werden? Jede gewürfelte Herausforderung ja; Bosse, Phasenfolgen und Elite-Gruppen nie.
static func eligible(definition: Dictionary) -> bool:
	return not definition.has("phases") and not definition.get("boss", false) and definition.get("block") != ID \
			and not affixes_for(definition.get("block", "")).is_empty()


## Eigenschaften (Ids in der Reihenfolge von AFFIXES), die den Bausteintyp `block` verändern.
static func affixes_for(block: String) -> Array:
	var result := []
	for id in AFFIXES:
		var changes: Dictionary = AFFIXES[id]["changes"]
		if changes.has(block) or changes.has("*"):
			result.append(id)
	return result


## Die Elite-Gruppe aus der Herausforderung `base`: Stufe `rank`, Eigenschaften `affix_ids` (Ids aus AFFIXES). Das Gefolge
## wählt `rng` (ohne: der Reihe nach). Ergebnis: Definition mit `block` = ID und `phases` (Anführer, Gefolge), Punkte,
## Beute-Qualität und `elite` = {rank, affixes, base}.
static func make(base: Dictionary, rank: String, affix_ids: Array, rng: RandomNumberGenerator = null) -> Dictionary:
	var level: Dictionary = RANKS.get(rank, RANKS[CHAMPION])
	var leader := base.duplicate(true)
	var tempo := 1.0
	var retinue: int = level["retinue"]
	for id in affix_ids:
		for change in changes_of(id, base.get("block", "")):
			if change.has("retinue"):
				retinue += int(change["retinue"])
			elif change.has("tempo"):
				tempo = float(change["tempo"])
			else:
				_apply(leader, change)
	var phases := [leader]
	if tempo != 1.0 and leader.get("block") == "rhythm_gates":
		phases = _change_tempo(leader, tempo)
	var candidates := RETINUE.filter(func(entry): return entry.has("threshold_at") == base.has("threshold_at"))
	var points := roundi(float(base.get("points", 0)) * float(level["points_factor"]))
	for i in range(retinue):
		var follower: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1) if rng != null
				else i % candidates.size()].duplicate(true)
		follower["retinue"] = true
		phases.append(follower)
		points += int(follower.get("points", 0))
	return {"id": "%s_%s" % [rank, base.get("id", "")], "block": ID, "name": "%s: %s" % [level["name"], base.get("name", "")],
			"points": points, "loot_quality": float(level["loot_quality"]),
			"elite": {"rank": rank, "affixes": affix_ids.duplicate(), "base": base.get("id", "")}, "phases": phases}


## Änderungen der Eigenschaft `id` für den Bausteintyp `block` ([] = keine).
static func changes_of(id: String, block: String) -> Array:
	var changes: Dictionary = AFFIXES.get(id, {}).get("changes", {})
	return changes.get(block, changes.get("*", []))


## Elite-Stufe der Definition ("" = keine Elite-Gruppe).
static func rank_of(definition: Dictionary) -> String:
	return str(definition.get("elite", {}).get("rank", ""))


## Namen der Eigenschaften der Definition, z. B. ["Windschnell", "Zäh"].
static func affix_names(definition: Dictionary) -> Array:
	return definition.get("elite", {}).get("affixes", []).map(func(id): return AFFIXES[id]["name"])


## Farbe der Elite-Stufe (blau = Champions, gelb = Seltene).
static func color_of(rank: String) -> Color:
	return Loot.color_of(RANKS.get(rank, RANKS[CHAMPION])["rarity"])


static func _apply(definition: Dictionary, change: Dictionary) -> void:
	var key: String = change["key"]
	if change.has("set"):
		definition[key] = change["set"].duplicate(true) if change["set"] is Dictionary else change["set"]
	elif change.has("mul"):
		definition[key] = float(definition.get(key, 0.0)) * float(change["mul"])
	elif change.has("add"):
		var value = definition.get(key, 0)
		value = value + change["add"]
		if change.has("max"):
			value = minf(value, change["max"])
		definition[key] = value


## Taktwechsel: die Takt-Tore `leader` in zwei Phasen – die erste Hälfte der Tore im alten Takt, die zweite im Abstand
## × `tempo` (ihr erster Schlag nach einem neuen Abstand). Die nötigen Treffer teilen sich anteilig auf.
static func _change_tempo(leader: Dictionary, tempo: float) -> Array:
	var beats := maxi(int(leader["beats"]), 2)
	var need := clampi(int(leader["need"]), 2, beats)
	var first := leader.duplicate(true)
	first["beats"] = ceili(beats / 2.0)
	first["need"] = mini(ceili(need * float(first["beats"]) / beats), first["beats"])
	var second := leader.duplicate(true)
	second["id"] = "%s_taktwechsel" % leader.get("id", "")
	second["beats"] = beats - int(first["beats"])
	second["need"] = clampi(need - int(first["need"]), 1, second["beats"])
	second["interval_s"] = float(leader["interval_s"]) * tempo
	second["first_s"] = second["interval_s"]
	return [first, second]
