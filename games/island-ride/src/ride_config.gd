## Konfiguration der Inselfahrt: Bus-Adresse, Fahrmodell-Parameter und Strecke (ADR-0006).
## Wird aus einer ConfigFile-Datei (INI) gelesen, Standard `res://config.cfg`.
class_name RideConfig
extends RefCounted

const DEFAULT_PATH := "res://config.cfg"
const TRACK_ISLAND := "island"
const TRACK_GRAYBOX := "graybox"

## Bus-Adresse (docs/bus-protocol.md).
var bus_url := "ws://127.0.0.1:8765"
## Sekunden zwischen Verbindungsversuchen zum Bus.
var bus_reconnect_s := 2.0
## Sekunden, nach denen ein hängender Verbindungsaufbau abgebrochen und neu versucht wird.
var bus_connect_timeout_s := 5.0
## Übersetzungsfaktor k: km/h je rpm auf flacher Strecke.
var k_kmh_per_rpm := 0.33
## Bergauf: v_ziel / (1 + uphill_damping * Steigung).
var uphill_damping := 8.0
## Bergab: v_ziel * (1 + downhill_boost * |Gefälle|).
var downhill_boost := 2.0
## Trägheit als Zeitkonstante in Sekunden (0 = keine Trägheit).
var inertia_s := 1.5
## Strecke: TRACK_ISLAND (Insel-Rundkurs, Standard) oder TRACK_GRAYBOX (kurze Teststrecke).
var track := TRACK_ISLAND
## Tag/Nacht und Wetter (G6, SkyController): Zeitmodus (DayNight.MODE_*), feste Ortszeit (h), Zeitraffer (Minuten je
## Tag), Wettermodus (Weather.MODE_*) und (Anfangs-)Wetter (Weather.CLEAR …). Ungültige Werte prüfen die Module.
var sky_time_mode := "realtime"
var sky_fixed_hour := 13.0
var sky_timelapse_day_min := 24.0
var sky_weather_mode := "changing"
var sky_weather := "clear"


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
	config.bus_connect_timeout_s = float(file.get_value("bus", "connect_timeout_s", config.bus_connect_timeout_s))
	config.k_kmh_per_rpm = float(file.get_value("ride", "k_kmh_per_rpm", config.k_kmh_per_rpm))
	config.uphill_damping = float(file.get_value("ride", "uphill_damping", config.uphill_damping))
	config.downhill_boost = float(file.get_value("ride", "downhill_boost", config.downhill_boost))
	config.inertia_s = float(file.get_value("ride", "inertia_s", config.inertia_s))
	config.track = str(file.get_value("world", "track", config.track))
	if config.track not in [TRACK_ISLAND, TRACK_GRAYBOX]:
		push_warning("RideConfig: unbekannte Strecke '%s', nutze '%s'" % [config.track, TRACK_ISLAND])
		config.track = TRACK_ISLAND
	config.sky_time_mode = str(file.get_value("sky", "time_mode", config.sky_time_mode))
	config.sky_fixed_hour = _sky_number(file, "fixed_hour", config.sky_fixed_hour)
	config.sky_timelapse_day_min = _sky_number(file, "timelapse_day_min", config.sky_timelapse_day_min)
	config.sky_weather_mode = str(file.get_value("sky", "weather_mode", config.sky_weather_mode))
	config.sky_weather = str(file.get_value("sky", "weather", config.sky_weather))
	return config


## Zahl aus `[sky] key`; leer, Text oder (bei Zeitraffer) ≤ 0 → `fallback` (sonst wäre "" Mitternacht bzw. 0 min).
static func _sky_number(file: ConfigFile, key: String, fallback: float) -> float:
	var value = file.get_value("sky", key, fallback)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or (key == "timelapse_day_min" and value <= 0.0):
		push_warning("RideConfig: [sky] %s = '%s' ungültig, nutze %s" % [key, value, fallback])
		return fallback
	return float(value)
