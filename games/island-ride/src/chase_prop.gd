## Darstellung der Jagd (#47, verschoben aus der Hauptszene in #63): der Verfolger läuft hinter dem Fahrer, je weiter
## hinten, desto größer der Abstand; nach der Jagd zieht er ab. Nur Anzeige (ADR-0010).
class_name ChaseProp
extends ArcadeProp

var pursuer: Pursuer


func attach(owner_stage) -> void:
	super(owner_stage)
	pursuer = Pursuer.new()
	stage.track.add_child(pursuer)


func begin(block: ChallengeBlock) -> void:
	pursuer.reset(block.progress())


func follow(block: ChallengeBlock, _finish_at: float) -> bool:
	pursuer.follow(stage.track, stage.distance_m, block.progress())
	return false


func end(_block: ChallengeBlock) -> void:
	pursuer.dismiss()


func clear() -> void:
	pursuer.reset(0.0)


func hide() -> void:
	pursuer.reset(0.0)
