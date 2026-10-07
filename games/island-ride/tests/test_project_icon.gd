## Spiel-Symbol: das VSpin-Symbol ist als Projekt- und Windows-Symbol gesetzt und vorhanden.
extends GutTest


func test_project_icon_is_the_vspin_symbol() -> void:
	var icon: String = ProjectSettings.get_setting("application/config/icon", "")
	assert_eq(icon, "res://icon.svg")
	assert_true(FileAccess.file_exists(icon), "icon.svg fehlt")
	assert_true(FileAccess.get_file_as_string(icon).contains("#c6f432"), "Symbol in Limette")


func test_windows_icon_holds_all_sizes() -> void:
	var path: String = ProjectSettings.get_setting("application/config/windows_native_icon", "")
	assert_eq(path, "res://icon.ico")
	var data := FileAccess.get_file_as_bytes(path)
	assert_gt(data.size(), 6, "icon.ico fehlt oder ist leer")
	assert_eq(data.decode_u16(2), 1, "ICO-Kennung")
	assert_eq(data.decode_u16(4), 7, "16, 24, 32, 48, 64, 128 und 256 px")
