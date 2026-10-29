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
##
## ERG (Spec #75): Statt der Zielkadenz kann jede Phase eine Zielleistung tragen – absolut `"power_w": 250` oder relativ
## zur FTP des Profils `"power_ftp": 0.9` (Anteil); `cadence_rpm` ist dann freiwillig. Hat eine Phase ein Watt-Ziel,
## brauchen es alle: Die Einheit ist dann eine ERG-Einheit (`erg()`), der Trainer hält die Leistung, das Spiel führt
## durch die Einheit. Die Zielleistung je Phase (`target_w`, W) löst `_init` mit der FTP auf; ohne FTP bleibt sie bei
## %-FTP-Phasen NAN, die Einheit ist dann nicht startbar (`startable`). Bewertet wird in ERG-Einheiten die gemessene
## Leistung im Zielband (Ziel ± POWER_BAND_SHARE, mindestens ± POWER_BAND_MIN_W), angesagt die Zielleistung („In 8 s:
## 250 W“) statt des Widerstandsknopfs.
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
## Zielband einer ERG-Phase: ± 5 % der Zielleistung, mindestens ± 10 W (das Größere).
const POWER_BAND_SHARE := 0.05
const POWER_BAND_MIN_W := 10.0
## Art eines Tors (`gates`, #58), gleich CourseGate.KIND_*.
const GATE_START := "start"
const GATE_FINISH := "finish"

## Die Einheit wie geladen: {name, description, erg, phases: [{name, kind, duration_s, cadence_min, cadence_max,
## power_w, power_ftp, announcement, group}]}; in `phases` je Phase zusätzlich `target_w` (W, NAN = kein Watt-Ziel).
var unit: Dictionary
var phases: Array
## Gefahrene Zeit der Einheit (s, ohne Pausen).
var elapsed_s := 0.0
## Je Phase: gefahrene Zeit und Zeit im Zielbereich (s).
var ridden_s: Array[float] = []
var on_target_s: Array[float] = []
## Ende jeder Phase (s ab Beginn der Einheit).
var _ends: Array[float] = []


## `ftp_w`: FTP des Profils (W, 0 = nicht gesetzt) für Phasen mit `power_ftp`.
func _init(training_unit: Dictionary, ftp_w: int = 0) -> void:
	unit = training_unit
	phases = []
	var end := 0.0
	for source in training_unit.get("phases", []):
		var phase: Dictionary = source.duplicate()
		phase["target_w"] = target_watts(phase, ftp_w)
		phases.append(phase)
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
	var with_power := phases.filter(func(p): return not is_nan(p["power_w"]) or not is_nan(p["power_ftp"])).size()
	if with_power != 0 and with_power != phases.size():
		push_warning("Training: %s mischt Phasen mit und ohne Watt-Ziel" % path)
		return {}
	return {"name": parsed["name"], "description": str(parsed.get("description", "")), "erg": with_power > 0,
			"phases": phases}


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
		var power_w = entry.get("power_w")
		var power_ftp = entry.get("power_ftp")
		var has_power := power_w != null or power_ftp != null
		if (power_w != null and not (power_w is float and power_w > 0.0)) \
				or (power_ftp != null and not (power_ftp is float and power_ftp > 0.0)) \
				or (power_w != null and power_ftp != null):
			return []  # höchstens eins von beiden, positiv
		if not (entry.get("name") is String) or not (entry.get("duration_s") is float) or entry["duration_s"] <= 0.0 \
				or not (entry.get("kind") in KINDS):
			return []
		if not (cadence == null and has_power) and (not (cadence is Array) or cadence.size() != 2 \
				or not (cadence[0] is float) or not (cadence[1] is float) or cadence[0] > cadence[1]):
			return []  # ohne Watt-Ziel ist die Zielkadenz Pflicht
		result.append({"name": entry["name"], "kind": entry["kind"], "duration_s": float(entry["duration_s"]),
				"cadence_min": float(cadence[0]) if cadence != null else NAN,
				"cadence_max": float(cadence[1]) if cadence != null else NAN,
				"power_w": float(power_w) if power_w != null else NAN,
				"power_ftp": float(power_ftp) if power_ftp != null else NAN,
				"announcement": str(entry.get("announcement", "")), "group": ""})
	return result


## Zielleistung einer Phase (wie `_expand`) in W mit der FTP `ftp_w` (0 = nicht gesetzt): absolut, aus dem Anteil der
## FTP (gerundet) oder NAN (kein Watt-Ziel bzw. %-FTP ohne FTP).
static func target_watts(phase: Dictionary, ftp_w: int) -> float:
	if not is_nan(phase.get("power_w", NAN)):
		return roundf(phase["power_w"])
	if not is_nan(phase.get("power_ftp", NAN)) and ftp_w > 0:
		return roundf(phase["power_ftp"] * ftp_w)
	return NAN


