## Virtuelle Gänge (Spec #75, Story 8): Gangtabelle (Grenzen, neutral, effektive Steigung, Sperre), Tasten nur bei
## steuerbarem Trainer ohne offenes Menü oder Fenster, `set_grade` mit effektiver Steigung gegen den Fake-Bus,
## Grundlast bleibt 0, Ganganzeige im HUD. Spec #89: Grund im HUD für jeden Stand der Steuerung ohne Gänge, die Tasten
## wirken, sobald die Steuerung `active` wird.
extends "res://tests/support/bus_test.gd"

const CLIMB_M := 200.0  # Graybox: 6 % Steigung


func _steps(control: String) -> Array:
	return [FakeBusServer.status("connected", "ble", ["CADENCE", "RESISTANCE_CONTROL"], 0.0, {}, control)] \
			+ FakeBusServer.steady_cadence(80.0, 0.0, 30.0)


func _grades(bus: FakeBusServer) -> Array:
	return bus.received_of_type("set_grade").map(func(entry): return entry["message"]["grade"])


## Fahrt mit Trainer-Steuerung `control`, wartet auf die erste Steigungsmeldung.
func _ride(control: String = "active") -> Array:
	var bus := start_fake_bus(_steps(control))
	var ride := spawn_ride(bus, CLIMB_M)
	assert_true(await run_until(func(): return ride.state == "riding" and _grades(bus).size() >= 1, 3.0))
	return [bus, ride]


# --- Gangtabelle ---

func test_starts_neutral_with_zero_offset() -> void:
	var gears := Gears.new()
	assert_eq(gears.gear, 12)
	assert_eq(gears.offset(), 0.0)
	assert_eq(gears.effective_grade(0.06), 0.06)
	assert_eq(gears.text(), "12/24")


func test_shifting_moves_the_grade_by_the_step_and_higher_is_harder() -> void:
	var gears := Gears.new(24, 12, 0.5)
	assert_true(gears.shift_up())
	assert_almost_eq(gears.effective_grade(0.06), 0.065, 1e-9)
	assert_true(gears.shift_down())
	assert_true(gears.shift_down())
	assert_almost_eq(gears.effective_grade(0.06), 0.055, 1e-9)
	assert_almost_eq(gears.effective_grade(-0.02), -0.025, 1e-9, "auch bergab")


func test_gear_stops_at_both_ends() -> void:
	var gears := Gears.new(5, 3, 1.0)
	assert_true(gears.shift_up() and gears.shift_up())
	assert_false(gears.shift_up(), "oben bleibt der Gang stehen")
	assert_eq(gears.gear, 5)
	assert_almost_eq(gears.offset(), 0.02, 1e-9)
	for i in 4:
		gears.shift_down()
	assert_false(gears.shift_down(), "unten bleibt der Gang stehen")
	assert_eq(gears.gear, 1)
	assert_almost_eq(gears.offset(), -0.02, 1e-9)


func test_reset_returns_to_neutral() -> void:
	var gears := Gears.new()
	gears.shift_up()
	gears.reset()
	assert_eq(gears.gear, 12)


func test_locked_gears_do_not_shift() -> void:
	var gears := Gears.new()
	gears.locked = true
	assert_false(gears.shift_up())
	assert_false(gears.shift_down())
	assert_eq(gears.gear, 12)
	gears.locked = false
	assert_true(gears.shift_up())


func test_invalid_parameters_are_corrected() -> void:
	var gears := Gears.new(0, 99, -1.0)
	assert_eq(gears.count, 1)
	assert_eq(gears.neutral, 1)
	assert_eq(gears.step, 0.0)
	assert_false(gears.shift_up())


func test_config_defaults_and_missing_keys() -> void:
	var config := RideConfig.new()
	assert_eq([config.gears_count, config.gears_neutral, config.gears_step_pp], [24, 12, 0.5])
	var loaded := RideConfig.load_file("res://tests/fixtures/does_not_exist.cfg")
	assert_eq(loaded.gears_count, 24, "fehlende Datei → Standard")
	assert_eq(RideConfig.load_file().gears_count, 24, "config.cfg liefert die Standardwerte")


