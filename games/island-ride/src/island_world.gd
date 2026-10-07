## Insel-Welt um den Rundkurs (ADR-0006, #14) – Gelände (IslandTerrain), Meer, Fahrbahn, Stationsmarker und Deko
## je Station. Hafen und Küstenstraße sind ausgestaltet (#15) mit Low-Poly-Modellen von Kenney (CC0, unter
## `assets/kenney/`, Nachweis in ASSETS.md); die übrigen Stationen haben Graybox-Deko aus Grundkörpern (Mauer am
## Aussichtspunkt, Pinien/Oliven, Häuser mit Kirche).
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
## Modelle (Kenney, CC0) – Nachweis in ASSETS.md.
const MODEL_DIR := "res://assets/kenney/"
## Hafen: Kaimauer an der Bucht (Welt-z, gerade in Ost-West-Richtung).
const QUAY_EDGE_Z := 1302.0
## Küstenstraße: Modelle (Dateinamen in `assets/kenney/nature/`).
const COAST_CLIFFS := ["rock_tallA", "rock_tallB", "rock_tallG"]
const COAST_ROCKS := ["rock_largeA", "rock_largeB", "rock_largeD"]
const COAST_BUSHES := ["plant_bushLarge", "plant_bushDetailed", "plant_bush"]
const COAST_PINES := ["tree_simple", "tree_plateau", "tree_detailed"]
## Knotennamen-Präfix der Felsen auf dem Hang zwischen Straße und Meer (Felsküste im Blick).
const SLOPE_ROCK_PREFIX := "Hang_"
## Nature-Kit-Materialfarben (Türkis/Orange) → mediterrane Töne, nach Materialname.
const NATURE_COLORS := {
	"leafsGreen": Color(0.22, 0.38, 0.18),
	"grass": Color(0.34, 0.42, 0.2),
	"woodBark": Color(0.45, 0.33, 0.24),
	"dirt": Color(0.72, 0.66, 0.56),
	"_defaultMat": Color(0.8, 0.76, 0.68),
}

## Wird von `build()` gesetzt.
var terrain: IslandTerrain
var track: Track

static var _terrain_mesh: ArrayMesh = null
static var _models := {}
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


