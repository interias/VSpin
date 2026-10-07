## Bewegte Szenen der Insel (G3) – von `IslandWorld.build()` als Kind `World/Motion` eingehängt, findet die
## animierbaren Teile der Welt per Pfad und bewegt sie in `_process`:
##   Windmühlen   `Landmarks/windmuehlen/Muehle<n>/Fluegel` drehen um lokal z, je Mühle leicht andere Drehzahl
##   Leuchtturm   `Landmarks/leuchtturm/Lampe` dreht um lokal y, mit additivem Lichtkegel (`Lampe/Kegel`)
##   Boote        Boote und Bojen im Wasser (`Props/hafen/Boat*|Buoy*`, `Details/Boote/*`) schaukeln um ihre Lage
##   Segler       zwei Segelboote (`Motion/Segler<n>`) kreuzen auf Ellipsen vor der Westküste und vor dem Hafen
##   Vögel        Möwenschwärme über Hafen, Leuchtturm und Westküste, Greifvögel über Serpentinen und Burg
##                (`Motion/Voegel/*`, Low-Poly aus Grundkörpern, Flügelschlag über die Flügelknoten)
##   Wolken       Low-Poly-Wolken hoch über der Insel ziehen mit dem Wind (`Motion/Wolken/*`, am Rand umlaufend)
##   Brunnen      Wasserstrahl am Dorfbrunnen (CPUParticles3D, `Motion/Brunnen`)
## Dazu Shader (`src/shaders/`): Vegetation wiegt im Wind (`wind.gdshader`, über `sway()` beim Laden der
## Kenney-Modelle und für die Agaven), das Meer hat Wellen, Glitzern, Flachwasser und Brandung (`sea.gdshader`,
## `sea_material()`). Shader laufen über TIME; alles andere ist eine reine Funktion der Zeit `time_s` (`apply(t)`),
## damit Tests die Bewegung ohne Echtzeit prüfen können.
## Tag/Nacht und Wetter (G6, SkyController) stellen über kleine Setter: `set_clouds` (Bedeckung, Tönung), `set_wind`
## (Wolkenzug, Wiegen der Vegetation, Wellen), `set_sea` (Meeresfarben), `set_beacon` (Leuchtturm nachts),
## `set_birds_visible`, `set_road_wetness` (nasse Fahrbahn).
## Pausen (Verbindungsverlust, Pause-Taste) halten nur die Fahrt an, nicht den Szenenbaum: die Welt lebt als Ambiente
## weiter – sonst wirkte das Spiel bei einem Abbruch eingefroren.
class_name WorldMotion
extends Node3D

const WIND_SHADER := preload("res://src/shaders/wind.gdshader")
const SEA_SHADER := preload("res://src/shaders/sea.gdshader")
const BEAM_SHADER := preload("res://src/shaders/beam.gdshader")
## Kenney-Modelle (Dateiname beginnt so), die im Wind wiegen.
const VEGETATION_PREFIXES := ["tree_", "plant_", "grass_", "flower_"]
## Ausschlag an der Spitze (Anteil der Modellhöhe): Bäume wenig, Büsche und Gras mehr.
const TREE_SWAY := 0.018
const PLANT_SWAY := 0.05
## Drehzahl der Mühlenflügel (rad/s) und der Leuchtturm-Lampe (rad/s, eine Umdrehung in ~7 s).
const MILL_SPEED := Vector2(0.55, 0.8)
const LAMP_SPEED := 0.9
## Schaukeln: Hub (m) und Neigung (rad) höchstens.
const BOB_M := 0.15
const ROCK_RAD := 0.07
## Wolken: Zugrichtung/-tempo (m/s) und umlaufender Bereich (x/z, m) um die Insel.
const CLOUD_WIND := Vector3(3.5, 0.0, 1.2)
const CLOUD_EXTENT_M := 3600.0
## Anzahl der Wolken; davon sichtbar ist der Anteil `cloud_cover` (Wetter, G6).
const CLOUD_COUNT := 36
## Lichtkegel des Leuchtturms: Intensität am Tag (Uniform `intensity`) und nachts.
const BEAM_DAY := 0.18
const BEAM_NIGHT := 0.9
## Höhenkarte für das Meer: jeder SHORE_STEP-te Gitterpunkt des Geländes (10 m je Texel), Höhenbereich (m).
const SHORE_STEP := 2
const SHORE_MIN_M := -20.0
const SHORE_MAX_M := 5.0

