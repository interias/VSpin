## Verbindungsfenster (Spec #75, P4) gegen den Fake-Bus: Kacheln je Rolle (Zustand, Gerät, Live-Wert, Signal), Suche,
## Merken und Vergessen für Trainer und Controller (Bridge, Datei), Start ohne Dialog bei gemerktem Trainer, mit Dialog
## ohne Trainer bei `source="ble"`, kein Dialog beim Simulator; Knopf im Menü und im HUD, Taste V; Hinweis und Knopf
## „Steuerung zurückholen“ bei `lost`/`error`, Anzeige `read_only`, Controller „gesperrt“; alte Einstellungen aus #64
## bleiben gültig; Layout in 1152×648, 960×1040 und 1920×1080.
## Alle Dateien liegen unter TestIsolation.path, nie im echten `user://`.
extends "res://tests/support/bus_test.gd"

const DEVICES_MENU := preload("res://scenes/devices_menu.gd")
var SAVE_PATH := TestIsolation.path("test_connections_savegame.json")
var SETTINGS_PATH := TestIsolation.path("test_connections_settings.cfg")
const KICKR := "AA:00:00:00:10:01"
const LEFT := "CC:00:00:00:00:08"
const STRAP_ADDRESS := "F1:2A:33:44:55:66"


func after_each() -> void:
	super.after_each()
	for path in [SAVE_PATH, SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Hauptszene im Startmenü am Fake-Bus; `source` wie `config.cfg [bridge] source`, `trainer` (optional) liegt vorher in
## der Einstellungsdatei.
func _spawn_game(bus: FakeBusServer, source: String = "sim", trainer: RoleDevice = null) -> Node:
	if trainer != null:
		trainer.save_file(SETTINGS_PATH)
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.config.bridge_source = source
	game.quit_on_request = false
	game.settings_path = SETTINGS_PATH
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	assert_true(await run_until(func(): return game.bus.bus_connected, 3.0), "Bus verbunden")
	await wait_process_frames(2)
	return game


func _open(game: Node) -> CanvasLayer:
	game.start_menu.buttons["devices"].pressed.emit()
	await wait_process_frames(2)
	return game.devices_menu


func _last_sent(bus: FakeBusServer, kind: String) -> Variant:
	var sent := bus.received_of_type("set_devices").filter(func(m): return m["message"]["kind"] == kind)
	return sent[sent.size() - 1]["message"]["devices"] if not sent.is_empty() else null


func _ble_status(at: float = 0.0, control: String = "active", fields: Dictionary = {}) -> Dictionary:
	var step := FakeBusServer.status("connected", "ble", ["CADENCE", "POWER", "SPEED"], at, {}, control,
			{"address": KICKR, "name": "KICKR CORE 2"}, FakeBusServer.controller_block(),
			{"trainer": -55})
	step["send"].merge(fields, true)
	return step


func _tile(menu: CanvasLayer, kind: String) -> Array:
	return menu.tile_lines(kind)


# --- Kacheln --------------------------------------------------------------------------------------


func test_window_has_a_tile_per_role_with_state_device_live_value_and_signal() -> void:
	var strap := FakeBusServer.heart_rate_device(STRAP_ADDRESS, "HRM 600", "strap")
	var status := _ble_status()
	status["send"]["heart_rate"] = FakeBusServer.heart_rate_block("connected", strap)
	status["send"]["controller"] = FakeBusServer.controller_block("connected",
			{"address": LEFT, "name": "Zwift SF2", "side": "left"}, 81)
	status["send"]["signal"] = {"trainer": -55, "heart_rate": -63, "controller": -71}
	var bus := start_fake_bus([status, FakeBusServer.telemetry(88.0, 0.1, {"power_w": 182.0,
			"power_estimated": false, "heart_rate": 142})])
	var game := await _spawn_game(bus, "ble")
	var menu := await _open(game)
	assert_eq((game.get_node("DevicesMenu").find_child("Tiles", true, false) as Node).get_child_count(), 3)
	assert_true(await run_until(func(): return game.bus.has_heart_rate(), 2.0))
	await wait_process_frames(2)
	assert_eq(_tile(menu, "trainer"), [["Verbunden", DEVICES_MENU.COLOR_OK], "KICKR CORE 2", "182 W · 88 rpm",
			"Signal -55 dBm (stark)"])
	assert_eq(_tile(menu, "heart_rate"), [["Verbunden", DEVICES_MENU.COLOR_OK], "HRM 600 (Brustgurt)", "142 bpm",
			"Signal -63 dBm (gut)"])
	assert_eq(_tile(menu, "controller"), [["Verbunden", DEVICES_MENU.COLOR_OK], "Zwift SF2 (links)", "Akku 81 %",
			"Signal -71 dBm (mittel)"])
	var text: String = menu.tiles_text()
	for line in ["Trainer", "Puls", "Controller", "VSpin steuert den Widerstand", "Akku 81 %", "142 bpm"]:
		assert_true(text.contains(line), "Kachel zeigt „%s“: %s" % [line, text])
	assert_false(menu.buttons["reclaim"].visible, "kein Zurückholen bei active")


func test_simulator_tile_needs_no_trainer_and_trainer_search_is_off() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.1, 2.0))
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	await run_for(0.3)
	assert_eq(_tile(menu, "trainer")[0][0], "Simulator – kein Trainer nötig")
	assert_eq(_tile(menu, "trainer")[2], "Kadenz 80 rpm")
	assert_true(menu.buttons["search_trainer"].disabled, "mit dem Simulator wird kein Trainer gesucht")
	assert_true(menu.labels["sim_note"].visible)
	assert_eq(_tile(menu, "controller"), [["Kein Controller gemerkt – unten suchen", DEVICES_MENU.COLOR_DIM], "",
			"Akku —", "Signal —"], "Controller ohne Akku: —")
	menu.start_role_search("trainer")
	await run_for(0.2)
	assert_eq(bus.received_of_type("start_device_search").size(), 0)


