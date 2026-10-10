## Balancing-Simulation des Arcade-Modus (#55, Spec #27 Story 29): fährt Tausende Arcade-Läufe ohne Grafik, ohne Szene und
## ohne Bus – mit synthetischen Kadenzverläufen („Einsteiger“, „Trainierter“, „Sprinter“) – und erzeugt daraus einen Bericht
## (Markdown): Häufigkeit je Seltenheit, Dauer je Boss, Erfolgsquote je Herausforderung und Stufe, Erreichbarkeit der Stufen.
## Reine Logik über den echten Modulen (`ArcadeRun`, `Encounters`, `EliteGroups`, `Loot`, `ArcadeTiers`, `Inventory`,
## `Talents`, `ArcadeLevel`, `RideModel`) – nichts wird nachgebaut, die Werte stammen aus den Daten des Spiels. Startbar mit
## `tools/balancing_sim.gd`; GUT treibt kleine Läufe (`tests/test_balancing.gd`).
##
## **Reproduzierbar:** Jeder Lauf bekommt aus Seed, Kadenzverlauf, Stufe, Ausrüstungsvariante und Nummer einen eigenen
## Seed (`run_seed`); gleiche Eingaben ergeben denselben Bericht, Byte für Byte (Laufzeit und Datum stehen nur, wenn der
## Aufrufer sie als `meta` mitgibt).
##
## **Fahrer (`PROFILES`, Daten):** ein Kadenzverlauf entsteht je Schritt aus
##   freier Kadenz  = Grundkadenz − Ermüdung · Zeit + langsame Schwankung (Ornstein-Uhlenbeck, Streuung/Zeitkonstante)
##                    + Spitzen (nur Sprinter: alle ~90 s für 6 s +22 rpm)
##   Absicht        = freie Kadenz, solange keine Herausforderung läuft oder naht (`LEAD_S`); sonst wechselt der Fahrer
##                    zwischen „bei der Sache“ (Absicht = Ziel) und „abgelenkt“ (freie Kadenz) – ein Zweizustandsmodell,
##                    in dem er den Anteil `follow` der Zeit bei der Sache ist (mittlere Dauer eines Abschnitts
##                    `ATTENTION_DWELL_S`, zu Beginn je Herausforderung gewürfelt); Ziel = Mitte der Zone, bei einer Schwelle
##                    (Durchbruch, Jagd, Sammeln) der Punkt `push` zwischen Schwelle und Obergrenze
##   Kadenz         = Absicht mit Verzögerung `lag_s` (Trägheit der Beine), höchstens `peak_rpm` − Ermüdung · Zeit,
##                    plus Rauschen `jitter_rpm`.
## Alles liegt im Standardbereich 60–120 rpm (CadenceRange); die Ermüdung beginnt mit jeder Fahrt neu.
##
## **Fahrtempo:** `RideModel` mit den Standardwerten von `RideConfig` auf dem echten Rundkurs (`IslandCourse`, Steigung wie
## `Track.grade_at`): Kadenz → Tempo → Strecke, damit Abschnitte, Bosse und Runden dort liegen, wo sie im Spiel liegen.
## Schrittweite: `ACTIVE_STEP_S` (0,5 s – der Bus meldet mit 0,25 bis 1 s) in und kurz vor Herausforderungen, sonst
## `IDLE_STEP_S` (nur das Tempo ändert sich).
##
## **Nicht simuliert:** Fähigkeiten (#50) und legendäre Effekte – sie brauchen die ungeglättete Kadenz (`cadence_raw`) mit
## gezielten Gesten (Antritt, Gleichmaß, Innehalten, Rhythmus), die ein synthetischer Verlauf nur erfinden könnte; die
## Zahlen hier sind die Untergrenze **ohne** Fähigkeiten (sie verstärken nur den Fortschritt mit Kadenz in der Zone). Talente
## wirken über ihre Ausrüstungswerte (Zonenbreite, Fortschritt, Punkte, Glück) in den Laufbahnen.
class_name Balancing
extends RefCounted

