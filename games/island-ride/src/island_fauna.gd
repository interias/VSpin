## Weide- und Dorftiere (#40) – von `IslandWorld.build()` nach der Vegetation als Kind `World/Fauna` eingehängt. Reine
## Deko (ADR-0010): kein Tier wirkt auf Fahrmodell, Tempo, Rundenzeit oder Kamera.
##   Schafe, Ziegen  die Herden aus IslandLandmarks (Hain/obere Abfahrt bzw. Serpentinen/Küste, 22–45 m neben der
##                   Straße) grasen: Kopf gesenkt mit Kauen, ab und zu ein paar Schritte auf einem kleinen Kreis, dazu
##                   Umschauen. MultiMesh je Art unter `Details/Schafe|Ziegen` (Rumpf und Beine), Köpfe als eigenes
##                   MultiMesh `Details/<Art>/Koepfe`. Die Schafe tragen Glocken am Hals.
##   Querungen       kleine Ziegengruppen an `CROSSINGS_M` (`Fauna/Querung<n>/Ziege<k>`) laufen von der Bergseite über
##                   die Straße und springen über die Mauer auf die Talseite – abhängig vom Abstand des Fahrers in
##                   Fahrtrichtung (`crossing_progress`): ab CROSSING_START_M voraus, ab CROSSING_CLEAR_M ist die
##                   Fahrbahn frei. In beiden Richtungen; der Fahrer fährt nie durch eine Ziege.
##   Esel            je Finca der Abfahrt einer neben der Zufahrt, an einem Pfosten mit Heu (`Fauna/Esel<n>`):
##                   grast, hebt den Kopf, schlägt mit dem Schwanz.
##   Katzen          im Bergdorf auf dem Gehweg zwischen Laternen und Blumentöpfen und auf dem Kirchplatz
##                   (`Fauna/Katze<n>`): sitzend mit Schwanzwedeln und Umschauen oder auf und ab streifend.
## Tiere an Meer, Himmel und Wegrand (#41), je Art eine Gruppe `Fauna/<Art>`:
##   Delfine         Schulen in der Hafenbucht und vor der Westküste (`SCHOOLS`) ziehen auf Meereshöhe ihre Kreise und
##                   springen nacheinander aus dem Wasser.
##   Fische          springen an wechselnden Stellen nah am Ufer (Hafenkai, Küste unter der Straße), mit Spritzern.
##   Geier           Mönchsgeier kreisen in der Thermik über den Serpentinen, meist im Gleitflug. Eigene Art statt des
##                   einzelnen Greifvogels aus WorldMotion (der bleibt als Milan): so gilt für sie dieselbe
##                   Tag/Wetter-Regel wie für die anderen Arten aus #41, und Tests und Sichtprüfung erfassen sie über KINDS.
##   Schmetterlinge  flattern paarweise über Gras am Wegrand (Küste, Serpentinen, Hain, Abfahrt).
##   Eidechsen       sonnen sich auf der Mauer an Küstenstraße und Serpentinen, pumpen, huschen ein Stück und wenden.
## Wann sie sich zeigen (Tag/Nacht, Wetter, Jahreszeit), steht an einer Stelle: SHOWN_WHEN mit `shown()`; der
## SkyController stellt die Gruppen über `set_conditions()`. Browser (Compatibility): halb so viele Fische,
## Schmetterlinge und Eidechsen.
## Glocken (Einhängepunkt für den Ton, #44): `Fauna/Glocken/Herde<n>` – ein Node3D je Schafherde in ihrer Mitte,
## Meta `count` (Zahl der Schafe). Ein AudioStreamPlayer3D als Kind läutet dort.
## Orte: nicht auf der Fahrbahn (Abstand zur Straßenmitte − Radius ≥ IslandVegetation.ROAD_CLEARANCE_M; die Eidechsen
## auf der Mauer am Straßenrand), nicht in den Häusern (Dorf, Fincas), nicht auf den Getreidefeldern (#39). Alles in
## Pfadposition, also richtungsneutral.
## Wie WorldMotion ist alles eine reine Funktion der Zeit (`apply(t, rider_path_m)`), damit Tests die Bewegung ohne
## Echtzeit prüfen. Im Spiel bewegt `_process` nur Tiere bis ANIMATE_RANGE_M um die Kamera; die Fahrerposition
## liest es aus dem Pfadfolger `Track/Rider` der Hauptszene.
class_name IslandFauna
extends Node3D

## Tierarten (für Tests und Sichtprüfung).
const KINDS := ["Schafe", "Ziegen", "Esel", "Katzen", "Delfine", "Fische", "Geier", "Schmetterlinge", "Eidechsen"]
## Wann sich die Arten aus #41 zeigen: Sonnenhöhe mindestens (Grad), Regen und Bewölkung höchstens (Weather-Kennwerte
## 0..1), nicht in diesen Jahreszeiten. Delfine bei jedem Wetter, Fische nicht im Regen, Geier tagsüber ohne Regen,
## Schmetterlinge tagsüber ohne Regen und nicht im Winter, Eidechsen nur bei Sonne (klar oder leicht bewölkt).
## Arten ohne Eintrag (Weide- und Dorftiere, #40) zeigen sich immer.
const SHOWN_WHEN := {
	"Delfine": {"sun_deg": -2.0, "rain": 1.0, "cloud": 1.0, "seasons_off": []},
	"Fische": {"sun_deg": -2.0, "rain": 0.3, "cloud": 1.0, "seasons_off": []},
	"Geier": {"sun_deg": 4.0, "rain": 0.3, "cloud": 1.0, "seasons_off": []},
	"Schmetterlinge": {"sun_deg": 4.0, "rain": 0.3, "cloud": 1.0, "seasons_off": [Season.WINTER]},
	"Eidechsen": {"sun_deg": 8.0, "rain": 0.1, "cloud": 0.7, "seasons_off": []},
}
## Delfinschulen: Mitte `at` (x, z) oder Pfadposition `path_m` mit Abstand `out_m` seewärts hinter der Wasserlinie,
## Zahl und Kreisradius (m). Die Hafenbucht westlich vor den Molen, zwei Stellen vor der Westküste unter der Küstenstraße.
const SCHOOLS := [{"at": Vector2(110.0, 1530.0), "count": 4, "radius": 28.0},
		{"path_m": 900.0, "out_m": 20.0, "count": 3, "radius": 22.0},
		{"path_m": 1650.0, "out_m": 20.0, "count": 4, "radius": 24.0}]
const DOLPHIN_SPEED := 5.0
## Sprung: Zyklus (s), Anteil des Zyklus in der Luft bzw. knapp darunter, Tiefe (m) unter Wasser und Sprunghöhe.
const LEAP_PERIOD_S := 6.5
const LEAP_SHARE := 0.28
const DIVE_M := 1.6
const LEAP_M := 2.6
## Fische: Stellen [Pfadposition, Abstand hinter der Wasserlinie m] am Kai und an der Küste; Streuung (m) je Sprung.
const FISH_SPOTS := [[30.0, 8.0], [90.0, 10.0], [150.0, 8.0], [560.0, 10.0], [800.0, 8.0], [1060.0, 12.0], [1420.0, 10.0],
		[1780.0, 8.0], [2020.0, 10.0]]
