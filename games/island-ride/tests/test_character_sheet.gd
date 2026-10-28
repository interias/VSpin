## Charakterblatt der Arcade-Ausrüstung (#68): sechs Plätze um den Fahrer, angelegtes Teil je Platz in der Farbe der
## Seltenheit oder „leer“, Anlegen und Tauschen über die Plätze mit Maus und Tastatur, Summe der Werte und Stärke gegen
## die empfohlene Stärke der gewählten Stufe, Layout im Halbbild-Fenster und im Vollbild überdeckungsfrei. Das Inventar
## (Liste, Vergleich, Verwerten) bleibt in tests/test_arcade_loot_ride.gd geprüft.
extends "res://tests/support/bus_test.gd"

const GEAR_MENU := preload("res://scenes/gear_menu.gd")
var SAVE_PATH := TestIsolation.path("test_character_sheet_savegame.json")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _item(slot: String, rarity: String, stats: Dictionary) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": ""}


## Stand mit angelegtem magischem Helm (+3 rpm) und seltenem Trikot, dazu zwei weiteren Helmen im Inventar.
func _save_with_helmets() -> Dictionary:
	var save := SaveGame.new()
	var worn := Inventory.add(save, _item("helm", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 6}))
	Inventory.equip(save, worn["id"])
	var jersey := Inventory.add(save, _item("trikot", Loot.RARE, {"points_pct": 15, "progress_pct": 10, "luck_pct": 8}))
	Inventory.equip(save, jersey["id"])
	var spare := Inventory.add(save, _item("helm", Loot.COMMON, {"zone_width_rpm": 1}))
	var better := Inventory.add(save, _item("helm", Loot.RARE, {"zone_width_rpm": 5, "points_pct": 4, "luck_pct": 9}))
	return {"save": save, "worn": worn, "jersey": jersey, "spare": spare, "better": better}


func _gear_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var gear: CanvasLayer = GEAR_MENU.new()
	viewport.add_child(gear)
	gear.open(save)
	await wait_process_frames(4)
	return gear


func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	button.get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = at
		button.get_viewport().push_input(event, true)
		await get_tree().process_frame


func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _item_ids(gear: CanvasLayer) -> Array:
	return gear.buttons.keys().filter(func(k): return k.begins_with("item_")).map(func(k): return int(k.substr(5)))


func test_six_slots_show_worn_part_in_rarity_color_or_empty() -> void:
	var data := _save_with_helmets()
	var gear := await _gear_in(Vector2i(1920, 1080), data["save"])
	var slots := Loot.SLOTS.keys()
	assert_eq(slots.size(), 6, "sechs Plätze")
	for slot in slots:
		var button: Button = gear.buttons["slot_" + slot]
		assert_true(button.is_visible_in_tree(), "%s sichtbar" % slot)
		assert_true(button.text.begins_with(Loot.SLOTS[slot]["name"]), "%s trägt den Namen des Platzes" % slot)
	var helm: Button = gear.buttons["slot_helm"]
	assert_string_contains(helm.text, "Magischer Helm")
	assert_string_contains(helm.text, "+3 rpm Zonenbreite")
	assert_eq(helm.get_theme_color("font_color"), Loot.color_of(Loot.MAGIC), "Helm in der Farbe „magisch“")
	var jersey: Button = gear.buttons["slot_trikot"]
	assert_string_contains(jersey.text, "Seltenes Trikot")
	assert_eq(jersey.get_theme_color("font_color"), Loot.color_of(Loot.RARE), "Trikot in der Farbe „selten“")
	for slot in ["rahmen", "laufraeder", "schuhe", "talisman"]:
		assert_string_contains(gear.buttons["slot_" + slot].text, "leer")
		assert_ne(gear.buttons["slot_" + slot].get_theme_color("font_color"), Loot.color_of(Loot.MAGIC), "leer: neutral")
	assert_eq(gear.equipped_lines(), ["Rahmen: –", "Laufräder: –", "Trikot: Seltenes Trikot", "Helm: Magischer Helm",
			"Schuhe: –", "Talisman: –"])
	# Der Fahrer in der Mitte trägt Garderobe und angelegte Ausrüstung.
	assert_eq(gear.preview.material_color("helmet"), Loot.color_of(Loot.MAGIC), "Vorschau trägt den Helm")
	assert_eq(gear.preview.material_color("jersey"), Loot.color_of(Loot.RARE), "… und das Trikot")
	assert_false(gear.preview.talisman_visible(), "leerer Platz: kein Talisman")


