## Ausrüstung des Arcade-Modus (#49), aus dem Startmenü (Seite „Arcade“) geöffnet – die einzige Stelle, an der Beute
## verwaltet wird (in der Fahrt nichts). Rechts oben die gefundenen Teile (Name in der Farbe der Seltenheit, Werte; angelegte
## markiert), darunter das gewählte Teil mit dem **Vergleich** gegen das angelegte Teil desselben Platzes (je Wert besser,
## gleich, schlechter), dazu **Anlegen** und **Verwerten** (zu Splittern; angelegte nicht); die angelegten Teile je Platz
## zeigt das Charakterblatt links. Oben Splitter und Teile. Logik in Inventory/Loot; die Hauptszene speichert (`gear_changed`).
## Die Werte wirken nur im Arcade-Modus (ADR-0010).
##
## Ausrüstungssymbole (#83, `ItemIconView`): jeder Platz zeigt oben im Knopf das Symbol des angelegten Teils (SLOT_ICON px,
## Rahmen in der Farbe der Seltenheit) oder die graue Silhouette seiner Form, darunter Name und Werte; jede Zeile der Liste
## hat vorn das Symbol ihres Teils (ROW_ICON px); im Detail steht das gewählte Teil mit großem Symbol (DETAIL_ICON px) und
## im Vergleich das angelegte Teil des Platzes (COMPARE_ICON px) neben der Überschrift. Die Symbole liegen als Kinder in
## den Knöpfen (die Maus geht durch, Fokus und Klick bleiben beim Knopf). Die Liste baut `_refresh` bei jeder Änderung neu,
## die Bilder aber nicht: `ItemIcons` hält sie im Cache (derselbe Inhalt = dieselbe Textur), neue entstehen höchstens
## PER_FRAME je Bild – ein Inventar mit 50 Teilen öffnet sofort, die Symbole füllen sich von oben nach unten. Die Knopfstile
## mit dem Innenrand für das Symbol sind einmal gebaut und von allen Knöpfen geteilt.
##
## Charakterblatt (#68): links der Fahrer in der Mitte (die Vorschau der Garderobe, `rider_preview.gd`, mit Garderobe und
## angelegter Ausrüstung) und die sechs Plätze (Loot.SLOTS) drumherum. Jeder Platz zeigt das angelegte Teil (Name und Werte
## in der Farbe der Seltenheit) oder „leer“; ein Klick (Enter) darauf zeigt in der Liste nur die passenden Teile des
## Inventars, gewählt ist das neueste nicht angelegte, rechts steht der Vergleich – ein zweiter Klick zeigt wieder alle.
## Darunter die Summe der Werte und die eigene **Stärke** neben der **empfohlenen** der gewählten Stufe (#54). Reine
## Darstellung und Bedienung über Inventory, Loot und ArcadeTiers: keine eigenen Werte.
## Bedienung mit Maus und Tastatur: Pfeiltasten/Tab, Enter/Leertaste wählt bzw. löst aus, Esc oder „Zurück“ schließt.
## Layout nur über Anker und Container: passt in 960×1040, 1920×1080 und 1152×648; die Liste und der Fahrer mit seinen
## Plätzen scrollen, wenn sie nicht in die Höhe passen.
extends CanvasLayer

## Ausrüstung geschlossen („Zurück“ oder Esc).
signal closed
## Ein Teil angelegt oder verwertet (im Spielstand gesetzt, noch nicht auf der Platte).
signal gear_changed

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_BETTER := Color(0.5, 0.92, 0.55)
const COLOR_WORSE := Color(1.0, 0.55, 0.45)
const COLOR_SAME := Color(0.82, 0.86, 0.9)
const COLOR_OK := Color(0.45, 0.85, 0.5)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const RIDER_PREVIEW := preload("res://scenes/rider_preview.gd")
const EMPTY_TEXT := "Noch keine Beute – Herausforderungen im Arcade-Modus werfen sie ab."
## Plätze links und rechts vom Fahrer.
const LEFT_SLOTS := ["helm", "trikot", "schuhe"]
const RIGHT_SLOTS := ["rahmen", "laufraeder", "talisman"]
## Kantenlängen der Ausrüstungssymbole (px) je Fläche.
const SLOT_ICON := 80.0
const ROW_ICON := 56.0
const DETAIL_ICON := 112.0
const COMPARE_ICON := 64.0
## Abstand der Symbole zum Knopfrand und zum Rand des Scrollbereichs (px); das Leuchten ragt etwas darüber hinaus.
const ICON_INSET := 10.0

