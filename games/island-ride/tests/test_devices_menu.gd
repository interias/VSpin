## Geräteseite (Spec #64, P9) gegen den Fake-Bus: Menüpunkt öffnet und schließt die Seite; Suche (Befehl, Ergebnisse ohne
## Dubletten, Ende, Verlassen stoppt); Merken (HeartRateDevices, Bridge, Datei) und Vergessen; Live-Wert; Hinweise ohne
## Treffer; LTHR/Maximalpuls (speichern, abweisen, Zonenanzeige, Hinweis ohne Werte); Layout in 1152×648.
## Alle Dateien liegen unter TestIsolation.path, nie im echten `user://`.
extends "res://tests/support/bus_test.gd"

const DEVICES_MENU := preload("res://scenes/devices_menu.gd")
var SAVE_PATH := TestIsolation.path("test_devices_savegame.json")
var SETTINGS_PATH := TestIsolation.path("test_devices_settings.cfg")
const STRAP_ADDRESS := "F1:2A:33:44:55:66"
const WATCH_ADDRESS := "C8:11:22:33:44:55"


func after_each() -> void:
	super.after_each()
	for path in [SAVE_PATH, SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Hauptszene im Startmenü am Fake-Bus; Spielstand und Einstellungen in Testdateien. `devices` (optional) liegt vorher
## in der Einstellungsdatei.
func _spawn_game(bus: FakeBusServer, devices: HeartRateDevices = null) -> Node:
	if devices != null:
		devices.save_file(SETTINGS_PATH)
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = SETTINGS_PATH
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	assert_true(await run_until(func(): return game.bus.bus_connected, 3.0), "Bus verbunden")
	return game


func _open(game: Node) -> CanvasLayer:
	game.start_menu.buttons["devices"].pressed.emit()
	await wait_process_frames(2)
	return game.devices_menu


func _last_devices_sent(bus: FakeBusServer) -> Array:
	var sent := bus.received_of_type("set_heart_rate_devices")
	return sent[sent.size() - 1]["message"]["devices"] if not sent.is_empty() else []


func _sent_count(bus: FakeBusServer) -> int:
	return bus.received_of_type("set_heart_rate_devices").size()


func test_menu_entry_opens_and_closes_the_page() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	assert_true(game.start_menu.buttons.has("devices"), "Menüpunkt Geräte")
	assert_eq((game.start_menu.buttons["devices"] as Button).text, "Geräte")
	var menu := await _open(game)
	assert_true(menu.visible, "Seite offen")
	assert_false(game.start_menu.visible, "Startmenü tritt zurück")
	assert_true(menu.buttons["back"].has_focus(), "Fokus auf Zurück")
	menu.buttons["back"].pressed.emit()
	await wait_process_frames(2)
	assert_false(menu.visible)
	assert_true(game.start_menu.visible)
	assert_true(game.start_menu.buttons["devices"].has_focus(), "Fokus zurück auf dem Menüpunkt")
	await _open(game)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._input(escape)
	assert_false(menu.visible, "Esc schließt")


func test_page_shows_guides_for_strap_and_watch() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var menu := await _open(await _spawn_game(bus))
	var text: String = menu.page_text()
	assert_true(text.contains("Elektroden") and text.contains("anfeuchten") and text.contains("Hautkontakt"))
	assert_true(text.contains("Herzfrequenz übertragen") and text.contains("Wrist Heart Rate"), "Menüpfad der Uhr")
	assert_true(text.contains("ANT+"), "Empfehlung ANT+")
	assert_true(text.contains("HRM 600 gleichzeitig hält, ist nicht verifiziert"), "Verbindungszahl nicht als Tatsache")


func test_search_command_goes_out_and_results_are_unique() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.heart_rate_found(STRAP_ADDRESS, "HRM 600", -58, 0.6),
		FakeBusServer.heart_rate_found(WATCH_ADDRESS, "Forerunner 970", -75, 0.8),
		FakeBusServer.heart_rate_found(STRAP_ADDRESS, "HRM 600", -62, 1.0),
		FakeBusServer.heart_rate_found("AA:BB:CC:DD:EE:FF", null, -90, 1.1),
		FakeBusServer.heart_rate_search_ended("timeout", 1.4),
	])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.buttons["search_strap"].pressed.emit()
	assert_true(await run_until(func(): return not bus.received_of_type("start_heart_rate_search").is_empty(), 2.0))
	assert_eq(bus.received_of_type("start_heart_rate_search")[0]["message"]["duration_s"], 30.0)
	assert_true(await run_until(func(): return menu.search_ended == "timeout", 4.0), "Ende angezeigt")
	assert_eq(menu.found.size(), 3, "drei Geräte, Dublette nur einmal")
	assert_eq(menu.found[STRAP_ADDRESS]["rssi"], -62, "Signalstärke aktualisiert")
	var rows: Node = menu.find_child("CardStrap", true, false).find_child("Results", true, false)
	assert_eq(rows.get_child_count(), 3, "drei Zeilen")
	var text: String = menu.page_text()
	assert_true(text.contains("HRM 600 · Signal -62 dBm (gut)"), text)
	assert_true(text.contains("Unbenanntes Gerät"), "Gerät ohne Namen")
	assert_true(text.contains("Suche beendet · 3 Geräte gefunden"), "Suchende")