const FISH_SPREAD_M := 7.0
const FISH_LEAP_S := 0.7
## Geier: Zahl, Höhe (m) der Thermik über der höchsten Stelle der Serpentinen, Kreisradien (m).
const VULTURES := 4
const VULTURE_ABOVE_M := 60.0
const VULTURE_RADII := Vector2(30.0, 90.0)
## Schmetterlinge: Stationen, Stellen je Station, Tiere je Stelle, Flugkreis (m) und Höhe über dem Boden (m).
const BUTTERFLY_STATIONS := ["kueste", "serpentinen", "hain", "abfahrt"]
const BUTTERFLY_SPOTS := 6
const BUTTERFLY_PAIR := 2
const BUTTERFLY_LOOP_M := 1.0
const BUTTERFLY_HEIGHT := Vector2(0.4, 1.3)
## Am Wegrand: Abstand (m) zur Straßenmitte höchstens, damit man sie vom Rad aus sieht.
const BUTTERFLY_ROADSIDE_M := 9.0
const BUTTERFLY_COLORS := [Color(0.98, 0.86, 0.2), Color(0.96, 0.96, 0.92), Color(0.95, 0.5, 0.15), Color(0.45, 0.62, 0.95)]
## Eidechsen: Abstand (m) entlang der Mauer an Küste und Serpentinen, Sitz auf der Mauerkrone (m von der Mitte, Höhe),
## Weg eines Huschers (m) und Zyklus (s).
const LIZARD_EVERY_M := {"kueste": 90.0, "serpentinen": 110.0}
const LIZARD_SIDE_M := 3.85
const LIZARD_TOP_M := 0.6
const LIZARD_DASH_M := 1.1
const LIZARD_PERIOD := Vector2(5.0, 9.0)
## Frei um die Querungen der Ziegen und den Aussichtspunkt (m).
const LIZARD_GAP_M := 20.0
## Querungen der Ziegen (Pfadposition, m): gerade Stücke an der Küste und auf zwei Rampen der Serpentinen.
const CROSSINGS_M := [1240.0, 2860.0, 3620.0]
const CROSSING_GOATS := 3
## Abstand des Fahrers (in Fahrtrichtung, m) zu Beginn und Ende der Querung; noch CROSSING_RETURN_M hinter ihm
## bleiben die Ziegen drüben (außerhalb des Blicks gehen sie zurück auf die Bergseite).
const CROSSING_START_M := 100.0
const CROSSING_CLEAR_M := 35.0
const CROSSING_RETURN_M := 60.0
## Seitlicher Abstand (m) zur Straßenmitte vorher (Bergseite) und nachher (Talseite, hinter der Mauer).
const CROSSING_FROM_M := 9.0
const CROSSING_TO_M := 8.0
## Verzögerung je Ziege der Gruppe (Anteil der Querung): sie laufen hintereinander.
const CROSSING_LAG := 0.15
## Mauer am Straßenrand (m von der Mitte) und Sprunghöhe darüber.
const WALL_M := 3.8
const HOP_M := 0.75
## Fincas der Abfahrt (m nach Stationsbeginn, wie `IslandWorld._build_descent`); der Esel steht davor an der Zufahrt.
const FINCAS_M := [350.0, 900.0, 1500.0, 2050.0, 2600.0]
const DONKEY_ALONG_M := -16.0
const DONKEY_SIDE_M := 13.0
## Sperrkreis um ein Finca-Haus (wie IslandVegetation).
const FINCA_RADIUS_M := 15.0
## Katzen im Bergdorf: [Anteil der Station, seitlich m (rechts positiv), Streifweg m (0 = sitzt), Fellfarbe].
const CATS := [[0.12, 5.6, 0.0, 0], [0.25, -5.6, 9.0, 1], [0.38, -5.6, 0.0, 2], [0.488, 9.0, 0.0, 4],
		[0.62, 5.6, 7.0, 3], [0.7, -5.6, 0.0, 0], [0.78, -5.6, 8.0, 4], [0.9, 5.6, 0.0, 1]]
const CAT_COLORS := [Color(0.12, 0.11, 0.11), Color(0.86, 0.5, 0.22), Color(0.55, 0.55, 0.57), Color(0.93, 0.92, 0.9),
		Color(0.5, 0.38, 0.27)]
const CAT_SPEED := 0.45
## Grasen: Kreisradius (m) höchstens, Anteil eines Zyklus, in dem das Tier geht.
const WANDER_M := 1.4
const WALK_SHARE := 0.3
## Radius (m) eines Tiers für die Abstände.
const RADIUS_M := {"Schafe": 0.6, "Ziegen": 0.6, "Esel": 1.0, "Katzen": 0.3, "Delfine": 1.3, "Fische": 0.25, "Geier": 2.0,
		"Schmetterlinge": 0.1, "Eidechsen": 0.15}
## Abstand (m) zum nächsten Getreidehalm (Feld, #39).
const FIELD_GAP_M := 2.0
## Nur Tiere bis zu dieser Entfernung von der Kamera werden im Spiel bewegt; Sichtweite der Einzeltiere.
const ANIMATE_RANGE_M := 250.0
const VISIBLE_M := {"Ziegen": 300.0, "Esel": 300.0, "Katzen": 120.0, "Delfine": 1500.0, "Fische": 300.0, "Geier": 2500.0,
		"Schmetterlinge": 80.0, "Eidechsen": 70.0}
## Halsgelenk (Pivot des Kopfes) im Rumpf.
const NECK := {"Schafe": Vector3(0.0, 0.86, -0.46), "Ziegen": Vector3(0.0, 0.92, -0.42), "Esel": Vector3(0.0, 1.2, -0.52),
		"Eidechsen": Vector3(0.0, 0.03, -0.09)}

var world: IslandWorld
## Animationszeit (s), von `_process` vorgerückt.
var time_s := 0.0
## Pfadposition des Fahrers (NAN = keiner), aus `Track/Rider`.
var rider_path_m := NAN
## Je grasendem Herdentier {kind, index, base, angle, radius, turn, period, step, phase, now, head}.
var grazers: Array[Dictionary] = []
## Je Schafherde {node, centre, count} (Glocken, #44).
var bell_herds: Array[Dictionary] = []
## Je Querung {node, path_m, side, goats: [{node, head, legs, along, graze_yaw, phase}]}.
var crossings: Array[Dictionary] = []
## Je Esel {node, head, tail, base, yaw, phase}.
var donkeys: Array[Dictionary] = []
## Je Katze {node, head, tail, path_m, side, walk_m, sitting, phase}.
var cats: Array[Dictionary] = []
## Je Delfin {node, centre, radius, speed, phase, lag, period}.
var dolphins: Array[Dictionary] = []
## Je Fisch {node, splash, spot, period, phase, seed}.
var fish: Array[Dictionary] = []
## Je Geier {node, wings, centre, radius, height, speed, phase}.
var vultures: Array[Dictionary] = []
## Je Schmetterling {node, wings, base, radius, height, rate, phase}.
var butterflies: Array[Dictionary] = []
## Je Eidechse {node, head, tail, path_m, side, period, phase}.
var lizards: Array[Dictionary] = []
## Gruppenknoten der Arten aus #41 (`Fauna/<Art>`), ein-/ausgeblendet über `set_conditions`.
var groups := {}
var _bodies := {}
var _heads := {}
var _material: StandardMaterial3D
var _fields := {}
var _fincas: Array[Vector3] = []


