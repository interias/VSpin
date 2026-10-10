## Arcade-Lauf (#46, Spec #27): setzt die Herausforderungen auf der Strecke zusammen – reine Logik, ohne Szene und Bus.
## Ein Lauf hat eine Stufe (ArcadeTiers), den persönlichen Kadenzbereich (CadenceRange) und läuft über beliebig viele
## Runden. Je Runde und Abschnitt (Station des Rundkurses; ohne Stationen, z. B. Graybox, ist die ganze Runde ein
## Abschnitt) würfelt er 1–2 Herausforderungen aus den Begegnungen (Encounters, Daten) – jede Runde neu. Die nächste
## Runde wird schon beim Einfahren in die laufende gewürfelt, damit ihr erstes Tor rechtzeitig zu sehen ist.
##
## Eine Herausforderung beginnt, wenn der Fahrer ihren Startpunkt (START_LEAD_M hinter dem Abschnittsbeginn, die zweite
## in der Mitte des übrigen Abschnitts) erreicht und keine andere läuft – sonst direkt nach der laufenden, solange ihr
## Abschnitt nicht verlassen ist (danach verfällt sie ungespielt). Sie läuft über ihren Baustein (`advance` je
## Fahrschritt – in Pausen ruft die Hauptszene nichts auf, also läuft dort nichts weiter und nichts scheitert).
## Geschafft gibt Punkte (Encounters.points_for), verfehlt keine – Scheitern ist weich, die Fahrt geht weiter.
## Am Ende fasst `summary_lines` den Lauf zusammen, mit den Bossen.
##
## Feste Begegnungen (#51, Bosse): Typen mit einer Konstante `FIXED` (src/challenges/boss_challenges.gd) nennen je Eintrag
## einen Abschnitt (`section`). In diesem Abschnitt plant jede Runde statt der gewürfelten Herausforderungen die festen
## ein (gleiche Lage: die erste START_LEAD_M hinter dem Beginn). Gewürfelt wird dort trotzdem, damit alle übrigen
## Abschnitte bei gleichem Seed dieselben Herausforderungen bekommen. Ohne passenden Abschnitt (Graybox) gibt es keine.
##
## Elite-Gruppen (#52, src/elite_groups.gd): Jede gewürfelte Herausforderung kommt mit der Chance `elite_chance` als
## Elite-Gruppe (Champions oder Seltene mit Gefolge, 1–3 Eigenschaften) – gewürfelt mit einem **eigenen** Würfel und vor
## dem Ersetzen durch feste Begegnungen: Zahl, Auswahl und Lage der Herausforderungen bleiben bei gleichem Seed gleich,
## nur einzelne kommen als Elite-Gruppe. Die Chance gilt im Standard-Pool (`Encounters.CHALLENGES`); wer einen eigenen
## Pool vorgibt (Tests, Prüfhilfe, erzwungene Herausforderung), bekommt keine, außer er nennt die Chance selbst. Eine
## Elite-Gruppe trägt `loot_quality` ihrer Stufe (bessere Beute, siehe `_finish`).
##
## Beute (#49): Jede beendete Herausforderung würfelt Beute (Loot) – geschafft sicher, verfehlt nur mit einer Chance nach
## dem erreichten Fortschritt (Loot.drop_chance; ohne Kadenz in der Zone nie). Funde stehen im Ergebnis (`loot`), in
## `found` und in der Zusammenfassung; ins Inventar legt sie die Arcade-Bühne am Fahrtende (ArcadeStage.save). Die
## angelegte Ausrüstung (`gear`, Loot.modifiers) wirkt nur hier: breitere Zielzone und mehr Fortschritt in der Zone
## (über Encounters.build), mehr Punkte und Beute-Glück. Ein eigener Würfel für die Beute lässt die Planung der Herausforderungen unberührt.
##
## Rundensteigerung (#54): Jede weitere Runde im selben Lauf wird etwas härter und lohnender – die Runde im Lauf
## (`lap_index`, 0 = erste) geht beim Bau des Bausteins, bei Zielzone, Punkten und Beute-Qualität mit (ArcadeTiers.level,
## die Daten stehen dort). Gewürfelt wird unverändert: Auswahl und Lage der Herausforderungen bleiben bei gleichem Seed
## gleich, nur ihre Parameter ändern sich. Die Stufe hebt die Grundqualität der Beute (`loot_quality`, ab Konstruktor).
##
## Positionen sind Fahrtpositionen wie `RideModel.distance_m` (steigend über die Runden).
class_name ArcadeRun
extends RefCounted

