## Dichte Vegetation entlang der Strecke und Bodentexturen (#38) – von `IslandWorld.build()` nach den Landmarken gebaut.
##
## Vegetation unter `World/Vegetation/<Station>/<Art><Stück>`: auf jeder Station Grasbüschel, Unterholz (niedrige
## Polster) und Sträucher (Macchia) beidseits der Straße, nahe am Bankett am dichtesten. Die Pflanzen sind Low-Poly
## aus Grundformen (Halme als dreiseitige Prismen, Polster und Sträucher aus Ikosaedern), keine Modelldateien. Je Art
## und je `CHUNK_M` Strecke ein MultiMesh mit Sichtweite (`RANGE_M`), damit nur die Pflanzen nahe der Kamera
## gezeichnet werden; alle wiegen im Wind (`wind.gdshader`, wie die Kenney-Vegetation). Ausgespart: die Fahrbahn
## (Abstand zur Straßenmitte − Radius ≥ `ROAD_CLEARANCE_M`), Strand und Meer, Steilhänge, der Kai, Häuser, Kirchplatz,
## Fincas, der Aussichtspunkt und die Landmarken.
## Browser (Compatibility-Renderer, `IslandWorld.compatibility`): abgespeckt – Gras und Unterholz zur Hälfte
## (`LITE_SHARE`), kürzere Sichtweite (`LITE_RANGE`).
##
## Bodentexturen: Gelände und Fahrbahn behalten ihr Vertex-Farben-Material (Tönung des Lichtprofils, nasse Straße)
## und bekommen eine Detailtextur (multipliziert, weltfest triplanar): der Boden Erde und Gras als Farbflecken mit
## Körnung, die Straße Asphaltkorn mit ausgebesserten Flecken. Die Texturen entstehen prozedural (FastNoiseLite).
##
## Jahreszeiten (#39): alle Farben kommen aus `PALETTE`. `set_palette()` färbt die geteilten Materialien der
## Vegetation (Shader-Parameter `albedo`) und die Bodentextur zentral um, ohne die Welt neu zu bauen.
##
## `placements[station][art]` hält die Lage jeder Pflanze (PackedVector3Array) für Tests – headless liefern MultiMeshes
## keine Transforms. Eigene Zufallsgeneratoren je Station (Seeds 1511–1516); die übrige Welt bleibt unverändert.
## Bewusste Ausnahme von der `_`-Konvention wie bei IslandLandmarks: nutzt die Bauhelfer von `IslandWorld` direkt.
class_name IslandVegetation
extends RefCounted

## Pflanzenarten (Knotennamen-Präfix).
const KINDS := ["Gras", "Unterholz", "Strauch"]
## Versuche je 100 m Strecke und Art (vor dem Aussparen).
const ATTEMPTS_PER_100M := {"Gras": 520, "Unterholz": 80, "Strauch": 24}
## Seitlicher Bereich (m von der Straßenmitte) und Verteilung: Abstand = von + (bis − von) · Zufall^exponent –
## nahe am Bankett dichter.
const SPREAD_M := {"Gras": Vector3(4.4, 28.0, 2.4), "Unterholz": Vector3(4.8, 34.0, 1.5), "Strauch": Vector3(6.0, 45.0, 1.3)}
## Radius einer Pflanze (m) bei Größe 1; für den Fahrbahnabstand zählt die größte Größe (SCALE).
const RADIUS_M := {"Gras": 0.35, "Unterholz": 0.6, "Strauch": 1.3}
## Größenfaktor je Instanz (von, bis).
const SCALE := {"Gras": Vector2(0.8, 1.5), "Unterholz": Vector2(0.7, 1.3), "Strauch": Vector2(0.8, 1.7)}
## Steilster Hang (Höhe je Meter), auf dem die Art noch wächst.
const MAX_SLOPE := {"Gras": 1.0, "Unterholz": 1.0, "Strauch": 1.3}
## Sichtweite (m) je Art; dahinter wird das Stück nicht gezeichnet.
const RANGE_M := {"Gras": 150.0, "Unterholz": 220.0, "Strauch": 400.0}
## Ausschlag im Wind (Anteil der Höhe, siehe wind.gdshader).
const SWAY := {"Gras": 0.12, "Unterholz": 0.05, "Strauch": 0.04}
## Mindestabstand (m) zur Straßenmitte abzüglich Radius: Fahrbahnhälfte 3,0 m, Mauer bis 4,05 m.
const ROAD_CLEARANCE_M := 4.1
## Streckenlänge (m) je MultiMesh-Stück.
const CHUNK_M := 50.0
## Browser: Anteil von Gras und Unterholz und Faktor der Sichtweite.
const LITE_SHARE := 0.5
const LITE_RANGE := 0.7
## Unter dieser Geländehöhe (m) Strand oder Meer – dort wächst nichts.
const MIN_HEIGHT_M := 1.0
## Rastergröße (m) für Straßenpunkte und Sperrflächen.
const BUCKET_M := 10.0
## Farben (Einhängepunkt für Jahreszeiten #39, siehe `set_palette()`): Grundfarbe je Pflanzenart (mit Helligkeit der
## Vertex-Farben und Streuung je Instanz multipliziert) und Bodentextur (Faktoren auf die Geländefarben: Erde und Gras
## als Flecken, dazu die Körnung).
const PALETTE := {
	"Gras": Color(0.56, 0.6, 0.3),
	"Unterholz": Color(0.42, 0.47, 0.25),
	"Strauch": Color(0.3, 0.42, 0.21),
	"Boden_Erde": Color(1.0, 0.96, 0.91),
	"Boden_Gras": Color(0.93, 0.98, 0.87),
}
## Kachelgröße (m) der Detailtexturen und Pixel je Kante.
const GROUND_TILE_M := 20.0
const ROAD_TILE_M := 8.0
const TEXTURE_SIZE := 256

