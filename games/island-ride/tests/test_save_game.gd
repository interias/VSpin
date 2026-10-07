## Spielstand (#30): Version und Profilschlüssel ab dem ersten Speichern, Lesen/Schreiben übersteht einen Neustart,
## Fahrt nur als Zusammenfassung (keine Rohtelemetrie, ADR-0008), additive Bereiche, Hochstufung alter Stände,
## neuere Stände bleiben erhalten, eine kaputte Datei wird beiseitegelegt statt überschrieben.
extends GutTest

const TEMP_PATH := "user://test_savegame.json"


func after_each() -> void:
	for path in [TEMP_PATH, TEMP_PATH + SaveGame.BROKEN_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(text: String) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _stats(seconds: float, cadence: float, meters: float) -> RideStats:
	var stats := RideStats.new()
	stats.add(seconds, cadence, meters)
	return stats


func test_new_save_has_version_and_profile_key() -> void:
	var save := SaveGame.load_file("user://does_not_exist_savegame.json")
	assert_eq(save.version(), SaveGame.VERSION)
	assert_eq(save.profile_key().length(), 16, "Profilschlüssel ab dem ersten Speichern")
	assert_true(save.profile_key().is_valid_hex_number(), "16 Hex-Zeichen: %s" % save.profile_key())
	assert_ne(SaveGame.new().profile_key(), save.profile_key(), "jeder neue Stand bekommt einen eigenen Schlüssel")
	assert_eq(save.rides(), [], "noch keine Fahrten")


func test_ride_survives_restart() -> void:
	var save := SaveGame.new()
	var entry := SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, true, 1,
			_stats(1200.0, 85.0, 9210.0), "2026-10-07T18:30:00Z")
	save.add_ride(entry)
	assert_eq(save.save_file(TEMP_PATH), OK)
	var file := JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH)) as Dictionary
	assert_eq(file["version"], float(SaveGame.VERSION), "Version steht in der Datei")
	assert_eq(file["active_profile"], save.profile_key(), "Profilschlüssel steht in der Datei")
	var loaded := SaveGame.load_file(TEMP_PATH)
	assert_eq(loaded.version(), SaveGame.VERSION)
	assert_eq(loaded.profile_key(), save.profile_key(), "derselbe Fahrer nach dem Neustart")
	assert_eq(loaded.rides().size(), 1)
	var ride: Dictionary = loaded.rides()[0]
	assert_eq(ride["date"], "2026-10-07T18:30:00Z")
	assert_eq(ride["mode"], SaveGame.MODE_ROUND_TRIP)
	assert_eq(ride["track"], RideConfig.TRACK_ISLAND)
	assert_true(ride["finished"])
	assert_eq(ride["laps"], 1.0)
	assert_eq(ride["duration_s"], 1200.0)
	assert_eq(ride["distance_km"], 9.21)
	assert_eq(ride["avg_cadence_rpm"], 85.0)
	assert_almost_eq(ride["avg_speed_kmh"], 27.63, 0.001)
	loaded.add_ride(entry)
	loaded.save_file(TEMP_PATH)
	assert_eq(SaveGame.load_file(TEMP_PATH).rides().size(), 2, "weitere Fahrten werden angehängt")


func test_ride_entry_is_a_summary_without_raw_telemetry() -> void:
	var entry := SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_GRAYBOX, false, 0,
			_stats(61.27, 90.0, 512.3456))
	assert_eq(entry.keys(), ["date", "mode", "track", "finished", "laps", "duration_s", "distance_km",
			"avg_cadence_rpm", "avg_speed_kmh", "lap_times_s"], "nur Zusammenfassung, kein Kadenzverlauf")
	assert_almost_eq(entry["duration_s"], 61.3, 0.0001)
	assert_almost_eq(entry["distance_km"], 0.512, 0.0001)
	assert_false(entry["finished"], "abgebrochen")
	assert_string_ends_with(entry["date"], "Z")
	assert_eq(entry["date"].length(), 20, "UTC wie 2026-10-07T18:30:00Z: %s" % entry["date"])


