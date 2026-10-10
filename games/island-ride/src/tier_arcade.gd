## Erweiterung der Arcade-Bühne für Stufen und Rundensteigerung (#54, Spec #27 Stories 1, 2, 22, 23), angemeldet über
## `ArcadeStage.EXTENSIONS`: Beginnt im Lauf eine neue Runde, meldet ein Popup „Runde N – härter und lohnender“ (die
## Steigerung selbst rechnet der reine Lauf, ArcadeRun/ArcadeTiers.level). Am Ende der Fahrt (`run_finished`, nach dem
## Speichern des Fahrteintrags; die Hauptszene schreibt den Spielstand danach auf die Platte) trägt sie die besiegten
## Bosse für die Stufe ein und schaltet die nächste Stufe frei, wenn die Stufe damit abgeschlossen ist
## (ArcadeTiers.record_run). In der Zusammenfassung steht eine Zeile dazu, bei mehreren Runden auch die erreichte
## Steigerung. Nur im Arcade (ADR-0010): ohne Lauf kommt kein Hook und kein Signal.
class_name TierArcade
extends RefCounted

## Farbe des Runden-Popups.
const COLOR_ROUND := Color(0.55, 0.85, 1.0)

var stage: ArcadeStage

var _save: SaveGame = null
var _run: ArcadeRun = null
## Höchste Runde im Lauf, die schon gemeldet ist.
var _lap_index := 0
## Neu freigeschaltete Stufe (0 = keine), -1 = Fahrt noch nicht gespeichert.
var _unlocked := -1


## Die Erweiterung der Bühne `stage` (null, wenn nicht angemeldet).
static func of(owner_stage: ArcadeStage) -> TierArcade:
	for extension in owner_stage.extensions:
		if extension is TierArcade:
			return extension
	return null


func attach(owner_stage: ArcadeStage) -> void:
	stage = owner_stage
	stage.run_hooks.append(_on_run_begin)
	stage.stepped.connect(_on_stepped)
	stage.run_finished.connect(_on_run_finished)
	stage.summary_providers.append(_summary)


func _on_run_begin(run: ArcadeRun, save_game: SaveGame) -> void:
	_run = run
	_save = save_game
	_lap_index = 0
	_unlocked = -1


## Neue Runde im Lauf erreicht: ab jetzt geplante Herausforderungen sind härter und lohnender.
func _on_stepped(ride_m: float, _cadence: float, _cadence_raw: float, _delta_s: float) -> void:
	if stage.run == null or stage.run != _run:
		return
	var lap_index := _run.lap_index_at(ride_m)
	if lap_index <= _lap_index:
		return
	_lap_index = lap_index
	stage.hud.popup("Runde %d – härter und lohnender" % (lap_index + 1), COLOR_ROUND)


## Die Fahrt ist gespeichert: besiegte Bosse eintragen, ggf. die nächste Stufe freischalten (einmal je Lauf).
func _on_run_finished(run: ArcadeRun) -> void:
	if _save == null or run != _run or _unlocked >= 0:
		return
	_unlocked = ArcadeTiers.record_run(_save, run)


## Zeilen im Fahrtergebnis: erreichte Rundensteigerung (ab Runde 2) und Freischalten bzw. der Stand zum nächsten Ziel.
func _summary(run: ArcadeRun) -> Array:
	if _save == null or run != _run or _unlocked < 0:
		return []
	var lines := []
	if _lap_index > 0:
		var start := ArcadeTiers.level(run.tier)
		var now := ArcadeTiers.level(run.tier, _lap_index)
		lines.append("Runde %d erreicht: Zonen %d rpm schmaler · Punkte +%d %%" % [_lap_index + 1,
				roundi(start["zone_width_rpm"] - now["zone_width_rpm"]),
				roundi((now["points_factor"] / start["points_factor"] - 1.0) * 100.0)])
	if _unlocked > 0:
		lines.append("%s freigeschaltet!" % ArcadeTiers.get_tier(_unlocked)["name"])
	elif run.tier == ArcadeTiers.unlocked(_save) and run.tier < ArcadeTiers.LIST.size():
		lines.append("Für %s: %d/%d Bosse auf %s besiegt" % [ArcadeTiers.get_tier(run.tier + 1)["name"],
				ArcadeTiers.defeated(_save, run.tier).size(), ArcadeTiers.bosses().size(),
				ArcadeTiers.get_tier(run.tier)["name"]])
	return lines
