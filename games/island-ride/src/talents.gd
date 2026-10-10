## Talentbaum des Arcade-Modus (#53, Spec #27 Story 21; CONTEXT.md „Fähigkeit“): 15 Knoten in drei Ästen – **Sprinter**
## (Antritt, Windböe, Durchbruch), **Kletterer** (Fortschritt, Schild) und **Ausdauer** (Gleichmaß/Fokus, Zonenbreite,
## Beute-Glück, Kombo). Punkte kommen aus dem Arcade-Level (ArcadeLevel: ein Talentpunkt je Level ab 2), ein Knoten kostet
## einen Punkt, innerhalb eines Astes braucht jeder Knoten seinen Vorgänger (`requires`). Das Zurücksetzen ist **kostenlos**
## und gibt alle Punkte zurück: Der Baum soll zum Ausprobieren von Builds einladen, kein Handwerk und keine Währung (Out of
## Scope der Spec). Reine Logik über dem Spielstand (Bereich `arcade`, additiv, Formatversion bleibt 1):
##
##   arcade.talents   [Knoten-Id, …] in der Reihenfolge des Erlernens
##
## Ein Knoten verändert **Fähigkeiten** (Wirkung, Dauer, Abklingzeit), die **Schwellen der Kadenzmuster** oder die
## Ausrüstungswerte des Laufs (`run.gear`) – Daten in `changes`, Anwendung in BuildEffects, aufgerufen im `run_hook` der
## Arcade-Bühne (TalentArcade): Talente wirken nur im Arcade-Lauf (ADR-0010) und ersetzen nie das Treten.
## Der Stand von der Platte ist ungeprüft: unbekannte Knoten, doppelte, solche ohne erlernten Vorgänger und alles über den
## verfügbaren Punkten zählt nicht (`learned`).
## Für die Empfohlene Stärke (#54): `gear_bonus` liefert die Ausrüstungswerte der Talente im Format von `Loot.modifiers`.
class_name Talents
extends RefCounted

## Äste in Reihenfolge der Anzeige.
const BRANCHES := {
	"sprinter": {"name": "Sprinter", "text": "Antritt, Windböe, Durchbruch"},
	"kletterer": {"name": "Kletterer", "text": "Fortschritt und Schild"},
	"ausdauer": {"name": "Ausdauer", "text": "Gleichmaß, Zonenbreite, Beute, Kombo"},
}
## Knoten in Reihenfolge der Anzeige (Vorgänger stehen vor ihren Nachfolgern): `branch`, `name`, `text`, `requires`
## ("" = Wurzel des Astes), `cost`, `changes` (BuildEffects).
const NODES := {
	"sprinter_antritt": {"branch": "sprinter", "name": "Kräftiger Antritt", "requires": "", "cost": 1,
		"text": "Windböe stärker: Fortschritt in der Zone ×3,5 statt ×3",
		"changes": [{"ability": "windboe", "key": "power", "add": 0.5}]},
	"sprinter_atem": {"branch": "sprinter", "name": "Kurze Pause", "requires": "sprinter_antritt", "cost": 1,
		"text": "Windböe lädt 4 s schneller",
		"changes": [{"ability": "windboe", "key": "cooldown_s", "add": -4.0}]},
	"sprinter_reflex": {"branch": "sprinter", "name": "Wacher Antritt", "requires": "sprinter_antritt", "cost": 1,
		"text": "Antritt schon bei +20 statt +25 rpm erkannt",
		"changes": [{"pattern": "antritt_rise_rpm", "add": -5.0}]},
	"sprinter_spurt": {"branch": "sprinter", "name": "Langer Spurt", "requires": "sprinter_atem", "cost": 1,
		"text": "Windböe wirkt 1 s länger",
		"changes": [{"ability": "windboe", "key": "duration_s", "add": 1.0}]},
	"sprinter_druck": {"branch": "sprinter", "name": "Durchbruchskraft", "requires": "sprinter_reflex", "cost": 1,
		"text": "+6 % Fortschritt in der Zone",
		"changes": [{"gear": "progress_pct", "add": 6}]},
	"kletterer_zaeh": {"branch": "kletterer", "name": "Zäher Kletterer", "requires": "", "cost": 1,
		"text": "+4 % Fortschritt in der Zone",
		"changes": [{"gear": "progress_pct", "add": 4}]},
	"kletterer_atem": {"branch": "kletterer", "name": "Tiefes Durchatmen", "requires": "kletterer_zaeh", "cost": 1,
		"text": "Schild hält 2 s länger",
		"changes": [{"ability": "schild", "key": "duration_s", "add": 2.0}]},
	"kletterer_ruhe": {"branch": "kletterer", "name": "Ruhiger Puls", "requires": "kletterer_zaeh", "cost": 1,
		"text": "Innehalten schon nach 1,5 statt 2 s erkannt",
		"changes": [{"pattern": "pause_hold_s", "add": -0.5}]},
	"kletterer_rast": {"branch": "kletterer", "name": "Kurze Rast", "requires": "kletterer_atem", "cost": 1,
		"text": "Schild lädt 6 s schneller",
		"changes": [{"ability": "schild", "key": "cooldown_s", "add": -6.0}]},
	"kletterer_gipfel": {"branch": "kletterer", "name": "Gipfelsammler", "requires": "kletterer_ruhe", "cost": 1,
		"text": "+8 % Punkte",
		"changes": [{"gear": "points_pct", "add": 8}]},
	"ausdauer_gleichmass": {"branch": "ausdauer", "name": "Gleichmäßiger Tritt", "requires": "", "cost": 1,
		"text": "Gleichmaß nach 8 statt 10 s erkannt",
		"changes": [{"pattern": "steady_hold_s", "add": -2.0}]},
	"ausdauer_fokus": {"branch": "ausdauer", "name": "Tiefer Fokus", "requires": "ausdauer_gleichmass", "cost": 1,
		"text": "Fokus stärker: Fortschritt in der Zone ×1,75 statt ×1,5",
		"changes": [{"ability": "fokus", "key": "power", "add": 0.25}]},
	"ausdauer_breit": {"branch": "ausdauer", "name": "Breiter Tritt", "requires": "ausdauer_gleichmass", "cost": 1,
		"text": "+2 rpm Zonenbreite",
		"changes": [{"gear": "zone_width_rpm", "add": 2}]},
	"ausdauer_takt": {"branch": "ausdauer", "name": "Taktgefühl", "requires": "ausdauer_fokus", "cost": 1,
		"text": "Kombo gibt 15 Punkte mehr",
		"changes": [{"ability": "kombo", "key": "power", "add": 15.0}]},
	"ausdauer_glueck": {"branch": "ausdauer", "name": "Glückspilz", "requires": "ausdauer_breit", "cost": 1,
		"text": "+10 % Beute-Glück",
		"changes": [{"gear": "luck_pct", "add": 10}]},
}


