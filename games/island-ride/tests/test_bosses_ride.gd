## Bosse (#51) gegen den Fake-Bus durch die echte Hauptszene: die Simulator-Szenarien der Bridge
## (`bridge/profiles/arcade/boss_*.toml`) mit genau ihrem Kadenzverlauf – „Abbruch mitten im Bosskampf“ → Pause, Lebensbalken
## und Phase stehen, danach Weiterfahrt und Sieg; Tramuntana, Drac de na Coca und Dimonis besiegt (Punkte, Boss-Beute,
## Zusammenfassung), Dimonis entkommen (weich: keine Punkte, keine Beute, die Fahrt geht weiter). Dazu die Darstellung
## (Gestalt voraus, Lebensbalken im HUD, Zusammensinken bzw. Davonziehen) und die festen Orte auf dem Rundkurs. Auf der
## Graybox gibt es keine festen Orte: die Tests erzwingen den Boss über den Pool (wie die übrigen Szenarien).
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_bosses_ride_savegame.json")
const DT := 0.1
const BOSSES := preload("res://src/challenges/boss_challenges.gd")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _spawn_on(bus: FakeBusServer, track: String = "") -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus, RideConfig.DEFAULT_PATH, track) if not track.is_empty() else config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Arcade“, Stufe 1, 60–120 rpm, „Losfahren“ – mit festem Würfel und nur dem Boss `boss` im Pool (auf der Graybox
## gibt es keine festen Orte). Fähigkeiten (#50) sind hier nicht der Gegenstand: konstante Kadenz löste den Fokus aus.
func _start_arcade(game: Node, boss: String) -> void:
	await run_for(0.2)
	AbilityExtension.of(game.arcade_stage).enabled = false
	game.arcade_seed = 1
	game.arcade_pool = [BOSSES.find(boss)]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	menu.buttons["arcade_start"].pressed.emit()


func _prop(game: Node) -> BossProp:
	return game.arcade_stage.props["boss"]


## Spielt das Profil `name` mit dem Boss `boss` im Gleichschritt durchs Spiel; je Schritt Zustand, Weg, Kampfstand
## (Lebensbalken, Phase, Zeit) und die Anzeige (Balken, Gestalt).
func _play_profile(name: String, boss: String) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)  # verbinden; das Drehbuch steht noch bei 0 s
	await _start_arcade(game, boss)
	assert_eq(game.arcade.tier, 1)
	game.set_process(false)
	var steps := []
	var shown := []
	var ends := []
	for i in range(roundi((SimProfile.duration_s(profile) + 1.0) / DT)):
		bus.manual_clock_ms += roundi(DT * 1000.0)
		bus.poll()
		await get_tree().process_frame
		game.bus.poll(DT)
		game._update_state()
		if game.state == "riding":
			game._ride(DT)
		game._update_view()
		var fight: BossFight = game.arcade.active.get("block") as BossFight
		var prop := _prop(game)
		steps.append({"i": i, "state": game.state, "distance_m": game.model.distance_m, "active": fight != null,
				"health": fight.health() if fight != null else NAN,
				"phase": fight.phase_number() if fight != null else 0,
				"block_s": fight.elapsed_s if fight != null else NAN, "results": game.arcade.results.size(),
				"bar": prop.bar.title_text(), "line": prop.bar.phase_text(), "figure": prop.figure.state,
				"ahead_m": prop.figure.target_ahead_m})  # Ziel; die Gestalt gleitet in Echtzeit (_process) dorthin
		if game.arcade.results.size() > ends.size():
			ends.append({"i": i, "bar": prop.bar.title_text(), "figure": prop.figure.state})
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return {"game": game, "steps": steps, "shown": shown, "ends": ends}


func _fighting(steps: Array) -> Array:
	return steps.filter(func(s): return s["active"])


# --- Abbruch mitten im Bosskampf ------------------------------------------------------------------------------------


