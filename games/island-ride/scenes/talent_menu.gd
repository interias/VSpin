## Talentbaum des Arcade-Modus (#53), aus dem Startmenü (Seite „Arcade“ → „Talente“) geöffnet – die einzige Stelle, an der
## Talentpunkte verteilt werden (in der Fahrt nichts). Drei Äste nebeneinander (Sprinter, Kletterer, Ausdauer), je fünf Knoten
## von der Wurzel abwärts; ein Knoten wird mit einem Talentpunkt erlernt, wenn sein Vorgänger erlernt ist. Oben das
## Arcade-Level, die freien Punkte und die Punkte bis zum nächsten Level; „Zurücksetzen“ gibt alle Punkte kostenlos zurück.
## Logik in Talents/ArcadeLevel; die Hauptszene speichert (`talents_changed`). Die Talente wirken nur im Arcade-Modus
## (ADR-0010) – sie verändern Fähigkeiten, ersetzen aber nie das Treten.
## Bedienung mit Maus und Tastatur: Pfeiltasten/Tab, Enter/Leertaste lernt bzw. löst aus, Esc oder „Zurück“ schließt.
## Layout nur über Anker und Container: passt in 960×1040, 1920×1080 und 1152×648; die Äste scrollen, wenn es eng wird.
extends CanvasLayer

## Talentbaum geschlossen („Zurück“ oder Esc).
signal closed
## Ein Talent erlernt oder alle zurückgesetzt (im Spielstand gesetzt, noch nicht auf der Platte).
signal talents_changed

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_LEARNED := Color(0.5, 0.92, 0.55)
const COLOR_OPEN := Color(0.92, 0.95, 1.0)
const COLOR_LOCKED := Color(0.55, 0.6, 0.66)
const BRANCH_COLORS := {
	"sprinter": Color(1.0, 0.6, 0.35),
	"kletterer": Color(0.5, 0.85, 0.55),
	"ausdauer": Color(0.45, 0.7, 1.0),
}

## Knöpfe: je Knoten „node_<id>“ (Talents.NODES), dazu „reset“ und „back“.
var buttons := {}
var _save: SaveGame
var _info: Label
var _columns: HBoxContainer


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Mit dem Stand `save` öffnen; der Fokus liegt auf dem ersten erlernbaren Knoten (sonst auf „Zurück“).
func open(save: SaveGame) -> void:
	_save = save
	_refresh()
	visible = true
	focus_default()


## Schließen; der Fokus geht mit.
func close() -> void:
	if not visible:
		return
	visible = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	closed.emit()


## Fokus auf den ersten erlernbaren Knoten (sonst „Zurück“), z. B. nach dem Schließen der Einstellungen.
func focus_default() -> void:
	if not visible:
		return
	for id in Talents.NODES:
		var button: Button = buttons["node_" + id]
		if not button.disabled:
			button.grab_focus()
			return
	buttons["back"].grab_focus()


## Knoten `id` erlernen (wie ein Klick); danach der Fokus auf den nächsten erlernbaren Knoten.
func learn(id: String) -> void:
	if _save == null or not Talents.learn(_save, id):
		return
	_refresh()
	talents_changed.emit()
	var next := Talents.NODES.keys().filter(func(n): return Talents.NODES[n]["requires"] == id and not buttons["node_" + n].disabled)
	if not next.is_empty():
		buttons["node_" + next[0]].grab_focus()
	else:
		focus_default()


## Alle Talente zurücksetzen (kostenlos).
func reset_talents() -> void:
	if _save == null or Talents.learned(_save).is_empty():
		return
	Talents.reset(_save)
	_refresh()
	talents_changed.emit()
	focus_default()


## Kopfzeile wie angezeigt (Arcade-Level, freie Punkte).
func info_text() -> String:
	return _info.text


## Text des Knotens `id` wie angezeigt (für Tests), z. B. „Kräftiger Antritt · erlernt\nWindböe stärker …“.
func node_text(id: String) -> String:
	return buttons["node_" + id].text


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return  # Einstellungen (F2) liegen darüber und bedienen sich selbst
	var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if key == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## Kopfzeile und Knoten aus dem Stand.
func _refresh() -> void:
	var total := ArcadeLevel.total_points(_save)
	var level := ArcadeLevel.level(_save)
	var free := Talents.available(_save)
	var next_text := "Höchstlevel" if level >= ArcadeLevel.MAX_LEVEL else "noch %d Punkte bis Level %d" % [
			ArcadeLevel.points_to_next(total), level + 1]
	_info.text = "Arcade-Level %d · %d %s frei (%d ausgegeben) · %s · wirkt nur im Arcade-Modus" % [level, free,
			"Talentpunkt" if free == 1 else "Talentpunkte", Talents.spent(_save), next_text]
	var learned := Talents.learned(_save)
	for id in Talents.NODES:
		var node: Dictionary = Talents.NODES[id]
		var button: Button = buttons["node_" + id]
		var blocked := Talents.blocked_by(_save, id)
		var state := "erlernt" if blocked == "learned" else ("braucht „%s“" % Talents.NODES[node["requires"]]["name"]
				if blocked == "requires" else ("kein Talentpunkt frei" if blocked == "points" else "1 Talentpunkt"))
		button.text = "%s · %s\n%s" % [node["name"], state, node["text"]]
		var color: Color = COLOR_LEARNED if blocked == "learned" else (COLOR_LOCKED if blocked != "" else COLOR_OPEN)
		for slot in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_disabled_color",
				"font_hover_pressed_color"]:
			button.add_theme_color_override(slot, color)
		button.disabled = blocked != ""
		button.focus_mode = Control.FOCUS_NONE if blocked != "" else Control.FOCUS_ALL
	var reset: Button = buttons["reset"]
	reset.disabled = learned.is_empty()
	reset.focus_mode = Control.FOCUS_NONE if learned.is_empty() else Control.FOCUS_ALL
	reset.text = "Zurücksetzen (+%d)" % Talents.spent(_save) if not learned.is_empty() else "Zurücksetzen"


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
	title.text = "Talente"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	_info = Label.new()
	_info.name = "Info"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 17)
	column.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	_columns = HBoxContainer.new()
	_columns.name = "Branches"
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 12)
	scroll.add_child(_columns)
	for branch in Talents.BRANCHES:
		_build_branch(branch)
	var bottom := HBoxContainer.new()
	bottom.name = "Actions"
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	column.add_child(bottom)
	_button(bottom, "reset", "Zurücksetzen", reset_talents)
	_button(bottom, "back", "Zurück", close)


func _build_branch(branch: String) -> void:
	var panel := PanelContainer.new()
	panel.name = branch.capitalize()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", _panel_style(0.78, 12))
	_columns.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = Talents.BRANCHES[branch]["name"]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", BRANCH_COLORS.get(branch, COLOR_HEADING))
	box.add_child(heading)
	var caption := Label.new()
	caption.text = Talents.BRANCHES[branch]["text"]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 15)
	box.add_child(caption)
	for id in Talents.nodes_of(branch):
		var button := Button.new()
		button.name = "node_" + id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # schmale Fenster: Texte brechen um
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 66)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(learn.bind(id))
		box.add_child(button)
		buttons[button.name] = button


func _button(parent: Container, key: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(190, 46)
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[key] = button
	return button


func _panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, alpha)
	style.set_corner_radius_all(12 if margin > 0 else 0)
	style.set_content_margin_all(margin)
	return style
