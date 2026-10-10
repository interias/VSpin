## Baustein-Typ der Elite-Gruppen (#52) – Eintrag in `EncounterRegistry.TYPES`. Elite-Gruppen werden **nicht** aus diesem
## Typ gewürfelt (`CHALLENGES` leer): `ArcadeRun` würfelt je gewürfelter Herausforderung mit eigenem Würfel, ob sie als
## Elite-Gruppe kommt (EliteGroups.roll), und baut dann ihre Definition (EliteGroups.make: `block` = ID, `phases` =
## Anführer und Gefolge). `Encounters.build` baut jede Phase wie jede Herausforderung (Wächter, Stufe, Ausrüstung) und
## gibt sie `build_phases`. Daten der Eigenschaften und Stufen: src/elite_groups.gd.
extends RefCounted

const ID := "elite"
const CHALLENGES := []


## Eine Elite-Gruppe braucht Phasen (`build_phases`); ohne Phasen kein Baustein.
static func build(definition: Dictionary, _level: Dictionary, _zone: Vector2) -> ChallengeBlock:
	push_warning("Elite-Gruppe %s ohne Phasen" % definition.get("id"))
	return null


## Elite-Gruppe aus den schon gebauten Phasen `phases` – null, wenn eine Phase einen unbekannten Baustein hat. Nur über
## `Encounters.build` aufrufen.
static func build_phases(definition: Dictionary, phases: Array) -> ChallengeBlock:
	if phases.is_empty() or phases.has(null):
		return null
	var elite: Dictionary = definition.get("elite", {})
	return EliteGroup.new(definition["id"], definition["name"], str(elite.get("rank", "")), elite.get("affixes", []),
			phases, definition["phases"])
