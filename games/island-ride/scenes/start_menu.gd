## Startmenü der Inselfahrt (#30): Titel über dem Kameraflug, Menüpunkte und unten dauerhaft der Status des Rads.
##   Fahren        → Modus-Auswahl: Rundfahrt, Training, Arcade
##   Rundfahrt     → Rundenzahl (1–n oder endlos), Richtung (im / gegen den Uhrzeigersinn, #34), Tageszeit (wie im
##                   Einstellungsmenü), Ghost (aus, Bestzeit, letzte Fahrt; ohne Aufzeichnung ausgegraut, #32), Bestzeit
##                   der gewählten Richtung; „Losfahren“ (#31)
##   Training      → Einheit (aus `res://trainings`, Training.load_all) mit Beschreibung und Dauer; „Losfahren“ (#37)
##   Arcade        → Stufe (ArcadeTiers, drei) mit Beschreibung, persönlicher Kadenzbereich (von/bis, CadenceRange),
##                   beste Punktzahl der Stufe; „Losfahren“ (#46). Der Kadenzbereich steht hier, weil er nur im Arcade
##                   wirkt (Grenze aller Zielzonen) und vor dem Losfahren gewählt wird wie die Stufe. „Ausrüstung“ öffnet
##                   das Inventar der Beute (#49) – aus demselben Grund hier und nicht auf der Hauptseite.
##   Fahrtenbuch   öffnet das Fahrtenbuch (Statistik, Bestzeiten, Erfolge, letzte Fahrten; #35)
##   Garderobe     öffnet die Garderobe (Trikot, Radfarbe, Helm mit Vorschau; #36)
##   Einstellungen öffnet das Menü „Grafik und Fenster“ (wie F2)
##   Beenden       beendet das Spiel (nicht im Browser; nur Enter oder Klick, nie die Leertaste – #19)
## Bedienung mit Maus und Tastatur (Pfeiltasten/Tab, Enter/Leertaste); beim Öffnen liegt der Fokus auf dem ersten
## Punkt. Was gewählt wird, meldet das Menü als Signal; den Szenenfluss steuert die Hauptszene.
## Layout nur über Anker und Container: passt im Halbbild-Fenster (960×1040) wie im Vollbild.
extends CanvasLayer

## „Fahren → Rundfahrt → Losfahren“ gewählt (Modus wie SaveGame.MODE_*); Rundenzahl und Tageszeit siehe
## `round_trip_laps()`, `ride_direction()`, `time_index()` und `ghost_choice()`. „Fahren → Training → Losfahren“: Modus
## SaveGame.MODE_TRAINING, die Einheit liefert `training_unit()`. „Fahren → Arcade → Losfahren“: Modus
## SaveGame.MODE_ARCADE, Stufe und Kadenzbereich liefern `arcade_tier()` und `cadence_range()`.
signal ride_requested(mode: String)
## Stufe oder Kadenzbereich auf der Seite „Arcade“ geändert (#46); die Hauptszene speichert sie.
signal arcade_changed
## Richtung auf der Seite „Rundfahrt“ gewechselt (Track.DIRECTION_*): Bestzeit und Ghosts gelten je Richtung (#34).
signal direction_changed(direction: String)
## „Fahrtenbuch“ gewählt (#35).
signal logbook_requested
## „Garderobe“ gewählt (#36).
signal wardrobe_requested
## „Fahren → Arcade → Ausrüstung“ gewählt (#49).
signal gear_requested
## „Fahren → Arcade → Talente“ gewählt (#53).
signal talents_requested
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
## Hinweis im Radstatus ohne Bus: Bridge von Hand starten.
const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"
## Rundenzahlen zur Auswahl; 0 = endlos.
const LAP_CHOICES := [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 0]
## Richtungen zur Auswahl (#34): im Uhrzeigersinn (Standard), gegen den Uhrzeigersinn.
const DIRECTION_CHOICES := [Track.DIRECTION_CW, Track.DIRECTION_CCW]
## Ghost-Auswahl (#32): aus, Bestzeit-Runde, letzte Fahrt.
const GHOST_CHOICES := ["", Ghost.BEST, Ghost.LAST]

## Läuft im Browser? (Vor `_ready` überschreibbar, für Tests.)
var web := OS.has_feature("web")

