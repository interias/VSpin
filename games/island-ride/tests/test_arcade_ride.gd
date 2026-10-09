## Arcade (#46) gegen den Fake-Bus durch die echte Hauptszene: im Menü wählbar mit drei Stufen und einstellbarem
## Kadenzbereich (wirksam: die Zielzone folgt ihm, Wächter), Zone halten mit HUD und Toren, Punkte und Zusammenfassung,
## Arcade-Stand im Spielstand, getrennte Welten (ADR-0010: km zählen, nie Bestzeit, Segmentzeit, Medaille, Ghost) und
## die Simulator-Szenarien der Bridge (`bridge/profiles/arcade/*.toml`) mit genau ihrem Kadenzverlauf:
## „perfekt in der Zone“ → geschafft, „knapp daneben“ → weich verfehlt, „Abbruch“ → Pause, nichts läuft weiter,
## danach geschafft. Durchbruch und Jagd (#47): Zugbrücke und Verfolger auf der Strecke, Erfolg und weiches Scheitern in
## HUD, Punkten und Beute, und ihre Szenarien (`durchbruch_*`, `jagd_*`).
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_arcade_ride_savegame.json")
const DT := 0.1
## Schnelles Rad wie in test_round_trip.gd: viele Graybox-Runden in einer Minute.
const FAST_K := 10.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus mit Drehbuch `steps`, Test-Spielstand. Mit `fast` ohne
## Trägheit und mit FAST_K.
func _spawn_game(steps: Array, fast: bool = false) -> Node:
	return _spawn_on(start_fake_bus(steps), fast)


func _spawn_on(bus: FakeBusServer, fast: bool = false) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	if fast:
		config.inertia_s = 0.0
		config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Arcade“, Stufe `tier`, Kadenzbereich `lower`–`upper` (rpm), „Losfahren“ – mit festem Würfel und nur der
## Herausforderung „zone_mitte“ (Zone halten in der Mitte des Bereichs), damit das Ergebnis vorhersagbar ist.
func _start_arcade(game: Node, tier: int = 1, lower: float = 60.0, upper: float = 120.0,
		challenge: String = "zone_mitte") -> void:
	await run_for(0.2)
	AbilityExtension.of(game.arcade_stage).enabled = false  # Fähigkeiten (#50) sind hier nicht der Gegenstand
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find(challenge)]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	_select(menu.options["tier"], tier - 1)
	_select(menu.options["cadence_min"], CadenceRange.MIN_CHOICES.find(lower))
	_select(menu.options["cadence_max"], CadenceRange.MAX_CHOICES.find(upper))
	menu.buttons["arcade_start"].pressed.emit()


func _select(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)


## Wartet, bis die Fahrt mit Kadenz läuft, und schaltet dann auf feste Schritte (`_ride`) um.
func _until_riding(game: Node) -> void:
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0), "Arcade fährt")
	game.set_process(false)


## `seconds` Fahrt in festen Schritten wie ein Frame der Hauptszene; hält im Ergebnis an. Liefert die Einblendungen.
func _ride(game: Node, seconds: float) -> Array:
	var shown := []
	for i in range(roundi(seconds / DT)):
		if game.state != "riding":
			break
		game._ride(DT)
		game._update_view()
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return shown


## Bis die erste Herausforderung läuft (höchstens `seconds`).
func _ride_to_challenge(game: Node, seconds: float = 30.0) -> void:
	for i in range(roundi(seconds / DT)):
		if not game.arcade.active.is_empty():
			return
		_ride(game, DT)


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


# --- Menü, Stufen, Kadenzbereich ---------------------------------------------------------------------------------


