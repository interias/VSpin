## Insel-Rundkurs (ADR-0006, #14): Grundriss und Höhenprofil des ca. 9 km langen Rundkurses im Mallorca-Stil.
##
## Reine Daten/Logik ohne Darstellung. Der Grundriss ist eine Folge von Wegpunkten (x, z in Metern; x = Osten,
## z = Süden, Insel ca. 2 × 3 km um den Ursprung), geglättet mit einem zentripetalen Catmull-Rom-Spline und
## gleichmäßig neu abgetastet. Das Höhenprofil entsteht aus Steigungen je Abschnitt (Station) mit Zielhöhen an den
## Abschnittsgrenzen, leichtem Wellen in Küste/Hain und einer gleitenden Glättung – so bleibt die Steigung
## realistisch (Serpentinen ~7 %, Abfahrt ~-7 %, keine Sprünge). Das Gelände (IslandTerrain) wird anschließend
## unter die Straße geformt, nicht umgekehrt.
##
## Stationen in Fahrtrichtung: Hafen (Start/Ziel) → Küstenstraße → Serpentinen (mit Aussichtspunkt am Ende)
## → Pinien-/Olivenhain → Bergdorf → Abfahrt zurück zum Hafen.
##
##   IslandCourse.apply_to(t) Kurve, Stationen und Segmente beider Richtungen auf einen Track (Path3D) setzen
##   IslandCourse.curve()     Curve3D des Rundkurses (gecacht, geschlossen: letzter Punkt = erster Punkt)
##   IslandCourse.stations()  [{id, name, start_m}] in Fahrtrichtung, start_m = Streckenposition auf der Kurve
##   IslandCourse.landmarks() [{id, name, distance_m}] besondere Punkte (Aussichtspunkt)
##   IslandCourse.segments(richtung) [{id, name, start_m, end_m}] Segmente mit eigener Zeit (#33), je Richtung (#34)
##
## Gegenrichtung (#34): derselbe Pfad rückwärts (Track.set_direction) – Start/Ziel bleibt der Hafen, der lange Anstieg
## führt über den Osthang hinauf zum Bergdorf, die Serpentinen werden zur Abfahrt.
class_name IslandCourse
extends RefCounted

## Abstand der Kurvenpunkte (Grundriss) in Metern.
const POINT_SPACING_M := 5.0
## Fensterbreite der gleitenden Glättung der Steigung in Metern.
const GRADE_SMOOTHING_M := 80.0

## Serpentinen à la Sa Calobra: Kehren zwischen geraden Rampen am Nordwesthang.
const SERPENTINE_FIRST_LEG := Vector2(-650.0, -250.0)
const SERPENTINE_LEG_LENGTH := 300.0
const SERPENTINE_LEGS := 6
const SERPENTINE_HAIRPIN_RADIUS := 27.5

## Abschnitte in Fahrtrichtung. Höhe am Abschnittsende: `to_height` (m über Meer), `rise` (m relativ) oder
## `grade` (feste mittlere Steigung, Höhe ergibt sich aus der Länge). `wave` = Amplitude einer Wellenbewegung
## (Anteil) mit `waves` vollen Perioden – summiert sich im Abschnitt zu 0. `runout_m`/`runout_grade` = flacherer
## Auslauf am Abschnittsende (Abfahrt in den Hafen). `ccw_name` = Name gegen den Uhrzeigersinn (#34), wo der Name
## rückwärts nicht passt: die Abfahrt ist dort der Anstieg über den Osthang.
const START_HEIGHT := 3.0
const SECTIONS := [
	{"id": "hafen", "name": "Hafen", "to_height": 4.0},
	{"id": "kueste", "name": "Küstenstraße", "to_height": 42.0, "wave": 0.025, "waves": 3},
	{"id": "serpentinen", "name": "Serpentinen", "grade": 0.072, "wave": 0.012, "waves": 3},
	{"id": "hain", "name": "Pinien-/Olivenhain", "rise": 10.0, "wave": 0.02, "waves": 2},
	{"id": "bergdorf", "name": "Bergdorf", "rise": 2.0},
	{"id": "abfahrt", "name": "Abfahrt", "ccw_name": "Osthang", "to_height": START_HEIGHT, "wave": 0.012, "waves": 3, "runout_m": 320.0, "runout_grade": -0.015},
]

