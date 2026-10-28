## Fund-Karte der Beute (#83, Story 6): ein Fund zeigt rechts im HUD das Ausrüstungssymbol des Teils (gleiches Teil,
## Rahmen in der Farbe der Seltenheit, legendär leuchtet) mit Name, Seltenheit und Werten; sie schiebt ein, steht und
## verschwindet; mehrere Funde stehen untereinander ohne sich zu überdecken (passt keiner mehr hin, wartet er); die Lage
## überdeckt in 960×1040, 1920×1080 und 1152×648 keine HUD-Anzeige (Kadenz, Tempo, Arcade-Zeile, Zonenbalken, Minikarte,
## Popups, Ansagen); über den echten Weg (`ArcadeStage.show_loot`, Fund in der Fahrt) erscheint sie, im Menü und im
## Ergebnis ist sie weg. Die Text-Popups bleiben (test_arcade_loot_ride.gd).
extends "res://tests/support/bus_test.gd"

const HUD_SCENE := preload("res://scenes/hud.tscn")
var SAVE_PATH := TestIsolation.path("test_loot_toast_savegame.json")
const DT := 0.1
const SIZES := [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]


func after_each() -> void:
	super.after_each()
	ItemIcons.clear_cache()
	ItemIcons.glow_enabled = true
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _item(slot: String, rarity: String, stats: Dictionary, effect: String = "") -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


func _legendary() -> Dictionary:
	return _item("trikot", Loot.LEGENDARY, {"points_pct": 24, "progress_pct": 12, "luck_pct": 9, "zone_width_rpm": 3},
			"rueckstoss")