## Knöpfe je Menüpunkt (Schlüssel: drive, round_trip, training, arcade, back, logbook, wardrobe, settings, quit;
## auf der Seite „Rundfahrt“: start, trip_back; auf der Seite „Training“: training_start, training_back; auf der Seite
## „Arcade“: arcade_start, arcade_gear, arcade_talents, arcade_back).
var buttons := {}
## Auswahlfelder der Seite „Rundfahrt“ (Schlüssel: laps, direction, time, ghost), der Seite „Training“ (unit) und der
## Seite „Arcade“ (tier, cadence_min, cadence_max).
var options := {}
## Einheiten zur Auswahl auf der Seite „Training“ (wie Training.load_file).
var training_units: Array = []
## Ghost selbst gewählt? Dann bleibt die Wahl, solange sie verfügbar ist; sonst gilt der Standard.
var _ghost_picked := false
var _main_page: VBoxContainer
var _mode_page: VBoxContainer
var _trip_page: VBoxContainer
var _training_page: VBoxContainer
var _arcade_page: VBoxContainer
var _arcade_info: Label
var _arcade_best: Label
var _arcade_level: Label
var _best_label: Label
var _training_info: Label
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
	_trip_page.visible = false
	_training_page.visible = false
	_arcade_page.visible = false
	if visible:
		focus_default()


## Seite „Rundfahrt“: Rundenzahl, Tageszeit, Bestzeit; Fokus auf „Losfahren“.
func show_round_trip() -> void:
	_main_page.visible = false
	_mode_page.visible = false
	_trip_page.visible = true
	_training_page.visible = false
	_arcade_page.visible = false
	if visible:
		focus_default()


## Seite „Training“: Einheit mit Beschreibung; Fokus auf „Losfahren“.
func show_training() -> void:
	_main_page.visible = false
	_mode_page.visible = false
	_trip_page.visible = false
	_training_page.visible = true
	_arcade_page.visible = false
	if visible:
		focus_default()


## Seite „Arcade“: Stufe, Kadenzbereich, beste Punktzahl; Fokus auf „Losfahren“.
func show_arcade() -> void:
	_main_page.visible = false
	_mode_page.visible = false
	_trip_page.visible = false
	_training_page.visible = false
	_arcade_page.visible = true
	if visible:
		focus_default()


## Fokus auf den ersten wählbaren Punkt der sichtbaren Seite (z. B. nach dem Schließen der Einstellungen).
func focus_default() -> void:
	var first: Button = buttons["drive"]
	if _trip_page.visible:
		first = buttons["start"]
	elif _training_page.visible:
		first = buttons["training_start"] if not buttons["training_start"].disabled else buttons["training_back"]
	elif _arcade_page.visible:
		first = buttons["arcade_start"]
	elif _mode_page.visible:
		first = buttons["round_trip"]
	first.grab_focus()


## Gewählte Rundenzahl (0 = endlos).
func round_trip_laps() -> int:
	return LAP_CHOICES[maxi((options["laps"] as OptionButton).selected, 0)]


## Gewählte Fahrtrichtung (Track.DIRECTION_*).
func ride_direction() -> String:
	return DIRECTION_CHOICES[maxi((options["direction"] as OptionButton).selected, 0)]


## Tageszeit-Auswahl der Seite „Rundfahrt“: Beschriftungen wie im Einstellungsmenü und der gewählte Eintrag.
func set_time_choices(labels: Array, selected: int) -> void:
	var option: OptionButton = options["time"]
	option.clear()
	for label in labels:
		option.add_item(label)
	option.select(selected)


## Index der gewählten Tageszeit (wie im Einstellungsmenü).
func time_index() -> int:
	return (options["time"] as OptionButton).selected


## Ghost-Auswahl: Einträge ohne Aufzeichnung ausgegraut. Standard ist die Bestzeit-Runde, sobald es sie gibt,
## sonst aus; eine eigene, noch verfügbare Wahl bleibt.
func set_ghost_choices(best_available: bool, last_available: bool) -> void:
	var option: OptionButton = options["ghost"]
	option.set_item_disabled(GHOST_CHOICES.find(Ghost.BEST), not best_available)
	option.set_item_disabled(GHOST_CHOICES.find(Ghost.LAST), not last_available)
	if not _ghost_picked or option.is_item_disabled(option.selected):
		option.select(GHOST_CHOICES.find(Ghost.BEST) if best_available else 0)


