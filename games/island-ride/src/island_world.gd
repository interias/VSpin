## Insel-Welt um den Rundkurs (ADR-0006, #14) – Gelände (IslandTerrain), Meer, Fahrbahn, Stationsmarker und Deko
## je Station. Alle Stationen sind mit Low-Poly-Modellen von Kenney ausgestaltet (CC0, unter `assets/kenney/`,
## Nachweis in ASSETS.md): Hafen und Küstenstraße (#15), Serpentinen mit Aussichtspunkt, Hain, Bergdorf und
## Abfahrt (#16). Jede Station zieht aus einem eigenen Zufallsgenerator (Seeds 1501–1506).
##
## Aufbau (Kinder dieses Knotens):
##   Terrain   MeshInstance3D des Höhenfelds
##   Sea       Meeresfläche auf y = 0
##   Road      Fahrbahn entlang des Pfads
##   Stations  je Station ein Node3D (Name = id) am Abschnittsbeginn mit Label3D; Metadaten `station_name`,
##             `distance_m`; dazu `aussichtspunkt` (Landmarke)
##   Props     je Station ein Node3D (Name = id) mit der Deko
##   Segments  je Segment ein Torbogen am Start (Name = id, #33), im Uhrzeigersinn; SegmentsCcw dasselbe gegen den
##             Uhrzeigersinn (#34). Sichtbar sind nur die Bögen der gewählten Richtung (`set_direction`).
##   Landmarks Sehenswürdigkeiten (Leuchtturm, Talaia, Ermita, …), Details Kleindetails – siehe IslandLandmarks (G2);
##             mit dem Aussichtspunkt die Orte der Panorama-Momente (`panorama_spots`, #43)
##   Vegetation Gras, Unterholz und Sträucher je Station; Gelände und Fahrbahn mit Detailtextur – siehe
##             IslandVegetation (#38)
##   Fauna     Weide- und Dorftiere (Herden, Ziegen auf der Straße, Esel, Katzen) – siehe IslandFauna (#40)
##   Motion    bewegte Szenen und Effekte (Windmühlen, Leuchtturm, Boote, Vögel, Wolken) – siehe WorldMotion (G3);
##             Meer und Vegetation bekommen dort ihre Shader (Wellen/Brandung, Wind)
## Jahreszeit (#39): `set_season(phase)` färbt Vegetation, Boden und Kenney-Vegetation um (`tint_nature`) – ohne Neubau.
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
## Serpentinen: graue Kalkfelsen (Hanganschnitt, Nadeln in den Kehren) und flache Kalksteine (auch Hain/Abfahrt).
const SERPENTINE_ROCKS := ["stone_tallA", "stone_tallB", "stone_tallC"]
const LIMESTONE := ["stone_largeA", "stone_largeB", "stone_largeC"]
## Knotennamen-Präfix der Kalksteinnadeln in den Kehren.
const SPIRE_PREFIX := "Nadel_"
## Hain und Abfahrt: Olivenbäume (silbriges Laub, OLIVE_COLORS), Pinien, Bodenpflanzen, Zypressen.
const OLIVE_TREES := ["tree_fat", "tree_oak"]
const GROVE_PINES := ["tree_plateau", "tree_detailed", "tree_simple"]
const GROUND_PLANTS := ["grass_large", "plant_flatShort", "flower_yellowA"]
const CYPRESS := "tree_tall"
## Bergdorf: Kantenlänge eines Fantasy-Town-Moduls (Wand 1 × 1) in m für Häuser und Kirche.
const HOUSE_MODULE_M := 3.2
const CHURCH_MODULE_M := 4.2
## Panorama am Aussichtspunkt (#43): Blickziel so weit links der Straße, über die Plattform hinaus aufs Meer (m).
const VIEWPOINT_OUTLOOK_M := 80.0
## Nature-Kit-Materialfarben (Türkis/Orange) → mediterrane Töne, nach Materialname.
const NATURE_COLORS := {
	"leafsGreen": Color(0.22, 0.38, 0.18),
	"grass": Color(0.34, 0.42, 0.2),
	"woodBark": Color(0.45, 0.33, 0.24),
	"woodBarkDark": Color(0.36, 0.27, 0.2),
	"wood": Color(0.62, 0.42, 0.28),
	"dirt": Color(0.72, 0.66, 0.56),
	"stone": Color(0.74, 0.72, 0.68),
	"_defaultMat": Color(0.8, 0.76, 0.68),
}
const OLIVE_COLORS := {
	"leafsGreen": Color(0.5, 0.56, 0.42),
	"woodBark": Color(0.33, 0.3, 0.26),
}
const CYPRESS_COLORS := {
	"leafsGreen": Color(0.2, 0.35, 0.19),
	"woodBark": Color(0.36, 0.27, 0.2),
}