## Segmente (#33): feste Abschnitte mit eigener Zeit, je Richtung Start- und Endmeter (Fahrtposition, Start < Ende in
## Fahrtrichtung). Reine Daten. Im Uhrzeigersinn ("cw"):
##   Küstenwelle  die drei Wellen der Küstenstraße (Kuppen bei ~0,6 / 1,2 / 1,8 km)
##   Bergwertung  die Serpentinen von der ersten Rampe bis zur Kuppe am Aussichtspunkt
##   Dorfsprint   durchs Bergdorf
## Gegen den Uhrzeigersinn ("ccw", Rundenlänge ~9210 m, Fahrtposition = Rundenlänge − Pfadposition):
##   Bergwertung  der lange Anstieg über den Osthang vom Ende der Hafeneinfahrt bis kurz vor das Bergdorf
##                (~2,85 km, ~7 %) – wieder der Berg der Runde, daher derselbe Name
##   Dorfsprint   durchs Bergdorf, dieselbe Strecke rückwärts
##   Küstenwelle  die drei Wellen der Küstenstraße rückwärts
## Ids und Namen bleiben je Richtung gleich; Bestzeiten und Medaillen trennt der Spielstand nach Richtung.
const SEGMENTS := [
	{"id": "kuestenwelle", "name": "Küstenwelle", "cw": {"start_m": 480.0, "end_m": 2240.0},
		"ccw": {"start_m": 6970.0, "end_m": 8730.0}},
	{"id": "bergwertung", "name": "Bergwertung", "cw": {"start_m": 2340.0, "end_m": 4590.0},
		"ccw": {"start_m": 330.0, "end_m": 3180.0}},
	{"id": "dorfsprint", "name": "Dorfsprint", "cw": {"start_m": 5700.0, "end_m": 6010.0},
		"ccw": {"start_m": 3200.0, "end_m": 3510.0}},
]

static var _cache: Dictionary = {}


## Wegpunkte des Grundrisses je Abschnitt (ohne den Endpunkt; der Endpunkt eines Abschnitts ist der
## erste Punkt des nächsten, der des letzten Abschnitts der Start).
static func waypoints() -> Array:
	var serpentine: Array[Vector2] = []
	for leg in range(SERPENTINE_LEGS):
		var z := SERPENTINE_FIRST_LEG.y - leg * SERPENTINE_HAIRPIN_RADIUS * 2.0
		var west := SERPENTINE_FIRST_LEG.x
		var east := west + SERPENTINE_LEG_LENGTH
		var eastbound := leg % 2 == 0
		var from := Vector2(west if eastbound else east, z)
		var to := Vector2(east if eastbound else west, z)
		serpentine.append(from)
		serpentine.append(from.lerp(to, 0.5))
		if leg < SERPENTINE_LEGS - 1:
			serpentine.append_array(_hairpin(to, eastbound))
		else:
			serpentine.append(to)
	serpentine.append(Vector2(-695.0, -545.0))  # Kuppe mit Aussichtspunkt über der Westküste
	return [
		# Hafen: Kai an der Bucht im Süden, Richtung Westen
		[Vector2(350, 1262), Vector2(200, 1268), Vector2(70, 1255)],
		# Küstenstraße: an der Südküste nach Westen, dann an der Felsküste im Westen nach Norden
		[Vector2(-60, 1225), Vector2(-200, 1185), Vector2(-380, 1105), Vector2(-540, 970), Vector2(-660, 790),
			Vector2(-745, 560), Vector2(-790, 320), Vector2(-800, 80), Vector2(-780, -80), Vector2(-735, -185),
			Vector2(-690, -240)],
		# Serpentinen-Anstieg mit Aussichtspunkt
		serpentine,
		# Pinien-/Olivenhain auf der Hochebene
		[Vector2(-735, -620), Vector2(-700, -740), Vector2(-560, -870), Vector2(-360, -940), Vector2(-150, -940),
			Vector2(0, -895)],
		# Bergdorf
		[Vector2(100, -850), Vector2(195, -790), Vector2(275, -715)],
		# Abfahrt über den Osthang zurück zum Hafen (mit zwei weiten Kehren)
		[Vector2(350, -630), Vector2(520, -520), Vector2(670, -365), Vector2(755, -160), Vector2(790, 60),
			Vector2(770, 250), Vector2(700, 340), Vector2(560, 375), Vector2(450, 410), Vector2(410, 470),
			Vector2(450, 530), Vector2(580, 545), Vector2(700, 600), Vector2(740, 700), Vector2(690, 790),
			Vector2(560, 820), Vector2(440, 850), Vector2(400, 910), Vector2(440, 970), Vector2(560, 985),
			Vector2(660, 1030), Vector2(680, 1120), Vector2(600, 1200), Vector2(480, 1245)],
	]


