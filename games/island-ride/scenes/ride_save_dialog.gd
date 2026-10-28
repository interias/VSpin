## Dialog „Fahrt speichern“ am Fahrtende (Spec #84, ADR-0008 Nachtrag): fragt, ob die Fahrt gespeichert wird, zeigt den
## Anmeldezustand bei Garmin Connect samt „so geht's“ und das Ergebnis. Die Hauptszene öffnet ihn nur mit Bridge am Bus
## (`open`), denn exportieren kann nur die Bridge (ADR-0008 „nur die Bridge loggt“). Von oben nach unten:
##   Titel, Fahrzeit und Strecke
##   Garmin Connect   Anmeldezustand (`status.garmin`, laufend aktualisiert) und was zu tun ist, dazu der Schalter
##                    „Nach Garmin Connect hochladen“ (Vorgabe: an, wenn angemeldet; die Wahl wird in `settings.cfg`
##                    gemerkt) und der Hinweis auf eine parallel aufzeichnende Uhr
##   Ergebnis         erst „speichert …“, dann Ablageort der FIT-Datei, Importweg in Garmin Connect und die Meldung des
##                    Uploads – oder der Grund, warum keine Datei entstand; keine Antwort heißt: Meldung und Weg zurück
## Knöpfe: „Speichern“ (gesperrt, solange die Antwort aussteht – kein Doppelversand), „Verwerfen“ (sendet nichts, der
## Spielstand ist davon unberührt) und „Weiter“ (nach dem Ergebnis). Nach einem Fehlschlag heißt „Speichern“ „Erneut
## speichern“: dieselbe Fahrt (`ride_id`), die Bridge lädt sie nie doppelt hoch. Die Texte zu Upload und Datei sind die
## der Bridge, hier nur eingefügt.
## Bedienung mit Maus, Tastatur und Controller: Fokus über Pfeiltasten/Tab bzw. Steuerkreuz, Enter/Leertaste. Esc öffnet wie
## überall die Einstellungen darüber. Layout nur über Anker und Container: passt im Halbbild-Fenster wie im Vollbild und in
## 1152×648; der Inhalt scrollt, die Knöpfe bleiben stehen.
extends CanvasLayer

## Dialog zu: weiter ins Menü (nach „Verwerfen“ oder „Weiter“).
signal closed

const STATE_ASK := "ask"
const STATE_SAVING := "saving"
const STATE_DONE := "done"
## So lange wartet das Spiel auf `ride_saved` (s): ein Upload kann dauern.
const REPLY_TIMEOUT_S := 60.0
## Upload-Zustände, nach denen die Fahrt als erledigt gilt (kein „Erneut speichern“).
const UPLOAD_DONE := ["uploaded", "duplicate", "already_uploaded"]
const LOGIN_COMMAND := "python -m vspin_bridge.garmin login"
const INSTALL_COMMAND := "pip install -e \".[garmin]\""
const IMPORT_HINT := "Von Hand in Garmin Connect importieren (Web: „Importieren“) und diese Datei wählen."

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_DIM := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_OK := Color(0.45, 0.85, 0.5)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)
## Breite der Inhaltsspalte (px), soweit das Fenster sie hergibt.
const COLUMN_WIDTH := 880.0

## Knöpfe: save, discard, done.
var buttons := {}
## Texte zum Prüfen und Lesen: summary, login, howto, parallel, status, result_head, result_file, result_import,
## result_upload.
var labels := {}
var upload_check: CheckBox
var state := STATE_ASK
## Wartezeit auf die Antwort (s); Tests verkürzen sie.
var reply_timeout_s := REPLY_TIMEOUT_S
## Letzte Antwort der Bridge (`ride_saved`) und, wenn keine kam, warum (verständliche Meldung); sonst leer.
var reply := {}
var failure := ""

var _bus: BusClient
var _trace: RideTrace
var _settings: GraphicsSettings
var _settings_path := ""
var _waited_s := 0.0
var _margin: MarginContainer
var _scroll: ScrollContainer


