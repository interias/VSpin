## Stufen des Arcade-Modus (#46, Spec #27; CONTEXT.md „Stufe“): der gewählte Schwierigkeitsgrad als **Daten**. Eine
## Stufe bestimmt die Breite der Zielzonen, die Dauer der Herausforderungen und die Punkte. Hier gibt es drei, alle
## wählbar; Freischalten, Empfohlene Stärke und die Steigerung je Runde kommen mit #54 als weitere Felder dazu – die
## Herausforderungen lesen eine Stufe nur über `Encounters.build`, also bleiben auch spätere Stufen im Kadenzbereich.
## Gewählt wird im Startmenü; die Wahl steht im Spielstand (`arcade.tier`). Wirkt nur im Arcade-Modus (ADR-0010).
class_name ArcadeTiers
extends RefCounted

## Je Stufe: Nummer, Name, Beschreibung, Breite der Zielzone (rpm), Faktor auf die Dauern der Herausforderungen und auf
## ihre Punkte.
const LIST := [
	{"tier": 1, "name": "Stufe 1", "description": "Breite Zonen (20 rpm), kurze Herausforderungen",
		"zone_width_rpm": 20.0, "duration_factor": 1.0, "points_factor": 1.0},
	{"tier": 2, "name": "Stufe 2", "description": "Zonen 14 rpm, länger halten, doppelte Punkte",
		"zone_width_rpm": 14.0, "duration_factor": 1.25, "points_factor": 2.0},
	{"tier": 3, "name": "Stufe 3", "description": "Schmale Zonen (10 rpm), lange halten, dreifache Punkte",
		"zone_width_rpm": 10.0, "duration_factor": 1.5, "points_factor": 3.0},
]
const DEFAULT := 1


## Stufe `tier` (unbekannt → Stufe DEFAULT).
static func get_tier(tier: int) -> Dictionary:
	for entry in LIST:
		if entry["tier"] == tier:
			return entry
	return LIST[0]


## Gültige Stufennummer (unbekannt → DEFAULT).
static func valid(tier) -> int:
	return int(get_tier(int(tier) if tier is float or tier is int else DEFAULT)["tier"])


## Gewählte Stufe laut Spielstand (`arcade.tier`).
static func selection(save: SaveGame) -> int:
	return valid(save.arcade().get("tier", DEFAULT))


## Stufe in den Spielstand schreiben (nicht auf die Platte).
static func choose(save: SaveGame, tier: int) -> void:
	save.arcade()["tier"] = valid(tier)
