## Inventar des Arcade-Modus (#49): gefundene Beute (Loot), angelegte Teile je Platz und Splitter – reine Logik über dem
## Spielstand (Bereich `arcade`, additiv, Formatversion bleibt 1). Verwaltet wird nur im Menü (Ausrüstung): anlegen,
## vergleichen, Überzähliges zu Splittern verwerten; in der Fahrt wird nichts verwaltet. Kein Handwerk: Splitter werden
## nur gesammelt (Spec #27, Out of Scope).
##
##   arcade.inventory      [Teil, …] – jedes mit eigener `id` (vergibt `add` aus `arcade.next_item_id`)
##   arcade.equipped       {Platz: id} – höchstens ein Teil je Platz, nur Teile aus dem Inventar
##   arcade.shards         Splitter (ganze Zahl)
##
## Der Stand von der Platte ist ungeprüft: ungültige Teile (Loot.valid) und Verweise auf fehlende Teile zählen nicht.
## Die Werte der angelegten Teile wirken nur im Arcade-Modus (ADR-0010) – als `modifiers` für den Arcade-Lauf.
class_name Inventory
extends RefCounted


## Alle gültigen Teile des Inventars (älteste zuerst), wie gespeichert.
static func items(save: SaveGame) -> Array:
	var stored = save.arcade().get("inventory")
	return stored.filter(func(item): return Loot.valid(item) and _id(item) > 0) if stored is Array else []


## Legt `item` ins Inventar und gibt ihm eine neue `id`; liefert das gespeicherte Teil. Schreibt nicht auf die Platte.
static func add(save: SaveGame, item: Dictionary) -> Dictionary:
	var arcade := save.arcade()
	if not (arcade.get("inventory") is Array):
		arcade["inventory"] = []
	var next := maxi(_int(arcade.get("next_item_id")), 1)
	for existing in items(save):
		next = maxi(next, _id(existing) + 1)
	var stored := item.duplicate(true)
	stored["id"] = next
	arcade["next_item_id"] = next + 1
	arcade["inventory"].append(stored)
	return stored


## Teil mit `id` ({} = keins).
static func find(save: SaveGame, id: int) -> Dictionary:
	for item in items(save):
		if _id(item) == id:
			return item
	return {}


## Angelegte Teile: Platz → Teil (nur Plätze mit gültigem Teil aus dem Inventar, das zum Platz passt).
static func equipped(save: SaveGame) -> Dictionary:
	var result := {}
	var stored = save.arcade().get("equipped")
	if not (stored is Dictionary):
		return result
	for slot in Loot.SLOTS:
		var item := find(save, _int(stored.get(slot)))
		if not item.is_empty() and item["slot"] == slot:
			result[slot] = item
	return result


## Ist das Teil `id` angelegt?
static func is_equipped(save: SaveGame, id: int) -> bool:
	return equipped(save).values().any(func(item): return _id(item) == id)


## Legt das Teil `id` an seinem Platz an (das bisherige bleibt im Inventar). Gibt zurück, ob es angelegt wurde.
static func equip(save: SaveGame, id: int) -> bool:
	var item := find(save, id)
	if item.is_empty():
		return false
	var arcade := save.arcade()
	if not (arcade.get("equipped") is Dictionary):
		arcade["equipped"] = {}
	arcade["equipped"][item["slot"]] = id
	return true


## Verwertet das Teil `id` zu Splittern (nicht, wenn es angelegt ist). Liefert die gewonnenen Splitter (0 = nichts
## verwertet). Schreibt nicht auf die Platte.
static func salvage(save: SaveGame, id: int) -> int:
	var item := find(save, id)
	if item.is_empty() or is_equipped(save, id):
		return 0
	var arcade := save.arcade()
	arcade["inventory"] = arcade["inventory"].filter(func(entry): return not (entry is Dictionary and _id(entry) == id))
	var gained := Loot.shards_for(item)
	arcade["shards"] = shards(save) + gained
	return gained


## Gesammelte Splitter.
static func shards(save: SaveGame) -> int:
	return maxi(_int(save.arcade().get("shards")), 0)


## Modifikatoren der angelegten Ausrüstung (Loot.modifiers) für den Arcade-Lauf.
static func modifiers(save: SaveGame) -> Dictionary:
	return Loot.modifiers(equipped(save).values())


## Vergleich des Teils `id` mit dem angelegten Teil seines Platzes (Loot.compare; [] = Teil unbekannt).
static func compare(save: SaveGame, id: int) -> Array:
	var item := find(save, id)
	if item.is_empty():
		return []
	return Loot.compare(item, equipped(save).get(item["slot"], {}))


static func _id(item) -> int:
	return _int(item.get("id")) if item is Dictionary else 0


static func _int(value) -> int:
	return int(value) if value is float or value is int else 0
