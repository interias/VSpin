## Kadenzmuster und Fähigkeiten (#50) gegen den Fake-Bus durch die echte Hauptszene: die Simulator-Szenarien der Bridge
## (`bridge/profiles/arcade/antritt|innehalten|gleichmass|rhythmus.toml`) laufen mit genau ihrem Kadenzverlauf durch das
## Spiel – erkannt wird das Muster aus `cadence_raw`, die Fähigkeit wird ausgelöst, die Anzeige zeigt „aktiv“ und danach die
## Abklingzeit, und im laufenden Baustein ist die Wirkung zu sehen. Dazu: die Muster nutzen die ungeglättete Kadenz, in
## Rundfahrt und Training passiert nichts (ADR-0010), die Leiste ist nur im Arcade-Lauf zu sehen.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_abilities_ride_savegame.json")
const DT := 0.1
## Lange Herausforderungen, die während des ganzen Profils laufen (Zone 75–95 rpm bzw. Schwelle 102 rpm in 60–120 rpm).
const LONG_ZONE := {"id": "t_long_zone", "block": "zone_hold", "name": "Zone halten", "zone_rpm": [75, 95],
		"hold_s": 400.0, "window_s": 600.0, "points": 100}
const LONG_CHASE := {"id": "t_long_chase", "block": "chase", "name": "Jagd", "threshold_at": 0.7, "escape_s": 100.0,
		"catch_s": 100.0, "window_s": 600.0, "start_gap": 0.5, "points": 100}


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _spawn_on(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


func _select(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)


## „Fahren → Arcade“, Stufe 1, Kadenzbereich 60–120 rpm, „Losfahren“ – mit festem Würfel und nur der Herausforderung
## `definition`.
func _start_arcade(game: Node, definition: Dictionary) -> void:
	await run_for(0.2)
	game.arcade_seed = 1
	game.arcade_pool = [definition]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	_select(menu.options["tier"], 0)
	_select(menu.options["cadence_min"], CadenceRange.MIN_CHOICES.find(60.0))
	_select(menu.options["cadence_max"], CadenceRange.MAX_CHOICES.find(120.0))
	menu.buttons["arcade_start"].pressed.emit()


func _extension(game: Node) -> AbilityExtension:
	return AbilityExtension.of(game.arcade_stage)


## Ein Schritt der Aufzeichnung: Zeit, läuft eine Herausforderung, Fähigkeiten, Anzeige, Faktor und Fortschritt des Bausteins.
func _record(game: Node, extension: AbilityExtension, t: float) -> Dictionary:
	var block: ChallengeBlock = game.arcade.active["block"] if game.arcade != null and not game.arcade.active.is_empty() else null
	var states := {}
	for id in Abilities.IDS:
		states[id] = extension.view.chip_state(id)
	return {"t": t, "block": block != null, "counts": extension.abilities.counts.duplicate(), "states": states,
			"flash": extension.view.flash_text(), "factor": block.progress_factor if block != null else 0.0,
			"progress": block.progress() if block != null else -1.0, "points": game.arcade.points if game.arcade != null else 0,
			"popups": game.hud.popups(), "shown": extension.view.visible}


## Spielt das Bridge-Profil `name` (unter bridge/profiles/arcade) über den Fake-Bus durch das Spiel (Arcade, die einzige
## Herausforderung `definition`) in festen Schritten, gleichauf mit dem Drehbuch (wie test_arcade_ride.gd). `tweak` darf nach
## dem Start an den Fähigkeiten drehen. Liefert Spiel, Erweiterung und je Schritt die Aufzeichnung.
func _play_profile(name: String, definition: Dictionary, tweak: Callable = Callable()) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)  # verbinden; das Drehbuch steht noch bei 0 s
	await _start_arcade(game, definition)
	game.set_process(false)
	var extension := _extension(game)
	if tweak.is_valid():
		tweak.call(extension)
	var steps := []
	for i in range(roundi((SimProfile.duration_s(profile) + 0.5) / DT)):
		bus.manual_clock_ms += roundi(DT * 1000.0)
		bus.poll()
		await get_tree().process_frame
		game.bus.poll(DT)
		game._update_state()
		if game.state == "riding":
			game._ride(DT)
		game._update_view()
		steps.append(_record(game, extension, (i + 1) * DT))
	return {"game": game, "extension": extension, "steps": steps}


## Erster Schritt, in dem `condition` wahr ist (-1 = nie).
func _first(steps: Array, condition: Callable) -> int:
	for i in range(steps.size()):
		if condition.call(steps[i]):
			return i
	return -1


func _seen(steps: Array, condition: Callable) -> bool:
	return _first(steps, condition) >= 0


# --- Simulator-Szenario „Antritt“ ----------------------------------------------------------------------------------


