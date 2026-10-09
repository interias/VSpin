## Anzeige der Fähigkeiten (#50, Spec #27 Story 14): eine Leiste mit je einer Plakette je Fähigkeit über dem unteren Panel des
## HUD – „bereit“ (grün, mit dem auslösenden Kadenzmuster), „aktiv“ (gold, mit Restzeit der Wirkung) oder die Abklingzeit
## (grau) – und eine kurze Einblendung „Windböe ausgelöst“, wenn eine Fähigkeit wirkt. Nur im Arcade sichtbar: ohne
## Arcade-Lauf, im Menü (das HUD ist dort aus) und im Ergebnis ist sie weg. Hängt als Kind unter dem HUD (`stage.hud`), das
## `ride_hud.gd` weiß davon nichts; die Werte liefert die Erweiterung (`AbilityExtension`), sie gehört dem Arcade-Lauf.
class_name AbilityHud
extends Control

const COLOR_READY := Color(0.55, 0.95, 0.6)
const COLOR_ACTIVE := Color(1.0, 0.86, 0.35)
const COLOR_COOLDOWN := Color(0.62, 0.64, 0.68)
## Dauer der Einblendung „ausgelöst“ (s) und Abstand der Leiste über dem unteren Panel (px).
const FLASH_S := 1.8
const GAP_PX := 10.0
const CHIP_WIDTH_PX := 112.0
const NAME_FONT_PX := 18
const STATE_FONT_PX := 13
const FLASH_FONT_PX := 34

## Erweiterung, deren Lauf gezeigt wird (null = immer sichtbar, z. B. in der Prüfhilfe).
var extension: AbilityExtension = null

var _row: HBoxContainer
var _chips := {}
var _flash: Label
var _flash_tween: Tween
var _bottom: Control = null


func _init() -> void:
	name = "AbilityHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_row = HBoxContainer.new()
	_row.name = "Chips"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 8)
	_row.anchor_left = 1.0
	_row.anchor_right = 1.0
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row.offset_right = -16.0
	_row.offset_bottom = -170.0
	add_child(_row)
	for id in Abilities.IDS:
		_chips[id] = _new_chip(id)
	_flash = Label.new()
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_color_override("font_color", COLOR_ACTIVE)
	_flash.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_flash.add_theme_constant_override("outline_size", 8)
	_flash.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_flash.visible = false
	add_child(_flash)


func _ready() -> void:
	var hud := get_parent()
	_bottom = hud.get_node_or_null("%Bottom") as Control if hud != null else null


func _process(_delta: float) -> void:
	var shown := extension == null or extension.is_shown()
	visible = shown
	if not shown:
		return
	var height := get_viewport_rect().size.y
	var scale := RideHud.text_scale(height)
	for id in _chips:
		_chips[id]["name"].add_theme_font_size_override("font_size", roundi(NAME_FONT_PX * scale))
		_chips[id]["state"].add_theme_font_size_override("font_size", roundi(STATE_FONT_PX * scale))
		_chips[id]["panel"].custom_minimum_size.x = CHIP_WIDTH_PX * scale
	_flash.add_theme_font_size_override("font_size", roundi(FLASH_FONT_PX * scale))
	_flash.offset_top = height * 0.2
	_flash.offset_bottom = height * 0.2 + FLASH_FONT_PX * 1.6 * scale
	if _bottom != null and _bottom.is_inside_tree():
		_row.offset_bottom = _bottom.get_global_rect().position.y - height - GAP_PX


## Zustand der Fähigkeiten übernehmen (`abilities` des Laufs).
func refresh(abilities: Abilities) -> void:
	for id in Abilities.IDS:
		var chip: Dictionary = _chips[id]
		var def: Dictionary = abilities.defs[id]
		var state := abilities.state_of(id)
		var color := COLOR_READY
		var text: String = "%s · bereit" % CadencePatterns.NAMES[def["pattern"]]
		if state == "active":
			color = COLOR_ACTIVE
			text = "aktiv · %d s" % ceili(abilities.active_left_s(id))
		elif state == "cooldown":
			color = COLOR_COOLDOWN
			text = "%d s" % ceili(abilities.cooldown_left_s(id))
		chip["name"].text = def["name"]
		chip["state"].text = text
		chip["name"].add_theme_color_override("font_color", color)
		chip["state"].add_theme_color_override("font_color", color)
		chip["status"] = state


## Einblendung „… ausgelöst“ (blendet in FLASH_S aus).
func flash(text: String) -> void:
	_flash.text = text
	_flash.visible = true
	_flash.modulate.a = 1.0
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, FLASH_S * 0.4).set_delay(FLASH_S * 0.6)
	_flash_tween.tween_callback(func(): _flash.visible = false)


## Für Tests und Prüfhilfen: Text der Plakette (`Name · Zustand`), ihr Zustand und die Einblendung ("" = keine).
func chip_text(id: String) -> String:
	return "%s · %s" % [_chips[id]["name"].text, _chips[id]["state"].text]


func chip_state(id: String) -> String:
	return _chips[id].get("status", "")


func flash_text() -> String:
	return _flash.text if _flash.visible else ""


func _new_chip(id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = id
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", NAME_FONT_PX)
	box.add_child(name_label)
	var state_label := Label.new()
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_label.add_theme_font_size_override("font_size", STATE_FONT_PX)
	box.add_child(state_label)
	_row.add_child(panel)
	return {"panel": panel, "name": name_label, "state": state_label}
