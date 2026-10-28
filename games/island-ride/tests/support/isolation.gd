## Testisolation je Worktree (#62): Parallele Testläufe – jeder mit eigenem Wert `VSPIN_PORT_BASE=n` – teilen sich
## weder Ports noch Dateien, und kein Test schreibt in das echte `user://` des Spielers.
##
## - Ports: n (jede ganze Zahl ≥ 0, z. B. die Paketnummer) wählt einen Platz p = `port_slot(n)`: 0 für n = 0, sonst
##   1 + (n − 1) mod 300 (#72). Fake-Bus ab 18765 + 100·p (je Lauf 100 Ports), Bus der echten Bridge 8765 + p (nur
##   Prüfhilfen, `probe_bus_url()`). Ohne Variable (oder n = 0) bleibt es bei 18765 bzw. 8765, für n = 1–300 bei
##   18765 + 100·n bzw. 8765 + n. Alle Ports liegen in 8765–48864, unter dem dynamischen Bereich 49152–65535, aus dem
##   Windows (Hyper-V, WinNAT) Ports ausschließt. Die Bereiche verschiedener Plätze überschneiden sich nie; zwei Werte
##   teilen Ports genau dann, wenn sie sich um ein Vielfaches von 300 unterscheiden (n, m ≥ 1) – solche Läufe nie
##   gleichzeitig. Dieselbe Ableitung steht in `bridge/tests/bridge_harness.py`.
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
## Plätze für n ≥ 1 (Platz 0 gehört n = 0); 300 hält den letzten Fake-Bus-Port (48864) unter 49152.
const PORT_SLOTS := 300
const TEST_USER_DIR := "res://.godot/test_user"
## Was die Engine selbst in `user://` schreibt (Protokolle, Sperrdatei des Editors, Shader- und Pipeline-Caches
## gerenderter Läufe – Spiel oder `view_probe` in einem anderen Worktree, Debugger-Snapshots) – kein Test.
const ENGINE_OWNED := ["logs", ".recovery_mode_lock", "shader_cache", "vulkan", "objectdb_snapshots"]

static var _user_dir_before := {}


## Fehlermeldung zu einem ungültigen `VSPIN_PORT_BASE`; leer, wenn der Wert gültig ist oder fehlt.
static func port_base_error() -> String:
	var raw := OS.get_environment(PORT_BASE_ENV).strip_edges()
	# Nur Ziffern, wie in `tools/e2e.sh` und `bridge_harness.py`: `is_valid_int` nähme auch „+5“ an (Nacharbeit #74).
	if raw.is_empty() or (raw.is_valid_int() and raw.lstrip("0123456789").is_empty()):
		return ""
	return "%s=%s: erwartet eine ganze Zahl ≥ 0" % [PORT_BASE_ENV, raw]


## Wert n aus `VSPIN_PORT_BASE` (fehlt oder ungültig = 0; ungültig hält der Pre-Run-Hook den Lauf an).
static func port_base() -> int:
	if not port_base_error().is_empty():
		return 0
	var raw := OS.get_environment(PORT_BASE_ENV).strip_edges()
	return 0 if raw.is_empty() else int(raw)


## Platz des Werts `n` (0 für n = 0, sonst 1–PORT_SLOTS); bestimmt alle Ports eines Laufs.
static func port_slot(n: int) -> int:
	return 0 if n <= 0 else 1 + (n - 1) % PORT_SLOTS


## Erster Fake-Bus-Port dieses Laufs.
static func first_test_port() -> int:
	return FIRST_TEST_PORT + TEST_PORTS_PER_RUN * port_slot(port_base())


## Bus-Port der echten Bridge dieses Laufs (`vspin-bridge --port`, `tools/e2e.sh`).
static func bus_port() -> int:
	return BUS_PORT + port_slot(port_base())


## Bus-Adresse für Prüfhilfen gegen die echte Bridge: ohne Variable `config_url` (config.cfg [bus] url),
## mit Variable die Bridge dieses Laufs auf `bus_port()`.
static func probe_bus_url(config_url: String) -> String:
	if OS.get_environment(PORT_BASE_ENV).strip_edges().is_empty():
		return config_url
	return "ws://127.0.0.1:%d" % bus_port()


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
