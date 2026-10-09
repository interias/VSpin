## Erfolge (#35): alle sind Daten mit eindeutiger ID und Text (ohne verbotene Begriffe), je Kategorie fällt ein Erfolg
## auf sein Ereignis und einer nicht, ein Erfolg fällt nur einmal, und ein bestehender Spielstand ohne Erfolge zieht
## beim nächsten Fahrtende nach. Jahreszeit (#39) und Training (#37) gibt es noch nicht – die Tests füttern die Logik
## direkt mit deren Ereignissen.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_achievements_savegame.json")
const EVENTS := [Achievements.EVENT_DISTANCE, Achievements.EVENT_LAP, Achievements.EVENT_WEATHER,
		Achievements.EVENT_TIME_OF_DAY, Achievements.EVENT_SEASON, Achievements.EVENT_TRAINING]


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## IDs der Erfolge, die `event` bei leerem Stand neu erfüllt.
func _ids(event: Dictionary, unlocked: Dictionary = {}) -> Array:
	return Achievements.check(event, unlocked).map(func(a): return a["id"])


func test_achievements_are_data_with_unique_id_and_text() -> void:
	var ids := {}
	var per_category := {}
	assert_between(Achievements.LIST.size(), 20, 30, "etwa 25 Erfolge zum Start")
	for achievement in Achievements.LIST:
		var id: String = achievement["id"]
		assert_false(ids.has(id), "ID %s eindeutig" % id)
		ids[id] = true
		assert_false((achievement["name"] as String).is_empty(), "%s hat einen Namen" % id)
		assert_false((achievement["text"] as String).is_empty(), "%s hat einen Text" % id)
		assert_has(Achievements.CATEGORIES, achievement["category"], "%s: bekannte Kategorie" % id)
		assert_has(EVENTS, achievement["event"], "%s: Ereignis aus dem Vertrag" % id)
		assert_false((achievement["when"] as Dictionary).is_empty(), "%s: Bedingung als Daten" % id)
		per_category[achievement["category"]] = per_category.get(achievement["category"], 0) + 1
		var words := ("%s %s" % [achievement["name"], achievement["text"]]).to_lower()
		for forbidden in ["achievement", "abzeichen", "medaille"]:
			assert_false(words.contains(forbidden), "%s: kein „%s“ (CONTEXT.md)" % [id, forbidden])
	for category in Achievements.CATEGORIES:
		assert_gt(per_category.get(category, 0), 0, "Kategorie %s hat Erfolge" % category)
	assert_eq(Achievements.find("night")["name"], "Nachtfahrt")
	assert_eq(Achievements.find("gibt_es_nicht"), {})


func test_distance() -> void:
	assert_eq(_ids({"type": "distance", "total_km": 0.9, "ride_km": 0.9}), [], "unter 1 km nichts")
	assert_eq(_ids({"type": "distance", "total_km": 1.0, "ride_km": 1.0}), ["km_1"], "1 km gesamt")
	assert_eq(_ids({"type": "distance", "total_km": 120.0, "ride_km": 4.0}), ["km_1", "km_10", "km_100"],
			"alles, was die Gesamt-km schon erfüllen")
	assert_has(_ids({"type": "distance", "total_km": 20.0, "ride_km": 20.0}), "ride_km_20", "20 km in einer Fahrt")
	assert_does_not_have(_ids({"type": "distance", "total_km": 300.0, "ride_km": 19.9}), "ride_km_20",
			"20 km über mehrere Fahrten zählen nicht als eine")


func test_laps() -> void:
	assert_eq(_ids({"type": "lap", "total_laps": 0, "ride_laps": 0}), [], "keine volle Runde")
	assert_eq(_ids({"type": "lap", "total_laps": 1, "ride_laps": 1}), ["laps_1"], "erste Runde")
	assert_has(_ids({"type": "lap", "total_laps": 12, "ride_laps": 3}), "ride_laps_3", "3 Runden in einer Fahrt")
	assert_does_not_have(_ids({"type": "lap", "total_laps": 12, "ride_laps": 2}), "ride_laps_3")
	assert_eq(_ids({"type": "lap", "total_laps": 1.0, "ride_laps": 1.0}), ["laps_1"], "Zahlen aus JSON (float)")


func test_time_of_day() -> void:
	assert_eq(_ids({"type": "time_of_day", "hour": 23.5}), ["night"], "23:30 Nachtfahrt")
	assert_eq(_ids({"type": "time_of_day", "hour": 2.0}), ["night"], "2:00 Nachtfahrt (über Mitternacht)")
	assert_eq(_ids({"type": "time_of_day", "hour": 6.5}), ["morning"], "6:30 Frühaufsteher")
	assert_eq(_ids({"type": "time_of_day", "hour": 10.0}), [], "10:00: kein Tageszeit-Erfolg")
	assert_eq(_ids({"type": "time_of_day", "hour": 21.0}), [], "21:00 gehört nicht mehr zur Feierabendrunde")
	assert_eq(_ids({"type": "weather", "hour": 23.5}), [], "Feld im falschen Ereignis zählt nicht")