func test_arcade_in_menu_with_three_tiers() -> void:
	var game := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 10.0))
	await run_for(0.2)
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	assert_false(menu.buttons["arcade"].disabled, "Arcade wählbar")
	assert_eq(menu.buttons["arcade"].text, "Arcade")
	menu.buttons["arcade"].pressed.emit()
	assert_true(menu.buttons["arcade_start"].is_visible_in_tree(), "Seite „Arcade“")
	assert_eq(game.get_viewport().gui_get_focus_owner(), menu.buttons["arcade_start"], "Fokus auf „Losfahren“")
	var tiers: OptionButton = menu.options["tier"]
	var names := []
	for i in range(tiers.item_count):
		names.append(tiers.get_item_text(i))
	assert_eq(names, ["Stufe 1", "Stufe 2", "Stufe 3"], "drei Stufen")
	assert_eq(menu.arcade_tier(), 1, "Standard Stufe 1")
	assert_eq(menu.cadence_range().to_dict(), {"min": 60.0, "max": 120.0}, "Standard-Kadenzbereich 60–120 rpm")
	var info: Label = menu.find_child("ArcadeInfo", true, false)
	assert_string_contains(info.text, "20 rpm")
	_select(tiers, 2)
	assert_string_contains(info.text, "10 rpm", "Beschreibung der Stufe 3")
	assert_eq(ArcadeTiers.selection(game.save_game), 3, "Wahl steht im Spielstand")
	watch_signals(menu)
	menu.buttons["arcade_start"].pressed.emit()
	assert_signal_emitted_with_parameters(menu, "ride_requested", [SaveGame.MODE_ARCADE])
	assert_eq(game.ride_mode, SaveGame.MODE_ARCADE)
	assert_eq(game.arcade.tier, 3, "die gewählte Stufe fährt")
	assert_null(game.training)
	assert_null(game.ghost, "ohne Ghost")
	assert_eq(game.lap_timing.finish_m(), INF, "beliebig viele Runden")
	menu.buttons["arcade_back"].pressed.emit()  # verborgen in der Fahrt, aber der Knopf führt zur Modus-Auswahl
	assert_true(menu.buttons["round_trip"].visible)


func test_cadence_range_is_settable_and_bounds_the_zones() -> void:
	var game := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(110.0, 0.0, 30.0))
	await _start_arcade(game, 1, 80.0, 150.0)
	await _until_riding(game)
	assert_eq(game.arcade.cadence_range.to_dict(), {"min": 80.0, "max": 150.0}, "Bereich aus dem Menü")
	var saved := SaveGame.load_file(SAVE_PATH)
	assert_eq(CadenceRange.selection(saved).to_dict(), {"min": 80.0, "max": 150.0}, "auf der Platte gespeichert")
	assert_string_contains(game.hud.readout(), "Ziel: 105–125 rpm", "nächste Zone schon angezeigt")
	_ride_to_challenge(game)
	var block: ZoneHold = game.arcade.active["block"]
	assert_eq(block.zone(), Vector2(105.0, 125.0), "Zone in der Mitte des eigenen Bereichs (115 rpm)")
	_ride(game, 2.0)
	assert_string_contains(game.hud.readout(), "Zone: im Bereich (105–125 rpm, 110 rpm)")
	assert_gt(block.progress(), 0.0, "110 rpm zählt hier")
	# Gegenprobe: im Standardbereich liegt dieselbe Herausforderung bei 80–100 rpm – 110 rpm zählt dort nicht.
	var other := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(110.0, 0.0, 30.0))
	await _start_arcade(other, 1, 60.0, 120.0)
	await _until_riding(other)
	_ride_to_challenge(other)
	_ride(other, 2.0)
	var standard: ZoneHold = other.arcade.active["block"]
	assert_eq(standard.zone(), Vector2(80.0, 100.0))
	assert_eq(standard.progress(), 0.0, "zu hoch für diese Zone")
	assert_string_contains(other.hud.readout(), "Zone: zu hoch (80–100 rpm, 110 rpm)")


# --- Zone halten in der Fahrt ------------------------------------------------------------------------------------


