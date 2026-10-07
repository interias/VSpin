## Fahrer auf dem Rennrad – stilisiertes Low-Poly-Modell aus Godot-Grundkörpern, ohne fremde Assets.
## Die Bewegung rechnet RiderMotion (headless testbar); dieses Modul baut die Geometrie und setzt die Posen.
##
##   update(cadence, speed_mps, grade, curvature, paused, delta)   einmal pro Frame aus der Hauptszene
##   make_ghost()   halbtransparente Kopie als Ghost (#32)
##
## Koordinaten (Meter): Ursprung am Boden unter der Radmitte, Fahrtrichtung −Z (wie PathFollow3D), rechts +X.
## Knoten: `Lean` (Schräglage um die Aufstandslinie) → `Bike` (Rahmen, starr), `FrontWheel`/`RearWheel` (rollen),
## `Crank` (Kurbel mit Kettenblatt, dreht), Pedale (bleiben waagrecht), `Torso` (Gelenk an der Hüfte, beugt und
## wiegt), Beine und Arme (Zwei-Glieder-IK: Hüfte → Pedal, Schulter → Bremsgriff).
## Die Geometrie entsteht in `_init`, damit das Modell auch ohne Szenenbaum aktualisiert werden kann.
class_name RiderModel
extends Node3D

## Rahmenpunkte (Seitenansicht, x = 0).
const REAR_AXLE := Vector3(0.0, 0.34, 0.50)
const FRONT_AXLE := Vector3(0.0, 0.34, -0.50)
const BOTTOM_BRACKET := Vector3(0.0, 0.27, 0.09)
const SEAT_CLUSTER := Vector3(0.0, 0.80, 0.245)
const HEAD_TOP := Vector3(0.0, 0.84, -0.37)
const HEAD_BOTTOM := Vector3(0.0, 0.70, -0.41)
const SADDLE := Vector3(0.0, 0.975, 0.30)
const BAR := Vector3(0.0, 0.89, -0.47)
const BAR_HALF_WIDTH := 0.21
const CRANK_LENGTH := 0.1725
const PEDAL_X := 0.12
## Fahrer: Hüftgelenke, Oberkörper (Länge, Neigung aus der Senkrechten), Glieder.
const HIP := Vector3(0.09, 1.03, 0.31)
const TORSO_LENGTH := 0.58
const TORSO_PITCH_RAD := deg_to_rad(55.0)
const SHOULDER_HALF_WIDTH := 0.19
const THIGH := 0.46
const SHIN := 0.44
const UPPER_ARM := 0.31
const FOREARM := 0.30
## Hände auf den Bremsgriffen (rechts; links gespiegelt).
const HAND := Vector3(0.21, 0.91, -0.53)
## Ferse/Knöchel relativ zum Pedal.
const ANKLE_FROM_PEDAL := Vector3(0.0, 0.075, 0.07)
## Wiegen mit dem Tritt (rad): Oberkörper und Rad gegenläufig.
const TORSO_SWAY_RAD := deg_to_rad(2.5)
const BIKE_ROCK_RAD := deg_to_rad(1.2)

const FRAME_COLOR := Color(0.82, 0.12, 0.1)
const JERSEY_COLOR := Color(0.05, 0.55, 0.78)
const SKIN_COLOR := Color(0.93, 0.72, 0.58)
## Ghost (#32): Deckkraft und Farbton, zu dem hin aufgehellt wird.
const GHOST_ALPHA := 0.45
const GHOST_TINT := Color(0.75, 0.9, 1.0)

var motion := RiderMotion.new()

var _lean: Node3D
var _front_wheel: Node3D
var _rear_wheel: Node3D
var _crank: Node3D
var _pedals: Array[Node3D] = []
var _torso: Node3D
var _head: Node3D
## Je Seite (0 = rechts, 1 = links): Oberschenkel, Unterschenkel, Schuh, Oberarm, Unterarm, Hand.
var _thighs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _shoes: Array[Node3D] = []
var _upper_arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _hands: Array[Node3D] = []

var _materials := {}


func _init() -> void:
	_lean = _node(self, "Lean")
	_build_bike()
	_build_rider()
	_apply_pose()


