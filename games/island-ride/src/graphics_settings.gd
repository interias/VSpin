## Grafik- und Fenstereinstellungen der Inselfahrt (Menü `F2`, G4): Kantenglättung, Render-Auflösung, VSync,
## fps-Limit, Schatten, Tempo-Effekte (#42), Panorama-Momente (#43), Fenstermodus und -geometrie; dazu Tageszeit, Wetter und Jahreszeit (G8, #39; Abschnitt `[sky]`, nur geschrieben,
## sobald im Menü gewählt – sonst gilt `config.cfg [sky]`). Gespeichert in `user://settings.cfg` (ConfigFile), getrennt von
## der Spiel-Konfiguration `config.cfg` (Bus, Fahrmodell). Fehlende Datei oder Schlüssel, ungültige Werte → Standard.
## Logik und Werte hier; das Menü (`scenes/settings_menu.gd`) zeigt sie an und wendet sie an.
class_name GraphicsSettings
extends RefCounted

const DEFAULT_PATH := "user://settings.cfg"

## Kantenglättung: genau ein Verfahren (Kombinationen bringen hier wenig und kosten doppelt).
const AA_OFF := "off"
const AA_FXAA := "fxaa"
const AA_MSAA_2X := "msaa_2x"
const AA_MSAA_4X := "msaa_4x"
const AA_MSAA_8X := "msaa_8x"
const AA_TAA := "taa"
const AA_MODES := [AA_OFF, AA_FXAA, AA_MSAA_2X, AA_MSAA_4X, AA_MSAA_8X, AA_TAA]
## Im Compatibility-Renderer (Web) nur MSAA – FXAA/TAA gibt es dort in Godot 4.4 nicht.
const AA_MODES_COMPATIBILITY := [AA_OFF, AA_MSAA_2X, AA_MSAA_4X, AA_MSAA_8X]

## Render-Auflösung als Anteil der Fenstergröße (3D; HUD bleibt scharf).
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0, 1.25, 1.5, 2.0]
## Skalierungsverfahren der 3D-Auflösung; FSR nur im Forward+-Renderer.
const UPSCALER_BILINEAR := "bilinear"
const UPSCALER_FSR := "fsr"
const UPSCALER_FSR2 := "fsr2"
const UPSCALERS := [UPSCALER_BILINEAR, UPSCALER_FSR, UPSCALER_FSR2]

## fps-Obergrenze (0 = ohne).
const MAX_FPS_CHOICES := [0, 30, 60, 120, 144]

## Schattenqualität: Atlasgröße der Sonnenschatten (global, nicht am Licht-Knoten) und Weichzeichnung.
const SHADOWS_LOW := "low"
const SHADOWS_MEDIUM := "medium"
const SHADOWS_HIGH := "high"
const SHADOW_QUALITIES := [SHADOWS_LOW, SHADOWS_MEDIUM, SHADOWS_HIGH]
const SHADOW_ATLAS := {SHADOWS_LOW: 2048, SHADOWS_MEDIUM: 4096, SHADOWS_HIGH: 8192}
const SHADOW_FILTER := {
	SHADOWS_LOW: RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	SHADOWS_MEDIUM: RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	SHADOWS_HIGH: RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
}

## Fenstermodus: Fenster mit Rahmen (frei skalierbar, Windows-Snap), randloses Fenster, Vollbild
## (randlos über den ganzen Bildschirm, kein exklusiver Modus – Alt+Tab zur Musik-App ohne Umschalten).
const WINDOW_WINDOWED := "windowed"
const WINDOW_BORDERLESS := "borderless"
const WINDOW_FULLSCREEN := "fullscreen"
const WINDOW_MODES := [WINDOW_WINDOWED, WINDOW_BORDERLESS, WINDOW_FULLSCREEN]
## Gängige Fenstergrößen fürs Menü; 960×1040 ≈ halbe 1920er Arbeitsfläche.
const WINDOW_SIZES := [Vector2i(960, 1040), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
		Vector2i(2560, 1440)]
## Position „mittig auf dem Bildschirm“.
const POSITION_CENTERED := Vector2i(-1, -1)

## Tageszeit im Menü: feste Ortszeiten (Stunden) und Zeitraffer (Minuten je Tag).
const FIXED_HOURS := [6.0, 9.0, 12.0, 15.0, 18.0, 20.5, 22.0, 0.0]
const TIMELAPSE_DAY_MINS := [12.0, 24.0, 48.0]

var aa := AA_MSAA_4X
var render_scale := 1.0
var upscaler := UPSCALER_BILINEAR
var vsync := true
var max_fps := 0
var shadows := SHADOWS_MEDIUM
## Geschwindigkeitslinien und Sichtfeld-Kick (#42, SpeedEffects).
var speed_effects := true
## Panorama-Momente an den Sehenswürdigkeiten (#43).
var panorama := true
var window_mode := WINDOW_WINDOWED
var window_size := Vector2i(1600, 900)
## Position der Client-Fläche (ohne Rahmen); POSITION_CENTERED = mittig.
var window_position := POSITION_CENTERED
## Tageszeit und Wetter (wie `config.cfg [sky]`, siehe DayNight/Weather). Nur gültig, wenn `sky_saved`.
var sky_saved := false
var time_mode := DayNight.MODE_REALTIME
var fixed_hour := 13.0
var timelapse_day_min := 24.0
var weather_mode := Weather.MODE_CHANGING
var weather := Weather.CLEAR
## Jahreszeit (#39, Season): nach dem Datum oder fest.
var season_mode := Season.MODE_REAL
var season := Season.SPRING