func _ready() -> void:
	layer = 8  # über Fahrt und Ergebnis, unter den Einstellungen (10)
	visible = false
	_build()


## Dialog öffnen: `trace` = Angaben der Fahrt, `summary` = Zeile zur Fahrt, `settings` hält die gemerkte Wahl des
## Schalters (gespeichert nach `settings_path`, "" = nur im Speicher). Fokus auf „Speichern“.
func open(bus: BusClient, trace: RideTrace, summary: String, settings: GraphicsSettings, settings_path: String) -> void:
	_bus = bus
	_trace = trace
	_settings = settings
	_settings_path = settings_path
	if not _bus.ride_saved.is_connected(_on_ride_saved):
		_bus.ride_saved.connect(_on_ride_saved)
		_bus.ride_rejected.connect(_on_ride_rejected)
	state = STATE_ASK
	reply = {}
	failure = ""
	_waited_s = 0.0
	labels["summary"].text = summary
	upload_check.set_pressed_no_signal(_settings.garmin_upload if _settings.garmin_upload is bool \
			else _bus.garmin_login == BusClient.GARMIN_LOGGED_IN)
	visible = true
	_scroll.scroll_vertical = 0
	refresh()
	focus_default()


## Schließen ohne weiteres Zutun; die Hauptszene geht danach ins Menü.
func close() -> void:
	if not visible:
		return
	visible = false
	if _bus != null and _bus.ride_saved.is_connected(_on_ride_saved):
		_bus.ride_saved.disconnect(_on_ride_saved)
		_bus.ride_rejected.disconnect(_on_ride_rejected)
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	closed.emit()


func focus_default() -> void:
	if not visible:
		return
	for key in ["save", "done"]:
		var button: Button = buttons[key]
		if button.visible and not button.disabled:
			button.grab_focus()
			return


## „Speichern“: `save_ride` an die Bridge. Solange eine Antwort aussteht, passiert nichts (kein Doppelversand).
func save() -> void:
	if _bus == null or state == STATE_SAVING or (state == STATE_DONE and not can_retry()):
		return
	if _bus.send_message(_trace.save_message(upload_check.button_pressed)) != OK:
		_fail("Nicht gesendet: Die Bridge ist nicht erreichbar. Bridge starten (vspin-bridge --source sim) und erneut speichern.")
		return
	state = STATE_SAVING
	reply = {}
	failure = ""
	_waited_s = 0.0
	refresh()


## „Verwerfen“: nichts geht nach außen. Spielstand und Session-CSV bleiben, wie sie sind.
func discard() -> void:
	if state == STATE_SAVING:
		return
	close()


## Kann die Fahrt noch einmal gespeichert werden? Nicht, wenn sie schon in Garmin Connect ist.
func can_retry() -> bool:
	if state != STATE_DONE:
		return false
	var upload = reply.get("upload")
	return not (upload is Dictionary and upload.get("state") in UPLOAD_DONE)


## Alle Texte des Dialogs, eine Zeile je sichtbarem Label (Tests, Sichtprüfung).
func page_text() -> String:
	var lines := []
	for label in _scroll.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			lines.append(label.text)
	return "\n".join(lines)