## Ein Frame: Bewegung vorrücken und Pose setzen. Pause = Fahrer steht (Kurbel und Räder still).
func update(cadence_rpm: float, speed_mps: float, grade: float, curvature: float, paused: bool, delta_s: float) -> void:
	motion.step(cadence_rpm, speed_mps, grade, curvature, paused, delta_s)
	_apply_pose()


## Als Ghost (#32): alle Materialien halbtransparent (Deckkraft `alpha`) und zu einem hellen Blau hin aufgehellt,
## kein Schattenwurf. Tiefe wird mitgeschrieben, damit innere Teile nicht durchscheinen; läuft auch im
## Compatibility-Renderer.
func make_ghost(alpha: float = GHOST_ALPHA) -> void:
	for key in _materials:
		var material: StandardMaterial3D = _materials[key]
		var color := material.albedo_color.lerp(GHOST_TINT, 0.45)
		color.a = alpha
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		material.metallic = 0.0
	for mesh in find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Pedalposition (Modellkoordinaten im Schräglage-Knoten) für Seite 0 = rechts, 1 = links beim aktuellen Kurbelwinkel.
func pedal_position(side: int) -> Vector3:
	var angle := motion.crank_angle + PI * side
	var x := PEDAL_X * (1.0 if side == 0 else -1.0)
	return BOTTOM_BRACKET + Vector3(x, cos(angle) * CRANK_LENGTH, -sin(angle) * CRANK_LENGTH)


func _apply_pose() -> void:
	var sway := motion.sway()
	_lean.rotation = Vector3(0.0, 0.0, motion.lean + BIKE_ROCK_RAD * sway)
	_front_wheel.rotation.x = -motion.wheel_angle
	_rear_wheel.rotation.x = -motion.wheel_angle
	_crank.rotation.x = -motion.crank_angle
	_torso.basis = Basis.from_euler(Vector3(-(TORSO_PITCH_RAD + motion.bend), 0.0, -TORSO_SWAY_RAD * sway))
	_head.rotation.x = (TORSO_PITCH_RAD + motion.bend) * 0.8
	for side in range(2):
		var mirror := 1.0 if side == 0 else -1.0
		var pedal := pedal_position(side)
		_pedals[side].position = pedal
		var hip := Vector3(HIP.x * mirror, HIP.y, HIP.z)
		var ankle := pedal + ANKLE_FROM_PEDAL
		var knee := RiderMotion.joint_point(hip, ankle, THIGH, SHIN, Vector3(0.08 * mirror, 0.3, -1.0))
		_aim(_thighs[side], hip, knee)
		_aim(_shins[side], knee, ankle)
		_shoes[side].position = pedal + Vector3(0.0, 0.045, 0.02)
		var shoulder := _torso.transform * Vector3(SHOULDER_HALF_WIDTH * mirror, TORSO_LENGTH - 0.04, 0.0)
		var hand := Vector3(HAND.x * mirror, HAND.y, HAND.z)
		var elbow := RiderMotion.joint_point(shoulder, hand, UPPER_ARM, FOREARM, Vector3(0.5 * mirror, -0.6, 0.4))
		_aim(_upper_arms[side], shoulder, elbow)
		_aim(_forearms[side], elbow, hand)
		_hands[side].position = hand


## Glied `node` (Ursprung am Gelenk, Länge entlang +Y) von `from` nach `to` ausrichten.
func _aim(node: Node3D, from: Vector3, to: Vector3) -> void:
	var up := (to - from).normalized()
	var back := Vector3.RIGHT.cross(up).normalized()
	node.transform = Transform3D(Basis(up.cross(back), up, back), from)


