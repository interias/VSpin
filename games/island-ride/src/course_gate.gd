## Tor über der Straße (#58): Starttor (grün) oder Zieltor (orange-weiß kariert) mit Text auf dem Banner, z. B. vor und
## nach einem Intervall im Training; wiederverwendbar für „Takt-Tore“ (#48). Low-Poly aus Quadern wie die
## Segment-Torbögen (#33, blaue Pfosten, weißes Banner) und der Start/Ziel-Bogen (rot), aber klar anders: farbiges
## Banner, Wimpel auf den Pfosten und helle Sockel. Gestellt wird es über eine Fahrtposition
## (`place`), in jeder Richtung (#34) quer zur Fahrt, Banner zum anfahrenden Fahrer. Hängt am Track (lokale
## Pfadkoordinaten). Nur Anzeige (ADR-0010).
class_name CourseGate
extends Node3D

const KIND_START := "start"
const KIND_FINISH := "finish"
const COLOR_START := Color(0.2, 0.68, 0.3)
const COLOR_FINISH := Color(0.95, 0.5, 0.12)
const COLOR_LIGHT := Color(0.97, 0.97, 0.94)
## Halbe lichte Weite (m), etwas weiter als die Segment-Torbögen (4 m).
const HALF_WIDTH_M := 4.6

## Art (KIND_*) und Text auf dem Banner.
var kind := ""
var text := ""
## Fahrtposition, an der das Tor steht (NAN = nicht gestellt).
var ride_m := NAN

var _label: Label3D
var _parts: Node3D


## Art `gate_kind` (KIND_*) und Text `banner`; baut nur bei einer anderen Art neu.
func configure(gate_kind: String, banner: String) -> void:
	if gate_kind != kind:
		kind = gate_kind
		_build()
	text = banner
	_label.text = banner


## An Fahrtposition `at_m` auf `track` stellen, quer zur Fahrtrichtung, Banner zum anfahrenden Fahrer.
func place(track: Track, at_m: float) -> void:
	ride_m = at_m
	var a := track.ride_position_at(at_m - 1.0)
	var b := track.ride_position_at(at_m + 1.0)
	position = track.ride_position_at(at_m)
	rotation = Vector3(0.0, atan2(-(b.x - a.x), -(b.z - a.z)), 0.0)


func _build() -> void:
	if _parts != null:
		_parts.free()
	_parts = Node3D.new()
	_parts.name = "Parts"
	add_child(_parts)
	var color := COLOR_START if kind == KIND_START else COLOR_FINISH
	for side in [-1.0, 1.0]:
		var post := "PfostenL" if side < 0.0 else "PfostenR"
		_box(post, Vector3(0.45, 6.0, 0.45), Vector3(side * HALF_WIDTH_M, 3.0, 0.0), color)
		_box(post + "Fuss", Vector3(0.9, 0.3, 0.9), Vector3(side * HALF_WIDTH_M, 0.15, 0.0), COLOR_LIGHT)
		_flag(post + "Wimpel", Vector3(side * HALF_WIDTH_M, 6.0, 0.0), side, color)
	if kind == KIND_START:
		_box("Banner", Vector3(2.0 * HALF_WIDTH_M + 0.5, 1.3, 0.3), Vector3(0.0, 5.35, 0.0), color)
	else:  # Zieltor: Banner kariert in zwei Reihen
		var cells := 10
		var cell := (2.0 * HALF_WIDTH_M + 0.5) / cells
		for row in range(2):
			for i in range(cells):
				var light := (i + row) % 2 == 0
				_box("Karo%d_%d" % [row, i], Vector3(cell, 0.65, 0.3),
						Vector3(-HALF_WIDTH_M - 0.25 + cell * (i + 0.5), 5.025 + row * 0.65, 0.0),
						COLOR_LIGHT if light else color)
	if _label == null:
		_label = Label3D.new()
		_label.name = "Text"
		_label.font_size = 80
		_label.pixel_size = 0.01
		_label.outline_size = 10
		_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.75)
		add_child(_label)
	_label.modulate = COLOR_LIGHT
	_label.position = Vector3(0.0, 6.55, 0.2) if kind == KIND_FINISH else Vector3(0.0, 5.35, 0.17)


func _box(node_name: String, box_size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = at
	_parts.add_child(instance)


## Dreieckiger Wimpel auf einem Pfosten, nach außen wehend.
func _flag(node_name: String, at: Vector3, side: float, color: Color) -> void:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 0.7, 0.08)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(color.lightened(0.25))
	instance.position = at + Vector3(side * 0.5, 0.15, 0.0)
	instance.rotation.z = -side * PI / 2.0
	_parts.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
