## Menü „Grafik und Fenster“ (G4): `Esc` oder `F2` öffnet/schließt (auch aus der Pause), `F11` schaltet Vollbild um.
## Beenden nur über den Knopf „Beenden“ (Signal `quit_requested`; nicht im Browser). Während einer Fahrt zusätzlich
## „Fahrt beenden“ (Signal `ride_end_requested`): zurück ins Startmenü, ohne das Spiel zu schließen (#30).
## Jede Änderung wirkt sofort und wird in `settings_path` gespeichert (GraphicsSettings, `user://settings.cfg`).
## Beim Start wendet das Menü die gespeicherten Einstellungen an; die Fenstergeometrie (auch nach Ziehen oder
## Windows-Snap) wird beim Beenden gemerkt. Das Spiel läuft weiter, solange das Menü offen ist.
## Tempo-Effekte (#42, Geschwindigkeitslinien und Sichtfeld-Kick) und Panorama-Momente (#43) schaltet die Hauptszene über
## `settings_changed` um.
## Die Kameraperspektive (#59, CameraViews) steht nicht in den Einstellungen, sondern im Spielstand: Die Hauptszene setzt
## `camera_view`, das Feld zeigt es, eine Auswahl meldet `settings_changed("camera_view")`, und die Hauptszene speichert.
## Tageszeit, Wetter (G8) und Jahreszeit (#39) stehen in denselben Einstellungen (`[sky]`); auf die Welt wirken sie über
## `settings_changed`, das die Hauptszene an den SkyController weitergibt.
## Im Browser (`web`) gibt es keine Fenstermodi/-größen und kein VSync; im Compatibility-Renderer nur MSAA und
## bilineare Skalierung.
extends CanvasLayer

## Eine Einstellung wurde im Menü gewählt (Schlüssel wie in `options`).
signal settings_changed(key: String)
## Knopf „Beenden“ gedrückt (die Hauptszene beendet das Spiel).
signal quit_requested
## Knopf „Fahrt beenden“ gedrückt (die Hauptszene kehrt ins Startmenü zurück).
signal ride_end_requested

const AA_LABELS := {"off": "Aus", "fxaa": "FXAA", "msaa_2x": "MSAA 2×", "msaa_4x": "MSAA 4×", "msaa_8x": "MSAA 8×",
		"taa": "TAA"}
const UPSCALER_LABELS := {"bilinear": "Bilinear", "fsr": "AMD FSR 1", "fsr2": "AMD FSR 2"}
const SHADOW_LABELS := {"low": "Niedrig", "medium": "Mittel", "high": "Hoch"}
const WINDOW_LABELS := {"windowed": "Fenster", "borderless": "Randloses Fenster", "fullscreen": "Vollbild"}
const WEATHER_LABELS := {"clear": "Klar", "light_clouds": "Leicht bewölkt", "overcast": "Bewölkt", "rain": "Regen"}

## Einstellungsdatei; "" = Standardwerte, nichts laden/speichern, Fenster bleibt unberührt (Tests, Probe).
var settings_path := GraphicsSettings.DEFAULT_PATH
## Läuft im Browser? (Vor `_ready` überschreibbar, für Tests.)
var web := OS.has_feature("web")
## Compatibility-Renderer (Web)? (Vor `_ready` überschreibbar, für Tests.)
var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
var settings: GraphicsSettings
## Kameraperspektive (CameraViews.IDS) aus dem Spielstand; setzt die Hauptszene.
var camera_view := CameraViews.DEFAULT

## Auswahlfelder je Einstellung (Schlüssel wie in `_rows`).
var options := {}
## Zeilen (Beschriftung + Feld) je Einstellung, zum Ausblenden.
var _rows := {}
var _panel: PanelContainer
var _window_buttons: HBoxContainer
var _end_ride: Button
## Fenstermodus vor dem Vollbild (für `F11` zurück).
var _windowed_mode := GraphicsSettings.WINDOW_WINDOWED


func _ready() -> void:
	settings = GraphicsSettings.load_file(settings_path) if not settings_path.is_empty() else GraphicsSettings.new()
	if settings.window_mode != GraphicsSettings.WINDOW_FULLSCREEN:
		_windowed_mode = settings.window_mode
	_build()
	apply()
	if _manages_window():
		settings.apply_window()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ride_settings"):
		toggle()
	elif event.is_action_pressed("ride_fullscreen") and _manages_window():
		toggle_fullscreen()
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		remember_window()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if _manages_window():
		settings.capture_window()
	_refresh()
	visible = true
	(options["aa"] as OptionButton).grab_focus()


func close() -> void:
	visible = false
	var focus := _panel.get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()


