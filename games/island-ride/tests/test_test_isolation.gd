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


## Fixpunkte der Ableitung (#72), gleich in `bridge/tests/test_harness_lock.py`: Wert → [Bus-Port, erster Fake-Bus-Port].
const PORT_FIXPOINTS := {
	0: [8765, 18765], 1: [8766, 18865], 3: [8768, 19065], 300: [9065, 48765], 301: [8766, 18865],
	466: [8931, 35365], 467: [8932, 35465], 999: [8864, 28665], 1234: [8799, 22165],
}
## Sicherer Bereich: oberhalb der Systemports, unterhalb des dynamischen Bereichs (49152–65535), aus dem Windows
## (Hyper-V, WinNAT) wechselnde Bereiche ausschließt (`netsh interface ipv4 show excludedportrange protocol=tcp`).
const SAFE_LOW := 1024
const DYNAMIC_FIRST := 49152


func test_every_value_maps_to_its_fixed_ports() -> void:
	for n in PORT_FIXPOINTS:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, str(n))
		assert_eq(TestIsolation.port_base_error(), "", "gültig: %d" % n)
		assert_eq([TestIsolation.bus_port(), TestIsolation.first_test_port()], PORT_FIXPOINTS[n], "Wert %d" % n)
		assert_eq(TestIsolation.probe_bus_url("ws://127.0.0.1:8765"), "ws://127.0.0.1:%d" % PORT_FIXPOINTS[n][0])


func test_port_ranges_of_different_values_never_overlap() -> void:
	# Jeder Platz: Bus-Port und 100 Fake-Bus-Ports im sicheren Bereich, kein Port eines anderen Platzes.
	var used_by := {}
	for slot in range(TestIsolation.PORT_SLOTS + 1):
		var ports := [TestIsolation.BUS_PORT + slot]
		for i in range(TestIsolation.TEST_PORTS_PER_RUN):
			ports.append(TestIsolation.FIRST_TEST_PORT + TestIsolation.TEST_PORTS_PER_RUN * slot + i)
		for port in ports:
			if used_by.has(port):
				fail_test("Port %d doppelt: Platz %d und %d" % [port, used_by[port], slot])
			used_by[port] = slot
	assert_eq(used_by.size(), (TestIsolation.PORT_SLOTS + 1) * (TestIsolation.TEST_PORTS_PER_RUN + 1), "keine Überschneidung")
	assert_gte(used_by.keys().min(), SAFE_LOW, "unterster Port im sicheren Bereich")
	assert_lt(used_by.keys().max(), DYNAMIC_FIRST, "oberster Port unter dem dynamischen Bereich")
	assert_eq([used_by.keys().min(), used_by.keys().max()], [8765, 48864], "Grenzen wie dokumentiert")


func test_values_share_ports_only_a_multiple_of_300_apart() -> void:
	# Werte bis 2000: gleicher Platz genau dann, wenn beide 0 sind oder sich (n, m ≥ 1) um ein Vielfaches von 300
	# unterscheiden; Paketnummern, die gleichzeitig laufen, liegen viel enger beieinander.
	for n in range(0, 2001):
		var slot := TestIsolation.port_slot(n)
		assert_between(slot, 0 if n == 0 else 1, TestIsolation.PORT_SLOTS, "Wert %d" % n)
		if n >= 1 and n <= TestIsolation.PORT_SLOTS:
			assert_eq(slot, n, "bis 300 wie bisher: Platz = Wert")
		if n > TestIsolation.PORT_SLOTS:
			assert_eq(slot, TestIsolation.port_slot(n - TestIsolation.PORT_SLOTS), "Wert %d teilt mit %d" % [n, n - 300])
	for n in [1, 72, 172, 299]:
		assert_ne(TestIsolation.port_slot(n), TestIsolation.port_slot(n + 1), "Nachbarn getrennt")


func test_invalid_value_is_reported_not_silently_shared() -> void:
	for raw in ["x", "-1", "1.5", "4 6", "+5", "5_0"]:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, raw)
		assert_string_contains(TestIsolation.port_base_error(), TestIsolation.PORT_BASE_ENV)
	for raw in ["7", "467", "1234"]:
		OS.set_environment(TestIsolation.PORT_BASE_ENV, raw)
		assert_eq(TestIsolation.port_base_error(), "", "gültig: %s" % raw)


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
