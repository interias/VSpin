## Talente, Arcade-Level und legendäre Effekte (#53) durch die echte Hauptszene: der Talentbaum im Startmenü (Seite „Arcade“
## → „Talente“: Punkte verteilen, zurücksetzen, speichern, Esc, Fokus; Layout in 960×1040, 1920×1080 und 1152×648), der
## `run_hook` der Bühne legt Talente und Effekte **nach** den Fähigkeiten auf den Lauf, die Simulator-Szenarien der Bridge
## zeigen die Wirkung (stärkere Windböe, Rückstoß der Jagd), die Punkte der Fahrt zählen zum Arcade-Level, und in Rundfahrt
## und Training bleibt alles beim Alten (ADR-0010). Das Ausrüstungsmenü zeigt den Effekt legendärer Teile.
extends "res://tests/support/bus_test.gd"

const TALENT_MENU := preload("res://scenes/talent_menu.gd")
const GEAR_MENU := preload("res://scenes/gear_menu.gd")
const START_MENU_SCENE := preload("res://scenes/start_menu.tscn")
var SAVE_PATH := TestIsolation.path("test_talents_ride_savegame.json")
const DT := 0.1
const LONG_ZONE := {"id": "t_long_zone", "block": "zone_hold", "name": "Zone halten", "zone_rpm": [75, 95],
		"hold_s": 400.0, "window_s": 600.0, "points": 100}
const LONG_CHASE := {"id": "t_long_chase", "block": "chase", "name": "Jagd", "threshold_at": 0.7, "escape_s": 100.0,
		"catch_s": 100.0, "window_s": 600.0, "start_gap": 0.5, "points": 100}
const ZONE_MITTE_ID := "zone_mitte"


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _item(slot: String, rarity: String, effect: String = "", stats: Dictionary = {"luck_pct": 5}) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


## Stand auf der Platte: Arcade-Level `level`, die `talents` erlernt, die `legendaries` (Platz → Effekt) angelegt.
func _prepare_save(level: int, talents: Array = [], legendaries: Dictionary = {}) -> SaveGame:
	var save := SaveGame.new()
	ArcadeLevel.add_points(save, ArcadeLevel.points_for(level))
	for id in talents:
		assert_true(Talents.learn(save, id), "Talent %s erlernbar" % id)
	for slot in legendaries:
		Inventory.equip(save, Inventory.add(save, _item(slot, Loot.LEGENDARY, legendaries[slot]))["id"])
	save.save_file(SAVE_PATH)
	return save


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


## „Fahren → Arcade“, Stufe 1, 60–120 rpm, „Losfahren“ mit festem Würfel und nur der Herausforderung `definition`.
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


## Spielt das Bridge-Profil `name` im Gleichschritt durch das Spiel (Arcade, die einzige Herausforderung `definition`).
## Liefert Spiel und je Schritt {t, block, counts, factor, progress, popups}.
func _play_profile(name: String, definition: Dictionary) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)
	await _start_arcade(game, definition)
	game.set_process(false)
	var extension := _extension(game)
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
		var block: ChallengeBlock = game.arcade.active["block"] if game.arcade != null and not game.arcade.active.is_empty() else null
		steps.append({"t": (i + 1) * DT, "block": block != null, "counts": extension.abilities.counts.duplicate(),
				"factor": block.progress_factor if block != null else 0.0, "progress": block.progress() if block != null else -1.0,
				"popups": game.hud.popups()})
	return {"game": game, "steps": steps}


func _first(steps: Array, condition: Callable) -> int:
	for i in range(steps.size()):
		if condition.call(steps[i]):
			return i
	return -1


# --- Der Hook der Bühne: Talente und Effekte nach den Fähigkeiten ------------------------------------------------------------


func test_run_hook_puts_talents_and_effects_on_the_abilities_of_the_run() -> void:
	_prepare_save(6, ["sprinter_antritt", "sprinter_reflex", "sprinter_druck", "kletterer_zaeh"], {"helm": "tiefer_atem"})
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	var extension := _extension(game)
	assert_not_null(extension, "Fähigkeiten angemeldet")
	assert_not_null(game.talent_arcade, "Talente angehängt")
	assert_eq(game.arcade_stage.extensions.size(), ArcadeStage.EXTENSIONS.size(), "ohne Eintrag in EXTENSIONS")
	# Ein Hook je Erweiterung (die Fähigkeiten zuerst; #54 Stufen danach), die Talente zuletzt.
	var hooks: Array = game.arcade_stage.run_hooks
	assert_eq(hooks.size(), ArcadeStage.EXTENSIONS.size() + 1, "Hooks: erst die Erweiterungen, dann die Talente")
	assert_true(hooks[0].get_object() == extension, "erst die Fähigkeiten")
	assert_true(hooks[-1].get_object() == game.talent_arcade, "dann die Talente")
	assert_eq(extension.abilities.defs["windboe"]["power"], 2.0, "vor dem Lauf: die Standarddaten")
	game.arcade_stage.begin(true, 1, game.save_game, 0.0)
	assert_almost_eq(float(extension.abilities.defs["windboe"]["power"]), 2.5, 1e-9, "Talent „Kräftiger Antritt“")
	assert_almost_eq(float(extension.abilities.defs["schild"]["duration_s"]), 10.0, 1e-9, "Effekt „Tiefer Atem“")
	assert_almost_eq(float(extension.patterns.thresholds["antritt_rise_rpm"]), 20.0, 1e-9, "Talent „Wacher Antritt“")
	assert_eq(game.arcade.gear["progress_pct"], 10, "Talente +6 +4 % Fortschritt in der Zone")
	assert_eq(Abilities.DEFS["windboe"]["power"], 2.0, "die Standarddaten bleiben")
	# Der nächste Lauf ohne Talente und Effekt: alles wieder wie vorher (auch die Schwelle).
	Talents.reset(game.save_game)
	game.save_game.arcade()["equipped"] = {}
	game.arcade_stage.begin(true, 1, game.save_game, 0.0)
	assert_eq(extension.abilities.defs["windboe"]["power"], 2.0)
	assert_eq(extension.abilities.defs["schild"]["duration_s"], 6.0)
	assert_eq(extension.patterns.thresholds["antritt_rise_rpm"], 25.0, "Schwelle zurück auf den Standard")
	assert_eq(game.arcade.gear["progress_pct"], 0)


func test_the_hook_runs_only_in_the_arcade() -> void:
	_prepare_save(6, ["sprinter_antritt", "sprinter_reflex"], {"helm": "tiefer_atem"})
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	var extension := _extension(game)
	game.arcade_stage.begin(false, 1, game.save_game, 0.0)  # Rundfahrt/Training: kein Lauf, keine Hooks
	assert_null(game.arcade)
	assert_eq(extension.abilities.defs["windboe"]["power"], 2.0)
	assert_eq(extension.patterns.thresholds["antritt_rise_rpm"], 25.0)
	assert_true(game.talent_arcade.knockback.is_empty())


# --- Simulator-Szenarien --------------------------------------------------------------------------------------------------