func test_scenario_antritt_triggers_windboe_shows_it_and_speeds_up_the_block() -> void:
	var played := await _play_profile("antritt.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var first := _first(steps, func(s): return s["counts"]["windboe"] >= 1)
	assert_gte(first, 0, "die Windböe wurde ausgelöst")
	assert_true(steps[first]["block"], "und zwar in einer laufenden Herausforderung")
	assert_eq(steps[first]["flash"], "Windböe ausgelöst", "Anzeige „ausgelöst“")
	assert_eq(steps[first]["states"]["windboe"], "active", "die Plakette zeigt „aktiv“")
	assert_gte(steps[first]["factor"], 3.0, "Wirkung im Baustein: Fortschritt in der Zone ×3")
	assert_true(_seen(steps, func(s): return s["states"]["windboe"] == "cooldown"), "danach die Abklingzeit")
	assert_eq(steps[0]["states"]["windboe"], "ready", "am Anfang bereit")
	var after := steps.slice(first + roundi(2.6 / DT))  # die Wirkdauer (2,5 s) ist um
	assert_eq(after[0]["factor"], 1.0, "danach wieder der Ausgangsfaktor")
	# keine Auslösung ohne laufende Herausforderung: der erste Antritt (6 s) kommt, bevor der Startpunkt erreicht ist
	var triggers := steps.filter(func(s): return s["counts"]["windboe"] > 0 and not s["block"])
	assert_eq(triggers.size(), 0, "Fähigkeiten gibt es nur in Herausforderungen")
	assert_eq(steps[first]["counts"]["fokus"] + steps[first]["counts"]["schild"] + steps[first]["counts"]["kombo"], 0,
			"nur die Windböe, nicht die anderen")


func test_scenario_antritt_before_the_challenge_leaves_the_ability_ready() -> void:
	var played := await _play_profile("antritt.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var start := _first(steps, func(s): return s["block"])
	assert_gt(start, roundi(6.4 / DT), "der Startpunkt liegt hinter dem ersten Antritt (6 s)")
	assert_eq(steps[start]["states"]["windboe"], "ready", "der erste Antritt hat nichts verbraucht")
	assert_eq(steps[start]["counts"]["windboe"], 0)


# --- Simulator-Szenario „Innehalten“ -------------------------------------------------------------------------------


func test_scenario_innehalten_triggers_schild_and_the_chaser_does_not_close_in() -> void:
	var shielded := await _play_profile("innehalten.toml", LONG_CHASE)
	var steps: Array = shielded["steps"]
	var first := _first(steps, func(s): return s["counts"]["schild"] >= 1)
	assert_gte(first, 0, "das Schild wurde ausgelöst")
	assert_true(steps[first]["block"], "in der laufenden Jagd")
	assert_eq(steps[first]["flash"], "Schild ausgelöst")
	assert_eq(steps[first]["states"]["schild"], "active")
	assert_eq(steps[0]["states"]["schild"], "ready")
	assert_true(_seen(steps, func(s): return s["states"]["schild"] == "cooldown"))
	# solange das Schild hält (6 s), sinkt der Abstand nie
	var held := steps.slice(first, first + roundi(5.5 / DT))
	for i in range(1, held.size()):
		assert_gte(held[i]["progress"], held[i - 1]["progress"] - 1e-9, "unter dem Schild kein Verlust (Schritt %d)" % i)
	# Gegenprobe: dasselbe Szenario ohne Schild (Wirkdauer 0) verliert Abstand
	var open := await _play_profile("innehalten.toml", LONG_CHASE, func(extension: AbilityExtension):
		extension.abilities.defs["schild"]["duration_s"] = 0.0)
	var last := roundi(23.0 / DT)  # kurz vor dem Ablauf des Schildes (die erste Pause liegt vor der Jagd, die zweite löst aus)
	assert_gt(shielded["steps"][last]["progress"], open["steps"][last]["progress"] + 0.02,
			"mit Schild mehr Abstand als ohne")


func test_scenario_innehalten_second_pause_is_in_cooldown_and_the_short_rest_counts_not() -> void:
	var played := await _play_profile("innehalten.toml", LONG_CHASE)
	var steps: Array = played["steps"]
	assert_eq(steps[-1]["counts"]["schild"], 1, "zwei Pausen von 3 s: das Schild kühlt noch ab (30 s), das Absetzen von 1,5 s zählt nicht")


# --- Gleichmaß und Rhythmus ----------------------------------------------------------------------------------------


func test_scenario_gleichmass_triggers_fokus_after_ten_calm_seconds_not_from_standstill() -> void:
	var played := await _play_profile("gleichmass.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var first := _first(steps, func(s): return s["counts"]["fokus"] >= 1)
	assert_gte(first, 0, "Fokus ausgelöst")
	assert_gt(steps[first]["t"], 17.0, "nicht im Stillstand und nicht vor 10 ruhigen Sekunden")
	assert_eq(steps[first]["flash"], "Fokus ausgelöst")
	assert_almost_eq(steps[first]["factor"], 1.5, 1e-6, "Fortschritt in der Zone ×1,5")
	assert_eq(steps[first]["states"]["fokus"], "active")
	assert_true(_seen(steps, func(s): return s["states"]["fokus"] == "cooldown"))


func test_scenario_rhythmus_triggers_kombo_with_points() -> void:
	var played := await _play_profile("rhythmus.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var first := _first(steps, func(s): return s["counts"]["kombo"] >= 1)
	assert_gte(first, 0, "Kombo ausgelöst")
	assert_gt(steps[first]["t"], 6.0 + 3.0 * 3.0 - 1.0, "erst mit dem vierten Puls im Takt")
	assert_eq(steps[first]["flash"], "Kombo ausgelöst")
	assert_eq(steps[first]["points"], 30, "Punktebonus")
	assert_has(steps[first]["popups"], "+30 Kombo")
	assert_eq(steps[-1]["counts"]["kombo"], 1, "die unregelmäßigen Pulse danach sind kein Takt")
	var lines := []
	for provider in played["game"].arcade_stage.summary_providers:
		lines.append_array(provider.call(played["game"].arcade))
	assert_eq(lines, ["Fähigkeiten: Kombo 1× (+30 Punkte)"], "Zeile im Fahrtergebnis")


# --- Ungeglättete Kadenz, Arcade-Grenzen -----------------------------------------------------------------------------


## Fahrt mit gleichbleibender Kadenz bis die Herausforderung `definition` läuft; ohne Prozess, Schritte von Hand.
func _start_challenge(definition: Dictionary, cadence: float) -> Node:
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 120.0)))
	await _start_arcade(game, definition)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0), "Arcade fährt")
	game.set_process(false)
	for i in range(300):
		if not game.arcade.active.is_empty():
			break
		game._ride(DT)
		game._update_view()
	assert_false(game.arcade.active.is_empty(), "die Herausforderung läuft")
	return game


