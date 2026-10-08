## Sehenswürdigkeiten und Kleindetails der Insel (G2) – von `IslandWorld.build()` nach der Stations-Deko gebaut.
##
## Landmarken (je ein Node3D unter `World/Landmarks/<id>`, Metadaten `landmark_name`, `distance_m` = nächste
## Streckenposition, `side` = "links"/"rechts" in Fahrtrichtung), Mallorca-typisch und von der Strecke aus im Bild:
##   leuchtturm   Leuchtturm auf der Felsküste (Formentor-Anmutung), vom Hafen geradeaus zu sehen
##   cala         Badebucht westlich des Kais mit Sonnenschirmen, Liegen und Fischerhütten
##   talaia       runder Wachturm aus Naturstein auf der Westklippe
##   ermita       Einsiedelei mit Kirche und Klostertrakt auf dem Plateau über der Westküste (Serpentinen)
##   burg         Burgruine auf einem Felssockel über der Ostküste (Abfahrt)
##   aquaedukt    Bogenaquädukt neben der Abfahrt
##   windmuehlen  drei Windmühlen (Molins) an der unteren Abfahrt
## Animierbar (bewegt von WorldMotion, G3): `windmuehlen/Muehle<n>/Fluegel` (Drehachse lokal z, Pivot =
## Nabe), `leuchtturm/Lampe` (Drehachse lokal y, Pivot = Laternenmitte), Boote unter `Details/Boote`.
##
## Kleindetails unter `World/Details`: Kilometersteine, Agaven (teils mit Blütenstand), Feigenkakteen, Schafe und
## Ziegen, Blumen am Straßenrand, Boote und Bojen in den Buchten der Westküste, Bushaltestelle am Bergdorf.
##
## Gebäude aus Grundkörpern sind je Landmarke zu einem Mesh mit Vertex-Farben zusammengefasst (`Parts`, ein
## Draw-Call); Wiederholtes ist MultiMesh. Eigene Zufallsgeneratoren (Seeds 1507, 1508) – die Platzierungen der
## Stationen (1501–1506) bleiben unverändert. `placements` hält jede Platzierung ({id, at, radius_m}) für Tests:
## nichts liegt auf der Fahrbahn oder der Mauer (Abstand zur Straßenmitte − Radius ≥ 3,8 m).
## Bewusste Ausnahme von der `_`-Konvention: Die Klasse ist ausgelagerter Teil von `IslandWorld` und nutzt deren
## Bauhelfer (`_beside_road`, `_scatter`, `_place_model`, `_town_house` …) direkt.
class_name IslandLandmarks
extends RefCounted

## Mindestabstand (m) jeder Platzierung zur Straßenmitte: Fahrbahnhälfte 3,0 m, Mauer bei 3,8 m.
const ROAD_CLEARANCE_M := 4.2
const STONE := Color(0.74, 0.66, 0.52)
const WHITEWASH := Color(0.93, 0.92, 0.88)
const RUIN := Color(0.6, 0.53, 0.43)
const TERRACOTTA := Color(0.7, 0.36, 0.22)
const DARK := Color(0.16, 0.14, 0.13)
## Lage (x, z) der Ermita: Plateau über der Westküste (La-Trapa-Anmutung), auf den Rampen nach Westen voraus vor dem Meer.
const HERMITAGE_XZ := Vector2(-880.0, -420.0)
## Rastergröße (m) der Straßenpunkte für `road_clearance`.
const BUCKET_M := 25.0

var world: IslandWorld
var placements: Array[Dictionary] = []
## Straßenpunkte (x, z) in Eimern zu BUCKET_M für den Fahrbahnabstand.
var _road_buckets := {}


func _init(owner: IslandWorld) -> void:
	world = owner
	var points := world.track.curve.get_baked_points()
	for p in points:
		var key := Vector2i(floori(p.x / BUCKET_M), floori(p.z / BUCKET_M))
		if not _road_buckets.has(key):
			_road_buckets[key] = PackedVector2Array()
		_road_buckets[key].append(Vector2(p.x, p.z))


func build() -> void:
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	world.add_child(landmarks)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1507
	_lighthouse(landmarks, rng)
	_cala(landmarks, rng)
	_talaia(landmarks, rng)
	_hermitage(landmarks)
	_castle(landmarks, rng)
	_aqueduct(landmarks)
	_windmills(landmarks, rng)
	var details := Node3D.new()
	details.name = "Details"
	world.add_child(details)
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = 1508
	_kilometre_stones(details)
	_kilometre_stones(details, Track.DIRECTION_CCW)
	_plants_and_animals(details, detail_rng)
	_cove_boats(details, detail_rng)
	_bus_stop(details)


## Horizontaler Abstand von `p` zur Straßenmitte (m), INF weiter als zwei Eimer.
func road_clearance(p: Vector3) -> float:
	var best := INF
	var key := Vector2i(floori(p.x / BUCKET_M), floori(p.z / BUCKET_M))
	var q := Vector2(p.x, p.z)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for r in _road_buckets.get(key + Vector2i(dx, dz), PackedVector2Array()):
				best = minf(best, q.distance_to(r))
	return best