## Läuft eine Fahrt? Nur dann gibt es „Fahrt beenden“.
func set_ride_active(active: bool) -> void:
	_end_ride.visible = active


## Tageszeiten wie im Feld „Tageszeit“ (für das Rundfahrt-Menü, #31): [Beschriftungen, Index der aktuellen].
func time_choices() -> Array:
	_refresh()
	var option: OptionButton = options["time"]
	var labels := []
	for i in range(option.item_count):
		labels.append(option.get_item_text(i))
	return [labels, option.selected]


## Tageszeit wählen wie im Feld „Tageszeit“: wirkt sofort und wird gespeichert.
func select_time(index: int) -> void:
	_refresh()
	var option: OptionButton = options["time"]
	if index < 0 or index == option.selected:
		return
	option.select(index)
	option.item_selected.emit(index)


## Kantenglättung, Auflösung, VSync, fps-Limit und Schatten anwenden (ohne Fenster).
func apply() -> void:
	settings.apply_to_viewport(get_viewport(), compatibility)
	settings.apply_engine(not web)


## Vollbild an/aus; zurück in den Fenstermodus von vorher.
func toggle_fullscreen() -> void:
	settings.capture_window()
	if settings.window_mode == GraphicsSettings.WINDOW_FULLSCREEN:
		settings.window_mode = _windowed_mode
	else:
		_windowed_mode = settings.window_mode
		settings.window_mode = GraphicsSettings.WINDOW_FULLSCREEN
	settings.apply_window()
	_save()
	_refresh()


## Fenster auf die linke/rechte Hälfte der Arbeitsfläche des aktuellen Bildschirms (Rahmen eingerechnet);
## aus dem Vollbild zurück in den Fenstermodus von vorher.
func place_half(right: bool) -> void:
	if settings.window_mode == GraphicsSettings.WINDOW_FULLSCREEN:
		settings.window_mode = _windowed_mode
		settings.apply_window()
	var screen := DisplayServer.window_get_current_screen()
	var outer := GraphicsSettings.half_rect(DisplayServer.screen_get_usable_rect(screen), right)
	var frame_offset := DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
	var frame_size := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var client := GraphicsSettings.client_rect(outer, frame_offset, frame_size)
	DisplayServer.window_set_size(client.size)
	DisplayServer.window_set_position(client.position)
	settings.capture_window()
	_save()
	_refresh()


## Aktuelle Fenstergeometrie speichern (beim Beenden; nicht in Tests/Probe/Browser/headless).
func remember_window() -> void:
	if settings == null or not _manages_window() or DisplayServer.get_name() == "headless":
		return
	settings.capture_window()
	_save()


func _manages_window() -> bool:
	return not web and not settings_path.is_empty()


