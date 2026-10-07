## Lichter bei Nacht und Dämmerung (G6), von SkyController geschaltet (`set_on`):
##   Laternen     Leuchtpunkte (Lichthof, ein MultiMesh) an allen Laternen der Welt (`Props/*/Laternen`) und an den
##                Leuchtfeuern der Molen; echte Lichter nur nahe der Kamera: ein kleiner Vorrat OmniLight3D
##                (`POOL`, kurze Reichweite, ohne Schatten) wandert zu den nächsten Laternen (`follow`)
##   Fahrrad      Front- und Rücklicht am Rad (`Track/Rider/Model/Lean/Bike/Frontlicht|Ruecklicht`): Lampengehäuse
##                leuchten (emissiv), vorn ein Spot auf die Straße, hinten ein schwaches rotes Licht
## So bleiben nachts nur wenige echte Lichter aktiv (Performance, auch im Web-Export).
class_name NightLights
extends Node3D

const GLOW_SHADER := preload("res://src/shaders/glow.gdshader")
## Kopf der Kenney-Laterne (Modellkoordinaten, Höhe 1,556) – dort sitzt der Leuchtpunkt.
const LANTERN_HEAD := Vector3(0.0, 1.3, 0.0)
const LANTERN_COLOR := Color(1.0, 0.72, 0.38)
## Echte Lichter an den nächsten Laternen: Anzahl, Reichweite (m), höchstens so weit von der Kamera (m).
const POOL := 6
const POOL_RANGE_M := 16.0
const POOL_MAX_DISTANCE_M := 140.0

## Lichtpunkte der Welt: je {position, color}.
var points: Array[Dictionary] = []
var glows: MultiMeshInstance3D
var pool: Array[OmniLight3D] = []
## Fahrradlicht: Spot vorn, Licht hinten, emissive Materialien der Gehäuse.
var front_light: SpotLight3D
var rear_light: OmniLight3D
var lamp_materials: Array[StandardMaterial3D] = []
var on := false


## Sammelt Laternen und Leuchtfeuer aus `world` (darf null sein, Graybox) und baut die Fahrradlampen an `bike`.
func setup(world: Node3D, bike: Node3D) -> void:
	name = "NightLights"
	if world != null:
		_collect(world)
	_build_glows()
	for k in range(POOL):
		var light := OmniLight3D.new()
		light.name = "Laterne%d" % (k + 1)
		light.light_color = LANTERN_COLOR
		light.light_energy = 2.2
		light.omni_range = POOL_RANGE_M
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		pool.append(light)
	if bike != null:
		_build_bike_lights(bike)
	set_on(false)


## Lichter an/aus.
func set_on(value: bool) -> void:
	on = value
	glows.visible = on and points.size() > 0
	if not on:
		for light in pool:
			light.visible = false
	if front_light != null:
		front_light.visible = on
		rear_light.visible = on
	for material in lamp_materials:
		material.emission_enabled = on


## Echte Lichter an die `POOL` Laternen, die `camera_at` am nächsten sind (nur wenn an).
func follow(camera_at: Vector3) -> void:
	if not on:
		return
	var near := []
	for point in points:
		var d: float = camera_at.distance_squared_to(point["position"])
		if d < POOL_MAX_DISTANCE_M * POOL_MAX_DISTANCE_M:
			near.append([d, point])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in range(pool.size()):
		pool[k].visible = k < near.size()
		if k < near.size():
			pool[k].position = near[k][1]["position"] - Vector3(0.0, 0.3, 0.0)
			pool[k].light_color = near[k][1]["color"]


func _collect(world: Node3D) -> void:
	var props := world.get_node_or_null("Props")
	if props != null:
		for station in props.get_children():
			var lanterns := station.get_node_or_null("Laternen") as MultiMeshInstance3D
			if lanterns != null:
				var multimesh := lanterns.multimesh
				for k in range(multimesh.instance_count):
					var at: Vector3 = lanterns.global_transform * (multimesh.get_instance_transform(k) * LANTERN_HEAD)
					points.append({"position": at, "color": LANTERN_COLOR})
			for node in station.get_children():
				if node.name.ends_with("Laterne") and node is MeshInstance3D:
					# Leuchtfeuer an der Mole: Laterne in ihrer Farbe
					var color: Color = (node.material_override as BaseMaterial3D).albedo_color
					points.append({"position": (node as Node3D).global_position, "color": color.lightened(0.3)})


func _build_glows() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.2, 2.2)
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = points.size()
	for k in range(points.size()):
		multimesh.set_instance_transform(k, Transform3D(Basis(), points[k]["position"]))
		multimesh.set_instance_color(k, points[k]["color"])
	glows = MultiMeshInstance3D.new()
	glows.name = "Leuchtpunkte"
	glows.multimesh = multimesh
	glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glows.top_level = true
	add_child(glows)


## Lampen am Rad (Modellkoordinaten von RiderModel: Fahrtrichtung −z): vorn am Lenker, hinten an der Sattelstütze.
func _build_bike_lights(bike: Node3D) -> void:
	var front := _lamp(bike, "Frontlicht", RiderModel.BAR + Vector3(0.0, -0.03, -0.07), Vector3(0.06, 0.04, 0.05), Color(1.0, 0.97, 0.9))
	front_light = SpotLight3D.new()
	front_light.name = "Licht"
	front_light.light_color = Color(1.0, 0.96, 0.88)
	front_light.light_energy = 6.0
	front_light.spot_range = 32.0
	front_light.spot_angle = 26.0
	front_light.spot_attenuation = 0.7
	front_light.shadow_enabled = false
	front_light.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
	front.add_child(front_light)
	var rear := _lamp(bike, "Ruecklicht", RiderModel.SEAT_CLUSTER + Vector3(0.0, -0.06, 0.06), Vector3(0.04, 0.05, 0.03), Color(1.0, 0.08, 0.05))
	rear_light = OmniLight3D.new()
	rear_light.name = "Licht"
	rear_light.light_color = Color(1.0, 0.1, 0.05)
	rear_light.light_energy = 0.3
	rear_light.omni_range = 1.6
	rear_light.shadow_enabled = false
	rear_light.position = Vector3(0.0, 0.0, 0.08)
	rear.add_child(rear_light)


func _lamp(parent: Node3D, node_name: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.6)
	material.emission = color
	material.emission_energy_multiplier = 4.0
	lamp_materials.append(material)
	var lamp := MeshInstance3D.new()
	lamp.name = node_name
	lamp.mesh = box
	lamp.material_override = material
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.position = at
	parent.add_child(lamp)
	return lamp
