## Puls in der Fahrt (#64) gegen den Fake-Bus: eine Fahrt mit `heart_rate` in der Telemetrie endet mit Ø-Puls, Max-Puls
## und Zeit je Zone im Spielstand und im Ergebnis (Rundfahrt, Training, Arcade); eine Fahrt ohne Puls endet ohne
## Pulsfelder und ohne Pulszeile. Die Zonen gelten ab dem Start der Fahrt (Profil beim Start), nur Fahrzeit zählt.
## Gefahren wird in festen Schritten (DT) durch die Hauptszene; der Spielstand bleibt im Speicher (kein `user://`).
extends "res://tests/support/bus_test.gd"

const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const DT := 0.1


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


## Zeit je Zone einer Fahrt. Fehlt sie, schlägt die Prüfung fehl und es kommen Nullen zurück: Ein Zugriff auf ein fehlendes
## Feld wäre ein Skriptfehler, den GUT nicht als Fehlschlag zählt.
func _zones(ride: Dictionary) -> Array:
	assert_true(ride.has("hr_zone_s"), "Zeit je Zone gespeichert")
	return ride.get("hr_zone_s", [0.0, 0.0, 0.0, 0.0, 0.0])


## Hauptszene am Fake-Bus mit Kadenz 90 und `fields` in jeder Telemetrie, wartet auf Kadenz (und Puls, falls gesendet).
func _spawn(fields: Dictionary) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0, 0.25, fields))
	var game := spawn_ride(bus, 0.0)
	var wants_pulse := fields.has("heart_rate")
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence == 90.0 and game.bus.has_heart_rate() == wants_pulse, 3.0))
	game.set_process(false)
	return game


func _drive(game: Node, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		if game.state != "riding":
			break
		game._ride(DT)
		game._update_view()


func _end(game: Node) -> void:
	game._finish_ride()  # Ergebnis wie am Ziel
	assert_eq(game.state, "finished")
	game._update_view()


func test_ride_with_pulse_saves_values_and_shows_them_in_result() -> void:
	var game := await _spawn({"heart_rate": 140})
	game.save_game.set_heart_rate_profile(170, 0)  # Z2 = 138–152 bpm
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	_drive(game, 20.0)
	_end(game)
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride.get("avg_hr_bpm"), 140.0)
	assert_eq(ride.get("peak_hr_bpm"), 140)
	var zones := _zones(ride)
	assert_almost_eq(zones[1], 20.0, 0.2, "20 s in Z2")
	assert_eq(zones[0] + zones[2] + zones[3] + zones[4], 0.0, "sonst keine Zeit")
	var message := _message(game)
	assert_string_contains(message, "Ø Puls 140 · Max 140 bpm")
	assert_string_contains(message, "Zonen: Z2 0:20")
	assert_string_contains(message, "Enter: zurück ins Menü", "Hinweis bleibt am Ende")


func test_zones_are_those_of_the_start_and_stored_not_recomputed() -> void:
	var game := await _spawn({"heart_rate": 140})
	game.save_game.set_heart_rate_profile(170, 0)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	game.save_game.set_heart_rate_profile(120, 0)  # Änderung mitten in der Fahrt gilt erst für die nächste
	_drive(game, 10.0)
	_end(game)
	var zones := _zones(game.save_game.rides()[0])
	assert_almost_eq(zones[1], 10.0, 0.2, "Z2 der LTHR 170, nicht der LTHR 120")
	game.save_game.set_heart_rate_profile(100, 0)
	assert_almost_eq(_zones(game.save_game.rides()[0])[1], zones[1], 0.0001, "gespeichert, nicht neu gerechnet")


func test_ride_with_pulse_but_without_profile_has_avg_and_max_only() -> void:
	var game := await _spawn({"heart_rate": 140})
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	_drive(game, 5.0)
	_end(game)
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride.get("avg_hr_bpm"), 140.0)
	assert_false(ride.has("hr_zone_s"), "ohne Zonen keine Zeit je Zone")
	assert_string_contains(_message(game), "Ø Puls 140 · Max 140 bpm")
	assert_false(_message(game).contains("Zonen:"))


func test_ride_without_pulse_has_no_pulse_fields_and_no_pulse_line() -> void:
	var game := await _spawn({})
	game.save_game.set_heart_rate_profile(170, 190)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	_drive(game, 10.0)
	_end(game)
	var ride: Dictionary = game.save_game.rides()[0]
	for key in ["avg_hr_bpm", "peak_hr_bpm", "hr_zone_s"]:
		assert_false(ride.has(key), "%s fehlt ohne Puls" % key)
	assert_false(_message(game).contains("Puls"), "keine Pulszeile")


func test_pause_time_does_not_count() -> void:
	var game := await _spawn({"heart_rate": 140})
	game.save_game.set_heart_rate_profile(170, 0)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	_drive(game, 5.0)
	game.state = "paused_manual"  # in der Pause wird nicht gefahren: `_ride` läuft nicht
	_drive(game, 30.0)
	game.state = "riding"
	_drive(game, 5.0)
	assert_almost_eq(game.pulse_stats.pulse_time_s, 10.0, 0.25, "nur Fahrzeit")
	assert_almost_eq(game.pulse_stats.pulse_time_s, game.stats.ride_time_s, 0.0001, "wie RideStats")


func test_training_and_arcade_rides_carry_pulse_too() -> void:
	var game := await _spawn({"heart_rate": 160})
	game.save_game.set_heart_rate_profile(170, 0)  # Z4 ab 160 bpm
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(SHORT_UNIT))
	_drive(game, 8.0)
	_end(game)
	var training: Dictionary = game.save_game.rides()[0]
	assert_eq(training["mode"], SaveGame.MODE_TRAINING)
	assert_eq(training.get("peak_hr_bpm"), 160)
	assert_almost_eq(_zones(training)[3], 8.0, 0.2)
	assert_string_contains(_message(game), "Zonen: Z4 0:08")
	game.start_ride(SaveGame.MODE_ARCADE, 0)
	_drive(game, 6.0)
	_end(game)
	var arcade: Dictionary = game.save_game.rides()[1]
	assert_eq(arcade["mode"], SaveGame.MODE_ARCADE)
	assert_eq(arcade.get("peak_hr_bpm"), 160)
	assert_almost_eq(_zones(arcade)[3], 6.0, 0.2)
	assert_string_contains(_message(game), "Ø Puls 160 · Max 160 bpm", "Arcade-Ergebnis zeigt den Puls")
	assert_string_contains(_message(game), "Enter: zurück ins Menü")