func test_scenario_antritt_with_a_talent_gives_a_stronger_windboe() -> void:
	_prepare_save(3, ["sprinter_antritt"])
	var played := await _play_profile("antritt.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var first := _first(steps, func(s): return s["counts"]["windboe"] >= 1)
	assert_gte(first, 0, "die Windböe wurde ausgelöst")
	assert_almost_eq(steps[first]["factor"], 3.5, 1e-6, "Fortschritt in der Zone ×3,5 statt ×3")
	var after := steps.slice(first + roundi(2.6 / DT))
	assert_eq(after[0]["factor"], 1.0, "danach wieder der Ausgangsfaktor")


func test_scenario_antritt_without_talents_stays_at_the_default() -> void:
	_prepare_save(3)
	var played := await _play_profile("antritt.toml", LONG_ZONE)
	var steps: Array = played["steps"]
	var first := _first(steps, func(s): return s["counts"]["windboe"] >= 1)
	assert_almost_eq(steps[first]["factor"], 3.0, 1e-6)


func test_scenario_antritt_with_the_knockback_effect_throws_the_chaser_back() -> void:
	_prepare_save(1, [], {"rahmen": "rueckstoss"})
	var knocked := await _play_profile("antritt.toml", LONG_CHASE)
	_prepare_save(1)
	var plain := await _play_profile("antritt.toml", LONG_CHASE)
	var steps: Array = knocked["steps"]
	var first := _first(steps, func(s): return s["counts"]["windboe"] >= 1)
	assert_gte(first, 0, "die Windböe löst in der Jagd aus")
	assert_eq(first, _first(plain["steps"], func(s): return s["counts"]["windboe"] >= 1), "und zwar im selben Schritt")
	assert_gt(steps[first]["progress"], plain["steps"][first]["progress"] + 0.14, "Abstand um ~15 % größer")
	assert_has(steps[first]["popups"], "Rückstoß!", "Rückmeldung")
	assert_does_not_have(plain["steps"][first]["popups"], "Rückstoß!")
	# Der Vorsprung bleibt auch später: bei gleicher Kadenz bleibt der Abstand größer.
	var later := first + roundi(6.0 / DT)
	assert_gt(steps[later]["progress"], plain["steps"][later]["progress"] + 0.1)


# --- Arcade-Level: Punkte der Fahrt, Ergebnis, Menü ---------------------------------------------------------------------------


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


func _perfect_run(points_before: int) -> Dictionary:
	var save := SaveGame.new()
	ArcadeLevel.add_points(save, points_before)
	save.save_file(SAVE_PATH)
	var bus_run := await _play_profile("zone_perfekt.toml", Encounters.find(ZONE_MITTE_ID))
	return bus_run


func test_points_of_a_run_count_to_the_arcade_level_and_show_in_the_result() -> void:
	var run := await _perfect_run(0)
	var game: Node = run["game"]
	assert_eq(game.arcade.points, 100)
	assert_eq(ArcadeLevel.total_points(game.save_game), 0, "während der Fahrt noch nicht")
	game.settings_menu.ride_end_requested.emit()
	game._update_view()
	assert_eq(ArcadeLevel.total_points(game.save_game), 100, "nach der Fahrt gutgeschrieben")
	assert_eq(ArcadeLevel.total_points(SaveGame.load_file(SAVE_PATH)), 100, "gespeichert")
	assert_string_contains(_message(game), "Arcade-Level 1 · noch 300 Punkte bis Level 2")
	assert_eq(Talents.available(game.save_game), 0)
	game.settings_menu.ride_end_requested.emit()
	assert_eq(ArcadeLevel.total_points(game.save_game), 100, "ein zweites Beenden zählt nichts doppelt")


func test_a_new_level_gives_a_talent_point_shown_in_result_and_menu() -> void:
	var run := await _perfect_run(350)
	var game: Node = run["game"]
	game.settings_menu.ride_end_requested.emit()
	game._update_view()
	assert_eq(ArcadeLevel.level(game.save_game), 2, "450 Punkte: Level 2")
	assert_string_contains(_message(game), "Arcade-Level 2 – neues Level! · 1 Talentpunkt frei")
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["arcade"].pressed.emit()
	var label: Label = game.start_menu.find_child("ArcadeLevel", true, false)
	assert_eq(label.text, "Arcade-Level 2")
	assert_eq(game.start_menu.buttons["arcade_talents"].text, "Talente (1)")


func test_a_run_without_progress_adds_no_points() -> void:
	_prepare_save(1)
	var run := await _play_profile("zone_knapp_daneben.toml", Encounters.find(ZONE_MITTE_ID))
	var game: Node = run["game"]
	game.settings_menu.ride_end_requested.emit()
	assert_eq(ArcadeLevel.total_points(game.save_game), 0, "ohne Kadenz in der Zone keine Punkte, kein Level")
	assert_string_contains(game.arcade_result(), "Arcade-Level 1 · noch 400 Punkte bis Level 2")


# --- Rundfahrt und Training bleiben unberührt -----------------------------------------------------------------------------------


func _drive(mode: String, everything: bool) -> Dictionary:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(92.0, 0.0, 5.0))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == 92.0, 3.0))
	ride.set_process(false)
	if everything:
		var save: SaveGame = ride.save_game
		ArcadeLevel.add_points(save, ArcadeLevel.points_for(ArcadeLevel.MAX_LEVEL))
		for id in Talents.NODES:
			Talents.learn(save, id)
		for slot_effect in [["rahmen", "rueckstoss"], ["helm", "im_fluss"], ["schuhe", "auf_dem_sprung"]]:
			Inventory.equip(save, Inventory.add(save, _item(slot_effect[0], Loot.LEGENDARY, slot_effect[1],
					{"progress_pct": 18, "zone_width_rpm": 6}))["id"])
	if mode == SaveGame.MODE_TRAINING:
		ride.start_ride(mode, 0, "", Training.load_all()[0])
	else:
		ride.start_ride(mode, 1)
	for i in range(1500):
		ride._ride(DT)
	var extension := _extension(ride)
	var result := {"distance_m": ride.model.distance_m, "speed": ride.model.speed_mps, "laps": ride.lap_timing.lap_times,
			"time": ride.stats.ride_time_s, "defs": extension.abilities.defs, "thresholds": extension.patterns.thresholds,
			"arcade": ride.arcade == null, "points": ArcadeLevel.total_points(ride.save_game)}
	if ride.training != null:
		result["score"] = ride.training.total_score()
		result["phase"] = ride.training.phase_index()
	return result


