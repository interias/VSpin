## Arcade-Bühne und Bausteinregistrierung (#63): die Reihenfolge des Würfel-Pools bleibt (gleiche Würfe bei gleichem
## Seed), jeder Typ der Registry baut seinen Baustein über `Encounters.build`, unbekannte Typen liefern null; die Bühne
## meldet Ereignisse (Start, Ende, Fahrt gespeichert), und Hooks für Zusammenfassung und Lauf-Einstellung wirken – ohne
## sie ändert sich nichts (die Szenarien in test_arcade_ride.gd).
extends "res://tests/support/bus_test.gd"

const DT := 0.1
## Die Herausforderungen des Standardpools in der Reihenfolge von Epic-Kopf 78a1421 (#47). Neue Typen hängen sich hinten
## an (EncounterRegistry): geprüft wird der Anfang des Pools, Umsortieren oder Einschieben fällt auf, Anhängen nicht.
const POOL_IDS := ["zone_mitte", "zone_ruhig", "zone_zuegig", "durchbruch_bruecke", "durchbruch_spurt",
		"jagd_verfolger", "jagd_wild"]
## Die Typen dieser Zeit in der Reihenfolge der Registry, mit ihrem Baustein.
var type_blocks := {"zone_hold": ZoneHold, "breakthrough": Breakthrough, "chase": Chase}


func test_the_pool_keeps_its_order() -> void:
	var ids := Encounters.CHALLENGES.map(func(d): return d["id"])
	assert_eq(ids.slice(0, POOL_IDS.size()), POOL_IDS, "gleiche Reihenfolge = gleiche Würfe")


func test_every_registered_type_builds_its_block() -> void:
	assert_eq(EncounterRegistry.TYPES.keys().slice(0, type_blocks.size()), type_blocks.keys(), "Typen der Registry")
	var range_ := CadenceRange.new()
	for definition in Encounters.CHALLENGES:
		var block := Encounters.build(definition, 1, range_)
		assert_not_null(block, definition["id"])
		if type_blocks.has(definition["block"]):
			assert_true(is_instance_of(block, type_blocks[definition["block"]]), definition["id"])
		assert_eq(EncounterRegistry.type_of(definition["block"]).ID, definition["block"])


func test_an_unknown_type_builds_nothing() -> void:
	assert_null(EncounterRegistry.type_of("gibt_es_nicht"))
	assert_null(Encounters.build({"id": "x", "block": "gibt_es_nicht", "name": "X"}, 1, CadenceRange.new()))


func test_props_belong_to_registered_types() -> void:
	for id in ArcadeStage.PROPS:
		assert_true(EncounterRegistry.TYPES.has(id), "Darstellung für Typ %s" % id)


func test_the_stage_reports_events_and_runs_the_hooks() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 120.0))
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = ""
	add_child_autofree(game)
	await run_for(0.3)
	var stage: ArcadeStage = game.arcade_stage
	assert_false(stage.is_active(), "ohne Fahrt kein Lauf")
	var events := []
	stage.challenge_started.connect(func(entry): events.append("start:" + entry["definition"]["id"]))
	stage.challenge_ended.connect(func(result): events.append("end:" + result["id"]))
	stage.run_finished.connect(func(_run): events.append("finished"))
	var steps := [0]
	stage.stepped.connect(func(_m, _cadence, _raw, _dt): steps[0] += 1)
	stage.run_hooks.append(func(run, _save): run.loot_quality = 2.5)
	stage.summary_providers.append(func(_run): return ["Extra-Zeile"])
	game.arcade_seed = 1
	game.arcade_pool = [Encounters.find("zone_mitte")]
	game.start_ride(SaveGame.MODE_ARCADE, 0, "", {}, Track.DIRECTION_CW, 1)
	assert_eq(game.arcade.loot_quality, 2.5, "Hook stellt den Lauf ein")
	assert_true(await run_until(func(): return game.state == "riding" and game.bus.cadence > 0.0, 3.0))
	game.set_process(false)
	for i in range(roundi(120.0 / DT)):
		game._ride(DT)
		game._update_view()
		if game.arcade.results.size() > 0:
			break
	assert_eq(game.arcade.results.size(), 1, "eine Herausforderung gespielt")
	assert_eq(events.filter(func(e): return e != "finished"), ["start:zone_mitte", "end:zone_mitte"])
	assert_gt(steps[0], 100, "jeder Fahrschritt wird gemeldet")
	game.return_to_menu()
	assert_true(game.arcade_stage.has_result())
	assert_true("Extra-Zeile" in game.arcade_result(), "Zeile in der Zusammenfassung")
	assert_has(events, "finished", "Fahrt gespeichert")


func test_an_extension_attaches_itself_to_the_stage() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = ""
	add_child_autofree(game)
	await run_for(0.3)
	assert_eq(game.arcade_stage.extensions.size(), ArcadeStage.EXTENSIONS.size(), "die angemeldeten sind angelegt")
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nvar stage\nvar steps := 0\nfunc attach(owner_stage):\n\tstage = owner_stage\n" \
			+ "\towner_stage.stepped.connect(func(_m, _c, _r, _d): steps += 1)\n"
	script.reload()
	var extension = game.arcade_stage.add_extension(script)
	assert_true(extension.stage == game.arcade_stage, "attach bekam die Bühne")  # kein Objekt an GUT: ohne Skriptdatei
	assert_true(game.arcade_stage.extensions.has(extension), "die Bühne hält sie")
	game.arcade_stage.stepped.emit(0.0, 0.0, 0.0, 0.1)
	assert_eq(extension.steps, 1, "die Erweiterung hört auf die Signale")