## Wird von `build()` gesetzt.
var terrain: IslandTerrain
var track: Track
var landmarks: IslandLandmarks
## Gras, Unterholz und Sträucher entlang der Strecke (#38), Kind `Vegetation`.
var vegetation: IslandVegetation
## Weide- und Dorftiere (#40), Kind `Fauna`.
var fauna: IslandFauna
## Bewegte Szenen und Effekte (G3), Kind `Motion`.
var motion: WorldMotion
## Compatibility-Renderer (Web)? Dann wird die Vegetation abgespeckt (#38); vor `build()` injizierbar (Tests).
var compatibility := SkyController.is_compatibility_renderer()

static var _terrain_mesh: ArrayMesh = null
static var _models := {}
## Jahreszeit (#39): Faktor je Materialname der Kenney-Modelle (`tint_nature`) und die umgefärbten Materialien
## [Material, Materialname, Farbe vom Laden].
static var nature_tint := {}
static var _nature_materials := []


## Baut die Welt für `course_track` (Pfad mit Insel-Kurve). Die Pfad-Koordinaten sind Weltkoordinaten
## (der Pfad liegt im Ursprung).
func build(course_track: Track) -> void:
	track = course_track
	terrain = IslandTerrain.for_course()
	if _terrain_mesh == null:
		_terrain_mesh = terrain.build_mesh()
	var ground := _add_mesh("Terrain", _terrain_mesh, _vertex_color_material())
	var sea := PlaneMesh.new()
	sea.size = Vector2(SEA_SIZE_M, SEA_SIZE_M)
	_add_mesh("Sea", sea, WorldMotion.sea_material(terrain))
	var road := _add_mesh("Road", track.road_mesh(), _vertex_color_material())
	IslandVegetation.texture_ground(ground.material_override, road.material_override)
	_build_stations()
	_build_props()
	_build_segment_gates()
	landmarks = IslandLandmarks.new(self)
	landmarks.build()
	vegetation = IslandVegetation.new(self)
	vegetation.build()
	fauna = IslandFauna.new()
	add_child(fauna)
	fauna.setup(self)
	motion = WorldMotion.new()
	add_child(motion)
	motion.setup(self)


func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
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


## Sehenswürdigkeiten für die Panorama-Momente (#43): [{id, name, path_m (Pfadposition), at (Weltpunkt)}] – der
## Aussichtspunkt (Blick über die Plattform hinaus aufs Meer) und jede Landmarke unter `Landmarks` (Gruppen wie die
## Windmühlen über ihr mittleres Glied). Keine neuen Orte.
func panorama_spots() -> Array:
	var spots := []
	for landmark in IslandCourse.landmarks():
		var d: float = landmark["distance_m"]
		spots.append({"id": landmark["id"], "name": landmark["name"], "path_m": d,
				"at": track.to_global(track.position_at(d) + _side_offset(d, -VIEWPOINT_OUTLOOK_M))})
	for node in get_node("Landmarks").get_children():
		var part: Node3D = node if node.has_meta("distance_m") else node.get_child(node.get_child_count() / 2)
		spots.append({"id": String(node.name), "name": node.get_meta("landmark_name"),
				"path_m": part.get_meta("distance_m"), "at": part.global_position})
	return spots


## Weltpunkt neben der Straße auf Geländehöhe.
func _beside_road(distance_m: float, meters: float) -> Vector3:
	var p := track.position_at(distance_m) + _side_offset(distance_m, meters)
	p.y = terrain.height_at(p.x, p.z)
	return p


## Fahrtrichtung (#34, nach Track.set_direction): Torbögen und Kilometersteine der Richtung zeigen; die Stationsschilder
## stehen am Beginn ihrer Station in Fahrtrichtung, mit dem Namen in dieser Richtung (Track.ride_stations), der Pfosten
## rechts. Im Uhrzeigersinn steht alles wie beim Aufbau.
func set_direction(direction: String) -> void:
	var ccw := direction == Track.DIRECTION_CCW
	get_node("Segments").visible = not ccw
	get_node("SegmentsCcw").visible = ccw
	var details := get_node_or_null("Details")
	if details != null:
		details.get_node("Kilometersteine").visible = not ccw
		details.get_node("KilometersteineCcw").visible = ccw
	var stations := get_node("Stations")
	for station in track.ride_stations():
		var marker := stations.get_node_or_null(NodePath(station["id"])) as Node3D
		if marker == null:
			continue
		var path_m := track.path_distance(station["start_m"], direction)
		marker.set_meta("station_name", station["name"])
		marker.set_meta("distance_m", path_m)
		marker.position = track.position_at(path_m)
		(marker.get_node("Label") as Label3D).text = station["name"]
		(marker.get_node("Post") as Node3D).position = _side_offset(path_m, -4.2 if ccw else 4.2) + Vector3(0.0, 3.5, 0.0)


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
	# Laternen landseitig an der Uferstraße (nachts beleuchtet, G6)
	var lanterns: Array[Transform3D] = []
	d = 8.0
	while d < 340.0:
		lanterns.append(_scaled(_beside_road(d, 4.8), 2.6, 0.0))
		d += 30.0
	_scatter(node, "Laternen", "fantasy-town/lantern.glb", lanterns)
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


