## Lichtsäule der Beute (#49, Diablo-Feedback): fällt in einer Arcade-Herausforderung Beute, steht kurz vor dem Fahrer
## eine Säule aus Licht in der Farbe der Seltenheit (Loot.color_of) auf der Straße, am Boden ein leuchtender Ring und
## darüber schwebend und drehend das Fundstück als Raute. Low-Poly aus Grundkörpern, unbeleuchtete, halbtransparente
## Materialien (wirkt auch nachts und im Compatibility-Renderer), keine Assets. Gestellt wird sie über eine
## Fahrtposition (`place`), in jeder Richtung (#34). Hängt am Track (lokale Pfadkoordinaten). Nur Anzeige (ADR-0010).
class_name LootBeam
extends Node3D

## Höhe und Radius der Säule (m); Radius des Bodenrings; Höhe des schwebenden Fundstücks; Drehung (rad/s).
const HEIGHT_M := 16.0
const RADIUS_M := 0.45
const RING_M := 1.1
const GEM_HEIGHT_M := 1.3
const SPIN_RAD_S := 1.6

## Seltenheit (Loot.RARITIES) und Fahrtposition (NAN = nicht gestellt).
var rarity := ""
var ride_m := NAN

var _glow: StandardMaterial3D
var _core: StandardMaterial3D
var _solid: StandardMaterial3D
var _gem: Node3D
var _time := 0.0


func _init() -> void:
	name = "LootBeam"
	_glow = _material(0.28)
	_core = _material(0.75)
	_solid = _material(1.0)
	_cylinder(RADIUS_M, HEIGHT_M, _glow)
	_cylinder(RADIUS_M * 0.3, HEIGHT_M * 0.85, _core)
	var ring := TorusMesh.new()
	ring.inner_radius = RING_M - 0.12
	ring.outer_radius = RING_M
	ring.rings = 24
	ring.ring_segments = 6
	_mesh(ring, _core).position = Vector3(0.0, 0.05, 0.0)
	_gem = Node3D.new()
	_gem.name = "Gem"
	_gem.position = Vector3(0.0, GEM_HEIGHT_M, 0.0)
	add_child(_gem)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.38
	var gem := _mesh(box, _solid, _gem)
	gem.rotation = Vector3(PI / 4.0, 0.0, PI / 4.0)  # auf der Spitze: Raute
	set_rarity(Loot.COMMON)


## Farbe der Seltenheit `value` (Loot.RARITIES).
func set_rarity(value: String) -> void:
	rarity = value
	var color := Loot.color_of(value)
	for material in [_glow, _core, _solid]:
		var tinted := color
		tinted.a = material.albedo_color.a
		material.albedo_color = tinted


## Farbe der Säule (Seltenheit).
func color() -> Color:
	var result := _solid.albedo_color
	result.a = 1.0
	return result


## An Fahrtposition `at_m` auf `track` stellen.
func place(track: Track, at_m: float) -> void:
	ride_m = at_m
	position = track.ride_position_at(at_m)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_gem.rotation.y += SPIN_RAD_S * delta
	_gem.position.y = GEM_HEIGHT_M + sin(_time * 2.4) * 0.12


func _material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _cylinder(radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.6
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_mesh(mesh, material).position = Vector3(0.0, height / 2.0, 0.0)


func _mesh(mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(instance)
	return instance
