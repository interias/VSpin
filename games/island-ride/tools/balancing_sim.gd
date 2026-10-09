## Balancing-Simulation (#55): fährt Tausende Arcade-Läufe ohne Grafik und schreibt den Bericht (Markdown).
##   godot --headless --path games/island-ride -s res://tools/balancing_sim.gd -- --runs=N --seed=S --out=<pfad>
## Optionen (alle optional): `--runs=N` Läufe je Kadenzverlauf und Stufe ohne Ausrüstung (Standard 200),
## `--gear-runs=N` mit Empfohlener Stärke (Standard 100), `--careers=N` Laufbahnen je Verlauf (Standard 30),
## `--career-max-runs=N` (Standard 120), `--seed=S` (Standard 1), `--ride-minutes=M` (Standard 45), `--out=<pfad>`
## (Standard `docs/balancing/arcade-balancing.md` im Repository), `--commit=<hash>`, `--date=<JJJJ-MM-TT>` (Standard: heute),
## `--note=<text>`, `--appendix=<datei>` (Markdown, wird an den Bericht angehängt). Gleicher Seed und gleiche Optionen ergeben denselben Bericht. Spielstand ist nur im Speicher,
## `user://` bleibt unberührt. Die Laufzeit steht auf der Konsole (und mit `--note` im Bericht).
extends SceneTree


func _initialize() -> void:
	var options := {"runs": 200, "gear_runs": 100, "careers": 30, "career_max_runs": Balancing.CAREER_MAX_RUNS, "seed": 1,
			"ride_s": Balancing.RIDE_S}
	var meta := {"date": Time.get_date_string_from_system()}
	var out := ProjectSettings.globalize_path("res://").path_join("../../docs/balancing/arcade-balancing.md").simplify_path()
	var command := ["godot", "--headless", "--path", "games/island-ride", "-s", "res://tools/balancing_sim.gd", "--"]
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--runs":
				options["runs"] = int(value)
			"--gear-runs":
				options["gear_runs"] = int(value)
			"--careers":
				options["careers"] = int(value)
			"--career-max-runs":
				options["career_max_runs"] = int(value)
			"--seed":
				options["seed"] = int(value)
			"--ride-minutes":
				options["ride_s"] = float(value) * 60.0
			"--out":
				out = value
			"--commit":
				meta["commit"] = value
			"--date":
				meta["date"] = value
			"--note":
				meta["note"] = value
			"--appendix":
				meta["appendix"] = FileAccess.get_file_as_string(value)
			_:
				push_error("Unbekannte Option: " + arg)
				quit(2)
				return
		command.append(arg)
	meta["command"] = "`%s`" % " ".join(command)
	var started := Time.get_ticks_msec()
	var data := Balancing.simulate(options, func(line): print("[%6.1f s] %s" % [(Time.get_ticks_msec() - started) / 1000.0, line]))
	var text := Balancing.report(data, options, meta)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("Bericht nicht schreibbar: " + out)
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("Bericht: %s (%d Zeichen), Laufzeit %.1f s" % [out, text.length(), (Time.get_ticks_msec() - started) / 1000.0])
	quit(0)