const IDS := ["einsteiger", "trainierter", "sprinter"]
## Kadenzverläufe (Daten). `base_rpm` Grundkadenz, `wander_rpm`/`wander_tau_s` Streuung und Zeitkonstante der Schwankung,
## `jitter_rpm` Rauschen je Schritt, `fatigue_rpm_per_h` Verlust von Kadenz und Spitzenwert je Stunde, `peak_rpm`
## höchste erreichbare Kadenz, `follow` Gewicht des Ziels in Herausforderungen (0 = ignoriert sie, 1 = trifft sie genau),
## `push` Lage des Ziels bei Schwellen (0 = Schwelle, 1 = Obergrenze), `lag_s` Verzögerung, `surge_*` Spitzen (0 = keine).
const PROFILES := {
	"einsteiger": {"name": "Einsteiger", "base_rpm": 74.0, "wander_rpm": 7.0, "wander_tau_s": 40.0, "jitter_rpm": 4.0,
		"fatigue_rpm_per_h": 10.0, "peak_rpm": 118.0, "follow": 0.7, "push": 0.35, "lag_s": 3.5,
		"surge_every_s": 0.0, "surge_s": 0.0, "surge_rpm": 0.0,
		"text": "tritt 74 rpm, schwankt stark (±7), ist zu 70 % der Zeit bei der Sache und folgt der Zielzone träge (3,5 s), "
				+ "schafft höchstens 118 rpm, ermüdet schnell (−10 rpm/h)"},
	"trainierter": {"name": "Trainierter", "base_rpm": 88.0, "wander_rpm": 4.0, "wander_tau_s": 60.0, "jitter_rpm": 2.0,
		"fatigue_rpm_per_h": 4.0, "peak_rpm": 124.0, "follow": 0.9, "push": 0.5, "lag_s": 1.5,
		"surge_every_s": 0.0, "surge_s": 0.0, "surge_rpm": 0.0,
		"text": "tritt 88 rpm gleichmäßig (±4), ist zu 90 % der Zeit bei der Sache und folgt der Zielzone in 1,5 s, schafft 124 rpm, "
				+ "ermüdet kaum (−4 rpm/h)"},
	"sprinter": {"name": "Sprinter", "base_rpm": 92.0, "wander_rpm": 6.0, "wander_tau_s": 30.0, "jitter_rpm": 3.0,
		"fatigue_rpm_per_h": 8.0, "peak_rpm": 140.0, "follow": 0.75, "push": 0.75, "lag_s": 0.9,
		"surge_every_s": 90.0, "surge_s": 6.0, "surge_rpm": 22.0,
		"text": "tritt 92 rpm unruhig (±6), ist zu 75 % der Zeit bei der Sache und folgt der Zielzone flink (0,9 s), setzt bei Schwellen hoch an "
				+ "(Punkt 0,75), schafft 140 rpm, Spitzen von +22 rpm für 6 s alle ~90 s, ermüdet mäßig (−8 rpm/h)"},
}
## Ausrüstungsvarianten der Läufe auf fester Stufe: ohne Ausrüstung (Fitness allein) und mit der Empfohlenen Stärke der Stufe.
const GEAR_NONE := "ohne"
const GEAR_RECOMMENDED := "empfohlen"
const GEAR_VARIANTS := [GEAR_NONE, GEAR_RECOMMENDED]

## Länge einer simulierten Fahrt (s): 45 Minuten, die übliche Fahrt (Rundkurs ~3 Runden).
const RIDE_S := 2700.0
## Schrittweite (s) in/vor Herausforderungen und sonst.
const ACTIVE_STEP_S := 0.5
const IDLE_STEP_S := 2.0
## So viele Sekunden vor dem Start sieht der Fahrer das Tor und stellt sich auf die Zone ein.
const LEAD_S := 8.0
## Mittlere Dauer (s) von „bei der Sache“ und „abgelenkt“ zusammen (Wechselrate je Zustand = Anteil / Dauer).
const ATTENTION_DWELL_S := 10.0
## Nach Fahrtende läuft eine begonnene Herausforderung höchstens so lange weiter (s).
const FINISH_GRACE_S := 150.0
## Laufbahnen: höchstens so viele Läufe (danach gilt eine Stufe als nicht erreicht).
const CAREER_MAX_RUNS := 120
## Talente in dieser Reihenfolge (nur solche mit Wirkung auf Ausrüstungswerte, siehe Kopf), danach der Rest.
const TALENT_ORDER := ["ausdauer_gleichmass", "ausdauer_breit", "kletterer_zaeh", "sprinter_antritt", "sprinter_reflex",
		"sprinter_druck", "ausdauer_glueck", "kletterer_ruhe", "kletterer_gipfel"]
## Gewichte, mit denen die Laufbahn Teile eines Platzes vergleicht (Zonenbreite und Fortschritt zählen für die Stärke).
const ITEM_WEIGHTS := {"zone_width_rpm": 4.0, "progress_pct": 1.0, "points_pct": 0.1, "luck_pct": 0.1}

static var _grades := PackedFloat32Array()
static var _course := {}


# --- Ein Lauf --------------------------------------------------------------------------------------------------------


## Eigener Seed eines Laufs (stabil, nichtnegativ) aus den Eingaben.
static func run_seed(seed_value: int, profile: String, tier: int, variant: String, index: int) -> int:
	var h := seed_value & 0x7FFFFFFF
	for part in [IDS.find(profile) + 1, tier, GEAR_VARIANTS.find(variant) + 1, index + 1]:
		h = (h * 1000003 + int(part) * 7919 + 12345) & 0x7FFFFFFF
	return h


## Ausrüstungswerte, die genau die Empfohlene Stärke von Stufe `tier` ergeben (Hälfte über Zonenbreite, Rest Fortschritt).
static func recommended_gear(tier: int) -> Dictionary:
	var strength := ArcadeTiers.recommended_strength(tier)
	var width := mini(strength / 8, int(Loot.STATS["zone_width_rpm"]["cap"]))
	var progress := mini(strength - width * int(ArcadeTiers.STRENGTH_WEIGHTS["zone_width_rpm"]), int(Loot.STATS["progress_pct"]["cap"]))
	return {"zone_width_rpm": width, "progress_pct": progress, "points_pct": 0, "luck_pct": 0}


## Rundkurs ohne Szene: Länge (m), Abschnitte und Steigung je 5 m (gleich `Track.grade_at`).
static func course() -> Dictionary:
	if _course.is_empty():
		var track := Track.new()
		IslandCourse.apply_to(track)
		var length := track.length_m()
		_grades = PackedFloat32Array()
		for i in range(ceili(length / 5.0) + 1):
			_grades.append(track.grade_at(i * 5.0))
		_course = {"length": length, "sections": ArcadeRun.sections_from_stations(track.ride_stations(), length)}
		track.free()
	return _course


static func grade_at(distance_m: float) -> float:
	var length: float = course()["length"]
	return _grades[mini(int(fposmod(distance_m, length) / 5.0), _grades.size() - 1)]


## Ein neuer Lauf der Stufe `tier` auf dem Rundkurs (Standardbereich 60–120 rpm, Bosse an ihren Orten).
static func new_run(tier: int, seed_value: int, gear: Dictionary = {}) -> ArcadeRun:
	var info := course()
	var run := ArcadeRun.new(tier, CadenceRange.new(), info["sections"], info["length"], 0.0, seed_value)
	run.gear = gear.duplicate()
	return run


## Fährt `run` mit dem Kadenzverlauf `profile` (`PROFILES`-Id), gewürfelt mit `rider_seed`, über `ride_s` Sekunden (eine
## begonnene Herausforderung wird zu Ende gefahren). Liefert {elapsed_s, laps, records}: je beendeter Herausforderung
## {id, kind (normal | elite | boss), key, name, tier, lap, succeeded, duration_s, rarity ("" = keine Beute), rank,
## phases (nur Boss: [{name, reached, cleared}])}.
static func ride(run: ArcadeRun, profile: String, rider_seed: int, ride_s: float = RIDE_S) -> Dictionary:
	var rider := Rider.new(PROFILES[profile], rider_seed)
	var model := RideModel.new(RideConfig.new())
	var records := []
	var t := 0.0
	var tracked_key := ""
	var tracked_block: ChallengeBlock = null
	var started_s := 0.0
	while t < ride_s or (not run.active.is_empty() and t < ride_s + FINISH_GRACE_S):
		var active := not run.active.is_empty()
		var near: bool = not run.planned.is_empty() and run.planned[0]["at_m"] - model.distance_m < model.speed_mps * LEAD_S + 20.0
		var dt := ACTIVE_STEP_S if active or near else IDLE_STEP_S
		var target := NAN
		if active:  # die Zone des laufenden Bausteins (bei Boss und Elite die der laufenden Phase)
			var leaf: ChallengeBlock = run.active["block"]
			while leaf is BossFight and (leaf as BossFight).current_phase() != null:
				leaf = (leaf as BossFight).current_phase()
			target = rider.target_for(leaf.zone(), leaf is Breakthrough or leaf is Chase or leaf is Collect)
		elif near:  # das Starttor steht schon vor dem Fahrer: er stellt sich auf die Zone ein
			var next: Dictionary = run.planned[0]
			var first: Dictionary = next["definition"]
			while first.get("phases") is Array and not first["phases"].is_empty():
				first = first["phases"][0]
			target = rider.target_for(run.zone_of(next), first.has("threshold_at"))
		var cadence := rider.step(dt, target)
		model.step(cadence, grade_at(model.distance_m), dt)
		t += dt
		var ended := run.advance(model.distance_m, cadence, dt)
		for result in ended:
			records.append(_record(run, result, tracked_block, t - started_s))
		if not run.active.is_empty():
			var key := "%d@%d" % [int(run.active["lap"]), roundi(run.active["at_m"])]
			if key != tracked_key:
				tracked_key = key
				tracked_block = run.active["block"]
				started_s = t
		else:
			tracked_key = ""
	return {"elapsed_s": t, "laps": model.distance_m / float(course()["length"]), "records": records}


static func _record(run: ArcadeRun, result: Dictionary, block: ChallengeBlock, duration_s: float) -> Dictionary:
	var id: String = result["id"]
	var kind := "normal"
	var key := id
	for rank in EliteGroups.RANKS:
		if id.begins_with(rank + "_"):
			kind = "elite"
			key = rank
	if result["boss"]:
		kind = "boss"
	var record := {"id": id, "kind": kind, "key": key, "name": result["name"], "tier": run.tier, "lap": result["lap"],
			"succeeded": result["succeeded"], "duration_s": duration_s, "rarity": str(result["loot"].get("rarity", "")),
			"phases": []}
	if kind == "boss" and block is BossFight:
		var fight := block as BossFight
		for i in range(fight.phases.size()):
			record["phases"].append({"name": fight.definitions[i]["name"], "reached": fight.index >= i,
					"cleared": fight.index > i or result["succeeded"]})
	return record


