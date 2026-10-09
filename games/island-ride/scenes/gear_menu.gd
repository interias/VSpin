## Ausrüstung des Arcade-Modus (#49), aus dem Startmenü (Seite „Arcade“) geöffnet – die einzige Stelle, an der Beute
## verwaltet wird (in der Fahrt nichts). Links die gefundenen Teile (Name in der Farbe der Seltenheit, Werte; angelegte
## markiert), rechts das gewählte Teil mit dem **Vergleich** gegen das angelegte Teil desselben Platzes (je Wert besser,
## gleich, schlechter), dazu **Anlegen** und **Verwerten** (zu Splittern; angelegte nicht), darunter die angelegten
## Teile je Platz. Oben Splitter und Teile. Logik in Inventory/Loot; die Hauptszene speichert (`gear_changed`).
## Die Werte wirken nur im Arcade-Modus (ADR-0010).
## Bedienung mit Maus und Tastatur: Pfeiltasten/Tab, Enter/Leertaste wählt bzw. löst aus, Esc oder „Zurück“ schließt.
## Layout nur über Anker und Container: passt in 960×1040, 1920×1080 und 1152×648; die Liste scrollt.
extends CanvasLayer

## Ausrüstung geschlossen („Zurück“ oder Esc).
signal closed
## Ein Teil angelegt oder verwertet (im Spielstand gesetzt, noch nicht auf der Platte).
signal gear_changed

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_BETTER := Color(0.5, 0.92, 0.55)
const COLOR_WORSE := Color(1.0, 0.55, 0.45)
const COLOR_SAME := Color(0.82, 0.86, 0.9)
const EMPTY_TEXT := "Noch keine Beute – Herausforderungen im Arcade-Modus werfen sie ab."

## Knöpfe: je Teil „item_<id>“, dazu „equip“, „salvage“ und „back“.
var buttons := {}
## Gewähltes Teil (0 = keins).
var selected_id := 0
var _save: SaveGame
var _info: Label
var _list: VBoxContainer
var _detail_name: Label
var _detail_stats: Label
var _compare: VBoxContainer
var _equipped: VBoxContainer
var _group: ButtonGroup


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Mit dem Stand `save` öffnen; gewählt ist das neueste Teil, der Fokus liegt darauf (sonst auf „Zurück“).
func open(save: SaveGame) -> void:
	_save = save
	var items := Inventory.items(save)
	selected_id = int(items[-1]["id"]) if not items.is_empty() else 0
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


## Fokus auf das gewählte Teil (sonst „Zurück“), z. B. nach dem Schließen der Einstellungen.
func focus_default() -> void:
	if not visible:
		return
	var key := "item_%d" % selected_id
	(buttons[key] if buttons.has(key) else buttons["back"]).grab_focus()


## Teil `id` wählen: Werte und Vergleich rechts.
func select(id: int) -> void:
	selected_id = id
	if buttons.has("item_%d" % id):
		buttons["item_%d" % id].button_pressed = true  # die Gruppe gibt das vorige frei; `pressed` kommt nur vom Spieler
	_show_detail()


## Gewähltes Teil anlegen.
func equip_selected() -> void:
	if _save != null and Inventory.equip(_save, selected_id):
		_refresh()
		gear_changed.emit()
		buttons["item_%d" % selected_id].grab_focus()


## Gewähltes Teil zu Splittern verwerten (nicht angelegte); danach ist das nächste gewählt.
func salvage_selected() -> void:
	if _save == null:
		return
	var ids := Inventory.items(_save).map(func(item): return int(item["id"]))
	var index := ids.find(selected_id)
	if Inventory.salvage(_save, selected_id) <= 0:
		return
	ids.remove_at(index)
	selected_id = ids[mini(index, ids.size() - 1)] if not ids.is_empty() else 0
	_refresh()
	gear_changed.emit()
	focus_default()


## Vergleichszeilen des gewählten Teils wie angezeigt (für Tests), z. B. „Zonenbreite: +4 rpm · angelegt +2 rpm · +2“.
func comparison_lines() -> Array:
	return _compare.get_children().map(func(label): return label.text)


## Zeilen der angelegten Teile wie angezeigt (für Tests), z. B. „Helm: Magischer Helm“.
func equipped_lines() -> Array:
	return _equipped.get_children().filter(func(c): return c is Label).map(func(label): return label.text)


## Kopfzeile wie angezeigt (Splitter, Teile).
func info_text() -> String:
	return _info.text


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


