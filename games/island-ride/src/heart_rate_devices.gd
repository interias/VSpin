## Gemerkte Pulsgeräte (Spec #64, ADR-0008 „Puls als zweite Quelle“): höchstens ein Brustgurt und eine Uhr, je mit
## Adresse und Name. Gespeichert im Abschnitt `[heart_rate]` von `user://settings.cfg` (ConfigFile), derselben Datei wie
## die Grafikeinstellungen – die anderen Abschnitte bleiben beim Speichern unberührt. Ein fehlender oder kaputter
## Eintrag ergibt „kein Gerät“. Die Bridge speichert nichts: das Spiel schickt `bridge_list()` nach jedem (Neu-)Verbinden
## (BusClient.set_heart_rate_devices). Ein Gerät wird dort an der Adresse oder, wenn die nicht passt, am Namen erkannt;
## deshalb gehören beide gespeichert.
class_name HeartRateDevices
extends RefCounted

const SECTION := "heart_rate"
const ROLE_STRAP := "strap"
const ROLE_WATCH := "watch"
## Vorrang: Gurt vor Uhr.
const ROLES := [ROLE_STRAP, ROLE_WATCH]

## Je Rolle ein Eintrag {address, name}; fehlt die Rolle, gibt es kein Gerät.
var _devices := {}


## Liest den Abschnitt `[heart_rate]` aus `path`; fehlende oder kaputte Datei und ungültige Einträge ergeben „kein Gerät“.
static func load_file(path: String = GraphicsSettings.DEFAULT_PATH) -> HeartRateDevices:
	var devices := HeartRateDevices.new()
	var file := ConfigFile.new()
	if not FileAccess.file_exists(path):
		return devices
	var err := file.load(path)
	if err != OK:
		push_warning("HeartRateDevices: %s nicht lesbar (Fehler %d), kein Gerät gemerkt" % [path, err])
		return devices
	for role in ROLES:
		var address = file.get_value(SECTION, role + "_address", "")
		var device_name = file.get_value(SECTION, role + "_name", "")
		if address is String and not address.strip_edges().is_empty():
			devices._devices[role] = {"address": address.strip_edges(),
					"name": device_name if device_name is String else ""}
	return devices


## Schreibt den Abschnitt `[heart_rate]` nach `path`; alle anderen Abschnitte der Datei bleiben, wie sie sind.
func save_file(path: String = GraphicsSettings.DEFAULT_PATH) -> Error:
	var file := ConfigFile.new()
	if FileAccess.file_exists(path):
		file.load(path)  # kaputt = leer; der Rest ist dann ohnehin verloren
	write_to(file)
	var err := file.save(path)
	if err != OK:
		push_warning("HeartRateDevices: %s nicht schreibbar (Fehler %d)" % [path, err])
	return err


## Setzt den Abschnitt `[heart_rate]` in `file` (ersetzt ihn ganz; ohne Geräte entfällt er).
func write_to(file: ConfigFile) -> void:
	if file.has_section(SECTION):
		file.erase_section(SECTION)
	for role in ROLES:
		if _devices.has(role):
			file.set_value(SECTION, role + "_address", _devices[role]["address"])
			file.set_value(SECTION, role + "_name", _devices[role]["name"])


## Merkt `address`/`name` als Gerät der Rolle (`ROLE_STRAP` | `ROLE_WATCH`) und ersetzt ein früheres.
## Ohne Adresse oder mit unbekannter Rolle passiert nichts; gibt zurück, ob gemerkt wurde.
func remember(role: String, address: String, device_name: String) -> bool:
	if not role in ROLES or address.strip_edges().is_empty():
		return false
	_devices[role] = {"address": address.strip_edges(), "name": device_name}
	return true


## Vergisst das Gerät der Rolle.
func forget(role: String) -> void:
	_devices.erase(role)


func has_device(role: String) -> bool:
	return _devices.has(role)


## Das Gerät der Rolle als {address, name, role}; leer, wenn keines gemerkt ist.
func device(role: String) -> Dictionary:
	if not _devices.has(role):
		return {}
	return {"address": _devices[role]["address"], "name": _devices[role]["name"], "role": role}


## Die Liste für `set_heart_rate_devices` in Vorrang-Reihenfolge (Gurt vor Uhr); leer = Puls aus.
func bridge_list() -> Array:
	var list: Array = []
	for role in ROLES:
		if _devices.has(role):
			list.append(device(role))
	return list