var world: IslandWorld
## Animationszeit (s), von `_process` vorgerückt.
var time_s := 0.0
## Je Mühle {node, phase, speed}.
var mills: Array[Dictionary] = []
var lamp: Node3D
## Je Boot/Boje {node, base, phase, scale}.
var boats: Array[Dictionary] = []
## Je Segler {node, centre, axis, radii, speed, phase}.
var sailers: Array[Dictionary] = []
## Je Vogel {node, wings, centre, radius, height, speed, phase, flap_rate, flap_share}.
var birds: Array[Dictionary] = []
## Je Wolke {node, base}.
var clouds: Array[Dictionary] = []
## Wolkenzug (m/s, `set_wind`) und sichtbarer Anteil der Wolken 0..1 (`set_clouds`).
var cloud_wind := CLOUD_WIND
var cloud_cover := 0.5
## Gemeinsames Material der Wolken (Tönung bei Regen, weniger Rim nachts).
var cloud_material: StandardMaterial3D
## Material der Meeresfläche (`World/Sea`).
var sea: ShaderMaterial
## Licht des Leuchtturms (nachts an): Spot entlang des Kegels und Glühen an der Linse.
var beacon_lights: Array[Light3D] = []
## Windfaktor (1 = ruhig wie G3) und Verschiebung der Wolken, damit ein Wechsel des Windes sie nicht springen lässt.
var wind := 1.0
var _cloud_shift := Vector3.ZERO

## Alle Wind-Materialien (Vegetation, Agaven) mit Grundausschlag in Meta `base_strength` – für `set_wind`.
static var _wind_materials: Array[ShaderMaterial] = []

static var _shore_texture: ImageTexture = null


## Sucht die bewegten Teile in `owner` und baut Segler, Vögel, Wolken und Brunnen.
func setup(owner: IslandWorld) -> void:
	world = owner
	name = "Motion"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1509
	for mill in world.get_node("Landmarks/windmuehlen").get_children():
		var blades: Node3D = mill.get_node("Fluegel")
		mills.append({"node": blades, "phase": blades.rotation.z, "speed": rng.randf_range(MILL_SPEED.x, MILL_SPEED.y)})
	lamp = world.get_node("Landmarks/leuchtturm/Lampe")
	_add_beam(lamp)
	for parent in [world.get_node("Props/hafen"), world.get_node("Details/Boote")]:
		for node in parent.get_children():
			if (node.name.begins_with("Boat") or node.name.begins_with("Buoy")) and node.position.y < 0.0:
				boats.append({"node": node, "base": node.transform, "phase": rng.randf() * TAU,
						"scale": 1.6 if node.name.begins_with("Buoy") else 1.0})
	_add_sailer("Segler1", "boat-sail-a", Vector3(-1030.0, -0.45, 480.0), Vector3(0.12, 0.0, 1.0), Vector2(60.0, 380.0), rng)
	_add_sailer("Segler2", "boat-sail-b", Vector3(230.0, -0.45, 1650.0), Vector3(1.0, 0.0, 0.0), Vector2(230.0, 70.0), rng)
	var flock := Node3D.new()
	flock.name = "Voegel"
	add_child(flock)
	var lighthouse := world.get_node("Landmarks/leuchtturm") as Node3D
	_add_flock(flock, "Moewe", Vector3(300.0, 24.0, 1400.0), 7, Vector2(25.0, 55.0), false, rng)
	_add_flock(flock, "MoeweLeuchtturm", lighthouse.position + Vector3(0.0, 62.0, 0.0), 6, Vector2(18.0, 40.0), false, rng)
	_add_flock(flock, "MoeweKueste", Vector3(-800.0, 48.0, 860.0), 6, Vector2(25.0, 50.0), false, rng)
	_add_flock(flock, "Greif", Vector3(-480.0, 240.0, -400.0), 1, Vector2(80.0, 80.0), true, rng)
	_add_flock(flock, "GreifBurg", world.get_node("Landmarks/burg").position + Vector3(0.0, 70.0, 0.0), 1, Vector2(55.0, 55.0), true, rng)
	_add_clouds(rng)
	_add_fountain()
	sea = world.get_node("Sea").material_override as ShaderMaterial
	for key in ["Agaven", "AgavenBluete"]:
		var plants := world.get_node_or_null("Details/" + key) as GeometryInstance3D
		if plants != null:
			plants.material_override = _wind_material(Color.WHITE, 0.9, 1.6 if key == "Agaven" else 4.5, 0.03, true)
	apply(0.0)


