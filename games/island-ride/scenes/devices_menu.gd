## Geräteseite der Inselfahrt (Spec #64), aus dem Startmenü geöffnet: Brustgurt und Uhr einrichten und die Pulswerte des
## Fahrerprofils (LTHR, Maximalpuls) eintragen. Die Seite scrollt; von oben nach unten:
##   Karte Brustgurt / Karte Uhr   Anleitung, gemerktes Gerät, Live-Wert (Zustand und bpm aus dem BusClient), „Suchen“,
##                                 Liste der gefundenen Pulsgeräte (Name, Signalstärke, ohne Dubletten, laufend
##                                 aktualisiert) mit „Als … merken“, „Vergessen“, Hinweise, wenn nichts gefunden wird
##   Pulswerte                     zwei Eingabefelder (LTHR, Maximalpuls), Zonengrenzen Z1–Z5 in Zonenfarbe, Hinweis ohne Werte
## Die Seite ändert nur ihre Objekte (HeartRateDevices, SaveGame); gespeichert und an die Bridge geschickt wird in der
## Hauptszene über die Signale `devices_changed` und `profile_changed`. Es gibt eine Suche zur Zeit (Bus-Vertrag): sie
## gehört der Karte, auf der „Suchen“ gedrückt wurde. Verlässt der Fahrer die Seite, stoppt die Suche.
## Bedienung mit Maus, Tastatur und Controller: Fokus über Pfeiltasten/Tab bzw. Steuerkreuz, Enter/Leertaste, Esc oder
## B schließt. Layout nur über Anker und Container: passt im Halbbild-Fenster wie im Vollbild und in 1152×648.
extends CanvasLayer

## Geräteseite geschlossen („Zurück“ oder Esc).
signal closed
## Gemerkte Geräte geändert (merken oder vergessen): die Hauptszene speichert sie und schickt sie an die Bridge.
signal devices_changed
## LTHR/Maximalpuls im Spielstand geändert: die Hauptszene speichert den Spielstand.
signal profile_changed

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_DIM := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_OK := Color(0.45, 0.85, 0.5)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)
## Dauer einer Suche (s); die Bridge beendet sie danach mit `timeout`.
const SEARCH_DURATION_S := 30.0
const ROLE_NAMES := {HeartRateDevices.ROLE_STRAP: "Brustgurt", HeartRateDevices.ROLE_WATCH: "Uhr"}

## Anleitung je Rolle. Menüpfad der Uhr: Forerunner 970 Owner's Manual, „Broadcasting Heart Rate Data“ (Garmin,
## abgerufen 2026-10-10); die deutschen Menünamen sind sinngemäß übersetzt, die englischen stehen in Klammern.
const GUIDE := {
	HeartRateDevices.ROLE_STRAP: "1. Elektroden an der Innenseite des Gurts mit Wasser anfeuchten.\n"
			+ "2. Gurt eng anlegen – er wacht bei Hautkontakt auf.\n"
			+ "3. Unten „Suchen“ drücken und den Gurt in der Liste als Brustgurt merken.\n"
			+ "Empfehlung: Eine Uhr per ANT+ mit dem Gurt koppeln, nicht per Bluetooth – so bleibt eine "
			+ "Bluetooth-Verbindung des Gurts für VSpin frei (wie viele Bluetooth-Verbindungen der HRM 600 gleichzeitig hält, "
			+ "ist nicht verifiziert). Für Geräte anderer Hersteller empfiehlt Garmin beim HRM 600 die offene "
			+ "Verbindungsart.",
	HeartRateDevices.ROLE_WATCH: "1. Forerunner 970: Auf dem Zifferblatt die Taste Mitte links halten, dann "
			+ "Uhreinstellungen > Gesundheit & Wellness > Herzfrequenz am Handgelenk > Herzfrequenz übertragen "
			+ "(Watch Settings > Health & Wellness > Wrist Heart Rate > Broadcast Heart Rate). Oder: Taste oben links "
			+ "halten und im Steuerungsmenü „Herzfrequenz übertragen“ wählen.\n"
			+ "2. Taste oben rechts drücken: Die Uhr überträgt jetzt (zum Beenden erneut oben rechts).\n"
			+ "3. Unten „Suchen“ drücken und die Uhr in der Liste als Uhr merken. Das Übertragen kostet Akku.",
}
## Hinweise, wenn nichts gefunden wird (Story 6); je Rolle der erste Punkt.
const HINTS := {
	HeartRateDevices.ROLE_STRAP: "Gurt nicht angelegt oder Elektroden trocken: anfeuchten und eng anlegen.",
	HeartRateDevices.ROLE_WATCH: "Übertragung auf der Uhr nicht gestartet: „Herzfrequenz übertragen“ aktivieren.",
}
const HINTS_COMMON := "Das Gerät ist mit einer anderen App oder einem anderen Gerät verbunden: dort trennen. "
const HINT_BLUETOOTH := "Bluetooth am PC ist aus, oder die Bridge läuft ohne Bluetooth."
const LTHR_HELP := "Forerunner 970: Taste Mitte links halten > Uhreinstellungen > Benutzerprofil > Herzfrequenz- und " \
		+ "Leistungszonen > Herzfrequenz > LTHR bzw. Max. Herzfrequenz (Watch Settings > User Profile > Heart Rate & " \
		+ "Power Zones > Heart Rate). Garmin Connect: Anzeige dieser Werte nicht verifiziert (laut Handbuch lassen sich " \
		+ "die Zonen dort anpassen)."