## Platzierung merken (Test: nicht auf der Fahrbahn).
func _register(id: String, at: Vector3, radius: float) -> void:
	placements.append({"id": id, "at": at, "radius_m": radius})


## Frei von der Straße? (Abstand − Radius ≥ ROAD_CLEARANCE_M)
func _clear_of_road(at: Vector3, radius: float) -> bool:
	return road_clearance(at) - radius >= ROAD_CLEARANCE_M


## Landmarken-Wurzel an `at` mit Metadaten.
func _landmark(parent: Node3D, id: String, title: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.position = at
	node.rotation.y = yaw
	var d := world.track.curve.get_closest_offset(at)
	var road := world.track.position_at(d)
	var right := world._side_offset(d, 1.0)
	node.set_meta("landmark_name", title)
	node.set_meta("distance_m", d)
	node.set_meta("side", "rechts" if right.dot(at - road) > 0.0 else "links")
	parent.add_child(node)
	return node


func _vertex_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	return material


## Zusammengefasstes Mesh als Kind von `parent`.
func _mesh_node(parent: Node3D, node_name: String, parts: Parts, material: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = parts.commit()
	instance.material_override = material if material != null else _vertex_material()
	parent.add_child(instance)
	return instance


## Leuchtturm (Formentor-Anmutung) auf der Felsküste links der Küstenstraße: weißer, sich verjüngender Turm auf einem
## Sockel, Galerie, Laterne (eigener Knoten `Lampe`, drehbar um y) mit Kuppel, Wärterhaus, Felsen am Fuß.
func _lighthouse(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var d := 880.0
	var at := _shore_point(d, 4.0)
	var node := _landmark(parent, "leuchtturm", "Leuchtturm", at, world._yaw_at(d))
	node.scale = Vector3.ONE * 1.5  # aus der Ferne (Hafen, Küstenstraße) deutlich sichtbar
	var parts := Parts.new()
	parts.cylinder(6.0, 6.5, 5.0, Vector3(0.0, 0.5, 0.0), WHITEWASH.darkened(0.12))
	parts.cylinder(2.4, 3.3, 22.0, Vector3(0.0, 14.0, 0.0), WHITEWASH)
	for k in range(4):
		parts.box(Vector3(0.6, 1.0, 0.3), Transform3D(Basis(), Vector3(0.0, 7.0 + k * 4.5, 3.05 - k * 0.2)), DARK)
	parts.cylinder(3.3, 3.3, 0.5, Vector3(0.0, 25.25, 0.0), Color(0.3, 0.3, 0.3))
	parts.cylinder(3.1, 3.1, 0.9, Vector3(0.0, 25.95, 0.0), Color(0.35, 0.35, 0.36))
	parts.cylinder(0.2, 2.1, 1.6, Vector3(0.0, 29.9, 0.0), Color(0.2, 0.32, 0.28))
	parts.sphere(0.35, Vector3(0.0, 30.9, 0.0), Color(0.2, 0.32, 0.28))
	# Wärterhaus hinter dem Turm (lokal +z, entlang der Küste): weiß, Flachdach mit Rand, Tür und Fenster zur Straße
	parts.box(Vector3(7.0, 5.0, 10.0), Transform3D(Basis(), Vector3(0.0, 1.5, 10.0)), WHITEWASH)
	parts.box(Vector3(7.4, 0.5, 10.4), Transform3D(Basis(), Vector3(0.0, 4.25, 10.0)), STONE)
	parts.box(Vector3(0.2, 2.2, 1.2), Transform3D(Basis(), Vector3(3.55, 0.6, 10.0)), Color(0.2, 0.35, 0.3))
	for z in [7.0, 13.0]:
		parts.box(Vector3(0.2, 1.0, 1.0), Transform3D(Basis(), Vector3(3.55, 2.2, z)), Color(0.2, 0.35, 0.3))
	_mesh_node(node, "Bau", parts)
	# Laterne: drehbar (Linse versetzt, damit eine Drehung sichtbar ist)
	var lamp := Node3D.new()
	lamp.name = "Lampe"
	lamp.position = Vector3(0.0, 27.8, 0.0)
	node.add_child(lamp)
	var glass := Parts.new()
	glass.cylinder(1.7, 1.7, 2.6, Vector3.ZERO, Color(1.0, 0.92, 0.6))
	glass.box(Vector3(0.5, 1.2, 1.4), Transform3D(Basis(), Vector3(1.55, 0.0, 0.0)), Color(1.0, 1.0, 0.85))
	var light := StandardMaterial3D.new()
	light.vertex_color_use_as_albedo = true
	light.emission_enabled = true
	light.emission = Color(1.0, 0.85, 0.5)
	light.emission_energy_multiplier = 1.5
	_mesh_node(lamp, "Licht", glass, light)
	var rocks: Array[Transform3D] = []
	for k in range(7):
		var angle := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(7.0, 10.0)
		var s := rng.randf_range(3.5, 6.0)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.4, s, s * 1.4)),
				Vector3(cos(angle) * r, -1.5, sin(angle) * r)))
	world._scatter(node, "Felsen", "nature/rock_largeA.glb", rocks)
	_register("leuchtturm", at, 24.0)