## Liste, Kopfzeile, angelegte Teile und Auswahl aus dem Stand.
func _refresh() -> void:
	var items := Inventory.items(_save)
	_info.text = "Splitter: %d · %d %s · Werte wirken nur im Arcade-Modus, nur mit Kadenz in der Zone" % [
			Inventory.shards(_save), items.size(), "Teil" if items.size() == 1 else "Teile"]
	for key in buttons.keys().filter(func(k): return k.begins_with("item_")):
		buttons.erase(key)
	for child in _list.get_children():
		child.free()
	if items.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = EMPTY_TEXT
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	# Nach Platz (Reihenfolge wie Loot.SLOTS), darin die neuesten zuerst.
	var slots := Loot.SLOTS.keys()
	items.sort_custom(func(a, b): return slots.find(a["slot"]) < slots.find(b["slot"]) \
			or (a["slot"] == b["slot"] and a["id"] > b["id"]))
	if Inventory.find(_save, selected_id).is_empty():
		selected_id = int(items[0]["id"]) if not items.is_empty() else 0
	for item in items:
		var id := int(item["id"])
		var button := Button.new()
		button.name = "item_%d" % id
		button.text = "%s%s\n%s" % [Loot.item_name(item), " · angelegt" if Inventory.is_equipped(_save, id) else "",
				Loot.stats_text(item)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # schmale Fenster: Werte brechen um
		button.toggle_mode = true
		button.button_group = _group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 58)
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			button.add_theme_color_override(state, Loot.color_of(item["rarity"]))
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(select.bind(id))
		button.focus_entered.connect(select.bind(id))  # Pfeiltasten wählen mit
		_list.add_child(button)
		buttons[button.name] = button
	if buttons.has("item_%d" % selected_id):
		buttons["item_%d" % selected_id].set_pressed_no_signal(true)
	for child in _equipped.get_children():
		child.free()
	var worn := Inventory.equipped(_save)
	for slot in Loot.SLOTS:
		var label := Label.new()
		label.name = slot.capitalize()
		label.text = "%s: %s" % [Loot.SLOTS[slot]["name"], Loot.item_name(worn[slot]) if worn.has(slot) else "–"]
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Loot.color_of(worn[slot]["rarity"]) if worn.has(slot) else COLOR_SAME)
		_equipped.add_child(label)
	_show_detail()


## Rechts: Name, Werte, Vergleich mit dem angelegten Teil des Platzes, Knöpfe.
func _show_detail() -> void:
	for child in _compare.get_children():
		child.free()
	var item := Inventory.find(_save, selected_id) if _save != null else {}
	var equip: Button = buttons["equip"]
	var salvage: Button = buttons["salvage"]
	if item.is_empty():
		_detail_name.text = "Kein Teil gewählt"
		_detail_name.add_theme_color_override("font_color", COLOR_SAME)
		_detail_stats.text = ""
		_set_enabled(equip, false)
		_set_enabled(salvage, false)
		salvage.text = "Verwerten"
		return
	var worn := Inventory.is_equipped(_save, selected_id)
	_detail_name.text = Loot.item_name(item)
	_detail_name.add_theme_color_override("font_color", Loot.color_of(item["rarity"]))
	_detail_stats.text = Loot.stats_text(item).replace(" · ", "\n")
	var current: Dictionary = Inventory.equipped(_save).get(item["slot"], {})
	var heading := Label.new()
	heading.text = "Angelegt: %s" % ("dieses Teil" if worn else (Loot.item_name(current) if not current.is_empty()
			else "nichts – jeder Wert ist besser"))
	heading.add_theme_color_override("font_color", COLOR_HEADING)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compare.add_child(heading)
	if not worn:
		for row in Inventory.compare(_save, selected_id):
			var label := Label.new()
			var unit: String = Loot.STATS[row["stat"]]["unit"]
			label.text = "%s: %+d %s · angelegt %+d %s · %s" % [Loot.STATS[row["stat"]]["name"], row["candidate"], unit,
					row["current"], unit, "%+d" % row["delta"] if row["delta"] != 0 else "gleich"]
			label.add_theme_color_override("font_color", COLOR_BETTER if row["delta"] > 0 else (COLOR_WORSE
					if row["delta"] < 0 else COLOR_SAME))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_compare.add_child(label)
	_set_enabled(equip, not worn)
	equip.text = "Angelegt" if worn else "Anlegen"
	_set_enabled(salvage, not worn)
	salvage.text = "Verwerten (+%d Splitter)" % Loot.shards_for(item)


func _set_enabled(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE


func _build() -> void:
	_group = ButtonGroup.new()
	_group.allow_unpress = false
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
	title.text = "Ausrüstung"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	_info = Label.new()
	_info.name = "Info"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 17)
	column.add_child(_info)
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	var items := PanelContainer.new()
	items.name = "Items"
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_stylebox_override("panel", _panel_style(0.78, 12))
	body.add_child(items)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	items.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var side := PanelContainer.new()
	side.name = "Detail"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", _panel_style(0.78, 14))
	body.add_child(side)
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override("separation", 10)
	side.add_child(side_column)
	var side_scroll := ScrollContainer.new()
	side_scroll.name = "DetailScroll"
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(side_scroll)
	var detail := VBoxContainer.new()
	detail.name = "DetailContent"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	side_scroll.add_child(detail)
	_detail_name = Label.new()
	_detail_name.name = "Name"
	_detail_name.add_theme_font_size_override("font_size", 24)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_name)
	_detail_stats = Label.new()
	_detail_stats.name = "Stats"
	_detail_stats.add_theme_font_size_override("font_size", 17)
	detail.add_child(_detail_stats)
	_compare = VBoxContainer.new()
	_compare.name = "Compare"
	_compare.add_theme_constant_override("separation", 2)
	detail.add_child(_compare)
	var worn := Label.new()
	worn.text = "Angelegt je Platz"
	worn.add_theme_color_override("font_color", COLOR_HEADING)
	detail.add_child(worn)
	_equipped = VBoxContainer.new()
	_equipped.name = "Equipped"
	_equipped.add_theme_constant_override("separation", 0)
	detail.add_child(_equipped)
	var actions := HFlowContainer.new()  # außerhalb des Scrollbereichs: immer erreichbar
	actions.name = "ItemActions"
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	side_column.add_child(actions)
	_button(actions, "equip", "Anlegen", equip_selected)
	_button(actions, "salvage", "Verwerten", salvage_selected)
	var bottom := HBoxContainer.new()
	bottom.name = "Actions"
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(bottom)
	_button(bottom, "back", "Zurück", close)


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
