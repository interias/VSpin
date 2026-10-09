## Training (#37) gegen den Fake-Bus: aus dem Startmenü vom Aufwärmen bis zum Ausrollen – HUD mit Phase, Zielkadenz,
## Restzeit und nächster Phase, die Ansage vor dem Wechsel, die Bewertung im Ergebnis, das Erfolgs-Ereignis, der
## Fahrteintrag im Trainingsmodus und keine Bestzeit, Medaille, Segmentzeit oder Ghost. Dazu die Teilbewertung nach
## „Fahrt beenden“ und die ehrliche Wertung (ADR-0010): die Bewertung hängt nur an der Kadenz.
## Gefahren wird mit der Kadenz vom Bus in festen Schritten (DT) durch die Hauptszene, unabhängig von der Bildrate.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_training_ride_savegame.json")
## Kurze Test-Einheit: je 20 s Aufwärmen (80–100 rpm), Hart (95–105 rpm), Ausrollen (70–95 rpm).
const SHORT_UNIT := "res://tests/fixtures/training_short.json"
## Schnelles Rad wie in test_round_trip.gd: viele Graybox-Runden in einer Minute.
const FAST_K := 10.0
const DT := 0.1


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus mit Kadenz `cadence`, Test-Spielstand, ohne Trägheit.
func _spawn_game(cadence: float) -> Node:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 30.0))
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## `seconds` Fahrt in festen Schritten wie ein Frame der Hauptszene (Fahrschritt, dann Anzeige); hält im Ergebnis an.
## Liefert alle Einblendungen, die dabei zu sehen waren.
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


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


