## Beute und Ausrüstung (#49) gegen den Fake-Bus durch die echte Hauptszene: Beute fällt nach einer geschafften
## Herausforderung (Simulator-Profil „perfekt in der Zone“) mit Lichtsäule in Seltenheitsfarbe, Popups und Fund in der
## Zusammenfassung, landet im Spielstand; „knapp daneben“ gibt keine. Angelegte Ausrüstung wirkt im Arcade (breitere
## Zone: dasselbe Profil wird geschafft) und ist am Fahrer zu sehen – Rundfahrt und Training verhalten sich mit ihr
## identisch und zeigen die Garderobe (ADR-0010). Inventar nur im Menü: öffnen, vergleichen, anlegen, verwerten,
## gespeichert; Layout in 960×1040, 1920×1080 und 1152×648.
extends "res://tests/support/bus_test.gd"

const GEAR_MENU := preload("res://scenes/gear_menu.gd")
var SAVE_PATH := TestIsolation.path("test_arcade_loot_savegame.json")
const DT := 0.1


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _item(slot: String, rarity: String, stats: Dictionary) -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": ""}


## Stand mit angelegtem seltenem Helm (+6 rpm Zonenbreite), legendärem Trikot und magischem Talisman, auf der Platte.
func _geared_save() -> SaveGame:
	var save := SaveGame.new()
	for item in [_item("helm", Loot.RARE, {"zone_width_rpm": 6}),
			_item("trikot", Loot.LEGENDARY, {"points_pct": 20, "progress_pct": 10, "luck_pct": 10}),
			_item("talisman", Loot.MAGIC, {"luck_pct": 12, "points_pct": 5})]:
		Inventory.equip(save, Inventory.add(save, item)["id"])
	save.save_file(SAVE_PATH)
	return save


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus `bus`, Test-Spielstand.
func _spawn_on(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Arcade“, Stufe 1, 60–120 rpm, „Losfahren“ – fester Würfel, nur „zone_mitte“ (wie test_arcade_ride.gd).
func _start_arcade(game: Node) -> void:
	await run_for(0.2)
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find("zone_mitte")]
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	menu.buttons["arcade_start"].pressed.emit()


## Spielt das Bridge-Profil `name` (bridge/profiles/arcade) über den Fake-Bus im Gleichschritt durch das Spiel (wie
## test_arcade_ride.gd). Liefert {game, beam: [{i, visible, color}], popups, shown}.
func _play_profile(name: String) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn_on(bus)
	await run_for(0.3)
	await _start_arcade(game)
	game.set_process(false)
	var beam := []
	var popups := []
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
		beam.append({"i": i, "visible": game.loot_beam.visible, "color": game.loot_beam.color(),
				"ahead_m": game.loot_beam.ride_m - game.model.distance_m})
		for text in game.hud.popups():
			if not popups.has(text):
				popups.append(text)
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return {"game": game, "beam": beam, "popups": popups, "shown": shown}


func _message(game: Node) -> String:
	var label: Label = game.get_node("Hud/Message")
	return label.text if label.visible else ""


# --- Beute in der Fahrt --------------------------------------------------------------------------------------------