func setup(owner: IslandWorld) -> void:
	world = owner
	name = "Fauna"
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.9
	_index_fields()
	var descent := world._station_range("abfahrt")
	for offset in FINCAS_M:
		var finca_m: float = descent.x + offset
		_fincas.append(world._beside_road(finca_m, -world._valley_side(finca_m) * 27.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1531
	_add_herds(rng)
	_add_crossings(rng)
	_add_donkeys(rng)
	_add_cats(rng)
	var wild := RandomNumberGenerator.new()
	wild.seed = 1541
	var lite := world.compatibility
	_add_dolphins(wild)
	_add_fish(wild, lite)
	_add_vultures(wild)
	_add_butterflies(wild, lite)
	_add_lizards(wild, lite)
	apply(0.0)


func _process(delta: float) -> void:
	time_s += delta
	var rider := world.track.get_node_or_null("Rider") as PathFollow3D
	rider_path_m = rider.progress if rider != null else NAN
	var camera := get_viewport().get_camera_3d()
	_animate(time_s, rider_path_m, camera.global_position if camera != null else Vector3.ZERO,
			ANIMATE_RANGE_M if camera != null else INF)


## Stellt alle Tiere auf den Zeitpunkt `t` (s); die Querungen nach der Fahrerposition `path_m` (Pfadposition, NAN =
## kein Fahrer: Ziegen auf der Bergseite).
func apply(t: float, path_m: float = NAN) -> void:
	time_s = t
	rider_path_m = path_m
	_animate(t, path_m, Vector3.ZERO, INF)


func _animate(t: float, path_m: float, eye: Vector3, range_m: float) -> void:
	var near := func(at: Vector3) -> bool: return range_m == INF or at.distance_to(eye) < range_m
	for kind in _bodies:
		var bodies: MultiMesh = _bodies[kind]
		var heads: MultiMesh = _heads[kind]
		for grazer in grazers:
			if grazer["kind"] == kind and near.call(grazer["base"]):
				_graze(grazer, t)
				bodies.set_instance_transform(grazer["index"], grazer["now"])
				heads.set_instance_transform(grazer["index"], grazer["head"])
	for crossing in crossings:
		if near.call(crossing["node"].position):
			_cross(crossing, crossing_progress(crossing["path_m"], path_m), t)
	for donkey in donkeys:
		if near.call(donkey["node"].position):
			_place_donkey(donkey, t)
	for cat in cats:
		if near.call(cat["node"].position):
			_place_cat(cat, t)
	# Arten aus #41: ausgeblendete Gruppen ruhen im Spiel; Delfine und Geier (wenige, weithin sichtbar) immer.
	var shown := func(kind: String) -> bool: return range_m == INF or groups[kind].visible
	if shown.call("Delfine"):
		for dolphin in dolphins:
			_swim(dolphin, t)
	if shown.call("Geier"):
		for vulture in vultures:
			_soar(vulture, t)
	if shown.call("Fische"):
		for entry in fish:
			if near.call(entry["spot"]):
				_jump(entry, t)
	if shown.call("Schmetterlinge"):
		for butterfly in butterflies:
			if near.call(butterfly["base"]):
				_flutter(butterfly, t)
	if shown.call("Eidechsen"):
		for lizard in lizards:
			if near.call(lizard["node"].position):
				_place_lizard(lizard, t)


## Zeigt sich die Art `kind` bei Sonnenhöhe `sun_deg` (Grad), Wetter-Kennwerten `w` ({cloud, rain, …}, Weather) und
## Jahreszeit `season` (Season.PHASES, "" = egal)? Regel: SHOWN_WHEN. Reine Funktion.
static func shown(kind: String, sun_deg: float, w: Dictionary, season: String = "") -> bool:
	var rule: Dictionary = SHOWN_WHEN.get(kind, {})
	if rule.is_empty():
		return true
	return sun_deg >= rule["sun_deg"] and w.get("rain", 0.0) <= rule["rain"] and w.get("cloud", 0.0) <= rule["cloud"] \
			and season not in rule["seasons_off"]


## Blendet die Arten aus #41 nach Tag/Nacht, Wetter und Jahreszeit ein oder aus (vom SkyController).
func set_conditions(sun_deg: float, w: Dictionary, season: String) -> void:
	for kind in groups:
		groups[kind].visible = shown(kind, sun_deg, w, season)


## Fortschritt 0..1 der Querung an `path_m` bei Fahrer an `rider_m` (Pfadpositionen): 0 = Ziegen auf der Bergseite,
## 1 = auf der Talseite. Gemessen in Fahrtrichtung (`Track.reversed`), also in beiden Richtungen vor dem Fahrer.
func crossing_progress(path_m: float, rider_m: float) -> float:
	if is_nan(rider_m):
		return 0.0
	var length := world.track.length_m()
	var gap := fposmod(rider_m - path_m if world.track.reversed() else path_m - rider_m, length)
	if gap <= CROSSING_CLEAR_M or gap > length - CROSSING_RETURN_M:
		return 1.0
	return clampf((CROSSING_START_M - gap) / (CROSSING_START_M - CROSSING_CLEAR_M), 0.0, 1.0)


## Positionen aller Tiere einer Art (Weltkoordinaten, aktueller Stand) – für Tests und Sichtprüfung.
func positions(kind: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	for grazer in grazers:
		if grazer["kind"] == kind:
			result.append(grazer["now"].origin)
	if kind == "Ziegen":
		for crossing in crossings:
			for goat in crossing["goats"]:
				result.append(crossing["node"].position + goat["node"].position)
	var singles := {"Esel": donkeys, "Katzen": cats, "Delfine": dolphins, "Fische": fish, "Geier": vultures,
			"Schmetterlinge": butterflies, "Eidechsen": lizards}
	for entry in singles.get(kind, []):
		result.append(entry["node"].position)
	return result


## Steht an `at` ein Tier mit Radius `radius` frei (nicht auf der Fahrbahn, keinem Feld, keiner Finca)?
func allowed(at: Vector3, radius: float) -> bool:
	if world.landmarks.road_clearance(at) - radius < IslandVegetation.ROAD_CLEARANCE_M:
		return false
	for finca in _fincas:
		if Vector2(at.x - finca.x, at.z - finca.z).length() < FINCA_RADIUS_M + radius:
			return false
	return not on_field(at, radius)


## Liegt `at` (Radius `radius`) auf einem Getreidefeld (#39)?
func on_field(at: Vector3, radius: float) -> bool:
	var key := Vector2i(floori(at.x / 10.0), floori(at.z / 10.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for p in _fields.get(key + Vector2i(dx, dz), PackedVector2Array()):
				if p.distance_to(Vector2(at.x, at.z)) < FIELD_GAP_M + radius:
					return true
	return false


func _index_fields() -> void:
	if world.vegetation == null:
		return
	for station in world.vegetation.placements:
		for p in world.vegetation.placements[station].get("Getreide", PackedVector3Array()):
			var key := Vector2i(floori(p.x / 10.0), floori(p.z / 10.0))
			if not _fields.has(key):
				_fields[key] = PackedVector2Array()
			_fields[key].append(Vector2(p.x, p.z))


## Herden aus IslandLandmarks: Tiere auf Feldern oder an Fincas entfallen, der Kreis beim Grasen bleibt frei von der
## Fahrbahn. Schafherden bekommen einen Glocken-Knoten.
func _add_herds(rng: RandomNumberGenerator) -> void:
	var details := world.get_node("Details")
	var lists := {"Schafe": [] as Array[Transform3D], "Ziegen": [] as Array[Transform3D]}
	var bells := Node3D.new()
	bells.name = "Glocken"
	add_child(bells)
	for herd in world.landmarks.herds:
		var kind: String = herd["kind"]
		var radius: float = RADIUS_M[kind]
		var centre := Vector3.ZERO
		var count := 0
		for placed in herd["transforms"]:
			var base: Vector3 = placed.origin
			var wander := clampf(world.landmarks.road_clearance(base) - radius - IslandVegetation.ROAD_CLEARANCE_M, 0.0, WANDER_M)
			if not allowed(base, radius + wander):
				continue
			grazers.append({"kind": kind, "index": lists[kind].size(), "base": base, "angle": rng.randf() * TAU,
					"radius": wander * rng.randf_range(0.5, 1.0), "turn": 1.0 if rng.randf() < 0.5 else -1.0,
					"period": rng.randf_range(9.0, 16.0), "step": rng.randf_range(0.5, 1.1), "phase": rng.randf() * 10.0,
					"now": placed, "head": placed})
			lists[kind].append(placed)
			centre += base
			count += 1
		if kind == "Schafe" and count > 0:
			var bell := Node3D.new()
			bell.name = "Herde%d" % (bell_herds.size() + 1)
			bell.position = centre / count
			bell.set_meta("count", count)
			bells.add_child(bell)
			bell_herds.append({"node": bell, "centre": bell.position, "count": count})
	for kind in lists:
		var body := _multimesh(details, kind, _body_mesh(kind, true), lists[kind])
		_heads[kind] = _multimesh(body, "Koepfe", _head_mesh(kind), lists[kind]).multimesh
		_bodies[kind] = body.multimesh


func _multimesh(parent: Node, node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for k in range(transforms.size()):
		multimesh.set_instance_transform(k, transforms[k])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Grasen zur Zeit `t`: Zyklus aus Gehen (Anteil WALK_SHARE, ein Schritt `step` auf dem Kreis) und Fressen mit
## gesenktem Kopf und Kauen; dazwischen hebt das Tier kurz den Kopf und schaut sich um.
func _graze(grazer: Dictionary, t: float) -> void:
	var phase: float = grazer["phase"]
	var cycle: float = t / grazer["period"] + phase
	var n := floorf(cycle)
	var f := cycle - n
	var moving := smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(WALK_SHARE - 0.05, WALK_SHARE, f))
	var look := smoothstep(0.55, 0.6, f) * (1.0 - smoothstep(0.72, 0.78, f))
	var r: float = grazer["radius"]
	var turn: float = grazer["turn"]
	var angle: float = grazer["angle"] + turn * (n + smoothstep(0.0, WALK_SHARE, f)) * grazer["step"] / maxf(r, 0.5)
	var at: Vector3 = grazer["base"] + Vector3(cos(angle), 0.0, sin(angle)) * r
	at.y = world.terrain.height_at(at.x, at.z) + 0.03 * absf(sin(t * 8.0 + phase)) * moving
	var heading := Vector3(-sin(angle), 0.0, cos(angle)) * turn
	var body := Transform3D(Basis(Vector3.UP, atan2(-heading.x, -heading.z)), at)
	var pitch := lerpf(lerpf(-0.85 + 0.07 * sin(t * 5.0 + phase), 0.15, look), 0.05, moving)
	var yaw := 0.5 * sin(t * 0.9 + phase) * look
	grazer["now"] = body
	grazer["head"] = body * Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), NECK[grazer["kind"]])


## Ziegengruppen an den Querungen, anfangs grasend auf der Bergseite.
func _add_crossings(rng: RandomNumberGenerator) -> void:
	var i := 1
	for path_m in CROSSINGS_M:
		var node := Node3D.new()
		node.name = "Querung%d" % i
		node.position = world.track.position_at(path_m)
		add_child(node)
		var crossing := {"node": node, "path_m": path_m, "side": world._valley_side(path_m), "goats": []}
		for k in range(CROSSING_GOATS):
			var goat := _creature(node, "Ziege%d" % (k + 1), "Ziegen", _body_mesh("Ziegen", false), _head_mesh("Ziegen"))
			var legs: Array[Node3D] = []
			for leg in range(4):
				var pivot := Node3D.new()
				pivot.name = "Bein%d" % (leg + 1)
				pivot.position = Vector3(-0.13 if leg % 2 == 0 else 0.13, 0.5, -0.3 if leg < 2 else 0.3)
				goat["node"].add_child(pivot)
				var part := IslandLandmarks.Parts.new()
				part.box(Vector3(0.08, 0.5, 0.08), Transform3D(Basis(), Vector3(0.0, -0.25, 0.0)), Color(0.18, 0.13, 0.09))
				_mesh(pivot, "Mesh", part.commit(), VISIBLE_M["Ziegen"])
				legs.append(pivot)
			goat["legs"] = legs
			goat["along"] = (k - (CROSSING_GOATS - 1) / 2.0) * 1.8 + rng.randf_range(-0.4, 0.4)
			goat["graze_yaw"] = rng.randf() * TAU
			goat["phase"] = rng.randf() * TAU
			crossing["goats"].append(goat)
		crossings.append(crossing)
		i += 1


## Querung beim Fortschritt `progress`: Ziege k läuft um k · CROSSING_LAG verzögert von der Berg- auf die Talseite,
## springt über die Mauer, Beine im Trab; vorher und nachher grast sie.
func _cross(crossing: Dictionary, progress: float, t: float) -> void:
	var side: float = crossing["side"]
	var span := 1.0 - (CROSSING_GOATS - 1) * CROSSING_LAG
	var k := 0
	for goat in crossing["goats"]:
		var p := clampf((progress - k * CROSSING_LAG) / span, 0.0, 1.0)
		var x := lerpf(-side * CROSSING_FROM_M, side * CROSSING_TO_M, smoothstep(0.0, 1.0, p))
		var d: float = crossing["path_m"] + goat["along"]
		var road := world.track.position_at(d)
		var at := road + world._side_offset(d, x)
		var ground := world.terrain.height_at(at.x, at.z)
		at.y = lerpf(road.y + 0.08, ground, smoothstep(3.0, 4.5, absf(x)))
		var moving := smoothstep(0.0, 0.06, p) * (1.0 - smoothstep(0.94, 1.0, p))
		if signf(x) == side:
			at.y += HOP_M * maxf(0.0, 1.0 - pow((absf(x) - WALL_M) / 0.7, 2.0))
		var phase: float = goat["phase"]
		at.y += 0.05 * absf(sin(t * 9.0 + phase)) * moving
		var across := world._side_offset(d, side)
		var yaw := lerp_angle(goat["graze_yaw"] + 0.3 * sin(0.2 * t + phase), atan2(-across.x, -across.z), moving)
		var node: Node3D = goat["node"]
		node.position = at - crossing["node"].position
		node.rotation = Vector3(0.0, yaw, 0.0)
		var legs: Array[Node3D] = goat["legs"]
		for leg in range(4):
			legs[leg].rotation.x = 0.5 * moving * sin(t * 9.0 + phase + (PI if leg in [1, 2] else 0.0))
		goat["head"].rotation = Vector3(lerpf(-0.8 + 0.07 * sin(t * 5.0 + phase), 0.1, moving), 0.0, 0.0)
		k += 1


## Ein Esel je Finca neben der Zufahrt, mit Pfosten und Heu.
func _add_donkeys(rng: RandomNumberGenerator) -> void:
	var descent := world._station_range("abfahrt")
	var i := 1
	for offset in FINCAS_M:
		var finca_m: float = descent.x + offset
		var d: float = finca_m + DONKEY_ALONG_M
		var at := world._beside_road(d, -world._valley_side(finca_m) * DONKEY_SIDE_M)
		if not allowed(at, RADIUS_M["Esel"]):
			continue
		var donkey := _creature(self, "Esel%d" % i, "Esel", _body_mesh("Esel", true), _head_mesh("Esel"))
		var tail := Node3D.new()
		tail.name = "Schwanz"
		tail.position = Vector3(0.0, 1.15, 0.58)
		donkey["node"].add_child(tail)
		var parts := IslandLandmarks.Parts.new()
		parts.cylinder(0.025, 0.035, 0.55, Vector3(0.0, -0.27, 0.06), Color(0.42, 0.38, 0.35), 5, Basis(Vector3.RIGHT, 0.2))
		parts.sphere(0.07, Vector3(0.0, -0.58, 0.12), Color(0.15, 0.13, 0.12), Basis().scaled(Vector3(1.0, 1.8, 1.0)))
		_mesh(tail, "Mesh", parts.commit(), VISIBLE_M["Esel"])
		donkey["tail"] = tail
		var to_road := world.track.position_at(d) - at
		donkey["yaw"] = atan2(-to_road.x, -to_road.z) + PI / 2.0 + rng.randf_range(-0.4, 0.4)
		donkey["base"] = at
		donkey["phase"] = rng.randf() * 10.0
		# Pfosten mit Heu daneben (fest, zur Straße hin)
		var post := IslandLandmarks.Parts.new()
		var local := Basis(Vector3.UP, donkey["yaw"]) * Vector3(0.9, 0.0, -0.9)
		post.cylinder(0.07, 0.08, 1.2, local + Vector3(0.0, 0.5, 0.0), Color(0.4, 0.3, 0.2), 6)
		post.sphere(1.0, local + Vector3(-0.1, 0.05, -0.5), Color(0.82, 0.72, 0.42), Basis().scaled(Vector3(0.5, 0.22, 0.4)))
		var stand := _mesh(self, "Pfosten%d" % i, post.commit(), VISIBLE_M["Esel"])
		stand.position = Vector3(at.x, at.y - 0.05, at.z)
		donkeys.append(donkey)
		i += 1


## Esel zur Zeit `t`: grast meist, hebt alle paar Sekunden den Kopf und schaut, verlagert das Gewicht, Schwanz schlägt.
func _place_donkey(donkey: Dictionary, t: float) -> void:
	var phase: float = donkey["phase"]
	var f := fposmod(t / 14.0 + phase, 1.0)
	var up := smoothstep(0.55, 0.62, f) * (1.0 - smoothstep(0.85, 0.92, f))
	var node: Node3D = donkey["node"]
	node.position = donkey["base"]
	node.rotation = Vector3(0.0, donkey["yaw"] + 0.08 * sin(0.3 * t + phase), 0.0)
	donkey["head"].rotation = Vector3(lerpf(-0.95 + 0.06 * sin(t * 4.0 + phase), 0.1, up), 0.4 * sin(0.8 * t + phase) * up, 0.0)
	donkey["tail"].rotation = Vector3(0.15 + 0.1 * sin(t * 1.3 + phase), 0.0, 0.5 * sin(t * 2.2 + phase) * absf(sin(t * 0.4 + phase)))


## Katzen im Bergdorf (CATS): auf dem Gehweg oder dem Kirchplatz.
func _add_cats(rng: RandomNumberGenerator) -> void:
	var range_m := world._station_range("bergdorf")
	var i := 1
	for entry in CATS:
		var path_m: float = lerpf(range_m.x, range_m.y, entry[0])
		var sitting: bool = entry[2] == 0.0
		var color: Color = CAT_COLORS[entry[3]]
		var cat := _creature(self, "Katze%d" % i, "Katzen", _cat_body(color, sitting), _cat_head(color))
		cat["head"].position = Vector3(0.0, 0.31, -0.06) if sitting else Vector3(0.0, 0.27, -0.22)
		var tail := Node3D.new()
		tail.name = "Schwanz"
		tail.position = Vector3(0.0, 0.05, 0.12) if sitting else Vector3(0.0, 0.24, 0.2)
		cat["node"].add_child(tail)
		var parts := IslandLandmarks.Parts.new()
		var basis := Basis(Vector3.RIGHT, PI / 2.0 - 0.15) if sitting else Basis(Vector3.RIGHT, -0.5)
		parts.cylinder(0.018, 0.025, 0.28, basis * Vector3(0.0, 0.14, 0.0), color.darkened(0.1), 5, basis)
		_mesh(tail, "Mesh", parts.commit(), VISIBLE_M["Katzen"])
		cat["tail"] = tail
		cat["path_m"] = path_m
		cat["side"] = entry[1]
		cat["walk_m"] = entry[2]
		cat["sitting"] = sitting
		cat["phase"] = rng.randf() * 10.0
		cats.append(cat)
		i += 1


## Katze zur Zeit `t`: sitzend mit Umschauen und Schwanzwedeln; streifend auf und ab mit Pause und Kehrtwende am Ende.
func _place_cat(cat: Dictionary, t: float) -> void:
	var phase: float = cat["phase"]
	var walk: float = cat["walk_m"]
	var along := 0.0
	var yaw := 0.0
	var moving := 0.0
	if walk > 0.0:
		var u := fposmod(t * CAT_SPEED / walk + phase, 2.0)
		var going := u < 1.0
		var f := u if going else u - 1.0
		var m := smoothstep(0.0, 0.8, f)
		along = ((m if going else 1.0 - m) - 0.5) * walk
		yaw = (0.0 if going else PI) + smoothstep(0.85, 1.0, f) * PI
		moving = 1.0 - smoothstep(0.7, 0.8, f)
	else:
		yaw = PI / 2.0 * signf(cat["side"]) + 0.6 * sin(0.05 * t + phase)  # zur Straße hin
	var d: float = cat["path_m"] + along
	var node: Node3D = cat["node"]
	node.position = world._beside_road(d, cat["side"]) + Vector3(0.0, 0.03 * absf(sin(t * 10.0 + phase)) * moving, 0.0)
	node.rotation = Vector3(0.0, world._yaw_at(d) + yaw, 0.0)
	cat["head"].rotation = Vector3(0.1 * sin(t * 0.7 + phase), 0.7 * sin(t * 0.35 + phase) * (1.0 - moving), 0.0)
	var swish := sin(t * (1.6 if cat["sitting"] else 2.4) + phase)
	cat["tail"].rotation = Vector3(0.0, 0.5 * swish, 0.0) if cat["sitting"] else Vector3(0.0, 0.0, 0.35 * swish)


## Gruppenknoten `Fauna/<kind>` einer Art aus #41.
func _group(kind: String) -> Node3D:
	var node := Node3D.new()
	node.name = kind
	add_child(node)
	groups[kind] = node
	return node


## Delfinschulen (SCHOOLS): je Schule ein Kreis auf dem Meer, die Tiere hintereinander, Sprünge versetzt.
func _add_dolphins(rng: RandomNumberGenerator) -> void:
	var group := _group("Delfine")
	var mesh := _dolphin_mesh()
	var i := 1
	for school in SCHOOLS:
		var radius: float = school["radius"]
		var centre: Vector3
		if school.has("at"):
			centre = Vector3(school["at"].x, 0.0, school["at"].y)
		else:
			var water := world._water_distance(school["path_m"], 400.0)
			if water < 0.0:
				continue
			centre = world._beside_road(school["path_m"], -(water + school["out_m"] + radius))
			centre.y = 0.0
		var phase := rng.randf() * TAU
		var direction := 1.0 if rng.randf() < 0.5 else -1.0
		for k in range(school["count"]):
			var node := Node3D.new()
			node.name = "Delfin%d" % i
			group.add_child(node)
			_mesh(node, "Rumpf", mesh, VISIBLE_M["Delfine"])
			dolphins.append({"node": node, "centre": centre, "radius": radius + (k % 2) * 3.0,
					"speed": DOLPHIN_SPEED * direction, "phase": phase - direction * k * 0.13,
					"lag": k * 0.45 + rng.randf_range(0.0, 0.3), "period": LEAP_PERIOD_S * rng.randf_range(0.9, 1.15)})
			i += 1


## Delfin zur Zeit `t`: auf dem Kreis, meist knapp unter Wasser (ausgeblendet), im Sprung in einem Bogen hinaus und
## wieder hinein, die Nase in Bahnrichtung.
func _swim(dolphin: Dictionary, t: float) -> void:
	var r: float = dolphin["radius"]
	var speed: float = dolphin["speed"]
	var period: float = dolphin["period"]
	var angle: float = dolphin["phase"] + speed / r * t
	var s := fposmod((t + dolphin["lag"]) / period, 1.0) / LEAP_SHARE
	var y := -DIVE_M
	var climb := 0.0
	if s < 1.0:
		y = -DIVE_M + LEAP_M * sin(PI * s)
		climb = LEAP_M * PI * cos(PI * s) / (LEAP_SHARE * period)
	var at: Vector3 = dolphin["centre"] + Vector3(cos(angle) * r, y, sin(angle) * r)
	var heading := Vector3(-sin(angle), 0.0, cos(angle)) * signf(speed)
	var node: Node3D = dolphin["node"]
	node.transform = Transform3D(Basis.looking_at(heading, Vector3.UP) * Basis(Vector3.RIGHT, atan2(climb, absf(speed))), at)
	node.visible = y > -DIVE_M + 0.4


## Springende Fische (FISH_SPOTS): je Stelle zwei (Browser einer), dazu ein Spritzer an der Wasserlinie.
func _add_fish(rng: RandomNumberGenerator, lite: bool) -> void:
	var group := _group("Fische")
	var body := _fish_mesh()
	var splash := _splash_mesh()
	var i := 1
	for entry in FISH_SPOTS:
		var water := world._water_distance(entry[0], 300.0)
		if water < 0.0:
			continue
		var spot := world._beside_road(entry[0], -(water + entry[1]))
		spot.y = 0.0
		for k in range(1 if lite else 2):
			var node := Node3D.new()
			node.name = "Fisch%d" % i
			group.add_child(node)
			_mesh(node, "Rumpf", body, VISIBLE_M["Fische"])
			var ring := _mesh(group, "Spritzer%d" % i, splash, VISIBLE_M["Fische"])
			fish.append({"node": node, "splash": ring, "spot": spot, "period": rng.randf_range(3.5, 7.0),
					"phase": rng.randf(), "seed": rng.randf() * 100.0})
			i += 1


## Fisch zur Zeit `t`: am Anfang jedes Zyklus ein Sprung an einer neuen Stelle um seinen Platz (aus der Zyklusnummer
## gestreut), sonst unter Wasser; der Spritzer zeigt sich beim Ein- und Austauchen.
func _jump(entry: Dictionary, t: float) -> void:
	var period: float = entry["period"]
	var cycle: float = t / period + entry["phase"]
	var n := floorf(cycle)
	var s := (cycle - n) * period / FISH_LEAP_S
	var a := _hash(n, entry["seed"])
	var b := _hash(n + 0.5, entry["seed"])
	var spot: Vector3 = entry["spot"] + Vector3(cos(a * TAU), 0.0, sin(a * TAU)) * FISH_SPREAD_M * b
	var dir := Vector3(cos(b * TAU * 3.0), 0.0, sin(b * TAU * 3.0))
	var node: Node3D = entry["node"]
	var splash: Node3D = entry["splash"]
	var leap := minf(s, 1.0)
	var at := spot + dir * (leap - 0.5) * 1.2
	at.y = -0.25 + 0.9 * sin(PI * leap)
	var climb := 0.9 * PI * cos(PI * leap) / FISH_LEAP_S
	node.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, atan2(climb, 1.2 / FISH_LEAP_S)), at)
	node.visible = s < 1.0 and at.y > -0.1
	if s >= 1.6:
		node.position = Vector3(entry["spot"].x, -0.6, entry["spot"].z)
	splash.visible = s < 0.4 or (s > 0.75 and s < 1.6)
	var since := s if s < 0.4 else s - 0.75
	splash.position = spot + dir * (-0.6 if s < 0.4 else 0.6) + Vector3(0.0, 0.02, 0.0)
	splash.scale = Vector3.ONE * lerpf(0.5, 1.4, clampf(since / 0.8, 0.0, 1.0))


## Pseudo-Zufall 0..1 aus Zyklusnummer `n` und `seed_value` (deterministisch, ohne Zustand).
static func _hash(n: float, seed_value: float) -> float:
	return fposmod(sin(n * 12.9898 + seed_value * 78.233) * 43758.5453, 1.0)


## Mönchsgeier in der Thermik über der Mitte der Serpentinen, VULTURE_ABOVE_M über ihrer höchsten Stelle.
func _add_vultures(rng: RandomNumberGenerator) -> void:
	var group := _group("Geier")
	var range_m := world._station_range("serpentinen")
	var centre := Vector3.ZERO
	var count := 0
	var top := -INF
	var d := range_m.x
	while d < range_m.y:
		var p := world.track.position_at(d)
		centre += p
		top = maxf(top, p.y)
		count += 1
		d += 10.0
	centre /= maxf(count, 1)
	centre.y = top + VULTURE_ABOVE_M
	var meshes := _vulture_meshes()
	for k in range(VULTURES):
		var node := Node3D.new()
		node.name = "Geier%d" % (k + 1)
		group.add_child(node)
		_mesh(node, "Rumpf", meshes[0], VISIBLE_M["Geier"])
		var wings: Array[Node3D] = []
		for side in range(2):
			var pivot := Node3D.new()
			pivot.name = ["FluegelR", "FluegelL"][side]
			pivot.position = Vector3(0.14 if side == 0 else -0.14, 0.04, 0.0)
			node.add_child(pivot)
			_mesh(pivot, "Mesh", meshes[1 + side], VISIBLE_M["Geier"])
			wings.append(pivot)
		vultures.append({"node": node, "wings": wings, "centre": centre + Vector3(rng.randf_range(-30.0, 30.0), 0.0,
				rng.randf_range(-30.0, 30.0)), "radius": rng.randf_range(VULTURE_RADII.x, VULTURE_RADII.y),
				"height": rng.randf_range(-15.0, 15.0), "speed": rng.randf_range(8.0, 10.5), "phase": rng.randf() * TAU})


## Geier zur Zeit `t`: kreist gleitend, steigt und sinkt langsam, in die Kurve geneigt; selten ein paar Flügelschläge.
func _soar(vulture: Dictionary, t: float) -> void:
	var r: float = vulture["radius"]
	var speed: float = vulture["speed"]
	var phase: float = vulture["phase"]
	var angle := phase + speed / r * t
	var at: Vector3 = vulture["centre"] + Vector3(cos(angle) * r, vulture["height"] + 8.0 * sin(0.12 * t + phase), sin(angle) * r)
	var heading := Vector3(-sin(angle), 0.0, cos(angle))
	var node: Node3D = vulture["node"]
	node.transform = Transform3D(Basis.looking_at(heading, Vector3.UP) * Basis(Vector3.BACK, -0.3), at)
	var gate := clampf((sin(0.23 * t + phase) - 0.8) * 5.0, 0.0, 1.0)
	var flap := 0.1 + 0.04 * sin(0.9 * t + phase) + gate * 0.4 * sin(3.2 * t + phase)
	vulture["wings"][0].rotation.z = flap
	vulture["wings"][1].rotation.z = -flap


## Schmetterlinge paarweise über Gras am Wegrand (bis BUTTERFLY_ROADSIDE_M von der Straßenmitte), der Flugkreis frei
## von Fahrbahn, Feldern und Fincas.
func _add_butterflies(rng: RandomNumberGenerator, lite: bool) -> void:
	var group := _group("Schmetterlinge")
	var body := _butterfly_body()
	var wing_meshes := {}
	var i := 1
	for station in BUTTERFLY_STATIONS:
		var grass: PackedVector3Array = world.vegetation.placements.get(station, {}).get("Gras", PackedVector3Array()) \
				if world.vegetation != null else PackedVector3Array()
		var spots := 0
		var tries := 0
		while spots < (BUTTERFLY_SPOTS / 2 if lite else BUTTERFLY_SPOTS) and tries < 500 and not grass.is_empty():
			tries += 1
			var base := grass[rng.randi() % grass.size()]
			if world.landmarks.road_clearance(base) > BUTTERFLY_ROADSIDE_M \
					or not allowed(base, BUTTERFLY_LOOP_M + 0.3 + RADIUS_M["Schmetterlinge"]):
				continue
			spots += 1
			var color := rng.randi() % BUTTERFLY_COLORS.size()
			if not wing_meshes.has(color):
				wing_meshes[color] = [_butterfly_wing(BUTTERFLY_COLORS[color], 1.0), _butterfly_wing(BUTTERFLY_COLORS[color], -1.0)]
			for k in range(BUTTERFLY_PAIR):
				var node := Node3D.new()
				node.name = "Schmetterling%d" % i
				group.add_child(node)
				_mesh(node, "Rumpf", body, VISIBLE_M["Schmetterlinge"])
				var wings: Array[Node3D] = []
				for side in range(2):
					var pivot := Node3D.new()
					pivot.name = ["FluegelR", "FluegelL"][side]
					node.add_child(pivot)
					_mesh(pivot, "Mesh", wing_meshes[color][side], VISIBLE_M["Schmetterlinge"])
					wings.append(pivot)
				butterflies.append({"node": node, "wings": wings, "base": base,
						"radius": rng.randf_range(0.4, BUTTERFLY_LOOP_M),
						"height": rng.randf_range(BUTTERFLY_HEIGHT.x, BUTTERFLY_HEIGHT.y),
						"rate": rng.randf_range(0.8, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0), "phase": rng.randf() * TAU})
				i += 1


## Schmetterling zur Zeit `t`: torkelnde Schleifen über seinem Platz, Kopf in Flugrichtung, schneller Flügelschlag.
func _flutter(butterfly: Dictionary, t: float) -> void:
	var at := flutter_point(butterfly, t)
	var ahead := flutter_point(butterfly, t + 0.05) - at
	var node: Node3D = butterfly["node"]
	node.transform = Transform3D(Basis(Vector3.UP, atan2(-ahead.x, -ahead.z)), at)
	var beat := 0.2 + 1.0 * absf(sin(t * 15.0 + butterfly["phase"]))
	butterfly["wings"][0].rotation.z = beat
	butterfly["wings"][1].rotation.z = -beat


## Lage eines Schmetterlings zur Zeit `t` (waagerecht höchstens Flugkreis + 0,3 m um seinen Platz).
static func flutter_point(butterfly: Dictionary, t: float) -> Vector3:
	var p: float = butterfly["phase"]
	var r: float = butterfly["radius"]
	var a: float = p + butterfly["rate"] * t
	return butterfly["base"] + Vector3(cos(a) * r + 0.25 * sin(2.3 * a + p),
			butterfly["height"] + 0.25 * sin(1.7 * t + p) + 0.08 * sin(9.0 * t + p), sin(a) * r * 0.8 + 0.2 * cos(1.9 * a))


## Eidechsen auf der Mauerkrone an Küstenstraße (seeseitig) und Serpentinen (talseitig, in Kehren außen), nicht an den
## Querungen der Ziegen und am Aussichtspunkt.
func _add_lizards(rng: RandomNumberGenerator, lite: bool) -> void:
	var group := _group("Eidechsen")
	var body := _lizard_body()
	var head := _lizard_head()
	var tail_mesh := _lizard_tail()
	var gaps: Array = CROSSINGS_M + [IslandCourse.landmarks()[0]["distance_m"]]
	var i := 1
	for station in LIZARD_EVERY_M:
		var range_m := world._station_range(station)
		var step: float = LIZARD_EVERY_M[station] * (2.0 if lite else 1.0)
		var d := range_m.x + 30.0
		while d < range_m.y - 30.0:
			var path_m := d + rng.randf_range(-15.0, 15.0)
			d += step
			var free := true
			for gap in gaps:
				free = free and absf(path_m - gap) > LIZARD_GAP_M
			if not free:
				continue
			var side := -1.0
			if station == "serpentinen":
				var inner := world._inner_side(path_m)
				side = -inner if inner != 0.0 else world._valley_side(path_m)
			var lizard := _creature(group, "Eidechse%d" % i, "Eidechsen", body, head)
			var tail := Node3D.new()
			tail.name = "Schwanz"
			tail.position = Vector3(0.0, 0.02, 0.075)
			lizard["node"].add_child(tail)
			_mesh(tail, "Mesh", tail_mesh, VISIBLE_M["Eidechsen"])
			lizard["tail"] = tail
			lizard["path_m"] = path_m
			lizard["side"] = side
			lizard["period"] = rng.randf_range(LIZARD_PERIOD.x, LIZARD_PERIOD.y)
			lizard["phase"] = rng.randf() * 10.0
			lizards.append(lizard)
			i += 1


## Eidechse zur Zeit `t`: wendet zu Beginn jedes Zyklus, huscht LIZARD_DASH_M die Mauer entlang (abwechselnd vor und
## zurück), sonnt sich, macht Liegestütze und schaut umher; der Schwanz schlängelt beim Laufen.
func _place_lizard(lizard: Dictionary, t: float) -> void:
	var phase: float = lizard["phase"]
	var cycle: float = t / lizard["period"] + phase
	var n := floorf(cycle)
	var f := cycle - n
	var even := fposmod(n, 2.0) < 1.0
	var dash := smoothstep(0.1, 0.16, f)
	var d: float = lizard["path_m"] + ((dash if even else 1.0 - dash) - 0.5) * LIZARD_DASH_M
	var road := world.track.position_at(d)
	var at := road + world._side_offset(d, lizard["side"] * LIZARD_SIDE_M)
	var push := smoothstep(0.45, 0.5, f) * (1.0 - smoothstep(0.62, 0.67, f))
	at.y = road.y + LIZARD_TOP_M + 0.02 * push * absf(sin(t * 14.0))
	var turn := smoothstep(0.0, 0.1, f)
	var node: Node3D = lizard["node"]
	node.position = at
	node.rotation = Vector3(0.0, world._yaw_at(d) + (lerpf(PI, 0.0, turn) if even else lerpf(0.0, PI, turn)), 0.0)
	var moving := smoothstep(0.08, 0.1, f) * (1.0 - smoothstep(0.16, 0.18, f))
	lizard["head"].rotation = Vector3(0.2 * push, 0.5 * sin(0.6 * t + phase) * (1.0 - moving), 0.0)
	lizard["tail"].rotation = Vector3(0.0, lerpf(0.15 * sin(1.3 * t + phase), 0.6 * sin(t * 40.0), moving), 0.0)


## Einzeltier als Node3D mit Rumpf und Kopf (Pivot am Hals) – {node, head}.
func _creature(parent: Node3D, node_name: String, kind: String, body: Mesh, head: Mesh) -> Dictionary:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	_mesh(node, "Rumpf", body, VISIBLE_M[kind])
	var pivot := Node3D.new()
	pivot.name = "Kopf"
	pivot.position = NECK.get(kind, Vector3.ZERO)
	node.add_child(pivot)
	_mesh(pivot, "Mesh", head, VISIBLE_M[kind])
	return {"node": node, "head": pivot}


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, visible_m: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = visible_m
	parent.add_child(instance)
	return instance


## Rumpf (Blick lokal −z, Füße auf y = 0): Schaf mit Wollbüscheln, Ziege mit Stummelschwanz, Esel mit hellem Bauch und
## Mähne. `legs` = mit Beinen (die Ziegen der Querungen haben eigene, bewegliche Beine).
static func _body_mesh(kind: String, legs: bool) -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	match kind:
		"Schafe":
			var wool := Color(0.9, 0.88, 0.82)
			parts.sphere(1.0, Vector3(0.0, 0.72, 0.0), wool, Basis().scaled(Vector3(0.32, 0.28, 0.52)))
			for lump in [Vector3(-0.13, 0.9, -0.18), Vector3(0.14, 0.9, -0.1), Vector3(0.0, 0.94, 0.14),
					Vector3(-0.15, 0.86, 0.3), Vector3(0.15, 0.85, 0.28)]:
				parts.sphere(0.17, lump, wool.darkened(0.04))
			parts.sphere(0.09, Vector3(0.0, 0.74, 0.52), wool)
		"Ziegen":
			var coat := Color(0.42, 0.3, 0.2)
			parts.box(Vector3(0.34, 0.36, 0.82), Transform3D(Basis(), Vector3(0.0, 0.7, 0.0)), coat)
			parts.box(Vector3(0.3, 0.12, 0.6), Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)), coat.lightened(0.25))
			parts.box(Vector3(0.12, 0.08, 0.4), Transform3D(Basis(), Vector3(0.0, 0.9, 0.0)), Color(0.18, 0.13, 0.09))
			parts.box(Vector3(0.06, 0.16, 0.05), Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.0, 0.92, 0.44)), coat.darkened(0.3))
		"Esel":
			var coat := Color(0.5, 0.46, 0.42)
			parts.sphere(1.0, Vector3(0.0, 1.0, 0.0), coat, Basis().scaled(Vector3(0.3, 0.3, 0.62)))
			parts.sphere(1.0, Vector3(0.0, 0.86, 0.05), Color(0.82, 0.8, 0.76), Basis().scaled(Vector3(0.24, 0.16, 0.45)))
			parts.box(Vector3(0.05, 0.03, 0.55), Transform3D(Basis(), Vector3(0.0, 1.29, 0.0)), Color(0.3, 0.26, 0.23))
	if legs:
		var leg: Array = {"Schafe": [Color(0.2, 0.18, 0.16), 0.5, 0.15, 0.32], "Ziegen": [Color(0.18, 0.13, 0.09), 0.52, 0.13, 0.3],
				"Esel": [Color(0.4, 0.37, 0.34), 0.8, 0.16, 0.42]}[kind]
		for x in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				parts.box(Vector3(0.11 if kind == "Esel" else 0.08, leg[1], 0.11 if kind == "Esel" else 0.08),
						Transform3D(Basis(), Vector3(x * leg[2], leg[1] / 2.0, z * leg[3])), leg[0])
				if kind == "Esel":
					parts.box(Vector3(0.12, 0.08, 0.13), Transform3D(Basis(), Vector3(x * leg[2], 0.04, z * leg[3])), Color(0.18, 0.16, 0.15))
	return parts.commit()