## Hafen (#15): Kai von der Straße bis zur Kaimauer an der Bucht, Poller, zwei Molen mit Leuchtfeuern, Boote am Kai
## und in der Bucht, Ladung auf dem Kai, Häuserzeile mit Terrakotta-Dächern auf der Landseite, Palmen,
## Ruderboote am Strand; Start/Ziel-Bogen. Modelle: Kenney (CC0, siehe ASSETS.md).
func _build_harbour() -> void:
	var node := _props_node("hafen")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1501
	var stone := Color(0.6, 0.58, 0.54)
	# Kai: Segmente entlang der Straße (Oberkante auf Fahrbahnhöhe, über dem Gelände) bis zur geraden Kaimauer.
	var bollards: Array[Transform3D] = []
	var palms := {"tree_palmTall": [] as Array[Transform3D], "tree_palmBend": [] as Array[Transform3D]}
	var d := -60.0
	var i := 0
	while d <= 170.0:
		var p := track.position_at(d)
		var depth := QUAY_EDGE_Z - (p.z + 3.4)
		_box(node, "Kai%d" % i, Vector3(10.6, 7.0, depth), Vector3(p.x, p.y - 6.9, p.z + 3.4 + depth / 2.0), stone)
		bollards.append(Transform3D(Basis(), Vector3(p.x, p.y + 0.4, QUAY_EDGE_Z - 0.8)))
		if i % 2 == 0:
			var palm := Vector3(p.x + rng.randf_range(-2.0, 2.0), p.y + 0.1, p.z + 8.5)
			palms["tree_palmTall" if i % 4 == 0 else "tree_palmBend"].append(_scaled(palm, rng.randf_range(5.5, 7.0), rng.randf() * TAU))
		d += 10.0
		i += 1
	_multimesh(node, "Poller", _cylinder(0.25, 0.6), Color(0.25, 0.25, 0.27), bollards)
	_box(node, "MoleWest", Vector3(10.0, 6.2, 100.0), Vector3(200.0, -4.0, 1350.0), stone)
	_box(node, "MoleOst", Vector3(10.0, 6.2, 130.0), Vector3(410.0, -4.0, 1365.0), stone)
	_beacon(node, "LeuchtfeuerWest", Vector3(200.0, 2.2, 1396.0), Color(0.2, 0.6, 0.3))
	_beacon(node, "LeuchtfeuerOst", Vector3(410.0, 2.2, 1426.0), Color(0.85, 0.2, 0.15))
	# Boote: am Kai mit dem Bug zur Mauer (mediterran), dazu einige vor Anker in der Bucht.
	var moored := ["boat-sail-a", "boat-fishing-small", "boat-sail-b", "boat-tug-a", "boat-sail-a", "boat-row-small"]
	var x := 236.0
	i = 0
	while x < 400.0:
		if rng.randf() < 0.85:
			var model: String = moored[i % moored.size()]
			_place_model(node, "watercraft/%s.glb" % model, Vector3(x, -0.45, QUAY_EDGE_Z + 6.0),
					PI + rng.randf_range(-0.06, 0.06), 2.4)
		x += rng.randf_range(6.5, 8.0)
		i += 1
	for at in [Vector3(290.0, -0.45, 1385.0), Vector3(335.0, -0.45, 1435.0), Vector3(255.0, -0.45, 1440.0),
			Vector3(370.0, -0.45, 1395.0), Vector3(165.0, -0.45, 1390.0), Vector3(120.0, -0.45, 1430.0),
			Vector3(70.0, -0.45, 1455.0), Vector3(20.0, -0.45, 1470.0)]:
		if terrain.height_at(at.x, at.z) < -1.5:
			_place_model(node, "watercraft/%s.glb" % ["boat-sail-b", "boat-sail-a"][int(at.x) % 2], at, rng.randf() * TAU, 2.2)
	for at in [Vector3(230.0, -0.3, 1365.0), Vector3(385.0, -0.3, 1360.0), Vector3(315.0, -0.3, 1470.0)]:
		_place_model(node, "watercraft/buoy-flag.glb", at, 0.0, 1.6)
	# Ladung auf dem Kai
	for entry in [[395.0, "cargo-pile-a", 0.2], [372.0, "cargo-pile-b", 1.4], [214.0, "cargo-pile-a", 2.6]]:
		var p := track.position_at(track.curve.get_closest_offset(Vector3(entry[0], 3.0, 1265.0)))
		_place_model(node, "watercraft/%s.glb" % entry[1], Vector3(entry[0], p.y + 0.1, QUAY_EDGE_Z - 9.0), entry[2], 2.0)
	# Häuserzeile auf der Landseite (rechts in Fahrtrichtung), Front zur Straße
	var houses := ["building-type-a", "building-type-c", "building-type-g", "building-type-h", "building-type-k", "building-type-r"]
	d = 18.0
	i = 0
	while d < 340.0:
		var at := _beside_road(d, rng.randf_range(16.5, 19.0))
		_place_model(node, "city-suburban/%s.glb" % houses[(i * 5 + 2) % houses.size()], at - Vector3(0.0, 0.3, 0.0),
				_yaw_at(d) - PI / 2.0, rng.randf_range(8.5, 10.0))
		var palm := _beside_road(d + 8.0, 9.0)
		palms["tree_palmTall"].append(_scaled(palm, rng.randf_range(5.5, 7.5), rng.randf() * TAU))
		d += rng.randf_range(15.5, 18.0)
		i += 1
	# Strand westlich des Kais: Ruderboote und Palmen
	for at in [Vector3(132.0, 0.0, 1318.0), Vector3(118.0, 0.0, 1326.0), Vector3(150.0, 0.0, 1312.0)]:
		at.y = terrain.height_at(at.x, at.z) - 0.1
		_place_model(node, "watercraft/boat-row-small.glb", at, rng.randf() * TAU, 2.0)
	for k in range(6):
		var palm := _beside_road(200.0 + k * 35.0, -rng.randf_range(10.0, 24.0))
		palms["tree_palmBend"].append(_scaled(palm, rng.randf_range(5.5, 7.0), rng.randf() * TAU))
	for model in palms:
		_scatter(node, model, "nature/%s.glb" % model, palms[model])
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