## Punkt auf festem Land links der Straße kurz vor der Wasserlinie (Abstand `inset` m landeinwärts).
func _shore_point(d: float, inset: float) -> Vector3:
	var water := world._water_distance(d, 250.0)
	var m := water
	var at := world._beside_road(d, -m)
	while m > 12.0 and at.y < 2.5:
		m -= 1.0
		at = world._beside_road(d, -m)
	return world._beside_road(d, -maxf(m - inset, 12.0))


## Talaia: runder Wachturm aus Naturstein auf der Westklippe (seeseitig), Hocheingang, Zinnen, Felsen am Fuß.
func _talaia(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var d := 1720.0
	var water := world._water_distance(d, 250.0)
	var at := world._beside_road(d, -maxf(water * 0.55, 22.0))
	var node := _landmark(parent, "talaia", "Talaia (Wachturm)", at, world._yaw_at(d))
	node.scale = Vector3.ONE * 1.3  # überragt die Klippenfelsen der Küstenstraße
	var parts := Parts.new()
	parts.cylinder(3.7, 4.4, 13.0, Vector3(0.0, 4.5, 0.0), STONE)
	parts.cylinder(4.0, 3.8, 1.2, Vector3(0.0, 11.6, 0.0), STONE.darkened(0.08))
	for k in range(8):
		var angle := TAU * k / 8.0
		parts.box(Vector3(1.1, 0.9, 0.7), Transform3D(Basis(Vector3.UP, -angle), Vector3(sin(angle) * 3.6, 12.6, cos(angle) * 3.6)), STONE.darkened(0.08))
	# Hocheingang zur Landseite (rechts, lokal +x) mit Steinstufen
	parts.box(Vector3(0.3, 2.0, 1.1), Transform3D(Basis(), Vector3(4.05, 6.0, 0.0)), DARK)
	for k in range(5):
		parts.box(Vector3(1.2, 0.5, 1.4), Transform3D(Basis(), Vector3(4.6 + k * 0.6, 4.8 - k * 1.0, -1.6)), STONE.darkened(0.15))
	_mesh_node(node, "Bau", parts)
	var rocks: Array[Transform3D] = []
	for k in range(6):
		var angle := TAU * k / 6.0 + rng.randf_range(-0.4, 0.4)
		var s := rng.randf_range(2.5, 4.5)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.5, s, s * 1.5)),
				Vector3(cos(angle) * 6.0, -1.0, sin(angle) * 6.0)))
	world._scatter(node, "Felsen", "nature/rock_largeB.glb", rocks)
	_register("talaia", at, 13.0)


## Ermita auf dem Plateau über der Westküste (auf den Rampen nach Westen voraus), doppelt skaliert: Kirche
## (Module wie die Dorfkirche) mit Fassade zu den Serpentinen, Klostertrakt (Dorfhaus-Module), gemauerte Terrasse,
## Zypressen, Kreuz vor der Fassade.
func _hermitage(parent: Node3D) -> void:
	var top := Vector3(HERMITAGE_XZ.x, -INF, HERMITAGE_XZ.y)
	for x in range(-18, 19, 3):
		for z in range(-18, 19, 3):
			top.y = maxf(top.y, world.terrain.height_at(HERMITAGE_XZ.x + x, HERMITAGE_XZ.y + z))
	var to := Vector3(-500.0, 0.0, -400.0) - top
	var yaw := atan2(-to.x, -to.z)
	var node := _landmark(parent, "ermita", "Ermita (Einsiedelei)", top + Vector3(0.0, 0.5, 0.0), yaw)
	node.scale = Vector3.ONE * 2.0  # aus 400 m (Rampen nach Westen) erkennbar
	var parts := Parts.new()
	parts.box(Vector3(34.0, 20.0, 36.0), Transform3D(Basis(), Vector3(2.0, -10.2, 2.0)), STONE.darkened(0.1))
	# Kreuz vor der Fassade
	parts.box(Vector3(0.4, 4.0, 0.4), Transform3D(Basis(), Vector3(-4.0, 2.0, -13.0)), STONE.darkened(0.2))
	parts.box(Vector3(1.8, 0.4, 0.4), Transform3D(Basis(), Vector3(-4.0, 3.0, -13.0)), STONE.darkened(0.2))
	# Brüstung um die Terrasse
	for side in [-1.0, 1.0]:
		parts.box(Vector3(34.0, 1.0, 0.6), Transform3D(Basis(), Vector3(2.0, 0.3, 2.0 + side * 17.7)), STONE)
		parts.box(Vector3(0.6, 1.0, 36.0), Transform3D(Basis(), Vector3(2.0 + side * 16.7, 0.3, 2.0)), STONE)
	_mesh_node(node, "Terrasse", parts)
	var modules := {}
	world._church(modules, Vector3.ZERO, 0.0)
	var cloister := {}
	world._town_house(cloister, Vector3(12.5, 0.0, 6.0), PI / 2.0, 4, 2)
	for file in modules:
		world._scatter(node, "Kirche_" + file, "fantasy-town/%s.glb" % file, modules[file])
	for file in cloister:
		world._scatter(node, "Kloster_" + file, "fantasy-town/%s.glb" % file, cloister[file])
	var cypresses: Array[Transform3D] = []
	for at in [Vector3(-8.0, 0.0, -10.0), Vector3(-8.0, 0.0, -2.0), Vector3(-8.0, 0.0, 6.0), Vector3(-8.0, 0.0, 14.0),
			Vector3(8.0, 0.0, -12.0), Vector3(14.0, 0.0, -12.0)]:
		cypresses.append(Transform3D(Basis().scaled(Vector3(6.0, 10.0, 6.0)), at))
	world._scatter(node, "Zypressen", "nature/%s.glb" % IslandWorld.CYPRESS, cypresses, true, IslandWorld.CYPRESS_COLORS)
	_register("ermita", top, 52.0)