## Gewählter Ghost (Ghost.BEST/LAST, "" = aus).
func ghost_choice() -> String:
	var option: OptionButton = options["ghost"]
	return "" if option.selected < 0 or option.is_item_disabled(option.selected) else GHOST_CHOICES[option.selected]


## Einheiten für die Seite „Training“ (in dieser Reihenfolge); ohne Einheit ist „Losfahren“ ausgegraut.
func set_training_units(units: Array) -> void:
	training_units = units
	var option: OptionButton = options["unit"]
	option.clear()
	for unit in units:
		option.add_item(unit["name"])
	if not units.is_empty():
		option.select(0)
	var button: Button = buttons["training_start"]
	button.disabled = units.is_empty()
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	_show_training_info()


## Gewählte Einheit ({} = keine).
func training_unit() -> Dictionary:
	var index := (options["unit"] as OptionButton).selected
	return training_units[index] if index >= 0 and index < training_units.size() else {}


## Beschreibung und Dauer der gewählten Einheit, z. B. „10 × 30 s hart / 30 s locker · 23 min“.
func _show_training_info() -> void:
	var unit := training_unit()
	if unit.is_empty():
		_training_info.text = "Keine Einheit gefunden"
		return
	var text: String = unit["description"]
	_training_info.text = "%s%d min" % [text + " · " if not text.is_empty() else "",
			roundi(Training.new(unit).duration_s() / 60.0)]


## Seite „Arcade“: Stufe `tier` (ArcadeTiers) und Kadenzbereich `range_` auswählen. Grenzen, die nicht in der Auswahl
## stehen, nehmen den nächsten Eintrag.
func set_arcade_choices(tier: int, range_: CadenceRange) -> void:
	(options["tier"] as OptionButton).select(maxi(ArcadeTiers.LIST.find(ArcadeTiers.get_tier(tier)), 0))
	(options["cadence_min"] as OptionButton).select(_nearest(CadenceRange.MIN_CHOICES, range_.minimum))
	(options["cadence_max"] as OptionButton).select(_nearest(CadenceRange.MAX_CHOICES, range_.maximum))
	_show_arcade_info()


## Gewählte Stufe (ArcadeTiers).
func arcade_tier() -> int:
	return ArcadeTiers.LIST[maxi((options["tier"] as OptionButton).selected, 0)]["tier"]


## Gewählter Kadenzbereich.
func cadence_range() -> CadenceRange:
	return CadenceRange.new(CadenceRange.MIN_CHOICES[maxi((options["cadence_min"] as OptionButton).selected, 0)],
			CadenceRange.MAX_CHOICES[maxi((options["cadence_max"] as OptionButton).selected, 0)])


## Arcade-Level (#53); der Knopf „Talente“ zeigt die freien Talentpunkte.
func show_arcade_level(level: int, free_points: int) -> void:
	_arcade_level.text = "Arcade-Level %d" % level
	buttons["arcade_talents"].text = "Talente (%d)" % free_points if free_points > 0 else "Talente"


## Beste Punktzahl der gewählten Stufe (0 = noch keine).
func show_arcade_best(points: int) -> void:
	_arcade_best.text = "Bestpunktzahl: %s" % (str(points) if points > 0 else "noch keine")


func _on_arcade_option(_index: int) -> void:
	_show_arcade_info()
	arcade_changed.emit()


func _show_arcade_info() -> void:
	_arcade_info.text = ArcadeTiers.get_tier(arcade_tier())["description"]


static func _nearest(choices: Array, value: float) -> int:
	var best := 0
	for i in range(choices.size()):
		if absf(choices[i] - value) < absf(choices[best] - value):
			best = i
	return best


## Bestzeit der Strecke anzeigen, als fertiger Zeittext ("" = noch keine).
func show_best_time(time_text: String) -> void:
	_best_label.text = "Bestzeit: %s" % (time_text if not time_text.is_empty() else "noch keine")


## Menüpunkte ausblenden, solange darüber die Einstellungen offen sind (Titel und Radstatus bleiben).
func set_covered(covered: bool) -> void:
	_panel.visible = not covered  # der Platz bleibt, der Radstatus steht weiter unten
	if not covered and visible:
		focus_default.call_deferred()  # nach dem Schließen der Einstellungen (die geben ihren Fokus erst danach ab)