## Training mit der kurzen Einheit aus dem Startmenü starten; danach fährt nur noch `_ride` (Kadenz bleibt vom Bus).
func _start_from_menu(game: Node) -> void:
	await run_for(0.2)
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["training"].pressed.emit()
	game.start_menu.set_training_units([Training.load_file(SHORT_UNIT)])
	game.start_menu.buttons["training_start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0), "Training fährt")
	game.set_process(false)


func test_menu_offers_the_three_units() -> void:
	var game := _spawn_game(90.0)
	await run_for(0.2)
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["training"].pressed.emit()
	assert_true(menu.buttons["training_start"].is_visible_in_tree(), "Seite „Training“")
	assert_eq(game.get_viewport().gui_get_focus_owner(), menu.buttons["training_start"], "Fokus auf „Losfahren“")
	var units: OptionButton = menu.options["unit"]
	var texts := []
	for i in range(units.item_count):
		texts.append(units.get_item_text(i))
	assert_eq(texts, ["Intervalle kurz", "Pyramide", "Tempo-Blöcke"])
	var info: Label = menu.find_child("TrainingInfo", true, false)
	assert_eq(info.text, "10 × 30 s hart / 30 s locker · 23 min", "Beschreibung und Dauer")
	units.select(2)
	units.item_selected.emit(2)
	assert_eq(menu.training_unit()["name"], "Tempo-Blöcke")
	assert_eq(info.text, "3 × 8 min bei 85–90 rpm · 40 min")
	watch_signals(menu)
	menu.buttons["training_start"].pressed.emit()
	assert_signal_emitted_with_parameters(menu, "ride_requested", [SaveGame.MODE_TRAINING])
	assert_eq(game.ride_mode, SaveGame.MODE_TRAINING)
	assert_eq(game.training.unit["name"], "Tempo-Blöcke", "die gewählte Einheit fährt")
	menu.set_training_units([])
	assert_true(menu.buttons["training_start"].disabled, "ohne Einheit kein Losfahren")


func test_training_from_warmup_to_cooldown_over_the_bus() -> void:
	var game := _spawn_game(90.0)
	await _start_from_menu(game)
	assert_eq(game.ride_mode, SaveGame.MODE_TRAINING)
	assert_true(game.training_active(), "Training abfragbar (z. B. keine Panorama-Momente, #43)")
	assert_false(game.ghost_active())
	assert_eq(game.lap_timing.finish_m(), INF, "die Insel läuft endlos")
	# Aufwärmen: HUD mit Phase, Zielkadenz, Restzeit, nächster Phase und der Ansage zu Beginn.
	var shown := _ride(game, 2.0)
	var hud: String = game.hud.readout()
	assert_string_contains(hud, "Phase: Aufwärmen")
	assert_string_contains(hud, "Zielkadenz: 80–100 rpm")
	assert_string_contains(hud, "Restzeit: 0:18")
	assert_string_contains(hud, "Danach: Hart · 95–105 rpm")
	assert_string_contains(hud, "Ansage: Widerstand leicht, locker einrollen")
	shown += _ride(game, 6.0)
	assert_false(game.hud.readout().contains("Ansage:"), "zwischen den Ansagen Ruhe")
	# Die Ansage der harten Phase kommt vor dem Wechsel, noch im Aufwärmen.
	var announced_at := -1.0
	while game.training.phase_index() == 0 and game.state == "riding":
		shown += _ride(game, DT)
		if announced_at < 0.0 and game.hud.readout().contains("Ansage: In ") \
				and game.hud.readout().contains("Widerstand 2 Stufen hoch, 100 rpm halten"):
			announced_at = game.training.elapsed_s
			assert_string_contains(game.hud.readout(), "Phase: Aufwärmen", "angekündigt noch im Aufwärmen")
	assert_almost_eq(announced_at, 20.0 - Training.ANNOUNCE_AHEAD_S, 0.001, "ANNOUNCE_AHEAD_S vor dem Wechsel")
	hud = game.hud.readout()
	assert_string_contains(hud, "Phase: Hart")
	assert_string_contains(hud, "Zielkadenz: 95–105 rpm")
	assert_string_contains(hud, "Danach: Ausrollen · 70–95 rpm")
	assert_string_contains(hud, "Ansage: Widerstand 2 Stufen hoch, 100 rpm halten", "beim Wechsel noch einmal")
	# Ausrollen bis zum Ende: die Fahrt endet mit der Einheit, nicht an einer Ziellinie.
	shown += _ride(game, 25.0)
	assert_string_contains(game.hud.readout(), "Phase: Ausrollen")
	assert_string_contains(game.hud.readout(), "Danach: Ende der Einheit")
	assert_eq(game.state, "riding")
	shown += _ride(game, 20.0)
	assert_eq(game.state, "finished", "nach dem Ausrollen: Ergebnis")
	assert_true(game.training.finished())
	assert_almost_eq(game.stats.ride_time_s, 60.0, 0.001, "Fahrzeit = Dauer der Einheit")
	assert_gt(game.lap_timing.lap_times.size(), 2, "dabei mehrere Runden gefahren")
	# Bewertung: 90 rpm treffen Aufwärmen und Ausrollen, die harte Phase nicht.
	var message := _message(game)
	assert_string_contains(message, "Training beendet!")
	assert_string_contains(message, "Kurztest")
	assert_string_contains(message, "Zielkadenz getroffen: 67 %", "gesamt")
	assert_string_contains(message, "Je Phase: Aufwärmen 100 % · Hart 0 % · Ausrollen 100 %", "je Phase")
	assert_false(game.hud.readout().contains("Phase:"), "im Ergebnis keine Trainingszeile")
	# Erfolg: das Ereignis `training_finished` mit Zahl der Einheiten und Treffer.
	var unlocked: Array = game.ride_achievements.map(func(a): return a["id"])
	assert_has(unlocked, "training_1", "Erste Einheit")
	assert_does_not_have(unlocked, "training_precise", "67 % ist keine Punktlandung")
	assert_true(game.save_game.achievements().has("training_1"))
	# Runden im Training zählen nicht: keine Bestzeit, Medaille, Segmentzeit, kein Ghost, keine Einblendung dazu.
	for text in shown:
		assert_false(text.contains("Bestzeit"), "keine Bestzeit-Einblendung: %s" % text)
	var track := RideConfig.TRACK_GRAYBOX
	var cw := LapTiming.DIRECTION_CW
	assert_eq(game.save_game.best_time_s(track, cw), INF, "keine Bestzeit")
	assert_eq(game.save_game.best_medal(track, cw, Medals.LAP), Medals.NONE, "keine Medaille")
	assert_eq(game.save_game.segment_best_times(track, cw), {}, "keine Segmentzeit")
	assert_null(game.save_game.ghost(track, cw, Ghost.BEST), "kein Bestzeit-Ghost")
	assert_null(game.save_game.ghost(track, cw, Ghost.LAST), "kein Ghost „letzte Fahrt“")
	# Fahrteintrag im Trainingsmodus mit Einheit und Gesamtbewertung; km zählen fürs Fahrerlevel.
	assert_eq(game.save_game.rides().size(), 1)
	var ride: Dictionary = game.save_game.rides()[0]
	assert_eq(ride["mode"], SaveGame.MODE_TRAINING)
	assert_true(ride["finished"], "Einheit zu Ende gefahren")
	assert_eq(ride["training"], "Kurztest")
	assert_almost_eq(ride["training_score"], 0.667, 0.0005)
	assert_gt(ride["distance_km"], 1.0)
	assert_eq(game.save_game.finished_trainings(), 1)
	assert_true(FileAccess.file_exists(SAVE_PATH), "Spielstand auf der Platte")
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu", "Enter → Menü")
	assert_false(game.training_active())
	assert_eq(game.save_game.rides().size(), 1, "nicht doppelt gespeichert")
	# Fahrtenbuch: Modus „Training“.
	assert_string_contains(game.logbook.MODE_NAMES[SaveGame.MODE_TRAINING], "Training")


func test_end_ride_early_gives_partial_score_without_achievement() -> void:
	var game := _spawn_game(90.0)
	await _start_from_menu(game)
	_ride(game, 25.0)  # Aufwärmen ganz, 5 s der harten Phase
	assert_eq(game.training.phase()["name"], "Hart")
	game.settings_menu.ride_end_requested.emit()  # „Fahrt beenden“
	assert_eq(game.state, "finished", "erst die Teilbewertung")
	game._update_view()  # der nächste Frame
	var message := _message(game)
	assert_string_contains(message, "Training abgebrochen")
	assert_string_contains(message, "Zielkadenz getroffen: 80 %", "20 von 25 s im Zielbereich")
	assert_string_contains(message, "Je Phase: Aufwärmen 100 % · Hart 0 %")
	assert_false(message.contains("Ausrollen"), "nicht gefahrene Phasen fehlen")
	assert_false(game.save_game.achievements().has("training_1"), "nur ein beendetes Training zählt als Erfolg")
	var ride: Dictionary = game.save_game.rides()[0]
	assert_false(ride["finished"])
	assert_almost_eq(ride["training_score"], 0.8, 0.0005)
	assert_eq(game.save_game.finished_trainings(), 0)
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")


## Bewertung der kurzen Einheit mit Kadenz `cadence` und weiteren Telemetriefeldern vom Bus: Hauptszene am Fake-Bus,
## Training in festen Schritten bis zum Ende. Liefert [gesamt, je Phase …].
func _scores(cadence: float, fields: Dictionary = {}, config: RideConfig = null) -> Array:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, 5.0, 0.25, fields))
	if config != null:
		config.bus_url = bus.url()
	var game := spawn_ride(bus, 0.0, config)
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence == cadence, 3.0))
	game.set_process(false)
	game.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(SHORT_UNIT))
	_ride(game, 70.0)
	assert_true(game.training.finished(), "Einheit zu Ende")
	var result := [game.training.total_score()]
	for i in range(game.training.phases.size()):
		result.append(game.training.phase_score(i))
	return result


func test_score_depends_only_on_cadence() -> void:
	var reference := await _scores(90.0)
	# Alles andere anders: gemessene Watt, Tempo und Puls vom Rad …
	var other := await _scores(90.0, {"power_w": 420.0, "power_estimated": false, "speed_kmh": 55.0, "heart_rate": 172})
	assert_eq(other, reference, "gleiche Kadenz, andere Watt/Tempo/Puls → exakt gleiche Bewertung (ADR-0010)")
	# … und ein anderes Tempo im Spiel (Steigung ohne Wirkung): die Bewertung misst nur die Kadenz.
	var flat_bus := start_fake_bus([FakeBusServer.status()])
	var flat := config_for(flat_bus)
	flat.uphill_damping = 0.0
	flat.downhill_boost = 0.0
	flat.k_kmh_per_rpm = FAST_K
	assert_eq(await _scores(90.0, {}, flat), reference, "anderes Tempo, gleiche Bewertung")
	assert_ne(await _scores(100.0), reference, "andere Kadenz → andere Bewertung")
