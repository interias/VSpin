## Testisolation je Worktree (#62): Parallele Testläufe – jeder mit eigenem Wert `VSPIN_PORT_BASE=n` – teilen sich
## weder Ports noch Dateien, und kein Test schreibt in das echte `user://` des Spielers.
##
## - Ports: Fake-Bus ab 18765 + 100·n (je Lauf 100 Ports), Bus der echten Bridge 8765 + n (nur Prüfhilfen,
##   `probe_bus_url()`). Ohne Variable (oder n = 0) bleibt es bei 18765 bzw. 8765. Dieselbe Ableitung steht in
##   `bridge/tests/bridge_harness.py`. Die Bereiche überschneiden sich nie; n ≤ 466 hält alle Ports ≤ 65535.
## - Dateien: Tests legen Spielstand, Einstellungen, Caches unter `path(name)` an – im Projektordner unter
##   `.godot/test_user/<n>/` (git-ignoriert, je Worktree und Wert), nie unter `user://`.
## - Wächter: `tests/support/pre_run_isolation.gd` hält das echte `user://` vor dem Lauf fest, `post_run_check.gd`
##   vergleicht danach; jede Änderung lässt den Lauf scheitern.
class_name TestIsolation
extends RefCounted

const PORT_BASE_ENV := "VSPIN_PORT_BASE"
const BUS_PORT := 8765
const FIRST_TEST_PORT := 18765
const TEST_PORTS_PER_RUN := 100
const MAX_PORT_BASE := 466
const TEST_USER_DIR := "res://.godot/test_user"
## Was die Engine selbst in `user://` schreibt (Protokolle, Sperrdatei des Editors, Shader- und Pipeline-Caches
## gerenderter Läufe – Spiel oder `view_probe` in einem anderen Worktree, Debugger-Snapshots) – kein Test.
const ENGINE_OWNED := ["logs", ".recovery_mode_lock", "shader_cache", "vulkan", "objectdb_snapshots"]

static var _user_dir_before := {}


## Fehlermeldung zu einem ungültigen `VSPIN_PORT_BASE`; leer, wenn der Wert gültig ist oder fehlt.
static func port_base_error() -> String:
	var raw := OS.get_environment(PORT_BASE_ENV).strip_edges()
	if raw.is_empty() or (raw.is_valid_int() and int(raw) >= 0 and int(raw) <= MAX_PORT_BASE):
		return ""
	return "%s=%s: erwartet eine ganze Zahl 0–%d" % [PORT_BASE_ENV, raw, MAX_PORT_BASE]


## Wert n aus `VSPIN_PORT_BASE` (fehlt oder ungültig = 0; ungültig hält der Pre-Run-Hook den Lauf an).
static func port_base() -> int:
	if not port_base_error().is_empty():
		return 0
	var raw := OS.get_environment(PORT_BASE_ENV).strip_edges()
	return 0 if raw.is_empty() else int(raw)


## Erster Fake-Bus-Port dieses Laufs.
static func first_test_port() -> int:
	return FIRST_TEST_PORT + TEST_PORTS_PER_RUN * port_base()


## Bus-Adresse für Prüfhilfen gegen die echte Bridge: ohne Variable `config_url` (config.cfg [bus] url),
## mit Variable die Bridge dieses Laufs auf 8765 + n (`vspin-bridge --port`, `tools/e2e.sh`).
static func probe_bus_url(config_url: String) -> String:
	if OS.get_environment(PORT_BASE_ENV).strip_edges().is_empty():
		return config_url
	return "ws://127.0.0.1:%d" % (BUS_PORT + port_base())


## Verzeichnis für Testdateien dieses Laufs (absolut, wird angelegt).
static func user_dir() -> String:
	var dir := ProjectSettings.globalize_path(TEST_USER_DIR).path_join(str(port_base()))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Pfad einer Testdatei `file_name` – statt `user://<file_name>`.
static func path(file_name: String) -> String:
	return user_dir().path_join(file_name)


## Alle Dateien unter `dir` (rekursiv) als relativer Pfad → MD5, ohne `ENGINE_OWNED`.
static func snapshot(dir: String) -> Dictionary:
	var files := {}
	_collect(dir, "", files)
	return files


static func _collect(dir: String, prefix: String, files: Dictionary) -> void:
	for file_name in DirAccess.get_files_at(dir.path_join(prefix)):
		var relative := prefix.path_join(file_name) if not prefix.is_empty() else file_name
		if relative not in ENGINE_OWNED:
			files[relative] = FileAccess.get_md5(dir.path_join(relative))
	for sub in DirAccess.get_directories_at(dir.path_join(prefix)):
		var relative := prefix.path_join(sub) if not prefix.is_empty() else sub
		if relative not in ENGINE_OWNED:
			_collect(dir, relative, files)


## Unterschiede zweier Snapshots: neue, geänderte und gelöschte Dateien (sortiert).
static func changes(before: Dictionary, after: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for file_name in after:
		if not before.has(file_name):
			found.append("neu: " + file_name)
		elif before[file_name] != after[file_name]:
			found.append("geändert: " + file_name)
	for file_name in before:
		if not after.has(file_name):
			found.append("gelöscht: " + file_name)
	found.sort()
	return found


## Hält das echte `user://` vor dem Lauf fest (Pre-Run-Hook).
static func remember_user_dir() -> void:
	_user_dir_before = snapshot(OS.get_user_data_dir())


## Was sich seit `remember_user_dir()` im echten `user://` geändert hat (Post-Run-Hook).
static func user_dir_changes() -> Array[String]:
	return changes(_user_dir_before, snapshot(OS.get_user_data_dir()))