# --- Tasten und Steigung ---

func test_keys_shift_when_trainer_is_controllable_and_report_the_effective_grade() -> void:
	var ctx := await _ride()
	var bus: FakeBusServer = ctx[0]
	var ride = ctx[1]
	assert_almost_eq(_grades(bus)[0], 0.06, 0.001, "neutraler Gang: Steigung der Strecke")
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 13)
	assert_true(await run_until(func(): return _grades(bus).size() >= 2, 2.0), "ein Gangschritt erreicht die Meldeschwelle")
	assert_almost_eq(_grades(bus)[-1], 0.065, 0.001)
	await press_key(KEY_KP_SUBTRACT)
	await press_key(KEY_DOWN)
	assert_eq(ride.gears.gear, 11)
	assert_true(await run_until(func(): return absf(_grades(bus)[-1] - 0.055) < 0.001, 2.0))
	await press_key(KEY_KP_ADD)
	assert_eq(ride.gears.gear, 12)


func test_keys_do_nothing_without_controllable_trainer() -> void:
	for control in ["read_only", "lost", "none"]:
		var ctx := await _ride(control)
		var ride = ctx[1]
		await press_key(KEY_UP)
		assert_eq(ride.gears.gear, 12, "Steuerung %s: kein Schalten" % control)
		assert_false(ride.gears_active())
		ride.queue_free()
		await get_tree().process_frame


func test_keys_do_nothing_with_open_menu_settings_or_devices() -> void:
	var ctx := await _ride()
	var ride = ctx[1]
	ride.settings_menu.visible = true
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 12, "Einstellungen offen")
	ride.settings_menu.visible = false
	ride.open_devices()
	assert_true(ride.devices_menu.visible)
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 12, "Verbindungsfenster offen")
	ride.devices_menu.close()
	ride.state = "menu"
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 12, "Menü")


func test_keys_do_nothing_while_locked() -> void:
	var ctx := await _ride()
	var ride = ctx[1]
	ride.gears.locked = true
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 12)


func test_rest_load_stays_zero_in_a_high_gear() -> void:
	var ctx := await _ride()
	var bus: FakeBusServer = ctx[0]
	var ride = ctx[1]
	for i in 6:
		await press_key(KEY_UP)
	assert_true(await run_until(func(): return absf(_grades(bus)[-1] - 0.09) < 0.001, 3.0))
	var before := _grades(bus).size()
	await press_key(KEY_P)
	assert_true(await run_until(func(): return _grades(bus).size() == before + 1, 1.5))
	assert_eq(_grades(bus)[-1], 0.0, "Grundlast 0, nicht 0 + f(Gang)")
	assert_eq(ride.gears.gear, 18)


func test_new_ride_starts_in_neutral_gear() -> void:
	var ctx := await _ride()
	var ride = ctx[1]
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 13)
	ride.return_to_menu()
	ride.start_ride()
	assert_eq(ride.gears.gear, 12)


# --- HUD ---

func test_hud_shows_the_gear_only_with_controllable_trainer() -> void:
	var ctx := await _ride()
	var ride = ctx[1]
	var hud: RideHud = ride.get_node("Hud")
	await press_key(KEY_UP)
	assert_true(hud.get_node("%Gear").is_visible_in_tree())
	assert_string_contains(hud.readout(), "Gang: 13/24")
	var sim := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(80.0, 0.0, 10.0))
	var sim_ride := spawn_ride(sim, CLIMB_M)
	assert_true(await run_until(func(): return sim_ride.state == "riding", 3.0))
	await run_for(0.3)
	assert_false(sim_ride.get_node("Hud/Layout/Rows/Bottom/Box/Lap/Gear").is_visible_in_tree(), "Simulator: keine Anzeige")
	assert_false(sim_ride.get_node("Hud").readout().contains("Gang"))


