## Menü „Grafik und Fenster“: F2 öffnet/schließt in der Hauptszene, Esc schließt erst das Menü, Auswahl wirkt
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


func test_escape_closes_menu_before_quitting() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	watch_signals(ride)
	await press_key(KEY_F2)
	await press_key(KEY_ESCAPE)
	assert_false(ride.settings_menu.is_open(), "Esc schließt das Menü")
	assert_signal_not_emitted(ride, "quit_requested", "… und beendet nicht")
	await press_key(KEY_ESCAPE)
	assert_signal_emitted(ride, "quit_requested")


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
