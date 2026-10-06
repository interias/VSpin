## Gelände der Insel (ADR-0006, #14) als Höhenfeld – nur Godot-Bordmittel (kein Terrain3D, siehe ADR-0006 Nachtrag).
##
## Ein regelmäßiges Gitter (`CELL_M` Meter) mit Höhen in Metern über dem Meer (Meer = y 0). Zwei Quellen:
##   IslandTerrain.generate(road)   prozedural: Inselform (Superellipse mit Bucht am Hafen, Felsküste im Westen),
##                                  großräumig den Straßenhöhen folgend, Gipfel im Nordwesten, unter die Straße geformt
##   IslandTerrain.from_image(img)  handgemalte Höhenkarte (Graustufen/R-Kanal 0..1 → MIN..MAX Meter) – zum späteren
##                                  Ersetzen des prozeduralen Geländes; `fit_to_road()` formt sie ebenso unter die Straße.
## Die Straße bestimmt das Gelände in ihrer Nähe: bis `ROAD_FLAT_M` vom Straßenrand-Mittelpunkt liegt das Gelände
## auf Straßenhöhe (gewichtetes Mittel der nahen Straßenpunkte), bis `ROAD_BLEND_M` geht es weich ins natürliche
## Gelände über (Böschung, Einschnitt). So schwebt die Straße nicht und ist nicht vergraben.
##
##   height_at(x, z)        Geländehöhe (bilinear) an einer Weltposition
##   road_distance_at(x, z) Abstand zur Straßenmitte (für Bepflanzung/Deko), INF außerhalb der Straßennähe
##   build_mesh()           ArrayMesh mit Normalen und Vertex-Farben (Sand, Fels, trockenes Gras, Oliv)
class_name IslandTerrain
extends RefCounted

## Weltbereich des Gitters (x, z) – Insel ca. 2,1 × 3,1 km plus Meer drumherum.
const ORIGIN := Vector2(-1300.0, -1800.0)
const SIZE := Vector2(2600.0, 3600.0)
const CELL_M := 5.0
## Zellgröße des groben Gitters für die großräumige Höhe.
const MACRO_CELL_M := 40.0
## Gelände bis zu diesem Abstand von der Straßenmitte liegt auf Straßenhöhe (Fahrbahn + Bankett).
const ROAD_FLAT_M := 12.0
## Bis zu diesem Abstand geht das Gelände weich ins natürliche über.
const ROAD_BLEND_M := 70.0
## Tiefe des Meeresbodens weit draußen.
const SEA_FLOOR_M := -40.0
## Höhenbereich einer Höhenkarte (from_image): Schwarz = MIN, Weiß = MAX.
const IMAGE_MIN_M := -40.0
const IMAGE_MAX_M := 360.0

## Hafenbucht (Mitte, Radius) – hier reicht das Meer bis an den Kai.
const BAY_CENTER := Vector2(300.0, 1460.0)
const BAY_SIGMA_M := 150.0

## Vertex-Anzahl je Achse.
var columns := 0
var rows := 0
var heights := PackedFloat32Array()
## Abstand jedes Gitterpunkts zur Straßenmitte (INF = weiter als ROAD_BLEND_M).
var road_distance := PackedFloat32Array()

static var _noise: FastNoiseLite = null
static var _cached: IslandTerrain = null


func _init() -> void:
	columns = int(SIZE.x / CELL_M) + 1
	rows = int(SIZE.y / CELL_M) + 1
	heights.resize(columns * rows)
	road_distance.resize(columns * rows)
	road_distance.fill(INF)


## Gelände des Insel-Rundkurses (gecacht – die Erzeugung dauert ein paar Sekunden).
static func for_course() -> IslandTerrain:
	if _cached == null:
		_cached = generate(IslandCourse.samples())
	return _cached


## Prozedurales Gelände, unter die Straße `road` (Punkte x, Höhe, z) geformt.
## Großräumig folgt das Gelände den Straßenhöhen (weiches Mittel über die ganze Insel, damit die Straße nicht auf
## einem Damm oder in einer Schlucht liegt), darüber Gipfel, Rauschen und die Küstenform; nahe der Straße
## formt `fit_to_road()` das Gelände exakt unter die Fahrbahn.
static func generate(road: PackedVector3Array) -> IslandTerrain:
	var terrain := IslandTerrain.new()
	var macro := _macro_field(road)
	for row in range(terrain.rows):
		for col in range(terrain.columns):
			var p := terrain.vertex_xz(col, row)
			terrain.heights[row * terrain.columns + col] = natural_height(p.x, p.y, _macro_at(macro, p.x, p.y))
	terrain.fit_to_road(road)
	return terrain