func _ride(game: Node, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		game._ride(DT)
		game._update_view()


func test_patterns_read_the_unsmoothed_cadence() -> void:
	var game := await _start_challenge(LONG_ZONE, 80.0)
	var extension := _extension(game)
	_ride(game, 6.0)  # ruhig bei 80 rpm
	assert_eq(extension.abilities.counts["windboe"], 0)
	# Die geglättete Kadenz hinkt hinterher (EMA), die ungeglättete ist schon oben: der Antritt zählt sofort.
	game.bus.cadence = 88.0
	game.bus.cadence_raw = 110.0
	_ride(game, 0.2)
	assert_eq(extension.abilities.counts["windboe"], 1, "Antritt aus cadence_raw")
	assert_lt(game.bus.cadence, 100.0, "während die geglättete Kadenz noch unter +25 rpm liegt")
	# Umgekehrt: nur die geglättete Kadenz springt – kein Muster.
	var other := await _start_challenge(LONG_ZONE, 80.0)
	_ride(other, 6.0)
	other.bus.cadence = 120.0
	_ride(other, 0.5)
	assert_eq(_extension(other).abilities.counts["windboe"], 0, "die geglättete Kadenz löst nichts aus")


func test_abilities_do_nothing_in_a_round_trip() -> void:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/antritt.toml"))
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := spawn_ride(bus)  # Rundfahrt
	await run_for(0.3)
	game.set_process(false)
	var extension := _extension(game)
	assert_null(game.arcade, "kein Arcade-Lauf")
	for i in range(roundi(SimProfile.duration_s(profile) / DT)):
		bus.manual_clock_ms += roundi(DT * 1000.0)
		bus.poll()
		await get_tree().process_frame
		game.bus.poll(DT)
		game._update_state()
		if game.state == "riding":
			game._ride(DT)
		game._update_view()
		assert_false(extension.view.visible, "keine Leiste in der Rundfahrt")
	for id in Abilities.IDS:
		assert_eq(extension.abilities.counts[id], 0, "%s: nichts ausgelöst" % id)
	assert_eq(extension.view.flash_text(), "")


func test_the_bar_shows_only_during_the_arcade_run() -> void:
	var game := await _start_challenge(LONG_ZONE, 80.0)
	var extension := _extension(game)
	await get_tree().process_frame
	assert_true(extension.view.visible, "im Arcade-Lauf sichtbar")
	assert_eq(extension.view.chip_text("windboe"), "Windböe · Antritt · bereit")
	assert_eq(extension.view.chip_text("fokus"), "Fokus · Gleichmaß · bereit")
	assert_eq(extension.view.chip_text("schild"), "Schild · Innehalten · bereit")
	assert_eq(extension.view.chip_text("kombo"), "Kombo · Rhythmus · bereit")
	game.return_to_menu()  # Ergebnis
	await get_tree().process_frame
	assert_eq(game.state, "finished")
	assert_false(extension.view.visible, "im Ergebnis weg")
	game.return_to_menu()
	await get_tree().process_frame
	assert_eq(game.state, "menu")
	assert_false(extension.view.visible, "im Menü weg")


func test_a_disabled_extension_does_nothing() -> void:
	var game := await _start_challenge(LONG_ZONE, 80.0)
	var extension := _extension(game)
	extension.enabled = false
	_ride(game, 6.0)
	game.bus.cadence_raw = 120.0
	_ride(game, 0.5)
	assert_eq(extension.abilities.counts["windboe"], 0)
	await get_tree().process_frame
	assert_false(extension.view.visible)
