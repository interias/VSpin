## Konfigurationsdatei: Bus-Adresse und Fahrmodell-Parameter wirken ohne Codeänderung.
extends GutTest


func test_game_config_points_to_bus_default() -> void:
	var config := RideConfig.load_file()
	assert_eq(config.bus_url, "ws://127.0.0.1:8765")
	assert_gt(config.k_kmh_per_rpm, 0.0)


func test_values_are_read_from_file() -> void:
	var config := RideConfig.load_file("res://tests/fixtures/steep_feel.cfg")
	assert_eq(config.bus_url, "ws://127.0.0.1:18799")
	assert_eq(config.bus_reconnect_s, 0.5)
	assert_eq(config.bus_connect_timeout_s, 1.5)
	assert_eq(config.uphill_damping, 20.0)
	assert_eq(config.downhill_boost, 6.0)
	assert_eq(config.inertia_s, 0.0)
	assert_eq(config.track, RideConfig.TRACK_GRAYBOX)


func test_missing_keys_fall_back_to_defaults() -> void:
	var defaults := RideConfig.new()
	var config := RideConfig.load_file("res://tests/fixtures/partial.cfg")
	assert_eq(config.k_kmh_per_rpm, 0.4)
	assert_eq(config.bus_url, defaults.bus_url)
	assert_eq(config.inertia_s, defaults.inertia_s)
	assert_eq(config.track, RideConfig.TRACK_ISLAND, "ohne [world] → Insel-Rundkurs")


func test_unknown_track_falls_back_to_island() -> void:
	assert_eq(RideConfig.load_file("res://tests/fixtures/unknown_track.cfg").track, RideConfig.TRACK_ISLAND)


func test_missing_file_gives_defaults() -> void:
	var config := RideConfig.load_file("res://tests/fixtures/does_not_exist.cfg")
	assert_eq(config.bus_url, RideConfig.new().bus_url)


func test_config_file_changes_ride_feel() -> void:
	var standard := RideModel.new(RideConfig.load_file())
	var steep := RideModel.new(RideConfig.load_file("res://tests/fixtures/steep_feel.cfg"))
	assert_lt(steep.target_speed_mps(80.0, 0.06), standard.target_speed_mps(80.0, 0.06),
			"stärkere Dämpfung bergauf aus der Datei")
	assert_gt(steep.target_speed_mps(80.0, -0.06), standard.target_speed_mps(80.0, -0.06),
			"stärkere Verstärkung bergab aus der Datei")
	steep.step(80.0, 0.0, 0.1)
	assert_almost_eq(steep.speed_mps, steep.target_speed_mps(80.0, 0.0), 0.0001, "inertia_s=0 aus der Datei")