## Startpunkt der ersten Herausforderung hinter dem Beginn eines Abschnitts (m) – so steht ihr Tor vor dem Fahrer.
const START_LEAD_M := 50.0
## Herausforderungen je Abschnitt und Runde: zufällig zwischen MIN und MAX.
const PER_SECTION_MIN := 1
const PER_SECTION_MAX := 2

var tier := ArcadeTiers.DEFAULT
var cadence_range: CadenceRange
## Herausforderungen, aus denen gewürfelt wird (Encounters.CHALLENGES; Tests geben eigene vor).
var pool: Array
## Abschnitte einer Runde: [{name, start_m, end_m}] in Fahrtposition ab Rundenbeginn.
var sections: Array
var lap_length_m := 1.0
## Fahrtposition beim Start des Laufs.
var start_m := 0.0
## Gefahrene Zeit des Laufs (s, ohne Pausen).
var elapsed_s := 0.0
## Geplante Herausforderungen, nach Startpunkt: [{definition, at_m, end_m, section, lap}].
var planned: Array = []
## Laufende Herausforderung ({} = keine): wie in `planned` plus {block}.
var active: Dictionary = {}
## Beendete Herausforderungen: [{id, name, section, lap, succeeded, points, progress, loot, boss}] (`loot`: Teil, {} = keins;
## `boss`: ein Boss, #51).
var results: Array = []
var points := 0
## Modifikatoren der angelegten Ausrüstung (Loot.modifiers; {} = keine) – nur im Arcade-Lauf (ADR-0010).
var gear: Dictionary = {}
## Grundqualität der Beute (1 = Grundverteilung; die Stufe #54 setzt sie im Konstruktor, Hooks dürfen sie weiter heben;
## Bosse und Elite-Gruppen über ihre Definition, spätere Runden über die Rundensteigerung).
var loot_quality := 1.0
## In diesem Lauf gefundene Teile (Loot.roll, noch ohne Inventar-`id`), in Fundreihenfolge.
var found: Array = []
## Feste Begegnungen (Bosse): Definitionen mit `section`, je Runde in ihrem Abschnitt statt der gewürfelten.
var fixed: Array = []
## Chance je gewürfelter Herausforderung auf eine Elite-Gruppe (#52; 0 = keine).
var elite_chance := 0.0

var _rng := RandomNumberGenerator.new()
var _loot_rng := RandomNumberGenerator.new()
var _elite_rng := RandomNumberGenerator.new()
## Runden bis ausschließlich dieser sind gewürfelt.
var _planned_laps := 0
## Runde (des Rundkurses) beim Start des Laufs: die erste Runde im Lauf (`lap_index` 0).
var _first_lap := 0


## `seed_value` < 0 würfelt zufällig, sonst reproduzierbar. `fixed_list`: feste Begegnungen (null = die `FIXED` aller
## Typen der Registry, `fixed_from_types`; Tests geben eigene oder keine vor). `elite_chance_value`: Chance auf Elite-
## Gruppen (null = EliteGroups.CHANCE im Standard-Pool, 0 bei eigenem Pool).
func _init(tier_number: int, range_: CadenceRange, lap_sections: Array, lap_length: float, start: float = 0.0,
		seed_value: int = -1, challenges: Array = Encounters.CHALLENGES, fixed_list: Variant = null,
		elite_chance_value: Variant = null) -> void:
	tier = ArcadeTiers.valid(tier_number)
	loot_quality = float(ArcadeTiers.get_tier(tier)["loot_quality"])
	cadence_range = range_
	sections = lap_sections if not lap_sections.is_empty() else [{"name": "", "start_m": 0.0, "end_m": lap_length}]
	lap_length_m = lap_length
	start_m = start
	pool = challenges
	fixed = fixed_list if fixed_list is Array else fixed_from_types()
	if elite_chance_value is float or elite_chance_value is int:
		elite_chance = float(elite_chance_value)
	else:
		elite_chance = EliteGroups.CHANCE if challenges == Encounters.CHALLENGES else 0.0
	if seed_value >= 0:
		_rng.seed = seed_value
		_loot_rng.seed = seed_value + 1
		_elite_rng.seed = seed_value + 2
	else:
		_rng.randomize()
		_loot_rng.randomize()
		_elite_rng.randomize()
	_planned_laps = floori(start / lap_length)
	_first_lap = _planned_laps
	_plan_until(start)