func test_leaving_the_page_stops_the_search() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.buttons["search_watch"].pressed.emit()
	assert_true(await run_until(func(): return not bus.received_of_type("start_heart_rate_search").is_empty(), 2.0))
	menu.close()
	assert_true(await run_until(func(): return not bus.received_of_type("stop_heart_rate_search").is_empty(), 2.0),
			"Verlassen stoppt die Suche")


func test_close_without_search_sends_no_stop() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.close()
	await run_for(0.3)
	assert_eq(bus.received_of_type("stop_heart_rate_search").size(), 0)


func test_search_is_disabled_without_bus() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	bus.stop()
	game.quit_on_request = false
	game.settings_path = SETTINGS_PATH
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	await run_for(0.3)
	var menu := await _open(game)
	assert_true(menu.buttons["search_strap"].disabled and menu.buttons["search_watch"].disabled)
	assert_true(menu.page_text().contains("Bridge nicht erreichbar"))


func test_remember_sends_to_bridge_and_saves() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.heart_rate_found(STRAP_ADDRESS, "HRM 600", -58, 0.6),
	])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.buttons["search_strap"].pressed.emit()
	assert_true(await run_until(func(): return menu.found.has(STRAP_ADDRESS), 3.0))
	var row: HBoxContainer = menu.find_child("Result" + STRAP_ADDRESS.replace(":", ""), true, false)
	row.find_children("*", "Button", true, false)[0].pressed.emit()
	assert_eq(game.heart_rate_devices.device("strap")["address"], STRAP_ADDRESS, "in HeartRateDevices")
	assert_true(await run_until(func(): return _last_devices_sent(bus).size() == 1, 2.0), "an die Bridge")
	assert_eq(_last_devices_sent(bus)[0], {"address": STRAP_ADDRESS, "name": "HRM 600", "role": "strap"})
	assert_true(HeartRateDevices.load_file(SETTINGS_PATH).has_device("strap"), "gespeichert")
	assert_true(menu.page_text().contains("Gemerkt: HRM 600"))


func test_forget_removes_device_everywhere() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var devices := HeartRateDevices.new()
	devices.remember("watch", WATCH_ADDRESS, "Forerunner 970")
	var game := await _spawn_game(bus, devices)
	var menu := await _open(game)
	assert_false(menu.buttons["forget_watch"].disabled)
	assert_true(menu.buttons["forget_strap"].disabled, "nichts zu vergessen")
	menu.buttons["forget_watch"].pressed.emit()
	assert_false(game.heart_rate_devices.has_device("watch"))
	assert_false(HeartRateDevices.load_file(SETTINGS_PATH).has_device("watch"), "Datei")
	assert_true(await run_until(func(): return _sent_count(bus) >= 2 and _last_devices_sent(bus).is_empty(), 2.0),
			"leere Liste an die Bridge")
	assert_true(menu.page_text().contains("Kein Gerät gemerkt."))


func test_live_value_on_the_card_of_the_connected_device() -> void:
	var strap := FakeBusServer.heart_rate_device(STRAP_ADDRESS, "HRM 600", "strap")
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
				FakeBusServer.heart_rate_block("connected", strap)),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 142}),
	])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	assert_true(await run_until(func(): return game.bus.has_heart_rate(), 2.0))
	await wait_process_frames(2)
	assert_eq(menu.labels["live_strap"].text, "Verbunden · 142 bpm")
	assert_eq(menu.labels["live_watch"].text, "nicht verbunden", "andere Karte")


func test_live_value_shows_zone_with_profile() -> void:
	var strap := FakeBusServer.heart_rate_device(STRAP_ADDRESS, "HRM 600", "strap")
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
				FakeBusServer.heart_rate_block("connected", strap)),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 160}),
	])
	var game := await _spawn_game(bus)
	game.save_game.set_heart_rate_profile(170, 0)
	var menu := await _open(game)
	assert_true(await run_until(func(): return game.bus.has_heart_rate(), 2.0))
	await wait_process_frames(2)
	var zone: int = game.save_game.heart_rate_zones().zone_for(160)
	assert_eq(menu.labels["live_strap"].text, "Verbunden · 160 bpm (Z%d)" % zone)