func _process(delta: float) -> void:
	advance(delta)


## Animationszeit um `seconds` vorrücken und anwenden.
func advance(seconds: float) -> void:
	time_s += seconds
	apply(time_s)


## Stellt alle bewegten Teile auf den Zeitpunkt `t` (s).
func apply(t: float) -> void:
	time_s = t
	for mill in mills:
		mill["node"].rotation.z = mill["phase"] - mill["speed"] * t
	lamp.rotation.y = LAMP_SPEED * t
	for boat in boats:
		var phase: float = boat["phase"]
		var s: float = boat["scale"]
		var tilt := Basis.from_euler(Vector3(ROCK_RAD * 0.5 * s * sin(0.7 * t + phase * 1.3), 0.0,
				ROCK_RAD * minf(s, 1.0) * sin(0.9 * t + phase) * (0.6 + 0.4 * sin(0.23 * t + phase))))
		var base: Transform3D = boat["base"]
		boat["node"].transform = Transform3D(base.basis * tilt, base.origin + Vector3(0.0, BOB_M * sin(1.1 * t + phase * 0.7), 0.0))
	for sailer in sailers:
		_place_sailer(sailer, t)
	for bird in birds:
		_place_bird(bird, t)
	for cloud in clouds:
		var at: Vector3 = cloud["base"] + cloud_wind * t + _cloud_shift
		at.x = wrapf(at.x, -CLOUD_EXTENT_M, CLOUD_EXTENT_M)
		at.z = wrapf(at.z, -CLOUD_EXTENT_M, CLOUD_EXTENT_M)
		cloud["node"].position = at