## Der Kadenzverlauf eines Fahrers (siehe Kopf der Datei).
class Rider extends RefCounted:
	var p: Dictionary
	var rng := RandomNumberGenerator.new()
	var cadence: float
	var wander := 0.0
	var surge_left := 0.0
	var t := 0.0
	var targeting := false
	var attentive := false

	func _init(profile: Dictionary, seed_value: int) -> void:
		p = profile
		rng.seed = seed_value ^ 0x5BD1E995
		cadence = float(p["base_rpm"])

	## Ziel (rpm) für die Zone `zone`: ihre Mitte, bei einer Schwelle (Durchbruch, Jagd, Sammeln) der Punkt `push` von der
	## Schwelle zur Obergrenze. NAN ohne Zone.
	func target_for(zone: Vector2, threshold: bool) -> float:
		if is_nan(zone.x):
			return NAN
		return lerpf(zone.x, zone.y, float(p["push"]) if threshold else 0.5)

	## Ein Schritt von `dt` Sekunden; `target` NAN = keine Herausforderung. Liefert die Kadenz.
	func step(dt: float, target: float) -> float:
		t += dt
		var decay := exp(-dt / float(p["wander_tau_s"]))
		wander = wander * decay + float(p["wander_rpm"]) * sqrt(1.0 - decay * decay) * rng.randfn()
		var free: float = float(p["base_rpm"]) - float(p["fatigue_rpm_per_h"]) * t / 3600.0 + wander
		if surge_left > 0.0:
			surge_left -= dt
			free += float(p["surge_rpm"])
		elif float(p["surge_every_s"]) > 0.0 and rng.randf() < dt / float(p["surge_every_s"]):
			surge_left = float(p["surge_s"])
		var follow: float = p["follow"]
		if is_nan(target):
			targeting = false
		elif not targeting:
			targeting = true
			attentive = rng.randf() < follow
		else:
			var rate := ((1.0 - follow) if attentive else follow) / ATTENTION_DWELL_S
			if rng.randf() < rate * dt:
				attentive = not attentive
		var want := target if targeting and attentive else free
		cadence += (want - cadence) * (1.0 - exp(-dt / float(p["lag_s"])))
		var ceiling: float = maxf(float(p["peak_rpm"]) - float(p["fatigue_rpm_per_h"]) * t / 3600.0, 0.0)
		cadence = clampf(cadence, 0.0, ceiling)
		return clampf(cadence + float(p["jitter_rpm"]) * rng.randfn(), 0.0, ceiling)


# --- Sammeln der Kennzahlen ------------------------------------------------------------------------------------------


## Leere Kennzahlen einer Zelle (Kadenzverlauf × Ausrüstungsvariante × Stufe).
static func new_cell() -> Dictionary:
	return {"runs": 0, "seconds": 0.0, "laps": 0.0, "challenges": {}, "rarity": {}, "drops": 0, "boss": {}}


## Nimmt die Ergebnisse einer Fahrt in `cell` auf.
static func add_to_cell(cell: Dictionary, fahrt: Dictionary) -> void:
	cell["runs"] += 1
	cell["seconds"] += fahrt["elapsed_s"]
	cell["laps"] += fahrt["laps"]
	for record in fahrt["records"]:
		var key := _row_key(record)
		var row: Dictionary = cell["challenges"].get(key, {"won": 0, "total": 0})
		row["total"] += 1
		row["won"] += 1 if record["succeeded"] else 0
		cell["challenges"][key] = row
		if record["rarity"] != "":
			cell["drops"] += 1
			cell["rarity"][record["rarity"]] = int(cell["rarity"].get(record["rarity"], 0)) + 1
		if record["kind"] == "boss":
			var boss: Dictionary = cell["boss"].get(record["key"], {"won": [], "lost": [], "phases": []})
			boss["won" if record["succeeded"] else "lost"].append(snappedf(record["duration_s"], 0.5))
			for i in range(record["phases"].size()):
				if boss["phases"].size() <= i:
					boss["phases"].append({"name": record["phases"][i]["name"], "reached": 0, "cleared": 0})
				boss["phases"][i]["reached"] += 1 if record["phases"][i]["reached"] else 0
				boss["phases"][i]["cleared"] += 1 if record["phases"][i]["cleared"] else 0
			cell["boss"][record["key"]] = boss


static func _row_key(record: Dictionary) -> String:
	return "%s:%s" % [record["kind"], record["key"]]


## Eine Zelle: `runs` Fahrten von `profile` auf Stufe `tier` mit Ausrüstungsvariante `variant`.
static func run_cell(profile: String, tier: int, variant: String, runs: int, seed_value: int, ride_s: float = RIDE_S) -> Dictionary:
	var cell := new_cell()
	var gear := recommended_gear(tier) if variant == GEAR_RECOMMENDED else {}
	for i in range(runs):
		var s := run_seed(seed_value, profile, tier, variant, i)
		add_to_cell(cell, ride(new_run(tier, s, gear), profile, s, ride_s))
	return cell


# --- Laufbahnen (Erreichbarkeit der Stufen) --------------------------------------------------------------------------


