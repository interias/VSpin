## Medaillen (#33, CONTEXT.md): Bronze/Silber/Gold für eine Runden- oder Segmentzeit nach festen Schwellen – reine
## Logik ohne Szene und Bus. Keine Medaillen für Meilensteine (das sind Erfolge).
##
## Die Schwellen sind **nicht eingetragen, sondern aus dem Fahrmodell berechnet**: Bronze ist die Zeit bei konstant
## 70 rpm, Silber bei 85 rpm, Gold bei 95 rpm – je Strecke, Richtung und Segment. Dafür fährt das echte Fahrmodell
## (RideModel, Parameter aus RideConfig) mit konstanter Kadenz eine Runde ab der Start/Ziel-Linie aus dem Stand über
## das Steigungsprofil der Strecke; Runden- und Segmentzeiten misst dabei dieselbe Rundenwertung wie in der Fahrt
## (LapTiming, SegmentTiming). Ändern sich Strecke, Segmente oder Fahrmodell, ändern sich die Schwellen mit.
## Wie jede Wertung außerhalb von Arcade hängen sie nur an Kadenz und Steigung (ADR-0010).
class_name Medals
extends RefCounted

const GOLD := "gold"
const SILVER := "silver"
const BRONZE := "bronze"
## Keine Medaille.
const NONE := ""
## Medaillen, beste zuerst.
const ORDER := [GOLD, SILVER, BRONZE]
## Konstante Kadenz (rpm), deren Zeit die Schwelle einer Medaille ist.
const CADENCE_RPM := {GOLD: 95.0, SILVER: 85.0, BRONZE: 70.0}
## Anzeigenamen.
const NAMES := {GOLD: "Gold", SILVER: "Silber", BRONZE: "Bronze"}
## Schlüssel der Runde neben den Segment-IDs (Schwellen, Spielstand).
const LAP := "lap"
## Zeitschritt der Simulation (s), höchstens STEP_M Strecke je Schritt (die Steigung wird je Schritt gelesen);
## Übergänge über Linien werden anteilig aufgeteilt wie in der Fahrt.
const STEP_S := 0.1
const STEP_M := 2.0
## Spielraum (s) für Rechenunterschiede zwischen Simulation und Fahrt (anderer Zeitschritt): eine Fahrt mit genau der
## Schwellenkadenz bekommt die Medaille sicher. Weit unter dem Abstand der Schwellen (Sekunden bis Minuten).
const TOLERANCE_S := 0.15
## Bis zu so vielen Runden zählt `summary` die Medaillen einzeln auf.
const LIST_MAX := 5
## Obergrenze der simulierten Zeit (s) – schützt vor Endlosschleifen bei unsinnigen Parametern.
const MAX_SIM_S := 36000.0

## Berechnete Schwellen je Strecke und Fahrmodell (siehe `_key`).
static var _cache := {}


## Schwellen auf `track` (Kurve, `segments`) mit dem Fahrmodell aus `config`:
## {LAP: {GOLD: s, SILVER: s, BRONZE: s}, "<segment-id>": {…}}. Einmal berechnet, danach aus dem Zwischenspeicher.
static func thresholds(track: Track, config: RideConfig) -> Dictionary:
	var key := _key(track, config)
	if not _cache.has(key):
		var limits := {}
		for medal in ORDER:
			var times := simulate_lap(track, config, CADENCE_RPM[medal])
			for id in times:
				if not limits.has(id):
					limits[id] = {}
				limits[id][medal] = times[id]
		_cache[key] = limits
	return _cache[key]


## Eine Runde ab der Start/Ziel-Linie aus dem Stand mit konstanter Kadenz `cadence_rpm`: {LAP: s, "<segment-id>": s}.
static func simulate_lap(track: Track, config: RideConfig, cadence_rpm: float) -> Dictionary:
	var model := RideModel.new(config)
	var timing := LapTiming.new(track.length_m(), 0.0, 1, INF, track.segments)
	var t := 0.0
	while not timing.finished() and t < MAX_SIM_S:
		var dt := minf(STEP_S, STEP_M / maxf(model.speed_mps, 1.0))
		model.step(cadence_rpm, track.grade_at(model.distance_m), dt)
		timing.advance(model.distance_m, dt)
		t += dt
	var times := {}
	if timing.finished():
		times[LAP] = timing.lap_times[0]
	for result in timing.segments.results:
		times[result["id"]] = result["time_s"]
	return times


## Medaille für `time_s` nach den Schwellen `limits` ({GOLD: s, …}); NONE, wenn sie zu langsam ist oder keine
## Schwellen vorliegen.
static func medal_for(time_s: float, limits: Dictionary) -> String:
	for medal in ORDER:
		if limits.has(medal) and time_s <= limits[medal] + TOLERANCE_S:
			return medal
	return NONE


## Rang einer Medaille: Gold 3, Silber 2, Bronze 1, keine 0.
static func rank(medal: String) -> int:
	var index := ORDER.find(medal)
	return 0 if index < 0 else ORDER.size() - index


## Anzeigename („Silber“), "" ohne Medaille.
static func name_of(medal: String) -> String:
	return NAMES.get(medal, "")


## Medaillen mehrerer Runden fürs Ergebnis: bis LIST_MAX einzeln („Gold · Silber · –“), darüber gezählt, beste zuerst,
## ohne leere Stufen („12× Gold · 8× Silber · 3× ohne“) – damit das Ergebnis auch bei 20 Runden ins Bild passt.
static func summary(medals: Array) -> String:
	if medals.size() <= LIST_MAX:
		return " · ".join(medals.map(func(m): return name_of(m) if m != NONE else "–"))
	var parts := []
	for medal in ORDER + [NONE]:
		var count := medals.count(medal)
		if count > 0:
			parts.append("%d× %s" % [count, name_of(medal) if medal != NONE else "ohne"])
	return " · ".join(parts)


## Schlüssel des Zwischenspeichers: alles, wovon die Schwellen abhängen – Kurve (Länge und Höhenprofil über die
## Steigung in festen Abständen), Segmente und die Parameter des Fahrmodells.
static func _key(track: Track, config: RideConfig) -> String:
	var length := track.length_m()
	var profile := []
	for i in range(16):
		profile.append(snappedf(track.grade_at(length * i / 16.0), 0.0001))
	return str([length, profile, track.segments, config.k_kmh_per_rpm, config.uphill_damping, config.downhill_boost,
			config.inertia_s])