## Material mit Wind-Shader (siehe `wind.gdshader`).
static func _wind_material(color: Color, roughness: float, height: float, strength: float, vertex_color: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WIND_SHADER
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("height", height)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("use_vertex_color", vertex_color)
	material.set_meta("base_strength", strength)
	_wind_materials.append(material)
	return material


## Vegetation aus `path` (Kenney-Modell) wiegt im Wind: ersetzt die Materialien von `mesh` durch den Wind-Shader
## (Farbe und Rauheit übernommen). Andere Modelle bleiben unverändert. Aufgerufen von `IslandWorld._model_mesh`.
static func sway(mesh: Mesh, path: String) -> void:
	var file := path.get_file()
	var plant := false
	for prefix in VEGETATION_PREFIXES:
		plant = plant or file.begins_with(prefix)
	if not plant:
		return
	var height := maxf(mesh.get_aabb().end.y, 0.1)
	var strength := TREE_SWAY if file.begins_with("tree_") else PLANT_SWAY
	for s in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(s) as BaseMaterial3D
		if material != null:
			mesh.surface_set_material(s, _wind_material(material.albedo_color, material.roughness, height, strength))


## Meeresmaterial (siehe `sea.gdshader`) mit der Höhenkarte von `terrain` für Flachwasser und Brandung.
static func sea_material(terrain: IslandTerrain) -> ShaderMaterial:
	if _shore_texture == null:
		var columns := (terrain.columns - 1) / SHORE_STEP + 1
		var rows := (terrain.rows - 1) / SHORE_STEP + 1
		var data := PackedByteArray()
		data.resize(columns * rows)
		for row in range(rows):
			for col in range(columns):
				var h := terrain.heights[row * SHORE_STEP * terrain.columns + col * SHORE_STEP]
				data[row * columns + col] = int(round(clampf(inverse_lerp(SHORE_MIN_M, SHORE_MAX_M, h), 0.0, 1.0) * 255.0))
		_shore_texture = ImageTexture.create_from_image(Image.create_from_data(columns, rows, false, Image.FORMAT_L8, data))
	var material := ShaderMaterial.new()
	material.shader = SEA_SHADER
	material.set_shader_parameter("shore", _shore_texture)
	material.set_shader_parameter("shore_origin", IslandTerrain.ORIGIN)
	material.set_shader_parameter("shore_size", IslandTerrain.SIZE)
	material.set_shader_parameter("shore_min_m", SHORE_MIN_M)
	material.set_shader_parameter("shore_max_m", SHORE_MAX_M)
	return material


## Lichtkegel an der Linse (lokal +x) der Lampe.
func _add_beam(parent: Node3D) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.6
	cone.bottom_radius = 3.5
	cone.height = 45.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var material := ShaderMaterial.new()
	material.shader = BEAM_SHADER
	var beam := MeshInstance3D.new()
	beam.name = "Kegel"
	beam.mesh = cone
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Achse lokal y → +x, oberes (schmales) Ende an der Linse
	beam.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(1.6 + cone.height / 2.0, 0.0, 0.0))
	parent.add_child(beam)
	# Nachts (G6): Spot entlang des Kegels (−z → +x) und Glühen an der Linse; tagsüber aus.
	var spot := SpotLight3D.new()
	spot.name = "Licht"
	spot.light_color = Color(1.0, 0.9, 0.65)
	spot.light_energy = 12.0
	spot.spot_range = 320.0
	spot.spot_angle = 5.0
	spot.spot_attenuation = 0.6
	spot.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(1.6, 0.0, 0.0))
	var glow := OmniLight3D.new()
	glow.name = "Gluehen"
	glow.light_color = Color(1.0, 0.85, 0.55)
	glow.light_energy = 3.0
	glow.omni_range = 18.0
	for light in [spot, glow]:
		light.visible = false
		light.shadow_enabled = false
		parent.add_child(light)
		beacon_lights.append(light)


## Segelboot auf einer Ellipse um `centre` (Halbachsen `radii` entlang `axis` und quer dazu).
func _add_sailer(node_name: String, model: String, centre: Vector3, axis: Vector3, radii: Vector2, rng: RandomNumberGenerator) -> void:
	var boat: Node3D = load(IslandWorld.MODEL_DIR + "watercraft/%s.glb" % model).instantiate()
	boat.name = node_name
	add_child(boat)
	sailers.append({"node": boat, "centre": centre, "axis": axis.normalized(), "radii": radii, "speed": 3.5,
			"phase": rng.randf() * TAU})


## Punkt der Ellipse eines Seglers beim Winkel `angle` (rad).
func sailer_point(sailer: Dictionary, angle: float) -> Vector3:
	var axis: Vector3 = sailer["axis"]
	var across := Vector3(-axis.z, 0.0, axis.x)
	var radii: Vector2 = sailer["radii"]
	return sailer["centre"] + across * cos(angle) * radii.x + axis * sin(angle) * radii.y


