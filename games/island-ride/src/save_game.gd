## Spielstand der Inselfahrt (#30, ADR-0008 Nachtrag): lokal in `user://savegame.json` (JSON), **versioniert** und
## mit **Profilschlüssel** ab dem ersten Speichern. Gehört dem Spiel, nicht der Bridge: nur Zusammenfassungen der
## Fahrt (Datum, Dauer, Strecke, Runden, Durchschnitte), keine Rohtelemetrie – Kadenzverläufe stehen in der
## Session-CSV der Bridge.
##
##   {"version": 1, "active_profile": "<16 Hex-Zeichen>",
##    "profiles": {"<schlüssel>": {"created": "…Z", "rides": [{"date": "…Z", "mode": "rundfahrt", …}],
##                                 "best_times": {"<strecke>": {"<richtung>": <sekunden>}},
##                                 "segment_best_times": {"<strecke>": {"<richtung>": {"<segment>": <sekunden>}}},
##                                 "medals": {"<strecke>": {"<richtung>": {"lap"|"<segment>": "gold"|…}}},
##                                 "ghosts": {"<strecke>": {"<richtung>": {"best"|"last": {Ghost.to_dict()}}}},
##                                 "achievements": {"<erfolg>": "…Z"},
##                                 "wardrobe": {"trikot"|"radfarbe"|"helm": "<teil-id>"},
##                                 "camera": {"view": "nah"|"verfolger"|"weit"},
##                                 "arcade": {"cadence_range": {"min": 60, "max": 120}, "tier": 1,
##                                            "best_points": {"<stufe>": <punkte>}, "unlocked": 3,
##                                            "defeated": {"<stufe>": ["<boss-id>", …]}}}}}
##
## Bestzeiten (#31): schnellste Runde je Strecke und Richtung (LapTiming.DIRECTION_*), in Sekunden.
## Segment-Bestzeiten (#33): schnellste Zeit je Strecke, Richtung und Segment-ID, in Sekunden.
## Medaillen (#33): beste Medaille (Medals.GOLD/SILVER/BRONZE) je Strecke, Richtung und Runde (Medals.LAP) bzw. Segment.
## Ghosts (#32): je Strecke und Richtung die Bestzeit-Runde (Ghost.BEST) und die letzte volle Runde der zuletzt
## gespeicherten Fahrt mit mindestens einer vollen Runde (Ghost.LAST) – nur Strecke über Zeit, keine Rohtelemetrie.
## Erfolge (#35): freigeschaltete Erfolge (Achievements.LIST) mit Datum (UTC). Das Fahrerlevel wird nicht gespeichert:
## es folgt aus den Gesamt-Kilometern, und die ergeben sich wie Fahrzeit und Runden gesamt aus den Fahrten
## (`total_km`, `total_time_s`, `total_laps`). Ein älterer Stand ohne `achievements` bekommt den leeren Bereich; was er
## schon erfüllt, fällt beim nächsten Fahrtende.
## Garderobe (#36): das gewählte Teil je Kategorie (Wardrobe.CATEGORIES); prüfen und wählen macht Wardrobe. Fehlt eine
## Kategorie, gilt ihr Standard (der Look vor der Garderobe). Nur Kosmetik (ADR-0010).
## Kamera (#59): die gewählte Kameraperspektive (CameraViews.IDS); prüfen und wählen macht CameraViews. Fehlt sie, gilt
## „Verfolger“. Nur Darstellung (ADR-0010).
##
## Training (#37): eine Fahrt im Modus MODE_TRAINING trägt zusätzlich den Namen der Einheit (`training`) und die
## Gesamtbewertung (`training_score`, Treffer der Zielkadenz 0..1); `finished` heißt dort: Einheit zu Ende gefahren.
## Bestzeit, Segmentzeiten, Medaillen und Ghosts schreibt das Training nicht.
##
## Arcade (#46): eine Fahrt im Modus MODE_ARCADE trägt zusätzlich `arcade` (ArcadeRun.to_entry: Stufe, Punkte,
## geschafft, verfehlt); ihre km zählen wie jede Fahrt für Fahrtenbuch, Fahrerlevel und Erfolge. Bestzeit,
## Segmentzeiten, Medaillen und Ghosts schreibt Arcade nie (ADR-0010). Der Bereich `arcade` hält den persönlichen
## Kadenzbereich (CadenceRange prüft), die zuletzt gewählte Stufe (ArcadeTiers prüft) und die beste Punktzahl je Stufe;
## spätere Pakete (Beute #49, Talente #53, Stufen #54) ergänzen ihn. Stufen (#54): `unlocked` ist die höchste wählbare Stufe
## (fehlt → die drei Startstufen), `defeated` je Stufe die dort besiegten Bosse (ArcadeTiers prüft und schreibt beides).
## Ein Stand ohne ihn bekommt beim Laden den leeren Bereich (es gelten die Standards) – additiv, die Formatversion bleibt 1.
##
## Erweitern (spätere Pakete) geht additiv:
## neue Bereiche in PROFILE_DEFAULTS bekommen beim Laden ihren Standardwert. Ändert sich das Format, steigt
## VERSION und `_upgrade_steps()` bekommt einen Schritt von der alten Version aus – alte Stände werden beim Laden
## hochgestuft, nie verworfen. Ein Stand aus einer neueren Version bleibt unverändert erhalten (unbekannte
## Bereiche werden mitgeschrieben). Eine unlesbare Datei wird nicht überschrieben, sondern beiseitegelegt.
class_name SaveGame
extends RefCounted

