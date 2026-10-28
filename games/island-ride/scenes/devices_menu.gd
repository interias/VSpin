## Verbindungsfenster der Inselfahrt (Spec #75, aus der Geräteseite von #64): eine Kachel je Rolle – Trainer, Puls,
## Controller. Es öffnet aus dem Startmenü („Verbindungen“), während der Fahrt über den Knopf im HUD oder die Taste V,
## und beim Start von selbst, wenn die Bridge mit `source="ble"` läuft und noch kein Trainer gemerkt ist.
##   Kacheln (oben, nebeneinander)  je Rolle Zustand, Gerätename, Live-Wert (Trainer: Watt und Kadenz, Puls: bpm,
##                                 Controller: Akku, sonst „—“) und Signalstärke; die Überschrift springt zur Einrichtung
##                                 der Rolle. Trainer zusätzlich der Stand der Steuerung, „Nur lesen“ und bei `lost` bzw.
##                                 `error` der Knopf „Steuerung zurückholen“ (fordert nur auf diesen Klick neu an);
##                                 Controller „gesperrt – einmal in Zwift verbinden (gilt ca. 24 h)“ statt eines Fehlers.
## Darunter scrollt die Einrichtung; von oben nach unten:
##   Karte Trainer                 Anleitung, gemerktes Gerät, „Suchen“, gefundene Trainer mit „Als Trainer merken“,
##                                 „Vergessen“, Hinweise, wenn nichts gefunden wird (mit dem Simulator nicht suchbar)
##   Karte Brustgurt / Karte Uhr   Anleitung, gemerktes Gerät, Live-Wert (Zustand und bpm aus dem BusClient), „Suchen“,
##                                 Liste der gefundenen Pulsgeräte (Name, Signalstärke, ohne Dubletten, laufend
##                                 aktualisiert) mit „Als … merken“, „Vergessen“, Hinweise, wenn nichts gefunden wird
##   Pulswerte                     zwei Eingabefelder (LTHR, Maximalpuls), Zonengrenzen Z1–Z5 in Zonenfarbe, Hinweis ohne Werte
##   Karte Controller              wie der Trainer, gefundene Controller mit Seite (links bevorzugt)
## Das Fenster ändert nur seine Objekte (HeartRateDevices, RoleDevice, SaveGame); gespeichert und an die Bridge geschickt
## wird in der Hauptszene über die Signale `devices_changed`, `role_device_changed` und `profile_changed`. Je Rolle gibt es
## eine Suche zur Zeit (Bus-Vertrag); die Pulssuche gehört der Karte, auf der „Suchen“ gedrückt wurde. Schließt der
## Fahrer das Fenster, stoppen die Suchen.
## Bedienung mit Maus, Tastatur und Controller: Fokus über Pfeiltasten/Tab bzw. Steuerkreuz, Enter/Leertaste, Esc oder
## B schließt. Layout nur über Anker und Container: passt im Halbbild-Fenster wie im Vollbild und in 1152×648.
extends CanvasLayer

## Geräteseite geschlossen („Zurück“ oder Esc).
signal closed
## Gemerkte Geräte geändert (merken oder vergessen): die Hauptszene speichert sie und schickt sie an die Bridge.
signal devices_changed
## Gemerkter Trainer bzw. Controller geändert (`kind` = BusClient.KIND_*): die Hauptszene speichert und schickt ihn.
signal role_device_changed(kind: String)
## LTHR/Maximalpuls im Spielstand geändert: die Hauptszene speichert den Spielstand.
signal profile_changed

const COLOR_HEADING := Color(1.0, 0.86, 0.45)
const COLOR_DIM := Color(1.0, 1.0, 1.0, 0.55)
const COLOR_OK := Color(0.45, 0.85, 0.5)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)
## Dauer einer Suche (s); die Bridge beendet sie danach mit `timeout`.
const SEARCH_DURATION_S := 30.0
## Grund für `search_ended`, wenn der Bus während der Suche wegfällt (die Bridge meldet dann kein Ende).
const SEARCH_BUS_LOST := "bus_lost"
const ROLE_NAMES := {HeartRateDevices.ROLE_STRAP: "Brustgurt", HeartRateDevices.ROLE_WATCH: "Uhr"}
## Kacheln: Rollen in Anzeigereihenfolge und ihre Namen; Trainer und Controller haben je eine eigene Karte.
const KINDS := [BusClient.KIND_TRAINER, BusClient.KIND_HEART_RATE, BusClient.KIND_CONTROLLER]
const KIND_NAMES := {BusClient.KIND_TRAINER: "Trainer", BusClient.KIND_HEART_RATE: "Puls",
		BusClient.KIND_CONTROLLER: "Controller"}