func test_totals_and_strength_against_recommended_strength() -> void:
	var data := _save_with_helmets()
	var save: SaveGame = data["save"]
	var gear := await _gear_in(Vector2i(1920, 1080), save)
	assert_eq(gear.totals_text(), "Summe: +3 rpm Zonenbreite · +10 % Fortschritt in der Zone · +21 % Punkte · +8 % Beute-Glück")
	var own := ArcadeTiers.strength(save)
	assert_eq(own, 3 * 4 + 10, "Stärke wie ArcadeTiers.strength (Zone ×4 + Fortschritt)")
	assert_eq(gear.strength_text(), "Stärke 22 / empfohlen %d (Stufe %d)" % [
			ArcadeTiers.recommended_strength(ArcadeTiers.selection(save)), ArcadeTiers.selection(save)])
	ArcadeTiers.choose(save, 3)
	gear.open(save)
	assert_eq(gear.strength_text(), "Stärke 22 / empfohlen 20 (Stufe 3)", "reicht")
	assert_eq(gear._strength.get_theme_color("font_color"), GEAR_MENU.COLOR_OK)
	save.arcade()["unlocked"] = 5
	ArcadeTiers.choose(save, 5)
	gear.open(save)
	assert_eq(gear.strength_text(), "Stärke 22 / empfohlen 50 (Stufe 5)", "reicht nicht – eine Empfehlung, keine Sperre")
	assert_eq(gear._strength.get_theme_color("font_color"), GEAR_MENU.COLOR_WARN)
	var empty := await _gear_in(Vector2i(1920, 1080), SaveGame.new())
	assert_eq(empty.totals_text(), "Summe: noch keine Werte")
	assert_eq(empty.strength_text(), "Stärke 0 / empfohlen 0 (Stufe 1)")


func test_mouse_slot_filters_compares_and_swaps() -> void:
	var data := _save_with_helmets()
	var save: SaveGame = data["save"]
	var gear := await _gear_in(Vector2i(1920, 1080), save)
	watch_signals(gear)
	assert_eq(_item_ids(gear).size(), 4, "ohne gewählten Platz alle Teile")
	await _click(gear.buttons["slot_helm"])
	assert_eq(gear.slot_filter, "helm")
	var ids := _item_ids(gear)
	ids.sort()
	assert_eq(ids, [data["worn"]["id"], data["spare"]["id"], data["better"]["id"]], "nur die Helme")
	assert_eq(gear.selected_id, data["better"]["id"], "neuestes nicht angelegtes Teil gewählt")
	assert_eq(gear.comparison_lines()[0], "Angelegt: Magischer Helm", "Vergleich mit dem angelegten Helm")
	assert_eq(gear.comparison_lines()[1], "Zonenbreite: +5 rpm · angelegt +3 rpm · +2")
	assert_true(gear.buttons["slot_helm"].button_pressed, "gewählter Platz markiert")
	await _click(gear.buttons["equip"])
	assert_eq(int(Inventory.equipped(save)["helm"]["id"]), data["better"]["id"], "getauscht")
	assert_signal_emit_count(gear, "gear_changed", 1)
	assert_string_contains(gear.buttons["slot_helm"].text, "Seltener Helm", "der Platz zeigt das neue Teil")
	assert_eq(gear.buttons["slot_helm"].get_theme_color("font_color"), Loot.color_of(Loot.RARE))
	assert_eq(gear.preview.material_color("helmet"), Loot.color_of(Loot.RARE), "Fahrer trägt den neuen Helm")
	# Ein Klick auf einen leeren Platz ohne passende Teile: nichts zum Anlegen.
	await _click(gear.buttons["slot_schuhe"])
	assert_eq(gear.slot_filter, "schuhe")
	assert_eq(_item_ids(gear).size(), 0, "keine Schuhe im Inventar")
	assert_true(gear.find_child("Empty", true, false).text.contains("Schuhe"))
	assert_true(gear.buttons["equip"].disabled)
	# Derselbe Platz noch einmal: wieder alle Teile.
	await _click(gear.buttons["slot_schuhe"])
	assert_eq(gear.slot_filter, "")
	assert_eq(_item_ids(gear).size(), 4)


func test_keyboard_slot_to_part_to_equip_and_escape() -> void:
	var data := _save_with_helmets()
	data["save"].save_file(SAVE_PATH)
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(start_fake_bus([FakeBusServer.status()]))
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	await run_for(0.2)
	game.open_gear_menu()
	await get_tree().process_frame
	var gear: CanvasLayer = game.gear_menu
	var save: SaveGame = game.save_game
	var worn_id := int(Inventory.equipped(save)["helm"]["id"])
	gear.buttons["slot_helm"].grab_focus()
	await _press(KEY_ENTER)
	assert_eq(gear.slot_filter, "helm", "Enter auf dem Platz zeigt dessen Teile")
	assert_eq(game.get_viewport().gui_get_focus_owner(), gear.buttons["item_%d" % gear.selected_id], "Fokus auf dem Teil")
	assert_ne(gear.selected_id, worn_id)
	var chosen: int = gear.selected_id
	gear.buttons["equip"].grab_focus()
	await _press(KEY_ENTER)
	assert_eq(int(Inventory.equipped(save)["helm"]["id"]), chosen, "per Tastatur getauscht")
	assert_eq(int(Inventory.equipped(SaveGame.load_file(SAVE_PATH))["helm"]["id"]), chosen, "gleich gespeichert")
	assert_true(gear.buttons["salvage"].disabled, "das angelegte Teil lässt sich nicht verwerten")
	# Zurück auf einen anderen Platz mit den Pfeiltasten und Enter: Filter wechselt.
	gear.buttons["slot_trikot"].grab_focus()
	await _press(KEY_SPACE)
	assert_eq(gear.slot_filter, "trikot")
	await _press(KEY_ESCAPE)
	assert_false(gear.visible, "Esc schließt")
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.start_menu.buttons["arcade_gear"])