## Kopf (Pivot am Hals, Blick lokal −z): Schaf mit dunklem Gesicht, Ohren und Glocke am Halsband; Ziege mit Hörnern und
## Bart; Esel mit Hals, Mähne, hellem Maul und langen Ohren.
static func _head_mesh(kind: String) -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	match kind:
		"Schafe":
			var face := Color(0.2, 0.18, 0.16)
			parts.sphere(1.0, Vector3(0.0, 0.02, -0.17), face, Basis().scaled(Vector3(0.11, 0.12, 0.19)))
			parts.sphere(0.11, Vector3(0.0, 0.12, -0.07), Color(0.88, 0.86, 0.8))
			for x in [-1.0, 1.0]:
				parts.box(Vector3(0.14, 0.03, 0.06), Transform3D(Basis(Vector3.BACK, x * 0.3), Vector3(x * 0.13, 0.07, -0.08)), face)
			parts.cylinder(0.13, 0.13, 0.04, Vector3(0.0, -0.06, 0.02), Color(0.55, 0.2, 0.15), 8, Basis(Vector3.RIGHT, 0.4))
			parts.cylinder(0.025, 0.05, 0.08, Vector3(0.0, -0.17, -0.04), Color(0.82, 0.64, 0.26), 8)
		"Ziegen":
			var coat := Color(0.42, 0.3, 0.2)
			parts.box(Vector3(0.15, 0.17, 0.32), Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.02, -0.15)), coat.darkened(0.2))
			for x in [-1.0, 1.0]:
				parts.cylinder(0.0, 0.03, 0.28, Vector3(x * 0.05, 0.2, 0.0), Color(0.6, 0.55, 0.45), 5, Basis(Vector3.RIGHT, 0.7))
				parts.box(Vector3(0.14, 0.03, 0.06), Transform3D(Basis(Vector3.BACK, x * 0.4), Vector3(x * 0.12, 0.06, -0.04)), coat)
			parts.cylinder(0.0, 0.035, 0.12, Vector3(0.0, -0.12, -0.26), coat.darkened(0.4), 5, Basis(Vector3.RIGHT, PI))
		"Esel":
			var coat := Color(0.5, 0.46, 0.42)
			var neck := Basis(Vector3.RIGHT, 0.55)
			parts.box(Vector3(0.2, 0.5, 0.28), Transform3D(neck, Vector3(0.0, 0.12, -0.1)), coat)
			parts.box(Vector3(0.06, 0.5, 0.06), Transform3D(neck, Vector3(0.0, 0.2, 0.03)), Color(0.22, 0.19, 0.17))
			parts.box(Vector3(0.22, 0.24, 0.46), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.0, 0.34, -0.4)), coat)
			parts.box(Vector3(0.2, 0.18, 0.14), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0.0, 0.25, -0.62)), Color(0.84, 0.82, 0.78))
			for x in [-1.0, 1.0]:
				parts.box(Vector3(0.07, 0.34, 0.04), Transform3D(Basis(Vector3.BACK, -x * 0.35), Vector3(x * 0.1, 0.62, -0.26)), coat.darkened(0.15))
	return parts.commit()