const SIDE_NAMES := {"left": "links", "right": "rechts"}
const TILE_FONT_SIZE := 18
## Kein Wert (Controller ohne Akku, keine Signalstärke).
const NO_VALUE := "—"
const CONTROLLER_LOCKED_TEXT := "gesperrt – einmal in Zwift verbinden (gilt ca. 24 h)"
const RECLAIM_TEXT := "Steuerung zurückholen"
## Stand der Steuerung (`status.trainer.control`) in der Trainerkachel als [Text, Farbe-Schlüssel].
const CONTROL_TEXTS := {
	BusClient.TRAINER_CONTROL_ACTIVE: ["VSpin steuert den Widerstand", "ok"],
	BusClient.TRAINER_CONTROL_REQUESTING: ["fordere die Steuerung an …", "warn"],
	BusClient.TRAINER_CONTROL_LOST: ["Eine andere App steuert den Trainer", "warn"],
	BusClient.TRAINER_CONTROL_ERROR: ["Steuerung gescheitert – der Trainer wird nur gelesen", "warn"],
	BusClient.TRAINER_CONTROL_READ_ONLY: ["Nur lesen (config.cfg [bridge] trainer_read_only)", "dim"],
	BusClient.TRAINER_CONTROL_NOT_SUPPORTED: ["Trainer ohne Widerstandssteuerung", "dim"],
}
const ROLE_GUIDE := {
	BusClient.KIND_TRAINER: "1. Trainer einschalten (am Strom) und in Zwift, der Hersteller-App o. Ä. trennen – es "
			+ "steuert immer nur eine App.\n2. Unten „Suchen“ drücken und den Trainer in der Liste merken. Ab dann verbindet "
			+ "VSpin ihn beim Start von selbst.",
	BusClient.KIND_CONTROLLER: "Der linke Controller reicht – er gibt die Tasten des rechten weiter. VSpin zeigt nur "
			+ "Verbindung und Akku; die Lenkertasten nutzt es noch nicht.\nNeuere Firmware sperrt den Controller, bis er "
			+ "einmal in Zwift verbunden war (gilt dann etwa 24 h): dann steht er hier als „gesperrt“.",
}
const ROLE_HINTS := {
	BusClient.KIND_TRAINER: "Trainer aus oder ohne Strom: einschalten, kurz in die Pedale treten.",
	BusClient.KIND_CONTROLLER: "Controller schläft: eine Taste drücken, damit er sendet.",
}
const SIM_NOTE := "Die Bridge läuft mit dem Simulator (config.cfg [bridge] source=\"sim\") – ein Trainer wird erst mit " \
		+ "source=\"ble\" verbunden."

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
## Suche je Rolle (Trainer, Controller): gefundene Geräte Adresse → {name, rssi, side}, Grund des Endes ("" = läuft oder
## nicht gestartet) und ob sie läuft.
var role_found := {BusClient.KIND_TRAINER: {}, BusClient.KIND_CONTROLLER: {}}
var role_search_ended := {BusClient.KIND_TRAINER: "", BusClient.KIND_CONTROLLER: ""}
var _role_searching := {BusClient.KIND_TRAINER: false, BusClient.KIND_CONTROLLER: false}
var _role_rows := {BusClient.KIND_TRAINER: {}, BusClient.KIND_CONTROLLER: {}}
## Antwort auf „Steuerung zurückholen“ ("" = keine oder ok).
var reclaim_message := ""

var _bus: BusClient
var _devices: HeartRateDevices
var _save: SaveGame
var _role_devices := {}  # Rolle → RoleDevice (Trainer, Controller)
var _scroll: ScrollContainer
var _cards := {}  # Rolle bzw. Pulsrolle → Karte in der Einrichtung
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


