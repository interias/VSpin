## Gemerkte Pulsgeräte (HeartRateDevices): merken, vergessen, Reihenfolge, kaputte Datei, Abschnitt in settings.cfg.
extends GutTest

var TEMP_PATH := TestIsolation.path("test_heart_rate_devices.cfg")


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _write(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_default_has_no_device() -> void:
	var devices := HeartRateDevices.new()
	assert_false(devices.has_device(HeartRateDevices.ROLE_STRAP))
	assert_false(devices.has_device(HeartRateDevices.ROLE_WATCH))
	assert_eq(devices.bridge_list(), [])
	assert_eq(devices.device(HeartRateDevices.ROLE_STRAP), {})


func test_remember_and_forget() -> void:
	var devices := HeartRateDevices.new()
	assert_true(devices.remember(HeartRateDevices.ROLE_STRAP, "F1:2A:33:44:55:66", "HRM 600"))
	assert_eq(devices.device("strap"), {"address": "F1:2A:33:44:55:66", "name": "HRM 600", "role": "strap"})
	devices.remember("strap", "AA:BB:CC:DD:EE:FF", "Tickr")
	assert_eq(devices.device("strap")["address"], "AA:BB:CC:DD:EE:FF", "höchstens ein Gurt: der neue ersetzt den alten")
	devices.forget("strap")
	assert_false(devices.has_device("strap"))
	devices.forget("strap")  # zweimal vergessen schadet nicht
	assert_eq(devices.bridge_list(), [])


func test_remember_rejects_bad_input() -> void:
	var devices := HeartRateDevices.new()
	assert_false(devices.remember("strap", "", "HRM"))
	assert_false(devices.remember("strap", "   ", "HRM"))
	assert_false(devices.remember("ring", "F1:2A:33:44:55:66", "HRM"))
	assert_eq(devices.bridge_list(), [])


func test_bridge_list_puts_strap_before_watch() -> void:
	var devices := HeartRateDevices.new()
	devices.remember("watch", "C8:11:22:33:44:55", "Forerunner 970")
	assert_eq(devices.bridge_list(), [{"address": "C8:11:22:33:44:55", "name": "Forerunner 970", "role": "watch"}])
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	var list := devices.bridge_list()
	assert_eq(list.size(), 2)
	assert_eq(list[0]["role"], "strap", "Gurt vor Uhr, egal in welcher Reihenfolge gemerkt")
	assert_eq(list[1]["role"], "watch")


func test_save_and_load_round_trip() -> void:
	var devices := HeartRateDevices.new()
	devices.remember("watch", "C8:11:22:33:44:55", "Forerunner 970")
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	assert_eq(devices.save_file(TEMP_PATH), OK)
	var loaded := HeartRateDevices.load_file(TEMP_PATH)
	assert_eq(loaded.bridge_list(), devices.bridge_list())


func test_forgotten_device_is_gone_after_save() -> void:
	var devices := HeartRateDevices.new()
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	devices.remember("watch", "C8:11:22:33:44:55", "Forerunner 970")
	devices.save_file(TEMP_PATH)
	devices.forget("strap")
	devices.save_file(TEMP_PATH)
	var loaded := HeartRateDevices.load_file(TEMP_PATH)
	assert_false(loaded.has_device("strap"))
	assert_true(loaded.has_device("watch"))


func test_missing_file_means_no_device() -> void:
	assert_eq(HeartRateDevices.load_file(TestIsolation.path("does_not_exist_hr.cfg")).bridge_list(), [])


func test_broken_file_means_no_device() -> void:
	_write("[heart_rate\nstrap_address = = \"F1\n\"kaputt")
	assert_eq(HeartRateDevices.load_file(TEMP_PATH).bridge_list(), [])


func test_broken_entries_mean_no_device() -> void:
	_write("[heart_rate]\nstrap_address=42\nstrap_name=\"HRM\"\nwatch_address=\"\"\nwatch_name=\"Uhr\"\n")
	assert_eq(HeartRateDevices.load_file(TEMP_PATH).bridge_list(), [], "Adresse keine Zeichenkette oder leer")
	_write("[heart_rate]\nstrap_address=\"F1:2A:33:44:55:66\"\nstrap_name=7\n")
	var list := HeartRateDevices.load_file(TEMP_PATH).bridge_list()
	assert_eq(list.size(), 1, "die Adresse genügt")
	assert_eq(list[0]["name"], "", "kaputter Name wird leer")


func test_file_without_section_means_no_device() -> void:
	_write("[graphics]\naa=\"fxaa\"\n")
	assert_eq(HeartRateDevices.load_file(TEMP_PATH).bridge_list(), [])


func test_saving_keeps_other_sections() -> void:
	_write("[graphics]\naa=\"fxaa\"\n[sound]\nvolume=0.5\n")
	var devices := HeartRateDevices.new()
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	devices.save_file(TEMP_PATH)
	var settings := GraphicsSettings.load_file(TEMP_PATH)
	assert_eq(settings.aa, GraphicsSettings.AA_FXAA)
	assert_eq(settings.sound_volume, 0.5)
	assert_eq(HeartRateDevices.load_file(TEMP_PATH).bridge_list().size(), 1)


func test_graphics_settings_save_keeps_the_devices() -> void:
	var devices := HeartRateDevices.new()
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	devices.remember("watch", "C8:11:22:33:44:55", "Forerunner 970")
	devices.save_file(TEMP_PATH)
	var settings := GraphicsSettings.load_file(TEMP_PATH)
	settings.aa = GraphicsSettings.AA_TAA
	assert_eq(settings.save_file(TEMP_PATH), OK)
	assert_eq(HeartRateDevices.load_file(TEMP_PATH).bridge_list(), devices.bridge_list(), "Geräte überstehen die Grafik")
	assert_eq(GraphicsSettings.load_file(TEMP_PATH).aa, GraphicsSettings.AA_TAA)