func test_tile_heading_jumps_to_the_setup_of_its_role() -> void:
	var bus := start_fake_bus([_ble_status()])
	var game := await _spawn_game(bus, "ble", _remembered_kickr())
	var menu := await _open(game)
	menu.buttons["tile_controller"].pressed.emit()
	await wait_process_frames(2)
	assert_true(menu.buttons["search_controller"].has_focus(), "Fokus auf „Suchen“ der Controllerkarte")
	menu.buttons["tile_heart_rate"].pressed.emit()
	await wait_process_frames(2)
	assert_true(menu.buttons["search_strap"].has_focus(), "Puls: die Karte Brustgurt")


# --- Suche, Merken, Vergessen ---------------------------------------------------------------------


func test_trainer_search_remember_and_forget() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status("disconnected", "ble", ["CADENCE"]),
		FakeBusServer.device_found("trainer", KICKR, "KICKR CORE 2", -55, 0.6),
		FakeBusServer.device_found("trainer", "AA:00:00:00:10:02", null, -80, 0.7),
		FakeBusServer.device_found("trainer", KICKR, "KICKR CORE 2", -52, 0.9),
		FakeBusServer.device_search_ended("trainer", "timeout", 1.2),
	])
	var game := await _spawn_game(bus, "ble")
	var menu: CanvasLayer = game.devices_menu
	assert_true(menu.visible, "ohne gemerkten Trainer offen")
	assert_eq(_last_sent(bus, "trainer"), [], "leere Liste: kein Trainer verbindet sich von selbst")
	assert_false(menu.buttons["search_trainer"].disabled)
	menu.buttons["search_trainer"].pressed.emit()
	assert_true(await run_until(func(): return not bus.received_of_type("start_device_search").is_empty(), 2.0))
	assert_eq(bus.received_of_type("start_device_search")[0]["message"],
			{"v": 0.0, "type": "start_device_search", "kind": "trainer", "duration_s": 30.0})
	assert_true(await run_until(func(): return menu.role_search_ended["trainer"] == "timeout", 4.0), "Ende angezeigt")
	assert_eq(menu.role_found["trainer"].size(), 2, "zwei Trainer, Dublette nur einmal")
	var text: String = menu.page_text()
	assert_true(text.contains("KICKR CORE 2 · Signal -52 dBm (stark)"), text)
	assert_true(text.contains("Suche beendet · 2 Geräte gefunden"), text)
	var row: HBoxContainer = menu.find_child("CardTrainer", true, false).find_child("Result" + KICKR.replace(":", ""),
			true, false)
	row.find_children("*", "Button", true, false)[0].pressed.emit()
	assert_eq(game.trainer_device.device(), {"address": KICKR, "name": "KICKR CORE 2"})
	assert_true(await run_until(func(): return _last_sent(bus, "trainer") == [{"address": KICKR, "name": "KICKR CORE 2"}],
			2.0), "an die Bridge")
	assert_true(RoleDevice.load_file("trainer", SETTINGS_PATH).has_device(), "gespeichert")
	assert_true(menu.page_text().contains("Gemerkt: KICKR CORE 2"))
	menu.buttons["forget_trainer"].pressed.emit()
	assert_false(game.trainer_device.has_device())
	assert_false(RoleDevice.load_file("trainer", SETTINGS_PATH).has_device(), "aus der Datei")
	assert_true(await run_until(func(): return _last_sent(bus, "trainer") == [], 2.0), "leere Liste an die Bridge")
	assert_true(menu.page_text().contains("Kein Trainer gemerkt."))