func test_weather() -> void:
	assert_eq(_ids({"type": "weather", "state": Weather.RAIN}), ["rain"], "im Regen gefahren")
	assert_eq(_ids({"type": "weather", "state": Weather.CLEAR}), ["clear"])
	assert_does_not_have(_ids({"type": "weather", "state": Weather.OVERCAST}), "rain", "bewölkt ist kein Regen")


func test_season_events_for_issue_39() -> void:
	assert_eq(_ids({"type": "season", "season": "spring"}), ["spring"], "Frühling")
	assert_eq(_ids({"type": "season", "season": "winter"}), ["winter"], "Winter")
	assert_eq(_ids({"type": "season", "season": "Frühling"}), [], "nur die Werte aus Achievements.SEASONS")
	for season in Achievements.SEASONS:
		assert_eq(_ids({"type": "season", "season": season}).size(), 1, "je Jahreszeit ein Erfolg: %s" % season)


func test_training_events_for_issue_37() -> void:
	assert_eq(_ids({"type": "training_finished", "total_trainings": 1, "score": 0.95}),
			["training_1", "training_precise"], "erste Einheit, Zielkadenz getroffen")
	assert_eq(_ids({"type": "training_finished", "total_trainings": 1, "score": 0.5}), ["training_1"],
			"50 % Treffer: keine Punktlandung")
	assert_eq(_ids({"type": "training_finished", "total_trainings": 0, "score": 0.2}), [], "kein Training beendet")


func test_achievement_falls_only_once() -> void:
	var save := SaveGame.new()
	var event := {"type": "weather", "state": Weather.RAIN}
	var first := Achievements.check(event, save.achievements())
	assert_eq(first.size(), 1)
	assert_true(save.unlock_achievement(first[0]["id"], "2026-10-07T21:00:00Z"), "neu freigeschaltet")
	assert_eq(_ids(event, save.achievements()), [], "fällt nur einmal")
	assert_false(save.unlock_achievement("rain", "2026-12-24T10:00:00Z"), "kein zweites Mal")
	assert_eq(save.achievements()["rain"], "2026-10-07T21:00:00Z", "das erste Datum bleibt")
	save.save_file(SAVE_PATH)
	assert_eq(SaveGame.load_file(SAVE_PATH).achievements(), {"rain": "2026-10-07T21:00:00Z"}, "übersteht einen Neustart")


func test_existing_save_without_achievements_catches_up_at_ride_end() -> void:
	# Ein Stand von vor #35: 13 Fahrten zu je einer Inselrunde, kein Bereich „achievements“.
	var rides := []
	for i in range(13):
		rides.append({"date": "2026-10-0%dT18:00:00Z" % (1 + i % 7), "mode": "rundfahrt", "track": "island",
			"finished": true, "laps": 1, "duration_s": 1500.0, "distance_km": 9.21, "avg_cadence_rpm": 85.0,
			"avg_speed_kmh": 22.1, "lap_times_s": [1500.0]})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "active_profile": "0123456789abcdef",
		"profiles": {"0123456789abcdef": {"created": "2026-10-01T10:00:00Z", "rides": rides}}}))
	file.close()
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(start_fake_bus([FakeBusServer.status()]))
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	game.start_in_menu = false
	add_child_autofree(game)
	await run_for(0.1)
	assert_eq(game.save_game.achievements(), {}, "älterer Stand: noch keine Erfolge")
	assert_eq(game.ride_level, DriverLevel.level_for(13 * 9.21), "Level aus den bisherigen km")
	game.set_process(false)
	game.start_ride()
	game.stats.add(30.0, 80.0, 200.0)  # kurz gefahren, dann abgebrochen
	game.return_to_menu()
	var unlocked := SaveGame.load_file(SAVE_PATH).achievements()
	for id in ["km_1", "km_10", "km_100", "laps_1", "laps_10"]:
		assert_true(unlocked.has(id), "%s holt der Stand beim Fahrtende nach" % id)
	assert_false(unlocked.has("km_500"), "nur, was er erfüllt")
	assert_false(unlocked.has("ride_laps_3"), "in keiner Fahrt 3 Runden")
	assert_eq(game.ride_level, DriverLevel.level_for(13 * 9.21 + 0.2), "Level aus allen km")