const NO_ZONES_HINT := "Ohne LTHR und Maximalpuls zeigt VSpin den Puls ohne Zonen (nur bpm). Trag einen der Werte ein, " \
		+ "dann erscheinen Zonen und Zonenfarben."

## Knöpfe: back, search_<rolle>, forget_<rolle>, save_profile.
var buttons := {}
## Texte zum Prüfen und Lesen: live_<rolle>, device_<rolle>, search_<rolle> (Status der Suche), hint_<rolle>, bus_note,
## profile_message, zone_source, zones (Zonenzeilen), no_zones.
var labels := {}
var lthr_edit: LineEdit
var max_hr_edit: LineEdit
## Karten, in denen die Suche läuft: Rolle der Karte oder "".
var search_role := ""
## Gefundene Geräte der laufenden Suche: Adresse → {name, rssi}.
var found := {}

var _bus: BusClient
var _devices: HeartRateDevices
var _save: SaveGame
var _scroll: ScrollContainer
var _results := {}  # Rolle → VBoxContainer mit den Ergebniszeilen
var _rows := {}  # Adresse → {label, button, role}
var _zone_box: VBoxContainer
var _searching := false
## Grund des Suchendes (timeout, taken_over); "" = läuft oder nicht gestartet.
var search_ended := ""
var _search_role_ended := ""


func _ready() -> void:
	layer = 6  # über dem Startmenü (5), unter den Einstellungen (10)
	visible = false
	_build()


## Seite öffnen mit Bus-Client, gemerkten Geräten und Spielstand; Fokus auf „Zurück“.
func open(bus: BusClient, devices: HeartRateDevices, save: SaveGame) -> void:
	_bus = bus
	_devices = devices
	_save = save
	if not _bus.heart_rate_found.is_connected(_on_found):
		_bus.heart_rate_found.connect(_on_found)
		_bus.heart_rate_search_ended.connect(_on_search_ended)
	_reset_search()
	lthr_edit.text = str(save.lthr_bpm()) if save.lthr_bpm() > 0 else ""
	max_hr_edit.text = str(save.max_hr_bpm()) if save.max_hr_bpm() > 0 else ""
	labels["profile_message"].text = ""
	_show_zones()
	visible = true
	_scroll.scroll_vertical = 0
	refresh()
	focus_default()


## Schließen: eine laufende Suche stoppt, der Fokus geht mit.
func close() -> void:
	if not visible:
		return
	if _searching and _bus != null:
		_bus.stop_heart_rate_search()
	_reset_search()
	visible = false
	if _bus != null and _bus.heart_rate_found.is_connected(_on_found):
		_bus.heart_rate_found.disconnect(_on_found)
		_bus.heart_rate_search_ended.disconnect(_on_search_ended)
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()
	closed.emit()


func focus_default() -> void:
	if visible:
		(buttons["back"] as Button).grab_focus()


## Suche auf der Karte der Rolle starten (ersetzt eine laufende Suche); ohne Bus passiert nichts.
func start_search(role: String) -> void:
	if _bus == null or not _bus.bus_connected:
		return
	_clear_results()
	_searching = true
	search_role = role
	search_ended = ""
	_search_role_ended = ""
	_bus.start_heart_rate_search(SEARCH_DURATION_S)
	refresh()