func test_remembered_device_waits_when_not_connected() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
			FakeBusServer.heart_rate_block("disconnected"))])
	var devices := HeartRateDevices.new()
	devices.remember("watch", WATCH_ADDRESS, "Forerunner 970")
	var game := await _spawn_game(bus, devices)
	assert_true(await run_until(func(): return game.bus.heart_rate_state == "disconnected", 3.0))
	var menu := await _open(game)
	assert_eq(menu.labels["live_watch"].text, "wartet auf das Gerät …")
	assert_eq(menu.labels["live_strap"].text, "nicht verbunden")
	var hint: String = menu.labels["hint_watch"].text
	assert_true(hint.contains("Übertragung auf der Uhr"), hint)
	assert_true(hint.contains("anderen App") and hint.contains("Bluetooth"), hint)


func test_hints_after_search_without_result() -> void:
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.heart_rate_search_ended("timeout", 0.8)])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	assert_eq(menu.labels["hint_strap"].text, "", "vor der Suche kein Hinweis")
	menu.buttons["search_strap"].pressed.emit()
	assert_true(await run_until(func(): return menu.search_ended == "timeout", 3.0))
	var hint: String = menu.labels["hint_strap"].text
	assert_true(hint.contains("nicht angelegt") and hint.contains("trocken"), hint)
	assert_true(hint.contains("anderen App") and hint.contains("Bluetooth"), hint)
	assert_true(menu.labels["hint_strap"].visible)
	assert_eq(menu.labels["hint_watch"].text, "", "nur die Karte, auf der gesucht wurde")


func test_no_hint_when_search_found_something() -> void:
	var bus := start_fake_bus([FakeBusServer.status(),
			FakeBusServer.heart_rate_found(STRAP_ADDRESS, "HRM 600", -58, 0.4),
			FakeBusServer.heart_rate_search_ended("timeout", 0.8)])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.buttons["search_strap"].pressed.emit()
	assert_true(await run_until(func(): return menu.search_ended == "timeout", 3.0))
	assert_eq(menu.labels["hint_strap"].text, "")


func test_profile_values_are_saved_in_the_save_game() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.lthr_edit.text = "168"
	menu.max_hr_edit.text = "190"
	menu.buttons["save_profile"].pressed.emit()
	assert_eq(game.save_game.lthr_bpm(), 168)
	assert_eq(game.save_game.max_hr_bpm(), 190)
	var reloaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(reloaded.lthr_bpm(), 168, "auf der Platte")
	assert_eq(reloaded.max_hr_bpm(), 190)
	assert_eq(menu.labels["profile_message"].text, "Gespeichert.")


func test_implausible_values_are_rejected() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	game.save_game.set_heart_rate_profile(165, 0)
	for pair in [["300", ""], ["50", ""], ["abc", ""], ["170", "99"], ["170", "231"], ["16.5", ""]]:
		menu.lthr_edit.text = pair[0]
		menu.max_hr_edit.text = pair[1]
		assert_false(menu.save_profile(), "abgewiesen: %s / %s" % pair)
		assert_eq(game.save_game.lthr_bpm(), 165, "Wert unverändert")
	assert_true(menu.labels["profile_message"].text.begins_with("Nicht gespeichert"))
	assert_false(FileAccess.file_exists(SAVE_PATH), "nichts geschrieben")


func test_zones_are_shown_from_the_profile() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.lthr_edit.text = "170"
	menu.max_hr_edit.text = ""
	assert_true(menu.save_profile())
	await wait_process_frames(2)  # entfernte Zeilen räumt queue_free am Bildende ab
	var zones := HeartRateZones.new(170, 0)
	for zone in range(1, 6):
		var label: Label = menu.find_child("Zone%d" % zone, true, false)
		assert_not_null(label, "Z%d" % zone)
		var span := zones.zone_range(zone)
		assert_true(label.text.contains(str(span.x)), label.text)
		assert_eq(label.get_theme_color("font_color"), HeartRateZones.color_for(zone), "Zonenfarbe Z%d" % zone)
	assert_true(menu.find_child("Zone5", true, false).text.contains("ab "), "Z5 offen")
	assert_false(menu.labels["no_zones"].visible)
	assert_true(menu.labels["zone_source"].text.contains("LTHR"))