## Burgruine (Castell-Anmutung) auf einem Felssockel links der Abfahrt über der Ostküste: Ringmauer mit Lücken,
## drei Rundtürme (einer abgebrochen), Bergfried mit abgebrochener Krone.
func _castle(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var d := 7000.0
	var at := world._beside_road(d, -110.0)
	var node := _landmark(parent, "burg", "Burgruine", at, world._yaw_at(d))
	node.scale = Vector3.ONE * 1.6
	var parts := Parts.new()
	parts.cylinder(19.0, 25.0, 12.0, Vector3(0.0, 2.0, 0.0), Color(0.5, 0.45, 0.37), 9)
	var corners: Array[Vector3] = []
	for k in range(7):
		var angle := TAU * k / 7.0 + rng.randf_range(-0.15, 0.15)
		corners.append(Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(15.0, 17.5) + Vector3(0.0, 8.0, 0.0))
	for k in range(7):
		if k == 2 or k == 5:
			continue  # eingestürzte Mauerstücke
		var a := corners[k]
		var b := corners[(k + 1) % 7]
		var h := rng.randf_range(4.0, 8.0)
		var mid := (a + b) / 2.0 + Vector3(0.0, h / 2.0, 0.0)
		var yaw := atan2(b.x - a.x, b.z - a.z)
		parts.box(Vector3(1.6, h, a.distance_to(b) + 1.0), Transform3D(Basis(Vector3.UP, yaw), mid), RUIN)
	for entry in [[0, 11.0], [3, 6.0], [5, 13.0]]:
		var c: Vector3 = corners[entry[0]]
		parts.cylinder(2.6, 3.0, entry[1], c + Vector3(0.0, entry[1] / 2.0, 0.0), RUIN.darkened(0.05))
	parts.box(Vector3(8.0, 15.0, 8.0), Transform3D(Basis(Vector3.UP, 0.2), Vector3(-2.0, 15.5, 1.0)), RUIN)
	parts.box(Vector3(3.5, 3.0, 4.0), Transform3D(Basis(Vector3.UP, 0.2), Vector3(-4.0, 24.5, -0.5)), RUIN)
	for k in range(3):
		parts.box(Vector3(0.6, 2.0, 0.3), Transform3D(Basis(Vector3.UP, 0.2), Vector3(-2.0 + (k - 1) * 2.2, 14.0 + k * 1.5, -3.1)), DARK)
	_mesh_node(node, "Bau", parts)
	var rocks: Array[Transform3D] = []
	for k in range(9):
		var angle := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var s := rng.randf_range(5.0, 8.0)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.6, s, s * 1.6)),
				Vector3(cos(angle) * 23.0, -1.0, sin(angle) * 23.0)))
	world._scatter(node, "Felsen", "nature/stone_largeA.glb", rocks)
	_register("burg", at, 48.0)


