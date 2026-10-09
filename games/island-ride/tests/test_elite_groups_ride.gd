## Elite-Gruppen (#52) gegen den Fake-Bus durch die echte Hauptszene: die Simulator-Szenarien der Bridge
## (`bridge/profiles/arcade/elite_*.toml`) mit genau ihrem Kadenzverlauf – Champions (blau, Jagd mit Windschnell und
## Gegenwind) abgehängt: Punkte und Beute; Seltene (gelb, Durchbruch mit Gegenwind und Zäh) mit Gefolge: der Anführer
## fällt, das Gefolge entkommt – weich verfehlt, die Fahrt geht weiter. Dazu die Sichtbarkeit: Standarte auf der Strecke
## und Schild im HUD in der Farbe der Stufe mit den Eigenschaften, vor dem Start als Ankündigung, und die Darstellung des
## Bausteins der laufenden Phase (Verfolger, Zugbrücke). Die Szenarien erzwingen die Gruppe über den Pool; eine
## zufällige Elite-Gruppe aus dem Standard-Pool erscheint im echten Spiel mit festem Seed.
extends "res://tests/support/bus_test.gd"

var SAVE_PATH := TestIsolation.path("test_elite_groups_ride_savegame.json")
const DT := 0.1


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _spawn(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## „Fahren → Arcade“, Stufe 1, 60–120 rpm, „Losfahren“ – mit festem Würfel und `pool` (null = Standard-Pool).
## Fähigkeiten (#50) sind hier nicht der Gegenstand: konstante Kadenz löste den Fokus aus.
func _start_arcade(game: Node, pool: Variant, seed_value: int = 1) -> void:
	await run_for(0.2)
	AbilityExtension.of(game.arcade_stage).enabled = false
	game.arcade_seed = seed_value
	if pool is Array:
		game.arcade_pool = pool
	var menu: CanvasLayer = game.start_menu
	menu.buttons["drive"].pressed.emit()
	menu.buttons["arcade"].pressed.emit()
	menu.buttons["arcade_start"].pressed.emit()


func _prop(game: Node) -> EliteProp:
	return game.arcade_stage.props["elite"]


## Spielt das Profil `name` mit der Elite-Gruppe `definition` im Gleichschritt durchs Spiel; je Schritt Zustand, Weg,
## Gruppe (Phase, Gefolge) und die Anzeige (Schild, Standarte, Verfolger, Zugbrücke, Zieltor).
func _play_profile(name: String, definition: Dictionary) -> Dictionary:
	var profile := SimProfile.load_toml(SimProfile.path("arcade/" + name))
	assert_false(profile.is_empty(), "Profil %s lesbar" % name)
	var bus := start_fake_bus(SimProfile.to_script(profile))
	bus.manual_clock_ms = 0
	var game := _spawn(bus)
	await run_for(0.3)  # verbinden; das Drehbuch steht noch bei 0 s
	await _start_arcade(game, [definition])
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
		var group: EliteGroup = game.arcade.active.get("block") as EliteGroup
		var prop := _prop(game)
		steps.append({"i": i, "state": game.state, "distance_m": game.model.distance_m, "active": group != null,
				"phase": group.index if group != null else -1, "retinue": group.in_retinue() if group != null else false,
				"badge": prop.badge.mode, "title": prop.badge.title_text(), "color": prop.badge.title_color(),
				"affixes": prop.badge.affix_text(), "line": prop.badge.phase_text(), "banner": prop.banner.visible,
				"banner_label": prop.banner.label_text(), "banner_color": prop.banner.color,
				"banner_ahead_m": prop.banner.ride_m - game.model.distance_m, "pursuer": game.arcade_pursuer.active,
				"bridge": game.arcade_bridge.visible, "finish_gate": game.arcade_finish_gate.visible,
				"results": game.arcade.results.size()})
		if game.arcade.results.size() > ends.size():
			ends.append({"i": i, "title": prop.badge.title_text(), "line": prop.badge.phase_text()})
		if not game.hud.celebration().is_empty() and not shown.has(game.hud.celebration()):
			shown.append(game.hud.celebration())
	return {"game": game, "steps": steps, "shown": shown, "ends": ends}


func test_scenario_elite_champions_escaped() -> void:
	var definition := EliteGroups.make(Encounters.find("jagd_verfolger"), EliteGroups.CHAMPION,
			["windschnell", "gegenwind"])
	var run := await _play_profile("elite_champion.toml", definition)
	var game: Node = run["game"]
	var steps: Array = run["steps"]
	var blue := Loot.color_of(Loot.MAGIC)
	# Vor dem Start: angekündigt – Schild und Standarte in Blau mit den Eigenschaften.
	var before := steps.filter(func(s): return s["state"] == "riding" and not s["active"] and s["results"] == 0)
	assert_false(before.is_empty())
	assert_eq(before[-1]["badge"], EliteBadge.ANNOUNCE)
	assert_eq(before[-1]["title"], "Champions: Jagd")
	assert_eq(before[-1]["color"], blue, "Champions blau")
	assert_eq(before[-1]["affixes"], "Windschnell · Gegenwind", "sichtbare Eigenschaften")
	assert_string_contains(before[-1]["line"], "voraus · noch")
	assert_true(before[-1]["banner"], "die Standarte steht am Startpunkt")
	assert_eq(before[-1]["banner_label"], "Champions: Jagd\nWindschnell · Gegenwind")
	assert_eq(before[-1]["banner_color"], blue)
	# Im Kampf: der Verfolger der Jagd, die Standarte zieht voraus mit, das Schild nennt Phase und Ziel (98 statt 93 rpm).
	var during := steps.filter(func(s): return s["active"])
	assert_false(during.is_empty())
	for s in during:
		assert_eq(s["badge"], EliteBadge.GROUP)
		assert_eq(s["line"], "Anführer · ab 98 rpm")
		assert_true(s["pursuer"], "der Verfolger läuft (Darstellung des Bausteins)")
		assert_true(s["banner"])
		assert_almost_eq(s["banner_ahead_m"], EliteProp.AHEAD_M, 0.5, "die Standarte voraus")
	# Abgehängt: Punkte (140 × 1,5), Beute, Einblendung; das Schild meldet das Ergebnis.
	assert_eq(game.arcade.results.size(), 1)
	var result: Dictionary = game.arcade.results[0]
	assert_true(result["succeeded"], "abgehängt")
	assert_eq(result["name"], "Champions: Jagd")
	assert_eq(game.arcade.points, 210)
	assert_false(result["loot"].is_empty(), "Elite-Beute")
	assert_has(run["shown"], "Champions: Jagd geschafft!  +210 Punkte")
	assert_eq(run["ends"][0]["line"], "geschafft – Elite-Beute")
	var after := steps.filter(func(s): return s["i"] > run["ends"][0]["i"])
	assert_true(after.any(func(s): return s["state"] == "riding"), "die Fahrt geht weiter")


func test_scenario_elite_rare_with_retinue_fails_softly() -> void:
	var definition := EliteGroups.make(Encounters.find("durchbruch_bruecke"), EliteGroups.RARE, ["gegenwind", "zaeh"])
	var run := await _play_profile("elite_selten.toml", definition)
	var game: Node = run["game"]
	var steps: Array = run["steps"]
	var yellow := Loot.color_of(Loot.RARE)
	var before := steps.filter(func(s): return s["state"] == "riding" and not s["active"] and s["results"] == 0)
	assert_eq(before[-1]["title"], "Seltene: Durchbruch")
	assert_eq(before[-1]["color"], yellow, "Seltene gelb")
	assert_eq(before[-1]["affixes"], "Gegenwind · Zäh")
	assert_string_contains(before[-1]["line"], "mit Gefolge (1)")
	assert_eq(before[-1]["banner_color"], yellow)
	# Erst der Anführer (Zugbrücke statt Zieltor), dann das Gefolge.
	var leader := steps.filter(func(s): return s["active"] and not s["retinue"])
	var retinue := steps.filter(func(s): return s["active"] and s["retinue"])
	assert_false(leader.is_empty())
	assert_false(retinue.is_empty(), "nach dem Anführer kommt das Gefolge")
	assert_lt(leader[-1]["i"], retinue[0]["i"])
	assert_eq(leader[0]["line"], "Anführer · ab 112 rpm", "Gegenwind: 108 → 112 rpm")
	assert_true(leader.any(func(s): return s["bridge"] and not s["finish_gate"]), "die Zugbrücke ist das Ziel des Anführers")
	assert_eq(retinue[0]["line"], "Gefolge 1/1 · ab 102 rpm")
	assert_true(retinue.all(func(s): return s["color"] == yellow and s["banner"]))
	# Das Gefolge entkommt: weich verfehlt, keine Punkte, die Fahrt geht weiter.
	assert_eq(game.arcade.results.size(), 1)
	assert_false(game.arcade.results[0]["succeeded"])
	assert_eq(game.arcade.points, 0)
	assert_has(run["shown"], "Seltene: Durchbruch verfehlt – weiter geht's")
	assert_eq(run["ends"][0]["line"], "verfehlt – weiter geht's")
	var after := steps.filter(func(s): return s["i"] > run["ends"][0]["i"])
	assert_true(after.any(func(s): return s["state"] == "riding"), "die Fahrt geht weiter")


func test_a_random_elite_group_appears_in_the_real_game() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 30.0))
	var game := _spawn(bus)
	await run_for(0.3)
	# Ein Seed, bei dem der Standard-Pool zuerst eine Elite-Gruppe würfelt (wie die Bühne den Lauf anlegt).
	var sections := ArcadeRun.sections_from_stations(game.track.ride_stations(), game.track.length_m())
	var seed_value := -1
	for candidate in range(1, 200):
		var probe := ArcadeRun.new(1, CadenceRange.new(), sections, game.track.length_m(), 0.0, candidate)
		if probe.planned[0]["definition"]["block"] == EliteGroups.ID:
			seed_value = candidate
			break
	assert_gt(seed_value, 0, "im Standard-Pool kommen Elite-Gruppen")
	await _start_arcade(game, null, seed_value)
	await run_for(1.0)
	assert_eq(game.arcade_pool, Encounters.CHALLENGES, "Standard-Pool, nichts erzwungen")
	var next: Dictionary = game.arcade.next_challenge() if game.arcade.active.is_empty() else game.arcade.active
	var definition: Dictionary = next["definition"]
	assert_eq(definition["block"], EliteGroups.ID, "zufällig gewürfelt")
	var prop := _prop(game)
	assert_eq(prop.badge.title_text(), definition["name"], "im HUD erkennbar")
	assert_eq(prop.badge.affix_text(), " · ".join(EliteGroups.affix_names(definition)))
	assert_eq(prop.badge.title_color(), EliteGroups.color_of(EliteGroups.rank_of(definition)))
	assert_true(prop.banner.visible, "auf der Strecke erkennbar")