## Liest `path`; fehlende/kaputte Datei oder Schlüssel und ungültige Werte ergeben die Standardwerte.
static func load_file(path: String = DEFAULT_PATH) -> GraphicsSettings:
	var settings := GraphicsSettings.new()
	var file := ConfigFile.new()
	if not FileAccess.file_exists(path):
		return settings
	var err := file.load(path)
	if err != OK:
		push_warning("GraphicsSettings: %s nicht lesbar (Fehler %d), nutze Standardwerte" % [path, err])
		return settings
	settings.aa = _choice(file.get_value("graphics", "aa", settings.aa), AA_MODES, settings.aa)
	settings.render_scale = clampf(_number(file.get_value("graphics", "render_scale"), settings.render_scale), 0.25, 2.0)
	settings.upscaler = _choice(file.get_value("graphics", "upscaler", settings.upscaler), UPSCALERS, settings.upscaler)
	settings.vsync = bool(file.get_value("graphics", "vsync", settings.vsync))
	settings.max_fps = maxi(int(_number(file.get_value("graphics", "max_fps"), settings.max_fps)), 0)
	settings.shadows = _choice(file.get_value("graphics", "shadows", settings.shadows), SHADOW_QUALITIES,
			settings.shadows)
	settings.speed_effects = bool(file.get_value("graphics", "speed_effects", settings.speed_effects))
	settings.panorama = bool(file.get_value("graphics", "panorama", settings.panorama))
	settings.window_mode = _choice(file.get_value("window", "mode", settings.window_mode), WINDOW_MODES,
			settings.window_mode)
	var size = file.get_value("window", "size", settings.window_size)
	if size is Vector2i and size.x >= 320 and size.y >= 240:
		settings.window_size = size
	var position = file.get_value("window", "position", settings.window_position)
	if position is Vector2i:
		settings.window_position = position
	settings.sky_saved = file.has_section("sky")
	if settings.sky_saved:
		settings.time_mode = _choice(file.get_value("sky", "time_mode", settings.time_mode), DayNight.MODES,
				settings.time_mode)
		settings.fixed_hour = fposmod(_number(file.get_value("sky", "fixed_hour"), settings.fixed_hour), 24.0)
		var day_min := _number(file.get_value("sky", "timelapse_day_min"), settings.timelapse_day_min)
		settings.timelapse_day_min = day_min if day_min > 0.0 else settings.timelapse_day_min
		settings.weather_mode = _choice(file.get_value("sky", "weather_mode", settings.weather_mode), Weather.MODES,
				settings.weather_mode)
		settings.weather = _choice(file.get_value("sky", "weather", settings.weather), Weather.STATES.keys(),
				settings.weather)
		settings.season_mode = _choice(file.get_value("sky", "season_mode", settings.season_mode), Season.MODES,
				settings.season_mode)
		settings.season = _choice(file.get_value("sky", "season", settings.season), Season.PHASES, settings.season)
	return settings


func save_file(path: String = DEFAULT_PATH) -> Error:
	var file := ConfigFile.new()
	file.set_value("graphics", "aa", aa)
	file.set_value("graphics", "render_scale", render_scale)
	file.set_value("graphics", "upscaler", upscaler)
	file.set_value("graphics", "vsync", vsync)
	file.set_value("graphics", "max_fps", max_fps)
	file.set_value("graphics", "shadows", shadows)
	file.set_value("graphics", "speed_effects", speed_effects)
	file.set_value("graphics", "panorama", panorama)
	file.set_value("window", "mode", window_mode)
	file.set_value("window", "size", window_size)
	file.set_value("window", "position", window_position)
	if sky_saved:
		file.set_value("sky", "time_mode", time_mode)
		file.set_value("sky", "fixed_hour", fixed_hour)
		file.set_value("sky", "timelapse_day_min", timelapse_day_min)
		file.set_value("sky", "weather_mode", weather_mode)
		file.set_value("sky", "weather", weather)
		file.set_value("sky", "season_mode", season_mode)
		file.set_value("sky", "season", season)
	var err := file.save(path)
	if err != OK:
		push_warning("GraphicsSettings: %s nicht schreibbar (Fehler %d)" % [path, err])
	return err


