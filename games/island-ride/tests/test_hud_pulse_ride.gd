## Puls im HUD der Hauptszene (#64) gegen den Fake-Bus: der Puls kommt an und steht im Werte-Panel (Zahl, Zone, Farbe),
## ein Ausfall zeigt „--“, die Fahrt läuft weiter und der Puls kehrt zurück; ohne Pulsquelle fehlt die Anzeige; die
## Anzeige gilt in Rundfahrt, Training und Arcade. Dazu die Ergebnisanzeige mit Pulszeilen in 1152×648 für alle drei Modi:
## vollständig im Fenster, frei von den Panels, nichts abgeschnitten.
## Gefahren wird in Echtzeit durch die Hauptszene oder in festen Schritten (DT); der Spielstand bleibt im Speicher.
extends "res://tests/support/bus_test.gd"

const DT := 0.1
const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const PYRAMID := "res://trainings/pyramide.json"
## LTHR 160: Z1 < 130, Z2 130–143, Z3 144–149, Z4 150–159, Z5 ab 160 bpm.
const LTHR := 160


func _hud(game: Node) -> RideHud:
	return game.get_node("Hud")


func _pulse_text(game: Node) -> String:
	return _hud(game).get_node("%PulseValue").text


func _pulse_visible(game: Node) -> bool:
	return _hud(game).get_node("%Pulse").is_visible_in_tree()


## Drehbuch: Gurt verbunden mit 148 bpm (0–1,5 s), Ausfall (`stale`, kein Puls, 1,6–3 s), danach 150 bpm.
func _outage_steps() -> Array:
	var device := FakeBusServer.heart_rate_device()
	return [FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, FakeBusServer.heart_rate_block("connected", device))] \
			+ FakeBusServer.steady_cadence(90.0, 0.0, 1.5, 0.25, {"heart_rate": 148}) \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 1.6, FakeBusServer.heart_rate_block("stale", device))] \
			+ FakeBusServer.steady_cadence(90.0, 1.75, 3.0, 0.25, {"heart_rate": null}) \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 3.1, FakeBusServer.heart_rate_block("connected", device))] \
			+ FakeBusServer.steady_cadence(90.0, 3.25, 9.0, 0.25, {"heart_rate": 150})


func test_pulse_arrives_in_the_hud_and_an_outage_shows_dashes_while_the_ride_goes_on() -> void:
	var bus := start_fake_bus(_outage_steps())
	var game := spawn_ride(bus, 0.0)
	game.save_game.set_heart_rate_profile(LTHR, 0)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.has_heart_rate(), 3.0), "Puls kommt an")
	await run_for(0.3)
	assert_eq(_pulse_text(game), "148", "Zahl im Werte-Panel")
	assert_eq(_hud(game).get_node("%PulseZone").text, "Z3")
	assert_eq(_hud(game).get_node("%PulseValue").get_theme_color("font_color"), HeartRateZones.COLORS[2], "Farbe der Zone")
	assert_gt(_hud(game).get_node("%PulseGraph").samples.size(), 0, "die Kurve nimmt Punkte auf")
	# Ausfall: „--“, die Fahrt läuft mit der Kadenz weiter
	assert_true(await run_until(func(): return game.bus.heart_rate_state == "stale", 3.0), "Ausfall gemeldet")
	await run_for(0.3)
	assert_eq(_pulse_text(game), "--", "Ausfall: --")
	assert_true(_pulse_visible(game), "die Anzeige bleibt, solange ein Gerät bekannt ist")
	assert_eq(_hud(game).get_node("%PulseZone").text, "", "ohne Wert keine Zone")
	assert_eq(game.state, "riding", "keine Pause wegen des Pulses")
	var distance: float = game.model.distance_m
	await run_for(0.5)
	assert_gt(game.model.distance_m, distance + 0.1, "die Fahrt läuft weiter")
	assert_eq(game.state, "riding")
	# Rückkehr
	assert_true(await run_until(func(): return game.bus.has_heart_rate(), 4.0), "Puls kommt zurück")
	await run_for(0.3)
	assert_eq(_pulse_text(game), "150")
	assert_eq(_hud(game).get_node("%PulseZone").text, "Z4")
	assert_eq(_hud(game).get_node("%PulseValue").get_theme_color("font_color"), HeartRateZones.COLORS[3])