func test_loot_falls_after_a_won_challenge_with_beam_popups_and_save() -> void:
	var run := await _play_profile("zone_perfekt.toml")
	var game: Node = run["game"]
	assert_true(game.arcade.results[0]["succeeded"], "perfekt in der Zone: geschafft")
	assert_eq(game.arcade.found.size(), 1, "Beute ja")
	var item: Dictionary = game.arcade.found[0]
	assert_true(Loot.valid(item))
	var lit: Array = run["beam"].filter(func(b): return b["visible"])
	assert_false(lit.is_empty(), "Lichtsäule auf der Strecke")
	assert_eq(lit[0]["color"], Loot.color_of(item["rarity"]), "in der Farbe der Seltenheit")
	assert_almost_eq(lit[0]["ahead_m"], game.LOOT_AHEAD_M, 1.0, "kurz vor dem Fahrer")
	assert_lt(lit[-1]["ahead_m"], 0.0, "der Fahrer fährt durch sie hindurch")
	assert_false(run["beam"][-1]["visible"], "danach verschwindet sie")
	assert_has(run["popups"], "+100", "Zahlen-Popup der Punkte")
	assert_has(run["popups"], Loot.item_name(item), "Popup des Fundes")
	assert_has(run["shown"], "Zone halten geschafft!  +100 Punkte")
	assert_eq(Inventory.items(game.save_game), [], "in der Fahrt wird nichts verwaltet")
	game.hud.popup(Loot.item_name(item), Loot.color_of(item["rarity"]))  # läuft beim Fahrtende noch
	game.settings_menu.ride_end_requested.emit()
	game._update_view()
	assert_eq(game.hud.popups(), [], "die Zusammenfassung steht ohne Popups davor")
	assert_string_contains(_message(game), "Beute: " + Loot.item_name(item), "Fund in der Zusammenfassung")
	var saved := SaveGame.load_file(SAVE_PATH)
	var stored := Inventory.items(saved)
	assert_eq(stored.size(), 1, "der Spielstand enthält das Teil")
	assert_eq(stored[0]["slot"], item["slot"])
	assert_eq(stored[0]["rarity"], item["rarity"])
	assert_eq(Inventory.equipped(saved), {}, "angelegt wird nur im Menü")


func test_just_missed_gives_no_loot() -> void:
	var run := await _play_profile("zone_knapp_daneben.toml")
	var game: Node = run["game"]
	assert_false(game.arcade.results[0]["succeeded"])
	assert_eq(game.arcade.found, [], "knapp daneben (kein Fortschritt): Beute nein")
	assert_true(run["beam"].all(func(b): return not b["visible"]), "keine Lichtsäule")
	assert_false(run["popups"].has("+100"), "keine Punkte")
	game.settings_menu.ride_end_requested.emit()
	assert_eq(Inventory.items(SaveGame.load_file(SAVE_PATH)), [])


func test_gear_widens_the_zone_and_shows_on_the_rider_only_in_arcade() -> void:
	_geared_save()
	var run := await _play_profile("zone_knapp_daneben.toml")  # 102 rpm: ohne Ausrüstung knapp daneben
	var game: Node = run["game"]
	assert_eq(game.arcade.gear["zone_width_rpm"], 6)
	assert_true(game.arcade.results[0]["succeeded"], "mit +6 rpm Zonenbreite (77–103 rpm) geschafft")
	assert_eq(game.arcade.points, 125, "+25 % Punkte")
	assert_has(run["popups"], "+125")
	var rider: RiderModel = game.rider_model
	assert_eq(rider.material_color("helmet"), Loot.color_of(Loot.RARE), "Helm in Seltenheitsfarbe am Fahrer")
	assert_eq(rider.material_color("jersey"), Loot.color_of(Loot.LEGENDARY), "legendäres Trikot")
	assert_true(rider.talisman_visible(), "Talisman am Sattel")
	assert_eq(rider.material_color("talisman"), Loot.color_of(Loot.MAGIC))
	assert_eq(rider.material_color("frame"), RiderModel.FRAME_COLOR, "ohne Rahmen: Garderobe (Standard)")
	# Danach eine Rundfahrt: die Garderobe gilt, keine Ausrüstung.
	game.settings_menu.ride_end_requested.emit()
	await press_key(KEY_ENTER)
	assert_eq(game.state, "menu")
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	game.start_menu.buttons["start"].pressed.emit()
	assert_null(game.arcade)
	assert_eq(rider.material_color("helmet"), Wardrobe.PARTS["helm_weiss"]["colors"]["helmet"], "Rundfahrt: Garderobe")
	assert_eq(rider.material_color("jersey"), RiderModel.JERSEY_COLOR)
	assert_false(rider.talisman_visible(), "kein Talisman außerhalb des Arcade")


