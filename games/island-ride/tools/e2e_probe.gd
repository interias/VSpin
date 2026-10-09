## Manuelle Prüfhilfe (E2E): startet die Hauptszene headless gegen den Bus aus config.cfg,
## fährt N Sekunden und gibt eine Zeile mit Kadenz/Geschwindigkeit aus.
##   godot --headless --path games/island-ride -s res://tools/e2e_probe.gd -- --seconds=6 [--start-m=2400] [--track=graybox]
## `--start-m`: Startposition auf der Strecke (Insel: 2400 = Beginn der Serpentinen; Graybox: 140 = kurz vor
## dem Anstieg), z. B. für `set_grade`. `--track`: Strecke statt der aus config.cfg (`island` oder `graybox`).
## Exit-Code 2, wenn keine Bus-Verbindung zustande kam. Mit `VSPIN_PORT_BASE=n` (#62) fährt sie gegen die Bridge auf
## Port 8765 + n statt config.cfg [bus] url. Den Gelände-Cache legt sie ins Testverzeichnis (TestIsolation), nie
## nach user://.
extends SceneTree


func _initialize() -> void:
	var seconds := 6.0
	var start_m := 0.0
	var config := RideConfig.load_file()
	config.bridge_autostart = false  # Prüfhilfe startet nie selbst eine Bridge (#25)
	config.bus_url = TestIsolation.probe_bus_url(config.bus_url)
	IslandTerrain.cache_path = TestIsolation.path("terrain_cache.bin")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("--start-m="):
			start_m = float(arg.get_slice("=", 1))
		elif arg.begins_with("--track="):
			config.track = arg.get_slice("=", 1)
	var ride = load("res://scenes/main.tscn").instantiate()
	ride.config = config
	ride.start_distance_m = start_m
	ride.start_in_menu = false
	ride.save_path = ""
	root.add_child(ride)
	await create_timer(seconds).timeout
	print("E2E url=%s track=%s bus_connected=%s status=%s state=%s source=%s cadence=%.1f speed_kmh=%.2f distance_m=%.1f grade=%.3f grade_sent=%.4f station=%s hint=%s" % [
		ride.config.bus_url, ride.config.track, ride.bus.bus_connected, ride.bus.status, ride.state, ride.bus.source,
		ride.bus.cadence, ride.model.speed_kmh(), ride.model.distance_m, ride.current_grade(),
		ride.grade_reporter.last_sent, ride.current_station(), ride.resistance_hint])
	quit(0 if ride.bus.bus_connected else 2)
