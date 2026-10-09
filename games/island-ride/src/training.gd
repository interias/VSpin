## Training (#37): eine angeleitete Einheit als reine Logik, ohne Szene und Bus. Die Einheiten sind Dateien
## (`res://trainings/*.json`, eigene Einheiten entstehen nur als Datei):
##
##   {"name": "Intervalle kurz", "description": "10 × 30 s hart / 30 s locker",
##    "phases": [{"name": "Aufwärmen", "kind": "warmup", "duration_s": 480, "cadence_rpm": [80, 90],
##                "announcement": "Widerstand leicht, bei 85 rpm einrollen"},
##               {"repeat": 10, "phases": [{"name": "Hart", …}, {"name": "Locker", …}]},
##               {"name": "Ausrollen", "kind": "cooldown", …}]}
##
## Eine Phase hat Dauer, Zielkadenz-Bereich (rpm, Grenzen eingeschlossen) und eine Ansage zum Widerstandsknopf. Der
## Widerstand ist manuell – das Spiel kennt die Knopfstellung nicht, die Ansage ist nur eine Empfehlung. `repeat`
## wiederholt einen Block; die Phasen heißen dann „Hart 3/10“ und tragen den Blocknamen als `group`.
##
## Ablauf: `advance(kadenz, zeit)` je Fahrschritt (in Pausen nicht), verteilt über Phasengrenzen. Die Ansage der
## nächsten Phase kommt ANNOUNCE_AHEAD_S vor dem Wechsel („In 8 s: …“), die eigene steht die ersten ANNOUNCE_HOLD_S
## einer Phase. Bewertung (ADR-0010): allein der Anteil der Zeit, in der die Kadenz im Zielbereich lag – je Phase und
## gesamt (über die gefahrene Zeit, also auch als Teilbewertung nach einem Abbruch). Kein anderer Wert geht ein.
class_name Training
extends RefCounted

## Ordner der Einheiten (je Datei eine).
const DIRECTORY := "res://trainings"
## Art einer Phase: Aufwärmen, Hauptteil (Belastung), Erholung im Hauptteil, Ausrollen.
const KIND_WARMUP := "warmup"
const KIND_WORK := "work"
const KIND_RECOVERY := "recovery"
const KIND_COOLDOWN := "cooldown"
const KINDS := [KIND_WARMUP, KIND_WORK, KIND_RECOVERY, KIND_COOLDOWN]
## Vorankündigung der nächsten Phase (s vor dem Wechsel) und Anzeigedauer der eigenen Ansage nach dem Wechsel (s).
const ANNOUNCE_AHEAD_S := 10.0
const ANNOUNCE_HOLD_S := 5.0
## Art eines Tors (`gates`, #58), gleich CourseGate.KIND_*.
const GATE_START := "start"
const GATE_FINISH := "finish"

## Die Einheit wie geladen: {name, description, phases: [{name, kind, duration_s, cadence_min, cadence_max,
## announcement, group}]}.
var unit: Dictionary
var phases: Array
## Gefahrene Zeit der Einheit (s, ohne Pausen).
var elapsed_s := 0.0
## Je Phase: gefahrene Zeit und Zeit im Zielbereich (s).
var ridden_s: Array[float] = []
var on_target_s: Array[float] = []
## Ende jeder Phase (s ab Beginn der Einheit).
var _ends: Array[float] = []


func _init(training_unit: Dictionary) -> void:
	unit = training_unit
	phases = training_unit.get("phases", [])
	var end := 0.0
	for phase in phases:
		end += phase["duration_s"]
		_ends.append(end)
		ridden_s.append(0.0)
		on_target_s.append(0.0)