## Lagen je Station und Art: placements[station_id][art] = PackedVector3Array (Weltposition des Fußpunkts).
var placements := {}
var world: IslandWorld

## Aktuelle Farben (`set_palette`), geteilte Materialien und Meshes je Art, Detailtexturen.
static var palette := PALETTE.duplicate()
static var _materials := {}
static var _meshes := {}
static var _ground_texture: ImageTexture = null
## Aktuelles Bild der Bodentextur (headless liefert die Textur selbst nach einer Änderung noch das alte Bild).
static var ground_image: Image = null
static var _road_texture: ImageTexture = null
## Fertige Instanzlisten je Profil ("forward"/"lite"): {station: {art: [Transform3D, Farbe, Streckenposition] …}}
## und die Lagen dazu – einmal pro Prozess berechnet (die Welt ist deterministisch).
static var _cache := {}

## Straßenpunkte (x, z) alle 1 m und Sperrkreise (x, z, Radius) in Eimern zu BUCKET_M.
var _road := {}
var _blocked := {}


func _init(owner: IslandWorld) -> void:
	world = owner


func build() -> void:
	var root := Node3D.new()
	root.name = "Vegetation"
	world.add_child(root)
	var profile := "lite" if world.compatibility else "forward"
	if not _cache.has(profile):
		_cache[profile] = _plan(world.compatibility)
	var plan: Dictionary = _cache[profile]
	placements = plan["placements"]
	for station in plan["instances"]:
		var node := Node3D.new()
		node.name = station
		root.add_child(node)
		for kind in KINDS:
			var chunks := {}
			for entry in plan["instances"][station][kind]:
				var chunk := int(floorf(entry[2] / CHUNK_M))
				if not chunks.has(chunk):
					chunks[chunk] = []
				chunks[chunk].append(entry)
			for chunk in chunks:
				_chunk(node, "%s%d" % [kind, chunk], kind, chunks[chunk])


## MultiMesh eines Stücks: Instanzen mit Farbe, ohne Schatten, mit Sichtweite.
func _chunk(parent: Node3D, node_name: String, kind: String, entries: Array) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh(kind)
	multimesh.instance_count = entries.size()
	for k in range(entries.size()):
		multimesh.set_instance_transform(k, entries[k][0])
		multimesh.set_instance_color(k, entries[k][1])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = RANGE_M[kind] * (LITE_RANGE if world.compatibility else 1.0)
	parent.add_child(instance)


## Instanzen und Lagen aller Stationen (Browser: Gras und Unterholz ausgedünnt).
func _plan(lite: bool) -> Dictionary:
	_index_road()
	_index_blocked()
	var instances := {}
	var all_placements := {}
	var stations: Array = world.track.stations
	for i in range(stations.size()):
		var id: String = stations[i]["id"]
		var range_m := world._station_range(id)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1511 + i
		instances[id] = {}
		all_placements[id] = {}
		for kind in KINDS:
			var entries := _scatter_kind(id, kind, range_m, rng)
			if lite and kind != "Strauch":
				var kept := []
				for k in range(entries.size()):
					if k % int(round(1.0 / LITE_SHARE)) == 0:
						kept.append(entries[k])
				entries = kept
			var at := PackedVector3Array()
			for entry in entries:
				at.append(entry[3])
			instances[id][kind] = entries
			all_placements[id][kind] = at
	return {"instances": instances, "placements": all_placements}