## Rundfahrt bzw. Training mit fester Kadenz in festen Schritten; liefert die beobachtbaren Werte.
func _drive(mode: String, gear: bool) -> Dictionary:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(92.0, 0.0, 5.0))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == "riding" and ride.bus.cadence == 92.0, 3.0))
	ride.set_process(false)
	if gear:
		var save: SaveGame = ride.save_game
		for item in [_item("rahmen", Loot.LEGENDARY, {"progress_pct": 18, "points_pct": 30, "zone_width_rpm": 6,
				"luck_pct": 30}), _item("schuhe", Loot.LEGENDARY, {"zone_width_rpm": 6, "progress_pct": 18})]:
			Inventory.equip(save, Inventory.add(save, item)["id"])
	if mode == SaveGame.MODE_TRAINING:
		ride.start_ride(mode, 0, "", Training.load_all()[0])
	else:
		ride.start_ride(mode, 1)
	for i in range(1500):
		ride._ride(DT)
	var result := {"distance_m": ride.model.distance_m, "speed": ride.model.speed_mps, "laps": ride.lap_timing.lap_times,
			"time": ride.stats.ride_time_s, "talisman": ride.rider_model.talisman_visible(),
			"frame": ride.rider_model.material_color("frame")}
	if ride.training != null:
		result["score"] = ride.training.total_score()
		result["phase"] = ride.training.phase_index()
	return result


func test_round_trip_and_training_behave_identically_with_gear() -> void:
	# ADR-0010: Ausrüstung wirkt nur im Arcade-Modus – Fahrmodell, Runden, Training und Fahrer bleiben gleich.
	for mode in [SaveGame.MODE_ROUND_TRIP, SaveGame.MODE_TRAINING]:
		var plain := await _drive(mode, false)
		var geared := await _drive(mode, true)
		assert_eq(geared, plain, "%s mit angelegter Ausrüstung identisch" % mode)
		assert_false(geared["talisman"], "%s: keine Ausrüstung am Fahrer" % mode)
	assert_gt((await _drive(SaveGame.MODE_ROUND_TRIP, true))["laps"].size(), 0, "eine Runde gefahren")


# --- Inventar im Menü ----------------------------------------------------------------------------------------------