func _build_bike() -> void:
	var bike := _node(_lean, "Bike")
	var frame := _material("frame", FRAME_COLOR, 0.35, 0.3)
	var metal := _material("metal", Color(0.78, 0.79, 0.82), 0.3, 0.8)
	var black := _material("black", Color(0.07, 0.07, 0.08), 0.7)
	# Rahmen: Oberrohr, Unterrohr, Sitzrohr, Steuerrohr, Ketten- und Sitzstreben (beidseitig).
	_tube(bike, SEAT_CLUSTER, HEAD_TOP + Vector3(0, -0.02, 0), 0.016, frame)
	_tube(bike, BOTTOM_BRACKET, HEAD_BOTTOM, 0.022, frame)
	_tube(bike, BOTTOM_BRACKET, SEAT_CLUSTER, 0.018, frame)
	_tube(bike, HEAD_BOTTOM + Vector3(0, -0.02, 0.005), HEAD_TOP, 0.022, frame)
	for x in [-0.055, 0.055]:
		_tube(bike, BOTTOM_BRACKET + Vector3(x * 0.4, 0, 0), REAR_AXLE + Vector3(x, 0, 0), 0.011, frame)
		_tube(bike, SEAT_CLUSTER + Vector3(x * 0.3, -0.02, 0), REAR_AXLE + Vector3(x, 0, 0), 0.01, frame)
		_tube(bike, HEAD_BOTTOM + Vector3(x * 0.6, -0.02, 0.0), FRONT_AXLE + Vector3(x, 0, 0), 0.012, frame)
	_tube(bike, BOTTOM_BRACKET + Vector3(-0.045, 0, 0), BOTTOM_BRACKET + Vector3(0.045, 0, 0), 0.024, metal)
	# Trinkflasche am Unterrohr.
	var bottle_at := BOTTOM_BRACKET.lerp(HEAD_BOTTOM, 0.42) + Vector3(0, 0.05, 0.02)
	var bottle_dir := (HEAD_BOTTOM - BOTTOM_BRACKET).normalized()
	_tube(bike, bottle_at - bottle_dir * 0.1, bottle_at + bottle_dir * 0.1, 0.034, _material("bottle", Color(0.95, 0.95, 0.92), 0.6))
	# Sattelstütze, Sattel; Vorbau, Lenker (Oberlenker, Bremsgriffe, Unterlenker).
	_tube(bike, SEAT_CLUSTER, SADDLE + Vector3(0, -0.02, 0.01), 0.012, metal)
	_box(bike, SADDLE + Vector3(0, 0, 0.03), Vector3(0.13, 0.035, 0.16), black)
	_box(bike, SADDLE + Vector3(0, -0.002, -0.08), Vector3(0.06, 0.03, 0.14), black)
	_tube(bike, HEAD_TOP, BAR, 0.014, metal)
	_tube(bike, BAR + Vector3(-BAR_HALF_WIDTH, 0, 0), BAR + Vector3(BAR_HALF_WIDTH, 0, 0), 0.013, black)
	for mirror in [-1.0, 1.0]:
		var end := BAR + Vector3(BAR_HALF_WIDTH * mirror, 0, 0)
		var front := end + Vector3(0, -0.01, -0.08)
		var low := end + Vector3(0, -0.13, -0.09)
		_tube(bike, end, front, 0.013, black)
		_tube(bike, front, low, 0.013, black)
		_tube(bike, low, end + Vector3(0, -0.15, 0.0), 0.013, black)
		_tube(bike, front + Vector3(0, -0.01, 0), front + Vector3(0, 0.05, 0.0), 0.016, black)  # Bremsgriff
	# Kette (oben/unten) und Ritzel rechts.
	var chain := _material("chain", Color(0.3, 0.3, 0.32), 0.5, 0.6)
	_tube(bike, BOTTOM_BRACKET + Vector3(0.075, 0.105, 0), REAR_AXLE + Vector3(0.075, 0.045, 0), 0.004, chain)
	_tube(bike, BOTTOM_BRACKET + Vector3(0.075, -0.105, 0), REAR_AXLE + Vector3(0.075, -0.045, 0), 0.004, chain)
	_tube(bike, REAR_AXLE + Vector3(0.065, 0, 0), REAR_AXLE + Vector3(0.08, 0, 0), 0.045, metal)
	_front_wheel = _wheel("FrontWheel", FRONT_AXLE)
	_rear_wheel = _wheel("RearWheel", REAR_AXLE)
	# Kurbel: Kettenblatt rechts, zwei Kurbelarme (rechts bei Winkel 0 oben); Pedale bleiben waagrecht.
	_crank = _node(_lean, "Crank", BOTTOM_BRACKET)
	_tube(_crank, Vector3(0.07, 0, 0), Vector3(0.08, 0, 0), 0.105, metal, 24)
	_tube(_crank, Vector3(0.068, 0, 0), Vector3(0.082, 0, 0), 0.06, black, 12)
	_box(_crank, Vector3(0.09, CRANK_LENGTH / 2.0, 0), Vector3(0.016, CRANK_LENGTH + 0.03, 0.03), metal)
	_box(_crank, Vector3(-0.09, -CRANK_LENGTH / 2.0, 0), Vector3(0.016, CRANK_LENGTH + 0.03, 0.03), metal)
	for side in range(2):
		var pedal := _node(_lean, "Pedal%d" % side)
		_box(pedal, Vector3(0.01 * (1.0 if side == 0 else -1.0), 0, 0), Vector3(0.08, 0.02, 0.08), black)
		_pedals.append(pedal)


