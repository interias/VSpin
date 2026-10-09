## Stufen mit empfohlener Stärke (#54) gegen den Fake-Bus durch die echte Hauptszene: die Seite „Arcade“ zeigt die
## freigeschalteten Stufen (gesperrte ausgegraut, die nächste mit dem Stand der Bosse) und die eigene gegen die empfohlene
## Stärke der gewählten Stufe, und passt weiter in jedes Fenster; der Sieg über den letzten fehlenden Boss der höchsten
## freien Stufe schaltet die nächste frei (Spielstand, Zusammenfassung, Menü); mehrere Runden im Lauf werden härter
## (engere Zone) und lohnender (mehr Punkte), mit Hinweis beim Rundenwechsel. Fähigkeiten (#50) sind hier nicht der
## Gegenstand: konstante Kadenz löste sie aus, darum abgeschaltet.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_arcade_tiers_ride_savegame.json")
const DT := 0.1
const BOSSES := preload("res://src/challenges/boss_challenges.gd")
const START_MENU_SCENE := preload("res://scenes/start_menu.tscn")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene am Fake-Bus mit Test-Spielstand. `k_kmh_per_rpm` > 0: schnelleres Rad ohne Trägheit (Runden in kurzer Zeit).
func _spawn_on(bus: FakeBusServer, k_kmh_per_rpm: float = 0.0) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	if k_kmh_per_rpm > 0.0:
		config.inertia_s = 0.0
		config.k_kmh_per_rpm = k_kmh_per_rpm
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


func _select(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)


func _item(slot: String, stats: Dictionary) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": Loot.RARE, "stats": stats, "effect": ""}


## Stand auf der Platte: höchste freie Stufe `unlocked`, besiegte Bosse je Stufe, gewählte Stufe, angelegte Teile.
func _prepare_save(unlocked: int, defeated: Dictionary, tier: int, items: Array = []) -> SaveGame:
	var save := SaveGame.new()
	save.arcade()["unlocked"] = unlocked
	save.arcade()["defeated"] = defeated
	ArcadeTiers.choose(save, tier)
	for item in items:
		Inventory.equip(save, Inventory.add(save, item)["id"])
	save.save_file(SAVE_PATH)
	return save


func _open_arcade_page(game: Node) -> CanvasLayer:
	await run_for(0.2)
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	return menu


func _tier_items(menu: CanvasLayer) -> Array:
	var tiers: OptionButton = menu.options["tier"]
	var items := []
	for i in range(tiers.item_count):
		items.append([tiers.get_item_text(i), not tiers.is_item_disabled(i)])
	return items


## Mit festem Würfel und nur `definition` im Pool losfahren (Graybox: keine festen Orte), Fähigkeiten aus.
func _start_arcade(game: Node, definition: Dictionary) -> void:
	AbilityExtension.of(game.arcade_stage).enabled = false
	game.arcade_seed = 1
	game.arcade_pool = [definition]
	game.start_menu.buttons["arcade_start"].pressed.emit()
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0), "Arcade fährt")
	game.set_process(false)


# --- Seite „Arcade“: Stufen und Stärke --------------------------------------------------------------------------------


func test_arcade_page_shows_unlocked_tiers_and_strength() -> void:
	# Stufe 4 frei, auf ihr zwei Bosse besiegt; Schuhe +3 rpm und Laufräder +9 % Fortschritt angelegt: Stärke 21.
	_prepare_save(4, {"4": ["tramuntana", "drac"]}, 4,
			[_item("schuhe", {"zone_width_rpm": 3}), _item("laufraeder", {"progress_pct": 9, "luck_pct": 8})])
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	var menu := await _open_arcade_page(game)
	assert_eq(_tier_items(menu), [["Stufe 1", true], ["Stufe 2", true], ["Stufe 3", true], ["Stufe 4", true],
			["Stufe 5 (gesperrt – Bosse auf Stufe 4: 2/3)", false], ["Stufe 6 (gesperrt)", false]])
	assert_eq(menu.arcade_tier(), 4, "die gewählte Stufe steht wie im Spielstand")
	assert_true(menu.arcade_tier_unlocked(4))
	assert_false(menu.arcade_tier_unlocked(5))
	var strength: Label = menu.find_child("ArcadeStrength", true, false)
	assert_true(strength.is_visible_in_tree())
	assert_eq(strength.text, "Stärke 21 / empfohlen 35", "eigene Stärke aus Ausrüstung gegen die der Stufe")
	assert_eq(strength.get_theme_color("font_color"), menu.COLOR_WARN, "unter der Empfehlung: gelb, aber wählbar")
	_select(menu.options["tier"], 1)
	assert_eq(strength.text, "Stärke 21 / empfohlen 10", "folgt der gewählten Stufe")
	assert_eq(strength.get_theme_color("font_color"), menu.COLOR_OK)
	assert_eq(ArcadeTiers.selection(game.save_game), 2, "Wahl im Spielstand")
	# Eine Empfehlung, keine Sperre: Stufe 4 fährt auch unter der empfohlenen Stärke.
	_select(menu.options["tier"], 3)
	menu.buttons["arcade_start"].pressed.emit()
	assert_eq(game.arcade.tier, 4)


