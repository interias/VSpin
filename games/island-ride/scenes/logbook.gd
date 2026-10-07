## Fahrtenbuch der Inselfahrt (#35), aus dem Startmenü geöffnet. Liest den Spielstand (SaveGame) und zeigt ihn auf
## drei Seiten:
##   Übersicht  Statistik (km, Zeit, Fahrten, Runden) und Fahrerlevel, Bestzeiten je Strecke und Richtung,
##              Segmentzeiten, Medaillen (beste je Runde und Segment)
##   Erfolge    alle Erfolge nach Kategorie, freigeschaltet mit Datum, gesperrte blass
##   Fahrten    die letzten Fahrten, neueste zuerst
## Bedienung mit Maus und Tastatur: Seiten und „Zurück“ als Knöpfe (Pfeiltasten links/rechts, Tab, Enter/Leertaste),
## Pfeiltasten hoch/runter, Bild auf/ab, Pos1/Ende scrollen die Seite, das Mausrad ebenso; Esc schließt.
## Layout nur über Anker und Container: passt im Halbbild-Fenster (960×1040) wie im Vollbild und in 1152×648; was nicht
## auf die Seite passt, scrollt.
extends CanvasLayer

## Fahrtenbuch geschlossen („Zurück“ oder Esc).
signal closed

## Seiten in Reihenfolge der Knöpfe: Schlüssel → Beschriftung.
const PAGES := {"overview": "Übersicht", "achievements": "Erfolge", "rides": "Fahrten"}
## So viele Fahrten zeigt die Seite „Fahrten“ (neueste zuerst).
const RECENT_RIDES := 20
const TRACK_NAMES := {RideConfig.TRACK_ISLAND: "Insel-Rundkurs", RideConfig.TRACK_GRAYBOX: "Graybox"}
const DIRECTION_NAMES := {"cw": "im Uhrzeigersinn", "ccw": "gegen den Uhrzeigersinn"}
const MODE_NAMES := {SaveGame.MODE_ROUND_TRIP: "Rundfahrt"}
const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_DIM := Color(1.0, 1.0, 1.0, 0.45)
## Scrollschritt der Pfeiltasten (px).
const SCROLL_STEP_PX := 60

## Knöpfe: je Seite (PAGES) und „back“.
var buttons := {}
## Scrollbereich je Seite.
var pages := {}
var _page := "overview"


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Fahrtenbuch mit dem Stand `save` öffnen (Seite „Übersicht“, Fokus auf ihrem Knopf).
func open(save: SaveGame) -> void:
	_fill(save)
	visible = true
	show_page("overview")


## Schließen; der Fokus geht mit.
func close() -> void:
	if not visible:
		return
	visible = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	closed.emit()


## Seite `page` (Schlüssel aus PAGES) zeigen, nach oben gescrollt, Fokus auf ihren Knopf.
func show_page(page: String) -> void:
	_page = page
	for key in pages:
		(pages[key] as ScrollContainer).visible = key == page
		(buttons[key] as Button).button_pressed = key == page
	(pages[page] as ScrollContainer).scroll_vertical = 0
	focus_default()


func focus_default() -> void:
	if visible:
		(buttons[_page] as Button).grab_focus()


## Sichtbare Seite.
func current_page() -> String:
	return _page


## Alle Texte der Seite `page`, eine Zeile je Label (Tests, Sichtprüfung).
func page_text(page: String) -> String:
	var lines := []
	for label in (pages[page] as Node).find_children("*", "Label", true, false):
		lines.append(label.text)
	return "\n".join(lines)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return  # Einstellungen (F2) liegen darüber und bedienen sich selbst
	var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	var scroll: ScrollContainer = pages[_page]
	var page_px := int(scroll.size.y * 0.9)
	match key:
		KEY_ESCAPE:
			close()
		KEY_UP:
			scroll.scroll_vertical -= SCROLL_STEP_PX
		KEY_DOWN:
			scroll.scroll_vertical += SCROLL_STEP_PX
		KEY_PAGEUP:
			scroll.scroll_vertical -= page_px
		KEY_PAGEDOWN:
			scroll.scroll_vertical += page_px
		KEY_HOME:
			scroll.scroll_vertical = 0
		KEY_END:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_:
			return
	get_viewport().set_input_as_handled()


