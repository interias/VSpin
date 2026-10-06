## Bus-Client gegen den Fake-Bus: verbinden, parsen, reconnecten, senden.
extends "res://tests/support/bus_test.gd"


func test_parses_status_and_telemetry() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"]),
		FakeBusServer.telemetry(72.5, 0.1),
	])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.cadence == 72.5, 3.0), "Kadenz empfangen")
	assert_true(client.bus_connected)
	assert_eq(client.status, "connected")
	assert_eq(client.source, "sim")
	assert_eq(client.capabilities, PackedStringArray(["CADENCE"]))
	assert_true(client.has_capability("CADENCE"))
	assert_false(client.has_capability("RESISTANCE_CONTROL"))
	assert_eq(client.last_telemetry_t_ms, 100)


func test_follows_status_changes() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status("disconnected"),
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.2),
		FakeBusServer.status("stale", "sim", ["CADENCE"], 0.4),
	])
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return client.status == "stale", 3.0))
	assert_signal_emitted_with_parameters(client, "status_changed", ["connected"], 0)
	assert_signal_emitted_with_parameters(client, "status_changed", ["stale"], 1)


func test_telemetry_without_cadence_keeps_last_value() -> void:
	var gap := FakeBusServer.telemetry(0.0, 0.3)
	gap["send"]["cadence"] = null
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.telemetry(85.0, 0.1), gap])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.last_telemetry_t_ms == 300, 3.0))
	assert_eq(client.cadence, 85.0)


func test_ignores_unknown_messages() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.telemetry(60.0, 0.1),
		{"at": 0.2, "send": {"v": 0, "type": "ack", "for": "set_grade", "ok": false, "reason": "not_supported"}},
		{"at": 0.2, "send": {"v": 99, "type": "telemetry", "cadence": 150.0}},
		{"at": 0.2, "send": {"v": 99, "type": "status", "state": "disconnected"}},
		FakeBusServer.status("stale", "sim", ["CADENCE"], 0.3),  # Synchronisationspunkt: danach ist alles verarbeitet
	])
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return client.status == "stale", 3.0))
	assert_eq(client.cadence, 60.0, "Telemetrie mit v≠0 verworfen")
	assert_signal_emit_count(client, "status_changed", 2, "nur connected → stale; status mit v≠0 verworfen")


func test_status_with_null_fields_does_not_break_client() -> void:
	var broken := FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0)
	broken["send"]["source"] = null
	broken["send"]["capabilities"] = null
	var bus := start_fake_bus([broken, FakeBusServer.telemetry(65.0, 0.1)])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.cadence == 65.0, 3.0), "Telemetrie läuft weiter")
	assert_eq(client.status, "connected")
	assert_eq(client.source, "")
	assert_eq(client.capabilities, PackedStringArray())


func test_reconnects_after_bus_closes() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.telemetry(70.0, 0.1),
		FakeBusServer.close_at(0.4),
	])
	var client := connect_client(bus, 0.2)
	watch_signals(client)
	assert_true(await run_until(func(): return bus.connections_opened >= 2, 5.0), "zweite Verbindung")
	assert_signal_emitted_with_parameters(client, "bus_connection_changed", [false], 1)
	assert_eq(client.cadence, 70.0, "Abbruch ist keine Kadenz 0 (ADR-0004)")
	assert_true(await run_until(func(): return client.bus_connected and client.status == "connected", 3.0))


func test_connects_when_bus_comes_up_later() -> void:
	var bus := FakeBusServer.new([FakeBusServer.status(), FakeBusServer.telemetry(55.0, 0.1)])
	var port := FakeBusServer.DEFAULT_PORT + 50
	bus.port = port
	var client := connect_client(bus, 0.2)
	await run_for(0.5)
	assert_false(client.bus_connected)
	assert_eq(client.status, "disconnected")
	assert_eq(bus.start(port), OK)
	_buses.append(bus)
	assert_true(await run_until(func(): return client.cadence == 55.0, 5.0), "verbindet nach Bus-Start")


func test_send_message_reaches_bus() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var client := connect_client(bus)
	assert_eq(client.send_message({"type": "hello"}), ERR_UNAVAILABLE, "ohne Verbindung kein Senden")
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	assert_eq(client.send_message({"type": "set_grade", "grade": 0.05}), OK)
	assert_true(await run_until(func(): return bus.received.size() == 1, 3.0))
	assert_eq(bus.received[0], {"v": 0.0, "type": "set_grade", "grade": 0.05})


func test_script_from_json_file() -> void:
	var bus := start_fake_bus(FakeBusServer.load_script("res://tests/fixtures/cadence_drop.json"))
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.cadence == 90.0, 3.0))
	assert_true(await run_until(func(): return client.cadence == 40.0, 3.0))
