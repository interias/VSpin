## Garderobe der Inselfahrt (#36), aus dem Startmenü geöffnet: links die Vorschau (der Fahrer auf dem Rad dreht sich
## langsam und tritt, eigene 3D-Welt im SubViewport), rechts je Kategorie (Trikot, Radfarbe, Helm) die Teile als Knöpfe.
## Ein Klick wählt das Teil sofort (Vorschau und Spielstand; die Hauptszene speichert und zieht den Fahrer um). Gesperrte
## Teile sind ausgegraut und zeigen, ab welchem Fahrerlevel sie frei werden. Nur Kosmetik (ADR-0010).
## Bedienung mit Maus und Tastatur: Pfeiltasten/Tab zwischen den Teilen, Enter/Leertaste wählt, Esc oder „Zurück“
## schließt. Layout nur über Anker und Container: passt im Halbbild-Fenster (960×1040) wie im Vollbild und in
## 1152×648; die Teile brechen in Zeilen um, was nicht in die Höhe passt, scrollt.
extends CanvasLayer

## Garderobe geschlossen („Zurück“ oder Esc).
signal closed
## Teil `item` gewählt (im Spielstand gesetzt, noch nicht auf der Platte).
signal part_chosen(item: String)

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
## Vorschau: Drehung (rad/s), Kadenz und Tempo des Fahrers, Kamera und Blickpunkt (Modellkoordinaten).
const PREVIEW_TURN_RAD_S := 0.45
const PREVIEW_CADENCE_RPM := 70.0
const PREVIEW_SPEED_MPS := 7.0
## Die Vorschau ist quadratisch (mittig im freien Platz); die Kamera hält das ganze Rad in jeder Drehung im Bild.
const PREVIEW_CAMERA := Vector3(2.9, 1.5, -1.4)
const PREVIEW_LOOK := Vector3(0.0, 0.8, 0.0)
const PREVIEW_FOV_DEG := 42.0
const PREVIEW_BACKGROUND := Color(0.2, 0.27, 0.34)

## Knöpfe: je Teil (Teil-ID aus Wardrobe.PARTS) und „back“.
var buttons := {}
## Fahrermodell der Vorschau.
var preview: RiderModel
var _save: SaveGame
var _level := 1
var _level_label: Label
var _turntable: Node3D


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Garderobe mit dem Stand `save` öffnen; Fokus auf das gewählte Trikot.
func open(save: SaveGame) -> void:
	_save = save
	_level = Wardrobe.level(save)
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


## Fokus auf das gewählte Teil der ersten Kategorie (z. B. nach dem Schließen der Einstellungen).
func focus_default() -> void:
	if visible and _save != null:
		(buttons[Wardrobe.selection(_save)[Wardrobe.CATEGORIES.keys()[0]]] as Button).grab_focus()


## Text des Knopfs für `item`: Name, gesperrt mit dem Level, ab dem es frei wird.
static func part_text(item: String, level: int) -> String:
	var label := Wardrobe.part_name(item)
	return label if DriverLevel.unlocked(item, level) else "%s · ab Level %d" % [label, DriverLevel.unlock_level(item)]


func _process(delta: float) -> void:
	if visible:
		_turntable.rotation.y += PREVIEW_TURN_RAD_S * delta
		preview.update(PREVIEW_CADENCE_RPM, PREVIEW_SPEED_MPS, 0.0, 0.0, false, delta)


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


## Teil wählen (nur freie; gesperrte Knöpfe sind ohnehin ausgegraut).
func _choose(item: String) -> void:
	if _save == null or not Wardrobe.choose(_save, item):
		return
	_refresh()
	part_chosen.emit(item)


## Knöpfe (Text, gesperrt, gewählt), Levelzeile und Vorschau aus dem Stand.
func _refresh() -> void:
	var chosen := Wardrobe.selection(_save)
	for item in Wardrobe.PARTS:
		var button: Button = buttons[item]
		var free := DriverLevel.unlocked(item, _level)
		button.text = part_text(item, _level)
		button.disabled = not free
		button.focus_mode = Control.FOCUS_ALL if free else Control.FOCUS_NONE
		button.set_pressed_no_signal(chosen[Wardrobe.category_of(item)] == item)
	var next := DriverLevel.km_to_next(_save.total_km())
	_level_label.text = "Fahrerlevel %d%s – höhere Level schalten weitere Teile frei" % [_level,
			" (noch %.1f km bis Level %d)" % [next, _level + 1] if is_finite(next) else ""]
	preview.wear(Wardrobe.outfit(chosen))


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
	title.text = "Garderobe"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	_level_label = Label.new()
	_level_label.name = "Level"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_level_label)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_build_preview(body)
	var panel := PanelContainer.new()
	panel.name = "Parts"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.4
	panel.add_theme_stylebox_override("panel", _panel_style(0.78, 16))
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	var selected := _panel_style(0.95, 6)
	selected.set_border_width_all(3)
	selected.border_color = COLOR_HEADING
	selected.set_corner_radius_all(4)
	for category in Wardrobe.CATEGORIES:
		var heading := Label.new()
		heading.name = category.capitalize()
		heading.text = Wardrobe.CATEGORIES[category]
		heading.add_theme_color_override("font_color", COLOR_HEADING)
		heading.add_theme_font_size_override("font_size", 24)
		content.add_child(heading)
		var flow := HFlowContainer.new()
		flow.name = category.capitalize() + "Parts"
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		content.add_child(flow)
		var group := ButtonGroup.new()
		group.allow_unpress = false
		for item in Wardrobe.parts(category):
			var button := _button(flow, item, Wardrobe.part_name(item), _choose.bind(item))
			button.toggle_mode = true
			button.button_group = group
			for state in ["pressed", "hover_pressed"]:  # gewählt: goldener Rahmen
				button.add_theme_stylebox_override(state, selected)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	_button(actions, "back", "Zurück", close)


## Vorschau: eigene 3D-Welt mit Licht, Kamera und einem Fahrermodell auf einer Drehscheibe.
func _build_preview(parent: Container) -> void:
	var frame := PanelContainer.new()
	frame.name = "Preview"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(220, 220)
	frame.add_theme_stylebox_override("panel", _panel_style(0.78, 8))
	parent.add_child(frame)
	var square := AspectRatioContainer.new()
	square.name = "Square"
	frame.add_child(square)
	var container := SubViewportContainer.new()
	container.name = "View"
	container.stretch = true
	square.add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PREVIEW_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.88, 0.95)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = PREVIEW_FOV_DEG
	camera.transform = Transform3D(Basis.looking_at(PREVIEW_LOOK - PREVIEW_CAMERA), PREVIEW_CAMERA)
	viewport.add_child(camera)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.rotation.y = deg_to_rad(-30.0)
	viewport.add_child(_turntable)
	preview = RiderModel.new()
	preview.name = "Model"
	_turntable.add_child(preview)


func _button(parent: Container, key: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(150, 46)
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
