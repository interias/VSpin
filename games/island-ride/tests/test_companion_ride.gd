## Begleiter Toni in der Hauptszene (Spec #76, #80) gegen den Fake-Bus: Sprechtaste (Leertaste in der Fahrt sendet
## `companion_ptt` down/up, Pause nur `P`, im Startmenü unverändert), `ride_state` im Takt und `ride_event` beim Eintreten,
## HUD-Symbol für `companion_status` samt „Toni ist heiser“, Ducking solange Toni spricht, und: aus = keine Nachricht, kein
## Symbol, kein Ducking. Der Begleiter liest nur (ADR-0010): die Gegenprobe prüft, dass die Fahrt mit und ohne ihn gleich läuft.
extends "res://tests/support/bus_test.gd"

const RIDING := "riding"
const PAUSED_MANUAL := "paused_manual"
## Schnelles Rad: eine Graybox-Runde in wenigen Sekunden (wie in test_round_trip).
const FAST_K := 10.0
const STATE_KEYS := ["mode", "direction", "lap", "laps", "km_done", "km_left", "section", "next_sight", "next_sight_km",
		"grade", "speed_kmh", "cadence", "power_w", "power_estimated", "heart_rate", "hr_zone", "ghost_gap_s",
		"best_time_s", "companion_volume"]


## Fahrt-Drehbuch: Bridge `connected`, gleichbleibende Kadenz bis `to_s`, dazu `extra` (z. B. `companion_status`).
func _script(extra: Array = [], to_s := 40.0, fields: Dictionary = {}) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, to_s, 0.25, fields) + extra


func _companion_status(state: String, at: float, speaking = null) -> Dictionary:
	return {"at": at, "send": {"v": 0, "type": "companion_status", "state": state,
			"speaking": (state == "speaking") if speaking == null else speaking}}


## Schnelle Fahrt (ohne Trägheit) am Fake-Bus, sofort fahrend wie die Tests ohne Startmenü.
func _spawn_fast(bus: FakeBusServer) -> Node:
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	return spawn_ride(bus, 0.0, config)


## Nachrichten vom Typ `type` (und `kind`) an den Bus.
func _sent(bus: FakeBusServer, type: String, kind := "") -> Array:
	return bus.received.filter(func(m): return m.get("type") == type and (kind.is_empty() or m.get("kind") == kind))


func _kinds(bus: FakeBusServer) -> Array:
	return _sent(bus, "ride_event").map(func(m): return m["kind"])


## Aktionen der gesendeten `companion_ptt`-Nachrichten in Reihenfolge.
func _ptt(bus: FakeBusServer) -> Array:
	return _sent(bus, "companion_ptt").map(func(m): return m["action"])


## Taste wie die Hardware: gedrückt/losgelassen, auch als Tastenwiederholung (`echo`).
func _key(key: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await get_tree().process_frame


func _riding(ride: Node) -> void:
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0), "Fahrt läuft")
	assert_true(await run_until(func(): return ride.get("_ride_start_sent") == true, 2.0), "ride_start ist raus")


# --- Sprechtaste -------------------------------------------------------------------------------------------------

func test_holding_space_sends_down_then_up_without_key_repeat() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, true, true)  # Tastenwiederholung
	await _key(KEY_SPACE, true, true)
	await run_for(0.2)
	assert_eq(_ptt(bus), ["down"], "einmal down, keine Wiederholung")
	assert_eq(ride.state, RIDING, "die Leertaste pausiert nicht mehr")
	await _key(KEY_SPACE, false)
	await run_for(0.2)
	assert_eq(_ptt(bus), ["down", "up"], "Loslassen sendet up")
	await _key(KEY_SPACE, false)
	await run_for(0.1)
	assert_eq(_ptt(bus), ["down", "up"], "ein up ohne down gibt es nicht")