## Erlernte Knoten (nur gültige, in der Reihenfolge des Erlernens).
static func learned(save: SaveGame) -> Array:
	var result := []
	var stored = save.arcade().get("talents")
	if not (stored is Array):
		return result
	var budget := ArcadeLevel.talent_points_for(ArcadeLevel.level(save))
	var used := 0
	for id in stored:
		if not (id is String) or not NODES.has(id) or result.has(id):
			continue
		var node: Dictionary = NODES[id]
		if (node["requires"] != "" and not result.has(node["requires"])) or used + int(node["cost"]) > budget:
			continue
		result.append(id)
		used += int(node["cost"])
	return result


## Ist der Knoten `id` erlernt?
static func is_learned(save: SaveGame, id: String) -> bool:
	return learned(save).has(id)


## Ausgegebene Talentpunkte.
static func spent(save: SaveGame) -> int:
	var total := 0
	for id in learned(save):
		total += int(NODES[id]["cost"])
	return total


## Freie Talentpunkte (Punkte des Arcade-Levels minus ausgegebene).
static func available(save: SaveGame) -> int:
	return ArcadeLevel.talent_points_for(ArcadeLevel.level(save)) - spent(save)


## Warum `id` nicht erlernt werden kann: "" = kann erlernt werden, sonst "unknown", "learned", "requires" (Vorgänger fehlt)
## oder "points" (zu wenig freie Talentpunkte).
static func blocked_by(save: SaveGame, id: String) -> String:
	if not NODES.has(id):
		return "unknown"
	var have := learned(save)
	if have.has(id):
		return "learned"
	if NODES[id]["requires"] != "" and not have.has(NODES[id]["requires"]):
		return "requires"
	return "points" if available(save) < int(NODES[id]["cost"]) else ""


static func can_learn(save: SaveGame, id: String) -> bool:
	return blocked_by(save, id) == ""


## Lernt den Knoten `id`; gibt zurück, ob er erlernt wurde. Schreibt nicht auf die Platte.
static func learn(save: SaveGame, id: String) -> bool:
	if not can_learn(save, id):
		return false
	var arcade := save.arcade()
	arcade["talents"] = learned(save) + [id]  # räumt dabei Ungültiges aus dem Stand
	return true


## Setzt alle Talente zurück (kostenlos); liefert die zurückgegebenen Punkte. Schreibt nicht auf die Platte.
static func reset(save: SaveGame) -> int:
	var refunded := spent(save)
	save.arcade()["talents"] = []
	return refunded


## Alle Änderungen der erlernten Talente (BuildEffects) in der Reihenfolge des Erlernens.
static func changes(save: SaveGame) -> Array:
	var result := []
	for id in learned(save):
		result.append_array(NODES[id]["changes"])
	return result


## Ausrüstungswerte der erlernten Talente (jeder Wert aus Loot.STATS, 0 = keiner), ungedeckelt – wie `Loot.modifiers`
## für die Empfohlene Stärke (#54).
static func gear_bonus(save: SaveGame) -> Dictionary:
	var result := {}
	for stat in Loot.STATS:
		result[stat] = 0
	for change in changes(save):
		if change.has("gear") and result.has(change["gear"]):
			result[change["gear"]] += int(change["add"])
	return result


## Knoten eines Astes in Reihenfolge der Anzeige.
static func nodes_of(branch: String) -> Array:
	return NODES.keys().filter(func(id): return NODES[id]["branch"] == branch)
