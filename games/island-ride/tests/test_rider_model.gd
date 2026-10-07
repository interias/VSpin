## Fahrer und Rad in der Hauptszene: Modell statt Kapsel, Kurbel und Räder folgen Kadenz, Tempo und Spielzustand.
extends "res://tests/support/bus_test.gd"


func _steady(cadence: float, seconds: float = 6.0) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(cadence, 0.0, seconds)


## Transform eines Knotens relativ zum Modell (auch ohne Szenenbaum).
func _in_model(node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	while node != null and not node is RiderModel:
		transform = node.transform * transform
		node = node.get_parent() as Node3D
	return transform


func test_main_scene_has_rider_model_instead_of_capsule() -> void:
	var ride := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	var model = ride.get_node_or_null("Track/Rider/Model")
	assert_true(model is RiderModel, "RiderModel unter Track/Rider")
	assert_null(ride.get_node_or_null("Track/Rider/Body"), "keine Kapsel mehr")
	for part in ["Lean/Bike", "Lean/FrontWheel", "Lean/RearWheel", "Lean/Crank", "Lean/Rider/Torso/Head"]:
		assert_not_null(model.get_node_or_null(part), part)
	assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 40, "detailliertes Modell aus vielen Teilen")


func test_model_stands_on_the_road_and_has_rider_height() -> void:
	var model: RiderModel = autofree(RiderModel.new())
	var radius := RiderMotion.WHEEL_DIAMETER_M / 2.0
	assert_almost_eq(RiderModel.FRONT_AXLE.y, radius, 0.001, "Vorderrad steht auf")
	assert_almost_eq(RiderModel.REAR_AXLE.y, radius, 0.001, "Hinterrad steht auf")
	var head_y := _in_model(model.get_node("Lean/Rider/Torso/Head")).origin.y
	assert_between(head_y, 1.4, 1.8, "Kopf in Fahrerhöhe")


func test_feet_stay_on_the_pedals_all_the_way_round() -> void:
	var model: RiderModel = autofree(RiderModel.new())
	for i in range(12):
		model.update(60.0, 7.0, 0.0, 0.0, false, 1.0 / 12.0)  # Kurbel in 30°-Schritten
		for side in range(2):
			var shin: Node3D = model.get_node("Lean/Rider/Shin%d" % side)
			var ankle := shin.transform * Vector3(0, RiderModel.SHIN, 0)
			var target := model.pedal_position(side) + RiderModel.ANKLE_FROM_PEDAL
			assert_almost_eq(ankle.distance_to(target), 0.0, 0.02, "Fuß am Pedal, Seite %d, Schritt %d" % [side, i])


func test_hands_reach_the_bar_uphill_and_flat() -> void:
	var model: RiderModel = autofree(RiderModel.new())
	for grade in [0.0, 0.1]:
		for i in range(120):
			model.update(80.0, 5.0, grade, 0.0, false, 1.0 / 60.0)
		for side in range(2):
			var forearm: Node3D = model.get_node("Lean/Rider/Forearm%d" % side)
			var hand := forearm.transform * Vector3(0, RiderModel.FOREARM, 0)
			var bar := RiderModel.HAND * Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0)
			assert_almost_eq(hand.distance_to(bar), 0.0, 0.03, "Hand am Lenker, Steigung %.2f, Seite %d" % [grade, side])


func test_crank_turns_with_cadence_while_riding_and_stops_in_pause() -> void:
	var ride := spawn_ride(start_fake_bus(_steady(90.0)), 20.0)
	assert_true(await run_until(func(): return ride.state == "riding", 3.0))
	var model: RiderModel = ride.get_node("Track/Rider/Model")
	var crank: Node3D = model.get_node("Lean/Crank")
	var wheel: Node3D = model.get_node("Lean/RearWheel")
	var crank_before := crank.rotation.x
	var wheel_before := wheel.rotation.x
	await run_for(0.3)
	assert_ne(crank.rotation.x, crank_before, "Kurbel dreht beim Fahren")
	assert_ne(wheel.rotation.x, wheel_before, "Rad rollt beim Fahren")
	await press_key(KEY_P)
	assert_eq(ride.state, "paused_manual")
	var crank_paused := crank.rotation.x
	var wheel_paused := wheel.rotation.x
	await run_for(0.5)
	assert_eq(crank.rotation.x, crank_paused, "Pause: Kurbel steht")
	assert_eq(wheel.rotation.x, wheel_paused, "Pause: Rad steht")
