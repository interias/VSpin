## Segmente und Medaillen (#33) gegen den Fake-Bus auf der Insel: Torbogen je Segment, Live-Zeit im HUD, Ergebnis beim
## Verlassen mit Zeit und Medaille, Segment-Bestzeit im Spielstand (übersteht einen Neustart), und eine konstante Runde
## mit 85 rpm ergibt Silber für Runde und alle Segmente im Fahrtergebnis.
extends "res://tests/support/bus_test.gd"

const SAVE_PATH := "user://test_segments_savegame.json"
## Schnelles Rad für den Durchstich: 120 rpm · 10 km/h je rpm ≈ 330 m/s flach – der Dorfsprint in etwa einer Sekunde.
const FAST_K := 10.0
## Kurz vor dem Dorfsprint (5700–6010 m).
const BEFORE_VILLAGE_M := 5600.0
const DT := 1.0 / 60.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) auf der Insel am Fake-Bus, mit Test-Spielstand; schnelles Rad ohne
## Trägheit, Start kurz vor dem Dorfsprint.
func _spawn_game(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	game.start_distance_m = BEFORE_VILLAGE_M
	add_child_autofree(game)
	return game


## Im Startmenü „Fahren → Rundfahrt → Losfahren“ und warten, bis gefahren wird.
func _start(game: Node) -> void:
	await run_for(0.2)
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Rundfahrt fährt los")


func test_a_gate_marks_the_start_of_every_segment() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	await run_for(0.1)
	var gates: Node3D = game.world.get_node("Segments")
	assert_eq(gates.get_child_count(), 3, "ein Torbogen je Segment")
	for segment in game.track.segments:
		var gate: Node3D = gates.get_node(NodePath(segment["id"]))
		assert_eq(gate.get_meta("segment_name"), segment["name"])
		assert_lt(gate.global_position.distance_to(game.track.to_global(game.track.position_at(segment["start_m"]))), 0.01,
				"%s: Bogen am Start des Segments" % segment["id"])
		for part in ["PfostenL", "PfostenR", "Banner"]:
			assert_not_null(gate.get_node_or_null(part), "%s: %s aus Grundkörpern" % [segment["id"], part])
		assert_eq((gate.get_node("Name") as Label3D).text, segment["name"], "Name auf dem Banner")


func test_segment_gives_time_and_medal_and_its_best_time_survives_restart() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 30.0))
	var game := _spawn_game(bus)
	await _start(game)
	assert_eq(game.save_game.segment_best_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "dorfsprint"), INF)
	assert_true(await run_until(func(): return game.hud.readout().contains("Dorfsprint: "), 3.0),
			"im Segment: Live-Zeit im HUD")
	assert_true(await run_until(func(): return not game.lap_timing.segments.results.is_empty(), 3.0),
			"Segment verlassen")
	var result: Dictionary = game.lap_timing.segments.results[0]
	assert_eq(result["id"], "dorfsprint")
	var expected: float = Medals.simulate_lap(game.track, game.config, 120.0)["dorfsprint"]
	assert_almost_eq(result["time_s"], expected, 0.05, "Zeit wie das Fahrmodell bei 120 rpm")
	var celebration: String = game.hud.celebration()
	assert_string_contains(celebration, "Dorfsprint  %s" % game.format_time(result["time_s"], true), "Ergebnis eingeblendet")
	assert_string_contains(celebration, "Gold", "120 rpm > 95 rpm: Gold")
	assert_string_contains(celebration, "neue Bestzeit!")
	await run_for(0.1)
	assert_false(game.hud.readout().contains("Dorfsprint"), "nach dem Segment keine Live-Zeit mehr")
	game.settings_menu.ride_end_requested.emit()  # „Fahrt beenden“ ohne volle Runde → Menü, Fahrt gespeichert
	assert_eq(game.state, "menu")
	# Neustart: eine neue Hauptszene liest denselben Spielstand.
	var restarted := _spawn_game(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(100.0, 0.0, 30.0)))
	await run_for(0.1)
	var saved: float = restarted.save_game.segment_best_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "dorfsprint")
	var ride: Dictionary = restarted.save_game.rides()[-1]
	assert_eq(ride["direction"], LapTiming.DIRECTION_CW, "Fahrteintrag mit Richtung")
	assert_true(ride["segment_times_s"].has("dorfsprint"), "Segmentzeit dieser Fahrt im Fahrteintrag (Nacharbeit #26)")
	assert_almost_eq(float(ride["segment_times_s"].get("dorfsprint", -1.0)), result["time_s"], 0.01,
			"Segmentzeit dieser Fahrt im Fahrteintrag (Nacharbeit #26)")
	assert_almost_eq(saved, result["time_s"], 0.001, "Segment-Bestzeit nach dem Neustart erhalten")
	assert_eq(restarted.save_game.best_medal(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "dorfsprint"), Medals.GOLD,
			"beste Medaille des Segments gespeichert")
	# Langsamer (100 rpm): Gold, aber keine neue Bestzeit; die gespeicherte bleibt.
	await _start(restarted)
	assert_true(await run_until(func(): return not restarted.lap_timing.segments.results.is_empty(), 4.0))
	assert_gt(restarted.lap_timing.segments.results[0]["time_s"], saved)
	assert_string_contains(restarted.hud.celebration(), "Gold")
	assert_false(restarted.hud.celebration().contains("neue Bestzeit"), "langsamer als gespeichert")
	restarted.settings_menu.ride_end_requested.emit()
	assert_almost_eq(SaveGame.load_file(SAVE_PATH).segment_best_s(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW,
			"dorfsprint"), saved, 0.001, "die schnellere Zeit bleibt")


