## Startmenü und Szenenfluss (#30) gegen den Fake-Bus: Titel mit Kameraflug → Fahren → Rundfahrt → Ziel → Enter →
## Menü, Abbruch über „Fahrt beenden“, Menüpunkte per Tastatur und Maus, Radstatus, die beendete Fahrt im Spielstand
## (übersteht einen Neustart) und das Layout im Halbbild-Fenster wie im Vollbild.
extends "res://tests/support/bus_test.gd"

const START_MENU_SCENE := preload("res://scenes/start_menu.tscn")
const START_MENU := preload("res://scenes/start_menu.gd")
const SAVE_PATH := "user://test_start_menu_savegame.json"
## Abstand zur Ziellinie (letzter flacher Abschnitt der Graybox-Strecke).
const BEFORE_FINISH_M := 12.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü), am Fake-Bus, ohne Trägheit, mit Test-Spielstand.
func _spawn_game(bus: FakeBusServer, start_m: float = 20.0) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	config.inertia_s = 0.0
	game.config = config
	game.start_distance_m = start_m
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


func _lap_length() -> float:
	var track: GrayboxTrack = autofree(GrayboxTrack.new())
	return track.length_m()


## Taste wie ein Spieler (Zeichen und physische Position, damit auch die `ui_*`-Aktionen der Oberfläche greifen).
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


## Mausklick in die Mitte eines Knopfs, direkt an dessen Viewport (headless ist das Hauptfenster nur 64×64 groß,
## daher klicken die Maus-Tests das Menü in einem eigenen SubViewport).
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


func _focused(game: Node) -> Control:
	return game.get_viewport().gui_get_focus_owner()


func test_title_flies_over_the_island_without_riding() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 4.0))
	var game := _spawn_game(bus)
	await run_for(0.2)
	assert_eq(game.state, "menu", "nach dem Start: Startmenü")
	assert_true(game.start_menu.visible, "Menü sichtbar")
	assert_false(game.hud.visible, "kein HUD im Titelbild")
	assert_false(game.rider.visible, "kein Fahrer im Titelbild")
	var camera_before: Vector3 = game.camera.global_position
	await run_for(1.5)
	assert_gt(game.camera.global_position.distance_to(camera_before), 1.0, "Kamera fliegt")
	assert_eq(game.state, "menu", "Telemetrie startet keine Fahrt")
	assert_eq(game.model.distance_m, 20.0, "Fahrmodell steht")
	assert_eq(bus.received_of_type("set_grade"), [], "im Menü kein set_grade")
	assert_false(game.settings_menu.find_child("EndRide", true, false).visible, "„Fahrt beenden“ nur in der Fahrt")


func test_island_title_camera_stays_above_terrain() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	var game := MAIN_SCENE.instantiate()
	game.config = config
	game.settings_path = ""
	game.save_path = ""
	game.quit_on_request = false
	add_child_autofree(game)
	var lowest := INF
	for d in range(0, int(game.track.length_m()), 25):
		game._flight_m = float(d)
		game._fly_title(0.0, true)
		var at: Vector3 = game.camera.global_position
		lowest = minf(lowest, at.y - game.world.terrain.height_at(at.x, at.z))
	assert_gt(lowest, 15.0, "Kameraflug über die ganze Runde hoch über dem Gelände")


func test_menu_items_and_disabled_entries() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	var buttons: Dictionary = game.start_menu.buttons
	var texts := {}
	for key in buttons:
		texts[key] = (buttons[key] as Button).text
	assert_eq(texts["drive"], "Fahren")
	assert_eq(texts["round_trip"], "Rundfahrt")
	assert_eq(texts["settings"], "Einstellungen")
	assert_eq(texts["quit"], "Beenden")
	assert_eq(texts["arcade"], "Arcade", "Arcade wählbar (#46)")
	assert_eq(texts["logbook"], "Fahrtenbuch")
	assert_eq(texts["wardrobe"], "Garderobe", "Garderobe wählbar (#36)")
	assert_eq(texts["training"], "Training", "Training wählbar (#37)")
	for key in ["drive", "round_trip", "training", "arcade", "logbook", "wardrobe", "settings", "quit", "back"]:
		assert_false(buttons[key].disabled, "%s wählbar" % key)
	assert_true(buttons["quit"].is_visible_in_tree(), "Beenden auf dem Desktop")
	var web_menu := START_MENU_SCENE.instantiate()
	web_menu.web = true
	add_child_autofree(web_menu)
	assert_false(web_menu.buttons["quit"].visible, "Beenden gibt es im Browser nicht")


