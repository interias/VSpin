## Registrierung der Bausteintypen des Arcade (#63): **eine Zeile je Typ** in `TYPES`. Die Reihenfolge der Zeilen ist
## die Reihenfolge von `Encounters.CHALLENGES`, also der Würfel-Pool – neue Typen immer **ans Ende**, ein Eintrag in der
## Mitte verschöbe die Würfe bestehender Einträge (auch ein neuer Typ am Ende ändert die Würfe eines Seeds, weil der
## Pool wächst; Tests, die Planung festnageln, nutzen eigene Pools).
##
## Neuen Bausteintyp anmelden (Takt-Tore/Sammeln #48, Boss-Phasen #51, …) – nur eigene Dateien plus diese Zeile:
##  1. Baustein: `src/<name>.gd`, `extends ChallengeBlock` (Konstruktor nie direkt im Produktivcode, nur über `build`).
##  2. Daten + Bauanleitung: `src/challenges/<name>_challenges.gd` (`extends RefCounted`) mit
##       const ID := "<name>"                       # der Wert von `block` in den Herausforderungen
##       const CHALLENGES := [ {"id", "block": ID, "name", "points", …Parameter}, … ]
##       static func build(definition: Dictionary, level: Dictionary, zone: Vector2) -> ChallengeBlock
##     `level` = ArcadeTiers.level(tier, lap_index, boss) (Stufe mit Rundensteigerung, #54); `zone` =
##     `Encounters.zone_for(...)`, also schon durch den Wächter (CadenceRange.limit_zone) gelaufen und mit Ausrüstung.
##     Braucht der Typ eine andere Zielgeometrie, entsteht sie in `Encounters.zone_for` – vor `limit_zone`.
##     `progress_factor` setzt `Encounters.build` danach für alle Typen.
##  3. Diese Liste: `"<name>": preload("res://src/challenges/<name>_challenges.gd"),` (Schlüssel = `ID` des Typs).
## Sollen Einträge des Typs **nicht** gewürfelt werden (feste Gegner, Bosse #51): `CHALLENGES` des Typs leer lassen und die
## Einträge in einer eigenen Konstante führen – `Encounters.build` baut jede Definition nach ihrem `block`, ohne Pool.
## So die Bosse (#51, `src/challenges/boss_challenges.gd`): `CHALLENGES` leer, die Bosse in `FIXED` mit ihrem Abschnitt –
## `ArcadeRun` plant jede Konstante `FIXED` eines Typs je Runde an ihrem festen Ort ein (nicht im Würfel-Pool).
## Die Darstellung (Requisiten) hängt sich getrennt ein: `ArcadeStage.PROPS`; Hooks, Signale: `ArcadeStage.EXTENSIONS`.
class_name EncounterRegistry
extends RefCounted

const TYPES := {
	"zone_hold": preload("res://src/challenges/zone_hold_challenges.gd"),
	"breakthrough": preload("res://src/challenges/breakthrough_challenges.gd"),
	"chase": preload("res://src/challenges/chase_challenges.gd"),
	"rhythm_gates": preload("res://src/challenges/rhythm_gates_challenges.gd"),
	"collect": preload("res://src/challenges/collect_challenges.gd"),
	"boss": preload("res://src/challenges/boss_challenges.gd"),
	"elite": preload("res://src/challenges/elite_challenges.gd"),
}


## Alle Herausforderungen in der Reihenfolge der Typen (= `Encounters.CHALLENGES`).
static func challenges() -> Array:
	var result := []
	for type in TYPES.values():
		result.append_array(type.CHALLENGES)
	return result


## Typ-Skript zum Baustein `block_id` (null = unbekannt).
static func type_of(block_id: Variant) -> GDScript:
	return TYPES.get(block_id)