## Torbögen am Start jedes Segments (#33, Track.segments) im Stil des Start/Ziel-Bogens, blau statt rot, mit dem Namen
## des Segments auf dem Banner (zur anfahrenden Kamera hin). Knoten `Segments/<id>` (im Uhrzeigersinn) und
## `SegmentsCcw/<id>` (gegen ihn, #34: am Start in dieser Richtung, Banner zur Gegenrichtung) mit Metadaten
## `segment_name`, `distance_m` (Fahrtposition in ihrer Richtung).
func _build_segment_gates() -> void:
	for direction in [Track.DIRECTION_CW, Track.DIRECTION_CCW]:
		var gates := Node3D.new()
		gates.name = "Segments" if direction == Track.DIRECTION_CW else "SegmentsCcw"
		gates.visible = direction == track.direction
		add_child(gates)
		var segments: Array = track.segments_by_direction.get(direction,
				track.segments if direction == Track.DIRECTION_CW else [])
		for segment in segments:
			var path_m := track.path_distance(segment["start_m"], direction)
			_segment_gate(gates, segment, track.position_at(path_m),
					_yaw_at(path_m) + (PI if direction == Track.DIRECTION_CCW else 0.0))


## Ein Torbogen für `segment` an `at` mit Drehung `yaw` (Banner-Name zur anfahrenden Kamera).
func _segment_gate(gates: Node3D, segment: Dictionary, at: Vector3, yaw: float) -> void:
	var blue := Color(0.12, 0.3, 0.62)
	var arch := Node3D.new()
	arch.name = segment["id"]
	arch.set_meta("segment_name", segment["name"])
	arch.set_meta("distance_m", segment["start_m"])
	arch.position = at
	arch.rotation.y = yaw
	gates.add_child(arch)
	_box(arch, "PfostenL", Vector3(0.5, 5.5, 0.5), Vector3(-4.0, 0.0, 0.0), blue)
	_box(arch, "PfostenR", Vector3(0.5, 5.5, 0.5), Vector3(4.0, 0.0, 0.0), blue)
	_box(arch, "Banner", Vector3(8.5, 1.2, 0.3), Vector3(0.0, 5.0, 0.0), Color(0.95, 0.95, 0.95))
	var label := Label3D.new()
	label.name = "Name"
	label.text = segment["name"]
	label.font_size = 72
	label.pixel_size = 0.01
	label.outline_size = 0
	label.modulate = blue
	label.position = Vector3(0.0, 5.6, 0.16)
	arch.add_child(label)


## Küstenstraße (#15): seeseitig (links in Fahrtrichtung) eine niedrige Natursteinmauer am Straßenrand, Büsche und
## Felsen am Hang zum Meer und Klippen an der Wasserlinie; landseitig Pinien, Büsche und Felsen.
## Modelle: Kenney Nature Kit (CC0, siehe ASSETS.md).
func _build_coast() -> void:
	var node := _props_node("kueste")
	var range_m := _station_range("kueste")
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


func _scatter(parent: Node3D, node_name: String, path: String, transforms: Array[Transform3D], shadows: bool = true,
		colors: Dictionary = NATURE_COLORS) -> MultiMeshInstance3D:
	var model := _model_mesh(MODEL_DIR + path, colors)
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
## bekommen die Farben aus `colors` (Standard NATURE_COLORS; z. B. OLIVE_COLORS für silbriges Laub).
static func _model_mesh(path: String, colors: Dictionary = NATURE_COLORS) -> Array:
	var key := path if colors == NATURE_COLORS else "%s#%d" % [path, colors.hash()]
	if not _models.has(key):
		var scene: Node = load(path).instantiate()
		var mesh_node: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var placement := Transform3D()
		var node: Node = mesh_node
		while node != scene:
			placement = (node as Node3D).transform * placement
			node = node.get_parent()
		var mesh: Mesh = mesh_node.mesh.duplicate()
		var names := {}
		for s in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(s) as BaseMaterial3D
			if material != null and material.metallic > 0.0:
				material = material.duplicate()
				material.metallic = 0.0
				material.albedo_color = colors.get(material.resource_name,
						NATURE_COLORS.get(material.resource_name, material.albedo_color))
				mesh.surface_set_material(s, material)
				names[s] = [material.resource_name, material.albedo_color]
		WorldMotion.sway(mesh, path)
		for s in names:
			_nature_materials.append([mesh.surface_get_material(s), names[s][0], names[s][1]])
			_set_nature_color(_nature_materials[-1])
		_models[key] = [mesh, placement]
		scene.free()
	return _models[key]


## Jahreszeit (#39, Season.LOOKS[phase]): Vegetation und Boden (IslandVegetation-Palette), Kenney-Vegetation
## (`tint_nature`) und Mohn – ohne die Welt neu zu bauen.
func set_season(phase: String) -> void:
	var look: Dictionary = Season.LOOKS[phase]
	IslandVegetation.set_palette(look["palette"])
	tint_nature(look["nature"])
	if vegetation != null:
		vegetation.set_kind_visible("Mohn", look["poppies"])