## Lage eines Seglers zur Zeit `t`: auf der Ellipse, Bug in Fahrtrichtung, leichte Krängung und Schaukeln.
func _place_sailer(sailer: Dictionary, t: float) -> void:
	var radii: Vector2 = sailer["radii"]
	var angle: float = sailer["phase"] + sailer["speed"] * t / ((radii.x + radii.y) / 2.0)
	var at := sailer_point(sailer, angle)
	var ahead := sailer_point(sailer, angle + 0.01) - at
	var yaw := atan2(ahead.x, ahead.z)  # Bug der Kenney-Boote: lokal +z
	var heel := 0.1 + 0.03 * sin(0.8 * t + sailer["phase"])
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, heel) * Basis(Vector3.RIGHT, 0.03 * sin(1.2 * t))
	sailer["node"].transform = Transform3D(basis.scaled(Vector3.ONE * 2.6), at + Vector3(0.0, 0.1 * sin(1.1 * t), 0.0))


## `count` Vögel kreisen um `centre` (Radien zwischen `radii`); Greifvögel größer, dunkel, meist im Gleitflug.
func _add_flock(parent: Node3D, prefix: String, centre: Vector3, count: int, radii: Vector2, raptor: bool, rng: RandomNumberGenerator) -> void:
	var meshes := _bird_meshes(raptor)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.9
	for k in range(count):
		var bird := Node3D.new()
		bird.name = "%s%d" % [prefix, k + 1]
		bird.scale = Vector3.ONE * (3.2 if raptor else 1.7)
		parent.add_child(bird)
		var wings: Array[MeshInstance3D] = []
		for m in range(3):
			var part := MeshInstance3D.new()
			part.name = ["Rumpf", "FluegelR", "FluegelL"][m]
			part.mesh = meshes[m]
			part.material_override = material
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bird.add_child(part)
			if m > 0:
				wings.append(part)
		var speed := rng.randf_range(7.0, 10.0) * (0.8 if raptor else 1.0)
		birds.append({"node": bird, "wings": wings, "centre": centre, "radius": rng.randf_range(radii.x, radii.y),
				"height": rng.randf_range(-6.0, 6.0), "speed": speed * (1.0 if k % 3 else -1.0),
				"phase": rng.randf() * TAU, "flap_rate": (4.5 if raptor else 7.0) * rng.randf_range(0.9, 1.1),
				"flap_share": 0.25 if raptor else 0.6})


## Lage und Flügelschlag eines Vogels zur Zeit `t`: Kreisbahn mit leichtem Auf und Ab, in die Kurve geneigt;
## Flügelschlag in Phasen, dazwischen Gleitflug mit leicht angehobenen Flügeln.
func _place_bird(bird: Dictionary, t: float) -> void:
	var r: float = bird["radius"]
	var speed: float = bird["speed"]
	var phase: float = bird["phase"]
	var angle := phase + speed / r * t
	var at: Vector3 = bird["centre"] + Vector3(cos(angle) * r, bird["height"] + 3.0 * sin(0.4 * t + phase), sin(angle) * r)
	var heading := Vector3(-sin(angle), 0.0, cos(angle)) * signf(speed)
	var bank := -0.35 * signf(speed)
	var node: Node3D = bird["node"]
	node.transform = Transform3D(Basis.looking_at(heading, Vector3.UP) * Basis(Vector3.BACK, bank), at).scaled_local(node.scale)
	var gate := clampf((sin(0.5 * t + phase) + (bird["flap_share"] * 2.0 - 1.0)) * 3.0, 0.0, 1.0)
	var flap: float = 0.15 + gate * 0.55 * sin(bird["flap_rate"] * t + phase)
	bird["wings"][0].rotation.z = flap
	bird["wings"][1].rotation.z = -flap