const DEFAULT_PATH := "user://savegame.json"
## Aktuelle Formatversion.
const VERSION := 1
## Spielmodus einer Fahrt (CONTEXT.md: Rundfahrt, Training, Arcade).
const MODE_ROUND_TRIP := "rundfahrt"
const MODE_TRAINING := "training"
const MODE_ARCADE := "arcade"
## Bereiche je Fahrerprofil mit Standardwert (fehlende werden beim Laden ergänzt).
const PROFILE_DEFAULTS := {"rides": [], "best_times": {}, "segment_best_times": {}, "medals": {}, "ghosts": {},
		"achievements": {}, "wardrobe": {}, "camera": {}, "arcade": {}}
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


## Segment-Bestzeit von `segment_id` auf `track` in Richtung `direction` in Sekunden (INF = noch keine).
func segment_best_s(track: String, direction: String, segment_id: String) -> float:
	return segment_best_times(track, direction).get(segment_id, INF)


## Alle gültigen Segment-Bestzeiten auf `track` in Richtung `direction`: Segment-ID → Sekunden.
func segment_best_times(track: String, direction: String) -> Dictionary:
	var result := {}
	var times := _area("segment_best_times", track, direction)
	for id in times:
		if (times[id] is float or times[id] is int) and times[id] > 0.0:
			result[id] = float(times[id])
	return result


## Trägt `seconds` als Segment-Bestzeit ein, wenn sie schneller ist als die bisherige. Gibt zurück, ob sie eingetragen
## wurde. Schreibt nicht auf die Platte (das macht `save_file`).
func record_segment_time(track: String, direction: String, segment_id: String, seconds: float) -> bool:
	if not is_finite(seconds) or seconds <= 0.0 or seconds >= segment_best_s(track, direction, segment_id):
		return false
	_area("segment_best_times", track, direction, true)[segment_id] = snappedf(seconds, 0.001)
	return true


## Beste Medaille für `key` (Medals.LAP oder Segment-ID) auf `track` in Richtung `direction` (Medals.NONE = keine).
func best_medal(track: String, direction: String, key: String) -> String:
	var medal = _area("medals", track, direction).get(key)
	return medal if medal is String and Medals.rank(medal) > 0 else Medals.NONE


## Trägt `medal` für `key` ein, wenn sie besser ist als die bisherige. Gibt zurück, ob sie eingetragen wurde.
func record_medal(track: String, direction: String, key: String, medal: String) -> bool:
	if Medals.rank(medal) <= Medals.rank(best_medal(track, direction, key)):
		return false
	_area("medals", track, direction, true)[key] = medal
	return true


## Gespeicherter Ghost `kind` (Ghost.BEST/LAST) auf `track` in Richtung `direction` (null = keiner oder ungültig).
func ghost(track: String, direction: String, kind: String) -> Ghost:
	return Ghost.from_dict(_area("ghosts", track, direction).get(kind))


## Speichert `recording` als Ghost `kind`; ersetzt den bisherigen. Schreibt nicht auf die Platte.
func record_ghost(track: String, direction: String, kind: String, recording: Ghost) -> void:
	_area("ghosts", track, direction, true)[kind] = recording.to_dict()


