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


func test_silent_bus_counts_as_stale_until_next_message() -> void:
	# Bridge hängt bei offenem WebSocket: nach 0,5 s kommt nichts mehr – kein `stale` von der Bridge.
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.0, 0.5)
			+ [FakeBusServer.telemetry(82.0, 2.5)])
	var client := connect_client(bus)
	client.silence_timeout_s = 0.8
	assert_true(await run_until(func(): return client.cadence == 80.0, 3.0))
	assert_true(await run_until(func(): return client.status == "stale", 2.0), "Schweigen → wie stale")
	assert_true(client.silent)
	assert_true(client.bus_connected, "WebSocket bleibt offen")
	assert_eq(client.cadence, 80.0, "Schweigen ist keine Kadenz 0 (ADR-0004)")
	assert_true(await run_until(func(): return client.cadence == 82.0, 3.0))
	assert_eq(client.status, "connected", "neue Nachricht → wieder connected")
	assert_false(client.silent)


func test_telemetry_without_cadence_keeps_last_value() -> void:
	var gap := FakeBusServer.telemetry(0.0, 0.3)
	gap["send"]["cadence"] = null
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.telemetry(85.0, 0.1), gap])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.last_telemetry_t_ms == 300, 3.0))
	assert_eq(client.cadence, 85.0)


func test_reads_unsmoothed_cadence_next_to_smoothed() -> void:
	# Bridge ab #45: `cadence_raw` (ungeglättet) neben `cadence`; `null` behält den letzten Wert.
	var gap := FakeBusServer.telemetry(40.0, 0.3, {"cadence_raw": null})
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.telemetry(80.0, 0.1, {"cadence_raw": 80.0}),
		FakeBusServer.telemetry(52.3, 0.2, {"cadence_raw": 0.0}),
		gap,
	])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.last_telemetry_t_ms == 200, 3.0))
	assert_eq(client.cadence_raw, 0.0, "ungeglättet: Treten hört sofort auf")
	assert_eq(client.cadence, 52.3, "geglättet bleibt getrennt")
	assert_true(await run_until(func(): return client.last_telemetry_t_ms == 300, 3.0))
	assert_eq(client.cadence_raw, 0.0, "null behält den letzten Wert")
	assert_eq(client.cadence, 40.0)


func test_older_bridge_without_unsmoothed_cadence_falls_back_to_cadence() -> void:
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.telemetry(77.0, 0.1)])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.cadence == 77.0, 3.0))
	assert_eq(client.cadence_raw, 77.0)


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
	var port := TestIsolation.first_test_port() + 50
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


func test_reconnects_when_connecting_hangs() -> void:
	# Ein TCP-Server, der nie den WebSocket-Handshake beantwortet: der Client hängt in CONNECTING.
	var server := TCPServer.new()
	var port := TestIsolation.first_test_port() + 52
	assert_eq(server.listen(port, FakeBusServer.HOST), OK)
	var held: Array = []
	var client := connect_client_to("ws://%s:%d" % [FakeBusServer.HOST, port], 0.1, 0.4)
	var start := Time.get_ticks_msec()
	while held.size() < 3 and Time.get_ticks_msec() - start < 4000:
		await run_for(0.05)
		while server.is_connection_available():
			held.append(server.take_connection())
	server.stop()
	assert_gte(held.size(), 3, "nach Timeout neuer Verbindungsversuch")
	assert_false(client.bus_connected)
	assert_eq(client.status, "disconnected")