func test_without_zones_the_hud_shows_bpm_only() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
			FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device()))]
			+ FakeBusServer.steady_cadence(90.0, 0.0, 5.0, 0.25, {"heart_rate": 148}))
	var game := spawn_ride(bus, 0.0)
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)  # Profil ohne LTHR und Maximalpuls
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.has_heart_rate(), 3.0))
	await run_for(0.3)
	assert_eq(_pulse_text(game), "148")
	assert_eq(_hud(game).get_node("%PulseZone").text, "", "keine Zone")
	assert_eq(_hud(game).get_node("%PulseValue").get_theme_color("font_color"), Color.WHITE, "neutrale Farbe")


func test_pulse_display_is_gone_without_any_pulse_source() -> void:
	# Bridge ohne Pulsblock (ältere Version) und Bridge mit `off`, jeweils ohne Wert: keine Anzeige.
	for steps in [
			[FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 3.0),
			[FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, FakeBusServer.heart_rate_block("off"))]
					+ FakeBusServer.steady_cadence(90.0, 0.0, 3.0)]:
		var game := spawn_ride(start_fake_bus(steps), 0.0)
		assert_true(await run_until(func(): return game.state == "riding", 3.0))
		await run_for(0.4)
		assert_false(_pulse_visible(game), "ohne Quelle keine Pulsanzeige")
		assert_false(_hud(game).get_node("%PulseGraph").is_visible_in_tree())
		assert_false(_hud(game).readout().contains("Puls"))
		game.queue_free()
	# Der Simulator liefert einen Puls, auch wenn die Bridge `off` meldet: der Wert wird gezeigt.
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, FakeBusServer.heart_rate_block("off"))]
			+ FakeBusServer.steady_cadence(90.0, 0.0, 3.0, 0.25, {"heart_rate": 120}))
	var sim := spawn_ride(bus, 0.0)
	assert_true(await run_until(func(): return sim.state == "riding" and sim.bus.has_heart_rate(), 3.0))
	await run_for(0.3)
	assert_true(_pulse_visible(sim), "Wert vom Simulator")
	assert_eq(_pulse_text(sim), "120")


## Hauptszene am Fake-Bus mit Kadenz 90 und Puls 160, in festen Schritten gefahren.
func _spawn_with_pulse() -> Node:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
			FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device()))]
			+ FakeBusServer.steady_cadence(90.0, 0.0, 5.0, 0.25, {"heart_rate": 160}))
	var game := spawn_ride(bus, 0.0)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.has_heart_rate(), 3.0))
	game.set_process(false)
	game.save_game.set_heart_rate_profile(LTHR, 0)
	return game