## Fenster öffnen mit Bus-Client, gemerkten Geräten und Spielstand; Fokus auf „Zurück“. Ohne gemerkten Trainer bzw.
## Controller (`null`) gelten leere, die nur im Fenster leben.
func open(bus: BusClient, devices: HeartRateDevices, save: SaveGame, trainer: RoleDevice = null,
		controller: RoleDevice = null) -> void:
	_bus = bus
	_devices = devices
	_save = save
	_role_devices[BusClient.KIND_TRAINER] = trainer if trainer != null else RoleDevice.new(BusClient.KIND_TRAINER)
	_role_devices[BusClient.KIND_CONTROLLER] = controller if controller != null \
			else RoleDevice.new(BusClient.KIND_CONTROLLER)
	if not _bus.heart_rate_found.is_connected(_on_found):
		_bus.heart_rate_found.connect(_on_found)
		_bus.heart_rate_search_ended.connect(_on_search_ended)
		_bus.device_found.connect(_on_role_found)
		_bus.device_search_ended.connect(_on_role_search_ended)
		_bus.ack_received.connect(_on_ack)
	_reset_search()
	for kind in _role_searching:
		_reset_role_search(kind)
	reclaim_message = ""
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
	for kind in _role_searching:
		if _role_searching[kind] and _bus != null:
			_bus.stop_device_search(kind)
		_reset_role_search(kind)
	_reset_search()
	visible = false
	if _bus != null and _bus.heart_rate_found.is_connected(_on_found):
		_bus.heart_rate_found.disconnect(_on_found)
		_bus.heart_rate_search_ended.disconnect(_on_search_ended)
		_bus.device_found.disconnect(_on_role_found)
		_bus.device_search_ended.disconnect(_on_role_search_ended)
		_bus.ack_received.disconnect(_on_ack)
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


## Suche auf der Karte von Trainer bzw. Controller starten (ersetzt deren laufende Suche); ohne Bus passiert nichts,
## ein Trainer nur, wenn die Bridge mit einem Trainer läuft (`source` ble).
func start_role_search(kind: String) -> void:
	if _bus == null or not _bus.bus_connected or (kind == BusClient.KIND_TRAINER and _bus.source != "ble"):
		return
	_reset_role_search(kind)
	_role_searching[kind] = true
	_bus.start_device_search(kind, SEARCH_DURATION_S)
	refresh()


## Gefundenen Trainer bzw. Controller `address` merken (ersetzt den gemerkten).
func remember_role(kind: String, address: String) -> void:
	var hit: Dictionary = role_found[kind].get(address, {})
	if hit.is_empty():
		return
	if (_role_devices[kind] as RoleDevice).remember(address, hit["name"], hit.get("side", "")):
		role_device_changed.emit(kind)
		refresh()


## Gemerkten Trainer bzw. Controller vergessen: er verbindet sich nicht mehr von selbst.
func forget_role(kind: String) -> void:
	var remembered: RoleDevice = _role_devices[kind]
	if not remembered.has_device():
		return
	remembered.forget()
	role_device_changed.emit(kind)
	refresh()


## „Steuerung zurückholen“: nur dieser Klick fordert die Steuerung neu an (die Bridge schreibt bei `lost` nichts).
func reclaim_control() -> void:
	if _bus == null or not _bus.bus_connected:
		return
	reclaim_message = ""
	_bus.reclaim_trainer_control()
	refresh()


## Ist der Knopf „Steuerung zurückholen“ zu sehen? Bei `lost` und `error`.
func reclaim_visible() -> bool:
	return _bus != null and _bus.bus_connected and _bus.trainer_control in [BusClient.TRAINER_CONTROL_LOST,
			BusClient.TRAINER_CONTROL_ERROR]


## Zur Einrichtung der Rolle springen (Überschrift einer Kachel): Karte sichtbar, Fokus auf „Suchen“.
func show_card(kind: String) -> void:
	var card: Control = _cards.get(kind, _cards.get(HeartRateDevices.ROLE_STRAP))
	_scroll.ensure_control_visible(card)
	var search_key := "search_" + (kind if kind != BusClient.KIND_HEART_RATE else HeartRateDevices.ROLE_STRAP)
	(buttons[search_key] as Button).grab_focus()


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
	for kind in _role_searching:
		var remembered: RoleDevice = _role_devices[kind]
		labels["device_" + kind].text = "Gemerkt: %s" % _role_device_text(remembered.device()) \
				if remembered.has_device() else "Kein %s gemerkt." % KIND_NAMES[kind]
		(buttons["forget_" + kind] as Button).disabled = not remembered.has_device()
		(buttons["search_" + kind] as Button).disabled = not connected \
				or (kind == BusClient.KIND_TRAINER and _bus.source != "ble")
		(labels["search_" + kind] as Label).text = _role_search_text(kind)
		var hint := role_hint_for(kind)
		(labels["hint_" + kind] as Label).text = hint
		(labels["hint_" + kind] as Label).visible = not hint.is_empty()
	(labels["sim_note"] as Label).visible = connected and _bus.source != "ble"
	_refresh_tiles()