func _wheel(node_name: String, axle: Vector3) -> Node3D:
	var wheel := _node(_lean, node_name, axle)
	var radius := RiderMotion.WHEEL_DIAMETER_M / 2.0
	_ring(wheel, radius - 0.03, radius, _material("tire", Color(0.06, 0.06, 0.07), 0.9))
	_ring(wheel, radius - 0.07, radius - 0.025, _material("rim", Color(0.12, 0.12, 0.14), 0.4, 0.5))
	_tube(wheel, Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), 0.025, _materials["metal"])
	var spoke := _material("spoke", Color(0.85, 0.85, 0.88), 0.3, 0.8)
	for i in range(8):
		var angle := PI * i / 8.0
		var tip := Vector3(0, cos(angle), sin(angle)) * (radius - 0.06)
		var offset := Vector3(0.012 if i % 2 == 0 else -0.012, 0, 0)
		_tube(wheel, offset - tip, offset + tip, 0.0035, spoke, 4)
	return wheel


func _build_rider() -> void:
	var jersey := _material("jersey", JERSEY_COLOR, 0.75)
	var shorts := _material("shorts", Color(0.08, 0.08, 0.1), 0.8)
	var skin := _material("skin", SKIN_COLOR, 0.8)
	var white := _material("white", Color(0.95, 0.95, 0.95), 0.6)
	var black: StandardMaterial3D = _materials["black"]
	var rider := _node(_lean, "Rider")
	# Becken auf dem Sattel, Oberkörper mit Gelenk an der Hüfte.
	_capsule(rider, Vector3(0, HIP.y - 0.02, HIP.z + 0.01), 0.1, 0.26, shorts, Vector3(0, 0, PI / 2.0), Vector3(1.0, 1.0, 1.1))
	_torso = _node(rider, "Torso", Vector3(0, HIP.y, HIP.z))
	_capsule(_torso, Vector3(0, TORSO_LENGTH * 0.5, 0), 0.14, TORSO_LENGTH + 0.06, jersey, Vector3.ZERO, Vector3(1.3, 1.0, 0.8))
	_tube(_torso, Vector3(0, TORSO_LENGTH * 0.22, 0), Vector3(0, TORSO_LENGTH * 0.3, 0), 0.142, white, 12, Vector3(1.3, 1.0, 0.82))
	_tube(_torso, Vector3(0, -0.02, 0), Vector3(0, 0.07, 0), 0.142, shorts, 12, Vector3(1.28, 1.0, 0.8))
	for mirror in [-1.0, 1.0]:  # Schulterkugeln mit Ärmelansatz
		_sphere(_torso, Vector3((SHOULDER_HALF_WIDTH - 0.01) * mirror, TORSO_LENGTH - 0.05, 0), 0.06, jersey)
	_tube(_torso, Vector3(0, TORSO_LENGTH - 0.02, -0.01), Vector3(0, TORSO_LENGTH + 0.09, -0.02), 0.045, skin, 8)
	# Kopf mit Helm (Schale, Streifen, Lüftungsschlitze) und Brille; blickt nach vorn.
	_head = _node(_torso, "Head", Vector3(0, TORSO_LENGTH + 0.13, -0.03))
	_sphere(_head, Vector3.ZERO, 0.1, skin)
	var helmet := _material("helmet", Color(0.97, 0.97, 0.97), 0.35)
	var shell := _sphere(_head, Vector3(0, 0.025, 0.015), 0.125, helmet, true)
	shell.scale = Vector3(1.0, 1.0, 1.3)
	var stripe := _sphere(_head, Vector3(0, 0.027, 0.015), 0.129, _materials["frame"], true)
	stripe.scale = Vector3(0.22, 1.0, 1.31)
	for x in [-0.055, 0.055]:  # Lüftungsschlitze
		var vent := _sphere(_head, Vector3(x, 0.03, 0.03), 0.124, _material("vent", Color(0.15, 0.15, 0.17), 0.6), true)
		vent.scale = Vector3(0.1, 1.0, 1.2)
	_box(_head, Vector3(0, 0.01, -0.095), Vector3(0.19, 0.04, 0.03), black)
	# Beine: Oberschenkel (Hose), Unterschenkel (Haut, Socke), Schuh; Arme: Ärmel, Haut, Handschuh.
	for side in range(2):
		var thigh := _node(rider, "Thigh%d" % side)
		_capsule(thigh, Vector3(0, THIGH / 2.0, 0), 0.075, THIGH + 0.12, shorts)
		_thighs.append(thigh)
		var shin := _node(rider, "Shin%d" % side)
		_capsule(shin, Vector3(0, SHIN / 2.0, 0), 0.052, SHIN + 0.08, skin)
		_tube(shin, Vector3(0, SHIN - 0.12, 0), Vector3(0, SHIN - 0.01, 0), 0.054, white, 10)
		_shins.append(shin)
		var shoe := _node(rider, "Shoe%d" % side)
		_box(shoe, Vector3.ZERO, Vector3(0.09, 0.07, 0.27), white)
		_box(shoe, Vector3(0, -0.04, 0.0), Vector3(0.092, 0.015, 0.27), black)
		_shoes.append(shoe)
		var upper_arm := _node(rider, "UpperArm%d" % side)
		_capsule(upper_arm, Vector3(0, UPPER_ARM / 2.0, 0), 0.048, UPPER_ARM + 0.08, skin)
		_tube(upper_arm, Vector3(0, -0.02, 0), Vector3(0, 0.15, 0), 0.058, jersey, 10)
		_upper_arms.append(upper_arm)
		var forearm := _node(rider, "Forearm%d" % side)
		_capsule(forearm, Vector3(0, FOREARM / 2.0, 0), 0.04, FOREARM + 0.06, skin)
		_forearms.append(forearm)
		var hand := _node(rider, "Hand%d" % side)
		_sphere(hand, Vector3.ZERO, 0.045, black)
		_hands.append(hand)