## Gefundenes Gerät `address` als Gerät der Rolle merken.
func remember(role: String, address: String) -> void:
	if not found.has(address):
		return
	if _devices.remember(role, address, found[address]["name"]):
		devices_changed.emit()
		refresh()


## Gemerktes Gerät der Rolle vergessen.
func forget(role: String) -> void:
	if not _devices.has_device(role):
		return
	_devices.forget(role)
	devices_changed.emit()
	refresh()


## LTHR und Maximalpuls aus den Feldern übernehmen. Leer = nicht gesetzt; unplausible oder keine ganzen Zahlen werden
## abgewiesen (Meldung, nichts gespeichert). Gibt zurück, ob gespeichert wurde.
func save_profile() -> bool:
	var lthr := _parse_value(lthr_edit.text, HeartRateZones.LTHR_MIN, HeartRateZones.LTHR_MAX)
	var max_hr := _parse_value(max_hr_edit.text, HeartRateZones.MAX_HR_MIN, HeartRateZones.MAX_HR_MAX)
	var message: Label = labels["profile_message"]
	if lthr < 0 or max_hr < 0:
		var parts := []
		if lthr < 0:
			parts.append("LTHR %d–%d bpm" % [HeartRateZones.LTHR_MIN, HeartRateZones.LTHR_MAX])
		if max_hr < 0:
			parts.append("Maximalpuls %d–%d bpm" % [HeartRateZones.MAX_HR_MIN, HeartRateZones.MAX_HR_MAX])
		message.text = "Nicht gespeichert – erlaubt sind ganze Zahlen: " + ", ".join(parts) + "."
		message.add_theme_color_override("font_color", COLOR_ERROR)
		return false
	_save.set_heart_rate_profile(lthr, max_hr)
	message.text = "Gespeichert."
	message.add_theme_color_override("font_color", COLOR_OK)
	profile_changed.emit()
	_show_zones()
	return true


## Anzeige auffrischen (Zustand, Live-Wert, Gerät, Hinweise, Knöpfe); läuft jedes Bild, solange die Seite offen ist.
func refresh() -> void:
	if _bus == null:
		return
	var connected := _bus.bus_connected
	(labels["bus_note"] as Label).visible = not connected
	for role in HeartRateDevices.ROLES:
		var remembered := _devices.device(role)
		labels["device_" + role].text = "Gemerkt: %s" % _device_name(remembered) if not remembered.is_empty() \
				else "Kein Gerät gemerkt."
		(buttons["forget_" + role] as Button).disabled = remembered.is_empty()
		(buttons["search_" + role] as Button).disabled = not connected
		var live := live_text(role)
		(labels["live_" + role] as Label).text = live[0]
		(labels["live_" + role] as Label).add_theme_color_override("font_color", live[1])
		(labels["search_" + role] as Label).text = _search_text(role)
		var hint := hint_for(role)
		(labels["hint_" + role] as Label).text = hint
		(labels["hint_" + role] as Label).visible = not hint.is_empty()
	for address in _rows:
		var row = _rows[address]
		row["button"].text = "Als %s merken" % ROLE_NAMES[row["role"]]


## Live-Zeile der Karte als [Text, Farbe]: Zustand und bpm, wenn das verbundene Gerät diese Rolle hat.
func live_text(role: String) -> Array:
	if _bus == null or not _bus.bus_connected:
		return ["Bridge nicht erreichbar", COLOR_ERROR]
	var device: Dictionary = _bus.heart_rate_device
	var on_this_card: bool = device.get("role") == role
	match _bus.heart_rate_state:
		BusClient.HEART_RATE_CONNECTED:
			if on_this_card:
				if _bus.has_heart_rate():
					var bpm := roundi(_bus.heart_rate_bpm)
					var zone := _save.heart_rate_zones().zone_for(bpm)
					return ["Verbunden · %d bpm%s" % [bpm, " (Z%d)" % zone if zone > 0 else ""],
							HeartRateZones.color_for(zone) if zone > 0 else COLOR_OK]
				return ["Verbunden · -- bpm", COLOR_OK]
		BusClient.HEART_RATE_STALE:
			if on_this_card:
				return ["Verbunden · keine Daten", COLOR_WARN]
	if _devices.has_device(role):
		return ["wartet auf das Gerät …", COLOR_WARN]
	return ["nicht verbunden", COLOR_DIM]