## Pflanzen einer Art auf dem Abschnitt `range_m`: [Transform3D, Farbe, Streckenposition, Fußpunkt] je Instanz.
func _scatter_kind(station: String, kind: String, range_m: Vector2, rng: RandomNumberGenerator) -> Array:
	var entries := []
	var spread: Vector3 = SPREAD_M[kind]
	var radius: float = RADIUS_M[kind]
	var scale: Vector2 = SCALE[kind]
	var step := 2.0
	var per_step: float = ATTEMPTS_PER_100M[kind] * step / 100.0
	var carry := 0.0
	var d := range_m.x + step / 2.0
	while d < range_m.y:
		var p := world.track.position_at(d)
		var ahead := world.track.position_at(d + 1.0)
		var behind := world.track.position_at(d - 1.0)
		var dir := Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()
		var right := Vector3(-dir.z, 0.0, dir.x)
		carry += per_step
		while carry >= 1.0:
			carry -= 1.0
			var side := (1.0 if rng.randf() < 0.5 else -1.0) * (spread.x + (spread.y - spread.x) * pow(rng.randf(), spread.z))
			var along := rng.randf_range(-step / 2.0, step / 2.0)
			var at := p + dir * along + right * side
			at.y = world.terrain.height_at(at.x, at.z)
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(scale.x, scale.y)
			var shade := rng.randf_range(0.8, 1.08)
			var tint := Color(shade * rng.randf_range(0.95, 1.06), shade, shade * rng.randf_range(0.88, 1.0))
			if not _allowed(station, d + along, side, at, radius * scale.y, MAX_SLOPE[kind]):
				continue
			var sink := 0.05 if kind == "Gras" else 0.15 * s
			entries.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), at - Vector3(0.0, sink, 0.0)),
					tint, d + along, at])
		d += step
	return entries


## Darf an `at` (Streckenposition `d`, seitlich `side` m, rechts positiv) eine Pflanze mit Radius `radius` wachsen?
func _allowed(station: String, d: float, side: float, at: Vector3, radius: float, max_slope: float) -> bool:
	if at.y < MIN_HEIGHT_M:
		return false
	if road_clearance(at) - radius < ROAD_CLEARANCE_M:
		return false
	if _is_blocked(at, radius):
		return false
	var slope := Vector2(world.terrain.height_at(at.x + 1.0, at.z) - world.terrain.height_at(at.x - 1.0, at.z),
			world.terrain.height_at(at.x, at.z + 1.0) - world.terrain.height_at(at.x, at.z - 1.0)).length() / 2.0
	if slope > max_slope:
		return false
	var length := world.track.length_m()
	match station:
		"hafen":
			# Kai seeseitig (links) vom Start/Ziel bis hinter die Häuserzeile, Häuser rechts
			if side < 0.0 and d < 180.0:
				return false
			if side > 0.0 and d < 350.0 and side > 11.0 and side < 32.0:
				return false
		"abfahrt":
			if side < 0.0 and d > length - 70.0:  # Kai vor dem Ziel
				return false
		"bergdorf":
			# Häuserzeilen beidseits, rechts der Platz mit Kirche
			if absf(side) > 6.6 and absf(side) < 18.0:
				return false
			var range_m := world._station_range("bergdorf")
			if side > 6.6 and absf(d - (range_m.x + range_m.y) / 2.0) < 34.0 and side < 50.0:
				return false
	return true


