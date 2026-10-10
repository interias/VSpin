## Simulator-Profil der Bridge (`bridge/profiles/**.toml`) als Drehbuch für den Fake-Bus (#46): Spiel-Tests spielen
## so denselben Kadenzverlauf, den die Bridge mit `--profile` sendet – Szenarien laufen durch das echte Spiel.
## Liest nur die Teilmenge von TOML, die die Profile nutzen (`name`, `repeat`, `[[steps]]` mit `duration_s`, `cadence`,
## `cadence_to`, `action`; Kommentare mit `#`).
##
## Nachgebildet wird, was die Bridge am Bus daraus macht (bridge/README.md „Profile“, docs/bus-protocol.md):
##   Fahren      `round(duration_s / 0,25)` Telemetrien im Takt 0,25 s, Kadenz linear von `cadence` nach `cadence_to`
##               (auf 0,1 rpm); nach `stale`/`disconnected` erst `status: connected`
##   pause       keine Daten; dauert die Lücke länger als 3 s, `status: stale` 3 s nach der letzten Telemetrie
##   disconnect  `status: disconnected`, nach der Ausfallzeit beim nächsten Neuversuch (alle 3 s) wieder `connected`
##   Ende        ohne `repeat` `status: disconnected` (Quelle beendet)
## Die EMA-Glättung der Bridge fehlt: bei gleichbleibender Kadenz ist sie wirkungslos.
class_name SimProfile
extends RefCounted

## Profile der Bridge, vom Spielordner aus.
const BRIDGE_PROFILES := "../../bridge/profiles"
const TICK_S := 0.25
const STALE_AFTER_S := 3.0
const RECONNECT_S := 3.0


## Pfad eines Profils unter `bridge/profiles`, z. B. `path("arcade/zone_perfekt.toml")`.
static func path(relative: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(BRIDGE_PROFILES).path_join(relative).simplify_path()


## Profil aus `file`: {name, repeat, steps: [{duration_s, cadence?, cadence_to?, action?}]}; {} wenn unlesbar.
static func load_toml(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		push_error("SimProfile: %s fehlt" % file)
		return {}
	var profile := {"name": file.get_file().get_basename(), "repeat": false, "steps": []}
	var table := profile
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		var line := raw.get_slice("#", 0).strip_edges()
		if line.is_empty():
			continue
		if line == "[[steps]]":
			table = {}
			profile["steps"].append(table)
			continue
		var key := line.get_slice("=", 0).strip_edges()
		var value := line.substr(line.find("=") + 1).strip_edges()
		if value.begins_with("\""):
			table[key] = value.trim_prefix("\"").trim_suffix("\"")
		elif value in ["true", "false"]:
			table[key] = value == "true"
		else:
			table[key] = float(value)
	return profile


## Drehbuch für FakeBusServer aus `profile` (wie load_toml), beginnend mit `status: connected`.
static func to_script(profile: Dictionary) -> Array:
	var steps: Array = [FakeBusServer.status()]
	var t := 0.0
	var state := "connected"
	for step in profile["steps"]:
		var duration: float = step["duration_s"]
		match step.get("action", ""):
			"pause":
				if duration > STALE_AFTER_S:
					steps.append(FakeBusServer.status("stale", "sim", ["CADENCE"], t - TICK_S + STALE_AFTER_S))
					state = "stale"
				t += duration
			"disconnect":
				steps.append(FakeBusServer.status("disconnected", "sim", ["CADENCE"], t))
				t += ceilf(duration / RECONNECT_S) * RECONNECT_S
				steps.append(FakeBusServer.status("connected", "sim", ["CADENCE"], t))
				state = "connected"
			_:
				if state != "connected":
					steps.append(FakeBusServer.status("connected", "sim", ["CADENCE"], t))
					state = "connected"
				var count := maxi(1, roundi(duration / TICK_S))
				var from: float = step["cadence"]
				var to: float = step.get("cadence_to", from)
				for i in range(count):
					var fraction := float(i) / (count - 1) if count > 1 else 0.0
					steps.append(FakeBusServer.telemetry(snappedf(from + (to - from) * fraction, 0.1), t))
					t += TICK_S
	if not profile.get("repeat", false):
		steps.append(FakeBusServer.status("disconnected", "sim", ["CADENCE"], t))
	return steps


## Dauer des Profils (s, ohne Wiederholung) – so lange spielt das Drehbuch.
static func duration_s(profile: Dictionary) -> float:
	var total := 0.0
	for step in profile["steps"]:
		var duration: float = step["duration_s"]
		total += ceilf(duration / RECONNECT_S) * RECONNECT_S if step.get("action", "") == "disconnect" else duration
	return total