func test_round_trip_and_training_behave_identically_with_talents_and_effects() -> void:
	for mode in [SaveGame.MODE_ROUND_TRIP, SaveGame.MODE_TRAINING]:
		var plain := await _drive(mode, false)
		var full := await _drive(mode, true)
		assert_true(full["arcade"], "%s: kein Arcade-Lauf" % mode)
		assert_eq(full["defs"], Abilities.DEFS, "%s: Fähigkeiten unverändert" % mode)
		assert_eq(full["thresholds"], CadencePatterns.THRESHOLDS, "%s: Schwellen unverändert" % mode)
		full["points"] = plain["points"]  # der Stand selbst hat Punkte (Vorbereitung), die Fahrt keine
		assert_eq(full, plain, "%s mit Talenten und Effekten identisch" % mode)
	assert_gt((await _drive(SaveGame.MODE_ROUND_TRIP, true))["laps"].size(), 0, "eine Runde gefahren")


# --- Talentmenü ----------------------------------------------------------------------------------------------------------


func _open_talents(game: Node) -> CanvasLayer:
	await run_for(0.2)
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	assert_true(menu.buttons["arcade_talents"].is_visible_in_tree(), "„Talente“ auf der Seite „Arcade“")
	menu.buttons["arcade_talents"].pressed.emit()
	await get_tree().process_frame
	return game.talent_menu


func test_talent_menu_from_arcade_page_learn_reset_and_save() -> void:
	_prepare_save(4)  # drei Talentpunkte
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	var talents := await _open_talents(game)
	var menu: CanvasLayer = game.start_menu
	assert_true(talents.visible, "Talentbaum offen")
	assert_false(menu.visible, "Startmenü tritt zurück")
	assert_string_contains(talents.info_text(), "Arcade-Level 4 · 3 Talentpunkte frei (0 ausgegeben)")
	assert_eq(menu.buttons["arcade_talents"].text, "Talente (3)")
	assert_eq(talents.buttons.keys().filter(func(k): return k.begins_with("node_")).size(), 15, "15 Knoten")
	assert_eq(game.get_viewport().gui_get_focus_owner(), talents.buttons["node_sprinter_antritt"], "Fokus auf dem ersten")
	assert_true(talents.buttons["node_sprinter_atem"].disabled, "Nachfolger vorher gesperrt")
	assert_string_contains(talents.node_text("sprinter_atem"), "braucht „Kräftiger Antritt“")
	assert_string_contains(talents.node_text("sprinter_antritt"), "1 Talentpunkt")
	assert_true(talents.buttons["reset"].disabled, "nichts zurückzusetzen")
	# Lernen: sofort gespeichert, Fokus wandert zum Nachfolger.
	talents.buttons["node_sprinter_antritt"].pressed.emit()
	assert_eq(Talents.learned(game.save_game), ["sprinter_antritt"])
	assert_eq(Talents.learned(SaveGame.load_file(SAVE_PATH)), ["sprinter_antritt"], "gespeichert")
	assert_string_contains(talents.info_text(), "2 Talentpunkte frei (1 ausgegeben)")
	assert_string_contains(talents.node_text("sprinter_antritt"), "erlernt")
	assert_true(talents.buttons["node_sprinter_antritt"].disabled)
	assert_false(talents.buttons["node_sprinter_atem"].disabled, "Nachfolger offen")
	assert_eq(game.get_viewport().gui_get_focus_owner(), talents.buttons["node_sprinter_atem"])
	talents.buttons["node_sprinter_atem"].pressed.emit()
	talents.buttons["node_kletterer_zaeh"].pressed.emit()
	assert_string_contains(talents.info_text(), "0 Talentpunkte frei (3 ausgegeben)")
	for id in ["sprinter_reflex", "sprinter_spurt", "kletterer_atem", "ausdauer_gleichmass"]:
		assert_true(talents.buttons["node_" + id].disabled, "%s: ohne Punkt gesperrt" % id)
	assert_string_contains(talents.node_text("ausdauer_gleichmass"), "kein Talentpunkt frei")
	talents.buttons["node_sprinter_reflex"].pressed.emit()
	assert_eq(Talents.spent(game.save_game), 3, "ohne Punkt kein weiteres Talent")
	# Zurücksetzen: kostenlos, gespeichert.
	assert_false(talents.buttons["reset"].disabled)
	assert_string_contains(talents.buttons["reset"].text, "+3")
	talents.buttons["reset"].pressed.emit()
	assert_eq(Talents.learned(game.save_game), [])
	assert_eq(Talents.learned(SaveGame.load_file(SAVE_PATH)), [], "Zurücksetzen gespeichert")
	assert_string_contains(talents.info_text(), "3 Talentpunkte frei (0 ausgegeben)")
	talents.buttons["node_ausdauer_gleichmass"].pressed.emit()  # neu verteilen
	assert_eq(Talents.learned(SaveGame.load_file(SAVE_PATH)), ["ausdauer_gleichmass"])
	# Esc schließt; zurück auf der Seite „Arcade“, Fokus auf „Talente“, Level im Menü.
	await press_key(KEY_ESCAPE)
	assert_false(talents.visible, "Esc schließt")
	assert_false(game.settings_menu.is_open())
	assert_true(menu.buttons["arcade_start"].is_visible_in_tree(), "zurück auf der Seite „Arcade“")
	assert_eq(game.get_viewport().gui_get_focus_owner(), menu.buttons["arcade_talents"])
	assert_eq(menu.find_child("ArcadeLevel", true, false).text, "Arcade-Level 4")
	assert_eq(menu.buttons["arcade_talents"].text, "Talente (2)", "zwei Punkte frei")