## Horizontaler Abstand von `at` zur Straßenmitte (m); INF weiter als BUCKET_M.
func road_clearance(at: Vector3) -> float:
	var best := INF
	var key := Vector2i(floori(at.x / BUCKET_M), floori(at.z / BUCKET_M))
	var q := Vector2(at.x, at.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for r in _road.get(key + Vector2i(dx, dz), PackedVector2Array()):
				best = minf(best, q.distance_to(r))
	return best


func _index_road() -> void:
	_road.clear()
	var length := world.track.length_m()
	var d := 0.0
	while d < length:
		var p := world.track.position_at(d)
		var key := Vector2i(floori(p.x / BUCKET_M), floori(p.z / BUCKET_M))
		if not _road.has(key):
			_road[key] = PackedVector2Array()
		_road[key].append(Vector2(p.x, p.z))
		d += 1.0


## Sperrkreise: Landmarken (ab 2 m Radius; Pflanzen, Tiere, Kilometersteine dürfen im Gras stehen), Fincas an der
## Abfahrt, Plattform des Aussichtspunkts.
func _index_blocked() -> void:
	_blocked.clear()
	for entry in world.landmarks.placements:
		if entry["radius_m"] >= 2.0:
			_block(entry["at"], entry["radius_m"])
	var descent := world._station_range("abfahrt")
	for offset in [350.0, 900.0, 1500.0, 2050.0, 2600.0]:
		var finca_m: float = descent.x + offset
		_block(world._beside_road(finca_m, -world._valley_side(finca_m) * 27.0), 15.0)
	var view: float = IslandCourse.landmarks()[0]["distance_m"]
	_block(world._beside_road(view, -10.0), 11.0)


func _block(at: Vector3, radius: float) -> void:
	var circle := Vector3(at.x, at.z, radius)
	for x in range(floori((at.x - radius) / BUCKET_M), floori((at.x + radius) / BUCKET_M) + 1):
		for z in range(floori((at.z - radius) / BUCKET_M), floori((at.z + radius) / BUCKET_M) + 1):
			var key := Vector2i(x, z)
			if not _blocked.has(key):
				_blocked[key] = []
			_blocked[key].append(circle)


func _is_blocked(at: Vector3, radius: float) -> bool:
	for circle in _blocked.get(Vector2i(floori(at.x / BUCKET_M), floori(at.z / BUCKET_M)), []):
		if Vector2(at.x, at.z).distance_to(Vector2(circle.x, circle.y)) < circle.z + radius:
			return true
	return false


## Geteiltes Mesh einer Art mit Wind-Material (Farbe aus `palette`).
static func mesh(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1517 + KINDS.find(kind)
		var parts := Facets.new()
		match kind:
			"Gras":
				for k in range(12):
					parts.blade(rng, 0.2, rng.randf_range(0.35, 0.75))
			"Unterholz":
				for k in range(3):
					var angle := TAU * k / 3.0 + rng.randf_range(-0.4, 0.4)
					var r := rng.randf_range(0.18, 0.3)
					var size := rng.randf_range(0.26, 0.4)
					parts.lump(rng, Vector3(cos(angle) * r, size * 0.45, sin(angle) * r), Vector3(size, size * 0.7, size))
				for k in range(4):
					parts.blade(rng, 0.38, rng.randf_range(0.25, 0.45))
			"Strauch":
				parts.lump(rng, Vector3(0.0, 0.7, 0.0), Vector3(0.7, 0.62, 0.7))
				for k in range(5):
					var angle := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
					var r := rng.randf_range(0.35, 0.55)
					var size := rng.randf_range(0.38, 0.55)
					parts.lump(rng, Vector3(cos(angle) * r, size * 0.8 + rng.randf_range(0.0, 0.35), sin(angle) * r),
							Vector3(size, size * 0.85, size))
		var built := parts.commit()
		var height := maxf(built.get_aabb().end.y, 0.1)
		var material := WorldMotion._wind_material(palette[kind], 0.95, height, SWAY[kind], true)
		built.surface_set_material(0, material)
		_materials[kind] = material
		_meshes[kind] = built
	return _meshes[kind]


## Detailtexturen auf Gelände- und Fahrbahnmaterial (Vertex-Farben × Textur, weltfest von oben projiziert).
static func texture_ground(terrain_material: StandardMaterial3D, road_material: StandardMaterial3D) -> void:
	if _ground_texture == null:
		ground_image = _ground_image()
		_ground_texture = ImageTexture.create_from_image(ground_image)
		_road_texture = ImageTexture.create_from_image(_road_image())
	_detail(terrain_material, _ground_texture, GROUND_TILE_M)
	_detail(road_material, _road_texture, ROAD_TILE_M)


static func _detail(material: StandardMaterial3D, texture: Texture2D, tile_m: float) -> void:
	material.detail_enabled = true
	material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	material.detail_albedo = texture
	material.uv2_triplanar = true
	material.uv2_world_triplanar = true
	material.uv2_scale = Vector3.ONE / tile_m


## Jahreszeiten (#39): Farben der Vegetation und der Bodentextur ändern (Schlüssel wie PALETTE; fehlende bleiben).
## Wirkt sofort auf alle gebauten Welten (geteilte Materialien und Textur).
static func set_palette(colors: Dictionary) -> void:
	for key in colors:
		palette[key] = colors[key]
	for kind in _materials:
		(_materials[kind] as ShaderMaterial).set_shader_parameter("albedo", palette[kind])
	if _ground_texture != null:
		ground_image = _ground_image()
		_ground_texture.update(ground_image)


## Boden: Flecken aus Erde und Gras (palette), darüber feine Körnung; Werte ≤ 1 (multipliziert die Geländefarbe).
static func _ground_image() -> Image:
	var patches := _noise(1521, 0.012, 3).get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	var grain := _noise(1522, 0.09, 2).get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	var earth: Color = palette["Boden_Erde"]
	var grass: Color = palette["Boden_Gras"]
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var t := smoothstep(0.35, 0.65, patches.get_pixel(x, y).r)
			var g := lerpf(0.9, 1.0, grain.get_pixel(x, y).r)
			image.set_pixel(x, y, earth.lerp(grass, t) * g)
	image.generate_mipmaps()
	return image


## Fahrbahn: feines Asphaltkorn mit leicht dunkleren, ausgebesserten Flecken; grau, Werte ≤ 1.
static func _road_image() -> Image:
	var grain := _noise(1523, 0.45, 1).get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	var patches := _noise(1525, 0.015, 2).get_seamless_image(TEXTURE_SIZE, TEXTURE_SIZE)
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGB8)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var v := lerpf(0.88, 1.0, grain.get_pixel(x, y).r)
			v *= 1.0 - 0.06 * smoothstep(0.6, 0.72, patches.get_pixel(x, y).r)
			image.set_pixel(x, y, Color(v, v, v))
	image.generate_mipmaps()
	return image


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise


## Flächig schattiertes Low-Poly-Netz mit Vertex-Farben (Helligkeit; die Farbe kommt aus dem Material).
class Facets:
	const ICO_FACES := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10],
			[8, 6, 7], [9, 8, 1]]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	## Dreieck mit der Vorderseite weg von `inside` (Godot: im Uhrzeigersinn von vorn).
	func triangle(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			var t := b
			b = c
			c = t
			var tc := cb
			cb = cc
			cc = tc
			n = -n
		n = n.normalized()
		vertices.append_array([a, b, c])
		normals.append_array([n, n, n])
		colors.append_array([ca, cb, cc])

	## Halm: dreiseitiges Prisma vom Fuß (bis `reach` m von der Mitte) zur Spitze, nach außen geneigt; unten dunkler.
	func blade(rng: RandomNumberGenerator, reach: float, height: float) -> void:
		var angle := rng.randf() * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var foot := out * rng.randf_range(0.0, reach)
		var width := rng.randf_range(0.035, 0.055)
		var tip := foot + out * height * rng.randf_range(0.2, 0.45) + Vector3(0.0, height, 0.0)
		var base := []
		for k in range(3):
			var a := angle + TAU * k / 3.0
			base.append(foot + Vector3(cos(a), 0.0, sin(a)) * width)
		var low := Color(0.55, 0.55, 0.55)
		var high := Color(1.0, 1.0, 1.0) * rng.randf_range(0.92, 1.05)
		var axis := foot + (tip - foot) * 0.3
		for k in range(3):
			triangle(base[k], base[(k + 1) % 3], tip, axis, low, low, high)

	## Unregelmäßiger Ikosaeder mit Radien `radii` um `centre`; jede Fläche leicht anders hell.
	func lump(rng: RandomNumberGenerator, centre: Vector3, radii: Vector3) -> void:
		var t := (1.0 + sqrt(5.0)) / 2.0
		var corners := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t),
				Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1),
				Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
		var points := []
		for corner in corners:
			var v: Vector3 = corner.normalized() * rng.randf_range(0.82, 1.12)
			points.append(centre + v * radii)
		for face in ICO_FACES:
			var a: Vector3 = points[face[0]]
			var b: Vector3 = points[face[1]]
			var c: Vector3 = points[face[2]]
			var up := ((a + b + c) / 3.0 - centre).normalized().y
			var shade := Color.WHITE * (rng.randf_range(0.82, 0.98) * lerpf(0.72, 1.0, up * 0.5 + 0.5))
			triangle(a, b, c, centre, shade, shade, shade)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var built := ArrayMesh.new()
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return built