func test_zone_hold_hud_gates_points_and_summary() -> void:
	var game := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 30.0))
	await _start_arcade(game)
	await _until_riding(game)
	_ride(game, 1.0)
	var hud: String = game.hud.readout()
	assert_string_contains(hud, "Herausforderung: Nächste: Zone halten")
	assert_string_contains(hud, "Ziel: 80–100 rpm")
	assert_string_contains(hud, "Punkte: 0")
	assert_true(game.arcade_start_gate.visible, "Starttor vor dem Fahrer")
	assert_eq(game.arcade_start_gate.kind, CourseGate.KIND_START)
	assert_eq(game.arcade_start_gate.text, "Start  80–100 rpm")
	assert_almost_eq(game.arcade_start_gate.ride_m, ArcadeRun.START_LEAD_M, 0.001)
	_ride_to_challenge(game)
	_ride(game, 5.0)
	hud = game.hud.readout()
	assert_string_contains(hud, "Herausforderung: Zone halten")
	assert_string_contains(hud, "Noch: 0:25")
	assert_string_contains(hud, "Zone: im Bereich (80–100 rpm, 90 rpm)", "Zonenbalken (ZoneBar)")
	assert_string_contains(hud, "Fortschritt: 33 %")
	assert_eq(game.arcade_finish_gate.kind, CourseGate.KIND_FINISH, "Zieltor am Ende des Zeitfensters")
	var shown := _ride(game, 11.0)
	assert_has(shown, "Zone halten geschafft!  +100 Punkte", "Erfolg blendet ein")
	assert_string_contains(game.hud.readout(), "Punkte: 100")
	assert_false(game.hud.readout().contains("Fortschritt"), "nach dem Ende kein Zonenbalken")
	# „Fahrt beenden“: Zusammenfassung, Fahrt im Spielstand mit dem Arcade-Ergebnis und der besten Punktzahl.
	game.settings_menu.ride_end_requested.emit()
	assert_eq(game.state, "finished", "erst die Zusammenfassung")
	game._update_view()
	var message := _message(game)
	assert_string_contains(message, "Arcade beendet · Stufe 1")
	assert_string_contains(message, "Punkte: 100 – neue Bestpunktzahl!")
	assert_string_contains(message, "Herausforderungen: 1 geschafft · 0 verfehlt")
	assert_string_contains(message, "Zone halten 1/1")
	assert_false(game.hud.readout().contains("Herausforderung"), "im Ergebnis keine Arcade-Zeile")
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride["mode"], SaveGame.MODE_ARCADE)
	assert_eq(ride["arcade"], {"tier": 1, "points": 100, "won": 1, "failed": 0})
	var saved := SaveGame.load_file(SAVE_PATH)
	assert_eq(saved.best_arcade_points(1), 100, "Arcade-Stand auf der Platte")
	assert_eq(saved.rides()[0]["arcade"]["points"], 100.0)
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")
	assert_false(game.arcade_start_gate.visible, "im Menü keine Tore")
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["arcade"].pressed.emit()
	var best: Label = game.start_menu.find_child("ArcadeBest", true, false)
	assert_eq(best.text, "Bestpunktzahl: 100")


func test_arcade_km_count_but_never_records() -> void:
	# ADR-0010: Arcade-Runden schreiben nie Bestzeit, Segmentzeit, Medaille oder Ghost – auch nicht schneller als die
	# gespeicherte Bestzeit. Die km zählen für Fahrtenbuch, Fahrerlevel und Erfolge.
	var game := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 30.0), true)
	await run_for(0.2)
	var track := RideConfig.TRACK_GRAYBOX
	var cw := LapTiming.DIRECTION_CW
	game.save_game.record_best_time(track, cw, 9999.0)
	await _start_arcade(game)
	await _until_riding(game)
	var shown := _ride(game, 60.0)
	assert_gt(game.lap_timing.lap_times.size(), 5, "viele Runden gefahren")
	for text in shown:
		assert_false(text.contains("Bestzeit"), "keine Bestzeit-Einblendung: %s" % text)
	game.settings_menu.ride_end_requested.emit()
	var profile: Dictionary = game.save_game.profile()
	assert_eq(profile["best_times"], {track: {cw: 9999.0}}, "Bestzeit unverändert")
	assert_eq(profile["segment_best_times"], {}, "keine Segmentzeit")
	assert_eq(profile["medals"], {}, "keine Medaille")
	assert_eq(profile["ghosts"], {}, "kein Ghost")
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride["mode"], SaveGame.MODE_ARCADE)
	assert_gt(ride["distance_km"], 10.0, "km im Fahrtenbuch")
	assert_gt(game.save_game.total_km(), 10.0, "km zählen fürs Fahrerlevel")
	assert_gt(game.ride_level, 1, "Fahrerlevel gestiegen")
	assert_true(game.save_game.achievements().has("km_10"), "Erfolg „10 km gesamt“")
	assert_true(game.save_game.achievements().has("laps_1"), "Runden-Erfolg")
	assert_eq(game.logbook.MODE_NAMES[SaveGame.MODE_ARCADE], "Arcade", "Fahrtenbuch zeigt den Modus")


# --- Simulator-Szenarien (bridge/profiles/arcade) ----------------------------------------------------------------


