## Pulsstatistik einer Fahrt als reine Logik: Ø zeitgewichtet, Max, Zeit je Zone, Lücken ohne Puls.
extends GutTest


func test_empty_stats() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	assert_false(s.has_pulse())
	assert_eq(s.avg_bpm(), 0.0)
	assert_eq(s.max_bpm, 0)
	assert_eq(s.zone_seconds(), [0.0, 0.0, 0.0, 0.0, 0.0] as Array[float])


func test_average_is_time_weighted_and_max_tracked() -> void:
	var s := HeartRateStats.new()
	s.add(1.0, 100)
	s.add(3.0, 140.0)
	s.add(1.0, 120)
	assert_true(s.has_pulse())
	assert_almost_eq(s.pulse_time_s, 5.0, 1e-9)
	assert_almost_eq(s.avg_bpm(), (100.0 + 420.0 + 120.0) / 5.0, 1e-9)
	assert_eq(s.max_bpm, 140)


func test_seconds_per_zone() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(2.0, 100)  # Z1
	s.add(1.5, 140)  # Z2
	s.add(0.5, 155)  # Z3
	s.add(1.0, 165)  # Z4
	s.add(4.0, 180)  # Z5
	s.add(1.0, 100)  # Z1
	assert_eq(s.zone_seconds(), [3.0, 1.5, 0.5, 1.0, 4.0] as Array[float])


func test_gaps_without_pulse_count_nowhere() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(2.0, 155)
	s.add(10.0, null)
	s.add(10.0, 0)
	s.add(10.0)
	s.add(2.0, 155)
	assert_almost_eq(s.pulse_time_s, 4.0, 1e-9)
	assert_almost_eq(s.avg_bpm(), 155.0, 1e-9)
	assert_eq(s.zone_seconds(), [0.0, 0.0, 4.0, 0.0, 0.0] as Array[float])


func test_non_finite_values_count_as_gap() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(1.0, NAN)
	s.add(1.0, INF)
	s.add(NAN, 150)
	s.add(INF, 150)
	assert_false(s.has_pulse())
	assert_eq(s.avg_bpm(), 0.0)
	assert_eq(s.max_bpm, 0)
	assert_eq(s.zone_seconds(), [0.0, 0.0, 0.0, 0.0, 0.0] as Array[float])


func test_only_gaps_means_no_pulse() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(5.0, null)
	assert_false(s.has_pulse())
	assert_eq(s.avg_bpm(), 0.0)


func test_without_zones_avg_and_max_remain() -> void:
	for zones in [null, HeartRateZones.new()]:
		var s := HeartRateStats.new(zones)
		s.add(2.0, 120)
		s.add(2.0, 160)
		assert_true(s.has_pulse())
		assert_almost_eq(s.avg_bpm(), 140.0, 1e-9)
		assert_eq(s.max_bpm, 160)
		assert_true(s.zone_seconds().is_empty())


func test_non_positive_time_is_ignored() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(0.0, 200)
	s.add(-1.0, 200)
	assert_false(s.has_pulse())
	assert_eq(s.max_bpm, 0)


func test_zone_seconds_is_a_copy() -> void:
	var s := HeartRateStats.new(HeartRateZones.new(170))
	s.add(1.0, 150)
	var z := s.zone_seconds()
	z[0] = 99.0
	assert_eq(s.zone_seconds()[0], 0.0)