func test_missing_areas_are_added_and_unknown_kept() -> void:
	_write(JSON.stringify({"version": 1, "active_profile": "abcdef0123456789",
			"profiles": {"abcdef0123456789": {"created": "2026-10-07T10:00:00Z", "later_area": {"x": 1}}},
			"other": [1, 2]}))
	var save := SaveGame.load_file(TEMP_PATH)
	assert_eq(save.profile_key(), "abcdef0123456789")
	assert_eq(save.rides(), [], "fehlender Bereich mit Standardwert ergänzt")
	save.save_file(TEMP_PATH)
	var file := JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH)) as Dictionary
	assert_eq(file["other"], [1.0, 2.0], "Unbekanntes bleibt erhalten")
	assert_eq(file["profiles"]["abcdef0123456789"]["later_area"], {"x": 1.0})


func test_upgrade_runs_steps_in_order_and_keeps_data() -> void:
	var old := {"version": 1.0, "active_profile": "k", "profiles": {"k": {"rides": [{"distance_km": 9.21}]}}}
	var steps := {1: _add_best_times, 2: _add_medals}
	var upgraded := SaveGame.upgrade(old, steps, 3)
	assert_eq(upgraded["version"], 3, "auf die neue Version hochgestuft")
	assert_eq(upgraded["profiles"]["k"]["medals"], [true], "Schritte der Reihe nach (1 → 2 → 3)")
	assert_eq(upgraded["profiles"]["k"]["rides"], [{"distance_km": 9.21}], "alte Fahrten bleiben")
	assert_eq(old["version"], 1.0, "der alte Stand selbst bleibt unberührt")
	assert_eq(SaveGame.upgrade(upgraded, steps, 3), upgraded, "aktueller Stand: nichts zu tun")


## Beispiel-Hochstufungen 1 → 2 → 3 (wie sie spätere Pakete anlegen).
func _add_best_times(d: Dictionary) -> Dictionary:
	d["profiles"]["k"]["best_times"] = {}
	return d


func _add_medals(d: Dictionary) -> Dictionary:
	d["profiles"]["k"]["medals"] = [d["profiles"]["k"].has("best_times")]
	return d


func test_newer_version_is_kept_when_saving() -> void:
	_write(JSON.stringify({"version": 99, "active_profile": "abcdef0123456789",
			"profiles": {"abcdef0123456789": {"rides": [], "ghosts": {"island": [1, 2, 3]}}}}))
	var save := SaveGame.load_file(TEMP_PATH)
	assert_eq(save.version(), 99, "nicht herabgestuft")
	save.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, true, 1, _stats(10.0, 80.0, 50.0)))
	save.save_file(TEMP_PATH)
	var reloaded := SaveGame.load_file(TEMP_PATH)
	assert_eq(reloaded.version(), 99)
	assert_eq(reloaded.profile()["ghosts"], {"island": [1.0, 2.0, 3.0]}, "Daten der neueren Version bleiben")
	assert_eq(reloaded.rides().size(), 1)


func test_broken_file_is_set_aside_not_overwritten() -> void:
	_write("{\"version\": 1, \"profiles\": kaputt")
	var save := SaveGame.load_file(TEMP_PATH)
	assert_eq(save.rides(), [], "neuer Stand")
	assert_false(FileAccess.file_exists(TEMP_PATH), "kaputte Datei nicht mehr unter dem alten Namen")
	assert_eq(FileAccess.get_file_as_string(TEMP_PATH + SaveGame.BROKEN_SUFFIX), "{\"version\": 1, \"profiles\": kaputt",
			"… sondern unverändert beiseitegelegt")
	for text in ["[1, 2, 3]", "{\"profiles\": {}}", "{\"version\": 0}"]:
		_write(text)
		DirAccess.remove_absolute(TEMP_PATH + SaveGame.BROKEN_SUFFIX)
		assert_eq(SaveGame.load_file(TEMP_PATH).rides(), [], "kein Spielstand (%s) → neuer Stand" % text)
		assert_false(FileAccess.file_exists(TEMP_PATH), "%s beiseitegelegt" % text)
		assert_true(FileAccess.file_exists(TEMP_PATH + SaveGame.BROKEN_SUFFIX))