func test_hint_without_values_is_shown_until_a_value_is_entered() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	assert_true(menu.labels["no_zones"].visible, "ohne beide Werte")
	assert_true(menu.labels["no_zones"].text.contains("ohne Zonen"))
	assert_eq(menu.find_child("Zone1", true, false), null, "keine Zonenzeilen")
	menu.max_hr_edit.text = "190"
	assert_true(menu.save_profile())
	assert_false(menu.labels["no_zones"].visible)
	assert_true(menu.labels["zone_source"].text.contains("Maximalpuls"))
	menu.max_hr_edit.text = ""
	menu.lthr_edit.text = ""
	assert_true(menu.save_profile(), "leer = nicht gesetzt")
	assert_true(menu.labels["no_zones"].visible)


func test_fields_show_the_stored_values() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	game.save_game.set_heart_rate_profile(160, 185)
	var menu := await _open(game)
	assert_eq(menu.lthr_edit.text, "160")
	assert_eq(menu.max_hr_edit.text, "185")
	assert_true(menu.page_text().contains("Watch Settings > User Profile"), "Hinweis, wo die Werte stehen")
	assert_true(menu.page_text().contains("nicht verifiziert"), "Garmin Connect ungeprüft")


func test_signal_text() -> void:
	assert_eq(DEVICES_MENU.signal_quality(-55), "stark")
	assert_eq(DEVICES_MENU.signal_quality(-65), "gut")
	assert_eq(DEVICES_MENU.signal_quality(-75), "mittel")
	assert_eq(DEVICES_MENU.signal_quality(-95), "schwach")
	assert_eq(DEVICES_MENU.found_text("", -70), "Unbenanntes Gerät · Signal -70 dBm (gut)")


## Seite in `viewport_size` (Pixel) mit vollem Inhalt: Geräte gemerkt, Werte gesetzt, Suchergebnisse und Hinweise.
func _menu_in(viewport_size: Vector2i) -> CanvasLayer:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
			FakeBusServer.heart_rate_block("disconnected"))])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var devices := HeartRateDevices.new()
	devices.remember("strap", STRAP_ADDRESS, "HRM 600")
	devices.remember("watch", WATCH_ADDRESS, "Forerunner 970")
	var save := SaveGame.new()
	save.set_heart_rate_profile(168, 190)
	var menu: CanvasLayer = DEVICES_MENU.new()
	viewport.add_child(menu)
	menu.open(client, devices, save)
	menu.start_search("strap")
	for i in range(4):
		client.heart_rate_found.emit("AA:BB:CC:DD:EE:0%d" % i, "HRM Gerät %d" % i, -60 - i * 8)
	client.heart_rate_search_ended.emit("timeout")
	await wait_process_frames(4)
	return menu


func _assert_inside(menu: CanvasLayer, label: String) -> void:
	var panel: Rect2 = menu.find_child("Panel", true, false).get_global_rect()
	var back: Rect2 = menu.buttons["back"].get_global_rect()
	var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
	assert_true(screen.grow(0.5).encloses(panel), "%s: Inhalt im Fenster %s (%s)" % [label, screen, panel])
	assert_true(screen.grow(0.5).encloses(back), "%s: Zurück im Fenster" % label)
	assert_false(back.intersects(panel), "%s: Zurück frei vom Inhalt" % label)
	assert_gt(panel.size.y, 200.0, "%s: Platz für den Inhalt" % label)
	var scroll: ScrollContainer = menu.find_child("Scroll", true, false)
	var area := scroll.get_global_rect()
	for cell in scroll.find_children("*", "Label", true, false):
		if not cell.is_visible_in_tree():
			continue
		var rect: Rect2 = cell.get_global_rect()
		assert_true(rect.position.x >= area.position.x - 0.5 and rect.end.x <= area.end.x + 0.5,
				"%s: „%s“ seitlich im Inhalt (%s in %s)" % [label, cell.text.left(30), rect, area])
	var content: Control = scroll.get_node("Content")
	if content.size.y > area.size.y:
		var bar := scroll.get_v_scroll_bar()
		assert_true(bar.visible, "%s: zu lang → scrollt" % label)
		assert_almost_eq(bar.max_value, content.size.y, 1.0, "%s: alles erreichbar" % label)


func test_layout_fits_low_window() -> void:
	var menu := await _menu_in(Vector2i(1152, 648))
	_assert_inside(menu, "1152×648")
	assert_true((menu.find_child("Scroll", true, false) as ScrollContainer).get_v_scroll_bar().visible, "scrollt")


func test_layout_fits_half_screen_and_full_screen_windows() -> void:
	_assert_inside(await _menu_in(Vector2i(960, 1040)), "960×1040")
	_assert_inside(await _menu_in(Vector2i(1920, 1080)), "1920×1080")
