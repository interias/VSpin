## GUT-Post-Run-Hook: GUT überspringt Testskripte mit Parse-Fehler nur mit einer Warnung und
## endet trotzdem mit Exit-Code 0. Dieser Hook prüft alle test_*.gd unter res://tests und
## setzt den Exit-Code auf 1, wenn eines nicht ladbar ist – ebenso, wenn sich das echte user:// während des
## Laufs verändert hat (Wächter der Testisolation, #62, siehe pre_run_isolation.gd).
extends GutHookScript

const TEST_DIR := "res://tests"


func run() -> void:
	var broken: Array[String] = []
	for path in _test_scripts(TEST_DIR):
		var script = load(path)
		if script == null or not script.can_instantiate():
			broken.append(path)
	for path in broken:
		gut.logger.error("Testskript nicht ladbar (Parse-Fehler?): %s" % path)
	if not broken.is_empty():
		set_exit_code(1)
	# Testisolation (#62): kein Test schreibt in das echte user:// – Vergleich mit dem Stand vor dem Lauf.
	var changed := TestIsolation.user_dir_changes()
	for change in changed:
		gut.logger.error("Echtes user:// verändert (%s), Tests schreiben nach TestIsolation.path(): %s" % [
			OS.get_user_data_dir(), change])
	if not changed.is_empty():
		set_exit_code(1)


func _test_scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir_path):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	for sub in DirAccess.get_directories_at(dir_path):
		found.append_array(_test_scripts(dir_path.path_join(sub)))
	return found
