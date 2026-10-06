## Insel-Welt um den Rundkurs (ADR-0006, #14) – Grundform aus Godot-Bordmitteln: Gelände (IslandTerrain),
## Meer, Fahrbahn, Stationsmarker und einfache Graybox-Deko je Station (Kai und Boote, Felsen, Mauer am
## Aussichtspunkt, Pinien/Oliven, Häuser mit Kirche). Keine fremden Assets (siehe ASSETS.md).
##
## Aufbau (Kinder dieses Knotens):
##   Terrain   MeshInstance3D des Höhenfelds
##   Sea       Meeresfläche auf y = 0
##   Road      Fahrbahn entlang des Pfads
##   Stations  je Station ein Node3D (Name = id) am Abschnittsbeginn mit Label3D; Metadaten `station_name`,
##             `distance_m`; dazu `aussichtspunkt` (Landmarke)
##   Props     je Station ein Node3D (Name = id) mit der Deko
class_name IslandWorld
extends Node3D

const SEA_SIZE_M := 9000.0

## Wird von `build()` gesetzt.
var terrain: IslandTerrain
var track: Track

static var _terrain_mesh: ArrayMesh = null
var _rng := RandomNumberGenerator.new()


## Baut die Welt für `course_track` (Pfad mit Insel-Kurve). Die Pfad-Koordinaten sind Weltkoordinaten
## (der Pfad liegt im Ursprung).
func build(course_track: Track) -> void:
	track = course_track
	terrain = IslandTerrain.for_course()
	_rng.seed = 2026
	if _terrain_mesh == null:
		_terrain_mesh = terrain.build_mesh()
	_add_mesh("Terrain", _terrain_mesh, _vertex_color_material())
	var sea := PlaneMesh.new()
	sea.size = Vector2(SEA_SIZE_M, SEA_SIZE_M)
	var sea_material := StandardMaterial3D.new()
	sea_material.albedo_color = Color(0.1, 0.42, 0.62, 0.88)
	sea_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sea_material.roughness = 0.15
	sea_material.metallic = 0.2
	_add_mesh("Sea", sea, sea_material)
	_add_mesh("Road", track.road_mesh(), _vertex_color_material())
	_build_stations()
	_build_props()