func test_scenario_connection_loss_in_a_boss_fight_pauses_it() -> void:
	var run := await _play_profile("boss_abbruch.toml", "tramuntana")
	var game: Node = run["game"]
	var steps: Array = run["steps"]
	var paused := steps.filter(func(s): return s["state"] == "paused_connection" and s["active"])
	assert_gt(paused.size() * DT, 30.0, "Pause länger als das Zeitfenster der Phase (20 s), mitten im Kampf")
	var during := {}
	for s in paused:
		during[[s["health"], s["phase"], s["block_s"], s["distance_m"], s["results"], s["bar"], s["line"]]] = true
	assert_eq(during.size(), 1, "in der Pause stehen Lebensbalken, Phase und Zeit – nichts läuft weiter, nichts scheitert")
	assert_eq(paused[0]["phase"], 1, "unterbrochen im Gegenwind")
	assert_between(paused[0]["health"], 0.7, 0.95, "der Boss ist schon getroffen")
	assert_eq(paused[0]["bar"], "Tramuntana", "der Lebensbalken bleibt zu sehen")
	assert_string_contains(paused[0]["line"], "Phase 1/3 · Gegenwind · 80–100 rpm")
	assert_eq(paused[0]["figure"], BossFigure.FIGHT, "der Sturmgeist bleibt stehen")
	# Danach: Weiterfahrt und Fortsetzung bis zum Sieg.
	var after := steps.filter(func(s): return s["i"] > paused[-1]["i"])
	assert_eq(after[after.size() - 1]["state"], "paused_connection", "das Profil endet (Quelle beendet)")
	var resumed := after.filter(func(s): return s["state"] == "riding")
	assert_false(resumed.is_empty(), "Weiterfahrt nach der Rückkehr")
	assert_gt(resumed[-1]["distance_m"], paused[0]["distance_m"] + 100.0, "die Fahrt geht weiter")
	assert_lt(resumed.filter(func(s): return s["active"])[0]["health"], paused[0]["health"] + 1e-6,
			"der Kampf geht mit demselben Lebensbalken weiter")
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "nach der Rückkehr besiegt")
	assert_eq(game.arcade.points, 400)
	assert_gt(run["ends"][0]["i"], paused[-1]["i"], "besiegt erst nach der Pause")


# --- Besiegt -------------------------------------------------------------------------------------------------------


func test_scenario_tramuntana_defeated() -> void:
	var run := await _play_profile("boss_tramuntana.toml", "tramuntana")
	var game: Node = run["game"]
	var fight := _fighting(run["steps"])
	assert_eq(fight.map(func(s): return s["phase"]).reduce(func(a, b): return maxi(a, b), 0), 3, "alle drei Phasen")
	var healths: Array = fight.map(func(s): return s["health"])
	for k in range(1, healths.size()):
		assert_true(healths[k] <= healths[k - 1] + 1e-6, "der Lebensbalken steigt nie (Schritt %d)" % k)
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_true(result["boss"])
	assert_true(result["succeeded"], "besiegt")
	assert_eq(game.arcade.points, 400)
	assert_false(result["loot"].is_empty(), "Boss-Beute")
	assert_has(run["shown"], "Tramuntana geschafft!  +400 Punkte")
	assert_eq(run["ends"][0]["bar"], "Tramuntana besiegt!", "der Lebensbalken meldet den Sieg")
	assert_eq(run["ends"][0]["figure"], BossFigure.DEFEATED, "der Sturmgeist sinkt zusammen")
	var done: int = run["ends"][0]["i"]
	assert_gt(run["steps"][done + 30]["distance_m"], run["steps"][done]["distance_m"] + 10.0, "die Fahrt geht weiter")
	game.return_to_menu()
	var text: String = game.arcade_result()
	assert_string_contains(text, "Bosse: Tramuntana besiegt", "die Zusammenfassung nennt den Boss")
	assert_string_contains(text, "Beute: ")
	assert_eq(_prop(game).bar.title_text(), "", "im Menü kein Lebensbalken")
	assert_false(_prop(game).figure.visible)


func test_scenario_drac_de_na_coca_defeated() -> void:
	var run := await _play_profile("boss_drac.toml", "drac")
	var game: Node = run["game"]
	var phases := {}
	for s in _fighting(run["steps"]):
		phases[s["phase"]] = true
	assert_eq(phases.keys(), [1, 2, 3, 4], "der große Kampf: vier Phasen")
	assert_true(game.arcade.results[0]["succeeded"])
	assert_eq(game.arcade.points, 600)
	assert_eq(run["ends"][0]["bar"], "Drac de na Coca besiegt!")
	assert_has(run["shown"], "Drac de na Coca geschafft!  +600 Punkte")


func test_scenario_dimonis_caught_up() -> void:
	var run := await _play_profile("boss_dimonis_besiegt.toml", "dimonis")
	var game: Node = run["game"]
	var chase := _fighting(run["steps"]).filter(func(s): return s["phase"] == 1)
	assert_gt(chase[0]["ahead_m"], chase[-1]["ahead_m"] + 15.0, "die Dimonis kommen näher, je dichter der Fahrer dran ist")
	assert_true(game.arcade.results[0]["succeeded"], "eingeholt: besiegt")
	assert_eq(game.arcade.points, 450)
	assert_eq(run["ends"][0]["figure"], BossFigure.DEFEATED)