func test_pause_is_only_p_and_space_does_not_resume() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await press_key(KEY_P)
	assert_eq(ride.state, PAUSED_MANUAL, "P pausiert")
	assert_string_contains(ride.status_message(), "P: weiter")
	assert_false(ride.status_message().contains("Leertaste"), "der Hinweis nennt die Leertaste nicht mehr")
	await press_key(KEY_SPACE)
	await run_for(0.2)
	assert_eq(ride.state, PAUSED_MANUAL, "die Leertaste setzt nicht fort")
	assert_eq(_ptt(bus), [], "in der Pause spricht sie nicht")
	await press_key(KEY_P)
	assert_eq(ride.state, RIDING, "P setzt fort")


func test_pausing_while_holding_releases_the_key() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await _key(KEY_SPACE, true)
	await press_key(KEY_P)
	await run_for(0.2)
	assert_eq(ride.state, PAUSED_MANUAL)
	assert_eq(_ptt(bus), ["down", "up"], "Pause beendet das Sprechen, Toni hört nicht weiter zu")
	await _key(KEY_SPACE, false)
	await run_for(0.1)
	assert_eq(_ptt(bus), ["down", "up"], "das spätere Loslassen sendet nichts mehr")


func test_opening_the_settings_while_holding_releases_the_key() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await _key(KEY_SPACE, true)
	await press_key(KEY_F2)
	await run_for(0.2)
	assert_true(ride.settings_menu.is_open())
	assert_eq(_ptt(bus), ["down", "up"], "Einstellungsmenü beendet das Sprechen")
	await _key(KEY_SPACE, false)
	await _key(KEY_SPACE, true)
	await run_for(0.2)
	assert_eq(_ptt(bus), ["down", "up"], "bei offenem Einstellungsmenü kein Sprechen")


func test_ending_the_ride_while_holding_releases_the_key() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await _key(KEY_SPACE, true)
	await run_for(0.1)
	ride.return_to_menu()
	await run_for(0.2)
	assert_eq(_ptt(bus), ["down", "up"], "Fahrtende lässt die Sprechtaste los")
	assert_eq(_kinds(bus), ["ride_start", "ride_end"], "und up kommt vor ride_end")
	var order := bus.received.filter(func(m): return m.get("type") in ["companion_ptt", "ride_event"]).map(
			func(m): return m.get("action", m.get("kind")))
	assert_eq(order, ["ride_start", "down", "up", "ride_end"])


func test_space_in_the_start_menu_stays_unchanged() -> void:
	var bus := start_fake_bus(_script())
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = ""
	add_child_autofree(game)  # mit Startmenü
	await run_for(0.5)
	assert_eq(game.state, "menu")
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await run_for(0.3)
	assert_eq(game.state, "menu", "die Leertaste pausiert im Menü nichts")
	assert_eq(_ptt(bus), [], "und spricht dort nicht")
	assert_eq(_sent(bus, "ride_event"), [], "im Menü kein ride_start")
	assert_eq(_sent(bus, "ride_state"), [], "im Menü kein ride_state")


# --- ride_state und ride_event ------------------------------------------------------------------------------------

func test_ride_state_every_five_seconds_by_default() -> void:
	var ride := spawn_ride(start_fake_bus(_script()))
	assert_eq(ride.companion_state_interval_s, 5.0, "Takt laut Protokoll: alle 5 s")
	assert_eq(ride.COMPANION_STATE_S, 5.0)