## Setzt Kantenglättung und Render-Auflösung am Viewport. `compatibility`: Compatibility-Renderer (Web) –
## dort nur MSAA und bilineare Skalierung; andere Werte fallen auf „aus“ bzw. bilinear zurück.
func apply_to_viewport(viewport: Viewport, compatibility: bool = false) -> void:
	var mode := aa if not compatibility or aa in AA_MODES_COMPATIBILITY else AA_OFF
	viewport.msaa_3d = {AA_MSAA_2X: Viewport.MSAA_2X, AA_MSAA_4X: Viewport.MSAA_4X,
			AA_MSAA_8X: Viewport.MSAA_8X}.get(mode, Viewport.MSAA_DISABLED)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if mode == AA_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	var scaler := upscaler if not compatibility else UPSCALER_BILINEAR
	# FSR 2 glättet selbst zeitlich; TAA zusätzlich wäre doppelt.
	viewport.use_taa = mode == AA_TAA and scaler != UPSCALER_FSR2
	viewport.scaling_3d_mode = {UPSCALER_FSR: Viewport.SCALING_3D_MODE_FSR,
			UPSCALER_FSR2: Viewport.SCALING_3D_MODE_FSR2}.get(scaler, Viewport.SCALING_3D_MODE_BILINEAR)
	viewport.scaling_3d_scale = render_scale


## VSync, fps-Limit und Schattenqualität (global für das ganze Spiel). `window_vsync = false`: VSync nicht
## anfassen (Browser – den steuert dort der Browser).
func apply_engine(window_vsync: bool = true) -> void:
	if window_vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[shadows], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[shadows])


## Tageszeit, Wetter und Jahreszeit von `sky` übernehmen (Anzeige im Menü, solange nichts gespeichert ist).
func capture_sky(sky: SkyController) -> void:
	time_mode = sky.clock.mode
	fixed_hour = sky.clock.fixed_hour
	timelapse_day_min = sky.clock.timelapse_day_min
	weather_mode = sky.weather.mode
	weather = sky.weather.state
	season_mode = sky.season_mode
	season = sky.fixed_season


## Tageszeit, Wetter und Jahreszeit an `sky` setzen; Wetter ohne Überblendung (sofort sichtbar).
func apply_sky(sky: SkyController) -> void:
	sky.clock.timelapse_day_min = timelapse_day_min
	sky.set_time_mode(time_mode, fixed_hour if time_mode == DayNight.MODE_FIXED else NAN)
	sky.set_weather_mode(weather_mode, weather if weather_mode == Weather.MODE_FIXED else "")
	sky.weather.snap()
	sky.set_season_mode(season_mode, season)


## Fenstermodus, -größe und -position. Gespeicherte Position nur, wenn sie auf einem Bildschirm liegt, sonst mittig.
func apply_window() -> void:
	if window_mode == WINDOW_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_mode == WINDOW_BORDERLESS)
	DisplayServer.window_set_size(window_size)
	var screens: Array[Rect2i] = []
	for screen in range(DisplayServer.get_screen_count()):
		screens.append(DisplayServer.screen_get_usable_rect(screen))
	var screen := DisplayServer.window_get_current_screen()
	DisplayServer.window_set_position(window_origin(window_position, window_size,
			DisplayServer.screen_get_usable_rect(screen), screens))


## Merkt sich Modus, Größe und Position des Fensters, wie es gerade ist (z. B. nach Ziehen oder Windows-Snap).
func capture_window() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		window_mode = WINDOW_FULLSCREEN
		return
	if mode != DisplayServer.WINDOW_MODE_WINDOWED:
		return  # minimiert/maximiert: letzte Fenstergeometrie behalten
	window_mode = WINDOW_BORDERLESS if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) \
			else WINDOW_WINDOWED
	window_size = DisplayServer.window_get_size()
	window_position = DisplayServer.window_get_position()


## Linke oder rechte Hälfte der Arbeitsfläche `usable` (ohne Taskleiste) als Außenrechteck des Fensters.
## Ungerade Breite: die rechte Hälfte bekommt das übrige Pixel.
static func half_rect(usable: Rect2i, right: bool) -> Rect2i:
	var left_width := usable.size.x / 2
	if right:
		return Rect2i(usable.position.x + left_width, usable.position.y, usable.size.x - left_width, usable.size.y)
	return Rect2i(usable.position, Vector2i(left_width, usable.size.y))


## Client-Fläche (Position, Größe) für ein Außenrechteck `outer`, wenn der Rahmen oben-links `frame_offset`
## und insgesamt `frame_size` Pixel einnimmt (randlos: beides null).
static func client_rect(outer: Rect2i, frame_offset: Vector2i, frame_size: Vector2i) -> Rect2i:
	return Rect2i(outer.position + frame_offset, outer.size - frame_size)


## Fensterposition: `wanted`, wenn ein Fenster dort mit seiner Mitte auf einer der `screens` liegt, sonst mittig
## auf `screen` (auch bei POSITION_CENTERED).
static func window_origin(wanted: Vector2i, size: Vector2i, screen: Rect2i, screens: Array[Rect2i]) -> Vector2i:
	if wanted != POSITION_CENTERED:
		var center := wanted + size / 2
		for rect in screens:
			if rect.has_point(center):
				return wanted
	return screen.position + (screen.size - size) / 2


static func _choice(value, allowed: Array, fallback: String) -> String:
	var text := str(value)
	if text in allowed:
		return text
	push_warning("GraphicsSettings: ungültiger Wert '%s', nutze '%s'" % [text, fallback])
	return fallback


static func _number(value, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback
