## Takt-Tore und Sammeln (#48) gegen den Fake-Bus durch die echte Hauptszene: Tore und Sammelobjekte stehen auf der Strecke,
## der Magnetring folgt der Kadenz, Treffer/Verpasst und Einsammeln sind zu sehen, und die Simulator-Szenarien der Bridge
## (`bridge/profiles/arcade/takt_*.toml`, `sammeln_*.toml`) laufen mit genau ihrem Kadenzverlauf durch das Spiel:
## Takt getroffen → geschafft (Punkte, Beute), Takt verfehlt → weich verfehlt, Sammeln viel → geschafft, Sammeln wenig →
## weich verfehlt (je ohne Punkte und Beute, die Fahrt geht weiter).
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_arcade_rhythm_collect_ride_savegame.json")
const DT := 0.1


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
## `challenge`, damit das Ergebnis vorhersagbar ist.
func _start_arcade(game: Node, challenge: String) -> void:
	await run_for(0.2)
	AbilityExtension.of(game.arcade_stage).enabled = false  # Fähigkeiten (#50) sind hier nicht der Gegenstand
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find(challenge)]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	_select(menu.options["tier"], 0)
	_select(menu.options["cadence_min"], CadenceRange.MIN_CHOICES.find(60.0))
	_select(menu.options["cadence_max"], CadenceRange.MAX_CHOICES.find(120.0))
	menu.buttons["arcade_start"].pressed.emit()


## Ein Fahrschritt wie in der Hauptszene (feste Schritte, kein Bus): Fahrmodell, Lauf, Anzeige.
func _ride(game: Node, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		if game.state != "riding":
			break
		game._ride(DT)
		game._update_view()


## Fahrt mit gleichbleibender Kadenz `cadence` bis die Herausforderung `id` läuft.
func _start_challenge(id: String, cadence: float) -> Node:
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 120.0)))
	await _start_arcade(game, id)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0), "Arcade fährt")
	game.set_process(false)
	for i in range(300):
		if not game.arcade.active.is_empty():
			break
		_ride(game, DT)
	assert_false(game.arcade.active.is_empty(), "die Herausforderung läuft")
	return game


## Spielt das Bridge-Profil `name` (unter bridge/profiles/arcade) über den Fake-Bus durch das Spiel – Arcade aus dem Menü,
## Stufe 1, Kadenzbereich 60–120 rpm – in festen Schritten, gleichauf mit dem Drehbuch (wie test_arcade_ride.gd). Liefert
## je Schritt {state, distance_m, results} und die Einblendungen.
func _play_profile(name: String, challenge: String) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)  # verbinden; das Drehbuch steht noch bei 0 s
	await _start_arcade(game, challenge)
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
		steps.append({"i": i, "state": game.state, "distance_m": game.model.distance_m,
				"results": game.arcade.results.size()})
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return {"game": game, "steps": steps, "shown": shown}


func _gate_texts(game: Node) -> Array:
	var prop: RhythmGatesProp = game.arcade_stage.props["rhythm_gates"]
	return prop.gates.map(func(gate: CourseGate): return gate.text)


# --- Darstellung auf der Strecke -----------------------------------------------------------------------------------


func test_rhythm_gates_stand_on_the_road_ahead_in_beat_order() -> void:
	var game := await _start_challenge("takt_ruhig", 80.0)  # 80 rpm liegt in der Zone 74–94
	var prop: RhythmGatesProp = game.arcade_stage.props["rhythm_gates"]
	var block: RhythmGates = game.arcade.active["block"]
	_ride(game, 2.0)  # Tempo ist da, das erste Tor steht innerhalb von 40 m
	var visible_gates := prop.gates.filter(func(gate: CourseGate): return gate.visible)
	assert_between(visible_gates.size(), 1, RhythmGatesProp.AHEAD, "die nächsten Tore sind zu sehen")
	var ahead: float = game.model.distance_m
	assert_gt(visible_gates[0].ride_m, ahead, "das erste Tor liegt voraus")
	for i in range(visible_gates.size() - 1):
		assert_lt(visible_gates[i].ride_m, visible_gates[i + 1].ride_m, "in Taktfolge")
	assert_eq(visible_gates[0].text, "Takt 1/5")
	assert_false(game.arcade_finish_gate.visible, "die Tore ersetzen das Zieltor")
	# Das Tor steht dort, wo der Fahrer zum Schlag ankommt: bei gleichbleibendem Tempo ist es nach der Restzeit erreicht.
	var gate_ride: float = visible_gates[0].ride_m
	var to_beat: float = block.time_to_beat(0)
	_ride(game, maxf(to_beat, 0.0))
	assert_almost_eq(game.model.distance_m, gate_ride, 4.0, "Ankunft am Tor zum Schlag")


