## Fahrtstatistik als reine Logik: Fahrzeit, Ø Kadenz (zeitgewichtet), Ø Tempo = Strecke / Fahrzeit.
extends GutTest


func test_empty_stats_are_zero() -> void:
	var stats := RideStats.new()
	assert_eq(stats.ride_time_s, 0.0)
	assert_eq(stats.avg_cadence(), 0.0)
	assert_eq(stats.avg_speed_kmh(), 0.0)


func test_averages_are_time_weighted() -> void:
	var stats := RideStats.new()
	stats.add(1.0, 60.0, 5.0)
	stats.add(3.0, 90.0, 25.0)
	assert_almost_eq(stats.ride_time_s, 4.0, 1e-9)
	assert_almost_eq(stats.distance_m, 30.0, 1e-9)
	assert_almost_eq(stats.avg_cadence(), (60.0 * 1.0 + 90.0 * 3.0) / 4.0, 1e-9)
	assert_almost_eq(stats.avg_speed_kmh(), 30.0 / 4.0 * 3.6, 1e-9)


func test_non_positive_time_is_ignored() -> void:
	var stats := RideStats.new()
	stats.add(2.0, 80.0, 10.0)
	stats.add(0.0, 200.0, 50.0)
	stats.add(-1.0, 200.0, 50.0)
	assert_eq(stats.avg_cadence(), 80.0)
	assert_eq(stats.distance_m, 10.0)