func test_ride_state_carries_the_fields_of_the_protocol() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	ride.companion_state_interval_s = 0.4
	await _riding(ride)
	await run_for(1.7)
	var states := _sent(bus, "ride_state")
	assert_between(states.size(), 3, 5, "im Takt, nicht öfter")
	var state: Dictionary = states[-1]
	for key in STATE_KEYS:
		assert_true(state.has(key), "Feld %s" % key)
	assert_eq(state["mode"], "rundfahrt")
	assert_eq(state["direction"], "cw")
	assert_eq(state["lap"], 1.0)
	assert_eq(state["laps"], 1.0)
	assert_gt(state["km_done"], 0.0)
	assert_gt(state["km_left"], 0.0, "mit Ziel: Rest bis dorthin")
	assert_gt(state["speed_kmh"], 0.0)
	assert_eq(state["cadence"], 90.0)
	assert_eq(state["companion_volume"], GraphicsSettings.DEFAULT_COMPANION_VOLUME, "Lautstärke des Begleiters")
	for unknown in ["section", "next_sight", "next_sight_km", "power_w", "power_estimated", "heart_rate", "hr_zone",
			"ghost_gap_s", "best_time_s"]:
		assert_null(state[unknown], "%s ist ohne Wert null" % unknown)
	assert_between(state["km_done"], states[0]["km_done"], 1.0)
	assert_ne(states[0]["km_done"], state["km_done"], "wandert mit der Fahrt")


func test_ride_state_reports_power_pulse_and_volume_from_the_game() -> void:
	var fields := {"power_w": 142.0, "power_estimated": true, "heart_rate": 160.0}
	var bus := start_fake_bus(_script([], 40.0, fields))
	var ride := spawn_ride(bus)
	ride.pulse_zones = HeartRateZones.new(170.0, 190.0)
	ride.settings_menu.settings.companion_volume = 0.4
	await _riding(ride)
	var state: Dictionary = await _state_now(ride)
	assert_eq(state["power_w"], 142.0)
	assert_eq(state["power_estimated"], true)
	assert_eq(state["heart_rate"], 160.0)
	assert_eq(state["hr_zone"], float(ride.pulse_zones.zone_for(160.0)), "Zone aus den Pulszonen der Fahrt")
	assert_gte(state["hr_zone"], 1.0)
	assert_eq(state["companion_volume"], 0.4, "Lautstärke aus den Einstellungen, sofort")


func _state_now(ride: Node) -> Dictionary:
	await run_for(0.3)  # Telemetrie ist da
	return JSON.parse_string(JSON.stringify(ride.ride_state_message()))


func test_no_ride_state_during_pause() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	ride.companion_state_interval_s = 0.3
	await _riding(ride)
	await press_key(KEY_P)
	var before := _sent(bus, "ride_state").size()
	await run_for(1.2)
	assert_eq(_sent(bus, "ride_state").size(), before, "in der Pause keine ride_state")
	await press_key(KEY_P)
	await run_for(0.8)
	assert_gt(_sent(bus, "ride_state").size(), before, "danach wieder")


func test_ride_start_carries_logbook_summary_and_volume() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	for i in range(7):
		ride.save_game.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, "island", true, 1, RideStats.new(),
				"2026-10-%02dT10:00:00Z" % (i + 1)))
	await _riding(ride)
	var start: Dictionary = _sent(bus, "ride_event", "ride_start")[0]
	assert_eq(start["mode"], "rundfahrt")
	assert_eq(start["direction"], "cw")
	assert_eq(start["laps"], 1.0)
	assert_eq(start["companion_volume"], GraphicsSettings.DEFAULT_COMPANION_VOLUME)
	var logbook: Dictionary = start["logbook"]
	assert_eq(logbook["rides"], 7.0)
	assert_eq(logbook["recent"].size(), 5, "höchstens fünf letzte Fahrten")
	assert_eq(logbook["recent"][0]["date"], "2026-10-07T10:00:00Z", "neueste zuerst")
	for key in ["date", "mode", "distance_km", "duration_s", "avg_cadence_rpm"]:
		assert_true(logbook["recent"][0].has(key), "Fahrtenbuch-Feld %s" % key)
	assert_eq(_kinds(bus).count("ride_start"), 1, "genau einmal")