## Kehre (Halbkreis) am Ende einer Ost-West-Rampe: vom Rampenende `at` um 180° auf die nächste Rampe weiter
## nördlich (z kleiner). Liefert das Rampenende und die Punkte auf dem Bogen, ohne den Beginn der nächsten Rampe.
static func _hairpin(at: Vector2, eastbound: bool) -> Array[Vector2]:
	var r := SERPENTINE_HAIRPIN_RADIUS
	var center := at + Vector2(0.0, -r)
	var side := 1.0 if eastbound else -1.0
	var points: Array[Vector2] = []
	for i in range(0, 6):
		var angle := PI * float(i) / 6.0
		points.append(center + Vector2(side * r * sin(angle), r * cos(angle)))
	return points


## Macht `track` zum Insel-Rundkurs: Kurve, Stationen und Segmente beider Richtungen; gefahren wird in `direction`.
static func apply_to(track: Track, direction: String = Track.DIRECTION_CW) -> void:
	track.curve = curve()
	track.stations = stations().duplicate(true)
	track.segments_by_direction = {Track.DIRECTION_CW: segments(Track.DIRECTION_CW),
			Track.DIRECTION_CCW: segments(Track.DIRECTION_CCW)}
	track.set_direction(direction)


## Segmente in Richtung `direction` (Track.DIRECTION_*): [{id, name, start_m, end_m}], in Fahrtrichtung (nach start_m).
static func segments(direction: String) -> Array:
	var result := []
	for segment in SEGMENTS:
		if segment.has(direction):
			result.append({"id": segment["id"], "name": segment["name"], "start_m": segment[direction]["start_m"],
					"end_m": segment[direction]["end_m"]})
	result.sort_custom(func(a, b): return a["start_m"] < b["start_m"])
	return result


## Curve3D des Rundkurses (gecacht).
static func curve() -> Curve3D:
	return _build()["curve"]


## Stationen im Uhrzeigersinn: [{id, name, ccw_name, start_m}] (start_m = Pfadposition auf der Kurve).
static func stations() -> Array:
	return _build()["stations"]


## Besondere Punkte: [{id, name, distance_m}].
static func landmarks() -> Array:
	return _build()["landmarks"]


## Grundriss-Abtastpunkte mit Höhe: Vector3(x, Höhe, z), gleichmäßiger Abstand, geschlossen.
static func samples() -> PackedVector3Array:
	return _build()["samples"]


static func _build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var plan := _plan()
	var points: PackedVector2Array = plan["points"]
	var boundaries: Array = plan["boundaries"]
	var heights := _heights(points.size(), plan["spacing"], boundaries)
	var result := Curve3D.new()
	result.bake_interval = 1.0
	var samples := PackedVector3Array()
	for i in range(points.size()):
		var p := Vector3(points[i].x, heights[i], points[i].y)
		samples.append(p)
		result.add_point(p)
	result.add_point(samples[0])  # geschlossen
	samples.append(samples[0])
	var stations := []
	for s in range(SECTIONS.size()):
		stations.append({"id": SECTIONS[s]["id"], "name": SECTIONS[s]["name"],
				"ccw_name": SECTIONS[s].get("ccw_name", SECTIONS[s]["name"]),
				"start_m": 0.0 if s == 0 else result.get_closest_offset(samples[boundaries[s]])})
	var landmarks := [{"id": "aussichtspunkt", "name": "Aussichtspunkt",
			"distance_m": result.get_closest_offset(samples[plan["viewpoint"]])}]
	_cache = {"curve": result, "stations": stations, "landmarks": landmarks, "samples": samples}
	return _cache