func test_talents_and_new_gear_raise_the_shown_strength() -> void:
	var save := _prepare_save(3, {}, 1)
	ArcadeLevel.add_points(save, ArcadeLevel.points_for(3))
	assert_true(Talents.learn(save, "kletterer_zaeh"))
	save.save_file(SAVE_PATH)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	var menu := await _open_arcade_page(game)
	var strength: Label = menu.find_child("ArcadeStrength", true, false)
	var talent := ArcadeTiers.strength(game.save_game)
	assert_gt(talent, 0, "Talent zählt")
	assert_eq(strength.text, "Stärke %d / empfohlen 0" % talent)
	# Ausrüstung anlegen (Ausrüstungsmenü) und zurück: die Seite zeigt die neue Stärke.
	var shoes := Inventory.add(game.save_game, _item("schuhe", {"zone_width_rpm": 4}))
	game.start_menu.gear_requested.emit()
	game.gear_menu.select(shoes["id"])
	game.gear_menu.equip_selected()
	game.gear_menu.buttons["back"].pressed.emit()
	assert_eq(strength.text, "Stärke %d / empfohlen 0" % (talent + 16))


func test_arcade_page_with_six_tiers_and_strength_fits() -> void:
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child_autofree(viewport)
		var menu := START_MENU_SCENE.instantiate()
		viewport.add_child(menu)
		menu.show_arcade()
		menu.show_arcade_level(ArcadeLevel.MAX_LEVEL, 11)
		menu.show_arcade_best(123456)
		menu.set_arcade_unlocked(5, 2, 3)
		menu.show_arcade_strength(100)
		await wait_process_frames(4)
		var screen: Rect2 = menu.get_node("Layout").get_viewport_rect()
		for key in ["arcade_start", "arcade_gear", "arcade_talents", "arcade_back"]:
			assert_true(screen.grow(0.5).encloses(menu.buttons[key].get_global_rect()), "%s: %s im Fenster" % [size, key])
		var panel: Rect2 = menu.find_child("Panel", true, false).get_global_rect()
		assert_true(screen.grow(0.5).encloses(panel), "%s: Menü im Fenster" % size)
		var strength: Label = menu.find_child("ArcadeStrength", true, false)
		assert_true(panel.encloses(strength.get_global_rect()), "%s: Stärke im Menü" % size)
		var level: Label = menu.find_child("ArcadeLevel", true, false)
		assert_almost_eq(strength.get_global_rect().position.y, level.get_global_rect().position.y, 0.5,
				"%s: in der Zeile von Bestpunktzahl und Arcade-Level" % size)
		assert_eq(strength.text, "Stärke 100 / empfohlen 0")


# --- Freischalten nach Abschluss ---------------------------------------------------------------------------------------