func test_steady_85_rpm_lap_earns_silver_for_lap_and_segments_in_the_result() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(85.0, 0.0, 30.0))
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == 85.0, 3.0))
	# Eine ganze Runde Schritt für Schritt (DT) durch die Hauptszene – Spiel-Konfiguration, unabhängig von der Bildrate.
	ride.set_process(false)
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
	for i in range(200000):
		if ride.state == "finished":
			break
		ride._ride(DT)
	assert_eq(ride.state, "finished", "Ziel nach einer Runde")
	assert_eq(ride.lap_timing.segments.results.size(), 3, "alle drei Segmente gewertet")
	var message: String = ride.status_message()
	assert_string_contains(message, "Medaille: Silber", "85 rpm konstant: Runde Silber")
	var segments := []
	for result in ride.lap_timing.segments.results:
		segments.append("%s %s Silber" % [result["name"], ride.format_time(result["time_s"], true)])
	assert_string_contains(message, "Segmente: " + " · ".join(segments), "jedes Segment mit Zeit und Silber")
	for key in [Medals.LAP, "kuestenwelle", "bergwertung", "dorfsprint"]:
		assert_eq(ride.save_game.best_medal(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, key), Medals.SILVER,
				"%s: Silber im Spielstand" % key)


## Ergebnis einer Fahrt über 20 Runden mit gemischten Medaillen und drei Segmenten, gerendert in einem Fenster der
## Größe `size`: Hauptszene in einem SubViewport, Runden wie in view_probe in ganzen Schritten (Segmente anteilig),
## kurz vor dem Ziel noch die Einblendung „Neue Bestzeit!“. Liefert die Hauptszene im Zustand finished.
func _result_of_20_laps_in(bus: FakeBusServer, size: Vector2i) -> Node:
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
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 20)
	var limits: Dictionary = ride.medal_limits[Medals.LAP]
	var lap: float = ride.track.length_m()
	for i in range(20):
		var t: float = limits[Medals.GOLD] - 5.0 - i  # 12× Gold
		if i >= 12:
			t = (limits[Medals.GOLD] + limits[Medals.SILVER]) / 2.0 + i  # 5× Silber
		if i >= 17:
			t = (limits[Medals.SILVER] + limits[Medals.BRONZE]) / 2.0 + i  # 2× Bronze
		if i == 19:
			t = limits[Medals.BRONZE] + 60.0  # 1× ohne
		ride.lap_timing.advance(lap * (i + 1), t)
		ride.stats.add(t, 86.0, lap)
		if i == 0:
			ride.hud.celebrate("Neue Bestzeit!  %s" % ride.format_time(t, true))
	ride.model.distance_m = lap * 20
	ride._finish_ride()
	ride._update_view()
	await wait_process_frames(4)
	return ride


func test_result_of_20_laps_fits_between_the_panels() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1152, 648)]:
		var ride := await _result_of_20_laps_in(bus, size)
		assert_eq(ride.state, "finished")
		var label: Label = ride.get_node("Hud/Message")
		assert_true(label.is_visible_in_tree(), "%s: Ergebnis sichtbar" % size)
		assert_string_contains(label.text, "Medaillen: 12× Gold · 5× Silber · 2× Bronze · 1× ohne", "%s: gezählt" % size)
		for t in ride.lap_timing.lap_times:
			assert_string_contains(label.text, ride.format_time(t, true), "%s: alle Rundenzeiten" % size)
		assert_eq(ride.lap_timing.segments.results.size(), 60, "drei Segmente je Runde")
		assert_string_contains(label.text, "Segmente: Küstenwelle")
		assert_eq(ride.hud.celebration(), "", "%s: keine Einblendung hinter dem Ergebnis" % size)
		var message := label.get_global_rect()
		var hud: RideHud = ride.hud
		assert_true(hud.get_node("Layout").get_viewport_rect().encloses(message), "%s: im Fenster (%s)" % [size, message])
		# auch in niedrigen Fenstern zwischen den Panels (Nacharbeit #26: Leisten, kleinere Schrift)
		var panels := [hud.get_node("%Stats"), hud.get_node("%Bottom"), hud.get_node("%Minimap").get_parent()]
		for panel: Control in panels:
			if panel.is_visible_in_tree():
				assert_false(message.intersects(panel.get_global_rect()),
						"%s: Ergebnis %s frei von %s %s" % [size, message, panel.name, panel.get_global_rect()])
		assert_gte(label.get_theme_font_size("font_size"), RideHud.MIN_MESSAGE_FONT_PX, "%s: lesbar" % size)
