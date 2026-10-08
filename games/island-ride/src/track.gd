## Strecke als Path3D: der Fahrer folgt dem Pfad, keine Lenk-Physik (ADR-0006).
##
## Schnittstelle für Fahrmodell und spätere `set_grade`-Meldung (#12):
##   length_m()          Rundenlänge in Metern (Bogenlänge des Pfads)
##   grade_at(distance)  Steigung als Anteil (0.06 = 6 %, negativ = bergab) an einer Fahrtposition (siehe unten)
## Positionen jenseits der Rundenlänge werden umgerechnet (Rundkurs).
## Die Steigung wird aus der Geometrie des Pfads gelesen – jede Kurve (Graybox, Insel-Rundkurs #14) funktioniert.
##   stations            Abschnitte im Uhrzeigersinn [{id, name, start_m}] in Pfadposition (leer = keine, z. B. Graybox);
##                       optional `ccw_name` = Name gegen den Uhrzeigersinn
##   station_at(distance) Abschnitt an einer Pfadposition ({} ohne Stationen)
##   road_mesh()         Fahrbahn als Band entlang des Pfads
##   segments            Segmente mit eigener Zeit [{id, name, start_m, end_m}] (#33; leer = keine, z. B. Graybox)
##
## Fahrtrichtung (#34): `direction` im (DIRECTION_CW) oder gegen den Uhrzeigersinn (DIRECTION_CCW), gesetzt mit
## `set_direction()`. Es gibt zwei Arten von Positionen:
##   Pfadposition   Bogenlänge auf der Kurve, unabhängig von der Richtung – `position_at`, `stations`, `station_at`,
##                  `road_mesh` und der ganze Weltaufbau.
##   Fahrtposition  Meter ab Start/Ziel in Fahrtrichtung, steigt in beiden Richtungen von 0 bis zur Rundenlänge –
##                  Fahrmodell, Rundenwertung, Segmente und Ghost. `grade_at`, `segments`, `ride_position_at`,
##                  `ride_stations`, `ride_station_at`.
## Gespiegelt wird nur hier: `path_distance` bildet gegen den Uhrzeigersinn d auf L − d ab, `grade_at` dreht dort das
## Vorzeichen um. Rundenwertung, Segmente und Ghost bleiben unverändert (sie sehen nur Fahrtpositionen).
class_name Track
extends Path3D

## Halber Abstand der beiden Messpunkte für die Steigung (Meter).
const GRADE_SAMPLE_HALF_M := 2.0
## Fahrbahnbreite (m) und Abstand der Querschnitte des Fahrbahn-Bands.
const ROAD_WIDTH_M := 6.0
const ROAD_STEP_M := 2.0
## Fahrtrichtungen (Schlüssel im Spielstand wie LapTiming.DIRECTION_CW).
const DIRECTION_CW := LapTiming.DIRECTION_CW
const DIRECTION_CCW := "ccw"

## Abschnitte im Uhrzeigersinn: [{id, name, start_m}] in Pfadposition, nach start_m sortiert, erster bei 0.
var stations: Array = []
## Segmente in Fahrtrichtung: [{id, name, start_m, end_m}] in Fahrtposition innerhalb einer Runde (start_m < end_m).
var segments: Array = []
## Segmente je Richtung ({richtung: [...]}, z. B. aus IslandCourse); `set_direction` übernimmt sie in `segments`.
var segments_by_direction: Dictionary = {}
## Gewählte Fahrtrichtung (DIRECTION_*).
var direction := DIRECTION_CW


## Fahrtrichtung setzen; die Segmente dieser Richtung werden zu `segments` (sofern `segments_by_direction` sie kennt).
func set_direction(value: String) -> void:
	direction = value
	if segments_by_direction.has(value):
		segments = segments_by_direction[value]


## Gegen den Uhrzeigersinn: Fahrtrichtung entgegen der Pfadrichtung.
func reversed() -> bool:
	return direction == DIRECTION_CCW


func length_m() -> float:
	return curve.get_baked_length() if curve != null else 0.0


## Streckenposition innerhalb einer Runde.
func wrap_distance(distance_m: float) -> float:
	var length := length_m()
	return fposmod(distance_m, length) if length > 0.0 else 0.0


## Pfadposition (innerhalb der Runde) zur Fahrtposition `ride_m`: im Uhrzeigersinn dieselbe, gegen ihn L − d.
## `in_direction` rechnet für eine andere als die gewählte Richtung ("" = gewählte).
func path_distance(ride_m: float, in_direction: String = "") -> float:
	var ccw := (direction if in_direction.is_empty() else in_direction) == DIRECTION_CCW
	return wrap_distance(-ride_m if ccw else ride_m)


## Steigung an der Fahrtposition `distance_m` in Fahrtrichtung: Höhendifferenz / horizontale Distanz.
func grade_at(distance_m: float) -> float:
	var length := length_m()
	if length <= 0.0:
		return 0.0
	var d := path_distance(distance_m)
	var a := curve.sample_baked(wrap_distance(d - GRADE_SAMPLE_HALF_M))
	var b := curve.sample_baked(wrap_distance(d + GRADE_SAMPLE_HALF_M))
	var horizontal := Vector2(b.x - a.x, b.z - a.z).length()
	if horizontal < 0.001:
		return 0.0
	return (a.y - b.y if reversed() else b.y - a.y) / horizontal


## Weltposition (lokal zum Pfad) an der Fahrtposition.
func ride_position_at(ride_m: float) -> Vector3:
	return position_at(path_distance(ride_m))


## Weltposition (lokal zum Pfad) an der Pfadposition.
func position_at(distance_m: float) -> Vector3:
	return curve.sample_baked(wrap_distance(distance_m)) if curve != null else Vector3.ZERO


## Abschnitt (Station) an der Pfadposition `distance_m`, {} wenn die Strecke keine Stationen hat.
func station_at(distance_m: float) -> Dictionary:
	var d := wrap_distance(distance_m)
	var current: Dictionary = {}
	for station in stations:
		if station["start_m"] <= d:
			current = station
	return current


## Stationen in Fahrtrichtung: [{id, name, start_m}] mit start_m in Fahrtposition, erste bei 0. Gegen den
## Uhrzeigersinn in umgekehrter Reihenfolge; eine Station beginnt dort, wo sie im Uhrzeigersinn endet, und heißt
## `ccw_name`, falls die Station einen hat (z. B. Abfahrt → Osthang).
func ride_stations() -> Array:
	if not reversed() or stations.is_empty():
		return stations
	var length := length_m()
	var result := []
	for i in range(stations.size() - 1, -1, -1):
		var end: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else length
		result.append({"id": stations[i]["id"], "name": stations[i].get("ccw_name", stations[i]["name"]),
				"start_m": length - end})
	return result


## Abschnitt (Station) an der Fahrtposition `ride_m`, {} ohne Stationen.
func ride_station_at(ride_m: float) -> Dictionary:
	if not reversed():
		return station_at(ride_m)
	var d := wrap_distance(ride_m)
	var current: Dictionary = {}
	for station in ride_stations():
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