## Eine Laufbahn: ein Fahrer ab neuem Spielstand (nur im Speicher) fährt immer auf der höchsten freien Stufe, legt bessere
## Teile an, verwertet den Rest, lernt Talente und sammelt Arcade-Level, bis Stufe 6 abgeschlossen ist oder `max_runs`
## erreicht sind. Liefert {runs, unlocked: {"4": Läufe bis zur Freischaltung, …} (nur erreichte), completed_6: Läufe oder 0,
## strength_reached: {"4": Läufe, bis die Stärke die Empfehlung der Stufe erreicht, …}, final_strength, final_level}.
static func career(profile: String, seed_value: int, index: int, max_runs: int = CAREER_MAX_RUNS, ride_s: float = RIDE_S) -> Dictionary:
	var save := SaveGame.new()
	var result := {"runs": 0, "unlocked": {}, "completed_6": 0, "final_strength": 0, "final_level": 1, "strength_reached": {}}
	for n in range(max_runs):
		var tier := ArcadeTiers.unlocked(save)
		ArcadeTiers.choose(save, tier)
		var s := run_seed(seed_value, profile, tier, GEAR_NONE, index * 1000 + n)
		var run := new_run(tier, s)
		run.gear = Inventory.modifiers(save)
		BuildEffects.apply(BuildEffects.changes_for(save), run, null, null)
		ride(run, profile, s, ride_s)
		result["runs"] = n + 1
		_collect_loot(save, run)
		ArcadeLevel.add_points(save, run.points)
		_learn_talents(save)
		var strength := ArcadeTiers.strength(save)
		for entry in ArcadeTiers.LIST.slice(3):  # Läufe, bis die Stärke die Empfehlung der Stufen 4–6 erreicht
			if strength >= entry["strength"] and not result["strength_reached"].has(str(entry["tier"])):
				result["strength_reached"][str(entry["tier"])] = n + 1
		var fresh := ArcadeTiers.record_run(save, run)
		if fresh > 0:
			result["unlocked"][str(fresh)] = n + 1
		if tier == ArcadeTiers.LIST.size() and ArcadeTiers.completed(save, tier):
			result["completed_6"] = n + 1
			break
	result["final_strength"] = ArcadeTiers.strength(save)
	result["final_level"] = ArcadeLevel.level(save)
	return result


## Funde ins Inventar; je Platz das Teil mit dem höheren Wert anlegen, das übrige verwerten.
static func _collect_loot(save: SaveGame, run: ArcadeRun) -> void:
	for item in run.found:
		var stored := Inventory.add(save, item)
		var worn: Dictionary = Inventory.equipped(save).get(stored["slot"], {})
		if worn.is_empty() or _value(stored) > _value(worn):
			Inventory.equip(save, stored["id"])
	for item in Inventory.items(save):
		Inventory.salvage(save, item["id"])  # angelegte Teile verwertet das Inventar nie


static func _value(item: Dictionary) -> float:
	var total := 0.0
	for stat in item["stats"]:
		total += float(item["stats"][stat]) * float(ITEM_WEIGHTS.get(stat, 0.0))
	return total


## Freie Talentpunkte ausgeben: erst `TALENT_ORDER`, dann die übrigen Knoten.
static func _learn_talents(save: SaveGame) -> void:
	for id in TALENT_ORDER + Talents.NODES.keys():
		if Talents.available(save) <= 0:
			return
		if Talents.can_learn(save, id):
			Talents.learn(save, id)


# --- Gesamtlauf ------------------------------------------------------------------------------------------------------


## Alles fahren: {profile: {variant: {tier: Zelle}}} plus {profile: [Laufbahn, …]}. `options`: runs (Läufe je Zelle der
## Variante „ohne“), gear_runs (je Zelle der Variante „empfohlen“), careers, career_max_runs, seed, ride_s. `progress`
## (Callable, optional) bekommt eine Textzeile je fertigem Block.
static func simulate(options: Dictionary, progress: Callable = Callable()) -> Dictionary:
	var seed_value: int = options.get("seed", 1)
	var ride_s: float = options.get("ride_s", RIDE_S)
	var data := {"cells": {}, "careers": {}}
	for profile in IDS:
		data["cells"][profile] = {GEAR_NONE: {}, GEAR_RECOMMENDED: {}}
		for tier in ArcadeTiers.LIST.map(func(t): return t["tier"]):
			data["cells"][profile][GEAR_NONE][tier] = run_cell(profile, tier, GEAR_NONE, options.get("runs", 20), seed_value, ride_s)
			data["cells"][profile][GEAR_RECOMMENDED][tier] = run_cell(profile, tier, GEAR_RECOMMENDED,
					options.get("gear_runs", 10), seed_value, ride_s)
			if progress.is_valid():
				progress.call("%s Stufe %d fertig" % [profile, tier])
		data["careers"][profile] = []
		for i in range(options.get("careers", 5)):
			data["careers"][profile].append(career(profile, seed_value, i, options.get("career_max_runs", CAREER_MAX_RUNS), ride_s))
		if progress.is_valid():
			progress.call("%s Laufbahnen fertig" % profile)
	return data


# --- Bericht ---------------------------------------------------------------------------------------------------------


## Median und Quantil `q` (0..1) einer Liste (Nächster-Rang-Verfahren; leer = NAN).
static func quantile(values: Array, q: float) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(ceili(q * sorted.size()) - 1, 0, sorted.size() - 1)])