## Bogenaquädukt rechts der Abfahrt (parallel zur geraden Rampe nach Süden): Pfeiler bis zum Gelände, Rundbögen aus
## Keilsteinen, Kanal obenauf. Pfeiler zu nah an der Straße entfallen (Lücke).
func _aqueduct(parent: Node3D) -> void:
	var d := 6870.0
	var origin := world._beside_road(d, 48.0)
	var yaw := world._yaw_at(d)
	var node := _landmark(parent, "aquaedukt", "Aquädukt", origin, yaw)
	var bay := 9.0
	var bays := 18
	var ground_max := -INF
	for k in range(bays + 1):
		var s := (k - bays / 2.0) * bay
		var p := origin + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, s)
		ground_max = maxf(ground_max, world.terrain.height_at(p.x, p.z))
	var deck := ground_max - origin.y + 12.0
	var parts := Parts.new()
	var piers := []
	for k in range(bays + 1):
		var s := (k - bays / 2.0) * bay
		var p := origin + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, s)
		var ground := world.terrain.height_at(p.x, p.z) - origin.y - 1.0
		var ok := _clear_of_road(p, 2.0)
		piers.append(ok)
		if ok:
			parts.box(Vector3(2.4, deck - ground, 2.0), Transform3D(Basis(), Vector3(0.0, (deck + ground) / 2.0, s)), STONE)
			_register("aquaedukt", p, 2.0)
	var r := (bay - 2.0) / 2.0
	for k in range(bays):
		if not (piers[k] and piers[k + 1]):
			continue
		var s := (k - bays / 2.0) * bay + bay / 2.0
		var centre := Vector3(0.0, deck - 2.4 - r * 0.85, s)
		for v in range(7):
			var angle := PI * (v + 0.5) / 7.0
			var p := centre + Vector3(0.0, sin(angle) * r, -cos(angle) * r)
			parts.box(Vector3(2.4, 0.8, 1.7), Transform3D(Basis(Vector3.RIGHT, angle - PI / 2.0), p), STONE.darkened(0.05))
		parts.box(Vector3(2.4, 2.4 + r * 0.15, bay), Transform3D(Basis(), Vector3(0.0, deck - 1.2 - r * 0.075, s)), STONE)
		parts.box(Vector3(2.8, 0.4, bay), Transform3D(Basis(), Vector3(0.0, deck + 0.2, s)), STONE.darkened(0.12))
		_register("aquaedukt", origin + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, s), bay / 2.0 + 1.0)
	_mesh_node(node, "Bau", parts)