func _save() -> void:
	if not settings_path.is_empty():
		settings.save_file(settings_path)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font_size = 20
	_panel.theme = theme
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Grafik und Fenster"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	# Zwei Spalten (#42): links Grafik (mit Panorama-Momenten, #43), rechts Tageszeit, Wetter, Jahreszeit und Fenster –
	# so passt das Menü auch in 1280×720 und ins Halbbild.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	box.add_child(columns)
	var grid := _add_grid(columns)
	var aa_modes := GraphicsSettings.AA_MODES_COMPATIBILITY if compatibility else GraphicsSettings.AA_MODES
	_add_row(grid, "aa", "Kantenglättung", aa_modes.map(func(m): return AA_LABELS[m]), aa_modes,
			func(v): settings.aa = v)
	_add_row(grid, "render_scale", "Render-Auflösung",
			GraphicsSettings.RENDER_SCALES.map(func(s): return "%d %%" % roundi(s * 100.0)),
			GraphicsSettings.RENDER_SCALES, func(v): settings.render_scale = v)
	_add_row(grid, "upscaler", "Skalierung", GraphicsSettings.UPSCALERS.map(func(u): return UPSCALER_LABELS[u]),
			GraphicsSettings.UPSCALERS, func(v): settings.upscaler = v)
	_add_row(grid, "vsync", "VSync", ["An", "Aus"], [true, false], func(v): settings.vsync = v)
	_add_row(grid, "max_fps", "fps-Limit",
			GraphicsSettings.MAX_FPS_CHOICES.map(func(f): return "Ohne" if f == 0 else str(f)),
			GraphicsSettings.MAX_FPS_CHOICES, func(v): settings.max_fps = v)
	_add_row(grid, "shadows", "Schatten", GraphicsSettings.SHADOW_QUALITIES.map(func(s): return SHADOW_LABELS[s]),
			GraphicsSettings.SHADOW_QUALITIES, func(v): settings.shadows = v)
	_add_row(grid, "speed_effects", "Tempo-Effekte", ["An", "Aus"], [true, false], func(v): settings.speed_effects = v)
	_add_row(grid, "panorama", "Panorama-Momente", ["An", "Aus"], [true, false], func(v): settings.panorama = v)
	_add_row(grid, "camera_view", "Kamera", CameraViews.IDS.map(func(id): return CameraViews.NAMES[id]),
			CameraViews.IDS, func(v): camera_view = v)
	grid = _add_grid(columns)
	var times: Array = [_time_value(DayNight.MODE_REALTIME, 0.0)]
	times.append_array(GraphicsSettings.FIXED_HOURS.map(func(h): return _time_value(DayNight.MODE_FIXED, h)))
	times.append_array(GraphicsSettings.TIMELAPSE_DAY_MINS.map(
			func(m): return _time_value(DayNight.MODE_TIMELAPSE, m)))
	_add_row(grid, "time", "Tageszeit", times.map(_time_label), times, _on_time)
	var weathers: Array = [_weather_value(Weather.MODE_CHANGING, "")]
	weathers.append_array(Weather.STATES.keys().map(func(w): return _weather_value(Weather.MODE_FIXED, w)))
	_add_row(grid, "weather", "Wetter", weathers.map(_weather_label), weathers, _on_weather)
	var seasons: Array = [_season_value(Season.MODE_REAL, "")]
	seasons.append_array(Season.PHASES.map(func(p): return _season_value(Season.MODE_FIXED, p)))
	_add_row(grid, "season", "Jahreszeit", seasons.map(_season_label), seasons, _on_season)
	_add_row(grid, "window_mode", "Fenstermodus", GraphicsSettings.WINDOW_MODES.map(func(m): return WINDOW_LABELS[m]),
			GraphicsSettings.WINDOW_MODES, _on_window_mode)
	_add_row(grid, "window_size", "Fenstergröße", [], [], _on_window_size)
	_window_buttons = HBoxContainer.new()
	_window_buttons.add_theme_constant_override("separation", 8)
	box.add_child(_window_buttons)
	_add_button(_window_buttons, "Linke Hälfte", place_half.bind(false))
	_add_button(_window_buttons, "Rechte Hälfte", place_half.bind(true))
	var hint := Label.new()
	hint.text = "Esc / F2: schließen · F11: Vollbild\nWin+←/→: Fenster an den Rand"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_add_button(actions, "Schließen", close)
	_end_ride = _add_button(actions, "Fahrt beenden", _on_end_ride)
	_end_ride.name = "EndRide"
	_end_ride.visible = false
	var quit := _add_button(actions, "Beenden", quit_requested.emit)
	quit.name = "Quit"
	quit.visible = not web  # im Browser lässt sich das Spiel nicht beenden
	quit.focus_mode = Control.FOCUS_NONE  # nur per Klick: Leertaste (Pause) beendet nie versehentlich
	for key in ["vsync", "window_mode", "window_size"]:
		for control in _rows[key]:
			control.visible = not web
	_window_buttons.visible = not web
	for control in _rows["upscaler"]:
		control.visible = not compatibility
	if web:
		hint.text = "Esc / F2: schließen"
	_refresh()


func _on_end_ride() -> void:
	close()
	ride_end_requested.emit()


func _add_grid(parent: Container) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _add_row(grid: GridContainer, key: String, text: String, labels: Array, values: Array, setter: Callable) -> void:
	var label := Label.new()
	label.text = text
	var option := OptionButton.new()
	option.name = key
	option.custom_minimum_size.x = 240
	for item in labels:
		option.add_item(item)
	option.set_meta("values", values)
	option.item_selected.connect(_on_selected.bind(option, key, setter))
	grid.add_child(label)
	grid.add_child(option)
	options[key] = option
	_rows[key] = [label, option]