## Spielt das Bridge-Profil `name` (unter bridge/profiles/arcade) über den Fake-Bus durch das Spiel – Arcade aus dem
## Menü, Stufe 1, Kadenzbereich 60–120 rpm – in festen Schritten, gleichauf mit dem Drehbuch. Liefert je Schritt
## {state, distance_m, active, progress, block_s, results} und die Einblendungen (letzter Eintrag `shown`).
func _play_profile(name: String, challenge: String = "zone_mitte") -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)  # verbinden; das Drehbuch steht noch bei 0 s
	await _start_arcade(game, 1, 60.0, 120.0, challenge)
	game.set_process(false)
	var steps := []
	var shown := []
	for i in range(roundi((SimProfile.duration_s(profile) + 1.0) / DT)):
		bus.manual_clock_ms += roundi(DT * 1000.0)
		bus.poll()
		await get_tree().process_frame
		game.bus.poll(DT)
		game._update_state()
		if game.state == "riding":
			game._ride(DT)
		game._update_view()
		var block: ChallengeBlock = game.arcade.active.get("block")
		steps.append({"i": i, "state": game.state, "distance_m": game.model.distance_m, "active": block != null,
				"progress": block.progress() if block != null else NAN,
				"block_s": block.elapsed_s if block != null else NAN, "results": game.arcade.results.size()})
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return {"game": game, "steps": steps, "shown": shown}


func test_scenario_perfect_in_the_zone() -> void:
	var run := await _play_profile("zone_perfekt.toml")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1, "eine Herausforderung gespielt")
	assert_true(game.arcade.results[0]["succeeded"], "90 rpm in 80–100 rpm: geschafft")
	assert_eq(game.arcade.points, 100)
	assert_has(run["shown"], "Zone halten geschafft!  +100 Punkte")
	var done: int = run["steps"].map(func(s): return s["results"]).find(1)
	assert_eq(run["steps"][done]["state"], "riding", "Erfolg in voller Fahrt")
	assert_gt(run["steps"][done + 20]["distance_m"], run["steps"][done]["distance_m"], "die Fahrt geht weiter")


func test_scenario_just_missed_fails_softly() -> void:
	var run := await _play_profile("zone_knapp_daneben.toml")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "102 rpm bei 80–100 rpm: verfehlt")
	assert_eq(result["progress"], 0.0)
	assert_eq(game.arcade.points, 0, "keine Punkte")
	assert_has(run["shown"], "Zone halten verfehlt – weiter geht's", "weich: nur eine Einblendung")
	var done: int = run["steps"].map(func(s): return s["results"]).find(1)
	assert_eq(run["steps"][done]["state"], "riding", "kein Abbruch, kein Ergebnis")
	assert_gt(run["steps"][done + 50]["distance_m"], run["steps"][done]["distance_m"] + 30.0, "die Fahrt geht weiter")
	assert_eq(run["steps"][done + 50]["state"], "riding")


func test_scenario_connection_loss_pauses_the_challenge() -> void:
	var run := await _play_profile("zone_abbruch.toml")
	var game: Node = run["game"]
	var steps: Array = run["steps"]
	var paused := steps.filter(func(s): return s["state"] == "paused_connection" and s["active"])
	assert_gt(paused.size() * DT, 30.0, "Pause länger als das Zeitfenster (30 s), mitten in der Herausforderung")
	var during := {}
	for s in paused:
		during[[s["progress"], s["block_s"], s["distance_m"], s["results"]]] = true
	assert_eq(during.keys(), [[paused[0]["progress"], paused[0]["block_s"], paused[0]["distance_m"], 0]],
			"in der Pause läuft nichts weiter, nichts scheitert (Abbruch ist keine Kadenz 0)")
	assert_between(paused[0]["progress"], 0.3, 0.9, "unterbrochen mitten im Halten")
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "nach der Rückkehr geschafft")
	assert_eq(game.arcade.points, 100)
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_gt(done, paused[-1]["i"], "geschafft erst nach der Pause")


# --- Durchbruch und Jagd in der Fahrt (#47) ----------------------------------------------------------------------


## Fahrt mit gleichbleibender Kadenz `cadence` bis kurz vor die Herausforderung `id` (Stufe 1, Bereich 60–120 rpm).
func _start_challenge(id: String, cadence: float) -> Node:
	var game := _spawn_game([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 60.0))
	await _start_arcade(game, 1, 60.0, 120.0, id)
	await _until_riding(game)
	_ride(game, 1.0)
	return game