## Kachel der Rolle als Textzeilen [Zustand, Gerät, Live-Wert, Signal] mit Farbe des Zustands (Tests, Anzeige).
func tile_lines(kind: String) -> Array:
	if _bus == null or not _bus.bus_connected:
		return [["Bridge nicht erreichbar", COLOR_ERROR], "", "", ""]
	match kind:
		BusClient.KIND_TRAINER:
			return _trainer_tile()
		BusClient.KIND_HEART_RATE:
			return _heart_rate_tile()
	return _controller_tile()


## Stand der Steuerung in der Trainerkachel als [Text, Farbe]; "" ohne Trainer oder ohne Bus.
func control_line() -> Array:
	if _bus == null or not _bus.bus_connected or _bus.source != "ble" or not CONTROL_TEXTS.has(_bus.trainer_control):
		return ["", COLOR_DIM]
	var entry: Array = CONTROL_TEXTS[_bus.trainer_control]
	return [entry[0], {"ok": COLOR_OK, "warn": COLOR_WARN, "dim": COLOR_DIM}[entry[1]]]


## Alle sichtbaren Texte der Kacheln (Überschriften, Zeilen, Knopf), eine Zeile je Element (Tests, Sichtprüfung).
func tiles_text() -> String:
	var lines := []
	for item in get_node("Layout").find_child("Tiles", true, false).find_children("*", "", true, false):
		if (item is Label or item is Button) and item.is_visible_in_tree():
			lines.append(item.text)
	return "\n".join(lines)


## Hinweise der Karte von Trainer bzw. Controller: nach einer Suche ohne Treffer, oder wenn das gemerkte Gerät nicht
## verbunden werden kann. Sonst "".
func role_hint_for(kind: String) -> String:
	if _bus == null or not _bus.bus_connected:
		return ""
	var no_hit: bool = role_found[kind].is_empty() and role_search_ended[kind] != ""
	var remembered: RoleDevice = _role_devices[kind]
	var waiting := remembered.has_device() and (_bus.controller_state == BusClient.CONTROLLER_DISCONNECTED
			if kind == BusClient.KIND_CONTROLLER
			else _bus.source == "ble" and _bus.status == BusClient.STATE_DISCONNECTED)
	if not (no_hit or waiting):
		return ""
	var lead := "Kein %s gefunden." % KIND_NAMES[kind] if no_hit and role_search_ended[kind] == "timeout" \
			else "%s nicht verbunden." % KIND_NAMES[kind]
	if no_hit and role_search_ended[kind] == "taken_over":
		lead = "Die Suche wurde von einem anderen Programm übernommen."
	return "%s Prüfen:\n• %s\n• %s\n• %s" % [lead, ROLE_HINTS[kind], HINTS_COMMON.strip_edges(), HINT_BLUETOOTH]


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


## Alle Texte der Einrichtung, eine Zeile je Label (Tests, Sichtprüfung).
func page_text() -> String:
	var lines := []
	for label in _scroll.find_children("*", "Label", true, false):
		lines.append(label.text)
	return "\n".join(lines)


## Signalstärke für die Kachel: „Signal −58 dBm (gut)“, ohne Wert „Signal —“.
static func signal_text(has_value: bool, rssi: int) -> String:
	return "Signal %d dBm (%s)" % [rssi, signal_quality(rssi)] if has_value else "Signal " + NO_VALUE


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
	if not visible:
		return
	# Bus weg während der Suche: die Bridge meldet kein Ende mehr, die Suche gilt als abgebrochen (Nacharbeit #64).
	if _searching and (_bus == null or not _bus.bus_connected):
		_on_search_ended(SEARCH_BUS_LOST)
	for kind in _role_searching:
		if _role_searching[kind] and (_bus == null or not _bus.bus_connected):
			_on_role_search_ended(kind, SEARCH_BUS_LOST)
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


