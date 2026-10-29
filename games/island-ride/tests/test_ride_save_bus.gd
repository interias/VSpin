## BusClient und Fahrt speichern (Spec #84, docs/bus-protocol.md): `ride_saved` als eigenes Signal, `error` mit
## `invalid_ride` als `ride_rejected`, der Anmeldezustand aus `status.garmin` (auch ohne Block und bei Busverlust) und
## der Befehl `save_ride` bis zum Fake-Bus.
extends "res://tests/support/bus_test.gd"


func _status(login, at: float = 0.0) -> Dictionary:
	return FakeBusServer.status("connected", "sim", ["CADENCE"], at, {}, {} if login == null else {"login": login})


func test_garmin_login_follows_the_status_block() -> void:
	var bus := start_fake_bus([_status("not_logged_in", 0.0), _status("logged_in", 0.5), _status("unavailable", 1.0),
			_status(null, 1.5)])
	var client := connect_client(bus)
	assert_eq(client.garmin_login, "unknown", "vor dem ersten Status")
	watch_signals(client)
	var seen := []
	client.garmin_changed.connect(func(login): seen.append(login))
	assert_true(await run_until(func(): return seen.size() == 4, 4.0), "vier Wechsel")
	assert_eq(seen, ["not_logged_in", "logged_in", "unavailable", "unknown"],
			"ein Status ohne Block (ältere Bridge) heißt unbekannt")
	assert_eq(client.garmin_login, "unknown")


func test_garmin_login_is_ignored_when_invalid_and_unknown_without_a_bus() -> void:
	var bus := start_fake_bus([_status("logged_in", 0.0), _status("quatsch", 0.5)])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.garmin_login == "logged_in", 3.0))
	assert_true(await run_until(func(): return client.garmin_login == "unknown", 3.0), "unbekannter Wert → unbekannt")
	var again := start_fake_bus([_status("logged_in", 0.0)])
	var second := connect_client(again)
	assert_true(await run_until(func(): return second.garmin_login == "logged_in", 3.0))
	again.stop()
	assert_true(await run_until(func(): return not second.bus_connected, 3.0), "Bus weg")
	assert_eq(second.garmin_login, "unknown", "ohne Bus weiß das Spiel nichts über die Anmeldung")


func test_ride_saved_and_rejection_arrive_as_signals() -> void:
	var saved := {"v": 0, "type": "ride_saved", "ride_id": "a1b2c3", "fit_path": "C:\\sessions\\rides\\x.fit",
			"fit_error": null, "upload": {"state": "uploaded", "message": "Fahrt zu Garmin Connect hochgeladen."}}
	var bus := start_fake_bus([_status("logged_in", 0.0)])
	bus.replies["save_ride"] = saved
	bus.replies["bogus"] = {"v": 0, "type": "error", "reason": "invalid_ride", "detail": "ride_id fehlt"}
	var client := connect_client(bus)
	var received := []
	var rejected := []
	client.ride_saved.connect(func(message): received.append(message))
	client.ride_rejected.connect(func(detail): rejected.append(detail))
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	assert_eq(client.send_message({"type": "save_ride", "ride_id": "a1b2c3"}), OK)
	assert_true(await run_until(func(): return received.size() == 1, 3.0), "ride_saved weitergereicht")
	assert_eq(received[0]["ride_id"], "a1b2c3")
	assert_eq(received[0]["upload"]["state"], "uploaded")
	assert_eq(received[0]["fit_path"], "C:\\sessions\\rides\\x.fit")
	assert_true(rejected.is_empty())
	assert_eq(client.send_message({"type": "bogus"}), OK)
	assert_true(await run_until(func(): return rejected.size() == 1, 3.0), "invalid_ride weitergereicht")
	assert_eq(rejected[0], "ride_id fehlt")
	assert_eq(received.size(), 1, "ein Fehler ist keine Antwort")


func test_save_ride_reaches_the_bus_as_json_with_the_protocol_version() -> void:
	var bus := start_fake_bus([_status("logged_in", 0.0)])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	var trace := RideTrace.new("a1b2c3")
	trace.sample(123456, 0.0, true)
	trace.sample(124456, 8.1, true)
	trace.lap_end(124456)
	trace.finish(125000, 12.0)
	assert_eq(client.send_message(trace.save_message(true)), OK)
	await run_until(func(): return not bus.received_of_type("save_ride").is_empty(), 3.0)
	var message: Dictionary = bus.received_of_type("save_ride")[0]["message"]
	assert_eq(message["v"], 0.0)
	assert_eq(message["ride_id"], "a1b2c3")
	assert_eq(message["start_t_ms"], 123456.0)
	assert_eq(message["end_t_ms"], 125000.0)
	assert_eq(message["lap_end_t_ms"], [124456.0])
	assert_eq(message["distance"], [[123456.0, 0.0], [124456.0, 8.1], [125000.0, 12.0]])
	assert_eq(message["upload"], true)
	assert_eq(client.send_message({"type": "save_ride"}), OK)
	client.close()
	assert_eq(client.send_message(trace.save_message(true)), ERR_UNAVAILABLE, "ohne Bus geht nichts raus")