## Hinweise (Story 6) der Karte: nach einer Suche ohne Treffer auf dieser Karte, oder wenn ein gemerktes Gerät
## nicht verbunden werden kann (`disconnected`). Sonst "".
func hint_for(role: String) -> String:
	if _bus == null or not _bus.bus_connected:
		return ""
	var no_hit := _search_role_ended == role and found.is_empty() and search_ended != ""
	var lost := _devices.has_device(role) and _bus.heart_rate_state == BusClient.HEART_RATE_DISCONNECTED
	if not (no_hit or lost):
		return ""
	var lead := "Kein Pulsgerät gefunden." if no_hit and search_ended == "timeout" else "Gerät nicht verbunden."
	if no_hit and search_ended == "taken_over":
		lead = "Die Suche wurde von einem anderen Programm übernommen."
	return "%s Prüfen:\n• %s\n• %s\n• %s" % [lead, HINTS[role], HINTS_COMMON.strip_edges(), HINT_BLUETOOTH]


## Alle Texte der Seite, eine Zeile je Label (Tests, Sichtprüfung).
func page_text() -> String:
	var lines := []
	for label in _scroll.find_children("*", "Label", true, false):
		lines.append(label.text)
	return "\n".join(lines)


## „Name · Signal −58 dBm (gut)“ für die Ergebniszeile; ohne Namen „Unbenanntes Gerät“.
static func found_text(device_name: String, rssi: int) -> String:
	return "%s · Signal %d dBm (%s)" % [device_name if not device_name.strip_edges().is_empty() else "Unbenanntes Gerät",
			rssi, signal_quality(rssi)]