func test_keyboard_drives_menu_into_ride() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 6.0))
	var game := _spawn_game(bus)
	await run_for(0.2)
	assert_eq(_focused(game), game.start_menu.buttons["drive"], "Fokus auf „Fahren“")
	await _press(KEY_DOWN)
	assert_eq(_focused(game), game.start_menu.buttons["logbook"], "Fahrtenbuch wählbar (#35)")
	await _press(KEY_DOWN)
	assert_eq(_focused(game), game.start_menu.buttons["wardrobe"], "Garderobe wählbar (#36)")
	await _press(KEY_DOWN)
	assert_eq(_focused(game), game.start_menu.buttons["settings"])
	await _press(KEY_UP)
	await _press(KEY_UP)
	await _press(KEY_UP)
	await _press(KEY_ENTER)
	assert_eq(_focused(game), game.start_menu.buttons["round_trip"], "Fahren → Modus-Auswahl")
	await _press(KEY_DOWN)
	await _press(KEY_DOWN)
	assert_eq(_focused(game), game.start_menu.buttons["arcade"], "Arcade wählbar (#46)")
	await _press(KEY_UP)
	await _press(KEY_UP)
	await _press(KEY_ENTER)
	assert_eq(_focused(game), game.start_menu.buttons["start"], "Rundfahrt → Rundenzahl und Tageszeit, Fokus auf „Losfahren“")
	await _press(KEY_ENTER)
	assert_false(game.start_menu.visible, "Menü weg")
	assert_true(game.hud.visible, "HUD da")
	assert_true(game.rider.visible)
	assert_null(_focused(game), "kein verborgener Knopf behält den Fokus (Leertaste = Pause)")
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Rundfahrt fährt los")
	await _press(KEY_SPACE)
	assert_eq(game.state, "paused_manual", "Leertaste pausiert wie bisher")


func test_mouse_selects_menu_items() -> void:
	var menu := await _menu_in(Vector2i(1600, 900))
	watch_signals(menu)
	await _click(menu.buttons["wardrobe"])
	assert_signal_emitted(menu, "wardrobe_requested", "Garderobe per Maus (#36)")
	assert_signal_emit_count(menu, "ride_requested", 0)
	assert_signal_emit_count(menu, "logbook_requested", 0)
	await _click(menu.buttons["logbook"])
	assert_signal_emitted(menu, "logbook_requested", "Fahrtenbuch per Maus (#35)")
	assert_signal_emit_count(menu, "settings_requested", 0)
	assert_true(menu.buttons["drive"].is_visible_in_tree(), "noch auf der Hauptseite")
	await _click(menu.buttons["settings"])
	assert_signal_emitted(menu, "settings_requested", "Einstellungen per Maus")
	await _click(menu.buttons["drive"])
	assert_true(menu.buttons["round_trip"].is_visible_in_tree(), "Fahren → Modus-Auswahl")
	await _click(menu.buttons["arcade"])
	assert_signal_emit_count(menu, "ride_requested", 0, "Arcade öffnet erst die Auswahl (#46)")
	assert_true(menu.buttons["arcade_start"].is_visible_in_tree(), "Seite „Arcade“")
	await _click(menu.buttons["arcade_back"])
	assert_true(menu.buttons["round_trip"].is_visible_in_tree(), "zurück zur Modus-Auswahl")
	await _click(menu.buttons["back"])
	assert_true(menu.buttons["drive"].is_visible_in_tree(), "Zurück zur Hauptseite")
	await _click(menu.buttons["quit"])
	assert_signal_emitted(menu, "quit_requested", "Beenden per Maus")
	await _click(menu.buttons["drive"])
	await _click(menu.buttons["round_trip"])
	assert_signal_emit_count(menu, "ride_requested", 0, "Rundfahrt öffnet erst die Auswahl")
	await _click(menu.buttons["start"])
	assert_signal_emitted_with_parameters(menu, "ride_requested", [SaveGame.MODE_ROUND_TRIP])


func test_space_never_quits_enter_does() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	watch_signals(game.start_menu)
	await run_for(0.2)
	game.start_menu.buttons["quit"].grab_focus()
	await _press(KEY_SPACE)
	assert_signal_not_emitted(game.start_menu, "quit_requested", "Leertaste beendet nie (#19)")
	assert_eq(_focused(game), game.start_menu.buttons["quit"], "Fokus bleibt auf „Beenden“")
	await _press(KEY_ENTER)
	assert_signal_emitted(game.start_menu, "quit_requested", "Enter auf „Beenden“ beendet")