# --- Entkommen -----------------------------------------------------------------------------------------------------


func test_scenario_dimonis_escape_softly() -> void:
	var run := await _play_profile("boss_dimonis_entkommen.toml", "dimonis")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "85 rpm unter 93: die Dimonis entwischen")
	assert_eq(result["points"], 0, "keine Punkte")
	assert_eq(result["loot"], {}, "kein Schaden – keine Beute")
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Dimonis verfehlt – weiter geht's", "weich: nur eine Einblendung")
	assert_eq(run["ends"][0]["bar"], "Dimonis entkommen")
	assert_eq(run["ends"][0]["figure"], BossFigure.ESCAPING, "sie ziehen davon")
	var done: int = run["ends"][0]["i"]
	assert_eq(run["steps"][done]["state"], "riding", "kein Abbruch")
	assert_gt(run["steps"][done + 50]["distance_m"], run["steps"][done]["distance_m"] + 30.0, "die Fahrt geht weiter")
	game.return_to_menu()
	assert_string_contains(game.arcade_result(), "Bosse: Dimonis entkommen")


# --- Feste Orte im Spiel ---------------------------------------------------------------------------------------------


func test_bosses_wait_at_their_stations_on_the_island() -> void:
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]), RideConfig.TRACK_ISLAND)
	await run_for(0.3)
	game.arcade_seed = 1
	game.start_ride(SaveGame.MODE_ARCADE, 0, "", {}, Track.DIRECTION_CW, 1)
	var bosses := {}
	for entry in game.arcade.planned:
		if entry["definition"]["block"] == BOSSES.ID and entry["lap"] == 0:
			bosses[entry["definition"]["id"]] = entry["section"]
	assert_eq(bosses, {"tramuntana": "Küstenstraße", "drac": "Serpentinen", "dimonis": "Bergdorf"})
	var at: float = game.arcade.planned.filter(func(e): return e["definition"]["id"] == "tramuntana")[0]["at_m"]
	assert_eq(game.track.ride_station_at(at)["name"], "Küstenstraße", "Startpunkt im Abschnitt")


# --- Darstellung ---------------------------------------------------------------------------------------------------


func test_the_figure_shrinks_with_its_life_sinks_when_defeated_and_escapes_ahead() -> void:
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.3)
	var figure := BossFigure.new()
	figure.set_process(false)  # Zeit nur über die Aufrufe unten
	game.track.add_child(figure)
	figure.appear(BossFigure.DRAC)
	figure.follow(game.track, 100.0, BossFigure.AHEAD_M[BossFigure.DRAC], 1.0, false)
	assert_true(figure.visible)
	assert_eq(figure.ride_m(), 124.0, "der Drache steht voraus")
	var full: float = BossFigure.SCALE[BossFigure.DRAC]
	assert_almost_eq(figure.size_factor(), full, 0.001)
	figure.follow(game.track, 100.0, BossFigure.AHEAD_M[BossFigure.DRAC], 0.0, false)
	assert_almost_eq(figure.size_factor(), BossFigure.SMALLEST * full, 0.001, "leerer Lebensbalken: kleiner")
	figure.defeat()
	figure.track_rider(110.0)
	figure._process(BossFigure.DEFEAT_S / 2.0)
	assert_eq(figure.ride_m(), 124.0, "besiegt: er sinkt an seiner Stelle zusammen")
	assert_almost_eq(figure.size_factor(), BossFigure.SMALLEST * full / 2.0, 0.01)
	figure._process(BossFigure.DEFEAT_S)
	assert_eq(figure.state, "")
	assert_false(figure.visible, "verschwunden")
	figure.appear(BossFigure.DIMONIS)
	figure.follow(game.track, 200.0, 16.0, 1.0, false)
	figure.escape()
	figure._process(1.0)
	assert_eq(figure.state, BossFigure.ESCAPING)
	assert_almost_eq(figure.ahead_m, 16.0 + BossFigure.ESCAPE_MPS, 0.001, "entkommen: sie ziehen voraus davon")
	figure._process(BossFigure.ESCAPE_S)
	assert_false(figure.visible, "außer Sicht")
	figure.free()
