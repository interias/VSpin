## Strecke als Path3D: der Fahrer folgt dem Pfad, keine Lenk-Physik (ADR-0006).
##
## Schnittstelle für Fahrmodell und spätere `set_grade`-Meldung (#12):
##   length_m()          Rundenlänge in Metern (Bogenlänge des Pfads)
##   grade_at(distance)  Steigung als Anteil (0.06 = 6 %, negativ = bergab) an einer Streckenposition
## Positionen jenseits der Rundenlänge werden umgerechnet (Rundkurs).
## Die Steigung wird aus der Geometrie des Pfads gelesen – jede Kurve (Graybox, Insel-Rundkurs #14) funktioniert.
##   stations            Abschnitte in Fahrtrichtung [{id, name, start_m}] (leer = keine, z. B. Graybox)
##   station_at(distance) Abschnitt an einer Streckenposition ({} ohne Stationen)
##   road_mesh()         Fahrbahn als Band entlang des Pfads
class_name Track
extends Path3D

## Halber Abstand der beiden Messpunkte für die Steigung (Meter).
const GRADE_SAMPLE_HALF_M := 2.0
## Fahrbahnbreite (m) und Abstand der Querschnitte des Fahrbahn-Bands.
const ROAD_WIDTH_M := 6.0
const ROAD_STEP_M := 2.0

## Abschnitte in Fahrtrichtung: [{id, name, start_m}], nach start_m sortiert, erster bei 0.
var stations: Array = []


func length_m() -> float:
	return curve.get_baked_length() if curve != null else 0.0


## Streckenposition innerhalb einer Runde.
func wrap_distance(distance_m: float) -> float:
	var length := length_m()
	return fposmod(distance_m, length) if length > 0.0 else 0.0


## Steigung an der Streckenposition `distance_m`: Höhendifferenz / horizontale Distanz.
func grade_at(distance_m: float) -> float:
	var length := length_m()
	if length <= 0.0:
		return 0.0
	var a := curve.sample_baked(wrap_distance(distance_m - GRADE_SAMPLE_HALF_M))
	var b := curve.sample_baked(wrap_distance(distance_m + GRADE_SAMPLE_HALF_M))
	var horizontal := Vector2(b.x - a.x, b.z - a.z).length()
	if horizontal < 0.001:
		return 0.0
	return (b.y - a.y) / horizontal


## Weltposition (lokal zum Pfad) an der Streckenposition.
func position_at(distance_m: float) -> Vector3:
	return curve.sample_baked(wrap_distance(distance_m)) if curve != null else Vector3.ZERO


## Abschnitt (Station) an der Streckenposition `distance_m`, {} wenn die Strecke keine Stationen hat.
func station_at(distance_m: float) -> Dictionary:
	var d := wrap_distance(distance_m)
	var current: Dictionary = {}
	for station in stations:
		if station["start_m"] <= d:
			current = station
	return current


## Fahrbahn als flaches Band (Breite ROAD_WIDTH_M) entlang des Pfads, `lift` Meter über der Pfadhöhe
## (gegen Z-Fighting mit dem Gelände). Vertex-Farben: Asphalt mit hellen Randlinien. `skirt_m` > 0 hängt an
## beide Ränder eine senkrechte Böschung dieser Höhe (Graybox: Strecke über flachem Boden).
func road_mesh(lift: float = 0.08, skirt_m: float = 0.0) -> ArrayMesh:
	var length := length_m()
	var steps := maxi(int(ceil(length / ROAD_STEP_M)), 1)
	# Querschnitt: Randlinie | Asphalt | Asphalt | Randlinie (Abstand von der Mitte, Farbe)
	var across := [-0.5, -0.47, 0.47, 0.5]
	var asphalt := Color(0.33, 0.33, 0.35)
	var line := Color(0.92, 0.92, 0.88)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in range(steps + 1):
		var d := length * i / steps
		var p := position_at(d)
		var ahead := position_at(d + 1.0)
		var behind := position_at(d - 1.0)
		var dir := Vector3(ahead.x - behind.x, 0.0, ahead.z - behind.z).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		for k in range(across.size()):
			vertices.append(p + side * across[k] * ROAD_WIDTH_M + Vector3.UP * lift)
			normals.append(Vector3.UP)
			colors.append(line if k == 0 or k == across.size() - 1 else asphalt)
	var n := across.size()
	for i in range(steps):
		for k in range(n - 1):
			var a := i * n + k
			# Dreiecke so, dass die Oberseite sichtbar ist
			indices.append_array([a, a + n, a + 1, a + 1, a + n, a + n + 1])
	if skirt_m > 0.0:
		var base := vertices.size()
		var embankment := Color(0.5, 0.47, 0.42)
		for i in range(steps + 1):
			for edge in [i * n, i * n + n - 1]:
				vertices.append(vertices[edge] + Vector3.DOWN * skirt_m)
				normals.append(Vector3.UP)
				colors.append(embankment)
		for i in range(steps):
			for side in range(2):
				var top := i * n + (0 if side == 0 else n - 1)
				var low := base + i * 2 + side
				indices.append_array([top, low, top + n, top + n, low, low + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
