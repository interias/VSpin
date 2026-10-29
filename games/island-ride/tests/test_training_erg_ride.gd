## ERG-Ablauf gegen den Fake-Bus (Spec #75, Stories 12–14): `set_target_power` je Phase, nie `set_grade` in ERG, die
## Grundlast-Folge `null` → `set_grade 0` beim Verlassen von `riding`, gesperrte und ausgeblendete Gänge, Bewertung an
## der Leistung, ERG ohne steuerbaren Trainer, %-FTP-Einheit ohne FTP nicht startbar und die Ansage zum
## Widerstandsknopf nur ohne Trainersteuerung.
extends "res://tests/support/bus_test.gd"

const ERG_UNIT := "res://tests/fixtures/training_erg_short.json"
const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const SWEET_SPOT := "res://trainings/watt_sweet_spot.json"
const FTP := 250


## Bridge mit Trainer (Steuerung `control`) und gleichbleibender gemessener Leistung `power_w`.
func _steps(control: String, power_w: float = 150.0, until_s: float = 20.0) -> Array:
	return [FakeBusServer.status("connected", "ble", ["CADENCE", "POWER", "RESISTANCE_CONTROL", "SPEED"], 0.0, {},
			control)] + FakeBusServer.steady_cadence(85.0, 0.0, until_s, 0.25,
			{"power_w": power_w, "power_estimated": false})


## Fahrt mit der Einheit `path` (FTP des Spielstands `ftp`), gestartet, bevor ein Bild läuft.
func _start(bus: FakeBusServer, path: String = ERG_UNIT, ftp: int = FTP) -> Node:
	var ride := spawn_ride(bus, 20.0)
	ride.save_game.set_ftp(ftp)
	ride.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(path))
	return ride


## Steuerbefehle des Spiels in Reihenfolge, z. B. ["power 150", "power null", "grade 0.000"].
func _commands(bus: FakeBusServer) -> Array:
	var out := []
	for message in bus.received:
		if not (message is Dictionary):
			continue
		if message.get("type") == "set_grade":
			out.append("grade %.3f" % message["grade"])
		elif message.get("type") == "set_target_power":
			out.append("power %s" % ("null" if message["watts"] == null else str(int(message["watts"]))))
	return out


func _announcement(ride: Node) -> String:
	var label: Label = ride.hud.get_node("%Announcement")
	return label.text if label.visible else ""


func test_target_power_per_phase_no_grade_and_rest_load_at_the_end() -> void:
	var bus := start_fake_bus(_steps("active"))
	var ride := _start(bus)
	assert_true(ride.erg_ride())
	assert_true(await run_until(func(): return ride.state == "finished", 12.0), "Einheit zu Ende gefahren")
	await run_for(0.3)
	assert_eq(_commands(bus), ["power 150", "power 250", "power 100", "power null", "grade 0.000"],
			"je Phase die Zielleistung (Hart: 100 % von 250 W), nie eine Steigung, am Ende null und Steigung 0")
	assert_almost_eq(ride.training.phase_score(0), 1.0, 0.05, "150 W gemessen, Ziel 150 W")
	assert_eq(ride.training.phase_score(1), 0.0, "150 W gemessen, Ziel 250 W")
	assert_string_contains(ride.training_result(), "Zielleistung getroffen")


func test_manual_pause_sends_null_then_zero_grade_and_resume_sets_the_phase_target_again() -> void:
	var bus := start_fake_bus(_steps("active"))
	var ride := _start(bus, SWEET_SPOT)
	assert_true(await run_until(func(): return _commands(bus) == ["power 138"], 3.0))
	await press_key(KEY_P)
	assert_eq(ride.state, "paused_manual")
	assert_true(await run_until(func(): return _commands(bus).size() == 3, 1.0))
	assert_eq(_commands(bus), ["power 138", "power null", "grade 0.000"], "erst ERG aus, dann die Grundlast")
	await run_for(0.6)
	assert_eq(_commands(bus).size(), 3, "in der Pause nichts weiter")
	await press_key(KEY_P)
	assert_true(await run_until(func(): return _commands(bus).size() == 4, 1.5))
	assert_eq(_commands(bus)[-1], "power 138", "Weiterfahren: Zielleistung der laufenden Phase")
	ride.return_to_menu()
	assert_true(await run_until(func(): return _commands(bus).size() == 6, 1.0))
	assert_eq(_commands(bus).slice(4), ["power null", "grade 0.000"], "Menü: dieselbe Folge")