## Geglätteter, gleichmäßig abgetasteter Grundriss. `boundaries[s]` = Index des ersten Punkts von Abschnitt s.
static func _plan() -> Dictionary:
	var sections := waypoints()
	var control: Array[Vector2] = []
	var section_of_control: Array[int] = []
	for s in range(sections.size()):
		for p in sections[s]:
			control.append(p)
			section_of_control.append(s)
	# Dicht abtasten (zentripetaler Catmull-Rom, geschlossen), Länge je Wegpunkt merken.
	var dense := PackedVector2Array()
	var dense_len := PackedFloat32Array()
	var control_len := PackedFloat32Array()
	var length := 0.0
	var n := control.size()
	for i in range(n):
		var p0 := control[(i - 1 + n) % n]
		var p1 := control[i]
		var p2 := control[(i + 1) % n]
		var p3 := control[(i + 2) % n]
		var steps := maxi(4, int(ceil(p1.distance_to(p2) / 1.0)))
		control_len.append(length)
		for k in range(steps):
			var q := _catmull_rom(p0, p1, p2, p3, float(k) / steps)
			if not dense.is_empty():
				length += dense[dense.size() - 1].distance_to(q)
			dense.append(q)
			dense_len.append(length)
	length += dense[dense.size() - 1].distance_to(dense[0])
	# Gleichmäßig neu abtasten.
	var count := int(round(length / POINT_SPACING_M))
	var spacing := length / count
	var points := PackedVector2Array()
	var j := 0
	for i in range(count):
		var d := spacing * i
		while j + 1 < dense.size() and dense_len[j + 1] <= d:
			j += 1
		var a := dense[j]
		var b := dense[(j + 1) % dense.size()]
		var la := dense_len[j]
		var lb := dense_len[j + 1] if j + 1 < dense.size() else length
		points.append(a.lerp(b, (d - la) / maxf(lb - la, 0.0001)))
	var boundaries := []
	for s in range(sections.size()):
		var first := section_of_control.find(s)
		boundaries.append(int(round(control_len[first] / spacing)))
	boundaries.append(count)
	# Aussichtspunkt: letzter Wegpunkt der Serpentinen (Kuppe).
	var viewpoint := int(round(control_len[section_of_control.rfind(2)] / spacing))
	return {"points": points, "spacing": spacing, "boundaries": boundaries, "viewpoint": viewpoint}


## Zentripetaler Catmull-Rom zwischen p1 und p2 (t in [0, 1]) – ohne Überschwinger bei ungleichen Abständen.
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 0.001))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.001))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.001))
	var u := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))


## Höhe je Punkt: Steigung je Abschnitt (aus Zielhöhen), Wellen, gleitende Glättung, geschlossen.
static func _heights(count: int, spacing: float, boundaries: Array) -> PackedFloat32Array:
	var grades := PackedFloat32Array()
	grades.resize(count)
	var height := START_HEIGHT
	for s in range(SECTIONS.size()):
		var section: Dictionary = SECTIONS[s]
		var first: int = boundaries[s]
		var last: int = boundaries[s + 1]
		var points := last - first
		var run := points * spacing
		var target: float
		if section.has("grade"):
			target = height + section["grade"] * run
		elif section.has("rise"):
			target = height + section["rise"]
		else:
			target = section["to_height"]
		var runout_points := int(round(section.get("runout_m", 0.0) / spacing))
		var runout_grade: float = section.get("runout_grade", 0.0)
		var main_points := points - runout_points
		var main_grade := (target - height - runout_grade * runout_points * spacing) / (main_points * spacing)
		var wave: float = section.get("wave", 0.0)
		var waves: int = section.get("waves", 0)
		for k in range(points):
			var g := main_grade if k < main_points else runout_grade
			if k < main_points and wave > 0.0:
				g += wave * sin(TAU * waves * (k + 0.5) / main_points)
			grades[first + k] = g
		height = target
	# Gleitende Glättung (zyklisch): erhält die Summe, damit der Kurs geschlossen bleibt.
	var half := int(round(GRADE_SMOOTHING_M / spacing / 2.0))
	var smoothed := PackedFloat32Array()
	smoothed.resize(count)
	for i in range(count):
		var sum := 0.0
		for k in range(-half, half + 1):
			sum += grades[(i + k + count) % count]
		smoothed[i] = sum / (2 * half + 1)
	var heights := PackedFloat32Array()
	heights.resize(count)
	var h := START_HEIGHT
	var drift := 0.0
	for i in range(count):
		drift += smoothed[i] * spacing
	for i in range(count):
		heights[i] = h
		h += smoothed[i] * spacing - drift / count  # Rundungsfehler gleichmäßig verteilen
	return heights
