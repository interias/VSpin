## Ausrüstungssymbole (#83) im Ausrüstungsmenü: jeder Platz des Charakterblatts zeigt das Symbol des angelegten Teils in der
## Farbe der Seltenheit oder die graue Silhouette, jede Zeile der Inventarliste das Symbol ihres Teils, das Detail das
## gewählte Teil und der Vergleich das angelegte Teil des Platzes; nach Anlegen und Verwerten stimmen sie. Die Symbole liegen
## in den Fenstergrößen 960×1040, 1920×1080 und 1152×648 innerhalb ihrer Knöpfe bzw. Bereiche (mit vollem und leerem
## Stand), und ein Inventar mit 50 Teilen öffnet mit 50 Symbolen, deren Bilder über mehrere Bilder entstehen.
## Headless gibt es keine Pixel: geprüft werden Inhalt, Rahmenfarbe, Textur-Objekte und Rechtecke.
extends GutTest

const GEAR_MENU := preload("res://scenes/gear_menu.gd")


func after_each() -> void:
	ItemIcons.clear_cache()
	ItemIcons.glow_enabled = true


func _item(slot: String, rarity: String, stats: Dictionary, effect: String = "") -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


## Stand: angelegt Helm (magisch), Trikot (selten) und Rahmen (legendär); im Inventar dazu zwei Helme und Schuhe.
func _save_with_gear() -> Dictionary:
	var save := SaveGame.new()
	var data := {"save": save}
	data["helm"] = Inventory.add(save, _item("helm", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 6}))
	data["trikot"] = Inventory.add(save, _item("trikot", Loot.RARE, {"points_pct": 15, "progress_pct": 10, "luck_pct": 8}))
	data["rahmen"] = Inventory.add(save, _item("rahmen", Loot.LEGENDARY, {"progress_pct": 12, "points_pct": 9},
			Loot.EFFECTS.keys()[0]))
	for key in ["helm", "trikot", "rahmen"]:
		Inventory.equip(save, data[key]["id"])
	data["spare"] = Inventory.add(save, _item("helm", Loot.COMMON, {"zone_width_rpm": 1}))
	data["better"] = Inventory.add(save, _item("helm", Loot.RARE, {"zone_width_rpm": 5, "points_pct": 4, "luck_pct": 9}))
	data["shoes"] = Inventory.add(save, _item("schuhe", Loot.MAGIC, {"progress_pct": 4}))
	return data


func _gear_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var gear: CanvasLayer = GEAR_MENU.new()
	viewport.add_child(gear)
	gear.open(save)
	await wait_process_frames(4)
	return gear


func _full_save() -> SaveGame:
	var save := SaveGame.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(30):
		Inventory.add(save, Loot.roll(rng, 3.0))
	for slot in Loot.SLOTS:
		var best := Inventory.items(save).filter(func(item): return item["slot"] == slot)
		if not best.is_empty():
			Inventory.equip(save, int(best[-1]["id"]))
	return save


## Zeigt `icon` genau das Teil `item` (gleicher Inhalt, Bild und Rahmenfarbe der Seltenheit)?
func _assert_shows(icon: ItemIconView, item: Dictionary, label: String) -> void:
	assert_not_null(icon, "%s: Symbol vorhanden" % label)
	if icon == null:
		return
	assert_false(icon.is_empty(), "%s: nicht leer" % label)
	assert_eq(ItemIcons.key_of(icon.item), ItemIcons.key_of(item), "%s: zeigt das Teil" % label)
	assert_eq(icon.texture(), ItemIcons.texture_for(item), "%s: sein Bild" % label)
	assert_eq(icon.frame_color(), Loot.color_of(item["rarity"]), "%s: Rahmen in der Seltenheitsfarbe" % label)


func _assert_empty(icon: ItemIconView, slot: String, label: String) -> void:
	assert_not_null(icon, "%s: Symbol vorhanden" % label)
	if icon == null:
		return
	assert_true(icon.is_empty(), "%s: leer" % label)
	assert_eq(icon.slot, slot, "%s: Platz" % label)
	assert_eq(icon.texture(), ItemIcons.silhouette_for(slot), "%s: Silhouette" % label)
	assert_eq(icon.frame_color(), ItemIconView.EMPTY_BORDER, "%s: grauer Rahmen" % label)