func test_controller_search_shows_the_side_and_remembers_it() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.device_found("controller", "CC:00:00:00:00:07", "Zwift SF2", -66, 0.5, "right"),
		FakeBusServer.device_found("controller", LEFT, "Zwift SF2", -60, 0.6, "left"),
		FakeBusServer.device_search_ended("controller", "timeout", 1.0),
	])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.buttons["search_controller"].pressed.emit()
	assert_true(await run_until(func(): return menu.role_search_ended["controller"] == "timeout", 3.0))
	var text: String = menu.page_text()
	assert_true(text.contains("Zwift SF2 (links) · Signal -60 dBm (stark)"), text)
	assert_true(text.contains("Zwift SF2 (rechts)"), text)
	assert_eq(bus.received_of_type("start_device_search")[0]["message"]["kind"], "controller")
	menu.remember_role("controller", LEFT)
	assert_true(await run_until(func(): return _last_sent(bus, "controller") == [
			{"address": LEFT, "name": "Zwift SF2", "side": "left"}], 2.0), "mit Seite an die Bridge")
	assert_eq(RoleDevice.load_file("controller", SETTINGS_PATH).device()["side"], "left", "Seite gespeichert")
	assert_true(menu.page_text().contains("Gemerkt: Zwift SF2 (links)"))


func test_search_without_result_shows_hints_and_closing_stops_running_searches() -> void:
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.device_search_ended("controller", "timeout", 0.6)])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	assert_eq(menu.labels["hint_controller"].text, "", "vor der Suche kein Hinweis")
	menu.start_role_search("controller")
	assert_true(await run_until(func(): return menu.role_search_ended["controller"] == "timeout", 3.0))
	var hint: String = menu.labels["hint_controller"].text
	assert_true(hint.begins_with("Kein Controller gefunden.") and hint.contains("Taste drücken"), hint)
	menu.start_role_search("controller")
	assert_true(await run_until(func(): return bus.received_of_type("start_device_search").size() == 2, 2.0))
	menu.close()
	assert_true(await run_until(func(): return not bus.received_of_type("stop_device_search").is_empty(), 2.0),
			"Schließen stoppt die laufende Suche")
	assert_eq(bus.received_of_type("stop_device_search")[0]["message"]["kind"], "controller")


func test_bus_loss_ends_a_role_search() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	menu.start_role_search("controller")
	assert_true(await run_until(func(): return menu.page_text().contains("Suche läuft"), 2.0))
	bus.stop()
	assert_true(await run_until(func(): return menu.role_search_ended["controller"] == "bus_lost", 4.0))
	assert_true(menu.page_text().contains("Suche abgebrochen (Verbindung zur Bridge verloren)"))
	assert_eq(_tile(menu, "trainer")[0][0], "Bridge nicht erreichbar")


