## Menü „Grafik und Fenster“: F2 und Esc öffnen/schließen es in der Hauptszene, Beenden nur über den Knopf, Auswahl wirkt
## sofort und wird gespeichert, im Browser keine Fensteroptionen.
extends "res://tests/support/bus_test.gd"

const MENU_SCENE := preload("res://scenes/settings_menu.tscn")
const TEMP_PATH := "user://test_settings_menu.cfg"


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


## Menü allein, mit Testdatei und wahlweise als Browser-Variante.
func _spawn_menu(web: bool, compatibility: bool = false) -> CanvasLayer:
	var menu := MENU_SCENE.instantiate()
	menu.settings_path = TEMP_PATH
	menu.web = web
	menu.compatibility = compatibility
	add_child_autofree(menu)
	return menu


func test_f2_opens_and_closes_menu() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	assert_false(ride.settings_menu.is_open(), "beim Start zu")
	await press_key(KEY_F2)
	assert_true(ride.settings_menu.is_open(), "F2 öffnet")
	await press_key(KEY_F2)
	assert_false(ride.settings_menu.is_open(), "F2 schließt")


func test_escape_opens_and_closes_menu_without_quitting() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	watch_signals(ride)
	await run_for(0.1)
	await press_key(KEY_ESCAPE)
	assert_true(ride.settings_menu.is_open(), "Esc öffnet das Menü")
	assert_signal_not_emitted(ride, "quit_requested", "… und beendet nicht")
	await press_key(KEY_ESCAPE)
	assert_false(ride.settings_menu.is_open(), "Esc schließt das Menü")
	await press_key(KEY_F2)
	await press_key(KEY_ESCAPE)
	assert_false(ride.settings_menu.is_open(), "mit F2 geöffnet, mit Esc geschlossen")
	assert_signal_not_emitted(ride, "quit_requested", "Esc beendet nie")


func test_quit_button_requests_quit() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	watch_signals(ride)
	await press_key(KEY_ESCAPE)
	var quit: Button = ride.settings_menu.find_child("Quit", true, false)
	assert_not_null(quit, "Knopf „Beenden“ im Menü")
	assert_eq(quit.text, "Beenden")
	assert_true(quit.is_visible_in_tree())
	assert_eq(quit.focus_mode, Control.FOCUS_NONE, "Beenden nur per Klick, nie per Leertaste/Enter")
	quit.pressed.emit()
	assert_signal_emitted(ride, "quit_requested", "Beenden über den Knopf")


func test_pause_message_mentions_menu() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 3.0)))
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	await press_key(KEY_P)
	assert_string_contains(ride.status_message(), "F2")


func test_selection_applies_and_saves() -> void:
	var menu := _spawn_menu(false)
	var aa: OptionButton = menu.options["aa"]
	aa.select(GraphicsSettings.AA_MODES.find(GraphicsSettings.AA_FXAA))
	aa.item_selected.emit(aa.selected)
	var scale: OptionButton = menu.options["render_scale"]
	scale.select(GraphicsSettings.RENDER_SCALES.find(0.75))
	scale.item_selected.emit(scale.selected)
	assert_eq(menu.get_viewport().screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "wirkt sofort")
	assert_eq(menu.get_viewport().scaling_3d_scale, 0.75)
	var saved := GraphicsSettings.load_file(TEMP_PATH)
	assert_eq(saved.aa, GraphicsSettings.AA_FXAA, "gespeichert")
	assert_eq(saved.render_scale, 0.75)
	menu.settings.aa = GraphicsSettings.AA_MSAA_4X  # Testlauf-Viewport zurück auf Standard
	menu.settings.render_scale = 1.0
	menu.apply()


func test_desktop_shows_window_options() -> void:
	var menu := _spawn_menu(false)
	assert_true(menu.options["window_mode"].visible)
	assert_true(menu.options["window_size"].visible)
	assert_true(menu.options["vsync"].visible)
	assert_eq(menu.options["aa"].item_count, GraphicsSettings.AA_MODES.size())


func test_web_hides_window_options() -> void:
	var menu := _spawn_menu(true, true)
	assert_false(menu.options["window_mode"].visible, "keine Fenstermodi im Browser")
	assert_false(menu.options["window_size"].visible)
	assert_false(menu.options["vsync"].visible)
	assert_false(menu.options["upscaler"].visible, "kein FSR im Compatibility-Renderer")
	assert_true(menu.options["render_scale"].visible, "Render-Auflösung bleibt")
	assert_eq(menu.options["aa"].item_count, GraphicsSettings.AA_MODES_COMPATIBILITY.size(), "nur MSAA")
	assert_false(menu.find_child("Quit", true, false).visible, "Beenden gibt es im Browser nicht")


