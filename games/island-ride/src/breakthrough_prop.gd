## Darstellung des Durchbruchs (#47, verschoben aus der Hauptszene in #63): die Zugbrücke steht statt des Zieltors dort,
## wo das Zeitfenster endet, und senkt sich mit dem Balken; danach öffnet sie sich ganz (nach Scheitern langsam). Eine
## frühere Brücke bleibt stehen, bis sie hinter dem Fahrer liegt. Nur Anzeige (ADR-0010).
class_name BreakthroughProp
extends ArcadeProp

var bridge: Drawbridge


func attach(owner_stage) -> void:
	super(owner_stage)
	bridge = Drawbridge.new()
	bridge.visible = false
	stage.track.add_child(bridge)


func begin(_block: ChallengeBlock) -> void:
	bridge.reset()


func follow(block: ChallengeBlock, finish_at: float) -> bool:
	bridge.place(stage.track, finish_at)
	bridge.follow(block.progress())
	bridge.visible = stage.gate_placement.shown(stage.distance_m)
	return true  # die Brücke ist das Ziel


func idle() -> void:
	bridge.visible = _opened_shown()  # eine frühere Brücke bleibt, bis sie hinter dem Fahrer liegt


func end(block: ChallengeBlock) -> void:
	bridge.release(block.state == ChallengeBlock.SUCCEEDED)


func covers_finish_gate() -> bool:
	return bridge.visible


func clear() -> void:
	bridge.ride_m = NAN
	bridge.visible = false


func hide() -> void:
	bridge.visible = false


## Steht eine geöffnete Brücke noch im Bild? Sie liegt voraus (nach einem Erfolg öffnet sie sich schon vor dem Fahrer)
## oder höchstens `keep_behind_m` hinter ihm.
func _opened_shown() -> bool:
	var at := bridge.ride_m
	return not is_nan(at) and bridge.target >= 1.0 and at > stage.distance_m - stage.keep_behind_m \
			and at - stage.distance_m < stage.track.length_m() - stage.keep_behind_m