## Katze (Blick lokal −z): sitzend aufrecht mit Vorderpfoten, oder stehend mit vier Beinen.
static func _cat_body(color: Color, sitting: bool) -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	if sitting:
		parts.sphere(1.0, Vector3(0.0, 0.15, 0.03), color, Basis(Vector3.RIGHT, -0.35).scaled(Vector3(0.1, 0.15, 0.11)))
		parts.sphere(1.0, Vector3(0.0, 0.07, 0.08), color, Basis().scaled(Vector3(0.12, 0.08, 0.12)))
		for x in [-1.0, 1.0]:
			parts.box(Vector3(0.035, 0.18, 0.04), Transform3D(Basis(), Vector3(x * 0.04, 0.09, -0.07)), color.lightened(0.08))
	else:
		parts.sphere(1.0, Vector3(0.0, 0.2, 0.0), color, Basis().scaled(Vector3(0.09, 0.09, 0.22)))
		for x in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				parts.box(Vector3(0.035, 0.18, 0.04), Transform3D(Basis(), Vector3(x * 0.05, 0.09, z * 0.14)), color)
	return parts.commit()


static func _cat_head(color: Color) -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.sphere(1.0, Vector3(0.0, 0.03, -0.02), color, Basis().scaled(Vector3(0.075, 0.068, 0.07)))
	parts.sphere(0.03, Vector3(0.0, 0.01, -0.085), color.lightened(0.15))
	for x in [-1.0, 1.0]:
		parts.cylinder(0.0, 0.028, 0.06, Vector3(x * 0.042, 0.1, -0.01), color.darkened(0.1), 4)
		parts.sphere(0.011, Vector3(x * 0.028, 0.045, -0.083), Color(0.75, 0.7, 0.2))
	return parts.commit()


## Delfin (Blick lokal −z, Mitte im Rumpf, ~2,6 m lang): grauer Rücken, heller Bauch, Schnauze, Finne, Flipper, Fluke.
static func _dolphin_mesh() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	var back := Color(0.4, 0.45, 0.5)
	parts.sphere(1.0, Vector3.ZERO, back, Basis().scaled(Vector3(0.32, 0.34, 1.15)))
	parts.sphere(1.0, Vector3(0.0, -0.1, -0.1), Color(0.8, 0.82, 0.84), Basis().scaled(Vector3(0.27, 0.24, 0.9)))
	parts.cylinder(0.05, 0.1, 0.4, Vector3(0.0, -0.05, -1.25), back.lightened(0.1), 6, Basis(Vector3.RIGHT, -PI / 2.0))
	parts.box(Vector3(0.06, 0.35, 0.3), Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, 0.38, 0.15)), back.darkened(0.15))
	for x in [-1.0, 1.0]:
		parts.box(Vector3(0.35, 0.04, 0.16), Transform3D(Basis(Vector3.BACK, x * 0.4), Vector3(x * 0.3, -0.18, -0.35)), back)
	parts.sphere(1.0, Vector3(0.0, 0.0, 1.1), back, Basis().scaled(Vector3(0.12, 0.14, 0.35)))
	parts.box(Vector3(0.8, 0.05, 0.25), Transform3D(Basis(), Vector3(0.0, 0.0, 1.4)), back.darkened(0.15))
	return parts.commit()


