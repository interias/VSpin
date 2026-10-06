## Manuelle Prüfhilfe (E2E): startet die Hauptszene headless gegen den Bus aus config.cfg,
## fährt N Sekunden und gibt eine Zeile mit Kadenz/Geschwindigkeit aus.
##   godot --headless --path games/island-ride -s res://tools/e2e_probe.gd -- --seconds=6
## Exit-Code 2, wenn keine Bus-Verbindung zustande kam.
extends SceneTree


func _initialize() -> void:
	var seconds := 6.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.get_slice("=", 1))
	var ride = load("res://scenes/main.tscn").instantiate()
	root.add_child(ride)
	await create_timer(seconds).timeout
	print("E2E url=%s bus_connected=%s status=%s source=%s cadence=%.1f speed_kmh=%.2f distance_m=%.1f grade=%.3f" % [
		ride.config.bus_url, ride.bus.bus_connected, ride.bus.status, ride.bus.source,
		ride.bus.cadence, ride.model.speed_kmh(), ride.model.distance_m, ride.current_grade()])
	quit(0 if ride.bus.bus_connected else 2)