## Knöpfe: je Teil „item_<id>“, je Platz „slot_<platz>“, dazu „equip“, „salvage“ und „back“.
var buttons := {}
## Gewähltes Teil (0 = keins).
var selected_id := 0
## Gewählter Platz (Schlüssel aus Loot.SLOTS): die Liste zeigt nur seine Teile; "" = alle Plätze.
var slot_filter := ""
## Fahrermodell der Vorschau.
var preview: RiderModel
var _save: SaveGame
var _info: Label
var _list: VBoxContainer
var _detail_name: Label
var _detail_stats: Label
var _detail_effect: Label
var _compare: VBoxContainer
var _group: ButtonGroup
var _slot_group: ButtonGroup
var _totals: Label
var _strength: Label
var _slot_icons := {}
var _detail_icon: ItemIconView
var _compare_icon: ItemIconView
## Knopfstile mit Innenrand für das Symbol: Zeilen der Liste (Symbol links) und Plätze (Symbol oben), je geteilt.
var _row_styles := {}
var _slot_styles := {}


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Mit dem Stand `save` öffnen; gewählt ist das neueste Teil, der Fokus liegt darauf (sonst auf „Zurück“).
func open(save: SaveGame) -> void:
	_save = save
	slot_filter = ""
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


## Platz `slot` wählen: die Liste zeigt nur seine Teile, gewählt ist das neueste nicht angelegte (sonst das angelegte);
## derselbe Platz noch einmal (oder "") zeigt wieder alle Plätze.
func select_slot(slot: String) -> void:
	if _save == null:
		return
	slot_filter = "" if slot == slot_filter or not Loot.SLOTS.has(slot) else slot
	selected_id = _default_selection()
	_refresh()
	var key := "item_%d" % selected_id
	if buttons.has(key):
		buttons[key].grab_focus()


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


## Zeilen der angelegten Teile je Platz wie auf dem Charakterblatt (für Tests), z. B. „Helm: Magischer Helm“, „Rahmen: –“.
func equipped_lines() -> Array:
	var worn := Inventory.equipped(_save) if _save != null else {}
	return Loot.SLOTS.keys().map(func(slot): return "%s: %s" % [Loot.SLOTS[slot]["name"],
			Loot.item_name(worn[slot]) if worn.has(slot) else "–"])


## Summe der Werte der angelegten Teile wie angezeigt (für Tests), z. B. „Summe: +4 rpm Zonenbreite · +6 % Punkte“.
func totals_text() -> String:
	return _totals.text


## Stärke neben der empfohlenen der gewählten Stufe wie angezeigt (für Tests), z. B. „Stärke 12 / empfohlen 20 (Stufe 3)“.
func strength_text() -> String:
	return _strength.text


## Effekt des gewählten legendären Teils wie angezeigt (für Tests), z. B. „Effekt: Rückstoß\nWindböe wirft …“; sonst "".
func effect_text() -> String:
	return _detail_effect.text


## Symbol im Knopf `key` („slot_<platz>“ oder „item_<id>“), null wenn es keinen gibt (für Tests).
func icon_of(key: String) -> ItemIconView:
	return buttons[key].find_child("ItemIcon", false, false) if buttons.has(key) else null


## Großes Symbol des gewählten Teils im Detail (für Tests); unsichtbar, wenn nichts gewählt ist.
func detail_icon() -> ItemIconView:
	return _detail_icon


