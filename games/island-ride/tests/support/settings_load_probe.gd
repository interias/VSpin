## Probe für tests/test_graphics_settings.gd (Nacharbeit #74): lädt eine Einstellungsdatei in einem eigenen Godot-Prozess,
## damit der Test dessen Engine-Meldungen lesen kann (GUT sieht ConfigFile-Fehler nicht). Aufruf:
## `godot --headless --path <projekt> -s res://tests/support/settings_load_probe.gd -- <datei>`; meldet „geladen“.
extends SceneTree

const GRAPHICS_SETTINGS := preload("res://src/graphics_settings.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	GRAPHICS_SETTINGS.load_file(args[0] if args.size() > 0 else "")
	print("geladen")
	quit()