## Drei Windmühlen (Mallorca-Molí) an der unteren Abfahrt: Steinturm, Holzhaube, sechs Flügel mit Segeltuch. Die
## Flügel sind ein eigener Knoten `Fluegel` (Pivot = Nabe, Drehachse lokal z), zur Straße davor gedreht.
func _windmills(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "windmuehlen"
	group.set_meta("landmark_name", "Windmühlen")
	parent.add_child(group)
	var i := 1
	for entry in [[8330.0, 34.0], [8520.0, -38.0], [8700.0, 30.0]]:
		var d: float = entry[0]
		var side: float = entry[1]
		var at := world._beside_road(d, side)
		while not _clear_of_road(at, 6.0):
			side += signf(side) * 4.0
			at = world._beside_road(d, side)
		var to := world.track.position_at(d - 70.0) - at
		var mill := _landmark(group, "Muehle%d" % i, "Windmühle", at - Vector3(0.0, 0.3, 0.0), atan2(-to.x, -to.z))
		var parts := Parts.new()
		parts.cylinder(2.4, 3.1, 10.0, Vector3(0.0, 4.0, 0.0), STONE.lightened(0.08))
		parts.box(Vector3(1.2, 2.2, 0.3), Transform3D(Basis(), Vector3(0.0, 1.1, -2.85)), Color(0.32, 0.22, 0.14))
		parts.box(Vector3(0.6, 0.7, 0.3), Transform3D(Basis(), Vector3(0.0, 6.0, -2.55)), DARK)
		parts.cylinder(0.3, 2.7, 2.6, Vector3(0.0, 10.3, 0.0), Color(0.45, 0.33, 0.24))
		_mesh_node(mill, "Bau", parts)
		var blades := Node3D.new()
		blades.name = "Fluegel"
		blades.position = Vector3(0.0, 9.8, -3.0)
		blades.rotation.z = rng.randf() * TAU
		mill.add_child(blades)
		var sails := Parts.new()
		sails.cylinder(0.45, 0.45, 1.2, Vector3.ZERO, Color(0.3, 0.22, 0.15), 8, Basis(Vector3.RIGHT, PI / 2.0))
		for k in range(6):
			var turn := Basis(Vector3.BACK, TAU * k / 6.0)
			sails.box(Vector3(0.25, 7.2, 0.2), Transform3D(turn, turn * Vector3(0.0, 3.8, 0.0)), Color(0.4, 0.3, 0.2))
			sails.box(Vector3(1.9, 5.0, 0.06), Transform3D(turn, turn * Vector3(1.05, 4.6, 0.05)), Color(0.94, 0.91, 0.84))
		_mesh_node(blades, "Segel", sails)
		_register("windmuehlen", at, 8.5)
		i += 1


## Cala westlich des Kais: Sonnenschirme mit Liegen auf dem Sand, Fischerhütten (Escars) mit grünen Toren.
func _cala(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var centre := Vector3(40.0, 0.0, 1315.0)
	centre.y = world.terrain.height_at(centre.x, centre.z)
	var node := _landmark(parent, "cala", "Cala (Badebucht)", centre)
	var parts := Parts.new()
	var colors := [Color(0.9, 0.3, 0.2), Color(0.2, 0.5, 0.8), Color(0.95, 0.8, 0.25), Color(0.95, 0.95, 0.92)]
	var spots: Array[Vector3] = []
	var rowboats := [Vector3(132.0, 0.0, 1318.0), Vector3(118.0, 0.0, 1326.0), Vector3(150.0, 0.0, 1312.0)]  # Hafen-Strand
	for k in range(200):
		if spots.size() >= 16:
			break
		var at := Vector3(rng.randf_range(-40.0, 110.0), 0.0, rng.randf_range(1280.0, 1345.0))
		at.y = world.terrain.height_at(at.x, at.z)
		if at.y < 0.4 or at.y > 2.8 or not _clear_of_road(at, 10.0):
			continue
		var free := true
		for other in rowboats + spots:
			if Vector2(other.x - at.x, other.z - at.z).length() < 7.0:
				free = false
		if not free:
			continue
		spots.append(at)
		var local := at - centre
		var color: Color = colors[spots.size() % colors.size()]
		parts.cylinder(0.07, 0.07, 3.0, local + Vector3(0.0, 1.4, 0.0), Color(0.85, 0.85, 0.8), 6)
		parts.cylinder(0.1, 2.1, 0.7, local + Vector3(0.0, 2.9, 0.0), color, 8)
		var yaw := rng.randf() * TAU
		for side in [-0.9, 0.9]:
			var offset := Basis(Vector3.UP, yaw) * Vector3(side, 0.0, 0.6)
			parts.box(Vector3(0.7, 0.3, 1.9), Transform3D(Basis(Vector3.UP, yaw), local + offset + Vector3(0.0, 0.25, 0.0)), WHITEWASH)
		_register("cala", at, 2.5)
	# Fischerhütten am Westende des Strands: Front (Tor) zum Wasser
	var x := -36.0
	for k in range(4):
		var z := 1270.0
		while z < 1380.0 and world.terrain.height_at(x, z) > 1.2:
			z += 1.0
		var at := Vector3(x, 0.0, z - 7.0)
		at.y = world.terrain.height_at(at.x, at.z)
		if at.y > 0.2 and _clear_of_road(at, 4.0):
			var local := at - centre
			parts.box(Vector3(4.2, 3.0, 6.0), Transform3D(Basis(), local + Vector3(0.0, 1.0, 0.0)), Color(0.82, 0.74, 0.6))
			parts.box(Vector3(4.6, 0.35, 6.4), Transform3D(Basis(), local + Vector3(0.0, 2.6, 0.0)), TERRACOTTA)
			parts.box(Vector3(2.6, 2.0, 0.15), Transform3D(Basis(), local + Vector3(0.0, 0.6, 3.0)), Color(0.15, 0.45, 0.3))
			_register("cala", at, 3.8)
		x += 5.0
	_mesh_node(node, "Strand", parts)


## Kilometersteine rechts am Straßenrand (weiß, rote Kappe, Kilometerzahl zum Fahrer hin) je Richtung: `Kilometersteine`
## im Uhrzeigersinn, `KilometersteineCcw` gegen ihn (#34, Kilometer in dieser Richtung, anfangs verborgen;
## IslandWorld.set_direction schaltet um).
func _kilometre_stones(parent: Node3D, direction: String = Track.DIRECTION_CW) -> void:
	var ccw := direction == Track.DIRECTION_CCW
	var node := Node3D.new()
	node.name = "KilometersteineCcw" if ccw else "Kilometersteine"
	node.visible = direction == world.track.direction
	parent.add_child(node)
	var right := -1.0 if ccw else 1.0
	for km in range(1, 10):
		var d := world.track.path_distance(km * 1000.0, direction)
		var side := 4.8
		var at := world._beside_road(d, side * right)
		while not _clear_of_road(at, 0.4):
			side += 0.5
			at = world._beside_road(d, side * right)
		var stone := Node3D.new()
		stone.name = "Km%d" % km
		stone.position = at
		stone.rotation.y = world._yaw_at(d) + (PI if ccw else 0.0)
		node.add_child(stone)
		var parts := Parts.new()
		parts.box(Vector3(0.5, 0.7, 0.25), Transform3D(Basis(), Vector3(0.0, 0.35, 0.0)), WHITEWASH)
		parts.box(Vector3(0.52, 0.2, 0.27), Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)), Color(0.8, 0.15, 0.12))
		_mesh_node(stone, "Stein", parts)
		var label := Label3D.new()
		label.name = "Zahl"
		label.text = str(km)
		label.font_size = 48
		label.pixel_size = 0.006
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.42, 0.13)
		label.visibility_range_end = 120.0
		stone.add_child(label)
		_register("km", at, 0.4)