func test_settings_from_menu_and_back() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	watch_signals(game)
	await run_for(0.2)
	game.start_menu.buttons["settings"].pressed.emit()
	assert_true(game.settings_menu.is_open(), "Einstellungen öffnen das Grafik- und Fenstermenü")
	assert_false(game.start_menu.find_child("Panel", true, false).visible, "Menüpunkte darunter verdeckt")
	await _press(KEY_ESCAPE)
	assert_false(game.settings_menu.is_open(), "Esc schließt")
	await run_for(0.05)
	assert_true(game.start_menu.find_child("Panel", true, false).visible)
	var status: Control = game.start_menu.find_child("Status", true, false)
	assert_gt(status.get_global_rect().position.y, game.start_menu.find_child("Panel", true, false).get_global_rect().end.y,
			"Radstatus bleibt unter dem Menü")
	assert_eq(_focused(game), game.start_menu.buttons["drive"], "Fokus zurück im Menü")
	assert_eq(game.state, "menu")
	game.start_menu.buttons["quit"].pressed.emit()
	assert_signal_emitted(game, "quit_requested", "Beenden im Startmenü")


func test_flow_title_ride_finish_menu_and_saved_ride_survives_restart() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 10.0))
	var game := _spawn_game(bus, _lap_length() - BEFORE_FINISH_M)
	await run_for(0.3)
	assert_eq(game.state, "menu")
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "finished", 5.0), "Fahrt bis ins Ziel")
	assert_string_contains(game.status_message(), "Enter: zurück ins Menü")
	assert_eq(game.save_game.rides().size(), 1, "Fahrt gleich im Ziel gespeichert")
	await _press(KEY_ENTER)
	assert_eq(game.state, "menu", "Ergebnis → Menü")
	assert_true(game.start_menu.visible)
	assert_false(game.hud.visible)
	assert_eq(game.save_game.rides().size(), 1, "nicht doppelt gespeichert")
	var ride: Dictionary = game.save_game.rides()[0]
	assert_true(ride["finished"])
	assert_eq(ride["laps"], 1)
	assert_eq(ride["mode"], SaveGame.MODE_ROUND_TRIP)
	assert_almost_eq(ride["distance_km"], BEFORE_FINISH_M / 1000.0, 0.0005)
	assert_almost_eq(ride["avg_cadence_rpm"], 90.0, 0.05)
	# Neustart: eine neue Hauptszene liest denselben Spielstand.
	var key: String = game.save_game.profile_key()
	var restarted := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	assert_eq(restarted.save_game.profile_key(), key, "derselbe Fahrer")
	assert_eq(restarted.save_game.version(), SaveGame.VERSION)
	assert_eq(restarted.save_game.rides().size(), 1, "Fahrt übersteht den Neustart")
	assert_eq(restarted.save_game.rides()[0]["distance_km"], ride["distance_km"])


func test_end_ride_from_settings_returns_to_menu_without_quitting() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 8.0))
	var game := _spawn_game(bus)
	watch_signals(game)
	await run_for(0.2)
	game.start_ride()
	assert_true(await run_until(func(): return game.state == "riding", 3.0))
	await run_for(0.5)
	await _press(KEY_ESCAPE)
	var end_ride: Button = game.settings_menu.find_child("EndRide", true, false)
	assert_true(end_ride.is_visible_in_tree(), "„Fahrt beenden“ in der Fahrt")
	end_ride.pressed.emit()
	assert_eq(game.state, "menu", "zurück im Menü")
	assert_false(game.settings_menu.is_open(), "Einstellungen zu")
	assert_true(game.start_menu.visible)
	assert_signal_not_emitted(game, "quit_requested", "Spiel läuft weiter")
	assert_eq(game.save_game.rides().size(), 1, "abgebrochene Fahrt gespeichert")
	assert_false(game.save_game.rides()[0]["finished"])
	assert_eq(game.save_game.rides()[0]["laps"], 0)
	assert_gt(game.save_game.rides()[0]["distance_km"], 0.0)
	assert_true(FileAccess.file_exists(SAVE_PATH), "Spielstand liegt auf der Platte")
	game.start_ride()
	assert_eq(game.model.distance_m, 20.0, "neue Fahrt beginnt wieder am Start")
	assert_eq(game.stats.ride_time_s, 0.0, "mit frischer Statistik")
	game.return_to_menu()
	assert_eq(game.state, "menu")
	assert_eq(game.save_game.rides().size(), 1, "Fahrt ohne gefahrene Zeit wird nicht gespeichert")


