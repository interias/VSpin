## HUD, Debug-Anzeige und Rundenabschluss gegen den Fake-Bus: alle Werte sichtbar, Watt nur mit „~“ und nur
## wenn vorhanden, Debug-Anzeige per F3, Ziel mit Zusammenfassung – Fahrzeit und Durchschnitte ohne Pausen.
## Die HUD-Werte liest `_hud()` aus RideHud.readout(): genau die sichtbaren Anzeigen als „Name: Wert Einheit“.
extends "res://tests/support/bus_test.gd"

const FLAT_M := 20.0
## Abstand zur Ziellinie für Ziel-Tests (letzter flacher Abschnitt der Graybox-Strecke).
const BEFORE_FINISH_M := 12.0


func _hud(ride: Node) -> String:
	return ride.get_node("Hud").readout()


func _message(ride: Node) -> String:
	var label: Label = ride.get_node("Hud/Message")
	return label.text if label.visible else ""


## Konfiguration ohne Trägheit: die Geschwindigkeit ist sofort k · Kadenz, Durchschnitte sind exakt erwartbar.
func _instant_config(bus: FakeBusServer) -> RideConfig:
	var config := config_for(bus)
	config.inertia_s = 0.0
	return config


func _lap_length() -> float:
	var track: GrayboxTrack = autofree(GrayboxTrack.new())
	return track.length_m()


func test_hud_shows_all_values_without_watts() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0)), FLAT_M)
	await run_for(2.2)
	var hud := _hud(ride)
	assert_string_contains(hud, "Kadenz: 90 rpm")
	assert_string_contains(hud, "Tempo: %.1f km/h" % ride.model.speed_kmh())
	assert_string_contains(hud, "Strecke: %.2f km" % ((ride.model.distance_m - FLAT_M) / 1000.0))
	assert_between(ride.lap_time_s(), 1.5, 2.3, "Fahrzeit läuft")
	assert_string_contains(hud, "Zeit: %s" % ride.format_time(ride.lap_time_s()))
	assert_string_contains(hud, "Steigung: 0.0 %")
	assert_false(hud.contains("W"), "keine Watt, wenn die Quelle keine liefert: %s" % hud)


func test_estimated_watts_shown_with_tilde() -> void:
	var fields := {"power_w": 142.0, "power_estimated": true}
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 3.0, 0.25, fields)), FLAT_M)
	assert_true(await run_until(func(): return _hud(ride).contains("W"), 3.0))
	assert_string_contains(_hud(ride), "Leistung: ~142 W")


func test_measured_watts_shown_without_tilde_and_disappear_when_missing() -> void:
	var steps := [FakeBusServer.status()] \
			+ FakeBusServer.steady_cadence(90.0, 0.0, 1.0, 0.25, {"power_w": 180.4, "power_estimated": false}) \
			+ FakeBusServer.steady_cadence(90.0, 1.25, 4.0)
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	assert_true(await run_until(func(): return _hud(ride).contains("Leistung: 180 W"), 3.0), "gemessen: ohne „~“")
	assert_false(_hud(ride).contains("~"))
	assert_true(await run_until(func(): return not _hud(ride).contains("Leistung"), 3.0), "power_w null → keine Watt-Zeile")