# --- Gänge aus: Grund im HUD (Spec #89) ---

func test_hud_says_why_there_are_no_gears_for_every_control_state() -> void:
	var main := load("res://scenes/main.gd")
	var expected := {
		"none": main.GEARS_OFF_NONE,
		"requesting": main.GEARS_OFF_REQUESTING,
		"lost": main.RESISTANCE_CONTROL_LOST,
		"read_only": main.RESISTANCE_READ_ONLY,
		"not_supported": main.GEARS_OFF_NOT_SUPPORTED,
		"error": main.GEARS_OFF_ERROR,
	}
	for control in expected:
		var ctx := await _ride(control)
		var ride = ctx[1]
		var hint: Label = ride.get_node("Hud/Hint")
		assert_true(await run_until(func(): return hint.text == expected[control], 2.0),
				"Steuerung %s: Grund im HUD (%s)" % [control, hint.text])
		assert_string_starts_with(hint.text, "Gänge aus: ")
		assert_false(ride.get_node("Hud").readout().contains("Gang:"), "Steuerung %s: keine Ganganzeige" % control)
		ride.queue_free()
		await get_tree().process_frame
	assert_eq(expected.size(), 6, "alle Stände außer active")


func test_lost_and_error_point_to_reclaiming_control_in_the_connection_window() -> void:
	var main := load("res://scenes/main.gd")
	for text in [main.RESISTANCE_CONTROL_LOST, main.GEARS_OFF_ERROR]:
		assert_string_contains(text, "Steuerung zurückholen")
		assert_string_contains(text, "(V)")
	assert_string_contains(main.RESISTANCE_CONTROL_LOST, "von einer anderen App gesteuert")


func test_no_reason_while_vspin_controls_the_trainer_and_none_for_the_simulator() -> void:
	var ctx := await _ride()
	var ride = ctx[1]
	await run_for(0.3)
	assert_eq(ride.get_node("Hud/Hint").text, "", "VSpin steuert: kein Grund")
	var sim := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {}, "not_supported")]
			+ FakeBusServer.steady_cadence(80.0, 0.0, 10.0))
	var sim_ride := spawn_ride(sim, CLIMB_M)
	assert_true(await run_until(func(): return sim_ride.state == "riding", 3.0))
	await run_for(0.3)
	assert_eq(sim_ride.bus.trainer_control, "not_supported")
	assert_eq(sim_ride.get_node("Hud/Hint").text, "", "Simulator: nichts zu tun, kein Grund")


func test_keys_shift_as_soon_as_control_becomes_active() -> void:
	# Tastatur bleibt der Ersatz (US 6): dieselben Tasten wirken, sobald die Bridge die Steuerung hat.
	var steps := [FakeBusServer.status("connected", "ble", ["CADENCE", "RESISTANCE_CONTROL"], 0.0, {}, "error"),
			FakeBusServer.status("connected", "ble", ["CADENCE", "RESISTANCE_CONTROL"], 1.5, {}, "active")] \
			+ FakeBusServer.steady_cadence(80.0, 0.0, 30.0)
	var bus := start_fake_bus(steps)
	var ride := spawn_ride(bus, CLIMB_M)
	var hint: Label = ride.get_node("Hud/Hint")
	assert_true(await run_until(func(): return ride.state == "riding" and hint.text == ride.GEARS_OFF_ERROR, 1.4))
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 12, "error: kein Schalten")
	assert_true(await run_until(func(): return ride.gears_active(), 3.0))
	assert_true(await run_until(func(): return hint.text == "", 1.0), "active: Grund verschwindet")
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, 13, "active: Pfeil ↑ schaltet")
	await press_key(KEY_KP_SUBTRACT)
	assert_eq(ride.gears.gear, 12, "active: Ziffernblock − schaltet")
	assert_string_contains(ride.get_node("Hud").readout(), "Gang: 12/24")
