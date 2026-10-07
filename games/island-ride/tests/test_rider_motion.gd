## Bewegung von Fahrer und Rad als reine Logik: Kadenz/Tempo/Steigung/Kurve/Pause rein → Kurbel, Räder, Pose raus.
extends GutTest

const DT := 1.0 / 60.0


func _run(motion: RiderMotion, cadence: float, speed: float, seconds: float, grade: float = 0.0,
		curvature: float = 0.0, paused: bool = false) -> void:
	for i in range(int(round(seconds / DT))):
		motion.step(cadence, speed, grade, curvature, paused, DT)


func test_crank_turns_once_per_second_at_60_rpm() -> void:
	var motion := RiderMotion.new()
	_run(motion, 60.0, 5.0, 0.25)
	assert_almost_eq(motion.crank_angle, PI / 2.0, 0.001, "Viertelumdrehung nach 0,25 s")
	_run(motion, 60.0, 5.0, 0.75)
	assert_almost_eq(absf(angle_difference(motion.crank_angle, 0.0)), 0.0, 0.001, "volle Umdrehung nach 1 s")
	assert_almost_eq(RiderMotion.crank_advance(90.0, 1.0), 1.5 * TAU, 0.0001, "90 rpm → 1,5 Umdrehungen/s")


func test_crank_and_legs_stand_still_at_zero_cadence_and_in_pause() -> void:
	var motion := RiderMotion.new()
	_run(motion, 80.0, 8.0, 0.3)
	var angle := motion.crank_angle
	_run(motion, 0.0, 8.0, 0.5)
	assert_eq(motion.crank_angle, angle, "Kadenz 0: Kurbel steht")
	_run(motion, 90.0, 8.0, 0.5, 0.0, 0.0, true)
	assert_eq(motion.crank_angle, angle, "Pause: Kurbel steht trotz Kadenz")


func test_wheels_roll_with_speed() -> void:
	var motion := RiderMotion.new()
	var one_turn_per_second := RiderMotion.WHEEL_DIAMETER_M * PI
	_run(motion, 80.0, one_turn_per_second, 0.25)
	assert_almost_eq(motion.wheel_angle, PI / 2.0, 0.001, "Umfang je Sekunde → Viertelumdrehung nach 0,25 s")
	assert_almost_eq(RiderMotion.wheel_advance(10.0, 1.0), 10.0 / 0.34, 0.0001, "v · dt / r")
	assert_gt(RiderMotion.wheel_advance(10.0, 1.0), RiderMotion.wheel_advance(5.0, 1.0), "schneller → schneller rollen")


func test_wheels_roll_out_without_cadence_but_stand_in_pause() -> void:
	var motion := RiderMotion.new()
	_run(motion, 0.0, 6.0, 0.1)
	assert_gt(motion.wheel_angle, 0.0, "Kadenz 0, Rad rollt aus")
	var angle := motion.wheel_angle
	_run(motion, 0.0, 6.0, 0.5, 0.0, 0.0, true)
	assert_eq(motion.wheel_angle, angle, "Pause: Räder stehen")


## Punkt auf einem Kreis mit Radius `radius`: Start im Ursprung, Fahrtrichtung −Z, Linkskurve.
func _on_left_circle(s: float, radius: float) -> Vector3:
	var t := s / radius
	return Vector3(-radius + radius * cos(t), 0.0, -radius * sin(t))


func test_curvature_sign_and_size() -> void:
	var r := 20.0
	var left := RiderMotion.signed_curvature(_on_left_circle(-4.0, r), _on_left_circle(0.0, r), _on_left_circle(4.0, r))
	assert_almost_eq(left, 1.0 / r, 0.001, "Linkskurve positiv, 1/r")
	var flip := Vector3(-1.0, 1.0, 1.0)
	var right := RiderMotion.signed_curvature(_on_left_circle(-4.0, r) * flip, Vector3.ZERO, _on_left_circle(4.0, r) * flip)
	assert_almost_eq(right, -1.0 / r, 0.001, "Rechtskurve negativ")
	assert_eq(RiderMotion.signed_curvature(Vector3(0, 0, 4), Vector3.ZERO, Vector3(0, 1, -4)), 0.0, "geradeaus, auch bergauf")


func test_leans_slightly_into_curves() -> void:
	var motion := RiderMotion.new()
	_run(motion, 80.0, 5.0, 3.0, 0.0, 1.0 / 20.0)
	assert_almost_eq(motion.lean, atan(25.0 / 20.0 / RiderMotion.GRAVITY), 0.01, "links: atan(v²κ/g)")
	_run(motion, 80.0, 12.0, 3.0, 0.0, -1.0 / 15.0)
	assert_almost_eq(motion.lean, -RiderMotion.MAX_LEAN_RAD, 0.001, "rechts, schnell: begrenzt")
	_run(motion, 80.0, 12.0, 3.0)
	assert_almost_eq(motion.lean, 0.0, 0.001, "geradeaus aufrecht")
	_run(motion, 80.0, 12.0, 3.0, 0.0, 1.0 / 20.0, true)
	assert_almost_eq(motion.lean, 0.0, 0.001, "in der Pause aufrecht")


func test_bends_forward_uphill_only() -> void:
	var motion := RiderMotion.new()
	_run(motion, 80.0, 4.0, 6.0, 0.06)
	var climb := motion.bend
	assert_gt(climb, 0.05, "bergauf vorgebeugt")
	_run(motion, 80.0, 4.0, 6.0, 0.10)
	assert_gt(motion.bend, climb, "steiler → mehr")
	assert_lte(motion.bend, RiderMotion.MAX_BEND_RAD + 0.0001, "begrenzt")
	_run(motion, 80.0, 12.0, 8.0, -0.08)
	assert_almost_eq(motion.bend, 0.0, 0.001, "bergab nicht")


func test_sways_only_while_pedaling() -> void:
	var motion := RiderMotion.new()
	_run(motion, 60.0, 6.0, 2.25)  # rechtes Pedal waagrecht vorn
	assert_almost_eq(motion.sway(), 1.0, 0.01, "voller Tritt rechts")
	_run(motion, 0.0, 6.0, 3.0)
	assert_almost_eq(motion.sway(), 0.0, 0.01, "kein Tritt, kein Wiegen")


func test_joint_keeps_limb_lengths_and_bends_towards_pole() -> void:
	var hip := Vector3(0, 1, 0)
	var ankle := Vector3(0, 0.3, 0.1)
	var knee := RiderMotion.joint_point(hip, ankle, 0.46, 0.44, Vector3.FORWARD)
	assert_almost_eq(knee.distance_to(hip), 0.46, 0.0001)
	assert_almost_eq(knee.distance_to(ankle), 0.44, 0.0001)
	assert_lt(knee.z, 0.0, "Knie nach vorn (−Z)")
	var reach := RiderMotion.joint_point(hip, Vector3(0, -2, 0), 0.46, 0.44, Vector3.FORWARD)
	assert_almost_eq(reach.distance_to(hip), 0.46, 0.0001, "zu weit: gestreckt")
	assert_almost_eq(reach.x, 0.0, 0.01)
	assert_almost_eq(reach.z, 0.0, 0.01)