## Braucht die Einheit eine FTP (eine Phase in % FTP)?
static func needs_ftp(training_unit: Dictionary) -> bool:
	return training_unit.get("phases", []).any(func(p): return not is_nan(p.get("power_ftp", NAN)))


## Lässt sich die Einheit mit der FTP `ftp_w` (0 = nicht gesetzt) fahren? %-FTP-Einheiten nur mit FTP.
static func startable(training_unit: Dictionary, ftp_w: int) -> bool:
	return ftp_w > 0 or not needs_ftp(training_unit)


## ERG-Einheit (Watt-Ziele)?
func erg() -> bool:
	return unit.get("erg", false)


## Zielleistung der laufenden Phase in ganzen W (-1 = kein Watt-Ziel).
func target_power_w() -> int:
	var watts: float = phase()["target_w"]
	return -1 if is_nan(watts) else roundi(watts)


## Gesamtdauer der Einheit (s).
func duration_s() -> float:
	return _ends[-1] if not _ends.is_empty() else 0.0


## Einen Fahrschritt von `delta_s` Sekunden mit Kadenz `cadence_rpm` werten – über Phasengrenzen anteilig, nach dem
## Ende der Einheit nichts mehr. Nur die Kadenz zählt, in einer ERG-Einheit nur die gemessene Leistung `power_w` (NAN =
## keine, nicht im Ziel).
func advance(cadence_rpm: float, delta_s: float, power_w: float = NAN) -> void:
	var left := minf(delta_s, remaining_total_s())
	while left > 0.0:
		var i := phase_index()
		var step := minf(left, _ends[i] - elapsed_s)
		if step <= 0.0:
			break
		ridden_s[i] += step
		if (on_target_power(phases[i], power_w) if erg() else on_target(phases[i], cadence_rpm)):
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
## in ihren ersten ANNOUNCE_HOLD_S. Die Vorankündigung hat Vorrang. Eine ERG-Einheit sagt die Zielleistung an („In 8 s:
## 250 W“). Die Ansage zum Widerstandsknopf entfällt mit `with_knob == false` (VSpin regelt den Widerstand selbst).
func announcement(with_knob: bool = true) -> String:
	if finished() or (not erg() and not with_knob):
		return ""
	var next := next_phase()
	if not next.is_empty() and remaining_s() <= ANNOUNCE_AHEAD_S + 1e-6 and not _announcement_of(next).is_empty():
		return "In %d s: %s" % [ceili(remaining_s()), _announcement_of(next)]
	if phase()["duration_s"] - remaining_s() < ANNOUNCE_HOLD_S:
		return _announcement_of(phase())
	return ""


func _announcement_of(of_phase: Dictionary) -> String:
	return target_text(of_phase) if erg() else of_phase["announcement"]


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


## Zielband der ERG-Phase (W, Grenzen eingeschlossen): [Ziel − Band, Ziel + Band]; [NAN, NAN] ohne Watt-Ziel.
static func power_range(phase: Dictionary) -> Array:
	var target: float = phase.get("target_w", NAN)
	var band := maxf(target * POWER_BAND_SHARE, POWER_BAND_MIN_W)
	return [target - band, target + band]


## Liegt `power_w` im Zielband der Phase? NAN (keine Leistung, kein Ziel) nie.
static func on_target_power(phase: Dictionary, power_w: float) -> bool:
	var band := power_range(phase)
	return power_w >= band[0] and power_w <= band[1]


## Liegt `cadence_rpm` im Zielbereich der Phase (Grenzen eingeschlossen)?
static func on_target(phase: Dictionary, cadence_rpm: float) -> bool:
	return cadence_rpm >= phase["cadence_min"] and cadence_rpm <= phase["cadence_max"]


## Zielkadenz für die Anzeige, z. B. „95–105 rpm“, bei gleichen Grenzen „90 rpm“; mit Watt-Ziel die Zielleistung
## („250 W“, „– W“ ohne FTP).
static func target_text(phase: Dictionary) -> String:
	if phase.has("target_w") and (not is_nan(phase.get("power_w", NAN)) or not is_nan(phase.get("power_ftp", NAN))):
		return "– W" if is_nan(phase["target_w"]) else "%d W" % roundi(phase["target_w"])
	if is_equal_approx(phase["cadence_min"], phase["cadence_max"]):
		return "%d rpm" % roundi(phase["cadence_min"])
	return "%d–%d rpm" % [roundi(phase["cadence_min"]), roundi(phase["cadence_max"])]


## Treffer für die Anzeige, z. B. 0.874 → „87 %“, NAN → „–“.
static func percent_text(score: float) -> String:
	return "–" if is_nan(score) else "%d %%" % roundi(score * 100.0)