## Kenney-Modelle zentral umfärben (#39): Faktor je Materialname (z. B. "grass", "leafsGreen") auf die Farbe vom
## Laden (NATURE_COLORS/OLIVE_COLORS/…); fehlende Namen zurück auf 1. Wirkt sofort auf alle geladenen Modelle.
static func tint_nature(tints: Dictionary) -> void:
	nature_tint = tints.duplicate()
	for entry in _nature_materials:
		_set_nature_color(entry)


## Farbe eines Eintrags [Material, Materialname, Farbe vom Laden] mit dem aktuellen Faktor (Wind-Shader oder Standard).
static func _set_nature_color(entry: Array) -> void:
	var color: Color = entry[2] * nature_tint.get(entry[1], Color.WHITE)
	if entry[0] is ShaderMaterial:
		(entry[0] as ShaderMaterial).set_shader_parameter("albedo", color)
	elif entry[0] is BaseMaterial3D:
		(entry[0] as BaseMaterial3D).albedo_color = color


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


## Mauerblock-Lage (Naturstein, wie an der Küstenstraße) am Straßenrand, `side` m neben der Mitte (rechts positiv).
func _road_block(distance_m: float, side: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _yaw_at(distance_m)),
			track.position_at(distance_m) + _side_offset(distance_m, side) + Vector3(0.0, 0.3, 0.0))


## Mauerblöcke als MultiMesh (Box wie die Mauer an der Küstenstraße).
func _wall_blocks(parent: Node3D, node_name: String, transforms: Array[Transform3D], size: Vector3 = Vector3(0.5, 0.6, 3.3)) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_multimesh(parent, node_name, mesh, Color(0.76, 0.68, 0.55), transforms)


## Innenseite einer Kehre an `distance_m` (1 rechts, -1 links), 0 auf geraden Stücken und in weiten Bögen.
func _inner_side(distance_m: float) -> float:
	var turn := wrapf(_yaw_at(distance_m + 8.0) - _yaw_at(distance_m - 8.0), -PI, PI)
	if absf(turn) < 0.35:
		return 0.0
	return -signf(turn)


## Talseite an `distance_m`: 1 rechts, -1 links (dort liegt das Gelände 30 m neben der Straße tiefer).
func _valley_side(distance_m: float) -> float:
	return 1.0 if _beside_road(distance_m, 30.0).y < _beside_road(distance_m, -30.0).y else -1.0


## Lage-Listen je Modell (für `_scatter`).
func _model_lists(names: Array) -> Dictionary:
	var lists := {}
	for model in names:
		lists[model] = [] as Array[Transform3D]
	return lists


