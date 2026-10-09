## Elite-Schild im HUD (#52) oben in der Bildmitte, wie das Namensschild über einer Gegnergruppe: Elite-Stufe und
## Herausforderung in der Farbe der Stufe („Champions: Jagd“ blau, „Seltene: Durchbruch“ gelb), darunter die
## Eigenschaften („Windschnell · Zäh“) und die laufende Phase mit ihrem Ziel („Anführer · ab 98 rpm“, „Gefolge 1/1 ·
## 80–100 rpm“). Vor dem Start kündigt es die Gruppe an, nach dem Ende steht das Ergebnis HOLD_S Sekunden. Steht der
## Lebensbalken eines Bosses noch im Bild (`avoid`, BossBar), rückt es darunter. Kind unter dem HUD (`stage.hud`);
## `ride_hud.gd` weiß davon nichts. Nur Anzeige (ADR-0010).
class_name EliteBadge
extends Control

const COLOR_TEXT := Color(0.97, 0.95, 0.9)
const COLOR_FAILED := Color(0.7, 0.72, 0.76)
## So lange steht das Ergebnis (s).
const HOLD_S := 4.0
const TOP_PX := 14.0
const GAP_PX := 8.0
const TITLE_FONT_PX := 24
const LINE_FONT_PX := 15

## Ankündigung, laufende Gruppe, Ergebnis ("" = nicht zu sehen).
const ANNOUNCE := "announce"
const GROUP := "group"
const RESULT := "result"

## Steht dieses Control (mit einem Kind „Panel“) sichtbar oben, rückt das Schild darunter.
var avoid: Control = null
var mode := ""

var _panel: PanelContainer
var _title: Label
var _affixes: Label
var _phase: Label
var _hold_s := 0.0


func _init() -> void:
	name = "EliteBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_title = _label("Title", TITLE_FONT_PX)
	box.add_child(_title)
	_affixes = _label("Affixes", LINE_FONT_PX)
	box.add_child(_affixes)
	_phase = _label("Phase", LINE_FONT_PX)
	box.add_child(_phase)


## Die Elite-Gruppe `definition` liegt `meters` voraus (noch nicht begonnen).
func announce(definition: Dictionary, meters: int) -> void:
	var retinue: int = definition.get("phases", []).filter(func(d): return d.get("retinue", false)).size()
	_show(definition.get("name", ""), EliteGroups.color_of(EliteGroups.rank_of(definition)),
			" · ".join(EliteGroups.affix_names(definition)),
			"voraus · noch %d m%s" % [maxi(meters, 0), " · mit Gefolge (%d)" % retinue if retinue > 0 else ""])
	mode = ANNOUNCE


## Stand der laufenden Gruppe `group` (je Anzeigeschritt): Phase und ihr Ziel.
func show_group(group: EliteGroup) -> void:
	var definition := group.phase_definition()
	var role := "Gefolge %d/%d" % [group.retinue_number(), group.retinue_count()] if group.in_retinue() else "Anführer"
	if not group.in_retinue() and group.index > 0:
		role += " · Taktwechsel"
	_show(group.boss_name, EliteGroups.color_of(group.rank), " · ".join(group.affixes.map(
			func(id): return EliteGroups.AFFIXES[id]["name"])),
			"%s · %s" % [role, Encounters.target_text(definition, group.zone())])
	mode = GROUP


## Die Gruppe ist zu Ende: geschafft oder verfehlt; das Ergebnis steht HOLD_S Sekunden.
func finish(group: EliteGroup) -> void:
	var won := group.state == ChallengeBlock.SUCCEEDED
	_title.text = group.boss_name
	_title.add_theme_color_override("font_color", EliteGroups.color_of(group.rank) if won else COLOR_FAILED)
	_phase.text = "geschafft – Elite-Beute" if won else "verfehlt – weiter geht's"
	_hold_s = HOLD_S
	mode = RESULT
	visible = true


func reset() -> void:
	_hold_s = 0.0
	mode = ""
	visible = false


## Für Tests und Prüfhilfen: Zeilen und Titelfarbe ("" bzw. transparent, wenn nicht zu sehen).
func title_text() -> String:
	return _title.text if visible else ""


func affix_text() -> String:
	return _affixes.text if visible else ""


func phase_text() -> String:
	return _phase.text if visible else ""


func title_color() -> Color:
	return _title.get_theme_color("font_color") if visible else Color.TRANSPARENT


func _show(title: String, color: Color, affixes: String, line: String) -> void:
	_hold_s = 0.0
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_affixes.text = affixes
	_phase.text = line
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	var scale := RideHud.text_scale(get_viewport_rect().size.y)
	_title.add_theme_font_size_override("font_size", roundi(TITLE_FONT_PX * scale))
	_affixes.add_theme_font_size_override("font_size", roundi(LINE_FONT_PX * scale))
	_phase.add_theme_font_size_override("font_size", roundi(LINE_FONT_PX * scale))
	var top := TOP_PX * scale
	var above := avoid.get_node_or_null("Panel") as Control if avoid != null and avoid.visible else null
	if above != null:
		top = above.position.y + above.size.y + GAP_PX * scale
	_panel.offset_top = top
	_panel.offset_left = -_panel.size.x / 2.0
	_panel.offset_right = _panel.size.x / 2.0
	if _hold_s > 0.0:
		_hold_s -= delta
		if _hold_s <= 0.0:
			reset()


func _label(node_name: String, size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	return label