func _on_role_found(kind: String, address: String, device_name: String, rssi: int, side: String) -> void:
	if not _role_searching.get(kind, false) or address.is_empty():
		return
	var hits: Dictionary = role_found[kind]
	var known := hits.has(address)
	hits[address] = {"name": device_name, "rssi": rssi, "side": side}
	if not known:
		_add_role_row(kind, address)
	else:
		_role_rows[kind][address].text = _role_found_text(kind, hits[address])
	refresh()


func _on_role_search_ended(kind: String, reason: String) -> void:
	if not _role_searching.get(kind, false):
		return
	_role_searching[kind] = false
	role_search_ended[kind] = reason
	refresh()


func _on_ack(message: Dictionary) -> void:
	if message.get("for") != "reclaim_trainer_control":
		return
	match message.get("reason"):
		null:
			reclaim_message = ""
		"control_lost":
			reclaim_message = "Der Trainer lehnt ab: eine andere App steuert ihn noch. Dort trennen und erneut versuchen."
		"read_only":
			reclaim_message = "Nur-lesen-Modus: VSpin steuert den Trainer nicht."
		_:
			reclaim_message = "Steuerung nicht zurückgeholt (%s)." % message.get("reason")
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
	for role in HeartRateDevices.ROLES:  # nur die Pulskarten: Trainer und Controller suchen für sich
		_clear_box(_results[role])