## Küstenstraße (#15): seeseitig (links in Fahrtrichtung) eine niedrige Natursteinmauer am Straßenrand, Büsche und
## Felsen am Hang zum Meer und Klippen an der Wasserlinie; landseitig Pinien, Büsche und Felsen.
## Modelle: Kenney Nature Kit (CC0, siehe ASSETS.md).
func _build_coast() -> void:
	var node := _props_node("kueste")
	var range_m := _station_range("kueste")
	# Zufallsfolge der übrigen Stationen wie vor #15 halten: dieselben Ziehungen wie die frühere Graybox-Felsenschleife
	# aus `_rng`, ohne sie zu benutzen. Entfällt, sobald #16 die übrigen Stationen neu gestaltet.
	var skip := range_m.x + 40.0
	while skip < range_m.y - 40.0:
		_rng.randf_range(12.0, 45.0)
		_rng.randf_range(1.5, 4.0)
		_rng.randf()
		skip += _rng.randf_range(25.0, 50.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1502
	var wall: Array[Transform3D] = []
	var models := {}
	var slope_rocks := {}
	for model in COAST_CLIFFS + COAST_ROCKS + COAST_BUSHES + COAST_PINES:
		models[model] = [] as Array[Transform3D]
	for model in COAST_CLIFFS:
		slope_rocks[model] = [] as Array[Transform3D]
	var d := range_m.x + 15.0
	while d < range_m.y - 15.0:
		var yaw := _yaw_at(d)
		wall.append(Transform3D(Basis(Vector3.UP, yaw), track.position_at(d) + _side_offset(d, -3.8) + Vector3(0.0, 0.3, 0.0)))
		if int(d) % 12 < 4:
			var water := _water_distance(d, 250.0)
			# Seeseite: Klippen an der Wasserlinie, Felsen und Büsche am Hang
			if water > 0.0:
				if rng.randf() < 0.75:
					var cliff := _beside_road(d, -(water + rng.randf_range(-4.0, 2.0)))
					cliff.y = minf(cliff.y, 0.0) - 2.5
					# Höhe mit der Straße: unten am Wasser flache Felsen (Meer bleibt sichtbar), oben hohe Klippen
					var s := rng.randf_range(0.4, 0.8) * track.position_at(d).y + 2.5
					models[COAST_CLIFFS[rng.randi() % COAST_CLIFFS.size()]].append(
							Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.5, s, s * 1.5)), cliff))
				# Felsküste im Blick: Felsband auf dem Hang zwischen Mauer und Meer (die Wasserlinie verdeckt die
				# Hangkante), 4–10 m hoch, vom oberen Drittel bis kurz vor dem Wasser
				for k in range(4):
					var rock := _beside_road(d + rng.randf_range(-6.0, 6.0), -water * rng.randf_range(0.25, 0.85))
					if rock.y < 0.5 or terrain.road_distance_at(rock.x, rock.z) < 9.0:
						continue
					var h := rng.randf_range(4.0, 10.0)
					var w := h * rng.randf_range(1.2, 2.0)
					slope_rocks[COAST_CLIFFS[rng.randi() % COAST_CLIFFS.size()]].append(Transform3D(
							Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w)), rock - Vector3(0.0, 0.8, 0.0)))
				for k in range(2):
					var side := rng.randf_range(9.0, maxf(water - 6.0, 10.0))
					var at := _beside_road(d + rng.randf_range(-5.0, 5.0), -side)
					if at.y > 0.5 and terrain.road_distance_at(at.x, at.z) > 7.0:
						if rng.randf() < 0.35:
							models[COAST_ROCKS[rng.randi() % COAST_ROCKS.size()]].append(_scaled(at, rng.randf_range(3.0, 6.0), rng.randf() * TAU))
						else:
							models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 9.0), rng.randf() * TAU))
			# Landseite: Pinien, Büsche, vereinzelt Felsen
			for k in range(3):
				var at := _beside_road(d + rng.randf_range(-6.0, 6.0), rng.randf_range(10.0, 85.0))
				if at.y < 1.0 or terrain.road_distance_at(at.x, at.z) < 8.0:
					continue
				var roll := rng.randf()
				if roll < 0.45:
					models[COAST_PINES[rng.randi() % COAST_PINES.size()]].append(_scaled(at, rng.randf_range(7.0, 11.0), rng.randf() * TAU))
				elif roll < 0.9:
					models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 9.0), rng.randf() * TAU))
				else:
					models[COAST_ROCKS[rng.randi() % COAST_ROCKS.size()]].append(_scaled(at, rng.randf_range(2.5, 5.0), rng.randf() * TAU))
		d += 4.0
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(0.5, 0.6, 3.3)
	_multimesh(node, "Mauer", wall_mesh, Color(0.76, 0.68, 0.55), wall)
	for model in models:
		_scatter(node, model, "nature/%s.glb" % model, models[model], not (model in COAST_BUSHES))
	for model in slope_rocks:
		_scatter(node, SLOPE_ROCK_PREFIX + model, "nature/%s.glb" % model, slope_rocks[model])