## Serpentinen (#16, Sa-Calobra-Stil): talseitig eine Natursteinmauer am Straßenrand, in den Kehren außen eine
## durchgehende Mauer und innen weiße Randsteine, in jeder Kehre eine hohe Kalksteinnadel; bergseitig graue
## Kalkfelsen am Hanganschnitt, dazwischen Macchia und vereinzelte Pinien. Aussichtspunkt: gemauerte Plattform über
## der Westküste mit Brüstung, Bänken und Fernrohr. Modelle: Kenney Nature Kit (CC0, siehe ASSETS.md).
func _build_serpentines() -> void:
	var node := _props_node("serpentinen")
	var range_m := _station_range("serpentinen")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1503
	var wall: Array[Transform3D] = []
	var curbs: Array[Transform3D] = []
	var models := _model_lists(SERPENTINE_ROCKS + LIMESTONE + COAST_BUSHES + COAST_PINES)
	var spires := _model_lists(SERPENTINE_ROCKS)
	var centre := Vector3.ZERO
	var centre_count := 0
	var viewpoint_m: float = IslandCourse.landmarks()[0]["distance_m"]
	var d := range_m.x + 10.0
	while d < range_m.y - 5.0:
		var inner := _inner_side(d)
		if inner != 0.0:
			wall.append(_road_block(d, -inner * 3.8))
			curbs.append(Transform3D(Basis(), track.position_at(d) + _side_offset(d, inner * 3.6) + Vector3(0.0, 0.3, 0.0)))
			centre += track.position_at(d) + _side_offset(d, inner * IslandCourse.SERPENTINE_HAIRPIN_RADIUS)
			centre_count += 1
			d += 2.0
			continue
		if centre_count > 10:
			# Kehre zu Ende: Kalksteinnadel in ihrer Mitte
			var at := centre / centre_count
			at.y = terrain.height_at(at.x, at.z) - 1.0
			var h := rng.randf_range(18.0, 26.0)
			spires[SERPENTINE_ROCKS[rng.randi() % SERPENTINE_ROCKS.size()]].append(Transform3D(
					Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * 0.6, h, h * 0.6)), at))
		centre = Vector3.ZERO
		centre_count = 0
		var valley := _valley_side(d)
		if absf(d - viewpoint_m) > 8.0:  # Zugang zur Plattform frei
			wall.append(_road_block(d, valley * 3.8))
		if int(d) % 12 < 4:
			# Bergseite: Kalkfelsen am Hanganschnitt, Macchia, vereinzelt Pinien
			for k in range(4):
				var at := _beside_road(d + rng.randf_range(-6.0, 6.0), -valley * rng.randf_range(9.0, 40.0))
				if terrain.road_distance_at(at.x, at.z) < 8.0:
					continue
				var roll := rng.randf()
				if roll < 0.4:
					var h := rng.randf_range(3.0, 9.0)
					models[SERPENTINE_ROCKS[rng.randi() % SERPENTINE_ROCKS.size()]].append(Transform3D(
							Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * 1.3, h, h * 1.3)), at - Vector3(0.0, 0.5, 0.0)))
				elif roll < 0.55:
					models[LIMESTONE[rng.randi() % LIMESTONE.size()]].append(_scaled(at, rng.randf_range(3.0, 7.0), rng.randf() * TAU))
				elif roll < 0.85:
					models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 9.0), rng.randf() * TAU))
				else:
					models[COAST_PINES[rng.randi() % COAST_PINES.size()]].append(_scaled(at, rng.randf_range(7.0, 11.0), rng.randf() * TAU))
			# Talseite: Macchia, Pinien, einzelne Felsen
			for k in range(2):
				var at := _beside_road(d + rng.randf_range(-6.0, 6.0), valley * rng.randf_range(9.0, 45.0))
				if terrain.road_distance_at(at.x, at.z) < 8.0:
					continue
				var roll := rng.randf()
				if roll < 0.5:
					models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 9.0), rng.randf() * TAU))
				elif roll < 0.8:
					models[COAST_PINES[rng.randi() % COAST_PINES.size()]].append(_scaled(at, rng.randf_range(7.0, 11.0), rng.randf() * TAU))
				else:
					models[LIMESTONE[rng.randi() % LIMESTONE.size()]].append(_scaled(at, rng.randf_range(2.5, 5.0), rng.randf() * TAU))
		d += 4.0
	_wall_blocks(node, "Mauer", wall)
	_multimesh(node, "Randsteine", _cylinder(0.3, 0.6), Color(0.92, 0.92, 0.9), curbs)
	for model in models:
		_scatter(node, model, "nature/%s.glb" % model, models[model], not (model in COAST_BUSHES))
	for model in spires:
		_scatter(node, SPIRE_PREFIX + model, "nature/%s.glb" % model, spires[model])
	_build_viewpoint(node)


## Aussichtspunkt (Landmarke bei 4,59 km): gemauerte Plattform links über der Westküste auf Straßenhöhe, Brüstung an
## drei Seiten (die Straßenmauer bleibt am Zugang offen), zwei Bänke, Fernrohr.
func _build_viewpoint(node: Node3D) -> void:
	var view: Dictionary = IslandCourse.landmarks()[0]
	var d: float = view["distance_m"]
	var yaw := _yaw_at(d)
	var turn := Basis(Vector3.UP, yaw)
	var centre := track.position_at(d) + _side_offset(d, -10.0)
	var stone := Color(0.76, 0.7, 0.6)
	# Plattform als Bastion: Oberkante knapp unter der Fahrbahn, nach unten bis in den Hang
	_box(node, "Plattform", Vector3(14.0, 8.0, 12.0), centre + Vector3(0.0, -8.05, 0.0), stone, yaw)
	_box(node, "Bruestung", Vector3(0.6, 1.0, 12.0), centre + turn * Vector3(-6.7, 0.0, 0.0), stone, yaw)
	_box(node, "BruestungVorn", Vector3(14.0, 1.0, 0.6), centre + turn * Vector3(0.0, 0.0, -5.7), stone, yaw)
	_box(node, "BruestungHinten", Vector3(14.0, 1.0, 0.6), centre + turn * Vector3(0.0, 0.0, 5.7), stone, yaw)
	var wood := Color(0.5, 0.35, 0.2)
	_box(node, "Bank", Vector3(0.6, 0.5, 2.2), centre + turn * Vector3(-4.5, 0.0, -2.5), wood, yaw)
	_box(node, "Bank2", Vector3(0.6, 0.5, 2.2), centre + turn * Vector3(-4.5, 0.0, 2.5), wood, yaw)
	var post := _add_mesh("Fernrohr", _cylinder(0.08, 1.2), _flat_material(Color(0.3, 0.3, 0.32)), node)
	post.position = centre + turn * Vector3(-5.6, 0.6, 0.0)
	var scope := _add_mesh("FernrohrRohr", _cylinder(0.12, 0.8), _flat_material(Color(0.2, 0.35, 0.3)), node)
	scope.position = centre + turn * Vector3(-5.6, 1.3, 0.0)
	scope.basis = turn * Basis(Vector3.FORWARD, PI / 2.0)


