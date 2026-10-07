## Grafik- und Fenstereinstellungen: Standardwerte, Speichern/Laden, kaputte Datei, Anwenden am Viewport,
## Fensterhälften als reine Rechnung.
extends GutTest

const TEMP_PATH := "user://test_graphics_settings.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func test_defaults() -> void:
	var settings := GraphicsSettings.new()
	assert_eq(settings.aa, GraphicsSettings.AA_MSAA_4X)
	assert_eq(settings.render_scale, 1.0)
	assert_eq(settings.upscaler, GraphicsSettings.UPSCALER_BILINEAR)
	assert_true(settings.vsync)
	assert_eq(settings.max_fps, 0)
	assert_eq(settings.window_mode, GraphicsSettings.WINDOW_WINDOWED)
	assert_eq(settings.window_size, Vector2i(1600, 900))
	assert_eq(settings.window_position, GraphicsSettings.POSITION_CENTERED)


func test_missing_file_gives_defaults() -> void:
	var settings := GraphicsSettings.load_file("user://does_not_exist_settings.cfg")
	assert_eq(settings.aa, GraphicsSettings.new().aa)
	assert_eq(settings.window_size, GraphicsSettings.new().window_size)


func test_save_and_load_round_trip() -> void:
	var settings := GraphicsSettings.new()
	settings.aa = GraphicsSettings.AA_TAA
	settings.render_scale = 0.75
	settings.upscaler = GraphicsSettings.UPSCALER_FSR
	settings.vsync = false
	settings.max_fps = 144
	settings.shadows = GraphicsSettings.SHADOWS_HIGH
	settings.window_mode = GraphicsSettings.WINDOW_BORDERLESS
	settings.window_size = Vector2i(960, 1040)
	settings.window_position = Vector2i(960, 0)
	assert_eq(settings.save_file(TEMP_PATH), OK)
	var loaded := GraphicsSettings.load_file(TEMP_PATH)
	assert_eq(loaded.aa, GraphicsSettings.AA_TAA)
	assert_eq(loaded.render_scale, 0.75)
	assert_eq(loaded.upscaler, GraphicsSettings.UPSCALER_FSR)
	assert_false(loaded.vsync)
	assert_eq(loaded.max_fps, 144)
	assert_eq(loaded.shadows, GraphicsSettings.SHADOWS_HIGH)
	assert_eq(loaded.window_mode, GraphicsSettings.WINDOW_BORDERLESS)
	assert_eq(loaded.window_size, Vector2i(960, 1040))
	assert_eq(loaded.window_position, Vector2i(960, 0))


func test_broken_file_gives_defaults() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[graphics\naa = = msaa\n\"kaputt")
	file.close()
	var settings := GraphicsSettings.load_file(TEMP_PATH)
	assert_eq(settings.aa, GraphicsSettings.AA_MSAA_4X)
	assert_eq(settings.window_mode, GraphicsSettings.WINDOW_WINDOWED)


func test_invalid_values_fall_back_per_key() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string("[graphics]\naa=\"ssaa_16x\"\nrender_scale=\"gross\"\nmax_fps=-5\nshadows=\"ultra\"\n"
			+ "[window]\nmode=\"fenster\"\nsize=Vector2i(10, 10)\nposition=\"links\"\n")
	file.close()
	var settings := GraphicsSettings.load_file(TEMP_PATH)
	var defaults := GraphicsSettings.new()
	assert_eq(settings.aa, defaults.aa)
	assert_eq(settings.render_scale, defaults.render_scale)
	assert_eq(settings.max_fps, 0)
	assert_eq(settings.shadows, defaults.shadows)
	assert_eq(settings.window_mode, defaults.window_mode)
	assert_eq(settings.window_size, defaults.window_size, "zu kleine Fenstergröße verworfen")
	assert_eq(settings.window_position, defaults.window_position)


func test_apply_sets_viewport_aa_and_scale() -> void:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	var settings := GraphicsSettings.new()
	settings.render_scale = 0.5
	settings.apply_to_viewport(viewport)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_false(viewport.use_taa)
	assert_eq(viewport.scaling_3d_scale, 0.5)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)
	settings.aa = GraphicsSettings.AA_FXAA
	settings.apply_to_viewport(viewport)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	settings.aa = GraphicsSettings.AA_TAA
	settings.upscaler = GraphicsSettings.UPSCALER_FSR
	settings.apply_to_viewport(viewport)
	assert_true(viewport.use_taa)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	settings.upscaler = GraphicsSettings.UPSCALER_FSR2
	settings.apply_to_viewport(viewport)
	assert_false(viewport.use_taa, "FSR 2 glättet selbst – kein TAA zusätzlich")
	settings.aa = GraphicsSettings.AA_OFF
	settings.apply_to_viewport(viewport)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_false(viewport.use_taa)


func test_compatibility_renderer_only_msaa_and_bilinear() -> void:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	var settings := GraphicsSettings.new()
	settings.aa = GraphicsSettings.AA_TAA
	settings.upscaler = GraphicsSettings.UPSCALER_FSR
	settings.apply_to_viewport(viewport, true)
	assert_false(viewport.use_taa)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)
	settings.aa = GraphicsSettings.AA_MSAA_2X
	settings.apply_to_viewport(viewport, true)
	assert_eq(viewport.msaa_3d, Viewport.MSAA_2X)


func test_half_rect_splits_usable_area() -> void:
	var usable := Rect2i(0, 0, 1920, 1032)  # 1080 minus Taskleiste
	assert_eq(GraphicsSettings.half_rect(usable, false), Rect2i(0, 0, 960, 1032))
	assert_eq(GraphicsSettings.half_rect(usable, true), Rect2i(960, 0, 960, 1032))


func test_half_rect_on_second_screen_with_odd_width() -> void:
	var usable := Rect2i(1920, 40, 2561, 1400)
	assert_eq(GraphicsSettings.half_rect(usable, false), Rect2i(1920, 40, 1280, 1400))
	assert_eq(GraphicsSettings.half_rect(usable, true), Rect2i(3200, 40, 1281, 1400), "Rest-Pixel rechts")


func test_client_rect_subtracts_window_frame() -> void:
	var outer := Rect2i(960, 0, 960, 1032)
	assert_eq(GraphicsSettings.client_rect(outer, Vector2i(8, 31), Vector2i(16, 39)), Rect2i(968, 31, 944, 993))
	assert_eq(GraphicsSettings.client_rect(outer, Vector2i.ZERO, Vector2i.ZERO), outer, "randlos")


func test_window_origin_keeps_position_on_a_screen_else_centers() -> void:
	var screen := Rect2i(0, 0, 1920, 1040)
	var screens: Array[Rect2i] = [screen, Rect2i(1920, 0, 2560, 1400)]
	var size := Vector2i(1600, 900)
	assert_eq(GraphicsSettings.window_origin(Vector2i(100, 50), size, screen, screens), Vector2i(100, 50))
	assert_eq(GraphicsSettings.window_origin(Vector2i(2000, 100), size, screen, screens), Vector2i(2000, 100),
			"zweiter Bildschirm")
	assert_eq(GraphicsSettings.window_origin(Vector2i(9000, 100), size, screen, screens), Vector2i(160, 70),
			"Bildschirm weg → mittig")
	assert_eq(GraphicsSettings.window_origin(GraphicsSettings.POSITION_CENTERED, size, screen, screens),
			Vector2i(160, 70))