func _drive(game: Node, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		if game.state != "riding":
			break
		game._ride(DT)
		game._update_view()


func test_pulse_shows_in_round_trip_training_and_arcade() -> void:
	var game := await _spawn_with_pulse()
	for mode in [SaveGame.MODE_ROUND_TRIP, SaveGame.MODE_TRAINING, SaveGame.MODE_ARCADE]:
		if mode == SaveGame.MODE_TRAINING:
			game.start_ride(mode, 0, "", Training.load_file(SHORT_UNIT))
		else:
			game.start_ride(mode, 0)
		_drive(game, 3.0)
		assert_eq(game.state, "riding", mode)
		assert_eq(_pulse_text(game), "160", "%s: Puls im HUD" % mode)
		assert_eq(_hud(game).get_node("%PulseZone").text, "Z5", "%s: Zone aus dem Profil der Fahrt" % mode)
		assert_gt(_hud(game).get_node("%PulseGraph").samples.size(), 0, "%s: Kurve" % mode)
	# Eine neue Fahrt beginnt eine neue Kurve.
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	var samples: Array[Vector2] = _hud(game).get_node("%PulseGraph").samples
	assert_eq(samples.size(), 1, "neue Fahrt: neue Kurve, nur mit dem ersten Punkt")
	assert_eq(samples[0].x, 0.0, "bei Fahrzeit 0")


func test_zones_in_the_hud_are_those_of_the_ride() -> void:
	var game := await _spawn_with_pulse()
	game.start_ride(SaveGame.MODE_ROUND_TRIP, 0)
	game.save_game.set_heart_rate_profile(100, 0)  # Änderung mitten in der Fahrt gilt erst für die nächste
	_drive(game, 2.0)
	assert_eq(_hud(game).get_node("%PulseZone").text, "Z5", "Zonen der LTHR 160 beim Start (160 bpm = Z5)")
	assert_eq(game.pulse_zones.zone_for(160.0), 5, "Zonen der Fahrt")
	_drive(game, 1.0)
	assert_gt(game.pulse_stats.zone_seconds()[4], 0.0, "pulse_stats zählt in Z5")


# --- Ergebnisanzeige mit Pulszeilen in 1152×648 --------------------------------------------------------------------

## Hauptszene in einem SubViewport der Größe `size`, Fahrt im Modus `mode` gestartet (Prozess aus).
func _ride_in(size: Vector2i, mode: String, training_unit: Dictionary = {}) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	var viewport := SubViewport.new()
	viewport.size = size
	add_child_autofree(viewport)
	var ride := MAIN_SCENE.instantiate()
	ride.config = config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	ride.quit_on_request = false
	ride.settings_path = ""
	ride.save_path = ""
	ride.start_in_menu = false
	viewport.add_child(ride)
	await wait_process_frames(2)
	ride.set_process(false)
	ride.save_game.set_heart_rate_profile(LTHR, 0)
	ride.start_ride(mode, 20 if mode == SaveGame.MODE_ROUND_TRIP else 0, "", training_unit)
	return ride


## Pulsstatistik mit Zeit in allen fünf Zonen (die längste Pulszeile) und hohen Zeiten (breiteste Ziffern).
func _fill_pulse(ride: Node) -> void:
	for bpm in [120.0, 135.0, 147.0, 155.0, 171.0]:
		ride.pulse_stats.add(3000.0 + bpm, bpm)


func _assert_result_fits(ride: Node, size: Vector2i, label_text: String) -> void:
	var label: Label = ride.get_node("Hud/Message")
	assert_eq(ride.state, "finished", label_text)
	assert_true(label.is_visible_in_tree(), "%s: Ergebnis sichtbar" % label_text)
	assert_string_contains(label.text, "Ø Puls ", "%s: Pulszeile da" % label_text)
	assert_string_contains(label.text, "Zonen: Z1 ", "%s: Zonenzeile da" % label_text)
	assert_string_contains(label.text, "Z5 ", "%s: alle Zonen" % label_text)
	assert_string_contains(label.text, "Esc: Einstellungen", "%s: letzte Zeile da" % label_text)
	var hud: RideHud = ride.hud
	var message := label.get_global_rect()
	assert_eq(hud.get_viewport().get_visible_rect().size, Vector2(size), "%s: Fenstergröße" % label_text)
	assert_true(hud.get_node("Layout").get_viewport_rect().encloses(message), "%s: im Fenster (%s)" % [label_text, message])
	for panel: Control in [hud.get_node("%Stats"), hud.get_node("%Bottom"), hud.get_node("%Minimap").get_parent()]:
		if panel.is_visible_in_tree():
			assert_false(message.intersects(panel.get_global_rect()),
					"%s: Ergebnis %s frei von %s %s" % [label_text, message, panel.name, panel.get_global_rect()])
	assert_eq(label.get_visible_line_count(), label.get_line_count(), "%s: keine Zeile abgeschnitten" % label_text)
	assert_gte(label.get_theme_font_size("font_size"), RideHud.MIN_MESSAGE_FONT_PX, "%s: lesbar" % label_text)
	assert_true(hud.compact == (size.y < RideHud.COMPACT_BELOW_PX), "%s: Leisten passend zur Höhe" % label_text)
	gut.p("%s: Schrift %d px, Meldung %s, Streifen %s" % [label_text, label.get_theme_font_size("font_size"), message,
			(hud.get_node("%Celebration").get_parent() as Control).get_global_rect()])


func test_round_trip_result_with_pulse_lines_fits_in_1152x648() -> void:
	var size := Vector2i(1152, 648)
	var ride := await _ride_in(size, SaveGame.MODE_ROUND_TRIP)
	# 20 Runden mit gemischten Medaillen und Segmenten wie im Test des Ergebnisses (der längste Fall), dazu die Pulszeilen
	var limits: Dictionary = ride.medal_limits[Medals.LAP]
	var lap: float = ride.track.length_m()
	for i in range(20):
		var t: float = limits[Medals.GOLD] - 5.0 - i
		if i >= 12:
			t = (limits[Medals.GOLD] + limits[Medals.SILVER]) / 2.0 + i
		if i >= 17:
			t = (limits[Medals.SILVER] + limits[Medals.BRONZE]) / 2.0 + i
		ride.lap_timing.advance(lap * (i + 1), t)
		ride.stats.add(t, 86.0, lap)
	_fill_pulse(ride)
	ride.model.distance_m = lap * 20
	ride._finish_ride()
	ride._update_view()
	await wait_process_frames(4)
	assert_string_contains(ride.get_node("Hud/Message").text, "Medaillen: ", "20 Runden dabei")
	_assert_result_fits(ride, size, "Rundfahrt")


func test_training_result_with_pulse_lines_fits_in_1152x648() -> void:
	var size := Vector2i(1152, 648)
	var unit := Training.load_file(PYRAMID)
	var ride := await _ride_in(size, SaveGame.MODE_TRAINING, unit)
	var training: Training = ride.training
	while not training.finished():
		var phase := training.phase()
		training.advance((phase["cadence_min"] + phase["cadence_max"]) / 2.0, 1.0)
		ride.stats.add(1.0, 90.0, 0.0)
	_fill_pulse(ride)
	ride._finish_ride()
	ride._update_view()
	await wait_process_frames(4)
	assert_string_contains(ride.get_node("Hud/Message").text, "Je Phase:", "Phasenzeile dabei")
	_assert_result_fits(ride, size, "Training")


func test_arcade_result_with_pulse_lines_fits_in_1152x648() -> void:
	var size := Vector2i(1152, 648)
	var ride := await _ride_in(size, SaveGame.MODE_ARCADE)
	var run: ArcadeRun = ride.arcade_stage.run
	assert_not_null(run, "Arcade-Lauf")
	for name in ["Zone halten", "Durchbruch", "Takt-Tore", "Jagd", "Sammeln"]:
		for i in range(4):
			run.results.append({"id": name, "name": name, "succeeded": i % 2 == 0, "points": 100, "boss": false, "loot": {}})
	for name in ["Tramuntana", "Drac de na Coca", "Dimonis"]:
		run.results.append({"id": name, "name": name, "succeeded": true, "points": 500, "boss": true, "loot": {}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(4):
		run.found.append(Loot.roll(rng, 1.0))
	_fill_pulse(ride)
	ride.stats.add(900.0, 90.0, 5000.0)
	ride._finish_ride()
	ride._update_view()
	await wait_process_frames(4)
	assert_string_contains(ride.get_node("Hud/Message").text, "Beute:", "Beute dabei")
	assert_string_contains(ride.get_node("Hud/Message").text, "Bosse:", "Bosse dabei")
	_assert_result_fits(ride, size, "Arcade")
