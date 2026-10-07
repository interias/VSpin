## Spielstand der Inselfahrt (#30, ADR-0008 Nachtrag): lokal in `user://savegame.json` (JSON), **versioniert** und
## mit **Profilschlüssel** ab dem ersten Speichern. Gehört dem Spiel, nicht der Bridge: nur Zusammenfassungen der
## Fahrt (Datum, Dauer, Strecke, Runden, Durchschnitte), keine Rohtelemetrie – Kadenzverläufe stehen in der
## Session-CSV der Bridge.
##
##   {"version": 1, "active_profile": "<16 Hex-Zeichen>",
##    "profiles": {"<schlüssel>": {"created": "…Z", "rides": [{"date": "…Z", "mode": "rundfahrt", …}],
##                                 "best_times": {"<strecke>": {"<richtung>": <sekunden>}}}}}
##
## Bestzeiten (#31): schnellste Runde je Strecke und Richtung (LapTiming.DIRECTION_*), in Sekunden.
##
## Erweitern (Ghosts, Medaillen, Erfolge, Fahrerlevel, Garderobe – spätere Pakete) geht additiv:
## neue Bereiche in PROFILE_DEFAULTS bekommen beim Laden ihren Standardwert. Ändert sich das Format, steigt
## VERSION und `_upgrade_steps()` bekommt einen Schritt von der alten Version aus – alte Stände werden beim Laden
## hochgestuft, nie verworfen. Ein Stand aus einer neueren Version bleibt unverändert erhalten (unbekannte
## Bereiche werden mitgeschrieben). Eine unlesbare Datei wird nicht überschrieben, sondern beiseitegelegt.
class_name SaveGame
extends RefCounted

const DEFAULT_PATH := "user://savegame.json"
## Aktuelle Formatversion.
const VERSION := 1
## Spielmodus einer Fahrt (CONTEXT.md: Rundfahrt; Training und Arcade folgen).
const MODE_ROUND_TRIP := "rundfahrt"
## Bereiche je Fahrerprofil mit Standardwert (fehlende werden beim Laden ergänzt).
const PROFILE_DEFAULTS := {"rides": [], "best_times": {}}
## Endung, unter der eine unlesbare Datei beiseitegelegt wird.
const BROKEN_SUFFIX := ".defekt"

## Der ganze Stand (wie in der Datei).
var data := {}


func _init() -> void:
	data = complete({})


## Lädt den Stand aus `path`; fehlt die Datei, ein neuer Stand (mit neuem Profilschlüssel). Ist die Datei unlesbar,
## wird sie nach `<path>.defekt` verschoben (nicht überschrieben) und ein neuer Stand begonnen.
static func load_file(path: String = DEFAULT_PATH) -> SaveGame:
	var save := SaveGame.new()
	if not FileAccess.file_exists(path):
		return save
	var json := JSON.new()
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (parsed is Dictionary) or not (parsed.get("version") is float) or parsed["version"] < 1.0:
		push_warning("SaveGame: %s unlesbar, beiseitegelegt als %s" % [path, path + BROKEN_SUFFIX])
		DirAccess.rename_absolute(path, path + BROKEN_SUFFIX)
		return save
	save.data = complete(upgrade(parsed))
	return save