## Fisch (Blick lokal −z, ~0,55 m): silbern mit dunklem Rücken und Schwanzflosse.
static func _fish_mesh() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.sphere(1.0, Vector3.ZERO, Color(0.8, 0.82, 0.86), Basis().scaled(Vector3(0.06, 0.1, 0.25)))
	parts.sphere(1.0, Vector3(0.0, 0.035, 0.0), Color(0.32, 0.4, 0.48), Basis().scaled(Vector3(0.045, 0.06, 0.21)))
	parts.box(Vector3(0.012, 0.15, 0.1), Transform3D(Basis(), Vector3(0.0, 0.0, 0.28)), Color(0.55, 0.6, 0.66))
	return parts.commit()


## Spritzer auf dem Wasser: flacher weißer Kranz mit Tropfen.
static func _splash_mesh() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	var white := Color(0.95, 0.97, 1.0)
	parts.sphere(1.0, Vector3.ZERO, white, Basis().scaled(Vector3(0.35, 0.05, 0.35)))
	for k in range(6):
		var a := k * TAU / 6.0
		parts.sphere(0.05, Vector3(cos(a) * 0.3, 0.1 + (k % 2) * 0.12, sin(a) * 0.3), white)
	return parts.commit()


## [Rumpf, Flügel rechts, Flügel links] eines Mönchsgeiers (Blick lokal −z, ~3,8 m Spannweite, Flügel ab der
## Rumpfseite): fast schwarz, Halskrause, heller nackter Kopf mit dunklem Schnabel, breite Flügel mit gespreizten
## Handschwingen, kurzer Keilschwanz.
static func _vulture_meshes() -> Array:
	var dark := Color(0.16, 0.13, 0.11)
	var body := IslandLandmarks.Parts.new()
	body.sphere(1.0, Vector3.ZERO, dark, Basis().scaled(Vector3(0.22, 0.2, 0.6)))
	body.sphere(0.16, Vector3(0.0, 0.05, -0.5), Color(0.33, 0.26, 0.2))
	body.sphere(0.1, Vector3(0.0, 0.06, -0.68), Color(0.66, 0.62, 0.62))
	body.cylinder(0.0, 0.045, 0.14, Vector3(0.0, 0.04, -0.82), Color(0.2, 0.2, 0.22), 5, Basis(Vector3.RIGHT, -PI / 2.0))
	body.box(Vector3(0.42, 0.04, 0.35), Transform3D(Basis(), Vector3(0.0, 0.0, 0.62)), dark)
	var wings := []
	for side in [1.0, -1.0]:
		var wing := IslandLandmarks.Parts.new()
		wing.box(Vector3(0.9, 0.05, 0.62), Transform3D(Basis(), Vector3(side * 0.45, 0.0, 0.0)), dark)
		wing.box(Vector3(0.7, 0.045, 0.52), Transform3D(Basis(Vector3.UP, side * 0.08), Vector3(side * 1.25, 0.0, 0.02)), dark.darkened(0.2))
		for k in range(5):
			wing.box(Vector3(0.38, 0.03, 0.07), Transform3D(Basis(Vector3.UP, side * (k - 2) * 0.13),
					Vector3(side * 1.75, 0.0, -0.18 + k * 0.09)), Color(0.08, 0.07, 0.06))
		wings.append(wing.commit())
	return [body.commit(), wings[0], wings[1]]