## [Rumpf, Flügel rechts, Flügel links] eines Vogels (Blick lokal −z, 1 Einheit ≈ 1 m, Flügel ab der Rumpfseite).
static func _bird_meshes(raptor: bool) -> Array:
	var body := IslandLandmarks.Parts.new()
	var plumage := Color(0.42, 0.3, 0.2) if raptor else Color(0.96, 0.96, 0.94)
	var back := Color(0.32, 0.22, 0.15) if raptor else Color(0.62, 0.65, 0.68)
	var tip := Color(0.2, 0.14, 0.1) if raptor else Color(0.12, 0.12, 0.13)
	body.sphere(1.0, Vector3.ZERO, plumage, Basis().scaled(Vector3(0.11, 0.1, 0.3)))
	body.sphere(0.075, Vector3(0.0, 0.03, -0.3), plumage)
	body.cylinder(0.0, 0.03, 0.09, Vector3(0.0, 0.02, -0.4), Color(0.95, 0.75, 0.2) if not raptor else Color(0.3, 0.3, 0.3), 4,
			Basis(Vector3.RIGHT, -PI / 2.0))
	body.box(Vector3(0.16, 0.02, 0.16), Transform3D(Basis(), Vector3(0.0, 0.0, 0.32)), back)
	var wings := []
	for side in [1.0, -1.0]:
		var wing := IslandLandmarks.Parts.new()
		wing.box(Vector3(0.45, 0.025, 0.24), Transform3D(Basis(), Vector3(side * 0.27, 0.0, 0.0)), back)
		wing.box(Vector3(0.35, 0.022, 0.17), Transform3D(Basis(Vector3.UP, side * 0.25), Vector3(side * 0.63, 0.0, 0.03)), back)
		wing.box(Vector3(0.14, 0.02, 0.12), Transform3D(Basis(Vector3.UP, side * 0.35), Vector3(side * 0.85, 0.0, 0.07)), tip)
		wings.append(wing.commit())
	return [body.commit(), wings[0], wings[1]]


## Low-Poly-Wolken (abgeflachte Kugelhaufen) 380–560 m hoch über und um die Insel.
func _add_clouds(rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	node.name = "Wolken"
	add_child(node)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.rim_enabled = true
	material.rim = 0.4
	cloud_material = material
	for k in range(CLOUD_COUNT):
		var parts := IslandLandmarks.Parts.new()
		var size := rng.randf_range(50.0, 120.0)
		for b in range(rng.randi_range(4, 7)):
			var r := size * rng.randf_range(0.35, 0.6)
			var at := Vector3(rng.randf_range(-1.0, 1.0) * size, rng.randf_range(0.0, 0.25) * r, rng.randf_range(-0.5, 0.5) * size)
			parts.sphere(1.0, at, Color(1.0, 1.0, 1.0), Basis().scaled(Vector3(r, r * 0.55, r * 0.8)))
		parts.sphere(1.0, Vector3(0.0, -size * 0.08, 0.0), Color(0.9, 0.92, 0.95), Basis().scaled(Vector3(size * 1.1, size * 0.18, size * 0.5)))
		var cloud := MeshInstance3D.new()
		cloud.name = "Wolke%d" % (k + 1)
		cloud.mesh = parts.commit()
		cloud.material_override = material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.rotation.y = rng.randf() * TAU
		node.add_child(cloud)
		var base := Vector3(rng.randf_range(-CLOUD_EXTENT_M, CLOUD_EXTENT_M), rng.randf_range(380.0, 560.0),
				rng.randf_range(-CLOUD_EXTENT_M, CLOUD_EXTENT_M))
		clouds.append({"node": cloud, "base": base})
	set_clouds(cloud_cover)


## Wasserstrahl aus der Brunnenmitte im Bergdorf (CPU-Partikel: auch im Web-Export).
func _add_fountain() -> void:
	var fountain: Node3D = null
	for node in world.get_node("Props/bergdorf").get_children():
		if node.name.begins_with("Fountain"):
			fountain = node
	if fountain == null:
		return
	var top := -INF
	for mesh in fountain.find_children("*", "MeshInstance3D", true, false):
		var placement: Transform3D = mesh.transform
		var node: Node = mesh.get_parent()
		while node != fountain.get_parent():
			placement = (node as Node3D).transform * placement
			node = node.get_parent()
		top = maxf(top, (placement * mesh.get_aabb()).end.y)
	var drop := SphereMesh.new()
	drop.radius = 0.06
	drop.height = 0.12
	drop.radial_segments = 4
	drop.rings = 2
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.75, 0.88, 1.0, 0.8)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.1
	drop.material = water
	var jet := CPUParticles3D.new()
	jet.name = "Brunnen"
	jet.mesh = drop
	jet.amount = 90
	jet.lifetime = 1.1
	jet.direction = Vector3.UP
	jet.spread = 14.0
	jet.initial_velocity_min = 3.2
	jet.initial_velocity_max = 3.8
	jet.gravity = Vector3(0.0, -9.8, 0.0)
	jet.scale_amount_min = 0.7
	jet.scale_amount_max = 1.2
	jet.position = Vector3(fountain.position.x, top, fountain.position.z)
	add_child(jet)


