## Darstellung der Bosse (#51): die Gestalt des Bosses voraus auf der Strecke (BossFigure, nach der `id` der Daten:
## Tramuntana, Drac de na Coca, Dimonis) und sein Lebensbalken oben im HUD (BossBar). Im Kampf steht der Boss voraus – bei
## einer Jagd-Phase umso näher, je dichter der Fahrer ihm auf den Fersen ist – und wird mit sinkendem Lebensbalken kleiner;
## besiegt sinkt er zusammen, beim Scheitern entkommt er (zieht davon). Der Boss ist das Ziel: kein Zieltor im Kampf. Nur
## Anzeige (ADR-0010).
class_name BossProp
extends ArcadeProp

var figure: BossFigure
var bar: BossBar
var _block: BossFight = null
## Die Fahrt ist gespeichert (Ergebnis): nichts mehr zeigen, bis zur nächsten Fahrt.
var _done := false


func attach(owner_stage) -> void:
	super(owner_stage)
	figure = BossFigure.new()
	stage.track.add_child(figure)
	bar = BossBar.new()
	stage.hud.add_child(bar)
	stage.run_finished.connect(_on_run_finished)


func begin(block: ChallengeBlock) -> void:
	_block = block as BossFight
	if _block == null:
		return
	figure.appear(_block.boss_id)
	bar.start(_block.boss_name)


func follow(block: ChallengeBlock, _finish_at: float) -> bool:
	var boss := block as BossFight
	if boss == null or boss != _block:
		return false
	if _done:
		return true
	figure.follow(stage.track, stage.distance_m, ahead_of(boss), boss.health(), boss.current_phase() is Breakthrough)
	bar.show_fight(boss)
	return true  # der Boss ist das Ziel


func idle() -> void:
	figure.track_rider(stage.distance_m)


func end(block: ChallengeBlock) -> void:
	var boss := block as BossFight
	if boss == null or boss != _block:
		return
	if boss.state == ChallengeBlock.SUCCEEDED:
		figure.defeat()
	else:
		figure.escape()
	bar.finish(boss)
	_block = null


func covers_finish_gate() -> bool:
	return figure.visible


func clear() -> void:
	_block = null
	_done = false
	figure.reset()
	bar.reset()


func hide() -> void:
	figure.reset()
	bar.reset()


func _on_run_finished(_run: ArcadeRun) -> void:
	_done = true  # im Ergebnis weder Gestalt noch Balken
	figure.reset()
	bar.reset()


## Abstand der Gestalt voraus (m): bei einer Jagd-Phase nach ihrem Stand (0 = entwischt, weit voraus; 1 = eingeholt),
## sonst nach der Gestalt.
static func ahead_of(boss: BossFight) -> float:
	var phase := boss.current_phase()
	if phase is Chase:
		return lerpf(BossFigure.CHASE_FAR_M, BossFigure.CHASE_NEAR_M, phase.progress())
	return BossFigure.AHEAD_M.get(boss.boss_id, BossFigure.AHEAD_M[BossFigure.TRAMUNTANA])