## Hauptszene mit eigener Einstellungsdatei; `config.cfg [sky]` hier: feste 13 Uhr, klar.
func _spawn_ride_with_settings() -> Node:
	var config := config_for(start_fake_bus([FakeBusServer.status()]))
	config.sky_time_mode = DayNight.MODE_FIXED
	config.sky_fixed_hour = 13.0
	config.sky_weather_mode = Weather.MODE_FIXED
	config.sky_weather = Weather.CLEAR
	var ride := MAIN_SCENE.instantiate()
	ride.config = config
	ride.quit_on_request = false
	ride.settings_path = TEMP_PATH
	ride.save_path = ""
	ride.start_in_menu = false
	add_child_autofree(ride)
	return ride


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func test_sky_selection_applies_at_once_and_survives_restart() -> void:
	var ride := _spawn_ride_with_settings()
	_choose(ride.settings_menu, "time", [DayNight.MODE_FIXED, 20.5])
	_choose(ride.settings_menu, "weather", [Weather.MODE_FIXED, Weather.RAIN])
	assert_eq(ride.sky.clock.mode, DayNight.MODE_FIXED, "wirkt sofort")
	assert_eq(ride.sky.clock.fixed_hour, 20.5)
	assert_almost_eq(ride.sky.clock.local_hour(), 20.5, 0.01)
	assert_eq(ride.sky.weather.state, Weather.RAIN)
	assert_false(ride.sky.weather.changing(), "ohne Überblendung")
	assert_eq(ride.sky.current["rain"], 1.0, "Regen sofort sichtbar")
	_choose(ride.settings_menu, "time", [DayNight.MODE_TIMELAPSE, 48.0])
	assert_eq(ride.sky.clock.mode, DayNight.MODE_TIMELAPSE)
	assert_eq(ride.sky.clock.timelapse_day_min, 48.0)
	remove_child(ride)
	ride.free()
	var again := _spawn_ride_with_settings()
	assert_eq(again.sky.clock.mode, DayNight.MODE_TIMELAPSE, "nach Neustart gespeicherter Wert statt config.cfg")
	assert_eq(again.sky.clock.timelapse_day_min, 48.0)
	assert_eq(again.sky.weather.mode, Weather.MODE_FIXED)
	assert_eq(again.sky.weather.state, Weather.RAIN)
	_choose(again.settings_menu, "weather", [Weather.MODE_CHANGING, ""])
	assert_eq(again.sky.weather.mode, Weather.MODE_CHANGING)


func test_config_sky_applies_without_saved_section() -> void:
	var settings := GraphicsSettings.new()
	settings.aa = GraphicsSettings.AA_MSAA_4X
	settings.save_file(TEMP_PATH)  # nur [graphics]/[window]
	var ride := _spawn_ride_with_settings()
	assert_eq(ride.sky.clock.mode, DayNight.MODE_FIXED, "config.cfg gilt")
	assert_eq(ride.sky.clock.fixed_hour, 13.0)
	ride.settings_menu.open()
	var time: OptionButton = ride.settings_menu.options["time"]
	assert_eq(time.get_item_text(time.selected), "13:00 Uhr", "Menü zeigt den Stand aus config.cfg")
	var weather: OptionButton = ride.settings_menu.options["weather"]
	assert_eq(weather.get_item_text(weather.selected), "Klar")


func test_web_shows_sky_options() -> void:
	var menu := _spawn_menu(true, true)
	assert_true(menu.options["time"].visible)
	assert_true(menu.options["weather"].visible)


## Menü in einem Fenster `viewport_size` (ohne Datei, ohne Fenstersteuerung), mit „Fahrt beenden“ – die volle Höhe.
func _menu_in(viewport_size: Vector2i, web: bool = false) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var menu := MENU_SCENE.instantiate()
	menu.settings_path = ""
	menu.web = web
	viewport.add_child(menu)
	menu.set_ride_active(true)
	menu.open()
	await wait_process_frames(4)
	return menu


func _assert_menu_inside(menu: CanvasLayer, label: String) -> void:
	var screen: Rect2 = menu._panel.get_viewport_rect()
	var checked := 0
	for control in menu.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		checked += 1
		var rect: Rect2 = control.get_global_rect()
		assert_true(screen.encloses(rect), "%s: %s liegt im Fenster %s (%s)" % [label, control.name, screen, rect])
	assert_gt(checked, 20, "%s: alle Felder geprüft" % label)


## Layout in jeder wählbaren Fenstergröße (auch Halbbild) und im Browser – mit allen Feldern, auch der Jahreszeit (#39).
func test_layout_fits_every_window_size() -> void:
	for size in GraphicsSettings.WINDOW_SIZES:
		var label := "%d×%d" % [size.x, size.y]
		_assert_menu_inside(await _menu_in(size), label)
	_assert_menu_inside(await _menu_in(Vector2i(1280, 720), true), "Browser 1280×720")