func test_debug_overlay_toggles_and_shows_raw_values() -> void:
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(72.5, 0.0, 5.0)
	var ride := spawn_ride(start_fake_bus(steps), FLAT_M)
	var overlay: Label = ride.get_node("Hud/Debug")
	assert_false(overlay.visible, "anfangs aus")
	assert_true(await run_until(func(): return ride.bus.last_telemetry_t_ms >= 500, 3.0))
	await press_key(KEY_F3)
	assert_true(overlay.visible, "F3 schaltet ein")
	assert_string_contains(overlay.text, "Kadenz roh: 72.5", "Rohwert wie empfangen (HUD rundet auf 73)")
	assert_string_contains(_hud(ride), "Kadenz: 73 rpm")
	assert_string_contains(overlay.text, "t_ms: %d" % ride.bus.last_telemetry_t_ms)
	var age := RegEx.create_from_string("Letzte Telemetrie vor: (\\d+) ms").search(overlay.text)
	assert_not_null(age, "Zeit seit Empfang der letzten Telemetrie in ms")
	if age != null:
		assert_between(int(age.get_string(1)), 0, 1000)
	await run_for(0.6)
	assert_string_contains(overlay.text, "t_ms: %d" % ride.bus.last_telemetry_t_ms, "läuft mit")
	await press_key(KEY_F3)
	assert_false(overlay.visible, "F3 schaltet wieder aus")


func test_finish_shows_summary_with_averages_without_pause_time() -> void:
	# 90 rpm, Pause (stale) von 0,8 s bis 2,8 s, dann weiter bis ins Ziel.
	var steps := [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 0.75) \
			+ [FakeBusServer.status("stale", "sim", ["CADENCE"], 0.8)] \
			+ [FakeBusServer.status("connected", "sim", ["CADENCE"], 2.8)] \
			+ FakeBusServer.steady_cadence(90.0, 2.9, 10.0)
	var bus := start_fake_bus(steps)
	var start_m := _lap_length() - BEFORE_FINISH_M
	var ride := spawn_ride(bus, start_m, _instant_config(bus))
	var start_ms := Time.get_ticks_msec()
	assert_true(await run_until(func(): return ride.state == "paused_connection" and ride.lap_time_s() > 0.0, 3.0))
	var paused_time: float = ride.lap_time_s()
	await run_for(1.0)
	assert_eq(ride.lap_time_s(), paused_time, "Fahrzeit steht in der Pause")
	assert_true(await run_until(func(): return ride.state == "finished", 6.0), "Ziel erreicht")
	var wall_s := (Time.get_ticks_msec() - start_ms) / 1000.0
	var expected_kmh: float = ride.config.k_kmh_per_rpm * 90.0
	var expected_s := BEFORE_FINISH_M / (expected_kmh / 3.6)
	assert_almost_eq(ride.lap_time_s(), expected_s, 0.15, "Rundenzeit = Fahrzeit bis zur Ziellinie")
	assert_lt(ride.lap_time_s(), wall_s - 1.5, "Pause zählt nicht")
	assert_almost_eq(ride.stats.distance_m, BEFORE_FINISH_M, 0.001, "genau bis zur Ziellinie")
	assert_almost_eq(ride.stats.avg_cadence(), 90.0, 0.001)
	assert_almost_eq(ride.stats.avg_speed_kmh(), expected_kmh, 0.05, "Ø Tempo ohne Pause")
	var message := _message(ride)
	assert_string_contains(message, "Ziel erreicht")
	assert_string_contains(message, "Zeit: %s" % ride.format_time(ride.lap_time_s(), true))
	assert_string_contains(message, "Ø Kadenz: 90 rpm")
	assert_string_contains(message, "Ø Tempo: %.1f km/h" % ride.stats.avg_speed_kmh())
	assert_string_contains(_hud(ride), "Runde: 100 % (noch 0.00 km)", "Rundenfortschritt voll im Ziel")


func test_finish_is_final() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 8.0))
	var ride := spawn_ride(bus, _lap_length() - 5.0, _instant_config(bus))
	assert_true(await run_until(func(): return ride.state == "finished", 4.0))
	var distance: float = ride.model.distance_m
	var lap_time: float = ride.lap_time_s()
	await press_key(KEY_P)
	await run_for(0.5)
	assert_eq(ride.state, "finished", "Pause-Taste ändert nichts mehr")
	assert_eq(ride.model.distance_m, distance, "Fahrer steht im Ziel")
	assert_eq(ride.lap_time_s(), lap_time, "Rundenzeit bleibt")