## Radstatus unten im Menü aus dem Zustand des Bus-Clients.
## `bridge_hint`: Hinweis des Bridge-Starts im Spiel (BridgeLauncher.hint), "" = Standardhinweis.
func show_wheel_status(bus: BusClient, bridge_hint := "") -> void:
	var status := wheel_status(bus.bus_connected, bus.status, bus.source, bridge_hint)
	_status_label.text = status[0]
	_status_dot.add_theme_color_override("font_color", status[1])


## Radstatus als [Text, Farbe]: Bridge nicht erreichbar, Simulator läuft, Rad verbunden – oder die Bridge läuft,
## aber das Rad meldet sich nicht (`stale`/`disconnected`). Ohne Bus ergänzt `bridge_hint` (Start aus dem Spiel, z. B.
## „Programm fehlt: …“) den Text statt des Hinweises zum Start von Hand.
static func wheel_status(bus_connected: bool, status: String, source: String, bridge_hint := "") -> Array:
	if not bus_connected:
		return ["Bridge nicht erreichbar – " + (bridge_hint if not bridge_hint.is_empty() else BRIDGE_START_HINT),
				COLOR_ERROR]
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
	_add_button(_main_page, "logbook", "Fahrtenbuch", logbook_requested.emit)
	_add_button(_main_page, "wardrobe", "Garderobe", wardrobe_requested.emit)
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
	_add_button(_mode_page, "round_trip", "Rundfahrt", show_round_trip)
	_add_button(_mode_page, "training", "Training", show_training)
	_add_button(_mode_page, "arcade", "Arcade", show_arcade)
	_add_button(_mode_page, "back", "Zurück", show_page.bind(false))
	_trip_page = _page(pages, "RoundTrip")
	var trip_heading := Label.new()
	trip_heading.text = "Rundfahrt"
	trip_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trip_heading.add_theme_font_size_override("font_size", 26)
	_trip_page.add_child(trip_heading)
	var grid := GridContainer.new()
	grid.columns = 4  # zwei Felder je Zeile: mit der Richtung (#34) passten vier Zeilen nicht mehr in 1152×648
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	_trip_page.add_child(grid)
	_add_option(grid, "laps", "Runden", LAP_CHOICES.map(func(n): return "Endlos" if n == 0 else str(n)))
	_add_option(grid, "direction", "Richtung", ["Im Uhrzeigersinn", "Gegen den Uhrzeigersinn"])
	options["direction"].item_selected.connect(func(_index): direction_changed.emit(ride_direction()))
	_add_option(grid, "time", "Tageszeit", ["Echtzeit (Mallorca)"])
	_add_option(grid, "ghost", "Ghost", ["Aus", "Bestzeit", "Letzte Fahrt"])
	options["ghost"].item_selected.connect(func(_index): _ghost_picked = true)
	set_ghost_choices(false, false)
	_best_label = Label.new()
	_best_label.name = "BestTime"
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trip_page.add_child(_best_label)
	show_best_time("")
	var actions := HBoxContainer.new()  # nebeneinander: mit der Ghost-Zeile passt die Seite sonst nicht in 1152×648
	actions.add_theme_constant_override("separation", 10)
	_trip_page.add_child(actions)
	_add_button(actions, "start", "Losfahren", ride_requested.emit.bind(SaveGame.MODE_ROUND_TRIP))
	_add_button(actions, "trip_back", "Zurück", show_page.bind(true))
	_training_page = _page(pages, "Training")
	var training_heading := Label.new()
	training_heading.text = "Training"
	training_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	training_heading.add_theme_font_size_override("font_size", 26)
	_training_page.add_child(training_heading)
	var training_grid := GridContainer.new()
	training_grid.columns = 2
	training_grid.add_theme_constant_override("h_separation", 16)
	_training_page.add_child(training_grid)
	_add_option(training_grid, "unit", "Einheit", ["–"])
	options["unit"].item_selected.connect(func(_index): _show_training_info())
	_training_info = Label.new()
	_training_info.name = "TrainingInfo"
	_training_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_training_info.custom_minimum_size = Vector2(420, 0)
	_training_page.add_child(_training_info)
	var training_actions := HBoxContainer.new()
	training_actions.add_theme_constant_override("separation", 10)
	_training_page.add_child(training_actions)
	_add_button(training_actions, "training_start", "Losfahren", ride_requested.emit.bind(SaveGame.MODE_TRAINING))
	_add_button(training_actions, "training_back", "Zurück", show_page.bind(true))
	set_training_units(Training.load_all())
	_arcade_page = _page(pages, "Arcade")
	var arcade_heading := Label.new()
	arcade_heading.text = "Arcade"
	arcade_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arcade_heading.add_theme_font_size_override("font_size", 26)
	_arcade_page.add_child(arcade_heading)
	var arcade_grid := GridContainer.new()
	arcade_grid.columns = 2
	arcade_grid.add_theme_constant_override("h_separation", 16)
	arcade_grid.add_theme_constant_override("v_separation", 10)
	_arcade_page.add_child(arcade_grid)
	_add_option(arcade_grid, "tier", "Stufe", ArcadeTiers.LIST.map(func(t): return t["name"]))
	# Kadenzbereich in einer Zeile („von … bis …“): mit zwei Zeilen passte die Seite nicht in 1152×648.
	var range_caption := Label.new()
	range_caption.text = "Kadenzbereich"
	arcade_grid.add_child(range_caption)
	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override("separation", 8)
	arcade_grid.add_child(range_row)
	_add_option(range_row, "cadence_min", "", CadenceRange.MIN_CHOICES.map(func(r): return "%d rpm" % r))
	var until := Label.new()
	until.text = "bis"
	range_row.add_child(until)
	_add_option(range_row, "cadence_max", "", CadenceRange.MAX_CHOICES.map(func(r): return "%d rpm" % r))
	for key in ["cadence_min", "cadence_max"]:
		options[key].custom_minimum_size = Vector2(118, 44)
	for key in ["tier", "cadence_min", "cadence_max"]:
		options[key].item_selected.connect(_on_arcade_option)
	_arcade_info = Label.new()
	_arcade_info.name = "ArcadeInfo"
	_arcade_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arcade_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arcade_info.custom_minimum_size = Vector2(420, 0)
	_arcade_page.add_child(_arcade_info)
	_arcade_best = Label.new()
	_arcade_best.name = "ArcadeBest"
	_arcade_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arcade_level = Label.new()
	_arcade_level.name = "ArcadeLevel"
	_arcade_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arcade_status := HBoxContainer.new()  # Bestpunktzahl und Arcade-Level in einer Zeile (spart Höhe im kleinen Fenster)
	arcade_status.alignment = BoxContainer.ALIGNMENT_CENTER
	arcade_status.add_theme_constant_override("separation", 28)
	_arcade_page.add_child(arcade_status)
	arcade_status.add_child(_arcade_best)
	arcade_status.add_child(_arcade_level)
	var arcade_actions := HBoxContainer.new()
	arcade_actions.add_theme_constant_override("separation", 10)
	_arcade_page.add_child(arcade_actions)
	_add_button(arcade_actions, "arcade_start", "Losfahren", ride_requested.emit.bind(SaveGame.MODE_ARCADE))
	_add_button(arcade_actions, "arcade_gear", "Ausrüstung", gear_requested.emit)
	_add_button(arcade_actions, "arcade_talents", "Talente", talents_requested.emit)
	_add_button(arcade_actions, "arcade_back", "Zurück", show_page.bind(true))
	for key in ["arcade_start", "arcade_gear", "arcade_talents", "arcade_back"]:  # vier nebeneinander: schmaler als 200 px
		buttons[key].custom_minimum_size.x = 150
	set_arcade_choices(ArcadeTiers.DEFAULT, CadenceRange.new())
	show_arcade_best(0)
	show_arcade_level(1, 0)
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


## Auswahlfeld mit Beschriftung `text` in `grid` (zwei Zellen); ohne Text nur das Feld.
func _add_option(grid: Container, key: String, text: String, labels: Array) -> void:
	if not text.is_empty():
		var label := Label.new()
		label.text = text
		grid.add_child(label)
	var option := OptionButton.new()
	option.name = key
	option.custom_minimum_size = Vector2(260, 44)
	for item in labels:
		option.add_item(item)
	option.select(0)
	grid.add_child(option)
	options[key] = option


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
