## Pulszeile im Startmenü (Story 11): alle Texte der statischen Funktion und der Durchstich Fake-Bus → Menüzeile.
extends "res://tests/support/bus_test.gd"

const START_MENU := preload("res://scenes/start_menu.gd")
const START_MENU_SCENE := preload("res://scenes/start_menu.tscn")
const STRAP := {"address": "F1:2A:33:44:55:66", "name": "HRM 600", "role": "strap"}
const WATCH := {"address": "C8:11:22:33:44:55", "name": "", "role": "watch"}
var SAVE_PATH := TestIsolation.path("test_heart_rate_status_savegame.json")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func test_status_texts() -> void:
	var status := START_MENU.heart_rate_status(true, "connected", STRAP, 62.0, "ble")
	assert_eq(status[0], "Puls: HRM 600 · 62 bpm")
	assert_eq(status[1], START_MENU.COLOR_OK)
	status = START_MENU.heart_rate_status(true, "connected", STRAP, NAN, "ble")
	assert_eq(status[0], "Puls: HRM 600 · -- bpm", "verbunden, aber noch kein Wert")
	assert_eq(status[1], START_MENU.COLOR_OK)
	status = START_MENU.heart_rate_status(true, "connected", WATCH, 91.4, "ble")
	assert_eq(status[0], "Puls: Uhr · 91 bpm", "ohne Namen die Rolle")
	assert_eq(START_MENU.heart_rate_status(true, "connected", {}, 80.0, "ble")[0], "Puls: Brustgurt · 80 bpm")


func test_status_texts_without_device_data() -> void:
	var status := START_MENU.heart_rate_status(true, "stale", STRAP, NAN, "ble")
	assert_eq(status[0], "Puls: HRM 600 · keine Daten")
	assert_eq(status[1], START_MENU.COLOR_WARN)
	status = START_MENU.heart_rate_status(true, "disconnected", {}, NAN, "ble")
	assert_eq(status[0], "Puls: nicht verbunden")
	assert_eq(status[1], START_MENU.COLOR_WARN)
	status = START_MENU.heart_rate_status(true, "off", {}, NAN, "ble")
	assert_eq(status[0], "Puls: kein Gerät eingerichtet")
	assert_eq(status[1], START_MENU.COLOR_WARN)


func test_status_texts_with_pulse_from_the_wheel() -> void:
	var status := START_MENU.heart_rate_status(true, "off", {}, 118.0, "sim")
	assert_eq(status[0], "Puls: 118 bpm (Simulator)")
	assert_eq(status[1], START_MENU.COLOR_OK)
	assert_eq(START_MENU.heart_rate_status(true, "off", {}, 118.0, "ble")[0], "Puls: 118 bpm (vom Rad)")


func test_status_text_without_bus() -> void:
	var status := START_MENU.heart_rate_status(false, "connected", STRAP, 62.0, "ble")
	assert_eq(status[0], "Puls: nicht verbunden", "ohne Bus gilt kein alter Zustand")
	assert_eq(status[1], START_MENU.COLOR_ERROR)


func _spawn_game(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


func test_menu_line_shows_pulse_from_fake_bus_and_failure() -> void:
	var block := FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device())
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "ble", ["CADENCE"], 0.0, block),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 62}),
		FakeBusServer.status("connected", "ble", ["CADENCE"], 0.8, FakeBusServer.heart_rate_block("disconnected")),
		FakeBusServer.telemetry(80.0, 0.9, {"heart_rate": null}),
	])
	var game := _spawn_game(bus)
	var label: Label = game.start_menu.find_child("HeartRateStatus", true, false)
	assert_eq(label.text, "Puls: nicht verbunden", "vor der Verbindung")
	assert_true(await run_until(func(): return label.text == "Puls: HRM 600 · 62 bpm", 3.0), "Puls: %s" % label.text)
	assert_true(await run_until(func(): return game.bus.heart_rate_state == "disconnected", 3.0))
	assert_eq(label.text, "Puls: nicht verbunden", "Ausfall")
	bus.stop()
	assert_true(await run_until(func(): return not game.bus.bus_connected, 3.0))
	await wait_process_frames(2)
	assert_eq(label.text, "Puls: nicht verbunden", "Bus weg")


func test_menu_line_without_pulse_device() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
			FakeBusServer.heart_rate_block("off")), FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 118})])
	var game := _spawn_game(bus)
	var label: Label = game.start_menu.find_child("HeartRateStatus", true, false)
	assert_true(await run_until(func(): return label.text == "Puls: 118 bpm (Simulator)", 3.0), label.text)


func test_game_sends_devices_after_connect_and_on_change() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := _spawn_game(bus)
	assert_true(await run_until(func(): return bus.received_of_type("set_heart_rate_devices").size() == 1, 3.0))
	assert_eq(bus.received_of_type("set_heart_rate_devices")[0]["message"]["devices"], [], "auch die leere Liste")
	game.heart_rate_devices.remember("watch", "C8:11:22:33:44:55", "Forerunner 970")
	game.heart_rate_devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	game.apply_heart_rate_devices()
	assert_true(await run_until(func(): return bus.received_of_type("set_heart_rate_devices").size() == 2, 3.0))
	var sent: Array = bus.received_of_type("set_heart_rate_devices")[1]["message"]["devices"]
	assert_eq(sent.size(), 2)
	assert_eq(sent[0]["role"], "strap", "Gurt vor Uhr")


func test_menu_layout_with_pulse_line_fits_low_window() -> void:
	for size in [Vector2i(1152, 648), Vector2i(960, 1040), Vector2i(1280, 720)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child_autofree(viewport)
		var menu := START_MENU_SCENE.instantiate()
		viewport.add_child(menu)
		await wait_process_frames(4)
		var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
		var status: Control = menu.find_child("Status", true, false)
		var panel: Control = menu.find_child("Panel", true, false)
		var line: Control = menu.find_child("HeartRateStatus", true, false)
		assert_true(screen.grow(0.5).encloses(status.get_global_rect()), "%s: Status im Fenster" % size)
		assert_true(screen.grow(0.5).encloses(line.get_global_rect()), "%s: Pulszeile im Fenster" % size)
		assert_false(panel.get_global_rect().intersects(status.get_global_rect()), "%s: Menü frei vom Status" % size)