func test_laps_medals_best_time_and_end_reach_the_bus() -> void:
	var bus := start_fake_bus(_script([], 60.0))
	var ride := _spawn_fast(bus)
	await _riding(ride)
	ride.start_ride(SaveGame.MODE_ROUND_TRIP, 2)  # zwei Runden bis zum Ziel
	assert_true(await run_until(func(): return ride.state == "finished", 20.0), "Ziel nach zwei Runden")
	await run_for(0.3)
	var kinds := _kinds(bus)
	assert_eq(kinds[0], "ride_start")
	assert_eq(kinds[-1], "ride_end")
	assert_eq(kinds.count("ride_start"), 2, "start_ride beginnt eine neue Fahrt für den Begleiter")
	var laps := _sent(bus, "ride_event", "lap")
	assert_eq(laps.size(), 2)
	assert_eq(laps[0]["lap"], 1.0)
	assert_eq(laps[1]["lap"], 2.0)
	assert_almost_eq(laps[0]["time_s"], ride.lap_timing.lap_times[0], 0.01)
	var medals := _sent(bus, "ride_event", "medal")
	assert_gt(medals.size(), 0, "Medaille der Runde")
	assert_eq(medals[0]["for"], "lap")
	assert_true(medals[0]["medal"] in ["bronze", "silver", "gold"])
	var bests := _sent(bus, "ride_event", "best_time")
	assert_gt(bests.size(), 0)
	assert_null(bests[0]["previous_s"], "die erste Bestzeit hat keinen Vorgänger")
	assert_almost_eq(bests[0]["time_s"], ride.lap_timing.lap_times[0], 0.01)
	assert_eq(bests[0]["for"], "lap")
	var achievements := _sent(bus, "ride_event", "achievement")
	assert_gt(achievements.size(), 0, "ein Erfolg (erste Runde)")
	assert_true(achievements[0].has("id") and achievements[0].has("name"))
	var end: Dictionary = _sent(bus, "ride_event", "ride_end")[-1]
	assert_eq(end["finished"], true, "Ziel erreicht")
	assert_gt(end["distance_km"], 0.0)
	assert_almost_eq(end["duration_s"], ride.stats.ride_time_s, 0.1)
	assert_eq(_kinds(bus).count("ride_end"), 1, "ride_end einmal je Fahrt")


func test_aborting_the_ride_sends_ride_end_not_finished() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await run_for(0.5)
	ride.return_to_menu()
	await run_for(0.3)
	var end: Dictionary = _sent(bus, "ride_event", "ride_end")[-1]
	assert_eq(end["finished"], false, "abgebrochen")
	assert_eq(_kinds(bus).count("ride_end"), 1, "einmal je Fahrt")


func test_pause_event_on_both_edges() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await press_key(KEY_P)
	await press_key(KEY_P)
	await run_for(0.2)
	var pauses := _sent(bus, "ride_event", "pause")
	assert_eq(pauses.map(func(m): return m["paused"]), [true, false])


func test_training_reports_interval_start() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	var unit: Dictionary = Training.load_all()[0]
	ride.start_ride(SaveGame.MODE_TRAINING, 0, "", unit)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	await run_for(0.5)
	var intervals := _sent(bus, "ride_event", "interval_start")
	assert_gt(intervals.size(), 0)
	var phase: Dictionary = unit["phases"][0]
	assert_eq(intervals[0]["target_cadence"], (float(phase["cadence_min"]) + float(phase["cadence_max"])) / 2.0)
	assert_eq(intervals[0]["duration_s"], float(phase["duration_s"]))
	var start: Dictionary = _sent(bus, "ride_event", "ride_start")[-1]
	assert_eq(start["mode"], "training")
	assert_null(start["laps"], "endlos")


func test_boss_events_come_from_the_arcade_stage() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	ride.arcade_stage.challenge_started.emit({"definition": {"id": "x", "name": "Tramuntana", "boss": true}})
	ride.arcade_stage.challenge_ended.emit({"id": "x", "name": "Tramuntana", "boss": true, "succeeded": true})
	ride.arcade_stage.challenge_started.emit({"definition": {"id": "y", "name": "Zone halten"}})
	ride.arcade_stage.challenge_ended.emit({"id": "y", "name": "Zone halten", "boss": false, "succeeded": true})
	await run_for(0.3)
	assert_eq(_sent(bus, "ride_event", "boss_start").map(func(m): return m["boss"]), ["Tramuntana"])
	var ended := _sent(bus, "ride_event", "boss_end")
	assert_eq(ended.size(), 1, "gewöhnliche Herausforderungen sind keine Bosse")
	assert_eq(ended[0]["boss"], "Tramuntana")
	assert_eq(ended[0]["defeated"], true)