# --- Start ohne und mit Dialog --------------------------------------------------------------------


func _remembered_kickr() -> RoleDevice:
	var trainer := RoleDevice.new("trainer")
	trainer.remember(KICKR, "KICKR CORE 2")
	return trainer


func test_start_without_dialog_with_a_remembered_trainer() -> void:
	var bus := start_fake_bus([_ble_status()])
	var game := await _spawn_game(bus, "ble", _remembered_kickr())
	assert_false(game.devices_menu.visible, "Background Pairing: kein Dialog")
	assert_true(game.start_menu.visible)
	assert_true(await run_until(func(): return _last_sent(bus, "trainer") == [{"address": KICKR, "name": "KICKR CORE 2"}],
			2.0), "der gemerkte Trainer geht beim Verbinden an die Bridge")
	assert_eq(_last_sent(bus, "controller"), [], "auch die (leere) Controllerliste")
	assert_eq(bus.received_of_type("set_heart_rate_devices").size(), 1, "die Pulsliste wie bisher")


func test_start_with_dialog_without_trainer_at_source_ble() -> void:
	var bus := start_fake_bus([FakeBusServer.status("disconnected", "ble", ["CADENCE"])])
	var game := await _spawn_game(bus, "ble")
	assert_true(game.connections_needed())
	assert_true(game.devices_menu.visible, "erster Start: das Fenster öffnet von selbst")
	assert_false(game.start_menu.visible, "das Startmenü tritt zurück")
	assert_true(game.devices_menu.buttons["back"].has_focus())
	assert_eq(_tile(game.devices_menu, "trainer")[0][0], "Kein Trainer gemerkt – unten suchen")
	game.devices_menu.close()
	await wait_process_frames(2)
	assert_true(game.start_menu.visible, "Schließen führt ins Startmenü")


func test_no_dialog_with_the_simulator() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus, "sim")
	assert_false(game.connections_needed())
	assert_false(game.devices_menu.visible, "der Simulator braucht keinen Trainer")


func test_settings_from_64_stay_valid() -> void:
	# Eine Einstellungsdatei aus #64: nur Pulsgeräte (und Grafik). Kein Trainer, kein Controller, Puls unverändert.
	var old := ConfigFile.new()
	old.set_value("heart_rate", "strap_address", STRAP_ADDRESS)
	old.set_value("heart_rate", "strap_name", "HRM 600")
	old.set_value("graphics", "aa", "fxaa")
	old.save(SETTINGS_PATH)
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	assert_eq(game.heart_rate_devices.device("strap")["address"], STRAP_ADDRESS)
	assert_false(game.trainer_device.has_device())
	assert_false(game.controller_device.has_device())
	game.trainer_device.remember(KICKR, "KICKR CORE 2")
	game.apply_role_device("trainer")
	var saved := ConfigFile.new()
	assert_eq(saved.load(SETTINGS_PATH), OK)
	assert_eq(saved.get_value("heart_rate", "strap_address"), STRAP_ADDRESS, "[heart_rate] bleibt")
	assert_eq(saved.get_value("graphics", "aa"), "fxaa", "die Grafik bleibt")
	assert_eq(saved.get_value("trainer", "address"), KICKR, "[trainer] kommt dazu")
	assert_true(HeartRateDevices.load_file(SETTINGS_PATH).has_device("strap"))


# --- Während der Fahrt: HUD-Knopf und Taste -------------------------------------------------------


