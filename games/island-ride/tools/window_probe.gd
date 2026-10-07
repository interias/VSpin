## Manuelle Prüfung der Fenstermodi (G4), gerendert (ohne `--headless`): setzt das Fenster über das Grafikmenü auf
## die rechte und linke Hälfte der Arbeitsfläche, randlos und Vollbild, und gibt je Schritt Position und Größe aus
## (Client-Fläche und mit Rahmen). Danach optional `--unfocus`: startet Notepad (holt den Fokus) und misst, ob das
## Spiel ohne Fokus mit voller Bildrate weiterläuft.
##   godot --path games/island-ride -s res://tools/window_probe.gd -- [--unfocus]
## Schreibt nur eine Wegwerf-Einstellungsdatei im Temp-Ordner, nie `user://settings.cfg`.
extends SceneTree

var _menu: CanvasLayer


func _initialize() -> void:
	var path := OS.get_environment("TEMP").path_join("vspin_window_probe.cfg")
	for action in ["ride_settings", "ride_fullscreen", "ride_quit"]:
		InputMap.add_action(action)  # Tasten selbst sind hier egal (sonst registriert sie die Hauptszene)
	_menu = load("res://scenes/settings_menu.tscn").instantiate()
	_menu.settings_path = path
	root.add_child(_menu)
	await _frames(10)
	var screen := DisplayServer.window_get_current_screen()
	print("SCREEN %d usable=%s full=%s" % [screen, DisplayServer.screen_get_usable_rect(screen),
		DisplayServer.screen_get_size(screen)])
	_report("start")
	_menu.place_half(true)
	await _frames(20)
	_report("rechte Hälfte")
	_menu.place_half(false)
	await _frames(20)
	_report("linke Hälfte")
	_menu._on_window_mode(GraphicsSettings.WINDOW_BORDERLESS)
	_menu.place_half(true)
	await _frames(20)
	_report("randlos, rechte Hälfte")
	_menu.toggle_fullscreen()
	await _frames(30)
	_report("Vollbild (F11)")
	_menu.toggle_fullscreen()
	await _frames(30)
	_report("zurück (F11)")
	_menu._on_window_mode(GraphicsSettings.WINDOW_WINDOWED)
	_menu.place_half(true)
	await _frames(20)
	_report("Fenster, rechte Hälfte")
	if "--unfocus" in OS.get_cmdline_user_args():
		await _unfocused_fps()
	_menu.remember_window()
	var saved := GraphicsSettings.load_file(path)
	print("SAVED mode=%s size=%s position=%s" % [saved.window_mode, saved.window_size, saved.window_position])
	_menu.settings_path = ""  # beim Beenden nicht erneut merken
	DirAccess.remove_absolute(path)
	quit(0)


func _report(step: String) -> void:
	print("WINDOW %-24s mode=%d borderless=%s client=%s+%s outer=%s+%s" % [step, DisplayServer.window_get_mode(),
		DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), DisplayServer.window_get_position(),
		DisplayServer.window_get_size(), DisplayServer.window_get_position_with_decorations(),
		DisplayServer.window_get_size_with_decorations()])


## Bilder je Sekunde mit Fokus, dann ohne (Notepad holt den Fokus), je 3 s.
func _unfocused_fps() -> void:
	print("FOCUSED focused=%s fps=%.1f" % [DisplayServer.window_is_focused(), await _count_fps(3.0)])
	var pid := OS.create_process("notepad.exe", [])
	await _seconds(1.5)
	var focused := DisplayServer.window_is_focused()
	print("UNFOCUSED focused=%s fps=%.1f" % [focused, await _count_fps(3.0)])
	OS.kill(pid)


func _count_fps(seconds: float) -> float:
	var frames := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame
		frames += 1
	return frames / seconds


func _seconds(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame


func _frames(count: int) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw
