## Konfiguration der Inselfahrt: Bus-Adresse und Fahrmodell-Parameter (ADR-0006).
## Wird aus einer ConfigFile-Datei (INI) gelesen, Standard `res://config.cfg`.
class_name RideConfig
extends RefCounted

const DEFAULT_PATH := "res://config.cfg"

## Bus-Adresse (docs/bus-protocol.md).
var bus_url := "ws://127.0.0.1:8765"
## Sekunden zwischen Verbindungsversuchen zum Bus.
var bus_reconnect_s := 2.0
## Übersetzungsfaktor k: km/h je rpm auf flacher Strecke.
var k_kmh_per_rpm := 0.33
## Bergauf: v_ziel / (1 + uphill_damping * Steigung).
var uphill_damping := 8.0
## Bergab: v_ziel * (1 + downhill_boost * |Gefälle|).
var downhill_boost := 2.0
## Trägheit als Zeitkonstante in Sekunden (0 = keine Trägheit).
var inertia_s := 1.5


## Liest `path`; fehlende Datei oder fehlende Schlüssel ergeben die Standardwerte.
static func load_file(path: String = DEFAULT_PATH) -> RideConfig:
	var config := RideConfig.new()
	var file := ConfigFile.new()
	var err := file.load(path)
	if err != OK:
		push_warning("RideConfig: %s nicht lesbar (Fehler %d), nutze Standardwerte" % [path, err])
		return config
	config.bus_url = str(file.get_value("bus", "url", config.bus_url))
	config.bus_reconnect_s = float(file.get_value("bus", "reconnect_s", config.bus_reconnect_s))
	config.k_kmh_per_rpm = float(file.get_value("ride", "k_kmh_per_rpm", config.k_kmh_per_rpm))
	config.uphill_damping = float(file.get_value("ride", "uphill_damping", config.uphill_damping))
	config.downhill_boost = float(file.get_value("ride", "downhill_boost", config.downhill_boost))
	config.inertia_s = float(file.get_value("ride", "inertia_s", config.inertia_s))
	return config