static func _pct(part: int, whole: int) -> String:
	return "–" if whole == 0 else "%d %%" % roundi(100.0 * part / whole)


static func _num(value: float, digits: int = 0) -> String:
	return "–" if is_nan(value) else String.num(value, digits).replace(".", ",")  # Dezimalkomma wie im übrigen Bericht


static func _table(headers: Array, rows: Array) -> String:
	var lines := ["| " + " | ".join(headers) + " |", "|" + "|".join(headers.map(func(_h): return "---")) + "|"]
	for row in rows:
		lines.append("| " + " | ".join(row) + " |")
	return "\n".join(lines) + "\n"


## Name der Herausforderungszeile für den Schlüssel `kind:key` (aus den Daten).
static func _row_label(row_key: String) -> String:
	var kind := row_key.get_slice(":", 0)
	var key := row_key.get_slice(":", 1)
	match kind:
		"elite":
			return "Elite: " + str(EliteGroups.RANKS[key]["name"])
		"boss":
			return "Boss: " + str(_boss_name(key))
	return "%s (%s)" % [key, str(Encounters.find(key).get("name", key))]


static func _boss_name(id: String) -> String:
	for definition in ArcadeRun.fixed_from_types():
		if definition["id"] == id:
			return definition["name"]
	return id


## Reihenfolge der Zeilen: Herausforderungen des Pools, Elite, Bosse.
static func _row_order() -> Array:
	var rows := []
	for definition in Encounters.CHALLENGES:
		if definition.get("block") != EliteGroups.ID:
			rows.append("normal:" + str(definition["id"]))
	for rank in EliteGroups.RANKS:
		rows.append("elite:" + rank)
	for boss in ArcadeTiers.bosses():
		rows.append("boss:" + boss)
	return rows


## Der Bericht als Markdown. `data` aus `simulate`, `options` wie dort, `meta`: command, commit, date, note (alles optional,
## nur was gesetzt ist, steht im Kopf; `appendix`: Markdown-Text, der am Ende angehängt wird – Auffälligkeiten, Nachjustierung,
## offene Fragen).
static func report(data: Dictionary, options: Dictionary, meta: Dictionary = {}) -> String:
	var tiers: Array = ArcadeTiers.LIST.map(func(t): return t["tier"])
	var out := ["# Arcade-Balancing – Bericht der Simulation\n"]
	var head := ["- Seed: %d" % options.get("seed", 1),
			"- Läufe je Kadenzverlauf und Stufe: %d ohne Ausrüstung, %d mit Empfohlener Stärke; Laufbahnen je Kadenzverlauf: %d (höchstens %d Läufe)"
			% [options.get("runs", 20), options.get("gear_runs", 10), options.get("careers", 5), options.get("career_max_runs", CAREER_MAX_RUNS)],
			"- Fahrt: %d min auf dem Insel-Rundkurs (%.0f m), Standardbereich 60–120 rpm" % [roundi(options.get("ride_s", RIDE_S) / 60.0), course()["length"]]]
	for key in ["command", "commit", "date", "note"]:
		if meta.has(key):
			head.append("- %s: %s" % [{"command": "Befehl", "commit": "Stand (Commit)", "date": "Datum", "note": "Hinweis"}[key], meta[key]])
	out.append("\n".join(head) + "\n")
	out.append("Erzeugt von `src/balancing.gd`; Lesart und Grenzen der Simulation stehen im Kopf der Datei. Alle Zahlen sind "
			+ "**ohne Fähigkeiten** gerechnet (Untergrenze), Ausrüstung nur dort, wo sie genannt ist.\n")
	out.append("## Kadenzverläufe\n")
	out.append(_table(["Verlauf", "Beschreibung"], IDS.map(func(id): return [PROFILES[id]["name"], PROFILES[id]["text"]])))
	for profile in IDS:
		out.append("## %s\n" % PROFILES[profile]["name"])
		out.append(_section_rarity(data["cells"][profile][GEAR_NONE], tiers))
		out.append(_section_success(data["cells"][profile][GEAR_NONE], tiers))
		out.append(_section_phases(data["cells"][profile][GEAR_NONE], tiers))
		out.append(_section_boss_times(data["cells"][profile][GEAR_NONE], tiers))
		out.append(_section_gear(data["cells"][profile], tiers))
	out.append(_section_zones(tiers))
	out.append(_section_reach(data["careers"], options))
	if meta.has("appendix"):
		out.append("\n" + str(meta["appendix"]).strip_edges() + "\n")
	return "\n".join(out)


static func _section_rarity(cells: Dictionary, tiers: Array) -> String:
	var rows := []
	for tier in tiers:
		var cell: Dictionary = cells[tier]
		var row := ["Stufe %d" % tier, str(cell["runs"]), _num(cell["drops"] / maxf(cell["seconds"] / 3600.0, 1e-9), 1)]
		for rarity in Loot.RARITIES:
			var count := int(cell["rarity"].get(rarity, 0))
			row.append("%d (%s)" % [count, _pct(count, cell["drops"])])
		rows.append(row)
	return "### Häufigkeit je Seltenheit (ohne Ausrüstung)\n\nFunde je Stufe: absolut (Anteil an allen Funden).\n\n" \
			+ _table(["Stufe", "Fahrten", "Funde/h"] + Loot.RARITIES.keys().map(func(r): return Loot.RARITIES[r]["name"]), rows)