func test_talent_menu_without_points_and_back_button() -> void:
	_prepare_save(1)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	var talents := await _open_talents(game)
	assert_string_contains(talents.info_text(), "Arcade-Level 1 · 0 Talentpunkte frei")
	assert_string_contains(talents.info_text(), "noch 400 Punkte bis Level 2")
	assert_true(talents.buttons.keys().filter(func(k): return k.begins_with("node_")).all(
			func(k): return talents.buttons[k].disabled), "ohne Punkte ist alles gesperrt")
	assert_eq(game.get_viewport().gui_get_focus_owner(), talents.buttons["back"], "Fokus auf „Zurück“")
	assert_eq(game.start_menu.buttons["arcade_talents"].text, "Talente")
	talents.buttons["back"].pressed.emit()
	assert_false(talents.visible)
	assert_true(game.start_menu.buttons["arcade_start"].is_visible_in_tree())


func test_returning_to_the_menu_closes_the_talent_menu() -> void:
	_prepare_save(3)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	var talents := await _open_talents(game)
	game._enter_menu()
	assert_false(talents.visible, "Rückkehr ins Menü schließt den Talentbaum")


## Talentbaum in `viewport_size`, geöffnet mit `save`.
func _talents_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var talents: CanvasLayer = TALENT_MENU.new()
	viewport.add_child(talents)
	talents.open(save)
	await wait_process_frames(4)
	return talents


func _assert_talents_inside(talents: CanvasLayer, label: String) -> void:
	var screen: Rect2 = talents.get_node("Layout").get_viewport_rect()
	var scroll: ScrollContainer = talents.find_child("Scroll", true, false)
	var checked := 0
	for control in talents.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control is ScrollBar or scroll.is_ancestor_of(control):
			continue
		checked += 1
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()), "%s: %s liegt im Fenster %s (%s)" % [
				label, control.name, screen, control.get_global_rect()])
	assert_gt(checked, 5, "%s: alle Anzeigen geprüft" % label)
	assert_true(screen.grow(0.5).encloses(scroll.get_global_rect()), "%s: Bereich der Äste im Fenster" % label)
	var rects := []
	for branch in Talents.BRANCHES:
		var panel: Control = talents.find_child(branch.capitalize(), true, false)
		rects.append(panel.get_global_rect())
		assert_gt(panel.get_global_rect().size.x, 240.0, "%s: Ast %s breit genug" % [label, branch])
	assert_false(rects[0].intersects(rects[1]) or rects[1].intersects(rects[2]), "%s: Äste nebeneinander" % label)
	for key in ["reset", "back"]:
		var rect: Rect2 = talents.buttons[key].get_global_rect()
		assert_true(screen.grow(0.5).encloses(rect), "%s: %s im Fenster" % [label, key])
		assert_false(rect.intersects(scroll.get_global_rect()), "%s: %s außerhalb des Scrollbereichs" % [label, key])
	# Jeder Knoten ist erreichbar: im Scrollbereich oder durch Scrollen (follow_focus); seine Breite passt in die Spalte.
	for id in Talents.NODES:
		var button: Button = talents.buttons["node_" + id]
		var panel: Control = talents.find_child(Talents.NODES[id]["branch"].capitalize(), true, false)
		assert_true(panel.get_global_rect().grow(0.5).encloses(Rect2(button.get_global_position(), Vector2(button.size.x, 1))),
				"%s: Knoten %s in der Spalte seines Astes" % [label, id])


