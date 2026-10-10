## Lebensbalken eines Bosses (#51) oben in der Bildmitte: Name des Bosses, ein roter Balken (voll = unverletzt), darunter
## die laufende Phase mit ihrem Ziel und ihrer Restzeit („Phase 2/3 · Böe · ab 105 rpm · noch 12 s“). Nach dem Kampf steht
## dort kurz „Tramuntana besiegt!“ (gold) oder „Tramuntana entkommen – weiter geht's“ (grau), dann verschwindet er. Hängt
## als Kind unter dem HUD (`stage.hud`); `ride_hud.gd` weiß davon nichts. Nur Anzeige (ADR-0010).
class_name BossBar
extends Control

const COLOR_TITLE := Color(1.0, 0.95, 0.88)
const COLOR_FILL := Color(0.86, 0.16, 0.12)
const COLOR_BACK := Color(0.12, 0.05, 0.05, 0.85)
const COLOR_DEFEATED := Color(1.0, 0.86, 0.35)
const COLOR_ESCAPED := Color(0.7, 0.72, 0.76)
## So lange steht das Ergebnis des Kampfes (s).
const HOLD_S := 4.0
const WIDTH_PX := 420.0
const BAR_PX := 18.0
const TOP_PX := 14.0
const TITLE_FONT_PX := 24
const PHASE_FONT_PX := 15

## Angezeigter Lebensbalken (1 = voll).
var health := 1.0

var _panel: PanelContainer
var _title: Label
var _bar: ProgressBar
var _phase: Label
var _hold_s := 0.0


func _init() -> void:
	name = "BossBar"
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
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	_title = _label("Title", TITLE_FONT_PX)
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.name = "Life"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = COLOR_FILL
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = COLOR_BACK
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)
	_phase = _label("Phase", PHASE_FONT_PX)
	box.add_child(_phase)


## Ein Kampf beginnt: Name `title`, Balken voll.
func start(title: String) -> void:
	_hold_s = 0.0
	_title.text = title
	_title.add_theme_color_override("font_color", COLOR_TITLE)
	_phase.text = ""
	_set_health(1.0)
	visible = true


## Stand des Kampfes `boss` (je Anzeigeschritt): Lebensbalken, Phase, Ziel, Restzeit der Phase.
func show_fight(boss: BossFight) -> void:
	_set_health(boss.health())
	var phase := boss.current_phase()
	_phase.text = "Phase %d/%d · %s · %s · noch %d s" % [boss.phase_number(), boss.phase_count(),
			boss.phase_definition().get("name", ""), Encounters.target_text(boss.phase_definition(), phase.zone()),
			ceili(phase.remaining_s())]


## Der Kampf ist zu Ende: besiegt (`defeated`) oder entkommen; das Ergebnis steht HOLD_S Sekunden.
func finish(boss: BossFight) -> void:
	var defeated := boss.state == ChallengeBlock.SUCCEEDED
	_set_health(boss.health())
	_title.text = "%s besiegt!" % boss.boss_name if defeated else "%s entkommen" % boss.boss_name
	_title.add_theme_color_override("font_color", COLOR_DEFEATED if defeated else COLOR_ESCAPED)
	_phase.text = "Boss-Beute gefunden" if defeated else "weiter geht's"
	_hold_s = HOLD_S
	visible = true


func reset() -> void:
	_hold_s = 0.0
	visible = false


## Für Tests und Prüfhilfen: Titel und Phasenzeile ("" wenn nicht zu sehen).
func title_text() -> String:
	return _title.text if visible else ""


func phase_text() -> String:
	return _phase.text if visible else ""


func _process(delta: float) -> void:
	if not visible:
		return
	var height := get_viewport_rect().size.y
	var scale := RideHud.text_scale(height)
	_title.add_theme_font_size_override("font_size", roundi(TITLE_FONT_PX * scale))
	_phase.add_theme_font_size_override("font_size", roundi(PHASE_FONT_PX * scale))
	_bar.custom_minimum_size = Vector2(WIDTH_PX * scale, BAR_PX * scale)
	_panel.offset_top = TOP_PX * scale
	_panel.offset_left = -_panel.size.x / 2.0
	_panel.offset_right = _panel.size.x / 2.0
	if _hold_s > 0.0:
		_hold_s -= delta
		if _hold_s <= 0.0:
			visible = false


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, 1.0)
	_bar.value = health


func _label(node_name: String, size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	return label
