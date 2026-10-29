## ERG-Einheiten und FTP (Spec #75, Stories 12–14) als reine Logik: Watt-Ziele absolut und in % FTP, Startbarkeit ohne
## FTP, Bewertung an der Leistung im Zielband, Ansagen (Zielleistung statt Widerstandsknopf), FTP im Spielstand.
extends GutTest

const ERG_UNIT := "res://tests/fixtures/training_erg_short.json"
const SHORT_UNIT := "res://tests/fixtures/training_short.json"
const SWEET_SPOT := "res://trainings/watt_sweet_spot.json"
var BROKEN_PATH := TestIsolation.path("test_training_erg_broken.json")
var TEMP_PATH := TestIsolation.path("test_training_erg_savegame.json")


func after_each() -> void:
	for path in [BROKEN_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _load(phases: Array) -> Dictionary:
	var file := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"name": "Test", "phases": phases}))
	file.close()
	return Training.load_file(BROKEN_PATH)


# --- Format ---

func test_sweet_spot_unit_is_an_erg_unit_in_percent_of_ftp() -> void:
	var unit := Training.load_file(SWEET_SPOT)
	assert_true(unit["erg"], "Watt-Ziele: ERG-Einheit")
	assert_true(Training.needs_ftp(unit))
	assert_false(Training.startable(unit, 0), "ohne FTP nicht startbar")
	assert_true(Training.startable(unit, 250))
	var training := Training.new(unit, 250)
	assert_eq(training.target_power_w(), 138, "Aufwärmen 55 % von 250 W, gerundet")
	assert_eq(Training.target_text(training.phases[1]), "225 W", "Sweet Spot 90 %")
	assert_between(training.duration_s() / 60.0, 20.0, 60.0)
	assert_eq(Training.target_text(Training.new(unit).phases[1]), "– W", "ohne FTP kein Wert")
	assert_eq(Training.new(unit).target_power_w(), -1)


func test_absolute_watts_need_no_ftp_and_cadence_units_stay_cadence_units() -> void:
	var unit := _load([{"name": "A", "kind": "warmup", "duration_s": 60, "power_w": 180}])
	assert_true(unit["erg"])
	assert_false(Training.needs_ftp(unit))
	assert_true(Training.startable(unit, 0))
	assert_eq(Training.new(unit).target_power_w(), 180)
	var cadence := Training.load_file(SHORT_UNIT)
	assert_false(cadence["erg"], "Kadenz-Einheit")
	assert_true(Training.startable(cadence, 0))
	assert_eq(Training.target_text(Training.new(cadence).phases[0]), "80–100 rpm")


func test_invalid_power_targets_are_rejected() -> void:
	var cases := [
		[{"name": "A", "kind": "warmup", "duration_s": 60, "power_w": 180},
				{"name": "B", "kind": "work", "duration_s": 60, "cadence_rpm": [90, 100]}],  # gemischt
		[{"name": "A", "kind": "warmup", "duration_s": 60, "power_w": 180, "power_ftp": 0.5}],  # beides
		[{"name": "A", "kind": "warmup", "duration_s": 60, "power_w": -5}],
		[{"name": "A", "kind": "warmup", "duration_s": 60, "power_ftp": "0.5"}],
		[{"name": "A", "kind": "warmup", "duration_s": 60}],  # weder Kadenz noch Watt
	]
	for phases in cases:
		assert_eq(_load(phases), {}, "ungültig: %s" % JSON.stringify(phases))


# --- Bewertung und Ansage ---

func test_score_counts_the_power_in_the_band_not_the_cadence() -> void:
	var training := Training.new(Training.load_file(ERG_UNIT), 250)
	assert_eq(Training.power_range(training.phases[0]), [140.0, 160.0], "150 W: ± 10 W (5 % wären 7,5)")
	assert_eq(Training.power_range(training.phases[1]), [237.5, 262.5], "250 W: ± 5 %")
	training.advance(0.0, 1.0, 145.0)  # Kadenz egal, Leistung im Band
	training.advance(95.0, 1.0, 175.0)  # Kadenz „gut“, Leistung daneben
	assert_almost_eq(training.phase_score(0), 0.5, 0.001)
	training.advance(90.0, 1.0, NAN)  # keine Leistung: nicht im Ziel
	training.advance(90.0, 1.0, 262.5)  # Grenze eingeschlossen
	assert_almost_eq(training.phase_score(1), 0.5, 0.001)
	var cadence := Training.new(Training.load_file(SHORT_UNIT))
	cadence.advance(90.0, 1.0, 0.0)
	assert_almost_eq(cadence.phase_score(0), 1.0, 0.001, "Kadenz-Einheiten werten weiter die Kadenz")


func test_erg_unit_announces_the_target_power() -> void:
	var training := Training.new(Training.load_file(SWEET_SPOT), 250)
	assert_eq(training.announcement(), "138 W", "zu Beginn die eigene Zielleistung")
	training.advance(90.0, 472.0, 138.0)
	assert_eq(training.announcement(), "In 8 s: 225 W")
	assert_eq(training.announcement(false), "In 8 s: 225 W", "auch mit VSpin am Widerstand")


func test_knob_announcement_is_dropped_when_vspin_controls_the_trainer() -> void:
	var training := Training.new(Training.load_file(SHORT_UNIT))
	assert_string_contains(training.announcement(), "Widerstand")
	assert_eq(training.announcement(false), "", "VSpin regelt den Widerstand: keine Ansage zum Knopf")
	training.advance(90.0, 12.0)
	assert_string_contains(training.announcement(), "In 8 s: Widerstand")
	assert_eq(training.announcement(false), "")


# --- FTP im Spielstand ---

func test_ftp_defaults_to_not_set_has_limits_and_survives_restart() -> void:
	var save := SaveGame.new()
	assert_eq(save.ftp(), 0, "nicht gesetzt")
	for watts in [49, 601, -10]:
		assert_false(save.set_ftp(watts), "abgewiesen: %d" % watts)
	assert_eq(save.ftp(), 0)
	assert_true(save.set_ftp(SaveGame.FTP_MIN))
	assert_true(save.set_ftp(SaveGame.FTP_MAX))
	assert_true(save.set_ftp(250))
	save.set_heart_rate_profile(168, 190)  # LTHR/Maximalpuls lassen die FTP stehen
	assert_eq(save.save_file(TEMP_PATH), OK)
	var text := FileAccess.get_file_as_string(TEMP_PATH)
	for raw in ["power", "watt", "cadence"]:
		assert_false(text.containsn(raw), "keine Rohtelemetrie-Wörter im Spielstand: %s" % raw)
	var loaded := SaveGame.load_file(TEMP_PATH)
	assert_eq(loaded.ftp(), 250)
	assert_eq(loaded.lthr_bpm(), 168)
	assert_eq(loaded.version(), 1, "additiv: die Formatversion bleibt")
	assert_true(loaded.set_ftp(0), "0 = nicht gesetzt")
	assert_eq(loaded.ftp(), 0)


func test_older_save_without_ftp_stays_valid() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "active_profile": "00112233aabbccdd", "profiles": {"00112233aabbccdd": {'
			+ '"created": "2026-10-01T08:00:00Z", "rides": [], "pulse": {"lthr_bpm": 170, "max_hr_bpm": 0}}}}')
	file.close()
	var save := SaveGame.load_file(TEMP_PATH)
	assert_eq(save.ftp(), 0, "ohne Eintrag nicht gesetzt")
	assert_eq(save.lthr_bpm(), 170, "alte Werte bleiben")
	assert_false(FileAccess.file_exists(TEMP_PATH + SaveGame.BROKEN_SUFFIX), "nicht beiseitegelegt")