func _add_button(parent: Container, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Auswahl in einem Feld: Wert setzen; Grafik sofort anwenden und speichern (Fenster über eigene Setter, die
## Kameraperspektive speichert die Hauptszene im Spielstand).
func _on_selected(index: int, option: OptionButton, key: String, setter: Callable) -> void:
	setter.call(option.get_meta("values")[index])
	if key not in ["window_mode", "window_size", "camera_view"]:
		apply()
		_save()
	settings_changed.emit(key)


## Tageszeit als Menüwert: [Modus, Zahl] – feste Stunde bzw. Minuten je Tag im Zeitraffer, Echtzeit 0.
static func _time_value(mode: String, number: float) -> Array:
	return [mode, number]


static func _time_label(value: Array) -> String:
	match value[0]:
		DayNight.MODE_FIXED:
			return "%d:%02d Uhr" % [floori(value[1]), roundi(fmod(value[1], 1.0) * 60.0)]
		DayNight.MODE_TIMELAPSE:
			return "Zeitraffer %d min/Tag" % roundi(value[1])
	return "Echtzeit (Mallorca)"


## Wetter als Menüwert: [Modus, Zustand] – wechselnd ohne Zustand.
static func _weather_value(mode: String, state: String) -> Array:
	return [mode, state]


static func _weather_label(value: Array) -> String:
	return WEATHER_LABELS.get(value[1], "Wechselnd") if value[0] == Weather.MODE_FIXED else "Wechselnd"


func _on_time(value: Array) -> void:
	settings.sky_saved = true
	settings.time_mode = value[0]
	if value[0] == DayNight.MODE_FIXED:
		settings.fixed_hour = value[1]
	elif value[0] == DayNight.MODE_TIMELAPSE:
		settings.timelapse_day_min = value[1]


func _on_weather(value: Array) -> void:
	settings.sky_saved = true
	settings.weather_mode = value[0]
	if value[0] == Weather.MODE_FIXED:
		settings.weather = value[1]


## Jahreszeit als Menüwert: [Modus, Phase] – nach dem Datum ohne Phase.
static func _season_value(mode: String, phase: String) -> Array:
	return [mode, phase]


static func _season_label(value: Array) -> String:
	return Season.NAMES.get(value[1], "") if value[0] == Season.MODE_FIXED else "Nach Datum (Mallorca)"


func _on_season(value: Array) -> void:
	settings.sky_saved = true
	settings.season_mode = value[0]
	if value[0] == Season.MODE_FIXED:
		settings.season = value[1]


func _on_window_mode(mode: String) -> void:
	if mode != GraphicsSettings.WINDOW_FULLSCREEN:
		_windowed_mode = mode
	settings.window_mode = mode
	settings.apply_window()
	_save()
	_refresh()


func _on_window_size(size: Vector2i) -> void:
	settings.window_size = size
	settings.window_position = GraphicsSettings.POSITION_CENTERED
	settings.apply_window()
	settings.capture_window()
	_save()
	_refresh()


## Auswahl an die Einstellungen anpassen; Fenstergröße: Liste plus aktuelle Größe, im Vollbild die Bildschirmauflösung.
func _refresh() -> void:
	_select("aa", settings.aa)
	_select("render_scale", settings.render_scale)
	_select("upscaler", settings.upscaler)
	_select("vsync", settings.vsync)
	_select("max_fps", settings.max_fps)
	_select("shadows", settings.shadows)
	_select("speed_effects", settings.speed_effects)
	_select("panorama", settings.panorama)
	_select("camera_view", camera_view)
	_select("window_mode", settings.window_mode)
	var number := settings.fixed_hour if settings.time_mode == DayNight.MODE_FIXED 			else settings.timelapse_day_min if settings.time_mode == DayNight.MODE_TIMELAPSE else 0.0
	_select_or_add("time", _time_value(settings.time_mode, number), _time_label)
	_select_or_add("weather", _weather_value(settings.weather_mode,
			settings.weather if settings.weather_mode == Weather.MODE_FIXED else ""), _weather_label)
	_select("season", _season_value(settings.season_mode,
			settings.season if settings.season_mode == Season.MODE_FIXED else ""))
	var sizes: Array = GraphicsSettings.WINDOW_SIZES.duplicate()
	var size_option: OptionButton = options["window_size"]
	size_option.clear()
	var fullscreen := settings.window_mode == GraphicsSettings.WINDOW_FULLSCREEN
	if fullscreen:
		sizes = [DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())]
	elif settings.window_size not in sizes:
		sizes.push_front(settings.window_size)
	for size in sizes:
		size_option.add_item("%d × %d%s" % [size.x, size.y, " (Bildschirm)" if fullscreen else ""])
	size_option.set_meta("values", sizes)
	size_option.disabled = fullscreen
	_select("window_size", sizes[0] if fullscreen else settings.window_size)


## Wie `_select`; ein Wert, den die Liste nicht hat (z. B. 13:00 aus `config.cfg`), wird angehängt.
func _select_or_add(key: String, value, label: Callable) -> void:
	var option: OptionButton = options[key]
	var values: Array = option.get_meta("values")
	if value not in values:
		values.append(value)
		option.add_item(label.call(value))
	_select(key, value)


func _select(key: String, value) -> void:
	var option: OptionButton = options[key]
	var values: Array = option.get_meta("values")
	var index := -1
	for i in range(values.size()):
		if values[i] is float and value is float and is_equal_approx(values[i], value) or values[i] == value:
			index = i
			break
	option.select(index)