## Bedeckung `cover` 0..1: so viele Wolken wie der Anteil sichtbar, die Grenzwolke wächst/schrumpft (weicher
## Übergang), bei dichter Bedeckung sind alle Wolken größer; `tint` färbt alle Wolken (grau bei Regen, dunkel nachts), `rim` hellt die Ränder auf.
func set_clouds(cover: float, tint: Color = Color.WHITE, rim: float = 0.4) -> void:
	cloud_cover = clampf(cover, 0.0, 1.0)
	var shown := cloud_cover * clouds.size()
	for k in range(clouds.size()):
		var size := clampf(shown - k, 0.0, 1.0)
		var node: Node3D = clouds[k]["node"]
		node.visible = size > 0.01
		node.scale = Vector3.ONE * maxf(size, 0.01) * lerpf(1.0, 1.8, cloud_cover * cloud_cover)
	cloud_material.albedo_color = tint
	cloud_material.rim = rim


## Windfaktor (1 = ruhig): Wolkenzug, Wiegen der Vegetation und Wellenhöhe. Die Wolken ziehen ohne Sprung weiter.
func set_wind(factor: float) -> void:
	var next := CLOUD_WIND * factor
	_cloud_shift += (cloud_wind - next) * time_s
	cloud_wind = next
	wind = factor
	for material in _wind_materials:
		if is_instance_valid(material):
			material.set_shader_parameter("strength", material.get_meta("base_strength", 0.02) * lerpf(1.0, factor, 0.6))
	if sea != null:
		sea.set_shader_parameter("wave_scale", lerpf(1.0, factor, 0.5))


## Meeresfarben (siehe `sea.gdshader`: tief, flach, Schaum).
func set_sea(deep: Color, shallow: Color, foam: Color) -> void:
	if sea == null:
		return
	sea.set_shader_parameter("deep_color", deep)
	sea.set_shader_parameter("shallow_color", shallow)
	sea.set_shader_parameter("foam_color", foam)


## Leuchtturm: `level` 0 = Tag (schwacher Kegel, kein Licht) … 1 = Nacht (heller Kegel, Spot und Glühen an).
func set_beacon(level: float) -> void:
	var beam := lamp.get_node("Kegel") as MeshInstance3D
	(beam.material_override as ShaderMaterial).set_shader_parameter("intensity", lerpf(BEAM_DAY, BEAM_NIGHT, level))
	for light in beacon_lights:
		light.visible = level > 0.05


## Vögel ein-/ausblenden (nachts und bei Regen fliegen keine).
func set_birds_visible(shown: bool) -> void:
	get_node("Voegel").visible = shown


## Nasse Fahrbahn 0..1: dunkler und glänzender (auf eine Tönung des Lichtprofils in Meta `profile_tint`).
func set_road_wetness(wet: float) -> void:
	var road := world.get_node_or_null("Road") as MeshInstance3D
	if road == null:
		return
	var material := road.material_override as StandardMaterial3D
	material.albedo_color = material.get_meta("profile_tint", Color.WHITE) * Color.WHITE.lerp(Color(0.62, 0.62, 0.66), wet)
	material.roughness = lerpf(0.95, 0.3, wet)
	material.metallic_specular = lerpf(0.5, 0.8, wet)
