## Garderobe (#36): Teile werden mit dem Fahrerlevel frei (gesperrte zeigen ihr Level und sind nicht wählbar), die Wahl
## färbt das Fahrermodell, wird gespeichert und übersteht einen Neustart; Bedienung per Tastatur und Maus, Layout im
## Halbbild-Fenster, im Vollbild und in 1152×648 – und ADR-0010: mit anderer Garderobe gleiche Rundenzeit, Medaille und
## Bestzeit.
extends "res://tests/support/bus_test.gd"

const WARDROBE := preload("res://scenes/wardrobe.gd")
var SAVE_PATH := TestIsolation.path("test_wardrobe_savegame.json")
const DT := 1.0 / 60.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Ein Stand mit `km` gefahrenen Kilometern (eine Fahrt).
func _save_with_km(km: float) -> SaveGame:
	var save := SaveGame.new()
	if km > 0.0:
		var stats := RideStats.new()
		stats.add(km * 150.0, 85.0, km * 1000.0)
		save.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, false, 0, stats,
				"2026-10-01T18:00:00Z"))
	return save


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus, mit Test-Spielstand.
func _spawn_game(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## Garderobe in `viewport_size` (Pixel), geöffnet mit `save`.
func _wardrobe_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var wardrobe: CanvasLayer = WARDROBE.new()
	viewport.add_child(wardrobe)
	wardrobe.open(save)
	await wait_process_frames(4)
	return wardrobe


## Taste wie ein Spieler (wie tests/test_start_menu.gd).
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


## Mausklick in die Mitte eines Knopfs, direkt an dessen Viewport (wie tests/test_start_menu.gd).
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


func _color(item: String, material: String) -> Color:
	return Wardrobe.PARTS[item]["colors"][material]


func test_parts_unlock_over_the_level_curve() -> void:
	assert_eq(Wardrobe.PARTS.keys().size(), DriverLevel.UNLOCKS.size(), "jedes Teil hat ein Level und umgekehrt")
	for item in Wardrobe.PARTS:
		assert_true(DriverLevel.UNLOCKS.has(item), "%s in DriverLevel.UNLOCKS" % item)
		for material in Wardrobe.PARTS[item]["colors"]:
			assert_has(RiderModel.OUTFIT_MATERIALS, material, "%s färbt nur Kleidung, Rad und Helm" % item)
	for category in Wardrobe.CATEGORIES:
		var items := Wardrobe.parts(category)
		assert_gt(items.size(), 3, "%s: mehrere Teile" % category)
		assert_eq(items[0], Wardrobe.DEFAULTS[category], "%s: Standard zuerst" % category)
		assert_eq(DriverLevel.unlock_level(items[0]), 1, "%s: Standard ab Level 1" % category)
		var last := 0
		for item in items:
			assert_gt(DriverLevel.unlock_level(item), last, "%s: Teile über die Levelkurve verteilt" % item)
			last = DriverLevel.unlock_level(item)
		assert_gt(last, 10, "%s: das letzte Teil braucht ein hohes Level" % category)
	var beginner := _save_with_km(0.0)
	assert_eq(Wardrobe.level(beginner), 1)
	for item in Wardrobe.PARTS:
		assert_eq(DriverLevel.unlocked(item, 1), item in Wardrobe.DEFAULTS.values(), "Level 1: nur der Standard frei (%s)" % item)
	var veteran := _save_with_km(DriverLevel.km_for(DriverLevel.MAX_LEVEL))
	for item in Wardrobe.PARTS:
		assert_true(Wardrobe.choose(veteran, item), "höchstes Level: %s frei" % item)


func test_selection_defaults_and_locked_parts_not_selectable() -> void:
	var save := _save_with_km(DriverLevel.km_for(6))  # Level 6: Zitronengelb frei, Schwarz (15) nicht
	assert_eq(Wardrobe.selection(save), Wardrobe.DEFAULTS, "ohne Wahl: Standard je Kategorie")
	assert_true(Wardrobe.choose(save, "trikot_gelb"))
	assert_false(Wardrobe.choose(save, "trikot_schwarz"), "gesperrt (ab Level 15)")
	assert_false(Wardrobe.choose(save, "helm_unbekannt"), "unbekanntes Teil")
	assert_eq(Wardrobe.selection(save)["trikot"], "trikot_gelb", "die gesperrte Wahl ändert nichts")
	save.wardrobe()["radfarbe"] = "radfarbe_gold"  # z. B. aus einem Stand mit mehr Kilometern
	save.wardrobe()["helm"] = "trikot_rot"
	assert_eq(Wardrobe.selection(save)["radfarbe"], "radfarbe_rot", "gesperrt gespeichert: Standard")
	assert_eq(Wardrobe.selection(save)["helm"], "helm_weiss", "falsche Kategorie: Standard")
	var outfit := Wardrobe.outfit(Wardrobe.selection(save))
	assert_eq(outfit["jersey"], _color("trikot_gelb", "jersey"))
	assert_eq(outfit["frame"], RiderModel.FRAME_COLOR)


func test_locked_parts_show_their_level_in_the_wardrobe() -> void:
	var wardrobe := await _wardrobe_in(Vector2i(1920, 1080), _save_with_km(DriverLevel.km_for(6)))
	var locked: Button = wardrobe.buttons["trikot_schwarz"]
	assert_true(locked.disabled, "gesperrt: ausgegraut")
	assert_eq(locked.text, "Nachtschwarz · ab Level 15", "zeigt, ab welchem Level")
	assert_eq(locked.focus_mode, Control.FOCUS_NONE, "Tastatur überspringt gesperrte")
	var free: Button = wardrobe.buttons["trikot_gelb"]
	assert_false(free.disabled)
	assert_eq(free.text, "Zitronengelb", "freie Teile nur mit Namen")
	assert_string_contains(wardrobe.find_child("Level", true, false).text, "Fahrerlevel 6")
	for item in Wardrobe.PARTS:
		var level := DriverLevel.unlock_level(item)
		assert_eq((wardrobe.buttons[item] as Button).disabled, level > 6, item)
		if level > 6:
			assert_string_contains(wardrobe.buttons[item].text, "ab Level %d" % level)
	assert_true((wardrobe.buttons["trikot_blau"] as Button).button_pressed, "Standard gewählt")


func test_choice_dresses_rider_is_saved_and_survives_restart() -> void:
	_save_with_km(DriverLevel.km_for(20)).save_file(SAVE_PATH)
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	var rider: RiderModel = game.rider_model
	assert_eq(rider.material_color("jersey"), RiderModel.JERSEY_COLOR, "vorher: Standard")
	game.start_menu.buttons["wardrobe"].pressed.emit()
	var wardrobe: CanvasLayer = game.wardrobe
	assert_true(wardrobe.visible, "Garderobe offen")
	assert_false(game.start_menu.visible, "Startmenü tritt zurück")
	for item in ["trikot_gelb", "radfarbe_gold", "helm_schwarz"]:
		wardrobe.buttons[item].pressed.emit()
	assert_eq(rider.material_color("jersey"), _color("trikot_gelb", "jersey"), "Trikot am Fahrer")
	assert_eq(rider.material_color("jersey_band"), _color("trikot_gelb", "jersey_band"), "mit Brustband")
	assert_eq(rider.material_color("frame"), _color("radfarbe_gold", "frame"), "Radfarbe am Fahrer")
	assert_eq(rider.material_color("helmet"), _color("helm_schwarz", "helmet"), "Helm am Fahrer")
	assert_eq(rider.material_color("helmet_stripe"), _color("helm_schwarz", "helmet_stripe"))
	assert_eq(wardrobe.preview.material_color("jersey"), _color("trikot_gelb", "jersey"), "Vorschau zeigt die Wahl")
	assert_ne(game.ghost_model.material_color("jersey"), _color("trikot_gelb", "jersey"),
			"Ghost-Mitfahrer bleibt im Ghost-Look")
	assert_true((wardrobe.buttons["trikot_gelb"] as Button).button_pressed, "gewählt markiert")
	assert_false((wardrobe.buttons["trikot_blau"] as Button).button_pressed, "eins je Kategorie")
	var stored := SaveGame.load_file(SAVE_PATH)
	assert_eq(stored.wardrobe(), {"trikot": "trikot_gelb", "radfarbe": "radfarbe_gold", "helm": "helm_schwarz"},
			"sofort gespeichert")
	assert_eq(stored.version(), SaveGame.VERSION, "Format unverändert (Version 1)")
	# Neustart: eine neue Hauptszene liest denselben Spielstand; der Fahrer trägt die Wahl in der Fahrt.
	var restarted := _spawn_game(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 4.0)))
	await run_for(0.1)
	assert_eq(Wardrobe.selection(restarted.save_game)["trikot"], "trikot_gelb")
	assert_eq(restarted.rider_model.material_color("jersey"), _color("trikot_gelb", "jersey"), "nach dem Neustart")
	restarted.start_menu.buttons["drive"].pressed.emit()
	restarted.start_menu.buttons["round_trip"].pressed.emit()
	restarted.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return restarted.state == "riding", 3.0), "Fahrt läuft")
	assert_true(restarted.rider.visible)
	assert_eq(restarted.rider_model.material_color("frame"), _color("radfarbe_gold", "frame"), "in der Fahrt")