func test_wheel_status_texts() -> void:
	assert_string_contains(START_MENU.wheel_status(false, "disconnected", "")[0], "Bridge nicht erreichbar")
	assert_eq(START_MENU.wheel_status(true, "connected", "sim")[0], "Simulator läuft")
	assert_eq(START_MENU.wheel_status(true, "connected", "ble")[0], "Rad verbunden")
	assert_string_contains(START_MENU.wheel_status(true, "stale", "ble")[0], "Rad nicht verbunden")


func test_wheel_status_follows_bus() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim")] + [FakeBusServer.status("stale", "sim", ["CADENCE"], 0.6)])
	var game := _spawn_game(bus)
	var label: Label = game.start_menu.find_child("WheelStatus", true, false)
	assert_string_contains(label.text, "Bridge nicht erreichbar", "vor der Verbindung")
	assert_true(await run_until(func(): return label.text == "Simulator läuft", 3.0), "Simulator: %s" % label.text)
	assert_true(await run_until(func(): return label.text.contains("Rad nicht verbunden"), 3.0), "stale: %s" % label.text)
	bus.stop()
	assert_true(await run_until(func(): return label.text.contains("Bridge nicht erreichbar"), 3.0), "Bus weg")


## Startmenü in `viewport_size` (Pixel); `canvas_size` ≠ Null wie `stretch/mode="canvas_items"`. Längster Radstatus.
func _menu_in(viewport_size: Vector2i, canvas_size: Vector2i = Vector2i.ZERO) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	if canvas_size != Vector2i.ZERO:
		viewport.size_2d_override = canvas_size
		viewport.size_2d_override_stretch = true
	add_child_autofree(viewport)
	var menu := START_MENU_SCENE.instantiate()
	viewport.add_child(menu)
	await wait_process_frames(4)
	return menu


func _assert_menu_inside(menu: CanvasLayer, label: String) -> void:
	var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
	var checked := 0
	for control in menu.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		checked += 1
		var rect: Rect2 = control.get_global_rect()
		assert_true(screen.grow(0.5).encloses(rect), "%s: %s liegt im Fenster %s (%s)" % [label, control.name, screen, rect])
	assert_gt(checked, 10, "%s: alle Anzeigen geprüft" % label)
	var panel: Rect2 = menu.get_node("Layout").find_child("Panel", true, false).get_global_rect()
	assert_false(panel.intersects(menu.find_child("Subtitle", true, false).get_global_rect()), "%s: Menü frei vom Titel" % label)
	assert_false(panel.intersects(menu.find_child("Status", true, false).get_global_rect()), "%s: Menü frei vom Radstatus" % label)


func _check_both_pages(menu: CanvasLayer, label: String) -> void:
	_assert_menu_inside(menu, label)
	menu.show_page(true)
	await wait_process_frames(2)
	_assert_menu_inside(menu, label + " (Fahren)")
	menu.show_round_trip()
	await wait_process_frames(2)
	for key in ["laps", "direction", "time", "ghost"]:  # Richtung (#34) als viertes Feld
		assert_true((menu.options[key] as Control).is_visible_in_tree(), "%s: Feld %s auf der Seite „Rundfahrt“" % [label, key])
	_assert_menu_inside(menu, label + " (Rundfahrt)")
	menu.show_training()
	await wait_process_frames(2)
	_assert_menu_inside(menu, label + " (Training)")
	menu.show_arcade()
	await wait_process_frames(2)
	for key in ["tier", "cadence_min", "cadence_max"]:
		assert_true((menu.options[key] as Control).is_visible_in_tree(), "%s: Feld %s auf der Seite „Arcade“" % [label, key])
	_assert_menu_inside(menu, label + " (Arcade)")


func test_layout_fits_half_screen_window() -> void:
	await _check_both_pages(await _menu_in(Vector2i(960, 1040)), "960×1040")


func test_layout_fits_full_screen_sizes() -> void:
	await _check_both_pages(await _menu_in(Vector2i(1920, 1080)), "1920×1080")
	await _check_both_pages(await _menu_in(Vector2i(2560, 1440)), "2560×1440")
	await _check_both_pages(await _menu_in(Vector2i(1600, 900)), "1600×900")
	await _check_both_pages(await _menu_in(Vector2i(1152, 648)), "1152×648 (Godot-Standardfenster)")


func test_layout_fits_with_canvas_items_stretch() -> void:
	await _check_both_pages(await _menu_in(Vector2i(960, 1040), Vector2i(1920, 2080)), "canvas_items expand")
	await _check_both_pages(await _menu_in(Vector2i(960, 540), Vector2i(1920, 1080)), "canvas_items keep")
