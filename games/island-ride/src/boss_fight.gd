## Baustein „Bosskampf“ (#51, Spec #27 Story 11): ein Boss ist eine Folge von **Phasen**, jede ein vorhandener Baustein
## (Zone halten, Durchbruch, Jagd, …) mit eigenen Parametern – Daten, keine Sonderlogik (src/challenges/boss_challenges.gd).
## Die Phasen laufen nacheinander; jede beginnt mit ihrer eigenen Zeit bei 0. Alle geschafft → **besiegt**. Scheitert eine
## Phase (Zeitfenster vorbei, eingeholt), **entkommt** der Boss – weich: nur dieser Kampf ist zu Ende, die Fahrt geht weiter.
##
## Der **Lebensbalken** (`health`, 1 = voll) sinkt nur mit dem, was die Kadenz in der Zielzone (bzw. über der Schwelle) in
## den Phasen erarbeitet: jede geschaffte Phase zählt 1/n, die laufende ihren Beute-Fortschritt (`loot_progress`, also ohne
## geschenkten Vorsprung einer Jagd). Fällt der Balken einer Durchbruch-Phase zurück, erholt sich der Boss entsprechend.
## `progress` ist der Stand des Kampfes wie bei jedem Baustein (geschaffte Phasen plus Fortschritt der laufenden).
##
## Ausrüstung und Fähigkeiten (#49, #50) wirken über `progress_factor`: der Kampf reicht ihn in jedem Schritt an die
## laufende Phase weiter, die ihn wie jeder Baustein nur auf Fortschritt mit Kadenz in der Zone anwendet. Das Schild (#50)
## sichert die Skript-Variablen dieses Bausteins – `phase_state` spiegelt dafür den Zustand der laufenden Phase (ihre Zeit
## läuft beim Zurücknehmen weiter).
##
## Die Phasen baut `Encounters.build` (Wächter des Kadenzbereichs, Stufe, Ausrüstung); den Konstruktor nie direkt aufrufen.
class_name BossFight
extends ChallengeBlock

## Wer der Boss ist (Daten-`id` und Name; die Darstellung wählt danach ihre Gestalt).
var boss_id := ""
var boss_name := ""
## Phasen (ChallengeBlock) und ihre Definitionen (Name, Ziel), in Kampfreihenfolge.
var phases: Array = []
var definitions: Array = []
## Index der laufenden Phase (= Zahl der geschafften; nach dem Sieg = Zahl der Phasen).
var index := 0
## Zustand der laufenden Phase (für das Schild, #50): lesen liefert ihre Skript-Variablen, schreiben stellt sie wieder her.
var phase_state: Dictionary:
	get:
		return _state_of(current_phase())
	set(value):
		_restore(current_phase(), value)


func _init(id: String, title: String, phase_blocks: Array, phase_definitions: Array) -> void:
	boss_id = id
	boss_name = title
	phases = phase_blocks
	definitions = phase_definitions
	if phases.is_empty():
		state = FAILED


## Die laufende Phase (nach dem Ende die letzte gespielte; null ohne Phasen).
func current_phase() -> ChallengeBlock:
	if phases.is_empty():
		return null
	return phases[mini(index, phases.size() - 1)]


## Definition der laufenden Phase ({} ohne Phasen).
func phase_definition() -> Dictionary:
	return definitions[mini(index, definitions.size() - 1)] if not definitions.is_empty() else {}


## Nummer der laufenden Phase (1..n).
func phase_number() -> int:
	return mini(index + 1, phases.size())


func phase_count() -> int:
	return phases.size()


## Lebensbalken 1 (voll) .. 0 (besiegt).
func health() -> float:
	return 1.0 - loot_progress()


func progress() -> float:
	return _share(func(phase: ChallengeBlock): return phase.progress())


func loot_progress() -> float:
	return _share(func(phase: ChallengeBlock): return phase.loot_progress())


func score_caption() -> String:
	return "Kampf"


## Restzeit der laufenden Phase plus die Zeitfenster der folgenden (das späteste Ende des Kampfes).
func remaining_s() -> float:
	if finished():
		return 0.0
	var total := 0.0
	for i in range(index, phases.size()):
		total += phases[i].remaining_s()
	return total


func zone() -> Vector2:
	var phase := current_phase()
	return phase.zone() if phase != null else Vector2(NAN, NAN)


func _step(cadence_rpm: float, delta_s: float) -> void:
	elapsed_s += delta_s
	var phase := current_phase()
	phase.progress_factor = progress_factor
	phase.update(cadence_rpm, delta_s)
	if phase.state == SUCCEEDED:
		index += 1
		if index >= phases.size():
			state = SUCCEEDED
	elif phase.state == FAILED:
		state = FAILED  # der Boss entkommt


## Anteil am ganzen Kampf: geschaffte Phasen je 1, die laufende mit `value` (0..1).
func _share(value: Callable) -> float:
	if phases.is_empty():
		return 0.0
	var done := mini(index, phases.size())
	var running: float = value.call(phases[done]) if done < phases.size() else 0.0
	return clampf((done + running) / phases.size(), 0.0, 1.0)


static func _state_of(phase: ChallengeBlock) -> Dictionary:
	var values := {}
	if phase == null:
		return values
	for property in phase.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = phase.get(property["name"])
			values[property["name"]] = value.duplicate() if value is Array or value is Dictionary else value
	return values


static func _restore(phase: ChallengeBlock, values: Dictionary) -> void:
	if phase == null:
		return
	var elapsed := phase.elapsed_s
	for key in values:
		var value = values[key]
		phase.set(key, value.duplicate() if value is Array or value is Dictionary else value)
	phase.elapsed_s = elapsed