func test_every_slot_shows_worn_part_or_silhouette() -> void:
	var data := _save_with_gear()
	var gear := await _gear_in(Vector2i(1920, 1080), data["save"])
	_assert_shows(gear.icon_of("slot_helm"), data["helm"], "Helm")
	_assert_shows(gear.icon_of("slot_trikot"), data["trikot"], "Trikot")
	_assert_shows(gear.icon_of("slot_rahmen"), data["rahmen"], "Rahmen")
	for slot in ["laufraeder", "schuhe", "talisman"]:
		_assert_empty(gear.icon_of("slot_" + slot), slot, "leerer Platz " + slot)
	for slot in Loot.SLOTS:
		assert_eq(gear.icon_of("slot_" + slot).icon_size, GEAR_MENU.SLOT_ICON, "%s: Größe" % slot)
		assert_eq(gear.icon_of("slot_" + slot).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: Klick geht an den Knopf" % slot)


func test_empty_state_shows_six_silhouettes_and_no_detail() -> void:
	var gear := await _gear_in(Vector2i(1920, 1080), SaveGame.new())
	for slot in Loot.SLOTS:
		_assert_empty(gear.icon_of("slot_" + slot), slot, "leer " + slot)
	assert_false(gear.detail_icon().visible, "kein Teil gewählt: kein großes Symbol")
	assert_false(gear.compare_icon().visible, "… und kein Vergleich")
	assert_eq(gear.find_child("List", true, false).find_children("*", "ItemIconView", true, false).size(), 0, "keine Zeilen")


func test_legendary_slot_glows_and_the_switch_turns_it_off() -> void:
	var data := _save_with_gear()
	var gear := await _gear_in(Vector2i(1920, 1080), data["save"])
	assert_true(gear.icon_of("slot_rahmen").is_glowing(), "legendäres Teil leuchtet")
	assert_false(gear.icon_of("slot_helm").is_glowing(), "magisches nicht")
	assert_false(gear.icon_of("slot_schuhe").is_glowing(), "leerer Platz nicht")
	ItemIcons.glow_enabled = false
	await wait_process_frames(2)
	assert_false(gear.icon_of("slot_rahmen").is_glowing(), "Schalter aus: kein Leuchten")


func test_every_list_row_shows_its_part() -> void:
	var data := _save_with_gear()
	var save: SaveGame = data["save"]
	var gear := await _gear_in(Vector2i(1920, 1080), save)
	var items := Inventory.items(save)
	assert_eq(items.size(), 6)
	for item in items:
		var key := "item_%d" % int(item["id"])
		_assert_shows(gear.icon_of(key), item, key)
		assert_eq(gear.icon_of(key).icon_size, GEAR_MENU.ROW_ICON, "%s: Größe" % key)
	assert_eq(gear.find_child("List", true, false).find_children("*", "ItemIconView", true, false).size(), items.size(),
			"ein Symbol je Zeile")
	# Mit gewähltem Platz nur die Zeilen des Platzes – mit ihren Symbolen.
	gear.select_slot("helm")
	await wait_process_frames(2)
	var rows := gear.find_child("List", true, false).find_children("*", "ItemIconView", true, false)
	assert_eq(rows.size(), 3, "drei Helme")
	for icon in rows:
		assert_eq(icon.slot, "helm")


func test_detail_and_compare_show_selected_and_worn_part() -> void:
	var data := _save_with_gear()
	var gear := await _gear_in(Vector2i(1920, 1080), data["save"])
	gear.select(int(data["better"]["id"]))
	await wait_process_frames(2)
	assert_true(gear.detail_icon().visible)
	_assert_shows(gear.detail_icon(), data["better"], "Detail: gewählter Helm")
	assert_eq(gear.detail_icon().icon_size, GEAR_MENU.DETAIL_ICON)
	assert_true(gear.compare_icon().visible)
	_assert_shows(gear.compare_icon(), data["helm"], "Vergleich: angelegter Helm")
	assert_eq(gear.compare_icon().icon_size, GEAR_MENU.COMPARE_ICON)
	assert_lt(gear.compare_icon().icon_size, gear.detail_icon().icon_size, "angelegtes Teil kleiner")
	assert_eq(gear.comparison_lines()[0], "Angelegt: Magischer Helm", "Vergleichszeilen bleiben")
	# Platz ohne angelegtes Teil: die Silhouette steht für „nichts“.
	gear.select(int(data["shoes"]["id"]))
	_assert_shows(gear.detail_icon(), data["shoes"], "Detail: Schuhe")
	assert_true(gear.compare_icon().visible)
	_assert_empty(gear.compare_icon(), "schuhe", "Vergleich: kein Schuh angelegt")
	# Das angelegte Teil selbst: oben groß, kein zweites Symbol im Vergleich.
	gear.select(int(data["helm"]["id"]))
	_assert_shows(gear.detail_icon(), data["helm"], "Detail: angelegter Helm")
	assert_false(gear.compare_icon().visible, "angelegt: nichts zu vergleichen")


func test_icons_follow_equip_and_salvage() -> void:
	var data := _save_with_gear()
	var save: SaveGame = data["save"]
	var gear := await _gear_in(Vector2i(1920, 1080), save)
	gear.select(int(data["better"]["id"]))
	gear.equip_selected()
	await wait_process_frames(2)
	_assert_shows(gear.icon_of("slot_helm"), data["better"], "Platz nach Anlegen")
	assert_false(gear.compare_icon().visible, "das neue Teil ist angelegt")
	_assert_shows(gear.detail_icon(), data["better"], "Detail nach Anlegen")
	_assert_shows(gear.icon_of("item_%d" % int(data["helm"]["id"])), data["helm"], "altes Teil bleibt in der Liste")
	# Verwerten: die Zeile samt Symbol verschwindet, das nächste Teil steht im Detail.
	var rows_before := gear.find_child("List", true, false).find_children("*", "ItemIconView", true, false).size()
	gear.select(int(data["spare"]["id"]))
	gear.salvage_selected()
	await wait_process_frames(2)
	assert_null(gear.icon_of("item_%d" % int(data["spare"]["id"])), "verwertetes Teil ohne Zeile")
	assert_eq(gear.find_child("List", true, false).find_children("*", "ItemIconView", true, false).size(), rows_before - 1)
	var shown: Dictionary = Inventory.find(save, gear.selected_id)
	_assert_shows(gear.detail_icon(), shown, "Detail nach Verwerten")
	# Alles Angelegte wieder gleich: die Plätze zeigen weiter ihre Teile.
	_assert_shows(gear.icon_of("slot_trikot"), data["trikot"], "Trikot unverändert")
	_assert_empty(gear.icon_of("slot_schuhe"), "schuhe", "Schuhe weiter leer")


func test_rows_keep_button_behaviour() -> void:
	var data := _save_with_gear()
	var gear := await _gear_in(Vector2i(1920, 1080), data["save"])
	var button: Button = gear.buttons["item_%d" % int(data["better"]["id"])]
	assert_true(button.toggle_mode)
	assert_eq(button.focus_mode, Control.FOCUS_ALL, "Fokus am Knopf")
	assert_string_contains(button.text, "Seltener Helm", "Text bleibt am Knopf")
	assert_eq(gear.buttons["slot_helm"].focus_mode, Control.FOCUS_ALL)
	assert_string_contains(gear.buttons["slot_helm"].text, "Magischer Helm")


## Kleinster Innenrand des Knopfes auf der Seite `side` über alle Zustände: der Text beginnt erst dahinter.
func _text_margin(button: Button, side: Side) -> float:
	var least := INF
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		least = minf(least, button.get_theme_stylebox(state).get_margin(side))
	return least


## Symbole liegen in ihren Knöpfen bzw. Bereichen, überdecken sich nicht und lassen den Text der Knöpfe frei.
func _assert_icons_inside(gear: CanvasLayer, label: String) -> void:
	var seen: Array = []
	for slot in Loot.SLOTS:
		var button: Button = gear.buttons["slot_" + slot]
		var icon: ItemIconView = gear.icon_of("slot_" + slot)
		var rect := icon.get_global_rect()
		assert_true(button.get_global_rect().grow(0.5).encloses(rect), "%s: %s: Symbol im Knopf (%s in %s)" % [
				label, slot, rect, button.get_global_rect()])
		assert_almost_eq(rect.size.x, GEAR_MENU.SLOT_ICON, 1.0, "%s: %s: Symbolgröße" % [label, slot])
		assert_false(seen.any(func(r): return r.intersects(rect)), "%s: %s: Symbole überdecken sich nicht" % [label, slot])
		assert_gte(_text_margin(button, SIDE_TOP) + 0.5, rect.end.y - button.get_global_rect().position.y,
				"%s: %s: der Text beginnt unter dem Symbol" % [label, slot])
		seen.append(rect)
	var previous := Rect2()
	for key in gear.buttons.keys().filter(func(k): return k.begins_with("item_")):
		var row: Button = gear.buttons[key]
		var rect: Rect2 = gear.icon_of(key).get_global_rect()
		assert_true(row.get_global_rect().grow(0.5).encloses(rect), "%s: %s: Symbol in der Zeile (%s in %s)" % [
				label, key, rect, row.get_global_rect()])
		assert_gte(_text_margin(row, SIDE_LEFT) + 0.5, rect.end.x - row.get_global_rect().position.x,
				"%s: %s: der Text beginnt rechts vom Symbol" % [label, key])
		assert_false(previous.intersects(rect), "%s: %s: Zeilensymbole überdecken sich nicht" % [label, key])
		previous = rect
	var detail: Rect2 = gear.find_child("DetailContent", true, false).get_global_rect()
	var big: Rect2 = gear.detail_icon().get_global_rect()
	if gear.detail_icon().visible:
		assert_true(detail.grow(0.5).encloses(big), "%s: großes Symbol im Detail (%s in %s)" % [label, big, detail])
		assert_almost_eq(big.size.x, GEAR_MENU.DETAIL_ICON, 1.0)
		var small: Rect2 = gear.compare_icon().get_global_rect()
		if gear.compare_icon().visible:
			assert_true(detail.grow(0.5).encloses(small), "%s: Vergleichssymbol im Detail" % label)
			assert_false(big.intersects(small), "%s: Detail- und Vergleichssymbol überdecken sich nicht" % label)
		var name_rect: Rect2 = gear.find_child("Name", true, false).get_global_rect()
		assert_false(big.intersects(name_rect), "%s: Symbol überdeckt den Namen nicht" % label)
		var stats_rect: Rect2 = gear.find_child("Stats", true, false).get_global_rect()
		assert_false(big.intersects(stats_rect), "%s: … und nicht die Werte" % label)
		for line in gear.find_child("Compare", true, false).get_children():
			assert_false(small.intersects(line.get_global_rect()) and gear.compare_icon().visible,
					"%s: Vergleichssymbol überdeckt keine Zeile" % label)


func _layout_save() -> SaveGame:
	var save := _full_save()
	# Ein legendäres Teil angelegt (Leuchten) und ein Platz leer.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var legendary := Loot.roll(rng, 3.0)
	legendary["rarity"] = Loot.LEGENDARY
	legendary["effect"] = Loot.EFFECTS.keys()[0]
	legendary["slot"] = "helm"
	Inventory.equip(save, int(Inventory.add(save, legendary)["id"]))
	return save


func test_icons_fit_in_half_screen_window() -> void:
	_assert_icons_inside(await _gear_in(Vector2i(960, 1040), _layout_save()), "960×1040")
	_assert_icons_inside(await _gear_in(Vector2i(960, 1040), SaveGame.new()), "960×1040 ohne Beute")


func test_icons_fit_in_full_screen_sizes() -> void:
	_assert_icons_inside(await _gear_in(Vector2i(1920, 1080), _layout_save()), "1920×1080")
	_assert_icons_inside(await _gear_in(Vector2i(1152, 648), _layout_save()), "1152×648")
	_assert_icons_inside(await _gear_in(Vector2i(1152, 648), SaveGame.new()), "1152×648 ohne Beute")


## Das Leuchten (Schatten außerhalb des Rechtecks) der Symbole im Detail wird vom Scrollbereich nicht abgeschnitten.
func test_glow_of_detail_icons_is_not_clipped() -> void:
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var data := _save_with_gear()  # angelegt: ein legendärer Rahmen
		var legendary: Dictionary = Inventory.add(data["save"], _item("rahmen", Loot.LEGENDARY, {"progress_pct": 20},
				Loot.EFFECTS.keys()[0]))
		var gear := await _gear_in(size, data["save"])
		gear.select(int(legendary["id"]))
		await wait_process_frames(2)
		var clip: Rect2 = gear.find_child("DetailScroll", true, false).get_global_rect()
		for icon in [gear.detail_icon(), gear.compare_icon()]:
			assert_true(icon.is_glowing(), "%s: leuchtet" % icon.name)
			var rect: Rect2 = icon.get_global_rect().grow(maxi(4, roundi(icon.icon_size / 12.0)))
			assert_gte(rect.position.x, clip.position.x, "%s %s: Leuchten links nicht abgeschnitten" % [size, icon.name])
			assert_lte(rect.end.x, clip.end.x, "%s %s: … rechts" % [size, icon.name])
		var top: float = gear.detail_icon().get_global_rect().position.y - maxi(4, roundi(GEAR_MENU.DETAIL_ICON / 12.0))
		assert_gte(top, clip.position.y, "%s: Leuchten des großen Symbols oben nicht abgeschnitten" % size)


func test_inventory_of_50_opens_with_50_icons_built_over_several_frames() -> void:
	var save := SaveGame.new()
	var rarities := Loot.RARITIES.keys()
	var slots := Loot.SLOTS.keys()
	for i in range(50):  # verschiedener Inhalt: 50 verschiedene Bilder
		Inventory.add(save, _item(slots[i % slots.size()], rarities[i % rarities.size()], {"points_pct": i + 1},
				Loot.EFFECTS.keys()[0] if rarities[i % rarities.size()] == Loot.LEGENDARY else ""))
	assert_eq(Inventory.items(save).size(), 50)
	ItemIcons.clear_cache()
	var built_before := ItemIcons.built
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var gear: CanvasLayer = GEAR_MENU.new()
	viewport.add_child(gear)
	gear.open(save)
	var list := gear.find_child("List", true, false)
	assert_eq(list.find_children("*", "ItemIconView", true, false).size(), 50, "50 Symbole in der Liste, sofort")
	assert_eq(ItemIcons.built - built_before, ItemIcons.cache_size(), "jedes Bild entsteht einmal")
	assert_gt(ItemIcons.pending(), 0, "die Modelle warten noch auf ihre Bilder")
	assert_gte(ItemIcons.cache_size(), 50, "50 verschiedene Bilder (plus Silhouetten, Detail)")
	var frames := 0
	var start := Engine.get_process_frames()
	while ItemIcons.pending() > 0 and Engine.get_process_frames() - start < 120:
		await wait_process_frames(1)
		frames += 1
	assert_eq(ItemIcons.pending(), 0, "nach wenigen Bildern alle gebaut")
	assert_gt(frames, 1, "auf mehrere Bilder verteilt, nicht in einem (%d Bilder)" % frames)
	assert_lte(frames, 120)
	var built := ItemIcons.built - built_before
	assert_gte(built, 50)
	# Neuaufbau der Liste (Platz wählen, wieder alle): die Bilder kommen aus dem Cache, nichts wird neu gebaut.
	gear.select_slot("helm")
	gear.select_slot("helm")
	await wait_process_frames(2)
	assert_eq(list.find_children("*", "ItemIconView", true, false).size(), 50, "wieder alle 50")
	assert_eq(ItemIcons.built - built_before, built, "kein Bild neu erzeugt")
	assert_eq(ItemIcons.pending(), 0)
