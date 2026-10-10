## Puls im Bus-Client gegen den Fake-Bus (Spec #64, P7): Zustand, Gerät und Wert, ältere Bridge ohne Pulsblock.
extends "res://tests/support/bus_test.gd"

const STRAP := {"address": "F1:2A:33:44:55:66", "name": "HRM 600", "role": "strap"}
const WATCH := {"address": "C8:11:22:33:44:55", "name": "Forerunner 970", "role": "watch"}


func test_heart_rate_state_and_device_arrive() -> void:
	var block := FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device())
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, block)])
	var client := connect_client(bus)
	assert_eq(client.heart_rate_state, "off", "vor der ersten Nachricht")
	watch_signals(client)
	assert_true(await run_until(func(): return client.heart_rate_state == "connected", 3.0))
	assert_eq(client.heart_rate_device, STRAP)
	assert_signal_emitted_with_parameters(client, "heart_rate_changed", ["connected"])


func test_heart_rate_follows_status_changes() -> void:
	var strap := FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device())
	var watch := FakeBusServer.heart_rate_block("stale", FakeBusServer.heart_rate_device(
			"C8:11:22:33:44:55", "Forerunner 970", "watch"))
	var lost := FakeBusServer.heart_rate_block("disconnected")
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, strap),
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.2, watch),
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.4, lost),
	])
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return client.heart_rate_state == "disconnected", 3.0))
	assert_signal_emitted_with_parameters(client, "heart_rate_changed", ["connected"], 0)
	assert_signal_emitted_with_parameters(client, "heart_rate_changed", ["stale"], 1)
	assert_signal_emitted_with_parameters(client, "heart_rate_changed", ["disconnected"], 2)
	assert_eq(client.heart_rate_device, {}, "ohne Verbindung kein Gerät")


func test_device_change_without_state_change_is_signalled() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0,
				FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device())),
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.2,
				FakeBusServer.heart_rate_block("connected", FakeBusServer.heart_rate_device(
						"C8:11:22:33:44:55", "Forerunner 970", "watch"))),
	])
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return client.heart_rate_device.get("role") == "watch", 3.0))
	assert_signal_emit_count(client, "heart_rate_changed", 2, "Wechsel von Gurt zu Uhr")
	assert_eq(client.heart_rate_state, "connected")


func test_heart_rate_value_arrives_and_null_is_no_value() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 62}),
		FakeBusServer.telemetry(80.0, 0.5, {"heart_rate": null}),
	])
	var client := connect_client(bus)
	assert_false(client.has_heart_rate())
	assert_true(await run_until(func(): return client.has_heart_rate(), 3.0))
	assert_eq(client.heart_rate_bpm, 62.0)
	assert_true(await run_until(func(): return not client.has_heart_rate(), 3.0), "null = kein Wert")
	assert_true(is_nan(client.heart_rate_bpm))


func test_heart_rate_value_without_device_comes_from_the_wheel() -> void:
	# Kein Pulsgerät (`off`), aber der Simulator liefert Puls.
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, FakeBusServer.heart_rate_block("off")),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 118}),
	])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.has_heart_rate(), 3.0))
	assert_eq(client.heart_rate_state, "off")
	assert_eq(client.heart_rate_bpm, 118.0)


func test_old_bridge_without_heart_rate_block_is_off() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.0, 0.5,
			0.25, {"heart_rate": null}))
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.cadence == 80.0, 3.0))
	assert_eq(client.heart_rate_state, "off")
	assert_eq(client.heart_rate_device, {})
	assert_false(client.has_heart_rate())
	assert_eq(client.status, "connected", "Rad unbeeinflusst")


func test_malformed_heart_rate_block_is_off() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {"state": "kaputt"})])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.status == "connected", 3.0))
	assert_eq(client.heart_rate_state, "off")


func test_heart_rate_value_is_dropped_when_telemetry_stops() -> void:
	var device := FakeBusServer.heart_rate_device()
	var bus := start_fake_bus([
		FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, FakeBusServer.heart_rate_block("connected", device)),
		FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 70}),
		FakeBusServer.status("stale", "sim", ["CADENCE"], 0.4, FakeBusServer.heart_rate_block("connected", device)),
		FakeBusServer.close_at(2.0),
	])
	var client := connect_client(bus, 5.0)
	assert_true(await run_until(func(): return client.has_heart_rate(), 3.0))
	assert_true(await run_until(func(): return client.status == "stale", 3.0))
	assert_false(client.has_heart_rate(), "Quelle stale: kein alter Puls")
	assert_eq(client.cadence, 80.0, "die Kadenz bleibt wie bisher stehen")
	assert_true(await run_until(func(): return not client.bus_connected, 4.0))
	assert_eq(client.heart_rate_state, "off", "ohne Bus unbekannt")
	assert_eq(client.heart_rate_device, {})


func test_silence_drops_the_heart_rate_value() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + [FakeBusServer.telemetry(80.0, 0.1, {"heart_rate": 70})])
	var client := connect_client(bus)
	client.silence_timeout_s = 0.6
	assert_true(await run_until(func(): return client.has_heart_rate(), 3.0))
	assert_true(await run_until(func(): return client.silent, 3.0))
	assert_false(client.has_heart_rate())
