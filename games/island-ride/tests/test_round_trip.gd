## Rundfahrt mit Runden und Bestzeit (#31) gegen den Fake-Bus: Menü mit Rundenzahl und Tageszeit, HUD mit Runde und
## Rundenzeit, Ergebnis mit allen Rundenzeiten, Bestzeit im Spielstand (übersteht einen Neustart), endlos bis „Fahrt
## beenden“, und die ehrliche Wertung (ADR-0010): die Rundenzeit hängt nur an Kadenz und Steigung.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_round_trip_savegame.json")
## Schnelles Rad für den Durchstich: 120 rpm · 10 km/h je rpm ≈ 330 m/s flach – eine Graybox-Runde in wenigen Sekunden.
const FAST_K := 10.0
const DT := 1.0 / 60.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus, mit Test-Spielstand; schnelles Rad ohne Trägheit.
func _spawn_game(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## Im Startmenü „Fahren → Rundfahrt“ öffnen.
func _open_round_trip(game: Node) -> void:
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()


## Rundenzahl wählen (wie im Menü; 0 = endlos).
func _select_laps(game: Node, laps: int) -> void:
	(game.start_menu.options["laps"] as OptionButton).select(game.start_menu.LAP_CHOICES.find(laps))


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


func test_round_trip_menu_offers_laps_and_time_of_day() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	_open_round_trip(game)
	var menu: CanvasLayer = game.start_menu
	assert_true(menu.buttons["start"].is_visible_in_tree(), "Seite „Rundfahrt“")
	assert_eq(game.get_viewport().gui_get_focus_owner(), menu.buttons["start"], "Fokus auf „Losfahren“")
	var laps: OptionButton = menu.options["laps"]
	var lap_texts := []
	for i in range(laps.item_count):
		lap_texts.append(laps.get_item_text(i))
	assert_eq(lap_texts[0], "1", "Standard: eine Runde")
	assert_has(lap_texts, "2")
	assert_has(lap_texts, "20")
	assert_eq(lap_texts[-1], "Endlos")
	assert_eq(menu.round_trip_laps(), 1)
	var time: OptionButton = menu.options["time"]
	var settings_time: OptionButton = game.settings_menu.options["time"]
	assert_eq(time.item_count, settings_time.item_count, "dieselben Tageszeiten wie im Einstellungsmenü")
	assert_eq(time.get_item_text(time.selected), "Echtzeit (Mallorca)", "Standard: Echtzeit")
	assert_string_contains((menu.find_child("BestTime", true, false) as Label).text, "noch keine")
	# Tageszeit 20:30 und endlos wählen, losfahren: wirkt wie im Einstellungsmenü.
	var evening := -1
	for i in range(time.item_count):
		if time.get_item_text(i) == "20:30 Uhr":
			evening = i
	assert_gt(evening, 0, "20:30 Uhr in der Auswahl")
	time.select(evening)
	_select_laps(game, 0)
	assert_eq(menu.round_trip_laps(), 0, "endlos")
	menu.buttons["start"].pressed.emit()
	assert_false(menu.visible, "Fahrt läuft")
	assert_eq(game.laps, 0, "endlose Fahrt")
	assert_eq(game.lap_timing.finish_m(), INF, "ohne Ziel")
	assert_eq(game.settings_menu.settings.time_mode, DayNight.MODE_FIXED, "Tageszeit wie im Einstellungsmenü gesetzt")
	assert_almost_eq(game.settings_menu.settings.fixed_hour, 20.5, 0.001)
	assert_eq(game.sky.clock.mode, DayNight.MODE_FIXED, "Himmel folgt")
	assert_almost_eq(game.sky.clock.fixed_hour, 20.5, 0.001)


func test_two_laps_give_two_lap_times_and_a_best_time_that_survives_restart() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 30.0))
	var game := _spawn_game(bus)
	await run_for(0.2)
	_open_round_trip(game)
	_select_laps(game, 2)
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Rundfahrt fährt los")
	await run_for(0.3)
	var hud: String = game.hud.readout()
	assert_string_contains(hud, "Runde 1 / 2:", "HUD zeigt die Runde")
	assert_string_contains(hud, "Rundenzeit: %s" % game.format_time(game.lap_timing.lap_time_s))
	assert_true(await run_until(func(): return game.lap_timing.lap_times.size() == 1, 10.0), "Runde 1")
	assert_string_contains(game.hud.celebration(), "Neue Bestzeit!", "erste Runde: neue Bestzeit eingeblendet")
	assert_true(await run_until(func(): return game.hud.readout().contains("Runde 2 / 2:"), 1.0), "HUD: zweite Runde")
	assert_true(await run_until(func(): return game.state == "finished", 10.0), "Ziel nach zwei Runden")
	var times: Array = game.lap_timing.lap_times
	assert_eq(times.size(), 2, "zwei Rundenzeiten")
	var best := minf(times[0], times[1])
	assert_almost_eq(times[0] + times[1], game.stats.ride_time_s, 0.001, "Runden ergeben die Fahrzeit")
	var message := _message(game)
	assert_string_contains(message, "Ziel erreicht")
	assert_string_contains(message, "Runden: %s · %s" % [game.format_time(times[0], true), game.format_time(times[1], true)])
	assert_string_contains(message, "Bestzeit: %s – neu!" % game.format_time(best, true))
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride["laps"], 2)
	assert_true(ride["finished"])
	assert_eq(ride["lap_times_s"].size(), 2, "Rundenzeiten der Fahrt im Fahrtenbuch")
	assert_almost_eq(game.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), best, 0.001,
			"eine Bestzeit: die schnellere Runde")
	# Neustart: eine neue Hauptszene liest denselben Spielstand und zeigt die Bestzeit im Rundfahrt-Menü.
	var restarted := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	assert_almost_eq(restarted.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW), best, 0.001)
	_open_round_trip(restarted)
	var label: Label = restarted.start_menu.find_child("BestTime", true, false)
	assert_true(label.is_visible_in_tree())
	var saved_best: float = restarted.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW)
	assert_eq(label.text, "Bestzeit: %s" % restarted.format_time(saved_best, true), "Bestzeit nach dem Neustart angezeigt")


func test_endless_ride_ends_with_result_of_full_laps_only() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 30.0))
	var game := _spawn_game(bus)
	await run_for(0.2)
	_open_round_trip(game)
	_select_laps(game, 0)
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.lap_timing.lap_times.size() == 1, 12.0), "Runde 1")
	assert_string_contains(game.hud.readout(), "Runde 2:", "endlos: Runde ohne Gesamtzahl")
	await run_for(0.3)
	assert_eq(game.state, "riding", "endlos: kein Ziel")
	assert_gt(game.lap_timing.lap_time_s, 0.0, "Runde 2 angefangen")
	game.settings_menu.ride_end_requested.emit()  # „Fahrt beenden“
	assert_eq(game.state, "finished", "erst das Ergebnis")
	var message: String = game.status_message()
	assert_string_contains(message, "Fahrt beendet")
	assert_string_contains(message, "Runde: %s" % game.format_time(game.lap_timing.lap_times[0], true))
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride["laps"], 1, "nur die volle Runde")
	assert_false(ride["finished"], "endlos: kein Ziel erreicht")
	assert_almost_eq(game.save_game.best_time_s(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW),
			game.lap_timing.lap_times[0], 0.001, "angefangene Runde zählt nicht für die Bestzeit")
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu", "Enter → Menü")
	assert_eq(game.save_game.rides().size(), 1, "nicht doppelt gespeichert")


## Eine neue Fahrt über `laps` Runden auf der Graybox mit fester Kadenz, Schritt für Schritt (DT) durch die
## Hauptszene – unabhängig von Bildrate und Echtzeit. Liefert die Zeit der ersten Runde.
func _lap_time(ride: Node, laps: int = 1) -> float:
	ride.set_process(false)  # nur noch die festen Schritte unten
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, laps)
	for i in range(100000):
		if not ride.lap_timing.lap_times.is_empty():
			break
		ride._ride(DT)
	assert_eq(ride.lap_timing.lap_times.size(), 1, "Runde zu Ende gefahren")
	return ride.lap_timing.lap_times[0]


## Hauptszene am Fake-Bus mit Kadenz `cadence` und weiteren Telemetriefeldern, wartet, bis gefahren wird.
func _riding(cadence: float, fields: Dictionary = {}) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 5.0, 0.25, fields))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == cadence, 3.0))
	return ride


func test_lap_time_depends_only_on_cadence_and_grade() -> void:
	var plain := await _riding(90.0)
	var reference := _lap_time(plain)
	# Alles andere anders: gemessene Watt, Tempo und Puls vom Rad, Nacht, Regen, endlose Rundenzahl gewählt,
	# eine gespeicherte Bestzeit.
	var other := await _riding(90.0, {"power_w": 420.0, "power_estimated": false, "speed_kmh": 55.0, "heart_rate": 172})
	other.sky.set_time_mode(DayNight.MODE_FIXED, 22.0)
	other.sky.set_weather_mode(Weather.MODE_FIXED, Weather.RAIN)
	other.save_game.record_best_time(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, 1.0)
	assert_eq(_lap_time(other, 0), reference, "gleiche Kadenz, gleiche Strecke → exakt gleiche Rundenzeit (ADR-0010)")
	var faster := await _riding(100.0)
	assert_lt(_lap_time(faster), reference, "mehr Kadenz → schnellere Runde")
	# Steigung: dieselbe Kadenz ohne Dämpfung bergauf/Verstärkung bergab ergibt eine andere Zeit.
	var flat_bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0))
	var flat_config := config_for(flat_bus)
	flat_config.uphill_damping = 0.0
	flat_config.downhill_boost = 0.0
	var flat := spawn_ride(flat_bus, 0.0, flat_config)
	assert_true(await run_until(func(): return flat.state == "riding", 3.0))
	assert_lt(_lap_time(flat), reference, "ohne Wirkung der Steigung schneller: die Steigung zählt")