## Kleines Symbol des angelegten Teils (oder die Silhouette) im Vergleich (für Tests); unsichtbar beim angelegten Teil selbst.
func compare_icon() -> ItemIconView:
	return _compare_icon


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
	var shown := items.filter(func(item): return slot_filter == "" or item["slot"] == slot_filter)
	if shown.is_empty():
		var empty := Label.new()
		empty.name = "Empty"
		empty.text = EMPTY_TEXT if items.is_empty() else "Kein Teil für %s im Inventar – ein zweiter Klick auf den Platz zeigt wieder alle." % \
				Loot.SLOTS[slot_filter]["name"]
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	# Nach Platz (Reihenfolge wie Loot.SLOTS), darin die neuesten zuerst.
	var slots := Loot.SLOTS.keys()
	items.sort_custom(func(a, b): return slots.find(a["slot"]) < slots.find(b["slot"]) \
			or (a["slot"] == b["slot"] and a["id"] > b["id"]))
	if Inventory.find(_save, selected_id).is_empty():
		selected_id = int(items[0]["id"]) if not items.is_empty() else 0
	if slot_filter != "" and Inventory.find(_save, selected_id).get("slot", "") != slot_filter:
		selected_id = _default_selection()
	for item in shown:
		var id := int(item["id"])
		var button := Button.new()
		button.name = "item_%d" % id
		button.text = "%s%s\n%s%s" % [Loot.item_name(item), " · angelegt" if Inventory.is_equipped(_save, id) else "",
				Loot.stats_text(item), " · " + Loot.effect_name(item) if Loot.effect_of(item) != "" else ""]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # schmale Fenster: Werte brechen um
		button.toggle_mode = true
		button.button_group = _group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, ROW_ICON + 2 * ICON_INSET)
		for state in _row_styles:
			button.add_theme_stylebox_override(state, _row_styles[state])
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			button.add_theme_color_override(state, Loot.color_of(item["rarity"]))
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(select.bind(id))
		button.focus_entered.connect(select.bind(id))  # Pfeiltasten wählen mit
		_list.add_child(button)
		button.add_child(_place_icon(ItemIconView.of_item(item, ROW_ICON), false))
		buttons[button.name] = button
	if buttons.has("item_%d" % selected_id):
		buttons["item_%d" % selected_id].set_pressed_no_signal(true)
	_refresh_sheet()
	_show_detail()


## Gewählt wird beim Wechsel des Platzes: das neueste nicht angelegte Teil der gezeigten Liste, sonst das neueste.
func _default_selection() -> int:
	var shown := Inventory.items(_save).filter(func(item): return slot_filter == "" or item["slot"] == slot_filter)
	shown.reverse()
	for item in shown:
		if not Inventory.is_equipped(_save, int(item["id"])):
			return int(item["id"])
	return int(shown[0]["id"]) if not shown.is_empty() else 0