func test_defeating_the_last_missing_boss_unlocks_the_next_tier() -> void:
	# Stufe 3 gewählt, Tramuntana und Drac dort schon besiegt; jetzt die Dimonis: 120 rpm liegen über jeder ihrer
	# Schwellen auf Stufe 3 (98 / 110 / 104 rpm).
	_prepare_save(3, {"3": ["tramuntana", "drac"]}, 3)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 5.0)))
	var menu := await _open_arcade_page(game)
	assert_false(menu.arcade_tier_unlocked(4), "vorher gesperrt")
	assert_eq(_tier_items(menu)[3][0], "Stufe 4 (gesperrt – Bosse auf Stufe 3: 2/3)")
	await _start_arcade(game, BOSSES.find("dimonis"))
	assert_eq(game.arcade.tier, 3)
	for i in range(roundi(90.0 / DT)):
		if not game.arcade.results.is_empty():
			break
		game._ride(DT)
		game._update_view()
	assert_eq(game.arcade.results.size(), 1)
	assert_true(game.arcade.results[0]["succeeded"], "Dimonis besiegt")
	assert_eq(ArcadeTiers.unlocked(game.save_game), 3, "freigeschaltet wird mit dem Speichern der Fahrt")
	game.settings_menu.ride_end_requested.emit()
	assert_eq(ArcadeTiers.unlocked(game.save_game), 4, "Stufe 3 abgeschlossen: Stufe 4 frei")
	assert_string_contains(game.arcade_result(), "Stufe 4 freigeschaltet!")
	var loaded := SaveGame.load_file(SAVE_PATH)
	assert_eq(ArcadeTiers.unlocked(loaded), 4, "steht auf der Platte")
	assert_eq(ArcadeTiers.defeated(loaded, 3), ["tramuntana", "drac", "dimonis"])
	game._enter_menu()  # im Ergebnis: Enter
	assert_true(game.start_menu.visible, "zurück im Menü")
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["arcade"].pressed.emit()
	assert_true(menu.arcade_tier_unlocked(4), "im Menü wählbar")
	assert_eq(_tier_items(menu)[3], ["Stufe 4", true])
	assert_eq(_tier_items(menu)[4][0], "Stufe 5 (gesperrt – Bosse auf Stufe 4: 0/3)", "das nächste Ziel")


func test_a_boss_lost_or_a_lower_tier_unlocks_nothing() -> void:
	# Stufe 2 gewählt, dort fehlt nur noch Dimonis – auch ein Sieg schaltet nichts frei (Stufe 3 ist schon frei);
	# die Zusammenfassung nennt das Ziel nur für die höchste freie Stufe.
	_prepare_save(3, {"2": ["tramuntana", "drac"], "3": ["drac"]}, 2)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 5.0)))
	await _open_arcade_page(game)
	await _start_arcade(game, BOSSES.find("dimonis"))
	for i in range(roundi(90.0 / DT)):
		if not game.arcade.results.is_empty():
			break
		game._ride(DT)
	assert_true(game.arcade.results[0]["succeeded"])
	game.settings_menu.ride_end_requested.emit()
	assert_true(ArcadeTiers.completed(game.save_game, 2), "Stufe 2 abgeschlossen")
	assert_eq(ArcadeTiers.unlocked(game.save_game), 3, "aber nicht die höchste freie: nichts Neues")
	assert_false(game.arcade_result().contains("freigeschaltet"))
	assert_false(game.arcade_result().contains("Für Stufe"))


# --- Rundensteigerung im Lauf ----------------------------------------------------------------------------------------


func test_each_further_round_in_the_run_is_harder_and_more_rewarding() -> void:
	_prepare_save(3, {}, 1)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0)), 1.0)
	await _open_arcade_page(game)
	await _start_arcade(game, Encounters.find("zone_mitte"))
	var lap_length: float = game.track.length_m()
	var widths := {}
	var popups := []
	for i in range(roundi(200.0 / DT)):
		if game.model.distance_m > lap_length * 2.0 + 600.0:
			break
		game._ride(DT)
		game._update_view()
		var active: Dictionary = game.arcade.active
		if not active.is_empty():
			var zone: Vector2 = (active["block"] as ChallengeBlock).zone()
			widths[active["lap"]] = zone.y - zone.x
		for text in game.hud.popups():
			if text.begins_with("Runde") and not popups.has(text):
				popups.append(text)
	assert_eq(widths.keys().slice(0, 3), [0, 1, 2], "in drei Runden gespielt")
	assert_eq(widths.values().slice(0, 3), [20.0, 19.0, 18.0], "die Zone der zweiten Runde ist enger, die der dritten noch mehr")
	var points := {}
	for result in game.arcade.results:
		assert_true(result["succeeded"], "90 rpm treffen jede Runde")
		points[result["lap"]] = result["points"]
	assert_eq([points.get(0), points.get(1), points.get(2)], [100, 110, 120], "und lohnender")
	assert_eq(popups, ["Runde 2 – härter und lohnender", "Runde 3 – härter und lohnender"])
	game.settings_menu.ride_end_requested.emit()
	assert_string_contains(game.arcade_result(), "Runde 3 erreicht: Zonen 2 rpm schmaler · Punkte +20 %")
	assert_false(game.arcade_result().contains("Für Stufe"), "Stufe 1 ist nicht die höchste freie: kein Ziel")