func _node(parent: Node3D, node_name: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = at
	parent.add_child(node)
	return node


## Material je Schlüssel: beim ersten Aufruf angelegt, danach aus `_materials` wiederverwendet.
func _material(key: String, color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		material.metallic = metallic
		_materials[key] = material
	return _materials[key]


func _mesh(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


## Rohr (Zylinder) von `a` nach `b`.
func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, sides: int = 8,
		scale_xz: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = sides
	cylinder.rings = 1
	var instance := _mesh(parent, cylinder, material)
	var up := (b - a).normalized()
	var helper := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var back := helper.cross(up).normalized()
	instance.transform = Transform3D(Basis(up.cross(back), up, back) * Basis.from_scale(scale_xz), (a + b) / 2.0)
	return instance


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := _mesh(parent, box, material)
	instance.position = at
	return instance


func _sphere(parent: Node3D, at: Vector3, radius: float, material: Material, hemisphere: bool = false) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius if hemisphere else radius * 2.0
	sphere.is_hemisphere = hemisphere
	sphere.radial_segments = 12
	sphere.rings = 6
	var instance := _mesh(parent, sphere, material)
	instance.position = at
	return instance


func _capsule(parent: Node3D, at: Vector3, radius: float, height: float, material: Material,
		euler: Vector3 = Vector3.ZERO, scale_xyz: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	capsule.radial_segments = 10
	capsule.rings = 3
	var instance := _mesh(parent, capsule, material)
	instance.transform = Transform3D(Basis.from_euler(euler) * Basis.from_scale(scale_xyz), at)
	return instance


## Ring um die X-Achse (Reifen, Felge).
func _ring(parent: Node3D, inner: float, outer: float, material: Material) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 8
	var instance := _mesh(parent, torus, material)
	instance.rotation = Vector3(0, 0, PI / 2.0)
	return instance