## Freigeschaltete Erfolge: ID → Datum (UTC); ungültige Einträge fehlen.
func achievements() -> Dictionary:
	var result := {}
	var unlocked: Dictionary = profile()["achievements"]
	for id in unlocked:
		if unlocked[id] is String:
			result[id] = unlocked[id]
	return result


## Schaltet den Erfolg `id` mit `date` frei, wenn er es noch nicht ist. Gibt zurück, ob er neu ist. Schreibt nicht auf
## die Platte.
func unlock_achievement(id: String, date: String = utc_now()) -> bool:
	if achievements().has(id):
		return false
	profile()["achievements"][id] = date
	return true


## Garderobe: Kategorie → gewählte Teil-ID, wie gespeichert (ungeprüft; Wardrobe.selection prüft). Schreibbar.
func wardrobe() -> Dictionary:
	return profile()["wardrobe"]


## Kamera: {"view": <perspektive>}, wie gespeichert (ungeprüft; CameraViews.selection prüft). Schreibbar.
func camera() -> Dictionary:
	return profile()["camera"]


## Arcade (#46): Kadenzbereich, Stufe, Bestpunktzahlen …, wie gespeichert (ungeprüft; CadenceRange und ArcadeTiers
## prüfen). Schreibbar.
func arcade() -> Dictionary:
	return profile()["arcade"]


## Beste Punktzahl eines Arcade-Laufs auf Stufe `tier` (0 = noch keine).
func best_arcade_points(tier: int) -> int:
	var best = arcade().get("best_points", {}).get(str(tier)) if arcade().get("best_points") is Dictionary else null
	return int(best) if (best is float or best is int) and best > 0 else 0


## Trägt `points` als beste Punktzahl der Stufe `tier` ein, wenn sie höher ist. Gibt zurück, ob sie eingetragen wurde.
## Schreibt nicht auf die Platte.
func record_arcade_points(tier: int, points: int) -> bool:
	if points <= best_arcade_points(tier):
		return false
	if not (arcade().get("best_points") is Dictionary):
		arcade()["best_points"] = {}
	arcade()["best_points"][str(tier)] = points
	return true


## Gefahrene Kilometer aller Fahrten (jeder Modus).
func total_km() -> float:
	return _ride_sum("distance_km")


## Fahrzeit aller Fahrten in Sekunden.
func total_time_s() -> float:
	return _ride_sum("duration_s")


## Volle Runden aller Fahrten.
func total_laps() -> int:
	return int(_ride_sum("laps"))


## Zu Ende gefahrene Trainings (Einheit bis zum Ausrollen, #37).
func finished_trainings() -> int:
	var count := 0
	for ride in rides():
		if ride is Dictionary and ride.get("mode") == MODE_TRAINING and ride.get("finished") == true:
			count += 1
	return count


func _ride_sum(key: String) -> float:
	var sum := 0.0
	for ride in rides():
		var value = ride.get(key) if ride is Dictionary else null
		if (value is float or value is int) and value > 0.0:
			sum += value
	return sum


## Bereich `area` des Profils für Strecke und Richtung ({} wenn er fehlt oder ungültig ist); mit `create` angelegt.
func _area(area: String, track: String, direction: String, create: bool = false) -> Dictionary:
	var tracks: Dictionary = profile()[area]
	if not (tracks.get(track) is Dictionary):
		if not create:
			return {}
		tracks[track] = {}
	if not (tracks[track].get(direction) is Dictionary):
		if not create:
			return {}
		tracks[track][direction] = {}
	return tracks[track][direction]


## Zusammenfassung einer beendeten Fahrt – keine Rohtelemetrie. `finished`: Ziel erreicht (sonst abgebrochen oder
## endlos). `laps`: abgeschlossene Runden, `lap_times_s` ihre Zeiten.
## `direction` und `segment_times_s` (je Segment-ID die beste Zeit dieser Fahrt) kamen in der Nacharbeit zu #26 dazu –
## additiv: ältere Einträge ohne sie bleiben gültig.
static func ride_entry(mode: String, track: String, finished: bool, laps: int, stats: RideStats,
		date: String = utc_now(), lap_times_s: Array = [], direction: String = Track.DIRECTION_CW,
		segment_times_s: Dictionary = {}) -> Dictionary:
	var segments := {}
	for id in segment_times_s:
		segments[id] = snappedf(float(segment_times_s[id]), 0.01)
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
		"direction": direction,
		"segment_times_s": segments,
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
