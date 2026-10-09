## Erweiterung der Arcade-Bühne für Kadenzmuster und Fähigkeiten (#50, Spec #27 Stories 13 und 14): hängt sich über
## `ArcadeStage.EXTENSIONS` ein (die Hauptszene weiß davon nichts). Je Fahrschritt (`stepped`, nach `ArcadeRun.advance`)
## füttert sie den Mustererkenner (`CadencePatterns`) mit der **ungeglätteten** Kadenz `cadence_raw` (HUD und Fahrmodell
## bleiben beim geglätteten Wert, ADR-0004 Nachtrag #45), lässt die Fähigkeiten (`Abilities`) wirken und zeigt sie an
## (`AbilityHud` unter `stage.hud`, Einblendung „… ausgelöst“, bei Kombo ein Punkte-Popup). Nur im Arcade: ohne Lauf
## kommt kein `stepped`, Rundfahrt und Training sehen nichts (ADR-0010). Pausen: die Hauptszene ruft `advance` dann nicht
## auf, also läuft keine Zeit und kein Muster weiter.
##
## Für #53 (Talente, legendäre Beute): `abilities.defs[id]` ist je Lauf eine Kopie der Daten (`power`, `cooldown_s`,
## `duration_s`); ein `run_hook`, der nach diesem läuft (Anmeldung später), darf sie ändern. Schwellen der Muster stehen in
## `patterns.thresholds`.
class_name AbilityExtension
extends RefCounted

var stage: ArcadeStage
var patterns := CadencePatterns.new()
var abilities := Abilities.new()
var view: AbilityHud
## Aus: keine Muster, keine Fähigkeiten (nur Tests anderer Bausteine, die sich auf ihren eigenen Gegenstand beschränken).
var enabled := true
## Die Fahrt ist gespeichert (Ergebnis): die Leiste ist weg.
var finished := false

var _run: ArcadeRun = null


## Die Erweiterung der Bühne `stage` (null, wenn nicht angemeldet).
static func of(owner_stage: ArcadeStage) -> AbilityExtension:
	for extension in owner_stage.extensions:
		if extension is AbilityExtension:
			return extension
	return null


func attach(owner_stage: ArcadeStage) -> void:
	stage = owner_stage
	view = AbilityHud.new()
	view.extension = self
	stage.hud.add_child(view)
	stage.run_hooks.append(_on_run_begin)
	stage.stepped.connect(_on_stepped)
	stage.run_finished.connect(_on_run_finished)
	stage.summary_providers.append(_summary)
	view.refresh(abilities)


## Läuft ein Arcade-Lauf, dessen Fähigkeiten gezeigt werden sollen (HUD an, Fahrt nicht gespeichert)?
func is_shown() -> bool:
	return enabled and stage.run != null and not finished and stage.hud.visible


func _on_run_begin(run: ArcadeRun, _save_game: SaveGame) -> void:
	_reset(run)


func _reset(run: ArcadeRun) -> void:
	_run = run
	finished = false
	patterns.reset()
	abilities.reset()
	view.refresh(abilities)


func _on_stepped(_ride_m: float, _cadence: float, cadence_raw: float, delta_s: float) -> void:
	var run := stage.run
	if run == null or not enabled:
		return
	if run != _run:  # Lauf ohne `begin` (Prüfhilfen legen ihn selbst an)
		_reset(run)
	var points := abilities.combo_points
	for id in abilities.step(run, patterns.feed(cadence_raw, delta_s), delta_s):
		view.flash("%s ausgelöst" % abilities.defs[id]["name"])
		if abilities.combo_points > points:
			stage.hud.popup("+%d Kombo" % (abilities.combo_points - points), AbilityHud.COLOR_ACTIVE)
	view.refresh(abilities)


func _on_run_finished(_run_done: ArcadeRun) -> void:
	finished = true


## Zeile im Fahrtergebnis: wie oft welche Fähigkeit gewirkt hat (leer ohne Auslösung).
func _summary(_run_done: ArcadeRun) -> Array:
	var parts := []
	for id in Abilities.IDS:
		if abilities.counts[id] > 0:
			parts.append("%s %d×" % [abilities.defs[id]["name"], abilities.counts[id]])
	if parts.is_empty():
		return []
	var line := "Fähigkeiten: " + " · ".join(parts)
	if abilities.combo_points > 0:
		line += " (+%d Punkte)" % abilities.combo_points
	return [line]
