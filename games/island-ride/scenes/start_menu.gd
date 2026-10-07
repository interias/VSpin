## Startmenü der Inselfahrt (#30): Titel über dem Kameraflug, Menüpunkte und unten dauerhaft der Status des Rads.
##   Fahren        → Modus-Auswahl: Rundfahrt (startet die heutige Fahrt), Training und Arcade noch ausgegraut („bald“)
##   Fahrtenbuch, Garderobe  ausgegraut („bald“)
##   Einstellungen öffnet das Menü „Grafik und Fenster“ (wie F2)
##   Beenden       beendet das Spiel (nicht im Browser; nur Enter oder Klick, nie die Leertaste – #19)
## Bedienung mit Maus und Tastatur (Pfeiltasten/Tab, Enter/Leertaste); beim Öffnen liegt der Fokus auf dem ersten
## Punkt. Was gewählt wird, meldet das Menü als Signal; den Szenenfluss steuert die Hauptszene.
## Layout nur über Anker und Container: passt im Halbbild-Fenster (960×1040) wie im Vollbild.
extends CanvasLayer

## „Fahren → Rundfahrt“ gewählt (Modus wie SaveGame.MODE_*).
signal ride_requested(mode: String)
## „Einstellungen“ gewählt.
signal settings_requested
## „Beenden“ gewählt.
signal quit_requested

const TITLE := "Inselfahrt"
const SUBTITLE := "Radfahren auf einer Mittelmeerinsel"
## Farbe des Punkts vor dem Radstatus.
const COLOR_OK := Color(0.45, 0.85, 0.5)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)

## Läuft im Browser? (Vor `_ready` überschreibbar, für Tests.)
var web := OS.has_feature("web")

## Knöpfe je Menüpunkt (Schlüssel: drive, round_trip, training, arcade, back, logbook, wardrobe, settings, quit).
var buttons := {}
var _main_page: VBoxContainer
var _mode_page: VBoxContainer
var _center: CenterContainer
var _panel: PanelContainer
var _status_dot: Label
var _status_label: Label


func _ready() -> void:
	_build()
	show_page(false)


## Zeigt das Menü (Hauptseite, Fokus auf „Fahren“).
func open() -> void:
	visible = true
	show_page(false)


## Schließt das Menü; der Fokus geht mit (sonst löste die Leertaste in der Fahrt einen verborgenen Knopf aus).
func close() -> void:
	visible = false
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()


## Hauptseite oder Modus-Auswahl („Fahren“); der Fokus liegt auf dem ersten wählbaren Punkt.
func show_page(modes: bool) -> void:
	_main_page.visible = not modes
	_mode_page.visible = modes
	if visible:
		focus_default()


## Fokus auf den ersten wählbaren Punkt der sichtbaren Seite (z. B. nach dem Schließen der Einstellungen).
func focus_default() -> void:
	var first: Button = buttons["round_trip"] if _mode_page.visible else buttons["drive"]
	first.grab_focus()


## Menüpunkte ausblenden, solange darüber die Einstellungen offen sind (Titel und Radstatus bleiben).
func set_covered(covered: bool) -> void:
	_panel.visible = not covered  # der Platz bleibt, der Radstatus steht weiter unten
	if not covered and visible:
		focus_default.call_deferred()  # nach dem Schließen der Einstellungen (die geben ihren Fokus erst danach ab)


## Radstatus unten im Menü aus dem Zustand des Bus-Clients.
func show_wheel_status(bus: BusClient) -> void:
	var status := wheel_status(bus.bus_connected, bus.status, bus.source)
	_status_label.text = status[0]
	_status_dot.add_theme_color_override("font_color", status[1])


## Radstatus als [Text, Farbe]: Bridge nicht erreichbar, Simulator läuft, Rad verbunden – oder die Bridge läuft,
## aber das Rad meldet sich nicht (`stale`/`disconnected`).
static func wheel_status(bus_connected: bool, status: String, source: String) -> Array:
	if not bus_connected:
		return ["Bridge nicht erreichbar – Bridge starten: vspin-bridge --source sim", COLOR_ERROR]
	if status != BusClient.STATE_CONNECTED:
		return ["Bridge läuft – Rad nicht verbunden (%s)" % status, COLOR_WARN]
	match source:
		"sim":
			return ["Simulator läuft", COLOR_OK]
		"replay":
			return ["Replay läuft", COLOR_OK]
	return ["Rad verbunden", COLOR_OK]


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 22
	var layout := Control.new()
	layout.name = "Layout"
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layout.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = SUBTITLE
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	column.add_child(subtitle)
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _panel_style(0.72, 20))
	_center.add_child(_panel)
	var pages := VBoxContainer.new()
	_panel.add_child(pages)
	_main_page = _page(pages, "Main")
	_add_button(_main_page, "drive", "Fahren", show_page.bind(true))
	_add_button(_main_page, "logbook", "Fahrtenbuch – bald", Callable(), true)
	_add_button(_main_page, "wardrobe", "Garderobe – bald", Callable(), true)
	_add_button(_main_page, "settings", "Einstellungen", settings_requested.emit)
	var quit := _add_button(_main_page, "quit", "Beenden", quit_requested.emit)
	quit.visible = not web  # im Browser nicht
	quit.gui_input.connect(_swallow_space.bind(quit))  # nur Enter oder Klick: Leertaste beendet nie (#19)
	_mode_page = _page(pages, "Modes")
	var heading := Label.new()
	heading.text = "Fahren"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 26)
	_mode_page.add_child(heading)
	_add_button(_mode_page, "round_trip", "Rundfahrt", ride_requested.emit.bind(SaveGame.MODE_ROUND_TRIP))
	_add_button(_mode_page, "training", "Training – bald", Callable(), true)
	_add_button(_mode_page, "arcade", "Arcade – bald", Callable(), true)
	_add_button(_mode_page, "back", "Zurück", show_page.bind(false))
	var status := PanelContainer.new()
	status.name = "Status"
	status.add_theme_stylebox_override("panel", _panel_style(0.6, 12))
	status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	status.add_child(row)
	_status_dot = Label.new()
	_status_dot.text = "●"
	row.add_child(_status_dot)
	var caption := Label.new()
	caption.text = "Rad:"
	row.add_child(caption)
	_status_label = Label.new()
	_status_label.name = "WheelStatus"
	row.add_child(_status_label)
	var status_text := wheel_status(false, BusClient.STATE_DISCONNECTED, "")
	_status_label.text = status_text[0]
	_status_dot.add_theme_color_override("font_color", status_text[1])


func _page(parent: Container, page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	return page


func _add_button(parent: Container, key: String, text: String, action: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(300, 52)
	button.disabled = disabled
	button.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	buttons[key] = button
	return button


## Leertaste auf „Beenden“ verschlucken, bevor der Knopf sie als `ui_accept` auslöst.
func _swallow_space(event: InputEvent, button: Button) -> void:
	if event is InputEventKey and (event.keycode == KEY_SPACE or event.physical_keycode == KEY_SPACE):
		button.accept_event()


func _panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, alpha)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(margin)
	return style
