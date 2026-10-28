## Pulszonen als reine Logik: LTHR (Friel), Maximalpuls, Vorrang, ungültige Werte, Farben.
extends GutTest

const LTHR := 170


func _ranges(z: HeartRateZones) -> Array:
	var out := []
	for i in range(1, 6):
		out.append(z.zone_range(i))
	return out


func test_lthr_zones_at_every_edge() -> void:
	# 170: 81 % = 137,7 → 138; 90 % = 153; 94 % = 159,8 → 160; 100 % = 170
	var z := HeartRateZones.new(LTHR)
	assert_true(z.has_zones())
	assert_eq(z.source(), HeartRateZones.Source.LTHR)
	assert_eq(z.zone_for(137), 1)
	assert_eq(z.zone_for(138), 2)
	assert_eq(z.zone_for(152), 2)
	assert_eq(z.zone_for(153), 3)
	assert_eq(z.zone_for(159), 3)
	assert_eq(z.zone_for(160), 4)
	assert_eq(z.zone_for(169), 4)
	assert_eq(z.zone_for(170), 5)
	assert_eq(z.zone_for(230), 5)
	assert_eq(z.zone_for(40), 1)


func test_lthr_ranges() -> void:
	var z := HeartRateZones.new(LTHR)
	assert_eq(_ranges(z), [
		Vector2i(0, 137), Vector2i(138, 152), Vector2i(153, 159),
		Vector2i(160, 169), Vector2i(170, HeartRateZones.OPEN)])


func test_max_hr_zones_at_every_edge() -> void:
	# 190: 50 % = 95, 60 % = 114, 70 % = 133, 80 % = 152, 90 % = 171
	var z := HeartRateZones.new(0, 190)
	assert_true(z.has_zones())
	assert_eq(z.source(), HeartRateZones.Source.MAX_HR)
	assert_eq(z.zone_for(94), 1, "unter 50 % zählt als Z1")
	assert_eq(z.zone_for(95), 1)
	assert_eq(z.zone_for(113), 1)
	assert_eq(z.zone_for(114), 2)
	assert_eq(z.zone_for(132), 2)
	assert_eq(z.zone_for(133), 3)
	assert_eq(z.zone_for(151), 3)
	assert_eq(z.zone_for(152), 4)
	assert_eq(z.zone_for(170), 4)
	assert_eq(z.zone_for(171), 5)
	assert_eq(z.zone_for(200), 5, "über HFmax zählt als Z5")
	assert_eq(_ranges(z), [
		Vector2i(95, 113), Vector2i(114, 132), Vector2i(133, 151),
		Vector2i(152, 170), Vector2i(171, 190)])


func test_lthr_has_priority_over_max_hr() -> void:
	var z := HeartRateZones.new(LTHR, 190)
	assert_eq(z.source(), HeartRateZones.Source.LTHR)
	assert_eq(z.zone_range(2), Vector2i(138, 152))


func test_invalid_lthr_falls_back_to_max_hr() -> void:
	var z := HeartRateZones.new(40, 190)
	assert_eq(z.source(), HeartRateZones.Source.MAX_HR)


func test_no_values_means_no_zones() -> void:
	for z in [HeartRateZones.new(), HeartRateZones.new(0, 0), HeartRateZones.new(-5, -5)]:
		assert_false(z.has_zones())
		assert_eq(z.source(), HeartRateZones.Source.NONE)
		assert_eq(z.zone_for(150), 0)
		assert_eq(z.zone_range(3), Vector2i.ZERO)


func test_implausible_values_count_as_unset() -> void:
	for v in [-1, 0, 79, 221, 1000]:
		assert_false(HeartRateZones.new(v).has_zones(), "LTHR %d" % v)
	for v in [-1, 0, 99, 231, 1000]:
		assert_false(HeartRateZones.new(0, v).has_zones(), "HFmax %d" % v)
	assert_true(HeartRateZones.new(80).has_zones())
	assert_true(HeartRateZones.new(220).has_zones())
	assert_true(HeartRateZones.new(0, 100).has_zones())
	assert_true(HeartRateZones.new(0, 230).has_zones())


func test_every_bpm_belongs_to_exactly_one_zone() -> void:
	for z in [HeartRateZones.new(LTHR), HeartRateZones.new(0, 190),
			HeartRateZones.new(80), HeartRateZones.new(220), HeartRateZones.new(0, 100),
			HeartRateZones.new(0, 230), HeartRateZones.new(163.4)]:
		var last := 1
		for bpm in range(30, 231):
			var zone: int = z.zone_for(bpm)
			assert_between(zone, 1, 5)
			assert_gte(zone, last, "Zonen steigen mit dem Puls (%d bpm)" % bpm)
			assert_lte(zone, last + 1, "keine übersprungene Zone bei %d bpm" % bpm)
			# Genau eine Zone enthält den Wert laut zone_range; die Randzonen sind offen.
			var hits := 0
			for i in range(1, 6):
				var r: Vector2i = z.zone_range(i)
				var lo := -1000 if i == 1 else r.x
				var hi := 1000 if i == 5 else r.y
				if bpm >= lo and bpm <= hi:
					hits += 1
					assert_eq(i, zone, "%d bpm" % bpm)
			assert_eq(hits, 1, "%d bpm in genau einer Zone" % bpm)
			last = zone


func test_zone_range_out_of_bounds() -> void:
	var z := HeartRateZones.new(LTHR)
	assert_eq(z.zone_range(0), Vector2i.ZERO)
	assert_eq(z.zone_range(6), Vector2i.ZERO)


func test_colors_set_and_distinct() -> void:
	var seen := []
	for i in range(1, 6):
		var c := HeartRateZones.color_for(i)
		assert_ne(c, Color.WHITE, "Z%d hat eine Farbe" % i)
		assert_false(c in seen, "Z%d unterscheidet sich" % i)
		seen.append(c)
	assert_eq(HeartRateZones.color_for(0), Color.WHITE)
	assert_eq(HeartRateZones.color_for(6), Color.WHITE)
	# Z1 grau, Z2 blau, Z3 grün, Z4 orange, Z5 rot
	var z1 := HeartRateZones.color_for(1)
	assert_almost_eq(z1.r, z1.b, 0.1)
	var z2 := HeartRateZones.color_for(2)
	assert_gt(z2.b, z2.r + 0.3)
	var z3 := HeartRateZones.color_for(3)
	assert_gt(z3.g, z3.r + 0.3)
	assert_gt(z3.g, z3.b + 0.3)
	var z4 := HeartRateZones.color_for(4)
	assert_gt(z4.r, z4.b + 0.5)
	assert_gt(z4.g, 0.5)
	var z5 := HeartRateZones.color_for(5)
	assert_gt(z5.r, z5.g + 0.4)