## Schreibt den Stand nach `path` (JSON, eingerückt).
func save_file(path: String = DEFAULT_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: %s nicht schreibbar (Fehler %d)" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK


## Formatversion des Stands.
func version() -> int:
	return int(data["version"])


## Schlüssel des aktiven Fahrerprofils (es gibt vorerst genau eins).
func profile_key() -> String:
	return data["active_profile"]


## Bereiche des aktiven Fahrerprofils.
func profile() -> Dictionary:
	return data["profiles"][profile_key()]


## Fahrten des aktiven Profils, älteste zuerst.
func rides() -> Array:
	return profile()["rides"]


func add_ride(entry: Dictionary) -> void:
	rides().append(entry)


## Bestzeit auf `track` in Richtung `direction` in Sekunden (INF = noch keine).
func best_time_s(track: String, direction: String) -> float:
	var tracks: Dictionary = profile()["best_times"]
	var value = tracks.get(track, {}).get(direction) if tracks.get(track) is Dictionary else null
	return float(value) if (value is float or value is int) and value > 0.0 else INF


## Trägt `seconds` als Bestzeit ein, wenn sie schneller ist als die bisherige. Gibt zurück, ob sie eingetragen wurde.
func record_best_time(track: String, direction: String, seconds: float) -> bool:
	if not is_finite(seconds) or seconds <= 0.0 or seconds >= best_time_s(track, direction):
		return false
	var tracks: Dictionary = profile()["best_times"]
	if not (tracks.get(track) is Dictionary):
		tracks[track] = {}
	tracks[track][direction] = snappedf(seconds, 0.001)
	return true


## Zusammenfassung einer beendeten Fahrt – keine Rohtelemetrie. `finished`: Ziel erreicht (sonst abgebrochen oder
## endlos). `laps`: abgeschlossene Runden, `lap_times_s` ihre Zeiten.
static func ride_entry(mode: String, track: String, finished: bool, laps: int, stats: RideStats,
		date: String = utc_now(), lap_times_s: Array = []) -> Dictionary:
	return {
		"date": date,
		"mode": mode,
		"track": track,
		"finished": finished,
		"laps": laps,
		"duration_s": snappedf(stats.ride_time_s, 0.1),
		"distance_km": snappedf(stats.distance_m / 1000.0, 0.001),
		"avg_cadence_rpm": snappedf(stats.avg_cadence(), 0.1),
		"avg_speed_kmh": snappedf(stats.avg_speed_kmh(), 0.01),
		"lap_times_s": lap_times_s.map(func(t): return snappedf(t, 0.01)),
	}


## Jetzt als UTC-Zeitstempel („2026-10-07T12:34:56Z“).
static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## Stuft einen Stand Schritt für Schritt auf `target` hoch: `steps[v]` macht aus Version v Version v + 1. Ein Stand
## aus einer neueren Version bleibt, wie er ist.
static func upgrade(old: Dictionary, steps: Dictionary = _upgrade_steps(), target: int = VERSION) -> Dictionary:
	var result := old.duplicate(true)
	var from := int(result["version"])
	while from < target:
		if not steps.has(from):
			push_warning("SaveGame: keine Hochstufung von Version %d" % from)
			break
		result = steps[from].call(result)
		from += 1
		result["version"] = from
	return result


## Hochstufungen je Ausgangsversion (Version → Callable(Dictionary) -> Dictionary). Version 1 ist die erste.
static func _upgrade_steps() -> Dictionary:
	return {}


## Ergänzt fehlende Teile mit Standardwerten: Version, Profilschlüssel (neu erzeugt), Profil und seine Bereiche.
## Vorhandenes (auch Unbekanntes) bleibt unverändert.
static func complete(partial: Dictionary) -> Dictionary:
	var result := partial
	if not result.has("version"):
		result["version"] = VERSION
	if not (result.get("profiles") is Dictionary):
		result["profiles"] = {}
	if not (result.get("active_profile") is String) or (result["active_profile"] as String).is_empty():
		result["active_profile"] = new_profile_key()
	var profiles: Dictionary = result["profiles"]
	if not (profiles.get(result["active_profile"]) is Dictionary):
		profiles[result["active_profile"]] = {"created": utc_now()}
	var current: Dictionary = profiles[result["active_profile"]]
	for key in PROFILE_DEFAULTS:
		if typeof(current.get(key)) != typeof(PROFILE_DEFAULTS[key]):
			current[key] = PROFILE_DEFAULTS[key].duplicate(true)
	return result


## Neuer, zufälliger Profilschlüssel (16 Hex-Zeichen).
static func new_profile_key() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()