static func _section_success(cells: Dictionary, tiers: Array) -> String:
	var rows := []
	for row_key in _row_order():
		var row := [_row_label(row_key)]
		for tier in tiers:
			var entry: Dictionary = cells[tier]["challenges"].get(row_key, {"won": 0, "total": 0})
			row.append("%s (%d)" % [_pct(entry["won"], entry["total"]), entry["total"]])
		rows.append(row)
	var elite_row := ["Elite-Anteil an den Herausforderungen ohne Boss"]
	for tier in tiers:
		var elite := 0
		var plain := 0
		for key in cells[tier]["challenges"]:
			if key.begins_with("elite:"):
				elite += cells[tier]["challenges"][key]["total"]
			elif key.begins_with("normal:"):
				plain += cells[tier]["challenges"][key]["total"]
		elite_row.append(_pct(elite, elite + plain))
	var all_row := ["**alle zusammen**"]
	for tier in tiers:
		var won := 0
		var total := 0
		for entry in cells[tier]["challenges"].values():
			won += entry["won"]
			total += entry["total"]
		all_row.append("%s (%d)" % [_pct(won, total), total])
	rows.append(all_row)
	rows.append(elite_row)
	return "### Erfolgsquote je Herausforderung und Stufe (ohne Ausrüstung)\n\nErfolgsquote (Zahl der beendeten Herausforderungen).\n\n" \
			+ _table(["Herausforderung"] + tiers.map(func(t): return "Stufe %d" % t), rows)


static func _section_phases(cells: Dictionary, tiers: Array) -> String:
	var rows := []
	for boss in ArcadeTiers.bosses():
		var phases: Array = []
		for definition in ArcadeRun.fixed_from_types():
			if definition["id"] == boss:
				phases = definition["phases"]
		for i in range(phases.size()):
			var row := ["%s · Phase %d %s" % [_boss_name(boss), i + 1, phases[i]["name"]]]
			for tier in tiers:
				var seen: Array = cells[tier]["boss"].get(boss, {}).get("phases", [])
				row.append(_pct(seen[i]["cleared"], seen[i]["reached"]) if i < seen.size() else "–")
			rows.append(row)
	return "### Erfolgsquote der Boss-Phasen (ohne Ausrüstung)\n\nAnteil der erreichten Phasen, die geschafft wurden.\n\n" \
			+ _table(["Phase"] + tiers.map(func(t): return "Stufe %d" % t), rows)


static func _section_boss_times(cells: Dictionary, tiers: Array) -> String:
	var rows := []
	for boss in ArcadeTiers.bosses():
		for tier in tiers:
			var entry: Dictionary = cells[tier]["boss"].get(boss, {"won": [], "lost": []})
			var won: Array = entry["won"]
			var lost: Array = entry["lost"]
			rows.append([_boss_name(boss), "Stufe %d" % tier, str(won.size() + lost.size()), _pct(won.size(), won.size() + lost.size()),
					_num(quantile(won, 0.5)), _num(quantile(won, 0.9)), _num(quantile(lost, 0.5))])
	return "### Dauer je Boss (ohne Ausrüstung)\n\nSekunden vom Beginn des Kampfes bis zum Sieg bzw. Entkommen; Quantile nach dem Nächster-Rang-Verfahren.\n\n" \
			+ _table(["Boss", "Stufe", "Kämpfe", "Sieg", "Sieg: Median s", "Sieg: 90 % s", "Entkommen: Median s"], rows)


static func _section_gear(by_variant: Dictionary, tiers: Array) -> String:
	var rows := []
	for tier in tiers:
		var plain: Dictionary = by_variant[GEAR_NONE][tier]
		var geared: Dictionary = by_variant[GEAR_RECOMMENDED][tier]
		var gear := recommended_gear(tier)
		rows.append(["Stufe %d" % tier, "%d (Zone +%d rpm, Fortschritt +%d %%)" % [ArcadeTiers.recommended_strength(tier), gear["zone_width_rpm"], gear["progress_pct"]],
				_overall(plain, "normal"), _overall(geared, "normal"), _overall(plain, "elite"), _overall(geared, "elite"),
				_overall(plain, "boss"), _overall(geared, "boss")])
	return "### Mit Empfohlener Stärke (%d Fahrten je Stufe)\n\nErfolgsquote ohne → mit Ausrüstung der Empfohlenen Stärke.\n\n" % by_variant[GEAR_RECOMMENDED][tiers[0]]["runs"] \
			+ _table(["Stufe", "Empfohlene Stärke", "Normal ohne", "Normal mit", "Elite ohne", "Elite mit", "Boss ohne", "Boss mit"], rows)


static func _overall(cell: Dictionary, kind: String) -> String:
	var won := 0
	var total := 0
	for key in cell["challenges"]:
		if key.begins_with(kind + ":"):
			won += cell["challenges"][key]["won"]
			total += cell["challenges"][key]["total"]
	return _pct(won, total)