func test_keyboard_opens_chooses_and_closes() -> void:
	_save_with_km(DriverLevel.km_for(4)).save_file(SAVE_PATH)  # Level 4: Inselblau, Kalkweiß, Terrakotta frei
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	var viewport := game.get_viewport()
	assert_eq(viewport.gui_get_focus_owner(), game.start_menu.buttons["drive"])
	await _press(KEY_DOWN)
	await _press(KEY_DOWN)
	assert_eq(viewport.gui_get_focus_owner(), game.start_menu.buttons["wardrobe"], "Garderobe wählbar")
	await _press(KEY_ENTER)
	var wardrobe: CanvasLayer = game.wardrobe
	assert_true(wardrobe.visible, "Enter öffnet die Garderobe")
	assert_eq(viewport.gui_get_focus_owner(), wardrobe.buttons["trikot_blau"], "Fokus auf dem gewählten Trikot")
	await _press(KEY_TAB)
	assert_eq(viewport.gui_get_focus_owner(), wardrobe.buttons["trikot_weiss"], "Tab zum nächsten Teil")
	await _press(KEY_ENTER)
	assert_eq(Wardrobe.selection(game.save_game)["trikot"], "trikot_weiss", "Enter wählt")
	await _press(KEY_TAB)
	await _press(KEY_SPACE)
	assert_eq(Wardrobe.selection(game.save_game)["trikot"], "trikot_rot", "Leertaste wählt auch")
	await _press(KEY_TAB)
	assert_eq(viewport.gui_get_focus_owner(), wardrobe.buttons["radfarbe_rot"], "gesperrte Trikots übersprungen")
	assert_eq(game.rider_model.material_color("jersey"), _color("trikot_rot", "jersey"))
	await _press(KEY_ESCAPE)
	assert_false(wardrobe.visible, "Esc schließt")
	assert_false(game.settings_menu.is_open(), "Esc öffnet dabei nicht die Einstellungen")
	assert_true(game.start_menu.visible, "zurück im Startmenü")
	assert_eq(viewport.gui_get_focus_owner(), game.start_menu.buttons["wardrobe"], "Fokus auf „Garderobe“")
	assert_eq(SaveGame.load_file(SAVE_PATH).wardrobe()["trikot"], "trikot_rot", "gespeichert")