## Abstand (m) von der Straßenmitte zur Wasserlinie links in Fahrtrichtung (Seeseite), -1 wenn nicht bis `limit`.
func _water_distance(distance_m: float, limit: float) -> float:
	var m := 8.0
	while m <= limit:
		if _beside_road(distance_m, -m).y < 0.0:
			return m
		m += 4.0
	return -1.0


## Modelle (Kenney, CC0) aus `assets/kenney/<Pfad>`; Instanzen derselben Datei teilen sich das importierte Mesh.
## `_place_model` setzt eine ganze Modellszene (mehrteilig, z. B. Boot mit Segel), `_scatter` viele Instanzen des
## Meshs als MultiMesh (Vegetation, Felsen – ein Draw-Call je Material).
func _place_model(parent: Node3D, path: String, at: Vector3, yaw: float, factor: float) -> Node3D:
	var instance: Node3D = load(MODEL_DIR + path).instantiate()
	instance.name = path.get_file().get_basename().to_pascal_case() + str(parent.get_child_count())
	instance.transform = _scaled(at, factor, yaw)
	parent.add_child(instance)
	return instance


func _scatter(parent: Node3D, node_name: String, path: String, transforms: Array[Transform3D], shadows: bool = true) -> MultiMeshInstance3D:
	var model := _model_mesh(MODEL_DIR + path)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = model[0]
	multimesh.instance_count = transforms.size()
	for k in range(transforms.size()):
		multimesh.set_instance_transform(k, transforms[k] * model[1])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## [Mesh, Lage im Modell] des ersten MeshInstance3D einer Modellszene (gecacht). Die Nature-Kit-Dateien setzen
## `metallicFactor` 1 (glTF-Standardwert) – ohne Spiegelungen wären sie fast schwarz, daher Metallic 0 – und
## bekommen die Farben aus NATURE_COLORS.
static func _model_mesh(path: String) -> Array:
	if not _models.has(path):
		var scene: Node = load(path).instantiate()
		var mesh_node: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var placement := Transform3D()
		var node: Node = mesh_node
		while node != scene:
			placement = (node as Node3D).transform * placement
			node = node.get_parent()
		var mesh: Mesh = mesh_node.mesh.duplicate()
		for s in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(s) as BaseMaterial3D
			if material != null and material.metallic > 0.0:
				material = material.duplicate()
				material.metallic = 0.0
				material.albedo_color = NATURE_COLORS.get(material.resource_name, material.albedo_color)
				mesh.surface_set_material(s, material)
		_models[path] = [mesh, placement]
		scene.free()
	return _models[path]


func _scaled(at: Vector3, factor: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * factor), at)


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return mesh


## Leuchtfeuer am Molenkopf: weißer Turm mit farbiger Laterne.
func _beacon(parent: Node3D, node_name: String, at: Vector3, color: Color) -> void:
	var tower := _add_mesh(node_name, _cylinder(1.1, 7.0), _flat_material(Color(0.95, 0.95, 0.92)), parent)
	tower.position = at + Vector3(0.0, 3.5, 0.0)
	var lantern := _add_mesh(node_name + "Laterne", _cylinder(0.8, 1.6), _flat_material(color), parent)
	lantern.position = at + Vector3(0.0, 7.8, 0.0)


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