## Zielzonen und Schwellen je Stufe (Daten, erste Runde, ohne Ausrüstung, Standardbereich): „80–100“ bzw. „ab 108“; eine
## Schwelle auf der Obergrenze des Bereichs steht mit „(Obergrenze)“ – dort ist nur noch das Maximum selbst genug.
static func _section_zones(tiers: Array) -> String:
	var range_ := CadenceRange.new()
	var rows := []
	var definitions := []
	for definition in Encounters.CHALLENGES:
		if definition.get("block") != EliteGroups.ID:
			definitions.append([str(definition["id"]), definition])
	for boss in ArcadeRun.fixed_from_types():
		for phase in boss["phases"]:
			definitions.append(["%s · %s" % [boss["name"], phase["name"]], phase])
	for entry in definitions:
		var row := [entry[0]]
		for tier in tiers:
			var zone := Encounters.zone_for(entry[1], tier, range_)
			var text := Encounters.target_text(entry[1], zone).replace(" rpm", "")
			row.append(text + (" (Obergrenze)" if entry[1].has("threshold_at") and zone.x >= range_.maximum else ""))
		rows.append(row)
	return "## Zielzonen und Schwellen je Stufe\n\nStandardbereich %d–%d rpm, erste Runde, ohne Ausrüstung (rpm).\n\n" \
			% [range_.minimum, range_.maximum] + _table(["Herausforderung"] + tiers.map(func(t): return "Stufe %d" % t), rows)


static func _section_reach(careers: Dictionary, options: Dictionary) -> String:
	var hours: float = options.get("ride_s", RIDE_S) / 3600.0
	var rows := []
	var strength_rows := []
	for profile in IDS:
		for tier in [4, 5, 6]:
			var runs := []
			for entry in careers[profile]:
				if entry["unlocked"].has(str(tier)):
					runs.append(entry["unlocked"][str(tier)])
			rows.append([PROFILES[profile]["name"], "Stufe %d" % tier, "%d von %d (%s)" % [runs.size(), careers[profile].size(), _pct(runs.size(), careers[profile].size())],
					_num(quantile(runs, 0.5)), _num(quantile(runs, 0.5) * hours, 1), _num(quantile(runs, 0.9)), _num(quantile(runs, 0.9) * hours, 1)])
		var done: Array = careers[profile].filter(func(e): return e["completed_6"] > 0).map(func(e): return e["completed_6"])
		rows.append([PROFILES[profile]["name"], "Stufe 6 abgeschlossen", "%d von %d (%s)" % [done.size(), careers[profile].size(), _pct(done.size(), careers[profile].size())],
				_num(quantile(done, 0.5)), _num(quantile(done, 0.5) * hours, 1), _num(quantile(done, 0.9)), _num(quantile(done, 0.9) * hours, 1)])
	for profile in IDS:
		for entry in ArcadeTiers.LIST.slice(3):
			var runs := []
			for career_entry in careers[profile]:
				if career_entry["strength_reached"].has(str(entry["tier"])):
					runs.append(career_entry["strength_reached"][str(entry["tier"])])
			strength_rows.append([PROFILES[profile]["name"], "Stärke %d (Empfehlung Stufe %d)" % [entry["strength"], entry["tier"]],
					"%d von %d (%s)" % [runs.size(), careers[profile].size(), _pct(runs.size(), careers[profile].size())],
					_num(quantile(runs, 0.5)), _num(quantile(runs, 0.5) * hours, 1), _num(quantile(runs, 0.9)), _num(quantile(runs, 0.9) * hours, 1)])
	var ends := []
	for profile in IDS:
		var strengths: Array = careers[profile].map(func(e): return e["final_strength"])
		var levels: Array = careers[profile].map(func(e): return e["final_level"])
		ends.append([PROFILES[profile]["name"], _num(quantile(strengths, 0.5)), _num(quantile(levels, 0.5))])
	return "## Erreichbarkeit der Stufen\n\nLaufbahn: neuer Spielstand (nur im Speicher), gefahren wird immer auf der höchsten freien Stufe; "  \
			+ "bessere Teile werden angelegt, der Rest verwertet, Talente und Arcade-Level wachsen mit den Punkten. Eine Stufe gilt als "  \
			+ "erreicht, wenn sie innerhalb der Läufe freigeschaltet wird (Stufen 1–3 sind von Beginn an frei). Ein Lauf = eine Fahrt von "  \
			+ "%s Stunden.\n\n" % _num(hours, 2) \
			+ _table(["Verlauf", "Ziel", "Verläufe, die es schaffen", "Läufe (Median)", "Stunden (Median)", "Läufe (90 %)", "Stunden (90 %)"], rows) \
			+ "\nWann die Ausrüstung (mit Talenten) die Empfohlene Stärke der Stufen 4–6 erreicht:\n\n" \
			+ _table(["Verlauf", "Ziel", "Verläufe, die es schaffen", "Läufe (Median)", "Stunden (Median)", "Läufe (90 %)", "Stunden (90 %)"], strength_rows) \
			+ "\nStärke und Arcade-Level am Ende der Laufbahn (Median):\n\n" + _table(["Verlauf", "Stärke", "Level"], ends)