## Zeit für die Anzeige wie im Spiel: "m:ss.z" (Runden- und Segmentzeiten).
static func lap_time_text(seconds: float) -> String:
	var t := snappedf(maxf(seconds, 0.0), 0.1)
	return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]


## Dauer für die Statistik: "2 h 05 min", unter einer Stunde "42 min".
static func duration_text(seconds: float) -> String:
	var minutes := int(maxf(seconds, 0.0) / 60.0)
	return "%d h %02d min" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d min" % minutes


## Datum aus einem UTC-Zeitstempel („2026-10-07T18:30:00Z“ → „07.10.2026“).
static func date_text(utc: String) -> String:
	var parts := utc.get_slice("T", 0).split("-")
	return "%s.%s.%s" % [parts[2], parts[1], parts[0]] if parts.size() == 3 else utc


static func track_name(track: String) -> String:
	return TRACK_NAMES.get(track, track)


static func segment_name(id: String) -> String:
	for segment in IslandCourse.SEGMENTS:
		if segment["id"] == id:
			return segment["name"]
	return id


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 20
	var layout := Control.new()
	layout.name = "Layout"
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", _panel_style(0.55, 0))
	layout.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layout.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = "Fahrtenbuch"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for key in PAGES:
		var button := _button(tabs, key, PAGES[key], show_page.bind(key))
		button.toggle_mode = true
		button.button_group = group
	_button(tabs, "back", "Zurück", close)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(0.78, 16))
	column.add_child(panel)
	for key in PAGES:
		var scroll := ScrollContainer.new()
		scroll.name = key.capitalize().replace(" ", "")
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = false
		panel.add_child(scroll)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 6)
		scroll.add_child(content)
		pages[key] = scroll


