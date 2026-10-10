## Zugbrücke des Durchbruchs (#47): zwei Steintürme am Rand der Straße, dazwischen die hochgezogene Klappe aus Holz, die
## die Straße versperrt. Je voller der Balken des Durchbruchs, desto weiter senkt sie sich (`open` 0 = zu, 1 = offen,
## Klappe liegt dann auf der Straße); die Ketten spannen sich von den Türmen zur Klappe. Geht der Durchbruch zu Ende,
## öffnet sie sich ganz – auch beim Scheitern, nur langsamer (weich: die Fahrt geht weiter, Belohnung gibt es nicht).
## Low-Poly aus Quadern wie die CourseGate-Tore, keine Assets. Gestellt wird sie über eine Fahrtposition (`place`), in
## jeder Richtung (#34) quer zur Fahrt; hängt am Track (lokale Pfadkoordinaten). Nur Anzeige (ADR-0010).
class_name Drawbridge
extends Node3D

## Halbe lichte Weite wie die Tore (m), Höhe der Türme und Länge der Klappe.
const HALF_WIDTH_M := CourseGate.HALF_WIDTH_M
const TOWER_HEIGHT_M := 7.0
const LEAF_LENGTH_M := 6.0
const LEAF_LIFT_M := 0.12
## Geschwindigkeit des Öffnens (Anteil/s) beim Folgen des Balkens, nach Erfolg und nach Scheitern.
const FOLLOW_SPEED := 3.0
const SUCCESS_SPEED := 1.5
const FAIL_SPEED := 0.5

const COLOR_STONE := Color(0.62, 0.6, 0.55)
const COLOR_WOOD := Color(0.5, 0.33, 0.17)
const COLOR_BEAM := Color(0.3, 0.19, 0.1)
const COLOR_CHAIN := Color(0.22, 0.22, 0.24)

## Fahrtposition (NAN = nicht gestellt), Öffnungsgrad 0..1 (angezeigt), Ziel und Tempo der Bewegung.
var ride_m := NAN
var open := 0.0
var target := 0.0
var speed := FOLLOW_SPEED

var _leaf: Node3D
var _chains: Array[MeshInstance3D] = []


func _init() -> void:
	name = "Drawbridge"
	for side in [-1.0, 1.0]:
		var tower := "TurmL" if side < 0.0 else "TurmR"
		var x: float = side * (HALF_WIDTH_M + 0.7)
		_box(self, tower, Vector3(1.4, TOWER_HEIGHT_M, 1.4), Vector3(x, TOWER_HEIGHT_M / 2.0, 0.0), COLOR_STONE)
		_box(self, tower + "Dach", Vector3(1.9, 0.5, 1.9), Vector3(x, TOWER_HEIGHT_M + 0.25, 0.0), COLOR_BEAM)
		for i in range(2):  # Zinnen
			_box(self, "%sZinne%d" % [tower, i], Vector3(0.45, 0.5, 0.45),
					Vector3(side * (HALF_WIDTH_M + 0.2 + i * 1.0), TOWER_HEIGHT_M + 0.75, 0.0), COLOR_STONE)
		var chain := MeshInstance3D.new()
		chain.name = "Kette" + tower
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.1, 0.1, 1.0)
		chain.mesh = mesh
		chain.material_override = _material(COLOR_CHAIN)
		add_child(chain)
		_chains.append(chain)
	_box(self, "Sturz", Vector3(2.0 * HALF_WIDTH_M + 3.0, 0.7, 1.4), Vector3(0.0, TOWER_HEIGHT_M - 0.35, 0.0), COLOR_STONE)
	_leaf = Node3D.new()
	_leaf.name = "Klappe"
	_leaf.position = Vector3(0.0, LEAF_LIFT_M, 0.0)
	add_child(_leaf)
	var width := 2.0 * HALF_WIDTH_M - 0.8
	_box(_leaf, "Bohlen", Vector3(width, 0.3, LEAF_LENGTH_M), Vector3(0.0, 0.0, -LEAF_LENGTH_M / 2.0), COLOR_WOOD)
	for i in range(4):  # Querbalken
		_box(_leaf, "Balken%d" % i, Vector3(width + 0.2, 0.18, 0.3),
				Vector3(0.0, 0.2, -0.6 - i * (LEAF_LENGTH_M - 1.2) / 3.0), COLOR_BEAM)
	_apply()


## An Fahrtposition `at_m` auf `track` stellen, quer zur Fahrtrichtung (die Klappe senkt sich in Fahrtrichtung).
func place(track: Track, at_m: float) -> void:
	ride_m = at_m
	var a := track.ride_position_at(at_m - 1.0)
	var b := track.ride_position_at(at_m + 1.0)
	position = track.ride_position_at(at_m)
	rotation = Vector3(0.0, atan2(-(b.x - a.x), -(b.z - a.z)), 0.0)


## Der Öffnungsgrad folgt dem Fortschritt des Durchbruchs.
func follow(progress: float) -> void:
	target = clampf(progress, 0.0, 1.0)
	speed = FOLLOW_SPEED


## Durchbruch zu Ende: ganz öffnen – nach Erfolg zügig, nach Scheitern langsam.
func release(succeeded: bool) -> void:
	target = 1.0
	speed = SUCCESS_SPEED if succeeded else FAIL_SPEED


## Wieder zu (neuer Durchbruch).
func reset() -> void:
	open = 0.0
	target = 0.0
	speed = FOLLOW_SPEED
	_apply()


func _process(delta: float) -> void:
	if not is_equal_approx(open, target):
		open = move_toward(open, target, speed * delta)
		_apply()


## Winkel der Klappe aus dem Öffnungsgrad: 90° (steht) bis 0° (liegt).
static func leaf_angle(open_fraction: float) -> float:
	return (1.0 - clampf(open_fraction, 0.0, 1.0)) * PI / 2.0


## Spitze der Klappe (lokal) bei Öffnungsgrad `open_fraction`.
static func leaf_tip(open_fraction: float) -> Vector3:
	var angle := leaf_angle(open_fraction)
	return Vector3(0.0, LEAF_LIFT_M + LEAF_LENGTH_M * sin(angle), -LEAF_LENGTH_M * cos(angle))


func _apply() -> void:
	_leaf.rotation = Vector3(leaf_angle(open), 0.0, 0.0)
	var tip := leaf_tip(open)
	for i in range(_chains.size()):
		var x := (HALF_WIDTH_M - 0.3) * (-1.0 if i == 0 else 1.0)
		var from := Vector3(x, TOWER_HEIGHT_M - 0.8, 0.0)
		var to := Vector3(x, tip.y, tip.z)
		var along := to - from
		var direction := along.normalized()
		var chain := _chains[i]
		chain.position = (from + to) / 2.0
		chain.basis = Basis.looking_at(direction, Vector3.RIGHT if absf(direction.y) > 0.99 else Vector3.UP) \
				.scaled(Vector3(1.0, 1.0, maxf(along.length(), 0.01)))


func _box(parent: Node3D, node_name: String, box_size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = at
	parent.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