func test_hud_button_and_key_open_the_window_while_the_ride_goes_on() -> void:
	var bus := start_fake_bus([_ble_status()] + FakeBusServer.steady_cadence(90.0, 0.1, 8.0))
	var game := spawn_ride(bus)
	assert_true(await run_until(func(): return game.state == "riding", 3.0))
	var button: Button = game.hud.connections_button
	assert_eq(button.text, "Verbindungen (V)")
	assert_eq(button.focus_mode, Control.FOCUS_NONE, "nur Klick: Leertaste und Enter lösen ihn nie aus")
	button.pressed.emit()
	await wait_process_frames(2)
	assert_true(game.devices_menu.visible, "HUD-Knopf öffnet das Fenster")
	assert_false(game.start_menu.visible, "kein Startmenü während der Fahrt")
	var distance: float = game.model.distance_m
	await run_for(0.5)
	assert_eq(game.state, "riding", "die Fahrt läuft weiter wie bei den Einstellungen")
	assert_gt(game.model.distance_m, distance)
	await press_key(KEY_V)
	await wait_process_frames(2)
	assert_false(game.devices_menu.visible, "V schließt")
	assert_false(game.start_menu.visible, "zurück in die Fahrt")
	await press_key(KEY_V)
	await wait_process_frames(2)
	assert_true(game.devices_menu.visible, "V öffnet")
	var view: String = game.camera_view
	await press_key(KEY_C)
	assert_eq(game.camera_view, view, "Kamera wechselt nicht, solange das Fenster offen ist")


func test_space_stays_the_companion_talk_key_and_v_is_free() -> void:
	var bindings: Dictionary = MAIN_SCENE.instantiate().get_script().get_script_constant_map()["KEY_BINDINGS"]
	assert_eq(bindings["ride_devices"], [KEY_V])
	assert_eq(bindings["companion_ptt"], [KEY_SPACE], "Leertaste unverändert: Sprechtaste des Begleiters (#76)")
	for action in bindings:
		if action != "companion_ptt":
			assert_false(bindings[action].has(KEY_SPACE), "Leertaste nur für die Sprechtaste (%s)" % action)
	for action in bindings:
		if action != "ride_devices":
			assert_false(bindings[action].has(KEY_V), "V nur für das Verbindungsfenster (%s)" % action)


func test_key_v_does_nothing_in_the_start_menu() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := await _spawn_game(bus)
	await press_key(KEY_V)
	await wait_process_frames(2)
	assert_false(game.devices_menu.visible, "im Startmenü öffnet der Menüpunkt")


# --- Steuerung, Nur lesen, Controller gesperrt ----------------------------------------------------


func test_lost_shows_the_hint_and_the_reclaim_button_which_sends_only_on_click() -> void:
	var bus := start_fake_bus([_ble_status(0.0, "lost")])
	bus.replies["reclaim_trainer_control"] = FakeBusServer.ack("reclaim_trainer_control", false, "control_lost")
	var game := await _spawn_game(bus, "ble", _remembered_kickr())
	var menu := await _open(game)
	await wait_process_frames(2)
	assert_true(menu.buttons["reclaim"].visible, "Knopf bei lost")
	assert_eq(menu.buttons["reclaim"].text, "Steuerung zurückholen")
	assert_true(menu.tiles_text().contains("Eine andere App steuert den Trainer"), menu.tiles_text())
	await run_for(0.3)
	assert_eq(bus.received_of_type("reclaim_trainer_control").size(), 0, "von selbst wird nichts angefordert")
	menu.buttons["reclaim"].pressed.emit()
	assert_true(await run_until(func(): return bus.received_of_type("reclaim_trainer_control").size() == 1, 2.0))
	assert_true(await run_until(func(): return menu.reclaim_message.contains("lehnt ab"), 2.0), "Antwort angezeigt")
	await wait_process_frames(2)
	assert_true(menu.labels["reclaim_message"].visible)


func test_reclaim_button_also_on_error_and_not_when_active() -> void:
	var bus := start_fake_bus([_ble_status(0.0, "error"), _ble_status(1.0, "active")])
	var game := await _spawn_game(bus, "ble", _remembered_kickr())
	var menu := await _open(game)
	await wait_process_frames(2)
	assert_true(menu.buttons["reclaim"].visible, "Knopf bei error")
	assert_true(await run_until(func(): return game.bus.trainer_control == "active", 3.0))
	await wait_process_frames(2)
	assert_false(menu.buttons["reclaim"].visible, "weg, sobald VSpin steuert")