## Anmeldezustand als {text, howto, color}: Zeile, Anleitung (leer, wenn nichts zu tun ist) und Farbe.
static func login_info(login: String) -> Dictionary:
	match login:
		BusClient.GARMIN_LOGGED_IN:
			return {"text": "Garmin Connect: angemeldet", "howto": "", "color": COLOR_OK}
		BusClient.GARMIN_NOT_LOGGED_IN:
			return {"text": "Garmin Connect: nicht angemeldet – so geht's",
					"howto": "Im Terminal im Ordner bridge/ einmal anmelden:\n%s\n(E-Mail, Passwort und ggf. MFA-Code; "
							% LOGIN_COMMAND + "gespeichert wird nur das Token.) Die Anmeldung erkennt VSpin von selbst – "
							+ "danach hier speichern. Die FIT-Datei entsteht auch ohne Anmeldung.",
					"color": COLOR_WARN}
		BusClient.GARMIN_UNAVAILABLE:
			return {"text": "Garmin Connect: Upload nicht installiert",
					"howto": "Im Terminal im Ordner bridge/ installieren:\n%s\nDanach die Bridge neu starten und einmal "
							% INSTALL_COMMAND + "anmelden (%s). Die FIT-Datei entsteht auch ohne den Upload." % LOGIN_COMMAND,
					"color": COLOR_WARN}
	return {"text": "Garmin Connect: Anmeldung unbekannt",
			"howto": "Die Bridge meldet den Anmeldezustand nicht (ältere Version?). Die FIT-Datei entsteht trotzdem; "
					+ "ob der Upload klappt, zeigt sich beim Speichern.",
			"color": COLOR_DIM}


## Anzeige auffrischen (Anmeldezustand, Schalter, Ergebnis, Knöpfe); läuft jedes Bild, solange der Dialog offen ist.
func refresh() -> void:
	if _bus == null:
		return
	var login := login_info(_bus.garmin_login)
	(labels["login"] as Label).text = login["text"]
	(labels["login"] as Label).add_theme_color_override("font_color", login["color"])
	(labels["howto"] as Label).text = login["howto"]
	(labels["howto"] as Label).visible = not str(login["howto"]).is_empty()
	upload_check.disabled = state == STATE_SAVING or (state == STATE_DONE and not can_retry())
	(labels["status"] as Label).visible = state == STATE_SAVING
	_show_result()
	var save_button: Button = buttons["save"]
	save_button.visible = state != STATE_DONE or can_retry()
	save_button.disabled = state == STATE_SAVING
	save_button.text = "Speichert …" if state == STATE_SAVING else ("Erneut speichern" if state == STATE_DONE else "Speichern")
	(buttons["discard"] as Button).visible = state == STATE_ASK
	(buttons["done"] as Button).visible = state == STATE_DONE


func _process(delta: float) -> void:
	if not visible:
		return
	if state == STATE_SAVING:
		_waited_s += delta
		if not _bus.bus_connected:
			_fail("Die Verbindung zur Bridge ist abgebrochen, eine Antwort kam nicht. Ob die FIT-Datei entstanden ist, "
					+ "ist unklar – sie läge in sessions/rides/ im Ordner der Bridge. Erneut speichern ist möglich: "
					+ "Dieselbe Fahrt wird nie doppelt hochgeladen.")
		elif _waited_s >= reply_timeout_s:
			_fail("Die Bridge hat nach %d s nicht geantwortet (eine ältere Bridge kennt „Fahrt speichern“ nicht). "
					% roundi(reply_timeout_s) + "Ob die FIT-Datei entstanden ist, ist unklar – sie läge in "
					+ "sessions/rides/ im Ordner der Bridge. Erneut speichern ist möglich: Dieselbe Fahrt wird nie "
					+ "doppelt hochgeladen.")
	refresh()


func _on_toggled(on: bool) -> void:
	if _settings == null:
		return
	_settings.garmin_upload = on
	if not _settings_path.is_empty():
		_settings.save_file(_settings_path)


func _on_ride_saved(message: Dictionary) -> void:
	if state != STATE_SAVING or message.get("ride_id") != _trace.ride_id:
		return
	reply = message
	state = STATE_DONE
	refresh()
	focus_default()


func _on_ride_rejected(detail: String) -> void:
	if state == STATE_SAVING:
		_fail("Die Bridge hat die Fahrt abgelehnt: %s" % detail)


## Keine verwertbare Antwort: `message` anzeigen, „Erneut speichern“ und „Weiter“ anbieten.
func _fail(message: String) -> void:
	failure = message
	reply = {}
	state = STATE_DONE
	refresh()
	focus_default()


