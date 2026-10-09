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
## Am Ende fasst `summary_lines` den Lauf zusammen (später auch Bosse und Beute).
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
## Beendete Herausforderungen: [{id, name, section, lap, succeeded, points, progress}].
var results: Array = []
var points := 0

var _rng := RandomNumberGenerator.new()
## Runden bis ausschließlich dieser sind gewürfelt.
var _planned_laps := 0


## `seed_value` < 0 würfelt zufällig, sonst reproduzierbar.
func _init(tier_number: int, range_: CadenceRange, lap_sections: Array, lap_length: float, start: float = 0.0,
		seed_value: int = -1, challenges: Array = Encounters.CHALLENGES) -> void:
	tier = ArcadeTiers.valid(tier_number)
	cadence_range = range_
	sections = lap_sections if not lap_sections.is_empty() else [{"name": "", "start_m": 0.0, "end_m": lap_length}]
	lap_length_m = lap_length
	start_m = start
	pool = challenges
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_planned_laps = floori(start / lap_length)
	_plan_until(start)


## Abschnitte aus den Stationen der Strecke (Track.ride_stations, [{name, start_m}] in Fahrtposition einer Runde).
static func sections_from_stations(stations: Array, lap_length: float) -> Array:
	var result := []
	for i in range(stations.size()):
		var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else lap_length
		result.append({"name": stations[i]["name"], "start_m": float(stations[i]["start_m"]), "end_m": end})
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
		active["block"] = Encounters.build(active["definition"], tier, cadence_range)
		if active["block"] == null:
			active = {}
	return ended


## Nächste geplante Herausforderung ({} = keine).
func next_challenge() -> Dictionary:
	return planned[0] if not planned.is_empty() else {}


func succeeded_count() -> int:
	return results.filter(func(r): return r["succeeded"]).size()


func failed_count() -> int:
	return results.size() - succeeded_count()


## Zusammenfassung des Laufs als Zeilen, z. B. „Punkte: 340“, „Herausforderungen: 3 geschafft · 1 verfehlt“, „Zone halten
## 3/4“ (je Herausforderung geschafft/gespielt). Spätere Pakete hängen Bosse und Beute an.
func summary_lines() -> Array:
	var lines := ["Punkte: %d" % points,
			"Herausforderungen: %d geschafft · %d verfehlt" % [succeeded_count(), failed_count()]]
	var by_name := {}
	for result in results:
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
	return lines


## Für den Fahrteintrag im Spielstand: Stufe, Punkte, geschafft, verfehlt.
func to_entry() -> Dictionary:
	return {"tier": tier, "points": points, "won": succeeded_count(), "failed": failed_count()}


func _finish(entry: Dictionary) -> Dictionary:
	var block: ChallengeBlock = entry["block"]
	var won := block.state == ChallengeBlock.SUCCEEDED
	var gained := Encounters.points_for(entry["definition"], tier) if won else 0
	points += gained
	var result := {"id": entry["definition"]["id"], "name": entry["definition"]["name"], "section": entry["section"],
			"lap": entry["lap"], "succeeded": won, "points": gained, "progress": block.progress()}
	results.append(result)
	return result


## Würfelt die Runden bis einschließlich der nächsten nach der an `ride_m`.
func _plan_until(ride_m: float) -> void:
	var lap := floori(ride_m / lap_length_m)
	while _planned_laps <= lap + 1:
		_plan_lap(_planned_laps)
		_planned_laps += 1


## Runde `lap`: je Abschnitt PER_SECTION_MIN..MAX Herausforderungen, die erste START_LEAD_M hinter dem Beginn, weitere
## gleichmäßig im Rest. Startpunkte vor dem Start des Laufs fallen weg.
func _plan_lap(lap: int) -> void:
	var base := lap * lap_length_m
	for section in sections:
		var count := _rng.randi_range(PER_SECTION_MIN, PER_SECTION_MAX)
		var definitions := Encounters.roll(_rng, count, pool)
		var length: float = section["end_m"] - section["start_m"] - START_LEAD_M
		for i in range(definitions.size()):
			var at: float = base + section["start_m"] + START_LEAD_M + i * length / definitions.size()
			if at < start_m or length <= 0.0:
				continue
			planned.append({"definition": definitions[i], "at_m": at, "end_m": base + section["end_m"],
					"section": section["name"], "lap": lap})