## Agaven (Rosette aus blaugrünen Blättern, jede vierte mit Blütenstand), Feigenkakteen, Schafe und Ziegen, Blumen am
## Straßenrand – als MultiMesh über den ganzen Kurs, mit Abstand zur Straße.
func _plants_and_animals(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var lists := {"Agaven": [] as Array[Transform3D], "AgavenBluete": [] as Array[Transform3D],
			"Feigenkakteen": [] as Array[Transform3D], "Schafe": [] as Array[Transform3D], "Ziegen": [] as Array[Transform3D]}
	var flowers := world._model_lists(["flower_redA", "flower_purpleA", "flower_yellowA"])
	var length := world.track.length_m()
	var d := 30.0
	while d < length - 30.0:
		var station: String = world.track.station_at(d)["id"]
		var low := world.track.position_at(d).y < 120.0
		# Agaven und Feigenkakteen in Küstennähe und an der unteren Abfahrt, Blumen auf der Hochebene und am Hang
		if station != "bergdorf" and station != "hafen" and rng.randf() < 0.55:
			var at := world._beside_road(d + rng.randf_range(-10.0, 10.0), (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(6.5, 22.0))
			if at.y > 1.0 and _clear_of_road(at, 1.5):
				var transform := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), at)
				if low or station == "serpentinen":
					var roll := rng.randf()
					if roll < 0.2:
						lists["AgavenBluete"].append(transform)
					elif roll < 0.65:
						lists["Agaven"].append(transform)
					else:
						lists["Feigenkakteen"].append(transform)
					_register("pflanze", at, 1.5)
				else:
					flowers[flowers.keys()[rng.randi() % 3]].append(world._scaled(at, rng.randf_range(4.0, 6.0), rng.randf() * TAU))
					_register("blume", at, 0.6)
		# Herden: Schafe im Hain und an der oberen Abfahrt, Ziegen in den Serpentinen und an der Küste
		if int(d) % 400 < 20 and station != "hafen" and station != "bergdorf":
			var goats := station == "serpentinen" or station == "kueste"
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var centre := world._beside_road(d, side * rng.randf_range(22.0, 45.0))
			for k in range(rng.randi_range(4, 8)):
				var at := centre + Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0))
				at.y = world.terrain.height_at(at.x, at.z)
				if at.y < 1.0 or not _clear_of_road(at, 1.0):
					continue
				lists["Ziegen" if goats else "Schafe"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))
				_register("tier", at, 1.0)
		d += 20.0
	var meshes := {"Agaven": _agave_mesh(false), "AgavenBluete": _agave_mesh(true), "Feigenkakteen": _prickly_pear_mesh(),
			"Schafe": _animal_mesh(Color(0.9, 0.88, 0.82), Color(0.2, 0.18, 0.16)),
			"Ziegen": _animal_mesh(Color(0.42, 0.3, 0.2), Color(0.2, 0.15, 0.1))}
	for key in lists:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[key]
		multimesh.instance_count = lists[key].size()
		for k in range(lists[key].size()):
			multimesh.set_instance_transform(k, lists[key][k])
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multimesh
		instance.material_override = _vertex_material()
		parent.add_child(instance)
	for model in flowers:
		world._scatter(parent, "Blumen_" + model, "nature/%s.glb" % model, flowers[model], false)


## Agave: zehn schräg nach außen geneigte, spitze Blätter; mit Blütenstand ein hoher Schaft mit Querästen.
func _agave_mesh(flowering: bool) -> ArrayMesh:
	var parts := Parts.new()
	var leaf := Color(0.42, 0.55, 0.48)
	for k in range(10):
		var yaw := TAU * k / 10.0
		var tilt := 0.5 + 0.35 * (k % 2)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		parts.cylinder(0.0, 0.16, 1.5, basis * Vector3(0.0, 0.75, 0.0), leaf if k % 3 else leaf.darkened(0.12), 4, basis)
	if flowering:
		parts.cylinder(0.05, 0.12, 4.2, Vector3(0.0, 2.1, 0.0), Color(0.45, 0.42, 0.28), 5)
		for k in range(7):
			var y := 2.6 + k * 0.25
			var reach := 0.75 - k * 0.08
			var turn := Basis(Vector3.UP, k * 2.4)
			parts.cylinder(0.025, 0.025, reach * 2.0, Vector3(0.0, y, 0.0), Color(0.45, 0.42, 0.28), 4, turn * Basis(Vector3.FORWARD, PI / 2.0))
			for end in [-1.0, 1.0]:
				parts.sphere(0.13, turn * Vector3(end * reach, y + 0.08, 0.0), Color(0.85, 0.72, 0.3))
	return parts.commit()


## Feigenkaktus: flache, ovale Glieder in zwei Etagen, ein paar rote Früchte.
func _prickly_pear_mesh() -> ArrayMesh:
	var parts := Parts.new()
	var green := Color(0.35, 0.5, 0.28)
	var pads := [[Vector3(0.0, 0.5, 0.0), 0.0, 0.0], [Vector3(0.45, 1.2, 0.1), 0.6, -0.5], [Vector3(-0.4, 1.25, -0.1), 1.9, 0.45],
			[Vector3(0.2, 1.9, 0.0), 0.3, 0.2], [Vector3(-0.6, 0.55, 0.3), 2.4, 0.3], [Vector3(0.8, 1.85, 0.2), 1.1, -0.7]]
	for pad in pads:
		var basis := Basis(Vector3.UP, pad[1]) * Basis(Vector3.BACK, pad[2]) * Basis().scaled(Vector3(0.5, 0.65, 0.12))
		parts.sphere(1.0, pad[0], green if pad[0].y < 1.5 else green.lightened(0.08), basis)
	for fruit in [Vector3(0.2, 2.5, 0.0), Vector3(0.55, 1.75, 0.1), Vector3(-0.3, 1.85, -0.1)]:
		parts.sphere(0.1, fruit, Color(0.75, 0.2, 0.25))
	return parts.commit()