## Ergebnisblock: Datei und Upload aus `reply`, oder `failure`.
func _show_result() -> void:
	var done := state == STATE_DONE
	var head: Label = labels["result_head"]
	var file: Label = labels["result_file"]
	var import_hint: Label = labels["result_import"]
	var upload: Label = labels["result_upload"]
	for label in [head, file, import_hint, upload]:
		label.visible = false
	if not done:
		return
	if not failure.is_empty():
		head.text = "Nicht gespeichert"
		_color(head, COLOR_ERROR)
		file.text = failure
		_color(file, COLOR_ERROR)
		head.visible = true
		file.visible = true
		return
	var fit_path = reply.get("fit_path")
	var info = reply.get("upload")
	head.visible = true
	file.visible = true
	if fit_path is String and not fit_path.is_empty():
		head.text = "FIT-Datei gespeichert:"
		_color(head, COLOR_OK)
		file.text = fit_path
		_color(file, Color.WHITE)
		import_hint.text = IMPORT_HINT
		import_hint.visible = true
	else:
		head.text = "Keine FIT-Datei geschrieben"
		_color(head, COLOR_ERROR)
		var error = reply.get("fit_error")
		file.text = "%s Hochgeladen wurde nichts." % (error if error is String and not error.is_empty() \
				else "Die Bridge nennt keinen Grund.")
		_color(file, COLOR_ERROR)
	if info is Dictionary:
		upload.text = str(info.get("message", ""))
		var kind := str(info.get("state", ""))
		_color(upload, COLOR_OK if kind in UPLOAD_DONE else (COLOR_DIM if kind == "skipped" else COLOR_WARN))
		upload.visible = true


func _fit_margin() -> void:
	var side := maxf(24.0, (_margin.size.x + 48.0 - COLUMN_WIDTH) / 2.0)
	for name in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + name, int(side))


func _build() -> void:
	var theme := Theme.new()
	theme.default_font_size = 20
	var layout := Control.new()
	layout.name = "Layout"
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var backdrop := Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", _panel_style(0.72, 0))
	layout.add_child(backdrop)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 24)
	layout.add_child(_margin)
	layout.resized.connect(_fit_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_margin.add_child(column)
	var title := Label.new()
	title.text = "Fahrt speichern?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(0.85, 16))
	column.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	panel.add_child(_scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	labels["summary"] = _line(content, "")
	_heading(content, "Garmin Connect")
	labels["login"] = _line(content, "")
	labels["howto"] = _line(content, "", COLOR_WARN)
	upload_check = CheckBox.new()
	upload_check.name = "Upload"
	upload_check.text = "Nach Garmin Connect hochladen"
	upload_check.toggled.connect(_on_toggled)
	content.add_child(upload_check)
	labels["parallel"] = _line(content, "Zeichnet deine Uhr diese Fahrt parallel auf? Dann den Upload abschalten, "
			+ "sonst steht die Fahrt doppelt in Garmin Connect. Die FIT-Datei entsteht immer.", COLOR_DIM)
	labels["status"] = _line(content, "Speichert … Die Bridge schreibt die FIT-Datei und lädt hoch, das kann einige "
			+ "Sekunden dauern.", COLOR_HEADING)
	labels["result_head"] = _line(content, "")
	labels["result_head"].add_theme_font_size_override("font_size", 26)
	labels["result_file"] = _line(content, "")
	labels["result_import"] = _line(content, "", COLOR_DIM)
	labels["result_upload"] = _line(content, "")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	_button(row, "save", "Speichern", save)
	_button(row, "discard", "Verwerfen", discard)
	_button(row, "done", "Weiter", close)


func _button(parent: Container, key: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(190, 46)
	button.pressed.connect(action)
	parent.add_child(button)
	buttons[key] = button
	return button


func _heading(parent: Container, text: String) -> void:
	var label := _line(parent, text, COLOR_HEADING)
	label.add_theme_font_size_override("font_size", 26)


func _line(parent: Container, text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


static func _color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)


func _panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, alpha)
	style.set_corner_radius_all(12 if margin > 0 else 0)
	style.set_content_margin_all(margin)
	return style