func test_gears_are_locked_and_hidden_in_erg_only() -> void:
	var bus := start_fake_bus(_steps("active"))
	var ride := _start(bus)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	assert_true(ride.gears.locked)
	assert_true(ride.gears_active(), "der Trainer ist steuerbar …")
	assert_false(ride.hud.readout().contains("Gang"), "… die Ganganzeige bleibt trotzdem aus")
	await press_key(KEY_UP)
	assert_eq(ride.gears.gear, ride.gears.neutral, "in ERG wird nicht geschaltet")
	assert_eq(ride.reported_grade(), ride.current_grade(), "kein Gangoffset")
	ride.start_ride(SaveGame.MODE_TRAINING, 0, "", Training.load_file(SHORT_UNIT))
	assert_false(ride.gears.locked, "Kadenz-Einheit: Gänge wie immer")
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	assert_true(ride.hud.readout().contains("Gang"))


func test_erg_unit_without_controllable_trainer_runs_on_without_erg() -> void:
	for control in ["none", "read_only", "lost"]:
		var bus := start_fake_bus(_steps(control, 140.0))  # Aufwärmen 138 W (± 10 W)
		var ride := _start(bus, SWEET_SPOT)
		assert_true(await run_until(func(): return ride.state == "riding", 3.0))
		await run_for(0.5)
		assert_eq(_commands(bus), [], "Steuerung %s: weder Zielleistung noch Steigung" % control)
		assert_eq(_announcement(ride), "138 W", "Steuerung %s: die Zielleistung wird angesagt" % control)
		assert_gt(ride.training.on_target_s[0], 0.0, "Steuerung %s: bewertet an der gemessenen Leistung" % control)
		ride.queue_free()
		await get_tree().process_frame


func test_knob_announcement_only_without_trainer_control() -> void:
	var bus := start_fake_bus(_steps("active", NAN))
	var ride := _start(bus, SHORT_UNIT)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	await run_for(0.2)
	assert_eq(_announcement(ride), "", "VSpin steuert den Trainer: keine Ansage zum Widerstandsknopf")
	assert_eq(_commands(bus)[0], "grade 0.000", "Kadenz-Einheit: Steigung wie bisher")
	ride.queue_free()
	await get_tree().process_frame
	var other := start_fake_bus(_steps("none", NAN))
	var without := _start(other, SHORT_UNIT)
	assert_true(await run_until(func(): return without.state == "riding", 3.0))
	await run_for(0.2)
	assert_string_contains(_announcement(without), "Widerstand", "ohne Trainersteuerung bleibt die Ansage")


func test_percent_ftp_unit_is_not_startable_without_ftp() -> void:
	var bus := start_fake_bus(_steps("active"))
	var ride := spawn_ride(bus, 20.0)
	var menu: CanvasLayer = ride.start_menu
	menu.set_training_units([Training.load_file(SWEET_SPOT)])
	menu.set_ftp(0)
	assert_true(menu.buttons["training_start"].disabled, "ohne FTP kein Losfahren")
	var info: Label = menu.find_child("TrainingInfo", true, false)
	assert_string_contains(info.text, "FTP")
	ride._on_ride_requested(SaveGame.MODE_TRAINING)  # auch an der Hauptszene vorbei nicht
	assert_null(ride.training)
	ride.save_game.set_ftp(FTP)
	menu.set_ftp(FTP)
	assert_false(menu.buttons["training_start"].disabled)
	assert_false(info.text.contains("Trag deine FTP"))
	ride._on_ride_requested(SaveGame.MODE_TRAINING)
	assert_not_null(ride.training)
	assert_eq(ride.training.target_power_w(), 138)