## HUD in einem Fenster der Größe `size`, mit Karte, im Zustand eines Arcade-Laufs (alle Zeilen unten sichtbar).
func _hud_in(size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var hud: RideHud = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	hud.show_ride(92.0, 31.4, 5200.0, "12:04.3", 0.02, "+2,0 %", "Strand", "180 W")
	hud.show_arcade("Zone halten", "90–110 rpm", "0:24", "340")
	hud.show_zone(90.0, 110.0, 95.0, "63 %", "Fortschritt")
	var toast := LootToast.attach(hud)
	await wait_process_frames(4)
	return {"hud": hud, "toast": toast}


func _card_of(toast: LootToast, index: int = 0) -> Control:
	return toast.cards()[index]


func _icon_of(card: Control) -> ItemIconView:
	return card.find_child("ItemIcon", true, false)


func _texts(card: Control) -> Array:
	return card.find_child("Text", true, false).get_children().map(func(l): return (l as Label).text)


## Breite der Schrift eines mittigen Labels als Rechteck um seine Mitte (Popups und Ansagen füllen die Breite, der Text nicht).
func _text_rect(label: Label) -> Rect2:
	var rect := label.get_global_rect()
	# Ohne Schrift (headless) misst Godot zu schmal: mindestens eine mittlere Zeichenbreite je Zeichen zählt.
	var px := label.get_theme_font_size("font_size")
	var width := maxf(label.get_minimum_size().x, label.text.length() * px * 0.55)
	return Rect2(rect.get_center().x - width / 2.0, rect.position.y, width, rect.size.y)


# --- Inhalt der Karte ----------------------------------------------------------------------------------------------


func test_card_shows_the_icon_of_the_part_with_name_rarity_and_stats() -> void:
	var item := _legendary()
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.show_item(item)
	await wait_process_frames(2)
	assert_eq(toast.cards().size(), 1)
	var icon := _icon_of(_card_of(toast))
	assert_not_null(icon, "Symbol auf der Karte")
	assert_eq(icon.item, item, "das Symbol des Fundes")
	assert_eq(icon.frame_color(), Loot.color_of(Loot.LEGENDARY), "Rahmen in der Farbe der Seltenheit")
	assert_eq(icon.texture(), ItemIcons.texture_for(item), "dasselbe Bild wie überall (Inhalt, nicht id)")
	assert_almost_eq(icon.icon_size, 96.0, 0.5, "etwa 96 px bei 1080 px Höhe")
	var texts := _texts(_card_of(toast))
	assert_eq(texts[0], Loot.item_name(item), "Name")
	assert_eq(texts[1], "Legendär · Rückstoß", "Seltenheit und Effekt")
	assert_eq(texts.slice(2), Array(Array(Loot.stats_text(item).split(" · ")), TYPE_STRING, "", null), "Werte")
	var name_label: Label = _card_of(toast).find_child("Name", true, false)
	assert_eq(name_label.get_theme_color("font_color"), Loot.color_of(Loot.LEGENDARY), "Name in der Seltenheitsfarbe")


func test_each_rarity_gets_its_frame_color_and_only_legendary_glows() -> void:
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.hold_s = 0.3
	for rarity in [Loot.COMMON, Loot.MAGIC, Loot.RARE, Loot.LEGENDARY]:
		toast.clear()
		toast.show_item(_item("helm", rarity, {"zone_width_rpm": 4}))
		await wait_process_frames(2)
		var icon := _icon_of(_card_of(toast))
		assert_eq(icon.frame_color(), Loot.color_of(rarity), rarity)
		assert_eq(icon.is_glowing(), rarity == Loot.LEGENDARY, "leuchtet nur legendär: " + rarity)
		var kind: String = _texts(_card_of(toast))[1]
		assert_eq(kind, Loot.RARITIES[rarity]["name"], "ohne Effekt nur die Seltenheit")


func test_glow_switch_turns_the_glow_off_on_the_card() -> void:
	ItemIcons.glow_enabled = false
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.show_item(_legendary())
	await wait_process_frames(2)
	assert_false(_icon_of(_card_of(toast)).is_glowing(), "Schalter aus: kein Leuchten")


# --- Zeit ----------------------------------------------------------------------------------------------------------


func test_card_slides_in_stands_and_disappears_after_the_hold_time() -> void:
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.hold_s = 0.4
	toast.show_item(_item("helm", Loot.RARE, {"zone_width_rpm": 5}))
	await wait_process_frames(2)
	var card := _card_of(toast)
	var right: float = toast.column().end.x
	assert_gt(card.position.x + card.size.x, right, "schiebt von rechts ein")
	await run_for(LootToast.SLIDE_S + 0.2)
	assert_almost_eq(card.position.x + card.size.x, right, 1.0, "steht rechtsbündig neben der Minikarte")
	assert_almost_eq(card.position.y, toast.column().position.y, 1.0, "und oben")
	assert_almost_eq(card.modulate.a, 1.0, 0.01, "voll sichtbar")
	await run_for(0.5)  # in der Ausblendzeit
	assert_lt(card.modulate.a, 1.0, "blendet aus")
	await run_for(LootToast.OUT_S + 0.3)
	assert_eq(toast.cards(), [], "nach der Haltezeit weg")
	assert_false(toast.is_processing(), "nichts mehr zu tun")


func test_default_times_are_a_few_seconds() -> void:
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	assert_between(toast.hold_s, 3.0, 8.0, "steht einige Sekunden")
	assert_lt(LootToast.SLIDE_S, 0.6, "schiebt kurz ein")
	assert_lt(LootToast.OUT_S, 1.0, "blendet kurz aus")


# --- Mehrere Funde -------------------------------------------------------------------------------------------------


func test_several_finds_stack_without_overlapping_and_wait_when_the_column_is_full() -> void:
	for size in SIZES:
		var parts := await _hud_in(size)
		var toast: LootToast = parts["toast"]
		toast.hold_s = 0.5
		var found := [_legendary(), _item("helm", Loot.RARE, {"zone_width_rpm": 5, "points_pct": 8, "luck_pct": 9}),
				_item("schuhe", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 7}),
				_item("talisman", Loot.COMMON, {"luck_pct": 6})]
		for item in found:
			toast.show_item(item)
		await run_for(LootToast.SLIDE_S + 0.2)  # die Karten sind an ihrem Platz
		var column := toast.column()
		var cards := toast.cards()
		assert_gt(cards.size(), 0, "%s: mindestens eine Karte" % size)
		assert_eq(cards.size() + toast.waiting(), found.size(), "%s: kein Fund geht verloren" % size)
		var rects := cards.map(func(c): return Rect2(c.position, c.size))
		for i in range(rects.size()):
			assert_true(column.grow(0.5).encloses(rects[i]), "%s: Karte %d in der Spalte %s (%s)" % [size, i, column, rects[i]])
			for j in range(i):
				assert_false(rects[i].intersects(rects[j]), "%s: Karten %d und %d überdecken sich" % [size, j, i])
		# Alle kommen irgendwann dran, ohne dass sich je zwei überdecken.
		var shown := []
		var overlap := false
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 15000:
			await get_tree().process_frame
			var now := toast.cards().map(func(c): return Rect2(c.position, c.size))
			for item in toast.items():
				if not shown.has(item):
					shown.append(item)
			for i in range(now.size()):
				for j in range(i):
					overlap = overlap or now[i].intersects(now[j])
			if toast.cards().is_empty() and toast.waiting() == 0:
				break
		assert_false(overlap, "%s: nie überdeckt" % size)
		assert_eq(shown.size(), found.size(), "%s: jeder Fund war zu sehen" % size)