func _clear_box(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _reset_role_search(kind: String) -> void:
	_role_searching[kind] = false
	role_search_ended[kind] = ""
	(role_found[kind] as Dictionary).clear()
	(_role_rows[kind] as Dictionary).clear()
	if _results.has(kind):
		_clear_box(_results[kind])


func _add_role_row(kind: String, address: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Result" + address.replace(":", "")
	row.add_theme_constant_override("separation", 12)
	(_results[kind] as Node).add_child(row)
	var label := Label.new()
	label.text = _role_found_text(kind, role_found[kind][address])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var button := Button.new()
	button.text = "Als %s merken" % KIND_NAMES[kind]
	button.custom_minimum_size = Vector2(190, 40)
	button.pressed.connect(remember_role.bind(kind, address))
	row.add_child(button)
	_role_rows[kind][address] = label


## Ergebniszeile: wie beim Puls, beim Controller mit der Seite („Zwift SF2 (links) · Signal …“).
func _role_found_text(kind: String, hit: Dictionary) -> String:
	var device_name := str(hit["name"])
	if kind == BusClient.KIND_CONTROLLER and SIDE_NAMES.has(hit.get("side", "")):
		device_name = "%s (%s)" % [device_name if not device_name.strip_edges().is_empty() else "Controller",
				SIDE_NAMES[hit["side"]]]
	return found_text(device_name, int(hit["rssi"]))


func _role_search_text(kind: String) -> String:
	var count: int = (role_found[kind] as Dictionary).size()
	if _role_searching[kind]:
		return "Suche läuft … %d Gerät%s gefunden" % [count, "" if count == 1 else "e"]
	match role_search_ended[kind]:
		"timeout":
			return "Suche beendet · %d Gerät%s gefunden" % [count, "" if count == 1 else "e"]
		"taken_over":
			return "Suche beendet (von einem anderen Programm übernommen)"
		SEARCH_BUS_LOST:
			return "Suche abgebrochen (Verbindung zur Bridge verloren)"
	return ""


func _role_device_text(device: Dictionary) -> String:
	var text := _device_name(device)
	return "%s (%s)" % [text, SIDE_NAMES[device["side"]]] if SIDE_NAMES.has(device.get("side", "")) else text


func _trainer_tile() -> Array:
	var remembered: RoleDevice = _role_devices[BusClient.KIND_TRAINER]
	var signal_line := signal_text(_bus.has_rssi(BusClient.KIND_TRAINER), _bus.rssi_for(BusClient.KIND_TRAINER))
	match _bus.source:
		"sim":
			return [["Simulator – kein Trainer nötig", COLOR_OK], "config.cfg [bridge] source=\"sim\"",
					"Kadenz %d rpm" % roundi(_bus.cadence), ""]
		"replay":
			return [["Replay – kein Trainer nötig", COLOR_OK], "", "Kadenz %d rpm" % roundi(_bus.cadence), ""]
	var device_name := _device_name(_bus.trainer_device) if not _bus.trainer_device.is_empty() \
			else (_device_name(remembered.device()) if remembered.has_device() else "")
	match _bus.status:
		BusClient.STATE_CONNECTED:
			var watts := _bus.power_w()
			return [["Verbunden", COLOR_OK], device_name, "%s · %d rpm" % [
					"-- W" if is_nan(watts) else "%d W" % roundi(watts), roundi(_bus.cadence)], signal_line]
		BusClient.STATE_STALE:
			return [["Verbunden · keine Daten", COLOR_WARN], device_name, "-- W · -- rpm", signal_line]
	if remembered.has_device():
		return [["sucht den Trainer …", COLOR_WARN], device_name, "", signal_line]
	return [["Kein Trainer gemerkt – unten suchen", COLOR_WARN], "", "", signal_line]


func _heart_rate_tile() -> Array:
	var signal_line := signal_text(_bus.has_rssi(BusClient.KIND_HEART_RATE),
			_bus.rssi_for(BusClient.KIND_HEART_RATE))
	var device: Dictionary = _bus.heart_rate_device
	var device_name := "" if device.is_empty() else "%s (%s)" % [_device_name(device),
			ROLE_NAMES.get(device.get("role"), "")]
	var bpm := "%d bpm" % roundi(_bus.heart_rate_bpm) if _bus.has_heart_rate() else "-- bpm"
	match _bus.heart_rate_state:
		BusClient.HEART_RATE_CONNECTED:
			return [["Verbunden", COLOR_OK], device_name, bpm, signal_line]
		BusClient.HEART_RATE_STALE:
			return [["Verbunden · keine Daten", COLOR_WARN], device_name, "-- bpm", signal_line]
		BusClient.HEART_RATE_DISCONNECTED:
			return [["wartet auf das Gerät …", COLOR_WARN], "", "", signal_line]
	if _bus.has_heart_rate():
		return [["Kein Gerät gemerkt", COLOR_DIM], "", "%s (%s)" % [bpm, "Simulator" if _bus.source == "sim"
				else "vom Rad"], signal_line]
	return [["Kein Gerät gemerkt – unten suchen", COLOR_DIM], "", "", signal_line]


func _controller_tile() -> Array:
	var remembered: RoleDevice = _role_devices[BusClient.KIND_CONTROLLER]
	var signal_line := signal_text(_bus.has_rssi(BusClient.KIND_CONTROLLER),
			_bus.rssi_for(BusClient.KIND_CONTROLLER))
	var device_name := _role_device_text(_bus.controller_device) if not _bus.controller_device.is_empty() \
			else (_role_device_text(remembered.device()) if remembered.has_device() else "")
	var battery := "Akku %d %%" % _bus.controller_battery if _bus.controller_battery >= 0 else "Akku " + NO_VALUE
	match _bus.controller_state:
		BusClient.CONTROLLER_CONNECTED:
			return [["Verbunden", COLOR_OK], device_name, battery, signal_line]
		BusClient.CONTROLLER_LOCKED:
			return [[CONTROLLER_LOCKED_TEXT, COLOR_WARN], device_name, battery, signal_line]
		BusClient.CONTROLLER_DISCONNECTED:
			return [["wartet auf den Controller …", COLOR_WARN], device_name, "Akku " + NO_VALUE, signal_line]
	return [["Kein Controller gemerkt – unten suchen", COLOR_DIM], "", "Akku " + NO_VALUE, signal_line]


func _refresh_tiles() -> void:
	for kind in KINDS:
		var lines := tile_lines(kind)
		var state: Label = labels["tile_state_" + kind]
		state.text = lines[0][0]
		state.add_theme_color_override("font_color", lines[0][1])
		for i in range(1, 4):
			var label: Label = labels[["", "tile_device_", "tile_live_", "tile_signal_"][i] + kind]
			label.text = lines[i]
			label.visible = not str(lines[i]).is_empty()
	var control := control_line()
	var control_label: Label = labels["tile_control"]
	control_label.text = control[0]
	control_label.add_theme_color_override("font_color", control[1])
	control_label.visible = not str(control[0]).is_empty()
	(buttons["reclaim"] as Button).visible = reclaim_visible()
	var message: Label = labels["reclaim_message"]
	message.text = reclaim_message
	message.visible = not reclaim_message.is_empty() and reclaim_visible()


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
		SEARCH_BUS_LOST:
			return "Suche abgebrochen (Verbindung zur Bridge verloren)"
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
	title.text = "Verbindungen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(top)
	_button(top, "back", "Zurück", close)
	_build_tiles(column)
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
	labels["bus_note"] = _line(content, "Bridge nicht erreichbar – ohne sie kann VSpin keine Geräte suchen. "
			+ "Bridge starten: vspin-bridge --source sim", COLOR_ERROR)
	_build_role_card(content, BusClient.KIND_TRAINER)
	for role in HeartRateDevices.ROLES:
		_build_card(content, role)
	_build_profile(content)
	content.add_child(HSeparator.new())
	_build_role_card(content, BusClient.KIND_CONTROLLER)


## Kacheln nebeneinander, gleich breit; die Überschrift ist ein flacher Knopf zur Einrichtung der Rolle.
func _build_tiles(column: VBoxContainer) -> void:
	var tiles := HBoxContainer.new()
	tiles.name = "Tiles"
	tiles.add_theme_constant_override("separation", 12)
	column.add_child(tiles)
	for kind in KINDS:
		var tile := PanelContainer.new()
		tile.name = "Tile" + kind.to_pascal_case()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_stretch_ratio = 1.0
		tile.add_theme_stylebox_override("panel", _panel_style(0.82, 10))
		tiles.add_child(tile)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		tile.add_child(box)
		var heading := _button(box, "tile_" + kind, KIND_NAMES[kind], show_card.bind(kind))
		heading.flat = true
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.custom_minimum_size = Vector2(0, 34)
		heading.add_theme_font_size_override("font_size", 22)
		heading.add_theme_color_override("font_color", COLOR_HEADING)
		for key in ["tile_state_", "tile_device_", "tile_live_", "tile_signal_"]:
			labels[key + kind] = _small_line(box, "")
		if kind == BusClient.KIND_TRAINER:
			labels["tile_control"] = _small_line(box, "")
			var reclaim := _button(box, "reclaim", RECLAIM_TEXT, reclaim_control)
			reclaim.custom_minimum_size = Vector2(0, 36)
			reclaim.visible = false
			labels["reclaim_message"] = _small_line(box, "", COLOR_WARN)


## Karte von Trainer bzw. Controller in der Einrichtung: Anleitung, gemerktes Gerät, Suchen/Vergessen, Ergebnisse,
## Hinweise.
func _build_role_card(content: VBoxContainer, kind: String) -> void:
	var card := VBoxContainer.new()
	card.name = "Card" + kind.to_pascal_case()
	card.add_theme_constant_override("separation", 6)
	content.add_child(card)
	_cards[kind] = card
	_heading(card, KIND_NAMES[kind])
	_line(card, ROLE_GUIDE[kind])
	if kind == BusClient.KIND_TRAINER:
		labels["sim_note"] = _line(card, SIM_NOTE, COLOR_DIM)
	labels["device_" + kind] = _line(card, "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	_button(row, "search_" + kind, "Suchen", start_role_search.bind(kind))
	_button(row, "forget_" + kind, "Vergessen", forget_role.bind(kind))
	labels["search_" + kind] = _line(card, "", COLOR_DIM)
	var results := VBoxContainer.new()
	results.name = "Results"
	results.add_theme_constant_override("separation", 4)
	card.add_child(results)
	_results[kind] = results
	labels["hint_" + kind] = _line(card, "", COLOR_WARN)
	if kind == BusClient.KIND_TRAINER:
		card.add_child(HSeparator.new())


func _build_card(content: VBoxContainer, role: String) -> void:
	var card := VBoxContainer.new()
	card.name = "Card" + role.capitalize()
	card.add_theme_constant_override("separation", 6)
	content.add_child(card)
	_cards[role] = card
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


## Zeile einer Kachel: kleiner als die Einrichtung, damit drei Kacheln in 1152×648 über der Einrichtung Platz haben.
func _small_line(parent: Container, text: String, color: Color = Color.WHITE) -> Label:
	var label := _line(parent, text, color)
	label.add_theme_font_size_override("font_size", TILE_FONT_SIZE)
	return label


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