func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _add_mesh(node_name: String, mesh: Mesh, material: Material, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


## Stationsmarker: Node3D am Abschnittsbeginn mit großem, immer zur Kamera gedrehtem Namensschild.
func _build_stations() -> void:
	var stations := Node3D.new()
	stations.name = "Stations"
	add_child(stations)
	var markers := []
	for station in track.stations:
		markers.append({"id": station["id"], "name": station["name"], "distance_m": station["start_m"]})
	markers.append_array(IslandCourse.landmarks())
	for entry in markers:
		var marker := Node3D.new()
		marker.name = entry["id"]
		marker.set_meta("station_name", entry["name"])
		marker.set_meta("distance_m", entry["distance_m"])
		marker.position = track.position_at(entry["distance_m"])
		var label := Label3D.new()
		label.name = "Label"
		label.text = entry["name"]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 160
		label.pixel_size = 0.02
		label.outline_size = 24
		label.position = Vector3(0.0, 9.0, 0.0)
		marker.add_child(label)
		var post := CylinderMesh.new()
		post.top_radius = 0.12
		post.bottom_radius = 0.12
		post.height = 7.0
		var post_instance := _add_mesh("Post", post, _flat_material(Color(0.9, 0.9, 0.85)), marker)
		post_instance.position = _side_offset(entry["distance_m"], 4.2) + Vector3(0.0, 3.5, 0.0)
		stations.add_child(marker)


## Seitlicher Versatz (rechts in Fahrtrichtung, negativ = links) an einer Streckenposition, ohne Höhe.
func _side_offset(distance_m: float, meters: float) -> Vector3:
	var a := track.position_at(distance_m - 1.0)
	var b := track.position_at(distance_m + 1.0)
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	return Vector3(-dir.z, 0.0, dir.x) * meters


## Weltpunkt neben der Straße auf Geländehöhe.
func _beside_road(distance_m: float, meters: float) -> Vector3:
	var p := track.position_at(distance_m) + _side_offset(distance_m, meters)
	p.y = terrain.height_at(p.x, p.z)
	return p


func _station_range(id: String) -> Vector2:
	var stations := track.stations
	for i in range(stations.size()):
		if stations[i]["id"] == id:
			var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else track.length_m()
			return Vector2(stations[i]["start_m"], end)
	return Vector2.ZERO


func _props_node(id: String) -> Node3D:
	var props := get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		add_child(props)
	var node := Node3D.new()
	node.name = id
	props.add_child(node)
	return node


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color, yaw: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _add_mesh(node_name, mesh, _flat_material(color), parent)
	instance.position = at + Vector3(0.0, size.y / 2.0, 0.0)
	instance.rotation.y = yaw
	return instance


func _yaw_at(distance_m: float) -> float:
	var a := track.position_at(distance_m - 1.0)
	var b := track.position_at(distance_m + 1.0)
	return atan2(-(b.x - a.x), -(b.z - a.z))


func _build_props() -> void:
	_build_harbour()
	_build_coast()
	_build_serpentines()
	_build_grove()
	_build_village()
	_build_descent()


## Hafen: Kai an der Bucht, zwei Molen ins Wasser, Boote, Start/Ziel-Bogen.
func _build_harbour() -> void:
	var node := _props_node("hafen")
	var stone := Color(0.78, 0.74, 0.66)
	_box(node, "Kai", Vector3(260.0, 2.6, 16.0), Vector3(270.0, -0.5, 1292.0), stone)
	_box(node, "MoleWest", Vector3(10.0, 2.4, 100.0), Vector3(200.0, -0.5, 1350.0), stone)
	_box(node, "MoleOst", Vector3(10.0, 2.4, 130.0), Vector3(410.0, -0.5, 1365.0), stone)
	var boat_colors := [Color(0.95, 0.95, 0.95), Color(0.2, 0.45, 0.75), Color(0.85, 0.3, 0.2)]
	for i in range(6):
		var at := Vector3(240.0 + i * 25.0, -0.4, 1325.0 + (i % 2) * 25.0)
		_box(node, "Boot%d" % i, Vector3(3.0, 1.4, 9.0), at, boat_colors[i % boat_colors.size()], 0.15 * (i - 3))
	# Start/Ziel-Bogen über der Straße
	var arch := Node3D.new()
	arch.name = "StartZiel"
	arch.position = track.position_at(0.0)
	arch.rotation.y = _yaw_at(0.0)
	node.add_child(arch)
	var red := Color(0.85, 0.15, 0.15)
	_box(arch, "PfostenL", Vector3(0.5, 5.5, 0.5), Vector3(-4.0, 0.0, 0.0), red)
	_box(arch, "PfostenR", Vector3(0.5, 5.5, 0.5), Vector3(4.0, 0.0, 0.0), red)
	_box(arch, "Banner", Vector3(8.5, 1.2, 0.3), Vector3(0.0, 5.0, 0.0), Color(0.95, 0.95, 0.95))


## Küstenstraße: Felsbrocken auf der Seeseite (links in Fahrtrichtung nach Norden = Westen).
func _build_coast() -> void:
	var node := _props_node("kueste")
	var range_m := _station_range("kueste")
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 1.4
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 4
	var transforms: Array[Transform3D] = []
	var d := range_m.x + 40.0
	while d < range_m.y - 40.0:
		var side := -_rng.randf_range(12.0, 45.0)
		var p := _beside_road(d, side)
		var s := _rng.randf_range(1.5, 4.0)
		transforms.append(Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)).rotated(Vector3.UP, _rng.randf() * TAU), p))
		d += _rng.randf_range(25.0, 50.0)
	_multimesh(node, "Felsen", rock_mesh, Color(0.6, 0.55, 0.5), transforms)


## Serpentinen: Begrenzungssteine an den Kehren; Aussichtspunkt mit Plattform, Mauer und Bank.
func _build_serpentines() -> void:
	var node := _props_node("serpentinen")
	var range_m := _station_range("serpentinen")
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.5, 0.6, 0.5)
	var transforms: Array[Transform3D] = []
	var d := range_m.x
	while d < range_m.y:
		var p := track.position_at(d) + _side_offset(d, 3.6)
		transforms.append(Transform3D(Basis(), p + Vector3(0.0, 0.3, 0.0)))
		d += 6.0
	_multimesh(node, "Randsteine", stone_mesh, Color(0.92, 0.92, 0.9), transforms)
	var view: Dictionary = IslandCourse.landmarks()[0]
	var platform_at := track.position_at(view["distance_m"]) + _side_offset(view["distance_m"], -9.0)
	var stone := Color(0.76, 0.7, 0.6)
	_box(node, "Plattform", Vector3(10.0, 0.4, 10.0), platform_at + Vector3(0.0, -0.3, 0.0), stone)
	_box(node, "Mauer", Vector3(10.0, 1.0, 0.6), platform_at + Vector3(0.0, 0.0, -5.0), stone)
	_box(node, "Bank", Vector3(2.0, 0.5, 0.6), platform_at + Vector3(0.0, 0.0, -2.5), Color(0.5, 0.35, 0.2))