## Pinien-/Olivenhain (#16): in Abschnitten von 150 m im Wechsel auf einer Seite Olivenbäume in Reihen hinter einer
## Trockenmauer, auf der anderen Pinienwald; Gras und Blumen unter den Oliven. Modelle: Kenney Nature Kit (CC0, siehe
## ASSETS.md); die Oliven bekommen silbriges Laub und dunkle Stämme (OLIVE_COLORS).
func _build_grove() -> void:
	var node := _props_node("hain")
	var range_m := _station_range("hain")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1504
	var olives := _model_lists(OLIVE_TREES)
	var models := _model_lists(GROVE_PINES + GROUND_PLANTS + COAST_BUSHES)
	var terraces: Array[Transform3D] = []
	var d := range_m.x + 4.0
	while d < range_m.y:
		for side_sign in [-1.0, 1.0]:
			var olive_side: bool = (int((d - range_m.x) / 150.0) % 2 == 0) == (side_sign > 0.0)
			if olive_side:
				terraces.append(_road_block(d, side_sign * 10.0))
				if int(d) % 8 >= 4:
					continue
				for row in range(6):
					var at := _beside_road(d + rng.randf_range(-0.8, 0.8), side_sign * (15.0 + row * 9.0 + rng.randf_range(-1.0, 1.0)))
					if terrain.road_distance_at(at.x, at.z) < 10.0:
						continue
					var s := rng.randf_range(4.5, 6.5)
					olives[OLIVE_TREES[rng.randi() % OLIVE_TREES.size()]].append(Transform3D(
							Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.5, s * 0.9, s * 1.5)), at - Vector3(0.0, 0.2, 0.0)))
					if rng.randf() < 0.5:
						var ground := _beside_road(d + rng.randf_range(2.0, 6.0), side_sign * (15.0 + row * 9.0 + rng.randf_range(2.0, 5.0)))
						models[GROUND_PLANTS[rng.randi() % GROUND_PLANTS.size()]].append(_scaled(ground, rng.randf_range(4.0, 6.0), rng.randf() * TAU))
			elif int(d) % 8 < 4:
				for k in range(3):
					var at := _beside_road(d + rng.randf_range(-4.0, 4.0), side_sign * rng.randf_range(9.0, 70.0))
					if terrain.road_distance_at(at.x, at.z) < 8.0:
						continue
					if rng.randf() < 0.75:
						models[GROVE_PINES[rng.randi() % GROVE_PINES.size()]].append(_scaled(at, rng.randf_range(9.0, 14.0), rng.randf() * TAU))
					else:
						models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 8.0), rng.randf() * TAU))
		d += 4.0
	_wall_blocks(node, "Trockenmauer", terraces, Vector3(0.6, 0.8, 3.6))
	for model in olives:
		_scatter(node, model, "nature/%s.glb" % model, olives[model], true, OLIVE_COLORS)
	for model in models:
		_scatter(node, model, "nature/%s.glb" % model, models[model], model in GROVE_PINES)


## Bergdorf (#16): Häuserzeilen aus Natursteinhäusern mit Terrakotta-Dächern, Rundbogentüren und Fensterläden beidseits
## der Straße; in der Mitte rechts ein Platz mit Kirche (Glockenturm), Brunnen und Marktständen; Laternen an der
## Straße, Blumentöpfe vor den Häusern. Modelle: Kenney Fantasy Town Kit (CC0, Palette mediterran abgewandelt) und
## Nature Kit (siehe ASSETS.md). Gleiche Module aller Häuser teilen sich ein MultiMesh.
func _build_village() -> void:
	var node := _props_node("bergdorf")
	var range_m := _station_range("bergdorf")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1505
	var square := (range_m.x + range_m.y) / 2.0
	var parts := {}
	var pots: Array[Transform3D] = []
	var flowers := _model_lists(["flower_redA", "flower_purpleA", "flower_yellowA"])
	for side_sign in [-1.0, 1.0]:
		var d := range_m.x + 6.0
		while d < range_m.y - 6.0:
			var cells := rng.randi_range(2, 4)
			var width := cells * HOUSE_MODULE_M
			var mid := d + width / 2.0
			if side_sign > 0.0 and absf(mid - square) < 22.0 + width / 2.0:
				d = square + 22.0
				continue
			var at := _beside_road(mid, side_sign * (rng.randf_range(7.5, 9.0) + HOUSE_MODULE_M))
			var to_road := track.position_at(mid) - at
			_town_house(parts, at - Vector3(0.0, 0.3, 0.0), atan2(-to_road.x, -to_road.z), cells, 2 if rng.randf() < 0.7 else 1)
			if rng.randf() < 0.6:
				var pot := _beside_road(mid + rng.randf_range(-width / 3.0, width / 3.0), side_sign * 6.8)
				pots.append(_scaled(pot, 2.5, rng.randf() * TAU))
				flowers[flowers.keys()[rng.randi() % 3]].append(_scaled(pot + Vector3(0.0, 0.35, 0.0), 6.0, rng.randf() * TAU))
			d += width + rng.randf_range(0.0, 2.5)
	for file in parts:
		_scatter(node, "Haus_" + file, "fantasy-town/%s.glb" % file, parts[file])
	# Platz mit Kirche: Fassade zur Straße, Glockenturm an der Ecke, Brunnen davor
	var church := Node3D.new()
	church.name = "Kirche"
	node.add_child(church)
	var church_at := _beside_road(square, 27.0)
	var to_road := track.position_at(square) - church_at
	var church_parts := {}
	_church(church_parts, church_at - Vector3(0.0, 0.3, 0.0), atan2(-to_road.x, -to_road.z))
	for file in church_parts:
		_scatter(church, file, "fantasy-town/%s.glb" % file, church_parts[file])
	_place_model(node, "fantasy-town/fountain-round.glb", _beside_road(square, 12.5), 0.0, 3.0)
	_place_model(node, "fantasy-town/stall-red.glb", _beside_road(square - 12.0, 13.0), _yaw_at(square), 3.0)
	_place_model(node, "fantasy-town/stall-red.glb", _beside_road(square + 12.0, 13.0), _yaw_at(square), 3.0)
	_place_model(node, "fantasy-town/cart.glb", _beside_road(square + 17.0, 9.0), _yaw_at(square) + 0.4, 2.5)
	var lanterns: Array[Transform3D] = []
	var d := range_m.x + 10.0
	while d < range_m.y:
		for side_sign in [-1.0, 1.0]:
			lanterns.append(_scaled(_beside_road(d, side_sign * 4.6), 2.6, 0.0))
		d += 28.0
	_scatter(node, "Laternen", "fantasy-town/lantern.glb", lanterns)
	_scatter(node, "Blumentoepfe", "nature/pot_large.glb", pots)
	for model in flowers:
		_scatter(node, model, "nature/%s.glb" % model, flowers[model], false)


## Modul-Lage `local_yaw`/`local` (in Modul-Einheiten) eines Hauses mit Grundlage `base` in `parts[file]` sammeln.
func _part(parts: Dictionary, file: String, base: Transform3D, local: Vector3, local_yaw: float) -> void:
	if not parts.has(file):
		parts[file] = [] as Array[Transform3D]
	parts[file].append(base * Transform3D(Basis(Vector3.UP, local_yaw), local))


## Dorfhaus aus Fantasy-Town-Modulen (eine Einheit = HOUSE_MODULE_M): `cells` breit, 2 tief, `floors` Geschosse,
## Satteldach mit First in der Mitte. Die Front (lokal −z) hat unten eine Rundbogentür und Fensterläden, oben
## Fensterläden; die Wandmodule sitzen am Außenrand ihrer Zelle (Modul +x zeigt nach außen).
func _town_house(parts: Dictionary, at: Vector3, yaw: float, cells: int, floors: int) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * HOUSE_MODULE_M), at)
	var x0 := -cells / 2.0
	var door := cells / 2
	for f in range(floors):
		for i in range(cells):
			var front := "wall-doorway-round" if f == 0 and i == door else "wall-window-shutters"
			_part(parts, front, base, Vector3(x0 + i + 0.5, f, -0.5), PI / 2.0)
			_part(parts, "wall-window-small" if f == floors - 1 else "wall", base, Vector3(x0 + i + 0.5, f, 0.5), -PI / 2.0)
		for j in range(2):
			_part(parts, "wall", base, Vector3(x0 + 0.5, f, j - 0.5), PI)
			_part(parts, "wall-window-small" if j == f % 2 else "wall", base, Vector3(x0 + cells - 0.5, f, j - 0.5), 0.0)
	for i in range(cells):
		_part(parts, "roof-high", base, Vector3(x0 + i + 0.5, floors, -0.5), -PI / 2.0)
		_part(parts, "roof-high", base, Vector3(x0 + i + 0.5, floors, 0.5), PI / 2.0)


## Dorfkirche aus Fantasy-Town-Modulen (eine Einheit = CHURCH_MODULE_M): Schiff 2 breit und 4 lang mit First von der
## Fassade (lokal −z, Rundbogenportale, darüber Rundfenster) nach hinten, Glockenturm (1 × 1, 5 Geschosse,
## Schallfenster, Zeltdach) an der rechten vorderen Ecke.
func _church(parts: Dictionary, at: Vector3, yaw: float) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * CHURCH_MODULE_M), at)
	for f in range(2):
		for i in range(2):
			_part(parts, "wall-doorway-round" if f == 0 else "wall-window-round", base, Vector3(i - 0.5, f, -1.5), PI / 2.0)
			_part(parts, "wall", base, Vector3(i - 0.5, f, 1.5), -PI / 2.0)
		for j in range(4):
			_part(parts, "wall-window-round" if f == 1 else "wall", base, Vector3(-0.5, f, j - 1.5), PI)
			_part(parts, "wall-window-round" if f == 1 else "wall", base, Vector3(0.5, f, j - 1.5), 0.0)
	for j in range(4):
		_part(parts, "roof-high", base, Vector3(-0.5, 2.0, j - 1.5), 0.0)
		_part(parts, "roof-high", base, Vector3(0.5, 2.0, j - 1.5), PI)
	var tower := Vector3(1.5, 0.0, -1.5)
	for f in range(5):
		for side in range(4):
			_part(parts, "wall-window-round" if f == 4 else "wall", base, tower + Vector3(0.0, f, 0.0), side * PI / 2.0)
	_part(parts, "roof-high-point", base, tower + Vector3(0.0, 5.0, 0.0), 0.0)


## Abfahrt (#16): über den Osthang zurück zum Hafen – talseitig die Natursteinmauer, Pinien und Zypressen,
## Olivenhaine auf der Bergseite (Abschnitte von 300 m), Macchia und Kalkfelsen; einzelne Fincas mit Zypressen, auf
## den letzten 350 m Palmen am Ortsrand des Hafens. Modelle: Kenney Nature Kit und City Kit (CC0, siehe ASSETS.md).
func _build_descent() -> void:
	var node := _props_node("abfahrt")
	var range_m := _station_range("abfahrt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1506
	var wall: Array[Transform3D] = []
	var models := _model_lists(COAST_PINES + COAST_BUSHES + LIMESTONE + ["tree_palmTall"])
	var olives := _model_lists(OLIVE_TREES)
	var cypresses: Array[Transform3D] = []
	var d := range_m.x + 5.0
	while d < range_m.y - 5.0:
		var valley := _valley_side(d)
		wall.append(_road_block(d, valley * 3.8))
		var olive_zone := int((d - range_m.x) / 300.0) % 3 == 1
		var near_harbour := d > range_m.y - 350.0
		if int(d) % 12 < 4:
			for k in range(6):
				var side := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(9.0, 80.0)
				var at := _beside_road(d + rng.randf_range(-6.0, 6.0), side)
				if at.y < 1.0 or terrain.road_distance_at(at.x, at.z) < 8.0:
					continue
				var roll := rng.randf()
				if near_harbour and roll < 0.4:
					models["tree_palmTall"].append(_scaled(at, rng.randf_range(5.5, 7.5), rng.randf() * TAU))
				elif olive_zone and signf(side) != valley and roll < 0.7:
					var s := rng.randf_range(4.5, 6.0)
					olives[OLIVE_TREES[rng.randi() % OLIVE_TREES.size()]].append(Transform3D(
							Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.5, s * 0.9, s * 1.5)), at - Vector3(0.0, 0.2, 0.0)))
				elif roll < 0.35:
					models[COAST_PINES[rng.randi() % COAST_PINES.size()]].append(_scaled(at, rng.randf_range(8.0, 12.0), rng.randf() * TAU))
				elif roll < 0.5:
					cypresses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(6.0, rng.randf_range(7.0, 10.0), 6.0)), at))
				elif roll < 0.85:
					models[COAST_BUSHES[rng.randi() % COAST_BUSHES.size()]].append(_scaled(at, rng.randf_range(5.0, 9.0), rng.randf() * TAU))
				else:
					models[LIMESTONE[rng.randi() % LIMESTONE.size()]].append(_scaled(at, rng.randf_range(2.5, 5.0), rng.randf() * TAU))
		d += 4.0
	# Fincas: Landhaus (City Kit, wie am Hafen) bergseitig mit zwei Zypressen an der Zufahrt
	var houses := ["building-type-c", "building-type-k", "building-type-g", "building-type-r", "building-type-h"]
	var i := 0
	for finca_m in [range_m.x + 350.0, range_m.x + 900.0, range_m.x + 1500.0, range_m.x + 2050.0, range_m.x + 2600.0]:
		var side := -_valley_side(finca_m) * rng.randf_range(24.0, 30.0)
		var at := _beside_road(finca_m, side)
		var to_road := track.position_at(finca_m) - at
		_place_model(node, "city-suburban/%s.glb" % houses[i % houses.size()], at - Vector3(0.0, 0.4, 0.0),
				atan2(to_road.x, to_road.z), rng.randf_range(8.5, 10.0))
		for offset in [-7.0, 7.0]:
			var cypress := _beside_road(finca_m + offset, side * 0.55)
			cypresses.append(Transform3D(Basis().scaled(Vector3(6.0, 9.0, 6.0)), cypress))
		i += 1
	_wall_blocks(node, "Mauer", wall)
	for model in models:
		_scatter(node, model, "nature/%s.glb" % model, models[model], not (model in COAST_BUSHES))
	for model in olives:
		_scatter(node, model, "nature/%s.glb" % model, olives[model], true, OLIVE_COLORS)
	_scatter(node, "Zypressen", "nature/%s.glb" % CYPRESS, cypresses, true, CYPRESS_COLORS)


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
