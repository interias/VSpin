## Fahrer-Vorschau (aus der Garderobe #36 herausgelöst, damit sie auch das Charakterblatt #68 zeigt): der Fahrer auf dem
## Rad dreht sich langsam und tritt, eigene 3D-Welt im SubViewport. Quadratisch (mittig im freien Platz); die Kamera
## hält das ganze Rad in jeder Drehung im Bild. Das Modell (`model`) bekommt sein Aussehen von außen (`RiderModel.wear`).
extends PanelContainer

## Drehung (rad/s), Kadenz und Tempo des Fahrers, Kamera und Blickpunkt (Modellkoordinaten).
const TURN_RAD_S := 0.45
const CADENCE_RPM := 70.0
const SPEED_MPS := 7.0
const CAMERA := Vector3(2.9, 1.5, -1.4)
const LOOK := Vector3(0.0, 0.8, 0.0)
const FOV_DEG := 42.0
const BACKGROUND := Color(0.2, 0.27, 0.34)

## Fahrermodell der Vorschau.
var model: RiderModel
var _turntable: Node3D


func _init() -> void:
	name = "Preview"
	custom_minimum_size = Vector2(220, 220)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.78)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var square := AspectRatioContainer.new()
	square.name = "Square"
	add_child(square)
	var container := SubViewportContainer.new()
	container.name = "View"
	container.stretch = true
	square.add_child(container)
	var viewport := SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.88, 0.95)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = FOV_DEG
	camera.transform = Transform3D(Basis.looking_at(LOOK - CAMERA), CAMERA)
	viewport.add_child(camera)
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.rotation.y = deg_to_rad(-30.0)
	viewport.add_child(_turntable)
	model = RiderModel.new()
	model.name = "Model"
	_turntable.add_child(model)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_turntable.rotation.y += TURN_RAD_S * delta
		model.update(CADENCE_RPM, SPEED_MPS, 0.0, 0.0, false, delta)