func _assert_sheet_inside(gear: CanvasLayer, label: String) -> void:
	var screen: Rect2 = gear.get_node("Layout").get_viewport_rect()
	var scrolls := gear.find_children("*", "ScrollContainer", true, false)
	var checked := 0
	for control in gear.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control is ScrollBar \
				or scrolls.any(func(s): return s.is_ancestor_of(control)):
			continue
		checked += 1
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()), "%s: %s liegt im Fenster %s (%s)" % [
				label, control.name, screen, control.get_global_rect()])
	assert_gt(checked, 8, "%s: alle Anzeigen geprüft" % label)
	var sheet: Rect2 = gear.find_child("Sheet", true, false).get_global_rect()
	var items: Rect2 = gear.find_child("Items", true, false).get_global_rect()
	var detail: Rect2 = gear.find_child("Detail", true, false).get_global_rect()
	assert_false(sheet.intersects(items) or sheet.intersects(detail), "%s: Blatt neben Liste und Werten" % label)
	assert_false(items.intersects(detail), "%s: Liste und Werte getrennt" % label)
	assert_gt(items.size.x, 300.0, "%s: Liste breit genug" % label)
	var preview: Rect2 = gear.find_child("Preview", true, false).get_global_rect()
	var view_port: Rect2 = gear.find_child("SheetScroll", true, false).get_global_rect()
	assert_true(view_port.grow(0.5).encloses(preview) or gear.find_child("SheetScroll", true, false).get_v_scroll_bar().visible,
			"%s: Fahrer im Blatt oder erreichbar (%s in %s)" % [label, preview, view_port])
	assert_gt(minf(preview.size.x, preview.size.y), 150.0, "%s: Fahrer groß genug (%s)" % [label, preview.size])
	var rects := [preview]
	for slot in Loot.SLOTS:
		var rect: Rect2 = gear.buttons["slot_" + slot].get_global_rect()
		assert_gt(rect.size.x, 100.0, "%s: %s breit genug" % [label, slot])
		assert_false(rects.any(func(r): return r.intersects(rect)), "%s: %s überdeckt nichts (%s)" % [label, slot, rect])
		rects.append(rect)
		assert_true(sheet.grow(0.5).encloses(rect) or gear.find_child("SheetScroll", true, false).get_v_scroll_bar().visible,
				"%s: %s im Blatt" % [label, slot])
	var totals: Rect2 = gear.find_child("Totals", true, false).get_global_rect()
	var strength: Rect2 = gear.find_child("Strength", true, false).get_global_rect()
	assert_false(totals.intersects(strength), "%s: Summe und Stärke getrennt" % label)
	assert_false(totals.intersects(view_port) or strength.intersects(view_port), "%s: Summe und Stärke unter dem Fahrer" % label)
	for key in ["equip", "salvage"]:
		var rect: Rect2 = gear.buttons[key].get_global_rect()
		assert_true(detail.grow(0.5).encloses(rect), "%s: %s im Bereich der Werte" % [label, key])
	var view: SubViewport = gear.find_child("Viewport", true, false)
	assert_gt(view.size.x, 100, "%s: Vorschau rendert (%s)" % [label, view.size])


func _full_save() -> SaveGame:
	var save := SaveGame.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(30):
		Inventory.add(save, Loot.roll(rng, 3.0))
	for slot in Loot.SLOTS:  # alle sechs Plätze belegt, auch mit Teilen voller Werte
		var best := Inventory.items(save).filter(func(item): return item["slot"] == slot)
		if not best.is_empty():
			Inventory.equip(save, int(best[-1]["id"]))
	return save


func test_layout_fits_half_screen_window() -> void:
	_assert_sheet_inside(await _gear_in(Vector2i(960, 1040), _full_save()), "960×1040")
	_assert_sheet_inside(await _gear_in(Vector2i(960, 1040), SaveGame.new()), "960×1040 ohne Beute")


func test_layout_fits_full_screen_sizes() -> void:
	_assert_sheet_inside(await _gear_in(Vector2i(1920, 1080), _full_save()), "1920×1080")
	_assert_sheet_inside(await _gear_in(Vector2i(1152, 648), _full_save()), "1152×648 (Godot-Standardfenster)")