func test_read_only_is_shown_on_the_trainer_tile() -> void:
	var bus := start_fake_bus([_ble_status(0.0, "read_only")])
	var game := await _spawn_game(bus, "ble", _remembered_kickr())
	var menu := await _open(game)
	await wait_process_frames(2)
	assert_eq(menu.control_line()[0], "Nur lesen (config.cfg [bridge] trainer_read_only)")
	assert_true(menu.tiles_text().contains("Nur lesen"))
	assert_false(menu.buttons["reclaim"].visible, "im Nur-lesen-Modus nichts zurückzuholen")


func test_locked_controller_shows_the_zwift_hint_instead_of_an_error() -> void:
	var status := FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {}, "", {},
			FakeBusServer.controller_block("locked", {"address": LEFT, "name": "Zwift SF2", "side": "left"}, 64),
			{"controller": -64})
	var bus := start_fake_bus([status])
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	await wait_process_frames(2)
	assert_eq(game.bus.controller_state, "locked")
	assert_eq(_tile(menu, "controller"), [["gesperrt – einmal in Zwift verbinden (gilt ca. 24 h)",
			DEVICES_MENU.COLOR_WARN], "Zwift SF2 (links)", "Akku 64 %", "Signal -64 dBm (gut)"])
	assert_eq(game.bus.controller_handshake, "none", "gesperrt: kein Handshake")


func test_controller_tile_per_handshake_state() -> void:
	# Spec #89: Verlangt der Controller Verschlüsselung, sagt die Kachel das; sonst bleibt sie „Verbunden“.
	assert_eq(DEVICES_MENU.CONTROLLER_ENCRYPTED_TEXT,
			"Controller verlangt Verschlüsselung – Tasten in VSpin noch nicht nutzbar")
	var device := {"address": LEFT, "name": "Zwift SF2", "side": "left"}
	var cases := [["encrypted", [DEVICES_MENU.CONTROLLER_ENCRYPTED_TEXT, DEVICES_MENU.COLOR_WARN]],
			["answered", ["Verbunden", DEVICES_MENU.COLOR_OK]], ["no_answer", ["Verbunden", DEVICES_MENU.COLOR_OK]],
			["none", ["Verbunden", DEVICES_MENU.COLOR_OK]]]
	var script := []
	for i in range(cases.size()):
		script.append(FakeBusServer.status("connected", "sim", ["CADENCE"], 0.4 * i, {}, "", {},
				FakeBusServer.controller_block("connected", device, 81, cases[i][0]), {"controller": -61}))
	var bus := start_fake_bus(script)
	var game := await _spawn_game(bus)
	var menu := await _open(game)
	for entry in cases:
		assert_true(await run_until(func(): return game.bus.controller_handshake == entry[0], 3.0), "Stand %s" % entry[0])
		await wait_process_frames(2)
		assert_eq(_tile(menu, "controller"), [entry[1], "Zwift SF2 (links)", "Akku 81 %", "Signal -61 dBm (gut)"],
				"Kachel bei %s" % entry[0])


# --- Layout ---------------------------------------------------------------------------------------


## Fenster in `viewport_size` (Pixel) mit vollem Inhalt: alle Rollen gemerkt, Trainer `lost` (Knopf sichtbar),
## Controller gesperrt (oder `controller` als Block, z. B. verbunden mit Verschlüsselungshinweis), Suchergebnisse.
func _window_in(viewport_size: Vector2i, controller_block: Dictionary = {}) -> CanvasLayer:
	var status := _ble_status(0.0, "lost")
	status["send"]["heart_rate"] = FakeBusServer.heart_rate_block("disconnected")
	status["send"]["controller"] = controller_block if not controller_block.is_empty() \
			else FakeBusServer.controller_block("locked", {"address": LEFT, "name": "Zwift SF2", "side": "left"}, 64)
	var bus := start_fake_bus([status])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.bus_connected and client.trainer_control == "lost", 3.0))
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var devices := HeartRateDevices.new()
	devices.remember("strap", STRAP_ADDRESS, "HRM 600")
	var save := SaveGame.new()
	save.set_heart_rate_profile(168, 190)
	var controller := RoleDevice.new("controller")
	controller.remember(LEFT, "Zwift SF2", "left")
	var menu: CanvasLayer = DEVICES_MENU.new()
	viewport.add_child(menu)
	menu.open(client, devices, save, _remembered_kickr(), controller)
	menu.start_role_search("trainer")
	for i in range(3):
		client.device_found.emit("trainer", "AA:BB:CC:DD:EE:0%d" % i, "Trainer %d" % i, -60 - i * 8, "")
	client.device_search_ended.emit("trainer", "timeout")
	await wait_process_frames(4)
	return menu


