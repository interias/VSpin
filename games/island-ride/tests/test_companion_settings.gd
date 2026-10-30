## Einstellungen des Begleiters (Spec #76, #80): „Begleiter“ an/aus und „Toni-Stimme“ stehen im Einstellungsmenü,
## wirken sofort, werden in `settings.cfg` (Abschnitt `[companion]`) gespeichert und überstehen einen Neustart; eine alte
## Datei ohne den Abschnitt ergibt die Standardwerte (an, 80 %). Dazu das Ducking in RideSound als Pegelrechnung am Bus.
extends "res://tests/support/bus_test.gd"

const MENU_SCENE := preload("res://scenes/settings_menu.tscn")
var TEMP_PATH := TestIsolation.path("test_companion_settings.cfg")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _spawn_menu() -> CanvasLayer:
	var menu := MENU_SCENE.instantiate()
	menu.settings_path = TEMP_PATH
	add_child_autofree(menu)
	return menu


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func test_defaults_are_on_and_eighty_percent() -> void:
	var settings := GraphicsSettings.new()
	assert_true(settings.companion_enabled, "Standard: an")
	assert_eq(settings.companion_volume, GraphicsSettings.DEFAULT_COMPANION_VOLUME)
	assert_has(GraphicsSettings.COMPANION_VOLUMES, GraphicsSettings.DEFAULT_COMPANION_VOLUME, "Standard steht in der Auswahl")


func test_saved_and_old_file_without_section_loads_defaults() -> void:
	var settings := GraphicsSettings.new()
	settings.companion_enabled = false
	settings.companion_volume = 0.4
	assert_eq(settings.save_file(TEMP_PATH), OK)
	var loaded := GraphicsSettings.load_file(TEMP_PATH)
	assert_false(loaded.companion_enabled, "aus gespeichert")
	assert_eq(loaded.companion_volume, 0.4)
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[sound]\nenabled=true\nvolume=0.5\n")
	file.close()
	var old := GraphicsSettings.load_file(TEMP_PATH)
	assert_true(old.companion_enabled, "alte Datei: Standard")
	assert_eq(old.companion_volume, GraphicsSettings.DEFAULT_COMPANION_VOLUME)
	file = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[companion]\nenabled=true\nvolume=7.0\n")
	file.close()
	assert_eq(GraphicsSettings.load_file(TEMP_PATH).companion_volume, 1.0, "auf 0..1 begrenzt")
	file = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[companion]\nvolume=\"laut\"\n")
	file.close()
	assert_eq(GraphicsSettings.load_file(TEMP_PATH).companion_volume, GraphicsSettings.DEFAULT_COMPANION_VOLUME, "ungültig: Standard")


func test_menu_rows_apply_at_once_and_are_saved() -> void:
	var menu := _spawn_menu()
	assert_true(menu.options.has("companion") and menu.options.has("companion_volume"), "zwei Zeilen im Menü")
	assert_eq(menu.options["companion"].get_item_text(menu.options["companion"].selected), "An", "Standard: an")
	watch_signals(menu)
	_choose(menu, "companion", false)
	assert_false(menu.settings.companion_enabled, "wirkt sofort")
	assert_signal_emitted_with_parameters(menu, "settings_changed", ["companion"])
	_choose(menu, "companion_volume", 0.6)
	assert_eq(menu.settings.companion_volume, 0.6)
	assert_signal_emitted_with_parameters(menu, "settings_changed", ["companion_volume"])
	var saved := GraphicsSettings.load_file(TEMP_PATH)
	assert_false(saved.companion_enabled, "gespeichert")
	assert_eq(saved.companion_volume, 0.6)
	# Neustart: ein neues Menü zeigt die gespeicherten Werte.
	var again := _spawn_menu()
	assert_false(again.settings.companion_enabled)
	assert_eq(again.options["companion"].get_item_text(again.options["companion"].selected), "Aus")
	assert_eq(again.options["companion_volume"].get_item_text(again.options["companion_volume"].selected), "60 %")


func test_main_scene_reads_the_saved_settings() -> void:
	var settings := GraphicsSettings.new()
	settings.companion_enabled = false
	settings.companion_volume = 0.2
	settings.save_file(TEMP_PATH)
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := MAIN_SCENE.instantiate()
	ride.config = config_for(bus)
	ride.quit_on_request = false
	ride.settings_path = TEMP_PATH
	ride.save_path = ""
	ride.start_in_menu = false
	add_child_autofree(ride)
	assert_false(ride.companion_enabled(), "gespeichert aus")
	ride.settings_menu.settings.companion_enabled = true  # sofort wirksam, ohne Neustart
	assert_true(ride.companion_enabled())
	assert_eq(ride.ride_state_message()["companion_volume"], 0.2, "gespeicherte Lautstärke geht an den Begleiter")


func test_ducking_lowers_the_bus_only_while_speaking_and_fades() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus)
	var sound: RideSound = ride.sound
	sound.set_process(false)
	sound.apply_settings(true, 0.5, 1.0)
	var index := AudioServer.get_bus_index(RideSound.BUS)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.5), 0.01, "eingestellter Pegel")
	sound.set_ducked(true)
	sound.update(RideSound.DUCK_FADE_S / 2.0)
	assert_between(sound.duck, RideSound.DUCK_GAIN, 1.0, "gleitet")
	assert_ne(sound.duck, RideSound.DUCK_GAIN)
	sound.update(RideSound.DUCK_FADE_S)
	assert_eq(sound.duck, RideSound.DUCK_GAIN)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.5 * RideSound.DUCK_GAIN), 0.01, "gesenkt")
	sound.apply_settings(true, 0.7, 1.0)  # Lautstärke ändern, solange geduckt wird
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.7 * RideSound.DUCK_GAIN), 0.01, "bleibt gesenkt")
	sound.set_ducked(false)
	sound.update(RideSound.DUCK_FADE_S * 2.0)
	assert_eq(sound.duck, 1.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(index), linear_to_db(0.7), 0.01, "wieder auf dem eingestellten Pegel")
	sound.apply_settings(true, GraphicsSettings.DEFAULT_SOUND_VOLUME, 1.0)


func test_toni_rides_row_is_on_by_default_applies_at_once_and_is_saved() -> void:
	assert_true(GraphicsSettings.new().companion_rides, "Standard: an")
	var menu := _spawn_menu()
	assert_true(menu.options.has("companion_rides"), "Zeile „Toni fährt mit“")
	assert_eq(menu.options["companion_rides"].get_item_text(menu.options["companion_rides"].selected), "An")
	watch_signals(menu)
	_choose(menu, "companion_rides", false)
	assert_false(menu.settings.companion_rides, "wirkt sofort")
	assert_signal_emitted_with_parameters(menu, "settings_changed", ["companion_rides"])
	assert_false(GraphicsSettings.load_file(TEMP_PATH).companion_rides, "gespeichert")
	var again := _spawn_menu()
	assert_false(again.settings.companion_rides)
	assert_eq(again.options["companion_rides"].get_item_text(again.options["companion_rides"].selected), "Aus")
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[companion]\nenabled=true\nvolume=0.4\n")
	file.close()
	assert_true(GraphicsSettings.load_file(TEMP_PATH).companion_rides, "alte Datei ohne Schlüssel: Standard an")