## Pinien-/Olivenhain: Bäume auf beiden Seiten der Straße (Pinien: Kegel, Oliven: runde Kronen).
func _build_grove() -> void:
	var node := _props_node("hain")
	var range_m := _station_range("hain")
	var trunks: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var olives: Array[Transform3D] = []
	var d := range_m.x
	while d < range_m.y:
		for side_sign in [-1.0, 1.0]:
			var p := _beside_road(d + _rng.randf_range(-6.0, 6.0), side_sign * _rng.randf_range(14.0, 70.0))
			if terrain.road_distance_at(p.x, p.z) < 10.0 or p.y < 2.0:
				continue
			var s := _rng.randf_range(0.8, 1.3)
			trunks.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0.0, 1.5 * s, 0.0)))
			if _rng.randf() < 0.5:
				pines.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0.0, 6.0 * s, 0.0)))
			else:
				olives.append(Transform3D(Basis().scaled(Vector3(s * 1.2, s * 0.8, s * 1.2)), p + Vector3(0.0, 3.4 * s, 0.0)))
		d += 9.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.3
	trunk.height = 3.0
	trunk.radial_segments = 6
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.4
	pine.height = 6.0
	pine.radial_segments = 8
	var olive := SphereMesh.new()
	olive.radius = 2.2
	olive.height = 3.6
	olive.radial_segments = 8
	olive.rings = 4
	_multimesh(node, "Staemme", trunk, Color(0.4, 0.28, 0.18), trunks)
	_multimesh(node, "Pinien", pine, Color(0.2, 0.38, 0.2), pines)
	_multimesh(node, "Oliven", olive, Color(0.47, 0.55, 0.38), olives)


## Bergdorf: weiß/ockerfarbene Häuser mit Terrakotta-Dächern beidseits der Straße und eine Kirche.
func _build_village() -> void:
	var node := _props_node("bergdorf")
	var range_m := _station_range("bergdorf")
	var walls := [Color(0.95, 0.92, 0.85), Color(0.88, 0.78, 0.6), Color(0.93, 0.86, 0.72)]
	var roof := Color(0.72, 0.36, 0.22)
	var i := 0
	var d := range_m.x + 20.0
	while d < range_m.y - 10.0:
		for side_sign in [-1.0, 1.0]:
			var p := _beside_road(d, side_sign * _rng.randf_range(13.0, 18.0))
			var yaw := _yaw_at(d)
			var size := Vector3(_rng.randf_range(7.0, 11.0), _rng.randf_range(5.0, 8.0), _rng.randf_range(7.0, 10.0))
			_box(node, "Haus%d" % i, size, p, walls[i % walls.size()], yaw)
			var roof_mesh := PrismMesh.new()
			roof_mesh.size = Vector3(size.x + 0.6, 2.2, size.z + 0.6)
			var roof_instance := _add_mesh("Dach%d" % i, roof_mesh, _flat_material(roof), node)
			roof_instance.position = p + Vector3(0.0, size.y + 1.1, 0.0)
			roof_instance.rotation.y = yaw
			i += 1
		d += 26.0
	var church_at := _beside_road((range_m.x + range_m.y) / 2.0, 26.0)
	_box(node, "Kirche", Vector3(12.0, 10.0, 20.0), church_at, Color(0.85, 0.78, 0.62))
	_box(node, "Turm", Vector3(5.0, 22.0, 5.0), church_at + Vector3(0.0, 0.0, 11.0), Color(0.82, 0.74, 0.58))


## Abfahrt: vereinzelte Pinien am Hang.
func _build_descent() -> void:
	var node := _props_node("abfahrt")
	var range_m := _station_range("abfahrt")
	var pines: Array[Transform3D] = []
	var d := range_m.x
	while d < range_m.y - 200.0:
		var p := _beside_road(d, (1.0 if _rng.randf() < 0.5 else -1.0) * _rng.randf_range(15.0, 60.0))
		if terrain.road_distance_at(p.x, p.z) >= 10.0 and p.y > 2.0:
			pines.append(Transform3D(Basis(), p + Vector3(0.0, 4.0, 0.0)))
		d += _rng.randf_range(20.0, 45.0)
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.0
	pine.height = 8.0
	pine.radial_segments = 8
	_multimesh(node, "Pinien", pine, Color(0.2, 0.38, 0.2), pines)


func _multimesh(parent: Node3D, node_name: String, mesh: Mesh, color: Color, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for k in range(transforms.size()):
		multimesh.set_instance_transform(k, transforms[k])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _flat_material(color)
	parent.add_child(instance)
	return instance