## Charakterblatt: Plätze mit angelegtem Teil (oder „leer“), Fahrer, Summe der Werte, Stärke gegen empfohlene Stärke.
func _refresh_sheet() -> void:
	var worn := Inventory.equipped(_save)
	for slot in Loot.SLOTS:
		var button: Button = buttons["slot_" + slot]
		var item: Dictionary = worn.get(slot, {})
		button.text = "%s\n%s" % [Loot.SLOTS[slot]["name"], "leer" if item.is_empty()
				else "%s\n%s" % [Loot.item_name(item), Loot.stats_text(item).replace(" · ", "\n")]]
		if item.is_empty():
			_slot_icons[slot].show_empty(slot)
		else:
			_slot_icons[slot].show_item(item)
		var color: Color = COLOR_SAME if item.is_empty() else Loot.color_of(item["rarity"])
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color",
				"font_hover_pressed_color"]:
			button.add_theme_color_override(state, color)
		button.set_pressed_no_signal(slot == slot_filter)
	preview.reset_look()
	preview.wear(Wardrobe.outfit(Wardrobe.selection(_save)))
	preview.wear(Loot.appearance(worn))
	var modifiers := Inventory.modifiers(_save)
	var sums := []
	for stat in Loot.STATS:
		if int(modifiers.get(stat, 0)) > 0:
			sums.append(Loot.stat_text(stat, modifiers[stat]))
	_totals.text = "Summe: %s" % (" · ".join(sums) if not sums.is_empty() else "noch keine Werte")
	var tier := ArcadeTiers.selection(_save)
	var own := ArcadeTiers.strength(_save)
	var recommended := ArcadeTiers.recommended_strength(tier)
	_strength.text = "Stärke %d / empfohlen %d (Stufe %d)" % [own, recommended, tier]
	_strength.add_theme_color_override("font_color", COLOR_OK if own >= recommended else COLOR_WARN)


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
		_detail_effect.text = ""
		_detail_icon.visible = false
		_compare_icon.visible = false
		_set_enabled(equip, false)
		_set_enabled(salvage, false)
		salvage.text = "Verwerten"
		return
	var worn := Inventory.is_equipped(_save, selected_id)
	_detail_icon.visible = true
	_detail_icon.show_item(item)
	_detail_name.text = Loot.item_name(item)
	_detail_name.add_theme_color_override("font_color", Loot.color_of(item["rarity"]))
	_detail_stats.text = Loot.stats_text(item).replace(" · ", "\n")
	_detail_effect.text = "Effekt: %s\n%s" % [Loot.effect_name(item), Loot.effect_text(item)] \
			if Loot.effect_of(item) != "" else ""
	var current: Dictionary = Inventory.equipped(_save).get(item["slot"], {})
	_compare_icon.visible = not worn  # das angelegte Teil neben dem gewählten; ist es das gewählte, steht es schon oben
	if current.is_empty():
		_compare_icon.show_empty(item["slot"])
	else:
		_compare_icon.show_item(current)
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
	_row_styles = _padded_styles(ROW_ICON + ICON_INSET + 12.0, 0.0)
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
	_build_sheet(body)
	var right := VBoxContainer.new()
	right.name = "Side"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	var items := PanelContainer.new()
	items.name = "Items"
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.add_theme_stylebox_override("panel", _panel_style(0.78, 12))
	right.add_child(items)
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
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.3  # das große Symbol und der Vergleich brauchen etwas mehr Höhe als die Liste
	side.add_theme_stylebox_override("panel", _panel_style(0.78, 14))
	right.add_child(side)
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
	var header_margin := _inset(detail, "DetailHeaderMargin")  # Platz für das Leuchten im Scrollbereich
	var header := HBoxContainer.new()
	header.name = "DetailHeader"
	header.add_theme_constant_override("separation", 14)
	header_margin.add_child(header)
	_detail_icon = _plain_icon(DETAIL_ICON, "DetailIcon")
	header.add_child(_detail_icon)
	var heading_texts := VBoxContainer.new()
	heading_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading_texts)
	_detail_name = Label.new()
	_detail_name.name = "Name"
	_detail_name.add_theme_font_size_override("font_size", 24)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_texts.add_child(_detail_name)
	_detail_stats = Label.new()
	_detail_stats.name = "Stats"
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # schmal: Werte brechen um statt das Fenster zu sprengen
	_detail_stats.add_theme_font_size_override("font_size", 17)
	heading_texts.add_child(_detail_stats)
	_detail_effect = Label.new()
	_detail_effect.name = "Effect"
	_detail_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_effect.add_theme_font_size_override("font_size", 17)
	_detail_effect.add_theme_color_override("font_color", Loot.color_of(Loot.LEGENDARY))
	detail.add_child(_detail_effect)
	var compare_margin := _inset(detail, "CompareMargin")
	var compare_row := HBoxContainer.new()
	compare_row.name = "CompareRow"
	compare_row.add_theme_constant_override("separation", 12)
	compare_margin.add_child(compare_row)
	_compare_icon = _plain_icon(COMPARE_ICON, "CompareIcon")
	compare_row.add_child(_compare_icon)
	_compare = VBoxContainer.new()
	_compare.name = "Compare"
	_compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compare.add_theme_constant_override("separation", 2)
	compare_row.add_child(_compare)
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


## Charakterblatt links: der Fahrer (Vorschau der Garderobe) in der Mitte, drei Plätze auf jeder Seite, darunter Summe
## und Stärke. Fahrer und Plätze scrollen, wenn sie nicht in die Höhe passen; Summe und Stärke bleiben sichtbar.
func _build_sheet(parent: Container) -> void:
	_slot_group = ButtonGroup.new()
	_slot_group.allow_unpress = true
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_stretch_ratio = 1.5
	sheet.add_theme_stylebox_override("panel", _panel_style(0.78, 14))
	parent.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	sheet.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.name = "SheetScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var figure := HBoxContainer.new()
	figure.name = "Figure"
	figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
	figure.add_theme_constant_override("separation", 8)
	scroll.add_child(figure)
	_slot_column(figure, "LeftSlots", LEFT_SLOTS)
	var frame := RIDER_PREVIEW.new()
	frame.custom_minimum_size = Vector2(170, 170)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.2
	figure.add_child(frame)
	preview = frame.model
	_slot_column(figure, "RightSlots", RIGHT_SLOTS)
	_totals = Label.new()
	_totals.name = "Totals"
	_totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_totals.add_theme_font_size_override("font_size", 17)
	column.add_child(_totals)
	_strength = Label.new()
	_strength.name = "Strength"
	_strength.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strength.add_theme_font_size_override("font_size", 20)
	column.add_child(_strength)