## Lädt eine Einheit aus `path`; {} (mit Warnung), wenn die Datei fehlt oder ungültig ist.
static func load_file(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (parsed is Dictionary) or not (parsed.get("name") is String) or not (parsed.get("phases") is Array):
		push_warning("Training: %s fehlt oder ist keine Einheit" % path)
		return {}
	var phases := _expand(parsed["phases"])
	if phases.is_empty():
		push_warning("Training: %s hat ungültige Phasen" % path)
		return {}
	return {"name": parsed["name"], "description": str(parsed.get("description", "")), "phases": phases}


## Alle Einheiten aus `directory` (`*.json`, nach Dateiname sortiert); ungültige fehlen.
static func load_all(directory: String = DIRECTORY) -> Array:
	var units := []
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for file in files:
		if file.get_extension() == "json":
			var loaded := load_file(directory.path_join(file))
			if not loaded.is_empty():
				units.append(loaded)
	return units


## Phasen aus der Datei mit aufgelösten Wiederholungen; [] bei einem ungültigen Eintrag.
static func _expand(entries: Array) -> Array:
	var result := []
	for entry in entries:
		if not (entry is Dictionary):
			return []
		if entry.has("repeat"):
			var block := _expand(entry.get("phases", []) if entry.get("phases") is Array else [])
			var count := int(entry["repeat"]) if entry["repeat"] is float else 0
			if block.is_empty() or count < 1:
				return []
			for i in range(count):
				for phase in block:
					var copy: Dictionary = phase.duplicate()
					copy["name"] = "%s %d/%d" % [phase["name"], i + 1, count]
					copy["group"] = phase["name"]
					result.append(copy)
			continue
		var cadence = entry.get("cadence_rpm")
		if not (entry.get("name") is String) or not (entry.get("duration_s") is float) or entry["duration_s"] <= 0.0 \
				or not (cadence is Array) or cadence.size() != 2 or not (cadence[0] is float) \
				or not (cadence[1] is float) or cadence[0] > cadence[1] or not (entry.get("kind") in KINDS):
			return []
		result.append({"name": entry["name"], "kind": entry["kind"], "duration_s": float(entry["duration_s"]),
				"cadence_min": float(cadence[0]), "cadence_max": float(cadence[1]),
				"announcement": str(entry.get("announcement", "")), "group": ""})
	return result


## Gesamtdauer der Einheit (s).
func duration_s() -> float:
	return _ends[-1] if not _ends.is_empty() else 0.0


## Einen Fahrschritt von `delta_s` Sekunden mit Kadenz `cadence_rpm` werten – über Phasengrenzen anteilig, nach dem
## Ende der Einheit nichts mehr. Nur die Kadenz zählt.
func advance(cadence_rpm: float, delta_s: float) -> void:
	var left := minf(delta_s, remaining_total_s())
	while left > 0.0:
		var i := phase_index()
		var step := minf(left, _ends[i] - elapsed_s)
		if step <= 0.0:
			break
		ridden_s[i] += step
		if on_target(phases[i], cadence_rpm):
			on_target_s[i] += step
		elapsed_s += step
		left -= step


## Einheit zu Ende (nach dem Ausrollen)?
func finished() -> bool:
	return elapsed_s >= duration_s() - 1e-6


## Index der laufenden Phase (nach dem Ende die letzte).
func phase_index() -> int:
	for i in range(_ends.size()):
		if elapsed_s < _ends[i] - 1e-6:
			return i
	return _ends.size() - 1


## Laufende Phase.
func phase() -> Dictionary:
	return phases[phase_index()]


## Nächste Phase ({} in der letzten).
func next_phase() -> Dictionary:
	var i := phase_index() + 1
	return phases[i] if i < phases.size() else {}


## Restzeit der laufenden Phase (s).
func remaining_s() -> float:
	return maxf(_ends[phase_index()] - elapsed_s, 0.0)


## Restzeit der ganzen Einheit (s).
func remaining_total_s() -> float:
	return maxf(duration_s() - elapsed_s, 0.0)


## Ansage zum jetzigen Zeitpunkt ("" = keine): die nächste Phase ANNOUNCE_AHEAD_S vorher als „In 8 s: …“, die laufende
## in ihren ersten ANNOUNCE_HOLD_S. Die Vorankündigung hat Vorrang.
func announcement() -> String:
	if finished():
		return ""
	var next := next_phase()
	if not next.is_empty() and remaining_s() <= ANNOUNCE_AHEAD_S + 1e-6 and not next["announcement"].is_empty():
		return "In %d s: %s" % [ceili(remaining_s()), next["announcement"]]
	if phase()["duration_s"] - remaining_s() < ANNOUNCE_HOLD_S:
		return phase()["announcement"]
	return ""


## Treffer der Phase `index`: Anteil der gefahrenen Zeit im Zielbereich, 0..1 (NAN = nicht gefahren).
func phase_score(index: int) -> float:
	return on_target_s[index] / ridden_s[index] if ridden_s[index] > 0.0 else NAN


## Treffer gesamt über alle gefahrenen Phasen, nach Zeit gewichtet, 0..1 (NAN = nichts gefahren).
func total_score() -> float:
	var ridden := 0.0
	var on := 0.0
	for i in range(phases.size()):
		ridden += ridden_s[i]
		on += on_target_s[i]
	return on / ridden if ridden > 0.0 else NAN


## Bewertung je gefahrener Phase in einer Zeile, Wiederholungen zusammengefasst, z. B. „Aufwärmen 100 % · Hart 80 · 95 %
## · Locker 100 · 90 % · Ausrollen 100 %“. Nicht gefahrene Phasen fehlen (Teilbewertung nach einem Abbruch).
func phase_summary() -> String:
	var parts := []
	var groups := {}  # Blockname → Index in `parts` und Treffer
	for i in range(phases.size()):
		if ridden_s[i] <= 0.0:
			continue
		var group: String = phases[i]["group"]
		var percent := "%d" % roundi(phase_score(i) * 100.0)
		if group.is_empty():
			parts.append("%s %s %%" % [phases[i]["name"], percent])
		elif groups.has(group):
			groups[group]["scores"].append(percent)
		else:
			groups[group] = {"at": parts.size(), "scores": [percent]}
			parts.append("")
	for group in groups:
		parts[groups[group]["at"]] = "%s %s %%" % [group, " · ".join(groups[group]["scores"])]
	return " · ".join(parts)


## Tore der Einheit (#58): [{time_s, kind, text, phase}] nach Zeit – ein Starttor (GATE_START, Text „Start“ und
## Zielkadenz) zu Beginn jeder Belastung (KIND_WORK), ein Zieltor (GATE_FINISH, „Ziel“) an ihrem Ende, wenn keine
## Belastung folgt; folgt eine, steht dort nur deren Starttor. `time_s` ist der Phasenwechsel (s ab Beginn der Einheit),
## `phase` der Index der Phase, die dort beginnt. Aufwärmen, Erholung und Ausrollen allein bekommen keine Tore.
func gates() -> Array:
	var result := []
	for i in range(phases.size() - 1):
		var next: Dictionary = phases[i + 1]
		if next["kind"] == KIND_WORK:
			result.append({"time_s": _ends[i], "kind": GATE_START, "text": "Start  %s" % target_text(next),
					"phase": i + 1})
		elif phases[i]["kind"] == KIND_WORK:
			result.append({"time_s": _ends[i], "kind": GATE_FINISH, "text": "Ziel", "phase": i + 1})
	return result


## Liegt `cadence_rpm` im Zielbereich der Phase (Grenzen eingeschlossen)?
static func on_target(phase: Dictionary, cadence_rpm: float) -> bool:
	return cadence_rpm >= phase["cadence_min"] and cadence_rpm <= phase["cadence_max"]


## Zielkadenz für die Anzeige, z. B. „95–105 rpm“, bei gleichen Grenzen „90 rpm“.
static func target_text(phase: Dictionary) -> String:
	if is_equal_approx(phase["cadence_min"], phase["cadence_max"]):
		return "%d rpm" % roundi(phase["cadence_min"])
	return "%d–%d rpm" % [roundi(phase["cadence_min"]), roundi(phase["cadence_max"])]


## Treffer für die Anzeige, z. B. 0.874 → „87 %“, NAN → „–“.
static func percent_text(score: float) -> String:
	return "–" if is_nan(score) else "%d %%" % roundi(score * 100.0)