func _button(parent: Container, key: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(150, 46)
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[key] = button
	return button


## Alle Seiten neu aus dem Stand füllen.
func _fill(save: SaveGame) -> void:
	for key in pages:
		var content: Node = pages[key].get_node("Content")
		for child in content.get_children():
			content.remove_child(child)
			child.queue_free()
	_fill_overview(pages["overview"].get_node("Content"), save)
	_fill_achievements(pages["achievements"].get_node("Content"), save)
	_fill_rides(pages["rides"].get_node("Content"), save)


func _fill_overview(content: VBoxContainer, save: SaveGame) -> void:
	_heading(content, "Statistik")
	var km := save.total_km()
	var level := DriverLevel.level_for(km)
	var next := DriverLevel.km_to_next(km)
	var stats := _grid(content, 2)
	_cells(stats, ["Strecke", "%.1f km" % km])
	_cells(stats, ["Zeit", duration_text(save.total_time_s())])
	_cells(stats, ["Fahrten", str(save.rides().size())])
	_cells(stats, ["Runden", str(save.total_laps())])
	_cells(stats, ["Fahrerlevel", "%d%s" % [level, " (noch %.1f km bis Level %d)" % [next, level + 1]
			if is_finite(next) else " (höchstes Level)"]])
	var areas := _track_directions(save)
	_heading(content, "Bestzeiten")
	var best := _grid(content, 2)
	for area in areas:
		var seconds := save.best_time_s(area[0], area[1])
		if is_finite(seconds):
			_cells(best, [_area_name(area), lap_time_text(seconds)])
	if best.get_child_count() == 0:
		_line(content, "noch keine", COLOR_DIM)
	_heading(content, "Segmentzeiten")
	var segments := _grid(content, 3)
	for area in areas:
		var times := save.segment_best_times(area[0], area[1])
		for id in times:
			_cells(segments, [segment_name(id), _area_name(area), lap_time_text(times[id])])
	if segments.get_child_count() == 0:
		_line(content, "noch keine", COLOR_DIM)
	_heading(content, "Medaillen")
	var medals := _grid(content, 3)
	var counts := {}
	for area in areas:
		for key in _medal_keys(save, area):
			var medal := save.best_medal(area[0], area[1], key)
			if medal != Medals.NONE:
				counts[medal] = counts.get(medal, 0) + 1
				_cells(medals, ["Runde" if key == Medals.LAP else segment_name(key), _area_name(area),
						Medals.name_of(medal)])
	if medals.get_child_count() == 0:
		_line(content, "noch keine", COLOR_DIM)
	else:
		var summary := []
		for medal in Medals.ORDER:
			if counts.has(medal):
				summary.append("%d× %s" % [counts[medal], Medals.name_of(medal)])
		_line(content, "Beste je Runde und Segment: " + " · ".join(summary))


func _fill_achievements(content: VBoxContainer, save: SaveGame) -> void:
	var unlocked := save.achievements()
	var count := 0
	for achievement in Achievements.LIST:
		if unlocked.has(achievement["id"]):
			count += 1
	_line(content, "%d von %d Erfolgen freigeschaltet" % [count, Achievements.LIST.size()])
	for category in Achievements.CATEGORIES:
		_heading(content, Achievements.CATEGORIES[category])
		var grid := _grid(content, 3)
		for achievement in Achievements.LIST:
			if achievement["category"] != category:
				continue
			var done: bool = unlocked.has(achievement["id"])
			var cells := _cells(grid, [achievement["name"], achievement["text"],
					date_text(unlocked[achievement["id"]]) if done else "gesperrt"])
			cells[1].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cells[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cells[1].custom_minimum_size.x = 120
			cells[0].name = achievement["id"]
			for cell in cells:
				if not done:
					cell.modulate = COLOR_DIM


func _fill_rides(content: VBoxContainer, save: SaveGame) -> void:
	var rides := save.rides()
	if rides.is_empty():
		_line(content, "Noch keine Fahrten", COLOR_DIM)
		return
	_line(content, "Die letzten %d von %d Fahrten" % [mini(rides.size(), RECENT_RIDES), rides.size()])
	var grid := _grid(content, 6)
	for cell in _cells(grid, ["Datum", "Modus", "Runden", "Strecke", "Zeit", ""]):
		cell.add_theme_color_override("font_color", COLOR_HEADING)
	for i in range(rides.size() - 1, maxi(rides.size() - RECENT_RIDES, 0) - 1, -1):
		var ride = rides[i]
		if not (ride is Dictionary):
			continue
		var seconds := float(ride.get("duration_s", 0.0))
		_cells(grid, [date_text(str(ride.get("date", ""))), MODE_NAMES.get(ride.get("mode"), str(ride.get("mode", ""))),
				str(int(ride.get("laps", 0))), "%.2f km" % float(ride.get("distance_km", 0.0)),
				duration_text(seconds) if seconds >= 60.0 else "%d s" % int(seconds),
				"Ziel" if ride.get("finished") == true else "beendet"])


## Strecken und Richtungen mit Bestzeit, Segmentzeit oder Medaille: [[strecke, richtung], …], sortiert.
func _track_directions(save: SaveGame) -> Array:
	var result := []
	for area in ["best_times", "segment_best_times", "medals"]:
		var tracks: Dictionary = save.profile()[area]
		for track in tracks:
			if not (tracks[track] is Dictionary):
				continue
			for direction in tracks[track]:
				if not ([track, direction] in result):
					result.append([track, direction])
	result.sort_custom(func(a, b): return a[0] + a[1] < b[0] + b[1])
	return result


## Runde zuerst, dann die Segmente.
func _medal_keys(save: SaveGame, area: Array) -> Array:
	var keys := [Medals.LAP]
	var stored: Dictionary = save.profile()["medals"].get(area[0], {}).get(area[1], {}) \
			if save.profile()["medals"].get(area[0]) is Dictionary else {}
	for key in stored:
		if key != Medals.LAP:
			keys.append(key)
	return keys


func _area_name(area: Array) -> String:
	return "%s, %s" % [track_name(area[0]), DIRECTION_NAMES.get(area[1], area[1])]


func _heading(parent: Container, text: String) -> void:
	var label := _line(parent, text, COLOR_HEADING)
	label.add_theme_font_size_override("font_size", 24)


func _line(parent: Container, text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _grid(parent: Container, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _cells(grid: GridContainer, texts: Array) -> Array:
	var cells := []
	for text in texts:
		var label := Label.new()
		label.text = text
		grid.add_child(label)
		cells.append(label)
	return cells


func _panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, alpha)
	style.set_corner_radius_all(12 if margin > 0 else 0)
	style.set_content_margin_all(margin)
	return style
