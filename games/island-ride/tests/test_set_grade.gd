## `set_grade` gegen den Fake-Bus: das Spiel meldet die virtuelle Steigung (ADR-0007) – Erstmeldung,
## Schwelle 0,5 Prozentpunkte, höchstens 2/s, nicht in der Verbindungspause, `ack` im HUD.
extends "res://tests/support/bus_test.gd"

const FLAT_M := 20.0
const CLIMB_M := 200.0
## Kurz vor dem Anstieg (beginnt bei 150 m); die gemessene Steigung steigt auf 148–152 m von 0 auf 6 %.
const BEFORE_CLIMB_M := 140.0


func _steady(cadence: float, until_s: float = 10.0) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, until_s)


func _grades(bus: FakeBusServer) -> Array:
	return bus.received_of_type("set_grade").map(func(entry): return entry["message"]["grade"])


func _hud(ride: Node) -> String:
	return ride.get_node("Hud/Label").text


func test_sends_initial_grade_after_connect() -> void:
	var bus := start_fake_bus(_steady(80.0))
	spawn_ride(bus, CLIMB_M)
	assert_true(await run_until(func(): return bus.received_of_type("set_grade").size() >= 1, 3.0))
	var message: Dictionary = bus.received_of_type("set_grade")[0]["message"]
	assert_eq(message["v"], 0.0)
	assert_almost_eq(message["grade"], 0.06, 0.001, "Steigung an der Fahrerposition als Anteil")
	await run_for(1.0)
	assert_eq(bus.received_of_type("set_grade").size(), 1, "gleichbleibende Steigung → keine weitere Meldung")


func test_grade_changes_are_sent_with_threshold_and_throttle() -> void:
	var bus := start_fake_bus(_steady(90.0))
	var config := config_for(bus)
	config.k_kmh_per_rpm = 0.12  # ≈ 3 m/s: die Steigung ändert sich über ~1,3 s schneller, als gemeldet werden darf
	config.inertia_s = 0.0
	var ride := spawn_ride(bus, BEFORE_CLIMB_M, config)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	var start_ms := Time.get_ticks_msec()
	var reached := func(): return not _grades(bus).is_empty() and _grades(bus)[-1] > 0.059
	assert_true(await run_until(reached, 8.0), "Anstieg erreicht und gemeldet")
	var elapsed_s := (Time.get_ticks_msec() - start_ms) / 1000.0
	var sent := bus.received_of_type("set_grade")
	var grades := _grades(bus)
	assert_eq(grades[0], 0.0, "Erstmeldung flach")
	assert_gte(grades.size(), 3, "Zwischenwerte im Übergang gemeldet")
	for i in range(1, sent.size()):
		assert_gte(absf(grades[i] - grades[i - 1]), 0.005 - 1e-9, "Schwelle 0,5 Prozentpunkte (Meldung %d)" % i)
		assert_gte(sent[i]["ms"] - sent[i - 1]["ms"], 450, "höchstens 2 pro Sekunde (Meldung %d)" % i)
	assert_lte(sent.size(), int(elapsed_s * 2.0) + 2, "insgesamt höchstens 2/s")
	assert_lt(sent.size(), 12, "gedrosselt: ungedrosselt wären es ~12 Meldungen im Übergang")


func test_no_set_grade_while_connection_paused_and_resend_after() -> void:
	var steps := _steady(80.0, 1.0) + [FakeBusServer.status("stale", "sim", ["CADENCE"], 1.2)] \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 3.0)] \
			+ FakeBusServer.steady_cadence(80.0, 3.1, 6.0)
	var bus := start_fake_bus(steps)
	var ride := spawn_ride(bus, FLAT_M)
	assert_true(await run_until(func(): return bus.received_of_type("set_grade").size() == 1, 3.0))
	assert_true(await run_until(func(): return ride.state == "paused_connection", 3.0))
	await run_for(1.0)
	assert_eq(bus.received_of_type("set_grade").size(), 1, "kein set_grade in der Verbindungspause")
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	assert_true(await run_until(func(): return bus.received_of_type("set_grade").size() == 2, 2.0),
			"nach der Rückkehr gleiche Steigung erneut gemeldet")
	assert_eq(_grades(bus)[1], 0.0)


func test_resends_after_bus_reconnect() -> void:
	var bus := start_fake_bus(_steady(80.0, 1.0) + [FakeBusServer.close_at(1.0)])
	spawn_ride(bus, CLIMB_M)
	assert_true(await run_until(func(): return bus.connections_opened >= 2 and _grades(bus).size() >= 2, 5.0),
			"neue Verbindung → Steigung erneut gemeldet")
	assert_almost_eq(_grades(bus)[1], 0.06, 0.001)


func test_ack_not_supported_shows_hint() -> void:
	var bus := start_fake_bus(_steady(80.0))
	bus.replies["set_grade"] = FakeBusServer.ack("set_grade", false, "not_supported")
	var ride := spawn_ride(bus, FLAT_M)
	var hint: Label = ride.get_node("Hud/Hint")
	assert_eq(hint.text, "")
	assert_true(await run_until(func(): return hint.text == "Widerstand: nicht unterstützt", 3.0))


func test_ack_ok_shows_no_hint() -> void:
	var bus := start_fake_bus(_steady(80.0))
	bus.replies["set_grade"] = FakeBusServer.ack("set_grade", true)
	var ride := spawn_ride(bus, FLAT_M)
	assert_true(await run_until(func(): return bus.received_of_type("set_grade").size() >= 1, 3.0))
	await run_for(0.3)
	assert_eq(ride.get_node("Hud/Hint").text, "")


func test_hud_shows_grade() -> void:
	var bus := start_fake_bus(_steady(80.0))
	var up := spawn_ride(bus, CLIMB_M)
	var flat := spawn_ride(bus, FLAT_M)
	await run_for(0.5)
	assert_string_contains(_hud(up), "Steigung: +6.0 %")
	assert_string_contains(_hud(flat), "Steigung: 0.0 %")
