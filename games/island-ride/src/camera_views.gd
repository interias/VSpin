## Kameraperspektiven (#59): drei voreingestellte Lagen der Folgekamera hinter dem Fahrer – Nah, Verfolger (Standard)
## und Weit –, durchzublättern mit `C` während der Fahrt und im Einstellungsmenü. Die Wahl steht im Spielstand
## (SaveGame, Bereich `camera`) und gilt in Rundfahrt und Training, in beiden Richtungen. Nur Darstellung (ADR-0010).
##
## Die Werte sind Daten (VIEWS). „Weit“ ist die Kamera von vorher und kommt aus `config.cfg [camera]` (RideConfig,
## `behind_m`, `height_m`) – eine bestehende Konfiguration wirkt dort weiter. Blickpunkt voraus und seine Höhe
## (`[camera] look_ahead_m`, `look_height_m`) gelten für alle drei.
class_name CameraViews
extends RefCounted

const NEAR := "nah"
const CHASE := "verfolger"
const WIDE := "weit"
## Reihenfolge beim Durchblättern.
const IDS := [NEAR, CHASE, WIDE]
const DEFAULT := CHASE
const NAMES := {NEAR: "Nah", CHASE: "Verfolger", WIDE: "Weit"}
## Abstand hinter dem Fahrer entlang der Strecke und Höhe über der Strecke (m); WIDE aus der Konfiguration.
const VIEWS := {
	NEAR: {"behind_m": 3.5, "height_m": 1.8},
	CHASE: {"behind_m": 4.5, "height_m": 2.1},
}


## `id`, wenn es eine Perspektive ist, sonst DEFAULT.
static func valid(id) -> String:
	return id if id is String and id in IDS else DEFAULT


## Nächste Perspektive beim Durchblättern (nach Weit wieder Nah).
static func next(id: String) -> String:
	return IDS[(IDS.find(valid(id)) + 1) % IDS.size()]


## Lage der Folgekamera für Perspektive `id`: {behind_m, height_m, look_ahead_m, look_height_m} (m).
static func values(id: String, config: RideConfig) -> Dictionary:
	var view: Dictionary = VIEWS.get(valid(id), {"behind_m": config.camera_behind_m, "height_m": config.camera_height_m})
	return {"behind_m": view["behind_m"], "height_m": view["height_m"], "look_ahead_m": config.camera_look_ahead_m,
			"look_height_m": config.camera_look_height_m}


## Gewählte Perspektive aus dem Spielstand (fehlt sie oder ist ungültig: DEFAULT).
static func selection(save: SaveGame) -> String:
	return valid(save.camera().get("view"))


## Perspektive `id` in den Spielstand eintragen (schreibt nicht auf die Platte).
static func choose(save: SaveGame, id: String) -> void:
	save.camera()["view"] = valid(id)