func _slot_column(parent: Container, node_name: String, slots: Array) -> void:
	var column := VBoxContainer.new()
	column.name = node_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)
	if _slot_styles.is_empty():
		var selected := _panel_style(0.95, 6)
		selected.set_border_width_all(3)
		selected.border_color = COLOR_HEADING
		selected.set_corner_radius_all(4)
		_slot_styles = _padded_styles(0.0, SLOT_ICON + 2 * ICON_INSET, selected)
	for slot in slots:
		var button := Button.new()
		button.name = "slot_" + slot
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER  # unter dem Symbol
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.toggle_mode = true
		button.button_group = _slot_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(140, 80)
		button.add_theme_font_size_override("font_size", 15)
		for state in _slot_styles:  # gewählter Platz (pressed): goldener Rahmen; oben Platz für das Symbol
			button.add_theme_stylebox_override(state, _slot_styles[state])
		button.pressed.connect(select_slot.bind(slot))
		column.add_child(button)
		var icon := ItemIconView.of_slot(slot, SLOT_ICON)
		button.add_child(_place_icon(icon, true))
		_slot_icons[slot] = icon
		buttons[button.name] = button


## Knopfstile (Zustand → Stil) mit mindestens `left` bzw. `top` px Innenrand, in dem das Symbol im Knopf Platz hat;
## `selected` ersetzt den Stil des gedrückten Knopfes. Einmal gebaut und von allen Knöpfen einer Art geteilt.
func _padded_styles(left: float, top: float, selected: StyleBox = null) -> Dictionary:
	var probe := Button.new()
	var styles := {}
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style: StyleBox = (selected if selected != null and state.ends_with("pressed")
				else probe.get_theme_stylebox(state)).duplicate()
		style.set_content_margin(SIDE_LEFT, maxf(left, style.get_margin(SIDE_LEFT)))
		style.set_content_margin(SIDE_TOP, maxf(top, style.get_margin(SIDE_TOP)))
		styles[state] = style
	probe.free()
	return styles


## Symbol `icon` im Knopf platzieren: oben mittig (`on_top`) oder links in der Mitte; der Knopf behält Fokus und Klick.
func _place_icon(icon: ItemIconView, on_top: bool) -> ItemIconView:
	var px := icon.icon_size
	if on_top:
		icon.anchor_left = 0.5
		icon.anchor_right = 0.5
		icon.anchor_top = 0.0
		icon.anchor_bottom = 0.0
		icon.offset_left = -px / 2.0
		icon.offset_right = px / 2.0
		icon.offset_top = ICON_INSET
		icon.offset_bottom = ICON_INSET + px
	else:
		icon.anchor_left = 0.0
		icon.anchor_right = 0.0
		icon.anchor_top = 0.5
		icon.anchor_bottom = 0.5
		icon.offset_left = ICON_INSET
		icon.offset_right = ICON_INSET + px
		icon.offset_top = -px / 2.0
		icon.offset_bottom = px / 2.0
	return icon


## Leeres Symbol für das Detail (der Inhalt kommt mit `show_item`), oben bündig.
func _plain_icon(px: float, node_name: String) -> ItemIconView:
	var icon := ItemIconView.new()
	icon.icon_size = px
	icon.name = node_name
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.visible = false
	return icon


## Rand um einen Bereich im Scrollbereich, damit das Leuchten eines Symbols nicht abgeschnitten wird.
func _inset(parent: Container, node_name: String) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.name = node_name
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(ICON_INSET))  # größer als das Leuchten (9 px bei DETAIL_ICON)
	parent.add_child(margin)
	return margin


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