func test_a_big_window_shows_several_cards_at_once() -> void:
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.show_item(_item("helm", Loot.RARE, {"zone_width_rpm": 5}))
	toast.show_item(_item("schuhe", Loot.MAGIC, {"zone_width_rpm": 3}))
	await wait_process_frames(2)
	assert_eq(toast.cards().size(), 2, "untereinander")
	assert_eq(toast.waiting(), 0)


# --- Lage ----------------------------------------------------------------------------------------------------------


func test_card_covers_no_hud_element_in_all_window_sizes() -> void:
	for size in SIZES:
		var parts := await _hud_in(size)
		var hud: RideHud = parts["hud"]
		var toast: LootToast = parts["toast"]
		hud.popup("+100")
		hud.popup(Loot.item_name(_legendary()), Loot.color_of(Loot.LEGENDARY))
		hud.celebrate("Zone halten geschafft!  +100 Punkte")
		hud.show_announcement("In 10 s: Widerstand 2 Stufen hoch, 100 rpm halten")
		hud.show_camera_view("Verfolger")
		toast.show_item(_legendary())
		await run_for(LootToast.SLIDE_S + 0.2)
		var card := _card_of(toast)
		var rect := Rect2(card.position, card.size)
		assert_true(Rect2(Vector2.ZERO, Vector2(size)).encloses(rect), "%s: Karte im Fenster %s" % [size, rect])
		# Feste Anzeigen: Werte-Panel (Kadenz, Tempo …), Minikarte, unteres Panel (Arcade-Zeile, Zonenbalken), Hinweis.
		for node_name in ["Stats", "MapPanel", "Bottom", "Hint", "Cadence", "Gauge", "SpeedValue", "ChallengeValue",
				"ZoneBar", "PointsValue", "Minimap"]:
			var node: Control = hud.find_child(node_name, true, false)
			assert_not_null(node, node_name)
			assert_false(rect.intersects(node.get_global_rect()), "%s: Karte überdeckt %s nicht (%s / %s)" % [
					size, node_name, rect, node.get_global_rect()])
		# Mittige Texte (Landmarken bei Panoramastopps ausgenommen, siehe LootToast): nur der Text zählt.
		for node_name in ["Celebration", "Announcement", "CameraView"]:
			var label: Label = hud.find_child(node_name, true, false)
			assert_true(label.visible, node_name)
			assert_false(rect.intersects(_text_rect(label)), "%s: Karte überdeckt %s nicht (%s / %s)" % [
					size, node_name, rect, _text_rect(label)])
		var popups: Array = hud.find_children("*", "Label", true, false).filter(
				func(l): return l.text in ["+100", Loot.item_name(_legendary())] and not toast.is_ancestor_of(l))
		assert_gt(popups.size(), 0, "%s: Popups gefunden" % size)
		for popup in popups:
			assert_false(rect.intersects(_text_rect(popup)), "%s: Karte überdeckt Popup %s nicht" % [size, popup.text])


## Das Popup mit dem Namen des Fundes steht in der Bildmitte und füllt die Breite nicht; auch der längste Name
## („Gewöhnlicher Talisman“) darf nicht unter die Karte reichen (im Halbbild 960×1040 am knappsten).
func test_no_found_name_as_popup_reaches_the_card_in_any_window_size() -> void:
	for size in SIZES:
		var parts := await _hud_in(size)
		var toast: LootToast = parts["toast"]
		toast.show_item(_legendary())
		await run_for(LootToast.SLIDE_S + 0.2)
		var card_left: float = _card_of(toast).position.x
		var px: int = roundi(RideHud.POPUP_FONT_PX * RideHud.text_scale(size.y))
		for slot in Loot.SLOTS:
			for rarity in Loot.RARITIES:
				var shown := Loot.item_name({"slot": slot, "rarity": rarity})
				var right: float = size.x / 2.0 + shown.length() * px * 0.55 / 2.0  # Schätzung wie in `_text_rect`
				assert_lt(right, card_left, "%s: „%s“ reicht nicht an die Karte (%s / %s)" % [size, shown, right, card_left])


