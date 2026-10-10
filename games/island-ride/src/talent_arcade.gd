## Erweiterung der Arcade-Bühne für Talente, legendäre Effekte und das Arcade-Level (#53, Spec #27 Stories 15 und 21):
## Beim Start eines Arcade-Laufs (`run_hooks` der Bühne – laufen nur im Arcade, ADR-0010) legt sie die erlernten Talente und
## die Effekte der angelegten legendären Teile auf den Lauf (BuildEffects): Fähigkeiten (`AbilityExtension.abilities.defs`),
## Schwellen der Muster, `run.gear`. Der Hook läuft **nach** dem der Fähigkeiten-Erweiterung (#50, die ihre `defs` beim Start
## zurücksetzt) – darum hängt die Hauptszene diese Erweiterung nach dem Aufbau der Bühne an (`attach`, nicht in
## `ArcadeStage.EXTENSIONS`: die Reihenfolge der Hooks ist die der Anmeldung). Der Rückstoß
## legendärer Teile („Antritt wirft Gegner zurück“) wirkt je Fahrschritt (`stepped`), wenn die Windböe in diesem Schritt
## ausgelöst hat. Am Ende der Fahrt (`run_finished`) zählt sie die Punkte des Laufs zum Arcade-Level (ArcadeLevel) und
## schreibt eine Zeile in die Zusammenfassung. Rundfahrt und Training kennen nichts davon.
class_name TalentArcade
extends RefCounted

var stage: ArcadeStage
## Rückstoß dieses Laufs ({} = keiner), Summe der Effekte (BuildEffects.apply).
var knockback := {}

var _save: SaveGame = null
var _run: ArcadeRun = null
## Von diesem Hook verschobene Schwellen der Muster (beim nächsten Lauf zurück auf den Standard).
var _moved_thresholds: Array = []
## Windböen, die schon auf einen Rückstoß geprüft sind.
var _seen_gusts := 0
## Level vor dem Lauf und nach der Gutschrift (-1 = Fahrt noch nicht gespeichert).
var _level_before := 1
var _level_after := -1


func attach(owner_stage: ArcadeStage) -> void:
	stage = owner_stage
	stage.run_hooks.append(_on_run_begin)
	stage.stepped.connect(_on_stepped)
	stage.run_finished.connect(_on_run_finished)
	stage.summary_providers.append(_summary)


func _on_run_begin(run: ArcadeRun, save_game: SaveGame) -> void:
	_run = run
	_save = save_game
	_level_before = ArcadeLevel.level(save_game)
	_level_after = -1
	_seen_gusts = 0
	var abilities: Abilities = null
	var patterns: CadencePatterns = null
	var extension := AbilityExtension.of(stage)
	if extension != null:
		abilities = extension.abilities
		patterns = extension.patterns
		for key in _moved_thresholds:  # Schwellen des vorigen Laufs zurück, bevor die Talente dieses Laufs wirken
			patterns.thresholds[key] = CadencePatterns.THRESHOLDS[key]
	var applied := BuildEffects.apply(BuildEffects.changes_for(save_game), run, abilities, patterns)
	knockback = applied["knockback"]
	_moved_thresholds = applied["thresholds"]


## Nach der Fähigkeiten-Erweiterung (deren `stepped`-Verbindung ist älter): hat die Windböe in diesem Schritt ausgelöst, wirft
## der Rückstoß den Gegner zurück.
func _on_stepped(_ride_m: float, cadence: float, _cadence_raw: float, _delta_s: float) -> void:
	var extension := AbilityExtension.of(stage)
	if stage.run == null or extension == null or not extension.enabled:
		return
	var gusts: int = extension.abilities.counts["windboe"]
	var fresh := gusts > _seen_gusts
	_seen_gusts = gusts
	if not fresh or knockback.is_empty() or stage.run.active.is_empty():
		return
	if BuildEffects.knock_back(stage.run.active["block"], cadence, knockback):
		stage.hud.popup("Rückstoß!", AbilityHud.COLOR_ACTIVE)


## Die Fahrt ist gespeichert: ihre Punkte zählen zum Arcade-Level.
func _on_run_finished(run: ArcadeRun) -> void:
	if _save == null or run != _run or _level_after >= 0:
		return
	ArcadeLevel.add_points(_save, run.points)
	_level_after = ArcadeLevel.level(_save)


## Zeile im Fahrtergebnis: Arcade-Level, neues Level und freie Talentpunkte, sonst die Punkte bis zum nächsten Level.
func _summary(run: ArcadeRun) -> Array:
	if _save == null or run != _run or _level_after < 0:
		return []
	var line := "Arcade-Level %d" % _level_after
	if _level_after > _level_before:
		line += " – neues Level!"
	var free := Talents.available(_save)
	if free > 0:
		line += " · %d %s frei" % [free, "Talentpunkt" if free == 1 else "Talentpunkte"]
	elif _level_after < ArcadeLevel.MAX_LEVEL:
		line += " · noch %d Punkte bis Level %d" % [ArcadeLevel.points_to_next(ArcadeLevel.total_points(_save)),
				_level_after + 1]
	return [line]