func test_settings_over_wardrobe_return_focus() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	game.open_wardrobe()
	await _press(KEY_F2)
	assert_true(game.settings_menu.is_open(), "F2 öffnet die Einstellungen über der Garderobe")
	await _press(KEY_ESCAPE)
	await get_tree().process_frame
	assert_false(game.settings_menu.is_open(), "Esc schließt die Einstellungen")
	assert_true(game.wardrobe.visible, "die Garderobe bleibt offen")
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.wardrobe.buttons["trikot_blau"], "Fokus zurück")


func test_mouse_chooses_parts_and_back() -> void:
	var save := _save_with_km(DriverLevel.km_for(8))
	var wardrobe := await _wardrobe_in(Vector2i(1600, 900), save)
	watch_signals(wardrobe)
	await _click(wardrobe.buttons["radfarbe_orange"])
	assert_eq(Wardrobe.selection(save)["radfarbe"], "radfarbe_orange", "Klick wählt")
	assert_signal_emitted_with_parameters(wardrobe, "part_chosen", ["radfarbe_orange"])
	assert_eq(wardrobe.preview.material_color("frame"), _color("radfarbe_orange", "frame"), "Vorschau folgt")
	await _click(wardrobe.buttons["radfarbe_gold"])
	assert_eq(Wardrobe.selection(save)["radfarbe"], "radfarbe_orange", "gesperrt: Klick wählt nicht")
	assert_signal_emit_count(wardrobe, "part_chosen", 1)
	await _click(wardrobe.buttons["back"])
	assert_false(wardrobe.visible, "Zurück schließt")
	assert_signal_emitted(wardrobe, "closed")