func test_talent_layout_fits_half_and_full_screen() -> void:
	var save := SaveGame.new()
	ArcadeLevel.add_points(save, ArcadeLevel.points_for(9))
	for id in ["sprinter_antritt", "sprinter_atem", "kletterer_zaeh"]:
		Talents.learn(save, id)
	_assert_talents_inside(await _talents_in(Vector2i(960, 1040), save), "960×1040")
	_assert_talents_inside(await _talents_in(Vector2i(1920, 1080), save), "1920×1080")
	var small := await _talents_in(Vector2i(1152, 648), save)
	_assert_talents_inside(small, "1152×648 (Godot-Standardfenster)")
	var scroll: ScrollContainer = small.find_child("Scroll", true, false)
	assert_true(scroll.get_v_scroll_bar().visible or scroll.get_global_rect().size.y > 300.0, "1152×648: scrollt oder genug Platz")


func test_arcade_page_with_four_buttons_and_level_fits() -> void:
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child_autofree(viewport)
		var menu := START_MENU_SCENE.instantiate()
		viewport.add_child(menu)
		menu.show_arcade()
		menu.show_arcade_level(ArcadeLevel.MAX_LEVEL, 11)
		await wait_process_frames(4)
		var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
		for key in ["arcade_start", "arcade_gear", "arcade_talents", "arcade_back"]:
			assert_true(menu.buttons[key].is_visible_in_tree())
			assert_true(screen.grow(0.5).encloses(menu.buttons[key].get_global_rect()), "%s: %s im Fenster" % [size, key])
		var panel: Rect2 = menu.find_child("Panel", true, false).get_global_rect()
		assert_true(screen.grow(0.5).encloses(panel), "%s: Menü im Fenster" % size)
		assert_eq(menu.find_child("ArcadeLevel", true, false).text, "Arcade-Level 12")
		assert_eq(menu.buttons["arcade_talents"].text, "Talente (11)")


# --- Ausrüstungsmenü zeigt den Effekt ---------------------------------------------------------------------------------------


func test_gear_menu_shows_the_effect_of_a_legendary_item() -> void:
	var save := SaveGame.new()
	var plain := Inventory.add(save, _item("helm", Loot.RARE, "", {"zone_width_rpm": 3}))
	var legend := Inventory.add(save, _item("trikot", Loot.LEGENDARY, "rueckstoss", {"points_pct": 15, "luck_pct": 9}))
	var old := Inventory.add(save, _item("schuhe", Loot.LEGENDARY, "", {"zone_width_rpm": 6}))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var gear: CanvasLayer = GEAR_MENU.new()
	viewport.add_child(gear)
	gear.open(save)
	await wait_process_frames(3)
	gear.select(legend["id"])
	assert_string_contains(gear.effect_text(), "Effekt: Rückstoß")
	assert_string_contains(gear.effect_text(), "Windböe wirft Gegner zurück")
	assert_string_contains(gear.buttons["item_%d" % legend["id"]].text, "Rückstoß", "auch in der Liste")
	gear.select(plain["id"])
	assert_eq(gear.effect_text(), "", "ohne Effekt keine Zeile")
	gear.select(old["id"])
	assert_eq(gear.effect_text(), "", "älteres legendäres Teil ohne Effekt: keine Zeile")
	assert_false(gear.buttons["item_%d" % old["id"]].text.contains("Effekt"))