## Abschnitte aus den Stationen der Strecke (Track.ride_stations, [{name, start_m}] in Fahrtposition einer Runde).
static func sections_from_stations(stations: Array, lap_length: float) -> Array:
	var result := []
	for i in range(stations.size()):
		var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else lap_length
		result.append({"name": stations[i]["name"], "start_m": float(stations[i]["start_m"]), "end_m": end})
	return result


## Feste Begegnungen aller Typen der Registry (Konstante `FIXED` eines Typs, z. B. die Bosse), in Registry-Reihenfolge.
static func fixed_from_types() -> Array:
	var result := []
	for type in EncounterRegistry.TYPES.values():
		result.append_array(type.get_script_constant_map().get("FIXED", []))
	return result


## Ein Fahrschritt: Fahrerposition `ride_m` (nach dem Schritt), Kadenz `cadence_rpm`, Dauer `delta_s`. Liefert die in
## diesem Schritt beendeten Herausforderungen (Einträge wie in `results`).
func advance(ride_m: float, cadence_rpm: float, delta_s: float) -> Array:
	elapsed_s += delta_s
	_plan_until(ride_m)
	var ended := []
	if not active.is_empty():
		var block: ChallengeBlock = active["block"]
		block.update(cadence_rpm, delta_s)
		if block.finished():
			ended.append(_finish(active))
			active = {}
	while not planned.is_empty() and planned[0]["end_m"] <= ride_m:
		planned.pop_front()  # Abschnitt verlassen, bevor sie beginnen konnte
	if active.is_empty() and not planned.is_empty() and planned[0]["at_m"] <= ride_m:
		active = planned.pop_front()
		active["block"] = Encounters.build(active["definition"], tier, cadence_range, gear, lap_index_of(active))
		if active["block"] == null:
			active = {}
	return ended


## Zielzone der geplanten oder laufenden Herausforderung `entry` (wie in `planned`) mit der Ausrüstung dieses Laufs –
## dieselbe, die ihr Baustein bekommt (Anzeige, Starttor).
func zone_of(entry: Dictionary) -> Vector2:
	return Encounters.zone_for(entry["definition"], tier, cadence_range, gear, 0.0, lap_index_of(entry))


## Runde im Lauf (0 = erste) der geplanten oder laufenden Herausforderung `entry` – Grundlage der Rundensteigerung.
func lap_index_of(entry: Dictionary) -> int:
	return maxi(int(entry["lap"]) - _first_lap, 0)


## Grundqualität der Beute der Herausforderung `entry` (vor dem Beute-Glück der Ausrüstung): die des Laufs (Stufe), × die
## ihrer Definition (Boss, Elite-Gruppe, #51/#52; sonst 1) × die Rundensteigerung ihrer Runde (#54).
func loot_quality_of(entry: Dictionary) -> float:
	var definition: float = maxf(float(entry["definition"].get("loot_quality", 1.0)), 1.0)
	return loot_quality * definition * float(ArcadeTiers.round_bonus(lap_index_of(entry))["loot_factor"])


## Runde im Lauf (0 = erste) an der Fahrtposition `ride_m`.
func lap_index_at(ride_m: float) -> int:
	return maxi(floori(ride_m / lap_length_m) - _first_lap, 0)


## Nächste geplante Herausforderung ({} = keine).
func next_challenge() -> Dictionary:
	return planned[0] if not planned.is_empty() else {}


func succeeded_count() -> int:
	return results.filter(func(r): return r["succeeded"]).size()


func failed_count() -> int:
	return results.size() - succeeded_count()