func _assert_fits(menu: CanvasLayer, label: String) -> void:
	var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
	var tiles: Rect2 = menu.find_child("Tiles", true, false).get_global_rect()
	var panel: Rect2 = menu.find_child("Panel", true, false).get_global_rect()
	var back: Rect2 = menu.buttons["back"].get_global_rect()
	assert_true(screen.grow(0.5).encloses(tiles), "%s: Kacheln im Fenster (%s)" % [label, tiles])
	assert_true(screen.grow(0.5).encloses(panel), "%s: Einrichtung im Fenster (%s)" % [label, panel])
	assert_false(tiles.intersects(panel) or tiles.intersects(back), "%s: Kacheln frei" % label)
	assert_gt(panel.size.y, 200.0, "%s: Platz für die Einrichtung" % label)
	assert_true(menu.buttons["reclaim"].is_visible_in_tree(), "%s: Knopf sichtbar" % label)
	assert_true(tiles.encloses(menu.buttons["reclaim"].get_global_rect()), "%s: Knopf in der Kachel" % label)
	for cell in menu.find_child("Tiles", true, false).find_children("*", "Label", true, false):
		if cell.is_visible_in_tree():
			var tile: Rect2 = cell.get_parent().get_parent().get_global_rect()
			assert_true(tile.grow(0.5).encloses(cell.get_global_rect()),
					"%s: „%s“ in seiner Kachel" % [label, cell.text.left(30)])


func test_layout_fits_low_window() -> void:
	_assert_fits(await _window_in(Vector2i(1152, 648)), "1152×648")


func test_layout_fits_low_window_with_the_encryption_hint() -> void:
	var encrypted := FakeBusServer.controller_block("connected", {"address": LEFT, "name": "Zwift SF2", "side": "left"},
			81, "encrypted")
	var menu := await _window_in(Vector2i(1152, 648), encrypted)
	assert_true(menu.tiles_text().contains(DEVICES_MENU.CONTROLLER_ENCRYPTED_TEXT))
	_assert_fits(menu, "1152×648, verschlüsselt")


func test_layout_fits_half_screen_and_full_screen_windows() -> void:
	_assert_fits(await _window_in(Vector2i(960, 1040)), "960×1040")
	_assert_fits(await _window_in(Vector2i(1920, 1080)), "1920×1080")


func test_role_device_store_sends_an_unknown_side_as_null_and_ignores_broken_entries() -> void:
	var controller := RoleDevice.new("controller")
	assert_false(controller.remember("  ", "Zwift SF2"), "ohne Adresse nichts")
	assert_true(controller.remember(LEFT, "Zwift SF2", "oben"))
	assert_eq(controller.bridge_list(), [{"address": LEFT, "name": "Zwift SF2", "side": null}], "Seite unbekannt")
	var broken := ConfigFile.new()
	broken.set_value("trainer", "address", 42)
	broken.set_value("controller", "address", LEFT)
	broken.set_value("controller", "side", "left")
	broken.save(SETTINGS_PATH)
	assert_false(RoleDevice.load_file("trainer", SETTINGS_PATH).has_device(), "kaputter Eintrag: kein Gerät")
	assert_eq(RoleDevice.load_file("controller", SETTINGS_PATH).bridge_list(),
			[{"address": LEFT, "name": "", "side": "left"}])
	assert_eq(RoleDevice.new("trainer").bridge_list(), [], "nichts gemerkt: leere Liste")
