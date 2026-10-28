## Gemerktes Gerät einer Rolle im Verbindungsfenster (Spec #75): Trainer oder Lenkercontroller, je höchstens eins, mit
## Adresse und Name, der Controller dazu mit Seite (`left` | `right` | ""). Gespeichert im Abschnitt `[trainer]` bzw.
## `[controller]` von `user://settings.cfg` (ConfigFile) – derselben Datei wie die Pulsgeräte (`[heart_rate]`,
## HeartRateDevices) und die Grafik; die anderen Abschnitte bleiben beim Speichern unberührt. Eine Datei aus #64 ohne
## diese Abschnitte, ein fehlender oder kaputter Eintrag ergeben „kein Gerät“. Die Bridge speichert nichts: das Spiel
## schickt `bridge_list()` nach jedem (Neu-)Verbinden (BusClient.set_devices).
class_name RoleDevice
extends RefCounted

const SIDES := ["left", "right"]

## Rolle (`BusClient.KIND_TRAINER` | `BusClient.KIND_CONTROLLER`) = Abschnitt in der Datei.
var kind: String
var _device := {}


func _init(role: String = BusClient.KIND_TRAINER) -> void:
	kind = role


## Liest den Abschnitt der Rolle aus `path`; fehlende oder kaputte Datei und ungültige Einträge ergeben „kein Gerät“.
static func load_file(role: String, path: String = GraphicsSettings.DEFAULT_PATH) -> RoleDevice:
	var remembered := RoleDevice.new(role)
	if not FileAccess.file_exists(path):
		return remembered
	var file := ConfigFile.new()
	var err := file.load(path)
	if err != OK:
		push_warning("RoleDevice: %s nicht lesbar (Fehler %d), kein %s gemerkt" % [path, err, role])
		return remembered
	var address = file.get_value(role, "address", "")
	var device_name = file.get_value(role, "name", "")
	var side = file.get_value(role, "side", "")
	if address is String and not address.strip_edges().is_empty():
		remembered.remember(address, device_name if device_name is String else "", side if side is String else "")
	return remembered


## Schreibt den Abschnitt der Rolle nach `path`; alle anderen Abschnitte der Datei bleiben, wie sie sind.
func save_file(path: String = GraphicsSettings.DEFAULT_PATH) -> Error:
	var file := ConfigFile.new()
	if FileAccess.file_exists(path):
		file.load(path)  # kaputt = leer; der Rest ist dann ohnehin verloren
	write_to(file)
	var err := file.save(path)
	if err != OK:
		push_warning("RoleDevice: %s nicht schreibbar (Fehler %d)" % [path, err])
	return err


## Setzt den Abschnitt der Rolle in `file` (ersetzt ihn ganz; ohne Gerät entfällt er).
func write_to(file: ConfigFile) -> void:
	if file.has_section(kind):
		file.erase_section(kind)
	if _device.is_empty():
		return
	file.set_value(kind, "address", _device["address"])
	file.set_value(kind, "name", _device["name"])
	if kind == BusClient.KIND_CONTROLLER and not str(_device.get("side", "")).is_empty():
		file.set_value(kind, "side", _device["side"])


## Merkt `address`/`device_name` (Controller: mit `side`) und ersetzt ein früheres Gerät. Ohne Adresse passiert nichts;
## gibt zurück, ob gemerkt wurde.
func remember(address: String, device_name: String, side: String = "") -> bool:
	if address.strip_edges().is_empty():
		return false
	_device = {"address": address.strip_edges(), "name": device_name}
	if kind == BusClient.KIND_CONTROLLER:
		_device["side"] = side if side in SIDES else ""
	return true


func forget() -> void:
	_device = {}


func has_device() -> bool:
	return not _device.is_empty()


## Das gemerkte Gerät als {address, name} (Controller: dazu side); leer, wenn keins gemerkt ist.
func device() -> Dictionary:
	return _device.duplicate()


## Die Liste für `set_devices` der Rolle; leer = keins verbindet sich. Der Controller schickt seine Seite als `null`,
## wenn sie unbekannt ist.
func bridge_list() -> Array:
	if _device.is_empty():
		return []
	var entry := device()
	if kind == BusClient.KIND_CONTROLLER and str(entry["side"]).is_empty():
		entry["side"] = null
	return [entry]