## Schaf/Ziege: Rumpf, Kopf, vier Beine (Blick lokal −z).
func _animal_mesh(body: Color, legs: Color) -> ArrayMesh:
	var parts := Parts.new()
	parts.box(Vector3(0.55, 0.5, 1.0), Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)), body)
	parts.box(Vector3(0.3, 0.32, 0.4), Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.0, 1.05, -0.6)), body.darkened(0.25))
	for x in [-0.18, 0.18]:
		for z in [-0.35, 0.35]:
			parts.box(Vector3(0.1, 0.5, 0.1), Transform3D(Basis(), Vector3(x, 0.25, z)), legs)
	return parts.commit()


## Boote vor Anker und Bojen in den Buchten der Westküste (eigene Knoten, z. B. für Schaukeln).
func _cove_boats(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	node.name = "Boote"
	parent.add_child(node)
	var d := 1000.0
	while d < 2150.0:
		var water := world._water_distance(d, 250.0)
		if water > 0.0:
			var at := world._beside_road(d, -(water + rng.randf_range(15.0, 40.0)))
			if at.y < -1.5:
				at.y = -0.45
				var model: String = ["boat-sail-a", "boat-fishing-small", "boat-sail-b", "boat-row-small"][rng.randi() % 4]
				world._place_model(node, "watercraft/%s.glb" % model, at, rng.randf() * TAU, 2.2)
				world._place_model(node, "watercraft/buoy-flag.glb", at + Vector3(rng.randf_range(-12.0, 12.0), 0.15, rng.randf_range(-12.0, 12.0)), 0.0, 1.4)
				_register("boot", at, 5.0)
		d += rng.randf_range(180.0, 260.0)


## Bushaltestelle rechts vor dem Bergdorf: Wartehäuschen mit Bank und Haltestellenschild.
func _bus_stop(parent: Node3D) -> void:
	var d := world._station_range("bergdorf").x - 18.0
	var at := world._beside_road(d, 8.0)
	var node := Node3D.new()
	node.name = "Bushaltestelle"
	node.position = at
	node.rotation.y = world._yaw_at(d) + PI / 2.0
	parent.add_child(node)
	var parts := Parts.new()
	var frame := Color(0.3, 0.32, 0.34)
	parts.box(Vector3(4.0, 2.4, 0.15), Transform3D(Basis(), Vector3(0.0, 1.2, 0.9)), Color(0.75, 0.82, 0.85))
	parts.box(Vector3(4.4, 0.15, 2.2), Transform3D(Basis(), Vector3(0.0, 2.5, 0.1)), frame)
	for x in [-2.0, 2.0]:
		parts.box(Vector3(0.12, 2.5, 0.12), Transform3D(Basis(), Vector3(x, 1.25, -0.8)), frame)
	parts.box(Vector3(3.0, 0.1, 0.5), Transform3D(Basis(), Vector3(0.0, 0.5, 0.55)), Color(0.5, 0.35, 0.2))
	parts.box(Vector3(0.08, 2.8, 0.08), Transform3D(Basis(), Vector3(-3.0, 1.4, -0.9)), frame)
	parts.cylinder(0.35, 0.35, 0.06, Vector3(-3.0, 2.8, -0.9), Color(0.95, 0.75, 0.1), 12, Basis(Vector3.RIGHT, PI / 2.0))
	_mesh_node(node, "Haeuschen", parts)
	_register("bushaltestelle", at, 3.5)


## Sammelt Grundkörper (Box, Kegelstumpf, Kugel) mit Lage und Farbe zu einem ArrayMesh mit Vertex-Farben.
class Parts:
	var _vertices := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()

	func add(mesh: PrimitiveMesh, transform: Transform3D, color: Color) -> void:
		var arrays := mesh.get_mesh_arrays()
		var offset := _vertices.size()
		var normal_basis := transform.basis.inverse().transposed()
		for v in arrays[Mesh.ARRAY_VERTEX]:
			_vertices.append(transform * v)
			_colors.append(color)
		for n in arrays[Mesh.ARRAY_NORMAL]:
			_normals.append((normal_basis * n).normalized())
		for i in arrays[Mesh.ARRAY_INDEX]:
			_indices.append(offset + i)

	## Box `size` mit Mittelpunkt/Lage `transform`.
	func box(size: Vector3, transform: Transform3D, color: Color) -> void:
		var mesh := BoxMesh.new()
		mesh.size = size
		add(mesh, transform, color)

	## Kegelstumpf (Radius oben/unten, Höhe) mit Mittelpunkt `at`, optional gedreht.
	func cylinder(top: float, bottom: float, height: float, at: Vector3, color: Color, segments: int = 16,
			basis: Basis = Basis()) -> void:
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = segments
		mesh.rings = 1
		add(mesh, Transform3D(basis, at), color)

	func sphere(radius: float, at: Vector3, color: Color, basis: Basis = Basis()) -> void:
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		add(mesh, Transform3D(basis, at), color)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