## Alles liegt im Fenster und überlappt nicht; die Vorschau hat Platz, die Teile liegen seitlich in ihrem Bereich, und
## was nicht in die Höhe passt, erreicht der Scrollbalken.
func _assert_wardrobe_inside(wardrobe: CanvasLayer, label: String) -> void:
	var screen: Rect2 = wardrobe.get_node("Layout").get_viewport_rect()
	var scroll: ScrollContainer = wardrobe.find_child("Scroll", true, false)
	var checked := 0
	for control in wardrobe.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control is ScrollBar or scroll.is_ancestor_of(control):
			continue
		checked += 1
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()), "%s: %s liegt im Fenster %s (%s)" % [
				label, control.name, screen, control.get_global_rect()])
	assert_gt(checked, 6, "%s: alle Anzeigen geprüft" % label)
	var parts := scroll.get_global_rect()
	for item in Wardrobe.PARTS:
		var rect: Rect2 = wardrobe.buttons[item].get_global_rect()
		assert_true(rect.position.x >= parts.position.x - 0.5 and rect.end.x <= parts.end.x + 0.5,
				"%s: %s seitlich im Bereich der Teile (%s in %s)" % [label, item, rect, parts])
	var content: Control = scroll.get_node("Content")
	if content.size.y > parts.size.y + 0.5:
		assert_true(scroll.get_v_scroll_bar().visible, "%s: zu lang → scrollt" % label)
	var preview: Rect2 = wardrobe.find_child("Preview", true, false).get_global_rect()
	assert_gt(minf(preview.size.x, preview.size.y), 200.0, "%s: Vorschau groß genug (%s)" % [label, preview.size])
	assert_false(preview.intersects(parts), "%s: Vorschau neben den Teilen" % label)
	var actions: Rect2 = wardrobe.find_child("Actions", true, false).get_global_rect()
	var title: Rect2 = wardrobe.find_child("Title", true, false).get_global_rect()
	var level: Rect2 = wardrobe.find_child("Level", true, false).get_global_rect()
	for area in [preview, parts]:
		assert_false(area.intersects(actions) or area.intersects(title) or area.intersects(level),
				"%s: frei von Titel, Level und „Zurück“" % label)
	var view: SubViewport = wardrobe.find_child("Viewport", true, false)
	assert_gt(view.size.x, 150, "%s: Vorschau rendert in Größe (%s)" % [label, view.size])


func test_layout_fits_half_screen_window() -> void:
	var wardrobe := await _wardrobe_in(Vector2i(960, 1040), _save_with_km(DriverLevel.km_for(5)))
	_assert_wardrobe_inside(wardrobe, "960×1040")


func test_layout_fits_full_screen_sizes() -> void:
	_assert_wardrobe_inside(await _wardrobe_in(Vector2i(1920, 1080), _save_with_km(0.0)), "1920×1080")
	_assert_wardrobe_inside(await _wardrobe_in(Vector2i(1152, 648), _save_with_km(0.0)), "1152×648 (Godot-Standardfenster)")


## Eine Runde Graybox mit fester Kadenz, Schritt für Schritt (wie tests/test_driver_level.gd).
func _lap(ride: Node) -> Node:
	ride.set_process(false)
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
	for i in range(100000):
		if not ride.lap_timing.lap_times.is_empty():
			break
		ride._ride(DT)
	assert_eq(ride.lap_timing.lap_times.size(), 1, "Runde zu Ende gefahren")
	return ride


func _riding() -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == 90.0, 3.0))
	return ride


func test_wardrobe_changes_neither_lap_time_medal_nor_best_time() -> void:
	var plain := _lap(await _riding())
	var dressed_ride := await _riding()
	var km := DriverLevel.km_for(DriverLevel.MAX_LEVEL)
	dressed_ride.save_game.add_ride(_save_with_km(km).rides()[0])
	for item in ["trikot_schwarz", "radfarbe_gold", "helm_gold"]:
		assert_true(Wardrobe.choose(dressed_ride.save_game, item))
	dressed_ride._apply_wardrobe()
	var dressed := _lap(dressed_ride)
	assert_eq(dressed.rider_model.material_color("frame"), _color("radfarbe_gold", "frame"), "andere Garderobe")
	assert_eq(dressed.lap_timing.lap_times[0], plain.lap_timing.lap_times[0], "gleiche Rundenzeit (ADR-0010)")
	assert_eq(dressed.lap_medal(0), plain.lap_medal(0), "gleiche Medaille")
	assert_eq(dressed.medal_limits, plain.medal_limits, "gleiche Medaillen-Schwellen")
	assert_eq(dressed.model.distance_m, plain.model.distance_m, "gleiche Strecke")
	for ride in [plain, dressed]:
		ride._save_ride()
	assert_eq(dressed.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW),
			plain.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), "gleiche Bestzeit")