# --- Begleiter aus -----------------------------------------------------------------------------------------------

func test_companion_off_sends_nothing_and_shows_nothing() -> void:
	var script := _script([_companion_status("speaking", 0.5), _companion_status("hoarse", 1.0)])
	var bus := start_fake_bus(script)
	var ride := spawn_ride(bus)
	ride.settings_menu.settings.companion_enabled = false  # vor dem ersten Frame
	ride.companion_state_interval_s = 0.2
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await press_key(KEY_P)
	await press_key(KEY_P)
	await run_for(1.5)
	assert_true(ride.bus.companion_seen, "Toni ist am Bus …")
	for type in ["companion_ptt", "ride_state", "ride_event"]:
		assert_eq(_sent(bus, type), [], "… das Spiel sendet trotzdem kein %s" % type)
	assert_eq(ride.hud.companion_state(), "", "kein Symbol")
	assert_eq(ride.hud.companion_notice(), "", "kein Hinweis")
	assert_false(ride.sound.ducked, "kein Ducking")
	assert_eq(ride.sound.duck, 1.0)
	assert_eq(ride.state, RIDING, "die Fahrt läuft wie immer")


func test_switching_the_companion_on_works_at_once() -> void:
	var bus := start_fake_bus(_script([_companion_status("idle", 0.3)]))
	var ride := spawn_ride(bus)
	ride.settings_menu.settings.companion_enabled = false
	ride.companion_state_interval_s = 0.2
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0))
	await run_for(0.8)
	assert_eq(_sent(bus, "ride_event"), [])
	ride.settings_menu.settings.companion_enabled = true  # ohne Neustart
	assert_true(await run_until(func(): return _kinds(bus).has("ride_start"), 2.0), "ride_start holt es nach")
	assert_true(await run_until(func(): return _sent(bus, "ride_state").size() > 0, 2.0))
	assert_eq(ride.hud.companion_state(), "idle", "Symbol da")
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await run_for(0.2)
	assert_eq(_ptt(bus), ["down", "up"])


func test_switching_off_forgets_the_companion_so_it_can_come_back() -> void:
	# Ein ausgeschalteter (beendeter) Begleiter meldet sich nicht ab: sein letzter Zustand darf nicht stehen bleiben –
	# weder als Symbol/Ducking beim Wiedereinschalten noch als „schon einer da“ für den Launcher.
	var bus := start_fake_bus(_script([_companion_status("speaking", 0.3)]))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.sound.ducked, 3.0), "Toni spricht, Ducking an")
	ride.settings_menu.settings.companion_enabled = false
	await run_for(0.3)
	assert_false(ride.bus.companion_seen, "Begleiter vergessen")
	assert_false(ride.sound.ducked, "kein Ducking mehr")
	ride.settings_menu.settings.companion_enabled = true
	await run_for(0.3)
	assert_eq(ride.hud.companion_state(), "", "kein Symbol eines Begleiters, der nicht mehr da ist")
	assert_false(ride.sound.ducked)
	assert_false(ride.bus.companion_seen, "dem Launcher gilt: keiner am Bus, er darf einen neuen starten")


func test_companion_does_not_change_the_ride() -> void:
	# Gegenprobe zu ADR-0010: dieselbe Fahrt mit und ohne Begleiter ergibt dieselbe Strecke, Zeit und Wertung.
	var results := []
	for on in [true, false]:
		var bus := start_fake_bus(_script([_companion_status("speaking", 0.3), _companion_status("hoarse", 0.8)], 60.0))
		var ride := _spawn_fast(bus)
		ride.settings_menu.settings.companion_enabled = on
		ride.start_ride(SaveGame.MODE_ROUND_TRIP, 1)
		assert_true(await run_until(func(): return ride.state == "finished", 20.0))
		results.append([ride.lap_timing.lap_times.size(), ride.stats.distance_m > 0.0, ride.lap_timing.finished()])
		ride.queue_free()
		await get_tree().process_frame
	assert_eq(results[0], results[1])


# --- HUD und Ducking ---------------------------------------------------------------------------------------------

func test_hud_shows_all_five_states_and_ducking_only_while_speaking() -> void:
	var states := [["idle", 0.4], ["listening", 0.9], ["thinking", 1.4], ["speaking", 1.9], ["hoarse", 2.9],
			["idle", 3.4]]
	var bus := start_fake_bus(_script(states.map(func(s): return _companion_status(s[0], s[1]))))
	var ride := spawn_ride(bus)
	assert_eq(ride.hud.companion_state(), "", "ohne gesehenes companion_status kein Symbol")
	assert_false(ride.sound.ducked)
	var seen := []
	for step in states:
		assert_true(await run_until(func(): return ride.hud.companion_state() == step[0] and ride.bus.companion_state == step[0], 3.0),
				"HUD zeigt %s" % step[0])
		seen.append(ride.hud.companion_state())
		await run_for(0.1)
		var speaking: bool = step[0] == "speaking"
		assert_eq(ride.sound.ducked, speaking, "Ducking nur bei speaking (%s)" % step[0])
		assert_true(ride.hud.readout().contains("Toni: "), "Zeile im Readout")
		if step[0] == "speaking":
			await run_for(RideSound.DUCK_FADE_S + 0.1)
			assert_almost_eq(ride.sound.duck, RideSound.DUCK_GAIN, 0.001, "Pegel gesenkt")
			assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(RideSound.BUS)),
					linear_to_db(ride.sound.bus_volume()), 0.01, "am Audiobus")
	assert_eq(seen, ["idle", "listening", "thinking", "speaking", "hoarse", "idle"], "alle fünf Zustände")
	await run_for(RideSound.DUCK_FADE_S + 0.1)
	assert_eq(ride.sound.duck, 1.0, "nach dem Sprechen wieder voll")
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(RideSound.BUS)),
			linear_to_db(ride.settings_menu.settings.sound_volume), 0.01, "auf dem eingestellten Pegel")


func test_hoarse_notice_shows_once_per_ride_and_the_ride_goes_on() -> void:
	var bus := start_fake_bus(_script([_companion_status("hoarse", 0.5), _companion_status("listening", 1.0),
			_companion_status("hoarse", 1.5)]))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.hud.companion_notice() == "Toni ist heiser", 3.0), "Hinweis")
	assert_eq(ride.hud.companion_state(), "hoarse", "Symbol heiser")
	ride.hud.show_companion_notice("")  # weggeklickt
	assert_true(await run_until(func(): return ride.bus.companion_state == "listening", 3.0))
	assert_true(await run_until(func(): return ride.bus.companion_state == "hoarse", 3.0))
	await run_for(0.3)
	assert_eq(ride.hud.companion_state(), "hoarse")
	assert_eq(ride.hud.companion_notice(), "", "nicht noch einmal in derselben Fahrt")
	assert_eq(ride.state, RIDING, "die Fahrt läuft weiter")


func test_no_symbol_and_no_ducking_without_a_companion_status() -> void:
	var bus := start_fake_bus(_script())
	var ride := spawn_ride(bus)
	await _riding(ride)
	await run_for(0.5)
	assert_eq(ride.hud.companion_state(), "")
	assert_false(ride.sound.ducked)
	assert_false(ride.hud.readout().contains("Toni"))


# --- BusClient ---------------------------------------------------------------------------------------------------

func test_bus_client_reads_companion_status_and_forgets_it_on_disconnect() -> void:
	var script := [FakeBusServer.status(), _companion_status("thinking", 0.2), _companion_status("sonst", 0.4, true),
			_companion_status("speaking", 0.6), FakeBusServer.close_at(1.2)]
	var bus := start_fake_bus(script)
	var client := connect_client(bus, 5.0)
	var seen := []
	client.companion_status_received.connect(func(state, speaking): seen.append([state, speaking]))
	assert_false(client.companion_seen, "anfangs kein Begleiter am Bus")
	assert_true(await run_until(func(): return client.companion_state == "speaking", 3.0))
	assert_true(client.companion_seen)
	assert_true(client.companion_speaking)
	assert_eq(seen, [["thinking", false], ["speaking", true]], "ein unbekannter Zustand wird ignoriert")
	assert_true(await run_until(func(): return not client.bus_connected, 3.0), "Abbruch")
	assert_false(client.companion_seen, "nach einem Abbruch gilt wieder: kein Begleiter am Bus")
	assert_false(client.companion_speaking)


# --- Begleiter kommt später / geht verloren -----------------------------------------------------------------------

func test_late_companion_gets_ride_start_once_per_appearance() -> void:
	var bus := start_fake_bus(_script([_companion_status("idle", 3.0), _companion_status("speaking", 3.5),
			_companion_status("idle", 4.0)]))
	var ride := spawn_ride(bus)
	await _riding(ride)
	await run_for(1.0)
	assert_eq(_kinds(bus).count("ride_start"), 1, "vor Toni genau ein ride_start")
	assert_true(await run_until(func(): return ride.bus.companion_seen, 5.0), "Toni kommt während der Fahrt")
	assert_true(await run_until(func(): return _kinds(bus).count("ride_start") == 2, 2.0), "ride_start noch einmal")
	await run_for(1.5)
	assert_eq(_kinds(bus).count("ride_start"), 2, "nicht bei jeder Statusänderung")


func test_companion_present_from_the_start_gets_no_second_ride_start() -> void:
	var bus := start_fake_bus(_script([_companion_status("idle", 0.3)]))
	var ride := spawn_ride(bus)
	await _riding(ride)
	await run_for(2.5)
	assert_true(ride.bus.companion_seen)
	assert_eq(_kinds(bus).count("ride_start"), 1, "seine Antwort auf ride_start ist kein Neuankömmling")


func test_no_second_ride_start_when_companion_is_off() -> void:
	var bus := start_fake_bus(_script([_companion_status("idle", 2.5)]))
	var ride := spawn_ride(bus)
	ride.settings_menu.settings.companion_enabled = false
	assert_true(await run_until(func(): return ride.bus.companion_seen, 5.0))
	await run_for(0.5)
	assert_eq(_sent(bus, "ride_event"), [])


func test_own_companion_that_exits_is_forgotten_at_once() -> void:
	var bus := start_fake_bus(_script([_companion_status("speaking", 0.3), _companion_status("idle", 3.0)]))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.sound.ducked and ride.hud.companion_state() == "speaking", 3.0))
	ride.bridge_launcher.companion_failed = true  # der Launcher meldet: der eigene Begleiter hat sich beendet
	await run_for(0.2)
	assert_false(ride.bus.companion_seen, "vergessen")
	assert_eq(ride.hud.companion_state(), "", "kein Symbol mehr")
	assert_false(ride.sound.ducked, "kein Ducking mehr")
	assert_true(await run_until(func(): return ride.bus.companion_seen, 5.0), "ein neuer Begleiter wird wieder gesehen")
	await run_for(0.3)
	assert_true(ride.bus.companion_seen, "und nicht in jedem Frame vergessen")


func test_foreign_companion_stays_while_the_launcher_reports_nothing() -> void:
	var bus := start_fake_bus(_script([_companion_status("speaking", 0.3)]))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.sound.ducked, 3.0))
	await run_for(1.0)
	assert_true(ride.bus.companion_seen)
	assert_true(ride.sound.ducked, "Gegenprobe: ohne Meldung des Launchers bleibt er")