func test_breakthrough_shows_a_drawbridge_that_opens_with_the_bar() -> void:
	var game := await _start_challenge("durchbruch_bruecke", 114.0)
	assert_string_contains(game.hud.readout(), "Ziel: ab 108 rpm", "Schwelle statt Zone")
	assert_eq(game.arcade_start_gate.text, "Start  ab 108 rpm")
	assert_false(game.arcade_bridge.visible, "vor dem Start keine Brücke")
	_ride_to_challenge(game)
	var block: Breakthrough = game.arcade.active["block"]
	assert_eq(block.zone(), Vector2(108.0, 120.0))
	_ride(game, 3.0)
	var hud: String = game.hud.readout()
	assert_string_contains(hud, "Herausforderung: Durchbruch")
	assert_string_contains(hud, "Balken: 50 %", "Balken statt Fortschritt")
	assert_string_contains(hud, "Zone: im Bereich (108–120 rpm, 114 rpm)")
	assert_true(game.arcade_bridge.visible, "die Zugbrücke steht am Ende des Zeitfensters")
	assert_false(game.arcade_finish_gate.visible, "die Brücke ist das Ziel, kein Zieltor")
	assert_almost_eq(game.arcade_bridge.target, 0.5, 0.01, "sie senkt sich mit dem Balken")
	var shown := _ride(game, 4.0)
	assert_has(shown, "Durchbruch geschafft!  +140 Punkte")
	assert_eq(game.arcade.points, 140)
	assert_eq(game.arcade_bridge.target, 1.0, "nach dem Erfolg ganz offen")
	assert_eq(game.arcade_bridge.speed, Drawbridge.SUCCESS_SPEED)
	await run_for(1.2)
	assert_eq(game.arcade_bridge.open, 1.0, "die Klappe liegt auf der Straße")
	assert_eq(game.state, "riding", "die Fahrt geht weiter")


func test_breakthrough_missed_opens_the_bridge_anyway_without_reward() -> void:
	var game := await _start_challenge("durchbruch_bruecke", 100.0)
	_ride_to_challenge(game)
	var shown := _ride(game, 19.0)
	assert_has(shown, "Durchbruch verfehlt – weiter geht's", "weich")
	assert_eq(game.arcade.points, 0)
	assert_eq(game.arcade.results[0]["progress"], 0.0, "der Balken blieb leer")
	assert_eq(game.arcade.results[0]["loot"], {}, "keine Beute")
	assert_eq(game.arcade_bridge.target, 1.0, "die Brücke öffnet sich trotzdem …")
	assert_eq(game.arcade_bridge.speed, Drawbridge.FAIL_SPEED, "… nur langsamer")
	assert_eq(game.state, "riding")
	var before: float = game.model.distance_m
	_ride(game, 5.0)
	assert_gt(game.model.distance_m, before + 20.0, "die Fahrt geht weiter")


func test_chase_shows_a_pursuer_who_falls_back_when_escaped() -> void:
	var game := await _start_challenge("jagd_verfolger", 100.0)
	assert_string_contains(game.hud.readout(), "Ziel: ab 93 rpm")
	assert_false(game.arcade_pursuer.visible, "vor der Jagd kein Verfolger")
	_ride_to_challenge(game)
	_ride(game, 1.0)
	assert_true(game.arcade_pursuer.active)
	assert_string_contains(game.hud.readout(), "Abstand: ", "Abstand statt Fortschritt")
	var near: float = game.arcade_pursuer.target_behind_m
	_ride(game, 3.0)
	assert_gt(game.arcade_pursuer.target_behind_m, near, "wer über der Schwelle tritt, lässt ihn zurück")
	assert_true(game.arcade_pursuer.visible)
	var shown := _ride(game, 6.0)
	assert_has(shown, "Jagd geschafft!  +140 Punkte")
	assert_true(game.arcade_pursuer.leaving, "abgehängt: er zieht ab")
	await run_for(5.0)
	assert_false(game.arcade_pursuer.visible, "und verschwindet")
	assert_eq(game.state, "riding")


func test_chase_caught_pursuer_closes_in_and_leaves_without_reward() -> void:
	var game := await _start_challenge("jagd_verfolger", 80.0)
	_ride_to_challenge(game)
	_ride(game, 1.0)
	var start: float = game.arcade_pursuer.target_behind_m
	_ride(game, 2.0)
	assert_lt(game.arcade_pursuer.target_behind_m, start, "unter der Schwelle holt er auf")
	var shown := _ride(game, 4.0)
	assert_has(shown, "Jagd verfehlt – weiter geht's")
	assert_eq(game.arcade.points, 0)
	assert_eq(game.arcade.results[0]["loot"], {})
	assert_eq(game.arcade.results[0]["progress"], 0.0, "eingeholt")
	assert_true(game.arcade_pursuer.leaving, "weich: er zieht ab")
	assert_eq(game.state, "riding")
	await run_for(6.0)
	assert_false(game.arcade_pursuer.visible)