## Schmetterling: dünner dunkler Leib (Blick lokal −z, ~6 cm).
static func _butterfly_body() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.cylinder(0.008, 0.008, 0.06, Vector3.ZERO, Color(0.12, 0.1, 0.08), 4, Basis(Vector3.RIGHT, PI / 2.0))
	parts.sphere(0.011, Vector3(0.0, 0.0, -0.036), Color(0.12, 0.1, 0.08))
	return parts.commit()


## Flügelpaar einer Seite (`side` 1 rechts, −1 links; Pivot am Leib): Vorder- und Hinterflügel mit dunkler Spitze.
static func _butterfly_wing(color: Color, side: float) -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.box(Vector3(0.09, 0.004, 0.06), Transform3D(Basis(), Vector3(side * 0.047, 0.0, -0.01)), color)
	parts.box(Vector3(0.065, 0.004, 0.05), Transform3D(Basis(), Vector3(side * 0.036, 0.0, 0.03)), color.darkened(0.12))
	parts.box(Vector3(0.025, 0.005, 0.03), Transform3D(Basis(), Vector3(side * 0.08, 0.0, -0.022)), Color(0.12, 0.1, 0.08))
	return parts.commit()


## Eidechse (Blick lokal −z, Bauch auf y = 0): grün-brauner Rumpf mit dunklen Flecken und gespreizten Beinen.
static func _lizard_body() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	var skin := Color(0.36, 0.46, 0.2)
	parts.sphere(1.0, Vector3(0.0, 0.02, 0.0), skin, Basis().scaled(Vector3(0.032, 0.02, 0.085)))
	for z in [-0.04, 0.0, 0.04]:
		parts.box(Vector3(0.02, 0.008, 0.015), Transform3D(Basis(), Vector3(0.0, 0.038, z)), skin.darkened(0.45))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			parts.box(Vector3(0.05, 0.01, 0.012), Transform3D(Basis(Vector3.UP, x * z * 0.5), Vector3(x * 0.04, 0.008, z * 0.045)), skin.darkened(0.2))
	return parts.commit()


static func _lizard_head() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.sphere(1.0, Vector3(0.0, 0.0, -0.025), Color(0.4, 0.5, 0.22), Basis().scaled(Vector3(0.022, 0.016, 0.035)))
	return parts.commit()


## Schwanz (Pivot am Rumpfende, nach +z spitz zulaufend).
static func _lizard_tail() -> ArrayMesh:
	var parts := IslandLandmarks.Parts.new()
	parts.cylinder(0.003, 0.015, 0.17, Vector3(0.0, 0.0, 0.085), Color(0.33, 0.4, 0.2), 5, Basis(Vector3.RIGHT, PI / 2.0))
	return parts.commit()