func test_icon_stays_readable_in_small_windows() -> void:
	var parts := await _hud_in(Vector2i(1152, 648))
	var toast: LootToast = parts["toast"]
	toast.show_item(_legendary())
	await wait_process_frames(2)
	var icon := _icon_of(_card_of(toast))
	assert_gte(icon.icon_size, LootToast.MIN_ICON_PX, "mindestens 64 px")
	assert_almost_eq(icon.size.x, icon.icon_size, 1.0)
	var parts_big := await _hud_in(Vector2i(1920, 1080))
	var big: LootToast = parts_big["toast"]
	big.show_item(_legendary())
	await wait_process_frames(2)
	assert_gt(_icon_of(_card_of(big)).icon_size, 80.0, "im großen Fenster etwa 96 px")


func test_card_ignores_the_mouse() -> void:
	var parts := await _hud_in(Vector2i(1920, 1080))
	var toast: LootToast = parts["toast"]
	toast.show_item(_legendary())
	await wait_process_frames(2)
	assert_eq(toast.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var stack := [_card_of(toast)]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s fängt keine Maus" % node.name)
		stack.append_array(node.get_children())


# --- Über den echten Weg -------------------------------------------------------------------------------------------


func _spawn_arcade() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 120.0))
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	await run_for(0.3)
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find("zone_mitte")]
	game.start_ride(SaveGame.MODE_ARCADE, 0, "", {}, Track.DIRECTION_CW, 1)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0))
	return game


func test_show_loot_of_the_stage_raises_the_card_and_menu_and_result_remove_it() -> void:
	var game := await _spawn_arcade()
	var stage: ArcadeStage = game.arcade_stage
	assert_eq(stage.loot_toast.cards(), [], "ohne Fund keine Karte")
	var item := _legendary()
	stage.show_loot({"points": 100, "loot": item}, 0.0)
	await wait_process_frames(3)
	assert_eq(stage.loot_toast.items(), [item], "Fund aus der Bühne")
	assert_eq(_icon_of(_card_of(stage.loot_toast)).item, item, "Symbol des Fundes")
	assert_eq(game.hud.popups(), ["+100", Loot.item_name(item)], "die Text-Popups bleiben daneben")
	stage.show_loot({"points": 0, "loot": {}}, 0.0)
	await wait_process_frames(2)
	assert_eq(stage.loot_toast.items(), [item], "ohne Fund keine zweite Karte")
	game.settings_menu.ride_end_requested.emit()  # Fahrt beenden: Ergebnis (oder Menü)
	await wait_process_frames(3)
	assert_eq(stage.loot_toast.cards(), [], "im Ergebnis bzw. Menü ist die Karte weg")
	assert_eq(stage.loot_toast.waiting(), 0)


func test_menu_clears_the_card() -> void:
	var game := await _spawn_arcade()
	var stage: ArcadeStage = game.arcade_stage
	stage.show_loot({"points": 0, "loot": _legendary()}, 0.0)
	await wait_process_frames(2)
	assert_eq(stage.loot_toast.cards().size(), 1)
	stage.enter_menu()
	assert_eq(stage.loot_toast.cards(), [], "Menü: Karte weg")


func test_a_new_ride_starts_without_a_card() -> void:
	var game := await _spawn_arcade()
	var stage: ArcadeStage = game.arcade_stage
	stage.show_loot({"points": 0, "loot": _legendary()}, 0.0)
	await wait_process_frames(2)
	stage.begin(true, 1, game.save_game, 0.0)
	assert_eq(stage.loot_toast.cards(), [], "neue Fahrt: keine Karte der alten")


func test_a_find_in_a_real_ride_shows_the_card_with_its_icon() -> void:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/zone_perfekt.toml"))
	assert_false(profile.is_empty(), "Profil lesbar")
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	await run_for(0.3)
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find("zone_mitte")]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	menu.buttons["arcade_start"].pressed.emit()
	game.set_process(false)
	var seen := []
	for i in range(roundi((SimProfile.duration_s(profile) + 1.0) / DT)):
		bus.manual_clock_ms += roundi(DT * 1000.0)
		bus.poll()
		await get_tree().process_frame
		game.bus.poll(DT)
		game._update_state()
		if game.state == "riding":
			game._ride(DT)
		game._update_view()
		for card in game.arcade_stage.loot_toast.cards():
			if seen.is_empty():
				seen.append({"item": _icon_of(card).item, "icon": _icon_of(card)})
	assert_eq(game.arcade.found.size(), 1, "Beute in der Fahrt")
	assert_eq(seen.size(), 1, "die Karte erschien")
	assert_eq(seen[0]["item"], game.arcade.found[0], "mit dem gefundenen Teil")
