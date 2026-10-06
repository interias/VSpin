## Spielzustände gegen den Fake-Bus: Verbindungsverlust pausiert (keine Kadenz 0), Rückkehr fährt
## automatisch weiter, Bridge fehlt → Hinweis und neuer Versuch, Pause/Beenden per Taste.
extends "res://tests/support/bus_test.gd"

const FLAT_M := 20.0
const RIDING := "riding"
const PAUSED_MANUAL := "paused_manual"
const PAUSED_CONNECTION := "paused_connection"


func _message(ride: Node) -> String:
	var label: Label = ride.get_node("Hud/Message")
	return label.text if label.visible else ""


func test_rides_once_connected_with_data() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.2, 3.0)), FLAT_M)
	assert_eq(ride.state, PAUSED_CONNECTION, "vor der ersten Verbindung pausiert")
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0), "fährt los, sobald Daten kommen")
	assert_eq(_message(ride), "", "beim Fahren kein Hinweis")


func test_stale_pauses_and_connected_resumes() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 1.5) \
			+ [FakeBusServer.status("stale", "sim", ["CADENCE"], 1.6)] \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 3.5)] \
			+ FakeBusServer.steady_cadence(90.0, 3.6, 6.0)
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	assert_true(await run_until(func(): return ride.state == PAUSED_CONNECTION, 3.0), "stale → Pause")
	assert_string_contains(_message(ride), "Verbindung verloren")
	var speed: float = ride.model.speed_kmh()
	var distance: float = ride.model.distance_m
	assert_gt(speed, 5.0)
	await run_for(1.0)
	assert_eq(ride.model.distance_m, distance, "steht während der Pause")
	assert_eq(ride.model.speed_kmh(), speed, "Abbruch ist keine Kadenz 0 (ADR-0004): kein Ausrollen")
	assert_eq(ride.bus.cadence, 90.0)
	assert_true(await run_until(func(): return ride.state == RIDING, 4.0), "connected + Daten → fährt weiter")
	await run_for(0.5)
	assert_gt(ride.model.distance_m, distance, "fährt wieder")
	assert_eq(_message(ride), "")


func test_waits_for_data_after_connected_again() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.0, 1.0) \
			+ [FakeBusServer.status("disconnected", "sim", ["CADENCE"], 1.2)] \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 1.6)] \
			+ [FakeBusServer.telemetry(80.0, 3.0)]
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	assert_true(await run_until(func(): return ride.state == PAUSED_CONNECTION, 3.0), "disconnected → Pause")
	assert_eq(ride.bus.status, "disconnected")
	assert_string_contains(_message(ride), "Verbindung verloren")
	assert_true(await run_until(func(): return ride.bus.status == "connected", 3.0))
	await run_for(0.5)
	assert_eq(ride.state, PAUSED_CONNECTION, "connected allein reicht nicht – erst wenn Daten kommen")
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))


func test_bus_drop_pauses_and_reconnect_resumes() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 1.5) \
			+ [FakeBusServer.close_at(1.5)]
	var bus := start_fake_bus(steps)
	var config := config_for(bus)
	config.bus_reconnect_s = 1.0
	var ride := spawn_ride(bus, FLAT_M, config)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	assert_true(await run_until(func(): return not ride.bus.bus_connected, 3.0), "Bus bricht ab")
	assert_eq(ride.state, PAUSED_CONNECTION)
	assert_string_contains(_message(ride), "Verbindung verloren")
	assert_string_contains(_message(ride), "vspin-bridge --source sim")
	var distance: float = ride.model.distance_m
	assert_true(await run_until(func(): return bus.connections_opened >= 2 and ride.state == RIDING, 4.0),
			"Drehbuch spielt nach Reconnect von vorn → fährt weiter")
	await run_for(0.3)
	assert_gt(ride.model.distance_m, distance)


func test_bridge_not_running_shows_hint_and_connects_later() -> void:
	var bus := FakeBusServer.new([FakeBusServer.status()] + FakeBusServer.steady_cadence(70.0, 0.1, 3.0))
	bus.port = FakeBusServer.DEFAULT_PORT + 51
	var ride := spawn_ride(bus, FLAT_M)
	await run_for(0.6)
	assert_eq(ride.state, PAUSED_CONNECTION)
	assert_string_contains(_message(ride), "Bridge nicht erreichbar")
	assert_string_contains(_message(ride), "vspin-bridge --source sim")
	assert_false(_message(ride).contains("Verbindung verloren"), "noch nie verbunden → nichts verloren")
	assert_eq(ride.model.distance_m, FLAT_M)
	assert_eq(bus.start(bus.port), OK)
	_buses.append(bus)
	assert_true(await run_until(func(): return ride.state == RIDING, 5.0), "verbindet, sobald die Bridge läuft")


func test_pause_key_toggles_manual_pause() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 6.0)), FLAT_M)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	await press_key(KEY_P)
	assert_eq(ride.state, PAUSED_MANUAL, "P pausiert")
	assert_string_contains(_message(ride), "Pause")
	var distance: float = ride.model.distance_m
	await run_for(0.5)
	assert_eq(ride.model.distance_m, distance, "steht während der Pause")
	await press_key(KEY_SPACE)
	assert_eq(ride.state, RIDING, "Leertaste setzt fort")
	await run_for(0.3)
	assert_gt(ride.model.distance_m, distance)


func test_manual_pause_survives_connection_loss() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 1.0) \
			+ [FakeBusServer.status("stale", "sim", ["CADENCE"], 1.2)] \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 2.0)] \
			+ FakeBusServer.steady_cadence(90.0, 2.1, 5.0)
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	await press_key(KEY_P)
	assert_true(await run_until(func(): return ride.state == PAUSED_CONNECTION, 3.0), "Verbindungspause hat Vorrang")
	assert_string_contains(_message(ride), "manuell pausiert")
	var back := func(): return ride.bus.status == "connected" and ride.state != PAUSED_CONNECTION
	assert_true(await run_until(back, 3.0))
	assert_eq(ride.state, PAUSED_MANUAL, "kein automatisches Weiterfahren aus manueller Pause")


func test_escape_requests_quit() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]), FLAT_M)
	watch_signals(ride)
	await press_key(KEY_ESCAPE)
	assert_signal_emitted(ride, "quit_requested")