## Grobe Stufe der Signalstärke in dBm: stark ab −60, gut ab −70, mittel ab −80, sonst schwach.
static func signal_quality(rssi: int) -> String:
	if rssi >= -60:
		return "stark"
	if rssi >= -70:
		return "gut"
	if rssi >= -80:
		return "mittel"
	return "schwach"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var is_cancel: bool = (event is InputEventKey and event.pressed and not event.echo
			and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if not is_cancel:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return  # Einstellungen (F2) liegen darüber und bedienen sich selbst
	close()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		refresh()


func _on_found(address: String, device_name: String, rssi: int) -> void:
	if not _searching or address.is_empty():
		return
	var known: bool = found.has(address)
	found[address] = {"name": device_name, "rssi": rssi}
	if not known:
		_add_row(address)
	else:
		_rows[address]["label"].text = found_text(device_name, rssi)
	search_ended = ""
	refresh()


func _on_search_ended(reason: String) -> void:
	if not _searching:
		return
	_searching = false
	search_ended = reason
	_search_role_ended = search_role
	refresh()


func _reset_search() -> void:
	_searching = false
	search_role = ""
	search_ended = ""
	_search_role_ended = ""
	_clear_results()


func _clear_results() -> void:
	found.clear()
	_rows.clear()
	for role in _results:
		for child in (_results[role] as Node).get_children():
			(_results[role] as Node).remove_child(child)
			child.queue_free()


func _add_row(address: String) -> void:
	var box: VBoxContainer = _results[search_role]
	var row := HBoxContainer.new()
	row.name = "Result" + address.replace(":", "")
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var label := Label.new()
	label.text = found_text(found[address]["name"], found[address]["rssi"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var button := Button.new()
	button.text = "Als %s merken" % ROLE_NAMES[search_role]
	button.custom_minimum_size = Vector2(190, 40)
	button.pressed.connect(remember.bind(search_role, address))
	row.add_child(button)
	_rows[address] = {"label": label, "button": button, "role": search_role}


## Status der Suche auf der Karte: läuft / Ende / leer.
func _search_text(role: String) -> String:
	if search_role != role and _search_role_ended != role:
		return ""
	if _searching:
		return "Suche läuft … %d Gerät%s gefunden" % [found.size(), "" if found.size() == 1 else "e"]
	match search_ended:
		"timeout":
			return "Suche beendet · %d Gerät%s gefunden" % [found.size(), "" if found.size() == 1 else "e"]
		"taken_over":
			return "Suche beendet (von einem anderen Programm übernommen)"
	return ""


## Ganze Zahl in [low, high]; leer = 0 (nicht gesetzt); alles andere −1.
static func _parse_value(text: String, low: int, high: int) -> int:
	var value := text.strip_edges()
	if value.is_empty():
		return 0
	if not value.is_valid_int():
		return -1
	var number := value.to_int()
	return number if number >= low and number <= high else -1


func _device_name(device: Dictionary) -> String:
	var device_name := str(device.get("name", "")).strip_edges()
	return device_name if not device_name.is_empty() else str(device.get("address", ""))


## Zonenzeilen aus dem Spielstand: Z1–Z5 in Zonenfarbe mit bpm-Bereich, oder der Hinweis ohne Werte.
func _show_zones() -> void:
	for child in _zone_box.get_children():
		_zone_box.remove_child(child)
		child.queue_free()
	var zones := _save.heart_rate_zones()
	labels["no_zones"].visible = not zones.has_zones()
	labels["zone_source"].text = "" if not zones.has_zones() else \
			("Zonen nach LTHR (Friel)" if zones.source() == HeartRateZones.Source.LTHR else "Zonen nach Maximalpuls")
	labels["zone_source"].visible = zones.has_zones()
	if not zones.has_zones():
		return
	for zone in range(1, HeartRateZones.ZONE_COUNT + 1):
		var span := zones.zone_range(zone)
		var text := "Z%d  %d–%d bpm" % [zone, span.x, span.y] if span.y != HeartRateZones.OPEN \
				else "Z%d  ab %d bpm" % [zone, span.x]
		var label := _line(_zone_box, text, HeartRateZones.color_for(zone))
		label.name = "Zone%d" % zone


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
	title.text = "Geräte"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(top)
	_button(top, "back", "Zurück", close)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(0.78, 16))
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
	labels["bus_note"] = _line(content, "Bridge nicht erreichbar – ohne sie kann VSpin keine Pulsgeräte suchen. "
			+ "Bridge starten: vspin-bridge --source sim", COLOR_ERROR)
	for role in HeartRateDevices.ROLES:
		_build_card(content, role)
	_build_profile(content)


func _build_card(content: VBoxContainer, role: String) -> void:
	var card := VBoxContainer.new()
	card.name = "Card" + role.capitalize()
	card.add_theme_constant_override("separation", 6)
	content.add_child(card)
	_heading(card, ROLE_NAMES[role])
	_line(card, GUIDE[role])
	labels["device_" + role] = _line(card, "")
	labels["live_" + role] = _line(card, "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	_button(row, "search_" + role, "Suchen", start_search.bind(role))
	_button(row, "forget_" + role, "Vergessen", forget.bind(role))
	labels["search_" + role] = _line(card, "", COLOR_DIM)
	var results := VBoxContainer.new()
	results.name = "Results"
	results.add_theme_constant_override("separation", 4)
	card.add_child(results)
	_results[role] = results
	labels["hint_" + role] = _line(card, "", COLOR_WARN)
	card.add_child(HSeparator.new())


func _build_profile(content: VBoxContainer) -> void:
	_heading(content, "Pulswerte")
	_line(content, "Mit diesen Werten berechnet VSpin die Pulszonen. Leer lassen = nicht gesetzt.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	content.add_child(grid)
	lthr_edit = _field(grid, "lthr", "LTHR (bpm, %d–%d)" % [HeartRateZones.LTHR_MIN, HeartRateZones.LTHR_MAX])
	max_hr_edit = _field(grid, "max_hr", "Maximalpuls (bpm, %d–%d)" % [HeartRateZones.MAX_HR_MIN,
			HeartRateZones.MAX_HR_MAX])
	_button(content, "save_profile", "Speichern", save_profile)
	labels["profile_message"] = _line(content, "")
	_line(content, LTHR_HELP, COLOR_DIM)
	labels["zone_source"] = _line(content, "", COLOR_DIM)
	_zone_box = VBoxContainer.new()
	_zone_box.name = "Zones"
	content.add_child(_zone_box)
	labels["no_zones"] = _line(content, NO_ZONES_HINT, COLOR_WARN)


func _field(grid: GridContainer, key: String, caption: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	grid.add_child(label)
	var edit := LineEdit.new()
	edit.name = key
	edit.custom_minimum_size = Vector2(120, 40)
	edit.max_length = 4
	edit.placeholder_text = "—"
	edit.text_submitted.connect(func(_text): save_profile())
	grid.add_child(edit)
	return edit


func _button(parent: Container, key: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = text
	button.custom_minimum_size = Vector2(150, 46)
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


func _panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, alpha)
	style.set_corner_radius_all(12 if margin > 0 else 0)
	style.set_content_margin_all(margin)
	return style
