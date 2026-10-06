## Fahrmodell als reine Logik: Kadenz/Steigung/Zeitschritt rein → Geschwindigkeit/Position raus.
extends GutTest

const DT := 1.0 / 60.0


func _ride(model: RideModel, cadence: float, grade: float, seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		model.step(cadence, grade, DT)


func _settled_kmh(cadence: float, grade: float, config: RideConfig = RideConfig.new()) -> float:
	var model := RideModel.new(config)
	_ride(model, cadence, grade, 20.0)
	return model.speed_kmh()


func test_more_cadence_is_faster() -> void:
	var slow := _settled_kmh(60.0, 0.0)
	var fast := _settled_kmh(90.0, 0.0)
	assert_gt(fast, slow)
	assert_almost_eq(fast / slow, 1.5, 0.01, "v_ziel = k · Kadenz ist linear")


func test_flat_speed_is_k_times_cadence() -> void:
	var config := RideConfig.new()
	assert_almost_eq(_settled_kmh(90.0, 0.0, config), config.k_kmh_per_rpm * 90.0, 0.01)


func test_uphill_slower_downhill_somewhat_faster() -> void:
	var flat := _settled_kmh(80.0, 0.0)
	var up := _settled_kmh(80.0, 0.06)
	var down := _settled_kmh(80.0, -0.06)
	assert_lt(up, flat, "bergauf langsamer")
	assert_gt(down, flat, "bergab schneller")
	assert_lt(down - flat, flat - up, "bergab nur leicht verstärkt, bergauf deutlich gedämpft")


func test_steeper_climb_is_slower() -> void:
	assert_lt(_settled_kmh(80.0, 0.10), _settled_kmh(80.0, 0.04))


func test_speed_has_inertia_when_accelerating() -> void:
	var model := RideModel.new(RideConfig.new())
	var target := model.target_speed_mps(90.0, 0.0)
	model.step(90.0, 0.0, DT)
	assert_gt(model.speed_mps, 0.0)
	assert_lt(model.speed_mps, target * 0.1, "kein Sprung auf die Zielgeschwindigkeit")
	var previous := model.speed_mps
	_ride(model, 90.0, 0.0, 1.0)
	assert_gt(model.speed_mps, previous)
	assert_lt(model.speed_mps, target)


func test_speed_has_inertia_when_cadence_drops() -> void:
	var model := RideModel.new(RideConfig.new())
	_ride(model, 90.0, 0.0, 20.0)
	var cruising := model.speed_kmh()
	_ride(model, 0.0, 0.0, 0.5)
	assert_lt(model.speed_kmh(), cruising)
	assert_gt(model.speed_kmh(), cruising * 0.5, "rollt aus statt sofort zu stehen")
	_ride(model, 0.0, 0.0, 20.0)
	assert_almost_eq(model.speed_kmh(), 0.0, 0.01)


func test_inertia_zero_reaches_target_immediately() -> void:
	var config := RideConfig.new()
	config.inertia_s = 0.0
	var model := RideModel.new(config)
	model.step(90.0, 0.0, DT)
	assert_almost_eq(model.speed_mps, model.target_speed_mps(90.0, 0.0), 0.0001)


func test_position_advances_with_speed() -> void:
	var model := RideModel.new(RideConfig.new(), 100.0)
	assert_eq(model.distance_m, 100.0)
	_ride(model, 90.0, 0.0, 20.0)
	var before := model.distance_m
	_ride(model, 90.0, 0.0, 2.0)
	assert_almost_eq(model.distance_m - before, model.speed_mps * 2.0, 0.1)


func test_negative_cadence_counts_as_zero() -> void:
	assert_eq(_settled_kmh(-30.0, 0.0), 0.0)
