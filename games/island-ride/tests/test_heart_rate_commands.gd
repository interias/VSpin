## Pulsbefehle des Bus-Clients gegen den Fake-Bus (Spec #64, P7): Befehle als JSON, Antworten, Suchergebnisse und das
## Schicken der gemerkten Geräte nach jedem (Neu-)Verbinden. (Eigene Datei: ein Skript braucht je Test einen Fake-Bus-Port.)
extends "res://tests/support/bus_test.gd"

const STRAP := {"address": "F1:2A:33:44:55:66", "name": "HRM 600", "role": "strap"}
const WATCH := {"address": "C8:11:22:33:44:55", "name": "Forerunner 970", "role": "watch"}


func test_commands_go_out_as_json() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var client := connect_client(bus)
	assert_eq(client.start_heart_rate_search(), ERR_UNAVAILABLE, "ohne Bus kein Senden")
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	assert_eq(client.set_heart_rate_devices([STRAP, WATCH]), OK)
	assert_eq(client.start_heart_rate_search(30.0), OK)
	assert_eq(client.start_heart_rate_search(), OK)
	assert_eq(client.stop_heart_rate_search(), OK)
	assert_true(await run_until(func(): return bus.received.size() == 4, 3.0))
	assert_eq(bus.received[0], {"v": 0.0, "type": "set_heart_rate_devices", "devices": [STRAP, WATCH]})
	assert_eq(bus.received[1], {"v": 0.0, "type": "start_heart_rate_search", "duration_s": 30.0})
	assert_eq(bus.received[2], {"v": 0.0, "type": "start_heart_rate_search"}, "ohne Dauer: Standard der Bridge")
	assert_eq(bus.received[3], {"v": 0.0, "type": "stop_heart_rate_search"})


func test_acks_of_the_new_commands_arrive() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	bus.replies["start_heart_rate_search"] = FakeBusServer.ack("start_heart_rate_search", true)
	bus.replies["set_heart_rate_devices"] = FakeBusServer.ack("set_heart_rate_devices", false, "invalid_devices")
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	client.set_heart_rate_devices([STRAP])
	client.start_heart_rate_search(10.0)
	assert_true(await run_until(func(): return get_signal_emit_count(client, "ack_received") == 2, 3.0))
	assert_eq(get_signal_parameters(client, "ack_received", 0)[0]["reason"], "invalid_devices")
	assert_eq(get_signal_parameters(client, "ack_received", 1)[0]["for"], "start_heart_rate_search")


func test_search_results_and_end_arrive_as_signals() -> void:
	var bus := start_fake_bus([
		FakeBusServer.status(),
		FakeBusServer.heart_rate_found("F1:2A:33:44:55:66", "HRM 600", -58, 0.1),
		FakeBusServer.heart_rate_found("AA:BB:CC:DD:EE:FF", null, -80, 0.2),
		FakeBusServer.heart_rate_search_ended("timeout", 0.3),
		FakeBusServer.heart_rate_search_ended("taken_over", 0.4),
	])
	var client := connect_client(bus)
	watch_signals(client)
	assert_true(await run_until(func(): return get_signal_emit_count(client, "heart_rate_search_ended") == 2, 3.0))
	assert_signal_emit_count(client, "heart_rate_found", 2)
	assert_eq(get_signal_parameters(client, "heart_rate_found", 0), ["F1:2A:33:44:55:66", "HRM 600", -58])
	assert_eq(get_signal_parameters(client, "heart_rate_found", 1), ["AA:BB:CC:DD:EE:FF", "", -80], "ohne Namen")
	assert_eq(get_signal_parameters(client, "heart_rate_search_ended", 0), ["timeout"])
	assert_eq(get_signal_parameters(client, "heart_rate_search_ended", 1), ["taken_over"])


func test_devices_are_sent_after_every_connect() -> void:
	var bus := start_fake_bus([FakeBusServer.status(), FakeBusServer.close_at(0.6)])
	var client := connect_client(bus)
	assert_eq(client.set_heart_rate_devices([STRAP, WATCH]), ERR_UNAVAILABLE, "noch kein Bus: wird gemerkt")
	assert_true(await run_until(func(): return bus.received_of_type("set_heart_rate_devices").size() >= 2, 5.0),
			"nach dem Verbinden und nach dem Neuverbinden")
	assert_eq(bus.connections_opened, 2)
	for sent in bus.received_of_type("set_heart_rate_devices"):
		assert_eq(sent["message"]["devices"], [STRAP, WATCH])


func test_empty_list_is_sent_too() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var client := connect_client(bus)
	client.set_heart_rate_devices([])
	assert_true(await run_until(func(): return bus.received.size() == 1, 3.0))
	assert_eq(bus.received[0], {"v": 0.0, "type": "set_heart_rate_devices", "devices": []})


func test_nothing_is_sent_until_the_game_sets_devices() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.bus_connected, 3.0))
	await run_for(0.3)
	assert_eq(bus.received.size(), 0)


func test_changed_devices_go_out_at_once() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var client := connect_client(bus)
	client.set_heart_rate_devices([STRAP])
	assert_true(await run_until(func(): return bus.received.size() == 1, 3.0))
	client.set_heart_rate_devices([WATCH])
	assert_true(await run_until(func(): return bus.received.size() == 2, 3.0))
	assert_eq(bus.received[1]["devices"], [WATCH])
