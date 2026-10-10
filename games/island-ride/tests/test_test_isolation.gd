## Testisolation je Worktree (#62, TestIsolation): `VSPIN_PORT_BASE=n` verschiebt die Testports, Testdateien liegen
## je Worktree und Wert außerhalb von `user://`, und der Wächter erkennt jede Änderung im überwachten Verzeichnis.
## Ohne Variable bleibt für den Spieler alles beim Alten.
extends GutTest

var _env_before := ""
var _guard_dir := ""


func before_each() -> void:
	_env_before = OS.get_environment(TestIsolation.PORT_BASE_ENV)
	_guard_dir = TestIsolation.path("guard_probe")
	DirAccess.make_dir_recursive_absolute(_guard_dir.path_join("logs"))


func after_each() -> void:
	# Die übrigen Tests dieses Laufs brauchen wieder den Wert, mit dem er gestartet wurde.
	if _env_before.is_empty():
		OS.unset_environment(TestIsolation.PORT_BASE_ENV)
	else:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, _env_before)
	_remove_tree(_guard_dir)


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)


func _write(relative: String, text: String) -> void:
	var file := FileAccess.open(_guard_dir.path_join(relative), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_without_variable_ports_stay_as_before() -> void:
	OS.unset_environment(TestIsolation.PORT_BASE_ENV)
	assert_eq(TestIsolation.port_base(), 0)
	assert_eq(TestIsolation.first_test_port(), 18765)
	assert_eq(TestIsolation.probe_bus_url("ws://127.0.0.1:8765"), "ws://127.0.0.1:8765", "Prüfhilfen: config.cfg gilt")


func test_variable_moves_test_ports_and_probe_bus() -> void:
	OS.set_environment(TestIsolation.PORT_BASE_ENV, "3")
	assert_eq(TestIsolation.port_base(), 3)
	assert_eq(TestIsolation.first_test_port(), 18765 + 300)
	assert_eq(TestIsolation.probe_bus_url("ws://127.0.0.1:8765"), "ws://127.0.0.1:8768", "Bridge des Laufs: 8765 + n")


func test_port_ranges_of_different_values_never_overlap() -> void:
	# Fake-Bus-Bereich eines Werts (100 Ports) trifft weder den eines anderen noch einen Bus-Port 8765 + m.
	for n in [0, 1, 62, TestIsolation.MAX_PORT_BASE]:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, str(n))
		var first := TestIsolation.first_test_port()
		assert_gt(first, TestIsolation.BUS_PORT + TestIsolation.MAX_PORT_BASE, "über allen Bus-Ports")
		assert_lt(first + TestIsolation.TEST_PORTS_PER_RUN - 1, 65536, "gültiger Port")
		assert_eq(first % TestIsolation.TEST_PORTS_PER_RUN, TestIsolation.FIRST_TEST_PORT % 100, "eigener Block")


func test_invalid_value_is_reported_not_silently_shared() -> void:
	for raw in ["x", "-1", str(TestIsolation.MAX_PORT_BASE + 1), "1.5"]:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, raw)
		assert_string_contains(TestIsolation.port_base_error(), TestIsolation.PORT_BASE_ENV)
	OS.set_environment(TestIsolation.PORT_BASE_ENV, "7")
	assert_eq(TestIsolation.port_base_error(), "")


func test_test_files_live_per_value_outside_user_dir() -> void:
	OS.set_environment(TestIsolation.PORT_BASE_ENV, "1")
	var one := TestIsolation.path("test_x.json")
	OS.set_environment(TestIsolation.PORT_BASE_ENV, "2")
	var two := TestIsolation.path("test_x.json")
	assert_ne(one, two, "gleichzeitige Läufe mit anderem Wert teilen keine Datei")
	assert_true(one.begins_with(ProjectSettings.globalize_path("res://.godot/test_user")), "im Projektordner (je Worktree)")
	assert_false(one.begins_with(OS.get_user_data_dir()), "nie im echten user://")
	assert_true(DirAccess.dir_exists_absolute(one.get_base_dir()), "Verzeichnis wird angelegt")


func test_game_still_saves_to_user_dir() -> void:
	# Für den Spieler unverändert: Spielstand und Einstellungen liegen weiter in user://.
	assert_eq(SaveGame.DEFAULT_PATH, "user://savegame.json")
	assert_eq(GraphicsSettings.DEFAULT_PATH, "user://settings.cfg")
	assert_eq(RideConfig.load_file().bus_url, "ws://127.0.0.1:8765")


func test_guard_sees_new_changed_and_removed_files() -> void:
	_write("savegame.json", "{}")
	_write("settings.cfg", "a")
	var before := TestIsolation.snapshot(_guard_dir)
	assert_eq(TestIsolation.changes(before, TestIsolation.snapshot(_guard_dir)), [] as Array[String], "nichts geändert")
	_write("settings.cfg", "b")
	_write("test_x.json", "{}")
	DirAccess.remove_absolute(_guard_dir.path_join("savegame.json"))
	assert_eq(TestIsolation.changes(before, TestIsolation.snapshot(_guard_dir)),
		["gelöscht: savegame.json", "geändert: settings.cfg", "neu: test_x.json"] as Array[String])


func test_guard_ignores_engine_logs() -> void:
	var before := TestIsolation.snapshot(_guard_dir)
	_write("logs/godot.log", "Engine-Protokoll")
	_write(".recovery_mode_lock", "")
	# Gerenderte Läufe (Spiel, view_probe) in einem anderen Worktree füllen die Shader-Caches – kein Test.
	DirAccess.make_dir_recursive_absolute(_guard_dir.path_join("shader_cache/CanvasShaderRD"))
	_write("shader_cache/CanvasShaderRD/x.vulkan.cache", "Shader")
	assert_eq(TestIsolation.changes(before, TestIsolation.snapshot(_guard_dir)), [] as Array[String])
