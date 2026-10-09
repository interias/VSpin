## Darstellung (Requisiten) eines Bausteintyps im Arcade-Lauf (#63; Muster aus #47): Zugbrücke des Durchbruchs,
## Verfolger der Jagd. Die ArcadeStage hält je Bausteintyp höchstens eine Instanz (`ArcadeStage.PROPS`, eine Zeile je Typ)
## und ruft sie während der Fahrt – die Requisiten sind reine Anzeige (ADR-0010) und wissen nichts vom Spielstand.
##
## Neue Darstellung (z. B. Takt-Tore #48, Boss #51): `extends ArcadeProp`, nur die Methoden überschreiben, die nötig sind,
## und in `ArcadeStage.PROPS` eintragen: `"<block-id>": preload("res://src/<name>_prop.gd"),`. Ihre Knoten hängen sie in
## `attach` an `stage.track` (lokale Pfadkoordinaten, `track.ride_position_at`). Aus der Stage lesen sie
## `stage.track`, `stage.distance_m` (Fahrtposition), `stage.keep_behind_m` (so lange bleibt Durchfahrenes stehen) und
## `stage.gate_placement` (GatePlacement des Zieltors).
class_name ArcadeProp
extends RefCounted

## Die ArcadeStage, der diese Darstellung gehört (untypisiert: die Stage kennt die Requisiten, nicht umgekehrt).
var stage = null


## Einmal beim Aufbau der Stage: Knoten an `stage.track` hängen (Reihenfolge der Einträge in `PROPS` = Reihenfolge der Kinder).
func attach(owner_stage) -> void:
	stage = owner_stage


## Die Herausforderung `block` dieses Typs beginnt (auch wenn die vorige im selben Schritt endete).
func begin(_block: ChallengeBlock) -> void:
	pass


## Jeder Anzeigeschritt der laufenden Herausforderung `block` dieses Typs. `finish_at` = Lage des Zieltors (GatePlacement).
## Rückgabe true = diese Darstellung ersetzt das Zieltor (es wird nicht gezeigt).
func follow(_block: ChallengeBlock, _finish_at: float) -> bool:
	return false


## Jeder Anzeigeschritt, in dem die laufende Herausforderung (oder keine) von einem anderen Typ ist.
func idle() -> void:
	pass


## Die Herausforderung `block` dieses Typs ist zu Ende (`block.state`) – abziehen, öffnen o. Ä.
func end(_block: ChallengeBlock) -> void:
	pass


## Steht die Darstellung gerade im Bild und ersetzt damit das durchfahrene Zieltor?
func covers_finish_gate() -> bool:
	return false


## Neue Fahrt: alles zurück auf Anfang, unsichtbar.
func clear() -> void:
	pass


## Im Menü / ohne Arcade-Lauf: ausblenden.
func hide() -> void:
	pass