func test_props_vanish_with_the_menu() -> void:
	var game := await _start_challenge("jagd_verfolger", 100.0)
	_ride_to_challenge(game)
	_ride(game, 1.0)
	assert_true(game.arcade_pursuer.visible)
	game.settings_menu.ride_end_requested.emit()
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")
	game._update_view()
	assert_false(game.arcade_pursuer.visible)
	assert_false(game.arcade_bridge.visible)


## Beginnt die nächste Herausforderung im selben Schritt, in dem die vorige endet (ihr Startpunkt lag schon hinter dem
## Fahrer), muss der Verfolger trotzdem abziehen und die Brücke sich öffnen.
func test_pursuer_is_dismissed_when_the_next_challenge_starts_in_the_same_step() -> void:
	var next := {"definition": Encounters.find("zone_mitte"), "at_m": 0.0, "end_m": 1.0e9, "section": "x", "lap": 0}
	var game := await _start_challenge("jagd_verfolger", 100.0)
	_ride_to_challenge(game)
	game.arcade.planned.push_front(next)
	_ride(game, 14.0)
	assert_eq(game.arcade.results.size(), 1, "die Jagd ist beendet")
	assert_eq(game.arcade.active["definition"]["id"], "zone_mitte", "die nächste begann sofort")
	assert_true(game.arcade_pursuer.leaving, "der Verfolger zieht ab, statt stehen zu bleiben")


func test_bridge_is_released_when_the_next_challenge_starts_in_the_same_step() -> void:
	var next := {"definition": Encounters.find("zone_mitte"), "at_m": 0.0, "end_m": 1.0e9, "section": "x", "lap": 0}
	var game := await _start_challenge("durchbruch_bruecke", 114.0)
	_ride_to_challenge(game)
	game.arcade.planned.push_front(next)
	_ride(game, 8.0)
	assert_eq(game.arcade.active["definition"]["id"], "zone_mitte", "die nächste begann sofort")
	assert_eq([game.arcade_bridge.target, game.arcade_bridge.speed], [1.0, Drawbridge.SUCCESS_SPEED],
			"die Brücke öffnet sich")


func test_scenario_breakthrough_made() -> void:
	var run := await _play_profile("durchbruch_geschafft.toml", "durchbruch_bruecke")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "8 s mit 114 rpm über 108 rpm: geschafft")
	assert_eq(game.arcade.points, 140)
	assert_has(run["shown"], "Durchbruch geschafft!  +140 Punkte")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding", "Erfolg in voller Fahrt")
	assert_gt(steps[done + 20]["distance_m"], steps[done]["distance_m"], "die Fahrt geht weiter")
	assert_eq(game.arcade_bridge.target, 1.0, "die Brücke ist offen")


func test_scenario_breakthrough_too_weak() -> void:
	var run := await _play_profile("durchbruch_zu_schwach.toml", "durchbruch_bruecke")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "104 rpm unter 108 rpm: verfehlt")
	assert_eq(result["progress"], 0.0)
	assert_eq(result["loot"], {})
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Durchbruch verfehlt – weiter geht's")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding")
	assert_gt(steps[done + 30]["distance_m"], steps[done]["distance_m"] + 10.0, "die Fahrt geht weiter")
	assert_eq(game.arcade_bridge.target, 1.0, "die Brücke öffnet sich trotzdem")


func test_scenario_chase_escaped() -> void:
	var run := await _play_profile("jagd_entkommen.toml", "jagd_verfolger")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "14 s mit 100 rpm über 93 rpm: abgehängt")
	assert_eq(game.arcade.points, 140)
	assert_false(game.arcade.results[0]["loot"].is_empty(), "geschafft: Beute")
	assert_has(run["shown"], "Jagd geschafft!  +140 Punkte")
	assert_true(game.arcade_pursuer.leaving)
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding")
	assert_gt(steps[done + 20]["distance_m"], steps[done]["distance_m"])


func test_scenario_chase_caught() -> void:
	var run := await _play_profile("jagd_eingeholt.toml", "jagd_verfolger")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "80 rpm unter 93 rpm: eingeholt")
	assert_eq(result["progress"], 0.0)
	assert_eq(result["loot"], {}, "keine Beute")
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Jagd verfehlt – weiter geht's")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding", "weich: kein Abbruch")
	assert_gt(steps[done + 30]["distance_m"], steps[done]["distance_m"] + 20.0)
	assert_true(game.arcade_pursuer.leaving, "er zieht ab")