## Zusammenfassung des Laufs als Zeilen, z. B. „Punkte: 340“, „Herausforderungen: 3 geschafft · 1 verfehlt“, „Zone halten
## 3/4“ (je Herausforderung geschafft/gespielt; Bosse zählen mit, stehen aber in ihrer eigenen Zeile „Bosse: Tramuntana
## besiegt · Dimonis entkommen“, #51), mit Funden „Beute: Magischer Helm · Seltene Schuhe“ (#49).
func summary_lines() -> Array:
	var lines := ["Punkte: %d" % points,
			"Herausforderungen: %d geschafft · %d verfehlt" % [succeeded_count(), failed_count()]]
	var by_name := {}
	var bosses := []
	for result in results:
		if result.get("boss", false):
			bosses.append("%s %s" % [result["name"], "besiegt" if result["succeeded"] else "entkommen"])
			continue
		if not by_name.has(result["name"]):
			by_name[result["name"]] = [0, 0]
		by_name[result["name"]][1] += 1
		if result["succeeded"]:
			by_name[result["name"]][0] += 1
	var parts := []
	for name in by_name:
		parts.append("%s %d/%d" % [name, by_name[name][0], by_name[name][1]])
	if not parts.is_empty():
		lines.append(" · ".join(parts))
	if not bosses.is_empty():
		lines.append("Bosse: " + " · ".join(bosses))
	if not found.is_empty():
		lines.append("Beute: " + " · ".join(found.map(func(item): return Loot.item_name(item))))
	return lines


## Für den Fahrteintrag im Spielstand: Stufe, Punkte, geschafft, verfehlt.
func to_entry() -> Dictionary:
	return {"tier": tier, "points": points, "won": succeeded_count(), "failed": failed_count()}


func _finish(entry: Dictionary) -> Dictionary:
	var block: ChallengeBlock = entry["block"]
	var won := block.state == ChallengeBlock.SUCCEEDED
	var gained := 0
	if won:
		var bonus := 1.0 + float(gear.get("points_pct", 0)) / 100.0  # Ausrüstung: mehr Punkte
		gained = roundi(Encounters.points_for(entry["definition"], tier, lap_index_of(entry)) * bonus)
	points += gained
	var loot := {}
	var chance := Loot.drop_chance(won, block.loot_progress())
	if chance > 0.0 and _loot_rng.randf() <= chance:
		loot = Loot.roll(_loot_rng, Loot.quality_for(gear, loot_quality_of(entry)))
		found.append(loot)
	var result := {"id": entry["definition"]["id"], "name": entry["definition"]["name"], "section": entry["section"],
			"lap": entry["lap"], "succeeded": won, "points": gained, "progress": block.progress(), "loot": loot,
			"boss": bool(entry["definition"].get("boss", false))}
	results.append(result)
	return result


## Würfelt die Runden bis einschließlich der nächsten nach der an `ride_m`.
func _plan_until(ride_m: float) -> void:
	var lap := floori(ride_m / lap_length_m)
	while _planned_laps <= lap + 1:
		_plan_lap(_planned_laps)
		_planned_laps += 1


## Runde `lap`: je Abschnitt PER_SECTION_MIN..MAX Herausforderungen (in Abschnitten mit festen Begegnungen diese), die
## erste START_LEAD_M hinter dem Beginn, weitere gleichmäßig im Rest; jede gewürfelte vielleicht als Elite-Gruppe.
## Startpunkte vor dem Start des Laufs fallen weg.
func _plan_lap(lap: int) -> void:
	var base := lap * lap_length_m
	for section in sections:
		var count := _rng.randi_range(PER_SECTION_MIN, PER_SECTION_MAX)
		var definitions := Encounters.roll(_rng, count, pool)
		# Elite-Gruppen (#52): eigener Würfel, vor dem Ersetzen durch feste Begegnungen (Elite-Würfe überall gleich).
		definitions = definitions.map(func(definition): return EliteGroups.roll(_elite_rng, definition, elite_chance))
		var here := fixed.filter(func(definition): return definition.get("section") == section["name"])
		if not here.is_empty():
			definitions = here  # fester Ort (Boss) statt der Würfe – gewürfelt ist trotzdem (übrige Abschnitte gleich)
		var length: float = section["end_m"] - section["start_m"] - START_LEAD_M
		for i in range(definitions.size()):
			var at: float = base + section["start_m"] + START_LEAD_M + i * length / definitions.size()
			if at < start_m or length <= 0.0:
				continue
			planned.append({"definition": definitions[i], "at_m": at, "end_m": base + section["end_m"],
					"section": section["name"], "lap": lap})