## Großräumige Höhe aus den Straßenhöhen: gewichtetes Mittel (1/(d² + 80²)²) auf einem groben Gitter.
static func _macro_field(road: PackedVector3Array) -> Image:
	var cols := int(SIZE.x / MACRO_CELL_M) + 1
	var rows_count := int(SIZE.y / MACRO_CELL_M) + 1
	var field := Image.create(cols, rows_count, false, Image.FORMAT_RF)
	var points := PackedVector3Array()
	for i in range(0, road.size(), 8):
		points.append(road[i])
	for row in range(rows_count):
		for col in range(cols):
			var x := ORIGIN.x + col * MACRO_CELL_M
			var z := ORIGIN.y + row * MACRO_CELL_M
			var w_sum := 0.0
			var h_sum := 0.0
			for p in points:
				var d_sq := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z) + 6400.0
				var w := 1.0 / (d_sq * d_sq)
				w_sum += w
				h_sum += w * p.y
			field.set_pixel(col, row, Color(h_sum / w_sum, 0.0, 0.0))
	return field


static func _macro_at(field: Image, x: float, z: float) -> float:
	var fx := clampf((x - ORIGIN.x) / MACRO_CELL_M, 0.0, field.get_width() - 1.001)
	var fz := clampf((z - ORIGIN.y) / MACRO_CELL_M, 0.0, field.get_height() - 1.001)
	var col := int(fx)
	var row := int(fz)
	var top := lerpf(field.get_pixel(col, row).r, field.get_pixel(col + 1, row).r, fx - col)
	var bottom := lerpf(field.get_pixel(col, row + 1).r, field.get_pixel(col + 1, row + 1).r, fx - col)
	return lerpf(top, bottom, fz - row)


## Gelände aus einer Höhenkarte (R-Kanal 0..1 → IMAGE_MIN_M..IMAGE_MAX_M), auf das Gitter skaliert.
## Danach `fit_to_road()` aufrufen, damit die Straße passt.
static func from_image(image: Image) -> IslandTerrain:
	var terrain := IslandTerrain.new()
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.resize(terrain.columns, terrain.rows, Image.INTERPOLATE_BILINEAR)
	for row in range(terrain.rows):
		for col in range(terrain.columns):
			terrain.heights[row * terrain.columns + col] = lerpf(IMAGE_MIN_M, IMAGE_MAX_M, img.get_pixel(col, row).r)
	return terrain


## Formt das Gelände unter die Straße: nahe der Straße gewichtetes Mittel der Straßenhöhen (Gewicht 1/(d²+4)²,
## dominiert vom nächsten Straßenstück), weich übergeblendet ins vorhandene Gelände.
func fit_to_road(road: PackedVector3Array) -> void:
	var count := columns * rows
	var weight_sum := PackedFloat32Array()
	var height_sum := PackedFloat32Array()
	weight_sum.resize(count)
	height_sum.resize(count)
	var reach := int(ceil(ROAD_BLEND_M / CELL_M))
	var blend_sq := ROAD_BLEND_M * ROAD_BLEND_M
	for p in road:
		var center_col := int(round((p.x - ORIGIN.x) / CELL_M))
		var center_row := int(round((p.z - ORIGIN.y) / CELL_M))
		for row in range(maxi(center_row - reach, 0), mini(center_row + reach, rows - 1) + 1):
			var dz := ORIGIN.y + row * CELL_M - p.z
			for col in range(maxi(center_col - reach, 0), mini(center_col + reach, columns - 1) + 1):
				var dx := ORIGIN.x + col * CELL_M - p.x
				var d_sq := dx * dx + dz * dz
				if d_sq > blend_sq:
					continue
				var i := row * columns + col
				var w := 1.0 / ((d_sq + 4.0) * (d_sq + 4.0))
				weight_sum[i] += w
				height_sum[i] += w * p.y
				var d := sqrt(d_sq)
				if d < road_distance[i]:
					road_distance[i] = d
	for i in range(count):
		if weight_sum[i] <= 0.0:
			continue
		var road_height := height_sum[i] / weight_sum[i]
		var t := smoothstep(ROAD_FLAT_M, ROAD_BLEND_M, road_distance[i])
		heights[i] = lerpf(road_height, heights[i], t)


## Weltposition (x, z) eines Gitterpunkts.
func vertex_xz(col: int, row: int) -> Vector2:
	return Vector2(ORIGIN.x + col * CELL_M, ORIGIN.y + row * CELL_M)


## Geländehöhe an (x, z), bilinear zwischen den Gitterpunkten; außerhalb des Gitters Meeresboden.
func height_at(x: float, z: float) -> float:
	return _sample(heights, x, z, SEA_FLOOR_M)