func test_rhythm_gates_turn_green_on_a_hit_and_orange_on_a_miss() -> void:
	var game := await _start_challenge("takt_ruhig", 80.0)
	var prop: RhythmGatesProp = game.arcade_stage.props["rhythm_gates"]
	var block: RhythmGates = game.arcade.active["block"]
	while block.state_of(0) == RhythmGates.PENDING and not block.finished():
		_ride(game, DT)
	assert_eq(prop.gates[0].text, "Treffer")
	assert_eq(prop.gates[0].kind, CourseGate.KIND_START, "getroffen: grün")
	game.bus.cadence = 100.0  # über der Zone: das nächste Tor wird verpasst
	while block.state_of(1) == RhythmGates.PENDING and not block.finished():
		_ride(game, DT)
	assert_eq(prop.gates[1].text, "Verpasst")
	assert_eq(prop.gates[1].kind, CourseGate.KIND_FINISH, "verpasst: orange")
	assert_eq(prop.gates[0].text, "Treffer", "das getroffene bleibt stehen")


func test_rhythm_gates_stay_behind_the_rider_after_the_end_and_vanish_with_the_menu() -> void:
	var game := await _start_challenge("takt_ruhig", 80.0)
	var prop: RhythmGatesProp = game.arcade_stage.props["rhythm_gates"]
	for i in range(600):
		if game.arcade.active.is_empty():
			break
		_ride(game, DT)
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "80 rpm: alle in der Zone")
	assert_true(prop.covers_finish_gate(), "durchfahrene Tore stehen noch")
	assert_false(game.arcade_finish_gate.visible, "ohne das Zieltor")
	_ride(game, 8.0)
	game.arcade_stage.enter_menu()
	assert_false(prop.covers_finish_gate(), "im Menü keine Tore")


func test_collect_shows_objects_and_a_ring_that_follows_the_cadence() -> void:
	var game := await _start_challenge("sammeln_wiese", 105.0)
	var prop: CollectProp = game.arcade_stage.props["collect"]
	var block: Collect = game.arcade.active["block"]
	_ride(game, 3.0)
	var shown := prop.items.filter(func(item: MeshInstance3D): return item.visible)
	assert_between(shown.size(), 1, CollectProp.AHEAD, "die nächsten Objekte sind zu sehen")
	assert_true(prop.ring.visible, "der Magnetring ist da")
	assert_almost_eq(block.radius_m, block.radius_for(game.bus.cadence), 0.001)
	assert_almost_eq(prop.ring_radius_m, block.radius_m, 0.1, "der Ring zeigt den Radius")
	assert_almost_eq(prop.ring.scale.x, prop.ring_radius_m, 0.001)
	# Weniger Kadenz, kleinerer Ring.
	var big := prop.ring_radius_m
	game.bus.cadence = 80.0
	_ride(game, 2.0)
	assert_lt(prop.ring_radius_m, big - 1.0, "mit 80 rpm ein deutlich kleinerer Radius")
	game.bus.cadence = 0.0
	_ride(game, 1.0)
	assert_false(prop.ring.visible, "ohne Kadenz kein Magnet")
	# Seitlich versetzt: ein Objekt mit Abstand liegt abseits der Straßenmitte.
	var centre: Vector3 = game.track.ride_position_at(prop._at_m[1]) + Vector3.UP * CollectProp.HEIGHT_M
	assert_almost_eq(prop.items[1].position.distance_to(centre), 2.5, 0.01, "Objekt 1 liegt 2,5 m neben der Mitte")


