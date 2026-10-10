## Darstellung der Elite-Gruppen (#52; Eintrag `"elite"` in `ArcadeStage.PROPS`): Eine Elite-Gruppe ist eine Phasenfolge
## (EliteGroup) aus vorhandenen Bausteinen – ihre Phasen zeigt die Darstellung ihres Typs (Zugbrücke, Verfolger,
## Takt-Tore, Kristalle): dieser Prop reicht `begin`/`follow`/`end` an sie weiter, Phase für Phase (eine Phase vor dem
## Gefolge endet an ihrem eigenen Ende, TimedMarkers; die letzte am Ziel der Gruppe). Dazu die Elite-Markierung:
## - die **Standarte** (EliteBanner) in der Farbe der Elite-Stufe mit Stufe, Herausforderung und Eigenschaften – vor dem
##   Start am Startpunkt (ab ANNOUNCE_M voraus), im Kampf AHEAD_M voraus, danach bleibt sie stehen, bis sie hinter dem
##   Fahrer liegt;
## - das **Schild** im HUD (EliteBadge) oben in der Mitte: Ankündigung, Stand (Anführer/Gefolge mit Ziel), Ergebnis.
## Nur Anzeige (ADR-0010); nach dem Speichern der Fahrt (Ergebnis) nichts mehr.
class_name EliteProp
extends ArcadeProp

## Im Kampf steht die Standarte so weit voraus (m); vor dem Start so weit hinter dem Startpunkt (neben dem Starttor).
const AHEAD_M := 24.0
const START_OFFSET_M := 6.0
## Ab dieser Entfernung (m) wird die nächste Elite-Gruppe angekündigt.
const ANNOUNCE_M := 300.0

var banner: EliteBanner
var badge: EliteBadge
## Ende der laufenden Phase auf der Strecke (für die Darstellung der Phase, wenn danach noch eine kommt).
var markers := TimedMarkers.new()

var _group: EliteGroup = null
var _phase: ChallengeBlock = null
var _phase_prop: ArcadeProp = null
var _done := false


func attach(owner_stage) -> void:
	super(owner_stage)
	banner = EliteBanner.new()
	stage.track.add_child(banner)
	badge = EliteBadge.new()
	if stage.props.has("boss"):
		badge.avoid = stage.props["boss"].bar  # Ergebnis eines Bosskampfs: das Schild rückt darunter
	stage.hud.add_child(badge)
	stage.run_finished.connect(_on_run_finished)


func begin(block: ChallengeBlock) -> void:
	_group = block as EliteGroup
	_phase = null
	_phase_prop = null
	if _group == null:
		return
	banner.show_group(EliteGroups.color_of(_group.rank), _group.boss_name, _affix_text(_group.affixes))
	_sync_phase()


func follow(block: ChallengeBlock, finish_at: float) -> bool:
	if _group == null or block != _group or _done:
		return false
	_sync_phase()
	var replaces := false
	if _phase_prop != null:
		replaces = _phase_prop.follow(_phase, _phase_finish(finish_at))
	banner.place(stage.track, stage.distance_m + AHEAD_M)
	banner.visible = true
	badge.show_group(_group)
	return replaces


## Keine Elite-Gruppe läuft: die nächste ankündigen (wenn sonst nichts läuft), sonst bleibt die Standarte einer
## beendeten stehen, bis sie hinter dem Fahrer liegt.
func idle() -> void:
	if _done or stage.run == null:
		return
	var run: ArcadeRun = stage.run
	var next := run.next_challenge() if run.active.is_empty() else {}
	if not next.is_empty() and next["definition"].get("block") == EliteGroups.ID \
			and next["at_m"] - stage.distance_m <= ANNOUNCE_M:
		var definition: Dictionary = next["definition"]
		var at: float = next["at_m"] + START_OFFSET_M
		banner.show_group(EliteGroups.color_of(EliteGroups.rank_of(definition)), definition["name"],
				_affix_text(definition.get("elite", {}).get("affixes", [])))
		banner.place(stage.track, at)
		banner.visible = _in_view(at)
		if badge.mode != EliteBadge.RESULT:  # das Ergebnis der vorigen Gruppe steht zu Ende
			badge.announce(definition, ceili(next["at_m"] - stage.distance_m))
		return
	banner.visible = banner.visible and _in_view(banner.ride_m)
	if badge.mode == EliteBadge.ANNOUNCE:
		badge.reset()


func end(block: ChallengeBlock) -> void:
	if _group == null or block != _group:
		return
	if _phase_prop != null:
		_phase_prop.end(_phase)
	badge.finish(_group)
	_group = null
	_phase = null
	_phase_prop = null


func clear() -> void:
	_group = null
	_phase = null
	_phase_prop = null
	_done = false
	banner.reset()
	badge.reset()


func hide() -> void:
	banner.visible = false
	badge.reset()


func _on_run_finished(_run: ArcadeRun) -> void:
	_done = true  # im Ergebnis weder Standarte noch Schild
	banner.reset()
	badge.reset()


## Die laufende Phase hat gewechselt: die vorige Darstellung schließt ab, die der neuen beginnt.
func _sync_phase() -> void:
	var phase := _group.current_phase()
	if phase == _phase:
		return
	if _phase_prop != null:
		_phase_prop.end(_phase)
	_phase = phase
	var id: String = _group.phase_definition().get("block", "")
	_phase_prop = stage.props.get(id) if id != EliteGroups.ID else null
	markers.reset(1)
	if _phase_prop != null:
		_phase_prop.begin(_phase)


## Ende der laufenden Phase auf der Strecke: die letzte endet mit der Gruppe (`finish_at`), eine frühere dort, wo der
## Fahrer beim aktuellen Tempo ihr Zeitfenster beendet.
func _phase_finish(finish_at: float) -> float:
	if _group.index >= _group.phase_count() - 1:
		return finish_at
	var d: float = stage.distance_m
	markers.measure(d, _phase.elapsed_s)
	var at := markers.position_of(0, d, _phase.remaining_s())
	return finish_at if is_nan(at) else at


## Liegt die Fahrtposition `at` im Bild (höchstens `keep_behind_m` hinter dem Fahrer, nicht eine Runde voraus)?
func _in_view(at: float) -> bool:
	return not is_nan(at) and at > stage.distance_m - stage.keep_behind_m \
			and at - stage.distance_m < stage.track.length_m() - stage.keep_behind_m


static func _affix_text(affix_ids: Array) -> String:
	return " · ".join(affix_ids.map(func(id): return EliteGroups.AFFIXES[id]["name"]))