## Abstand zur Straßenmitte an (x, z) (nächster Gitterpunkt), INF weit weg von der Straße.
func road_distance_at(x: float, z: float) -> float:
	var col := int(round((x - ORIGIN.x) / CELL_M))
	var row := int(round((z - ORIGIN.y) / CELL_M))
	if col < 0 or row < 0 or col >= columns or row >= rows:
		return INF
	return road_distance[row * columns + col]


func _sample(values: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := (x - ORIGIN.x) / CELL_M
	var fz := (z - ORIGIN.y) / CELL_M
	if fx < 0.0 or fz < 0.0 or fx > columns - 1 or fz > rows - 1:
		return outside
	var col := mini(int(fx), columns - 2)
	var row := mini(int(fz), rows - 2)
	var tx := fx - col
	var tz := fz - row
	var i := row * columns + col
	var top := lerpf(values[i], values[i + 1], tx)
	var bottom := lerpf(values[i + columns], values[i + columns + 1], tx)
	return lerpf(top, bottom, tz)


## Landanteil an (x, z): > 0 an Land (größer = weiter im Inland), < 0 im Meer. Superellipse ~2,1 × 3,1 km
## mit leicht verrauschter Küste und einer Bucht am Hafen.
static func land(x: float, z: float) -> float:
	var e := pow(pow(absf(x) / 1050.0, 2.6) + pow(absf(z) / 1550.0, 2.6), 1.0 / 2.6)
	e *= 1.0 + 0.035 * _noise_2d(x * 0.6, z * 0.6)
	var bay := Vector2(x, z).distance_squared_to(BAY_CENTER)
	return 1.0 - e - 0.3 * exp(-bay / (2.0 * BAY_SIGMA_M * BAY_SIGMA_M))


## Natürliche Geländehöhe an (x, z) über der großräumigen Höhe `base` (aus den Straßenhöhen): Gipfel (Puig)
## über der Hochebene im Nordwesten, Rauschen, hohe Felsküste im Westen, flache Küste im Süden und Osten.
static func natural_height(x: float, z: float, base: float) -> float:
	var l := land(x, z)
	if l <= 0.0:
		return maxf(1.5 + l * 800.0, SEA_FLOOR_M)
	var interior := base \
			+ 90.0 * exp(-(pow((x + 330.0) / 260.0, 2.0) + pow((z + 730.0) / 190.0, 2.0))) \
			+ 14.0 * _noise_2d(x, z)
	# Küstenabfall: im Westen steile Klippen, im Süden/Osten flach.
	var shore := lerpf(0.02, 0.1, smoothstep(-600.0, 0.0, x))
	return 1.5 + (maxf(interior, 2.0) - 1.5) * smoothstep(0.0, shore, l)


static func _noise_2d(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1312
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.0025
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 4
	return _noise.get_noise_2d(x, z)


## Dreiecksnetz des Geländes mit Normalen und Vertex-Farben.
func build_mesh() -> ArrayMesh:
	var count := columns * rows
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	var sand := Color(0.86, 0.79, 0.6)
	var rock := Color(0.58, 0.52, 0.46)
	var dry := Color(0.68, 0.64, 0.42)
	var olive := Color(0.42, 0.5, 0.29)
	var shoulder := Color(0.72, 0.66, 0.55)
	var seabed := Color(0.55, 0.6, 0.55)
	for row in range(rows):
		for col in range(columns):
			var i := row * columns + col
			var h := heights[i]
			var p := vertex_xz(col, row)
			vertices[i] = Vector3(p.x, h, p.y)
			var hl := heights[i - 1] if col > 0 else h
			var hr := heights[i + 1] if col < columns - 1 else h
			var hu := heights[i - columns] if row > 0 else h
			var hd := heights[i + columns] if row < rows - 1 else h
			var n := Vector3(hl - hr, 2.0 * CELL_M, hu - hd).normalized()
			normals[i] = n
			var slope := sqrt(1.0 - n.y * n.y) / maxf(n.y, 0.01)
			var c: Color
			if h < 0.0:
				c = seabed
			elif h < 3.0:
				c = sand
			else:
				c = dry.lerp(olive, clampf(0.5 + 0.8 * _noise_2d(p.x * 3.0, p.y * 3.0), 0.0, 1.0))
				c = c.lerp(rock, smoothstep(0.6, 1.1, slope))
			if road_distance[i] < 9.0:
				c = shoulder
			colors[i] = c
	var indices := PackedInt32Array()
	indices.resize((columns - 1) * (rows - 1) * 6)
	var k := 0
	for row in range(rows - 1):
		for col in range(columns - 1):
			var a := row * columns + col
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + columns
			indices[k + 3] = a + 1
			indices[k + 4] = a + columns + 1
			indices[k + 5] = a + columns
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