func test_collect_objects_vanish_when_collected_and_grey_out_when_missed() -> void:
	var game := await _start_challenge("sammeln_wiese", 105.0)  # Radius ~3,7 m: Objekt 4 (4,0 m) bleibt liegen
	var prop: CollectProp = game.arcade_stage.props["collect"]
	var block: Collect = game.arcade.active["block"]
	while block.state_of(0) == Collect.PENDING and not block.finished():
		_ride(game, DT)
	assert_eq(block.state_of(0), Collect.COLLECTED)
	assert_false(prop.items[0].visible, "eingesammelt: weg")
	while block.state_of(4) == Collect.PENDING and not block.finished():
		_ride(game, DT)
	assert_eq(block.state_of(4), Collect.MISSED, "4 m liegen außerhalb von ~3,7 m")
	assert_true(prop.items[4].visible, "liegengeblieben: steht hinter dem Fahrer")
	assert_eq(prop.items[4].material_override, prop._grey)


# --- Simulator-Szenarien (bridge/profiles/arcade) ------------------------------------------------------------------


func test_scenario_rhythm_hit() -> void:
	var run := await _play_profile("takt_getroffen.toml", "takt_ruhig")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_true(result["succeeded"], "alle fünf Schläge in der Zone: geschafft")
	assert_eq(result["progress"], 1.0)
	assert_eq(game.arcade.points, 120)
	assert_false(result["loot"].is_empty(), "geschafft: Beute")
	assert_has(run["shown"], "Takt-Tore geschafft!  +120 Punkte")
	assert_eq(_gate_texts(game).slice(0, 5), ["Treffer", "Treffer", "Treffer", "Treffer", "Treffer"])
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding", "Erfolg in voller Fahrt")
	assert_gt(steps[done + 20]["distance_m"], steps[done]["distance_m"], "die Fahrt geht weiter")


func test_scenario_rhythm_missed() -> void:
	var run := await _play_profile("takt_verfehlt.toml", "takt_ruhig")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "100 rpm über der Zone 74–94: verfehlt")
	assert_eq(result["progress"], 0.0)
	assert_eq(result["loot"], {}, "keine Beute")
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Takt-Tore verfehlt – weiter geht's", "weich: nur eine Einblendung")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding", "weich: kein Abbruch")
	assert_gt(steps[done + 30]["distance_m"], steps[done]["distance_m"] + 20.0, "die Fahrt geht weiter")
	assert_eq(_gate_texts(game)[0], "Verpasst")


func test_scenario_collect_many() -> void:
	var run := await _play_profile("sammeln_viel.toml", "sammeln_wiese")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_true(result["succeeded"], "108 rpm: Radius ~3,9 m, 7 von 8 Objekten (nötig 5)")
	assert_almost_eq(result["progress"], 1.0, 0.001)
	assert_eq(game.arcade.points, 110)
	assert_false(result["loot"].is_empty(), "geschafft: Beute")
	assert_has(run["shown"], "Sammeln geschafft!  +110 Punkte")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding")
	assert_gt(steps[done + 20]["distance_m"], steps[done]["distance_m"])


func test_scenario_collect_few() -> void:
	var run := await _play_profile("sammeln_wenig.toml", "sammeln_wiese")
	var game: Node = run["game"]
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_false(result["succeeded"], "78 rpm: Radius ~1,3 m, zu wenig gesammelt")
	assert_gt(result["progress"], 0.0, "etwas gesammelt")
	assert_lt(result["progress"], 1.0)
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Sammeln verfehlt – weiter geht's")
	var steps: Array = run["steps"]
	var done: int = steps.map(func(s): return s["results"]).find(1)
	assert_eq(steps[done]["state"], "riding", "weich: kein Abbruch")
	assert_gt(steps[done + 30]["distance_m"], steps[done]["distance_m"] + 10.0)