func test_gear_menu_from_arcade_page_compare_equip_salvage() -> void:
	var save := SaveGame.new()
	var worn := Inventory.add(save, _item("helm", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 6}))
	Inventory.equip(save, worn["id"])
	var candidate := Inventory.add(save, _item("helm", Loot.RARE, {"zone_width_rpm": 5, "points_pct": 4, "luck_pct": 9}))
	save.save_file(SAVE_PATH)
	var game := _spawn_on(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	assert_true(menu.buttons["arcade_gear"].is_visible_in_tree(), "„Ausrüstung“ auf der Seite „Arcade“")
	menu.buttons["arcade_gear"].pressed.emit()
	var gear: CanvasLayer = game.gear_menu
	assert_true(gear.visible, "Ausrüstung offen")
	assert_false(menu.visible, "Startmenü tritt zurück")
	await get_tree().process_frame
	assert_eq(gear.selected_id, candidate["id"], "neuestes Teil gewählt")
	assert_eq(game.get_viewport().gui_get_focus_owner(), gear.buttons["item_%d" % candidate["id"]])
	assert_string_contains(gear.info_text(), "Splitter: 0 · 2 Teile")
	assert_eq(gear.comparison_lines(), ["Angelegt: Magischer Helm", "Zonenbreite: +5 rpm · angelegt +3 rpm · +2",
			"Punkte: +4 % · angelegt +6 % · -2", "Beute-Glück: +9 % · angelegt +0 % · +9"], "Vergleich mit dem angelegten Helm")
	assert_has(gear.equipped_lines(), "Helm: Magischer Helm")
	assert_has(gear.equipped_lines(), "Rahmen: –")
	assert_string_contains(gear.buttons["item_%d" % worn["id"]].text, "angelegt")
	# Anlegen: sofort gespeichert.
	gear.buttons["equip"].pressed.emit()
	assert_eq(int(Inventory.equipped(game.save_game)["helm"]["id"]), candidate["id"])
	assert_eq(Inventory.equipped(SaveGame.load_file(SAVE_PATH))["helm"]["id"], float(candidate["id"]), "gespeichert")
	assert_true(gear.buttons["equip"].disabled, "angelegtes Teil: nichts mehr anzulegen")
	assert_true(gear.buttons["salvage"].disabled, "angelegt: nicht verwertbar")
	# Den alten Helm verwerten.
	gear.select(worn["id"])
	assert_string_contains(gear.buttons["salvage"].text, "+3 Splitter")
	gear.buttons["salvage"].pressed.emit()
	assert_eq(Inventory.items(game.save_game).size(), 1)
	assert_eq(Inventory.shards(game.save_game), 3)
	assert_eq(Inventory.shards(SaveGame.load_file(SAVE_PATH)), 3, "gespeichert")
	assert_string_contains(gear.info_text(), "Splitter: 3 · 1 Teil")
	assert_false(gear.buttons.has("item_%d" % worn["id"]), "aus der Liste")
	await press_key(KEY_ESCAPE)
	assert_false(gear.visible, "Esc schließt")
	assert_false(game.settings_menu.is_open())
	assert_true(menu.buttons["arcade_start"].is_visible_in_tree(), "zurück auf der Seite „Arcade“")
	assert_eq(game.get_viewport().gui_get_focus_owner(), menu.buttons["arcade_gear"])


func test_empty_inventory_says_where_loot_comes_from() -> void:
	var gear := await _gear_in(Vector2i(1920, 1080), SaveGame.new())
	assert_eq(gear.find_child("Empty", true, false).text, GEAR_MENU.EMPTY_TEXT)
	assert_true(gear.buttons["equip"].disabled)
	assert_true(gear.buttons["salvage"].disabled)
	assert_eq(gear.get_viewport().gui_get_focus_owner(), gear.buttons["back"])


## Ausrüstung in `viewport_size`, geöffnet mit `save`.
func _gear_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var gear: CanvasLayer = GEAR_MENU.new()
	viewport.add_child(gear)
	gear.open(save)
	await wait_process_frames(4)
	return gear


func _full_save() -> SaveGame:
	var save := SaveGame.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(30):
		var item := Inventory.add(save, Loot.roll(rng, 3.0))
		if i % 5 == 0:
			Inventory.equip(save, item["id"])
	return save


func _assert_gear_inside(gear: CanvasLayer, label: String) -> void:
	var screen: Rect2 = gear.get_node("Layout").get_viewport_rect()
	var scrolls := gear.find_children("*", "ScrollContainer", true, false)
	var checked := 0
	for control in gear.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control is ScrollBar \
				or scrolls.any(func(s): return s.is_ancestor_of(control)):
			continue
		checked += 1
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()), "%s: %s liegt im Fenster %s (%s)" % [
				label, control.name, screen, control.get_global_rect()])
	assert_gt(checked, 6, "%s: alle Anzeigen geprüft" % label)
	var items: Rect2 = gear.find_child("Items", true, false).get_global_rect()
	var detail: Rect2 = gear.find_child("Detail", true, false).get_global_rect()
	assert_false(items.intersects(detail), "%s: Liste neben den Werten" % label)
	assert_gt(items.size.x, 300.0, "%s: Liste breit genug" % label)
	var scroll: ScrollContainer = gear.find_child("Scroll", true, false)
	assert_true(scroll.get_v_scroll_bar().visible, "%s: viele Teile → scrollt" % label)
	for key in ["equip", "salvage"]:
		var rect: Rect2 = gear.buttons[key].get_global_rect()
		assert_true(detail.grow(0.5).encloses(rect), "%s: %s im Bereich der Werte (%s in %s)" % [label, key, rect, detail])


func test_layout_fits_half_and_full_screen() -> void:
	_assert_gear_inside(await _gear_in(Vector2i(960, 1040), _full_save()), "960×1040")
	_assert_gear_inside(await _gear_in(Vector2i(1920, 1080), _full_save()), "1920×1080")
	_assert_gear_inside(await _gear_in(Vector2i(1152, 648), _full_save()), "1152×648 (Godot-Standardfenster)")
