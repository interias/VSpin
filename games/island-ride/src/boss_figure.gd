## Gestalt eines Bosses (#51) auf der Strecke, aus Grundkörpern im Low-Poly-Stil (eigene Interpretation der Sagen,
## keine Modelle von außen): **Tramuntana** als Sturmgeist – eine Wolkengestalt mit Gesicht und kreisenden Windringen,
## die über der Straße schwebt und Böen von vorn auf den Fahrer bläst (Windstreifen); **Drac de na Coca** als Drache mit
## Flügeln, Stachelkamm und Feueratem, der dem Fahrer zugewandt auf der Straße steht; **Dimonis** als Gruppe von drei
## Teufelsgestalten der Dorffeste (rote Masken mit Hörnern, schwarze Kostüme mit Flammen, Gabel), die vor dem Fahrer
## davonspringen. Im Kampf steht der Boss voraus (`follow`, Abstand nach Gestalt bzw. bei einer Jagd nach ihrem Stand)
## und wird mit sinkendem Lebensbalken kleiner. Besiegt (`defeat`) sinkt er in sich zusammen und verschwindet; entkommt er
## (`escape`), zieht er davon (voraus und in die Höhe). Reine Anzeige (ADR-0010). Hängt am Track (lokale Pfadkoordinaten),
## in jeder Richtung (#34).
class_name BossFigure
extends Node3D

const TRAMUNTANA := "tramuntana"
const DRAC := "drac"
const DIMONIS := "dimonis"
const KINDS := [TRAMUNTANA, DRAC, DIMONIS]
## Zustände: im Kampf, besiegt (sinkt zusammen), entkommt (zieht davon); "" = nicht zu sehen.
const FIGHT := "fight"
const DEFEATED := "defeated"
const ESCAPING := "escaping"
## Abstand voraus (m) im Kampf je Gestalt und Höhe über der Straße (m).
const AHEAD_M := {TRAMUNTANA: 30.0, DRAC: 24.0, DIMONIS: 16.0}
const LIFT_M := {TRAMUNTANA: 6.0, DRAC: 0.0, DIMONIS: 0.0}
## Grundgröße je Gestalt (der Drache ist der große Gegner).
const SCALE := {TRAMUNTANA: 1.0, DRAC: 1.6, DIMONIS: 1.15}
## Bei einer Jagd: Abstand voraus beim Stand 0 (entwischt) und 1 (eingeholt).
const CHASE_FAR_M := 42.0
const CHASE_NEAR_M := 7.0
## Nachführen des Abstands (m/s); Abziehen beim Entkommen (m/s voraus, m/s nach oben) und wie lange (s); Zusammensinken (s).
const FOLLOW_MPS := 12.0
const ESCAPE_MPS := 18.0
const ESCAPE_RISE_MPS := 4.0
const ESCAPE_S := 3.0
const DEFEAT_S := 1.6
## Größe bei leerem Lebensbalken (Anteil der vollen Größe).
const SMALLEST := 0.7
## Windstreifen der Tramuntana: Anzahl, Tempo (Anteil des Wegs Boss → Fahrer je s; bei einer Böe schneller).
const GUSTS := 12
const GUST_RATE := 0.45
const GUST_RATE_STRONG := 1.1

const COLOR_CLOUD := Color(0.86, 0.89, 0.93)
const COLOR_CLOUD_DARK := Color(0.52, 0.57, 0.66)
const COLOR_WIND_EYE := Color(0.65, 0.9, 1.0)
const COLOR_DRAGON := Color(0.24, 0.46, 0.22)
const COLOR_DRAGON_DARK := Color(0.13, 0.27, 0.13)
const COLOR_BELLY := Color(0.78, 0.72, 0.42)
const COLOR_WING := Color(0.52, 0.16, 0.12)
const COLOR_FIRE := Color(1.0, 0.36, 0.06)
const COLOR_EYE := Color(1.0, 0.85, 0.2)
const COLOR_HORN := Color(0.9, 0.86, 0.72)
const COLOR_COSTUME := Color(0.07, 0.07, 0.08)
const COLOR_MASK := Color(0.72, 0.1, 0.07)
const COLOR_FLAME := Color(0.95, 0.42, 0.08)
const COLOR_FORK := Color(0.35, 0.33, 0.3)

## Gestalt (KINDS), Zustand, angezeigter Abstand voraus (m) und dessen Ziel, Lebensbalken, Böe aktiv.
var kind := ""
var state := ""
var ahead_m := 0.0
var target_ahead_m := 0.0
var health := 1.0
var gusting := false
## Fahrtposition, an der ein besiegter Boss zusammensinkt (er bleibt dort stehen).
var anchor_m := NAN

var _track: Track
var _rider_m := 0.0
var _time := 0.0
var _ended_s := 0.0
var _lift := 0.0
var _figure: Node3D
var _looks := {}
var _parts := {}
var _gusts: Array[MeshInstance3D] = []
var _gust_t: Array[float] = []


func _init() -> void:
	name = "BossFigure"
	_figure = Node3D.new()
	_figure.name = "Figure"
	add_child(_figure)
	_build_tramuntana()
	_build_drac()
	_build_dimonis()
	_build_gusts()
	reset()


## Kampf beginnt: Gestalt `boss_kind` (KINDS) im Abstand ihrer Art voraus.
func appear(boss_kind: String) -> void:
	kind = boss_kind if boss_kind in KINDS else TRAMUNTANA
	state = FIGHT
	health = 1.0
	gusting = false
	anchor_m = NAN
	ahead_m = AHEAD_M[kind]
	target_ahead_m = ahead_m
	_lift = LIFT_M[kind]
	for id in _looks:
		_looks[id].visible = id == kind
	_figure.scale = Vector3.ONE
	_figure.rotation = Vector3.ZERO
	visible = true


## Im Kampf je Anzeigeschritt: Fahrer bei `rider_m` auf `track`, Abstand voraus `ahead` (m), Lebensbalken `life`, Böe `gust`.
func follow(track: Track, rider_m: float, ahead: float, life: float, gust: bool) -> void:
	_track = track
	_rider_m = rider_m
	if state != FIGHT:
		return
	target_ahead_m = ahead
	health = clampf(life, 0.0, 1.0)
	gusting = gust
	_apply()


## Fahrerposition nachführen (nach dem Kampf, solange die Gestalt noch zu sehen ist).
func track_rider(rider_m: float) -> void:
	_rider_m = rider_m


## Besiegt: an der Stelle zusammensinken und verschwinden.
func defeat() -> void:
	if state != FIGHT:
		return
	state = DEFEATED
	anchor_m = _rider_m + ahead_m
	_ended_s = 0.0


## Entkommen: voraus und in die Höhe davonziehen und verschwinden.
func escape() -> void:
	if state != FIGHT:
		return
	state = ESCAPING
	_ended_s = 0.0


func reset() -> void:
	state = ""
	kind = ""
	health = 1.0
	gusting = false
	anchor_m = NAN
	visible = false
	for gust in _gusts:
		gust.visible = false


## Für Tests und Prüfhilfen: Fahrtposition der Gestalt (NAN ohne Strecke) und ihre Größe.
func ride_m() -> float:
	if _track == null or state == "":
		return NAN
	return anchor_m if state == DEFEATED else _rider_m + ahead_m


func size_factor() -> float:
	return _figure.scale.x


func _process(delta: float) -> void:
	if state == "":
		return
	_time += delta
	match state:
		FIGHT:
			ahead_m = move_toward(ahead_m, target_ahead_m, FOLLOW_MPS * delta)
		ESCAPING:
			_ended_s += delta
			ahead_m += ESCAPE_MPS * delta
			if kind != DIMONIS:
				_lift += ESCAPE_RISE_MPS * delta
			if _ended_s >= ESCAPE_S:
				reset()
				return
		DEFEATED:
			_ended_s += delta
			if _ended_s >= DEFEAT_S:
				reset()
				return
	var rate := GUST_RATE_STRONG if gusting else GUST_RATE
	for i in range(_gust_t.size()):
		_gust_t[i] = fposmod(_gust_t[i] + rate * delta, 1.0)
	_animate()
	_apply()


func _apply() -> void:
	if _track == null or state == "":
		return
	var at := ride_m()
	var a := _track.ride_position_at(at - 1.0)
	var b := _track.ride_position_at(at + 1.0)
	var travel := atan2(-(b.x - a.x), -(b.z - a.z))  # Blick in Fahrtrichtung (wie der Verfolger)
	# Tramuntana und Drache sehen den Fahrer an, die Dimonis laufen voraus davon.
	_figure.rotation.y = travel if kind == DIMONIS else travel + PI
	var bob := 0.0
	if kind == TRAMUNTANA:
		bob = sin(_time * 1.3) * 0.4
	elif kind == DRAC:
		bob = absf(sin(_time * 2.0)) * 0.12
	_figure.position = _track.ride_position_at(at) + Vector3.UP * (_lift + bob)
	var size := lerpf(SMALLEST, 1.0, health) * float(SCALE.get(kind, 1.0))
	if state == DEFEATED:
		var k := clampf(_ended_s / DEFEAT_S, 0.0, 1.0)
		size *= 1.0 - k
		_figure.position += Vector3.DOWN * k * 1.5
		_figure.rotation.y += k * TAU
	_figure.scale = Vector3.ONE * maxf(size, 0.001)
	_place_gusts(at)


func _animate() -> void:
	match kind:
		TRAMUNTANA:
			_parts["ring_a"].rotation.y = _time * 1.6
			_parts["ring_b"].rotation.y = -_time * 1.1
			_parts["mouth"].scale = Vector3.ONE * (1.0 + 0.25 * sin(_time * (8.0 if gusting else 3.0)))
		DRAC:
			var flap := sin(_time * (6.0 if gusting else 3.5)) * 0.55
			_parts["wing_l"].rotation.z = -0.35 - flap  # Flügel gehoben, schlagend
			_parts["wing_r"].rotation.z = 0.35 + flap
			var flame := 0.75 + 0.35 * absf(sin(_time * 9.0))
			_parts["fire"].scale = Vector3(flame, flame, flame * (1.4 if gusting else 1.0))
		DIMONIS:
			for i in range(3):
				var devil: Node3D = _parts["devil_%d" % i]
				devil.position.y = absf(sin(_time * 5.5 + i * 2.1)) * 0.45
				devil.rotation.z = sin(_time * 5.5 + i * 2.1) * 0.12


## Windstreifen der Tramuntana: fliegen von der Wolke auf den Fahrer zu (bei einer Böe schneller), sonst unsichtbar.
func _place_gusts(at: float) -> void:
	var shown := kind == TRAMUNTANA and state == FIGHT
	for i in range(_gusts.size()):
		var gust := _gusts[i]
		gust.visible = shown
		if not shown:
			continue
		var t := _gust_t[i]
		var m := lerpf(at - 2.0, _rider_m - 4.0, t)
		var a := _track.ride_position_at(m - 0.5)
		var b := _track.ride_position_at(m + 0.5)
		var forward := (b - a).normalized()
		var side := forward.cross(Vector3.UP).normalized()
		var offset := float(i % 6) - 2.5
		var height := 0.8 + float((i * 7) % 5) * 0.8 + (1.0 - t) * _lift * 0.6
		gust.position = _track.ride_position_at(m) + side * offset * 1.4 + Vector3.UP * height
		gust.look_at(gust.position + forward, Vector3.UP)
		gust.scale = Vector3(1.0, 1.0, 0.6 + (1.6 if gusting else 0.8) * sin(t * PI))


func _build_tramuntana() -> void:
	var look := _look(TRAMUNTANA)
	var puffs := [[Vector3(0.0, 0.0, 0.0), 2.2, COLOR_CLOUD], [Vector3(-1.9, 0.4, 0.4), 1.6, COLOR_CLOUD],
			[Vector3(1.9, 0.3, 0.3), 1.7, COLOR_CLOUD], [Vector3(-1.0, 1.6, 0.2), 1.4, COLOR_CLOUD],
			[Vector3(1.1, 1.7, 0.3), 1.3, COLOR_CLOUD], [Vector3(0.0, -1.3, 0.5), 1.5, COLOR_CLOUD_DARK],
			[Vector3(-2.8, -0.6, 0.8), 1.0, COLOR_CLOUD_DARK], [Vector3(2.9, -0.5, 0.8), 1.0, COLOR_CLOUD_DARK],
			[Vector3(0.0, 2.4, 0.6), 1.0, COLOR_CLOUD]]
	for i in range(puffs.size()):
		var sphere := SphereMesh.new()
		sphere.radius = puffs[i][1]
		sphere.height = puffs[i][1] * 1.7
		sphere.radial_segments = 7
		sphere.rings = 4
		_add(look, "Wolke%d" % i, sphere, puffs[i][0], puffs[i][2])
	for side in [-1.0, 1.0]:
		var eye := BoxMesh.new()
		eye.size = Vector3(0.5, 0.28, 0.2)
		_add(look, "Auge" + ("L" if side < 0.0 else "R"), eye, Vector3(side * 0.75, 0.55, -2.05), COLOR_WIND_EYE, Vector3.ZERO,
				true)
		var brow := BoxMesh.new()
		brow.size = Vector3(0.7, 0.14, 0.2)
		_add(look, "Braue" + ("L" if side < 0.0 else "R"), brow, Vector3(side * 0.75, 0.9, -2.0), COLOR_CLOUD_DARK,
				Vector3(0.0, 0.0, side * 0.3))
	var mouth := SphereMesh.new()
	mouth.radius = 0.42
	mouth.height = 0.6
	mouth.radial_segments = 8
	mouth.rings = 3
	_parts["mouth"] = _add(look, "Mund", mouth, Vector3(0.0, -0.35, -2.05), Color(0.2, 0.24, 0.32))
	for ring_name in ["ring_a", "ring_b"]:
		var holder := Node3D.new()
		holder.name = ring_name
		holder.rotation = Vector3(0.35 if ring_name == "ring_a" else -0.5, 0.0, 0.25 if ring_name == "ring_a" else -0.2)
		look.add_child(holder)
		var torus := TorusMesh.new()
		torus.inner_radius = 3.3 if ring_name == "ring_a" else 3.9
		torus.outer_radius = torus.inner_radius + 0.18
		torus.rings = 16
		torus.ring_segments = 4
		_add(holder, "Wind", torus, Vector3.ZERO, Color(0.9, 0.95, 1.0, 0.75), Vector3.ZERO, false, true)
		_parts[ring_name] = holder


func _build_drac() -> void:
	var look := _look(DRAC)
	_box(look, "Rumpf", Vector3(1.7, 1.5, 3.6), Vector3(0.0, 1.6, 0.4), COLOR_DRAGON)
	_box(look, "Bauch", Vector3(1.3, 0.5, 3.0), Vector3(0.0, 0.95, 0.4), COLOR_BELLY)
	_box(look, "Hals", Vector3(0.9, 0.9, 1.6), Vector3(0.0, 2.6, -1.6), COLOR_DRAGON, Vector3(0.6, 0.0, 0.0))
	_box(look, "Kopf", Vector3(1.0, 0.8, 1.5), Vector3(0.0, 3.3, -2.5), COLOR_DRAGON)
	_box(look, "Kiefer", Vector3(0.8, 0.3, 1.2), Vector3(0.0, 2.85, -2.75), COLOR_DRAGON_DARK, Vector3(-0.25, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		_box(look, "Auge" + tag, Vector3(0.18, 0.14, 0.1), Vector3(side * 0.32, 3.5, -3.26), COLOR_EYE, Vector3.ZERO, true)
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.14
		horn.height = 0.8
		horn.radial_segments = 5
		_add(look, "Horn" + tag, horn, Vector3(side * 0.35, 3.9, -2.2), COLOR_HORN, Vector3(0.6, 0.0, -side * 0.3))
		for z in [-0.6, 1.4]:
			_box(look, "Bein%s%s" % [tag, "V" if z < 0.0 else "H"], Vector3(0.45, 1.1, 0.5), Vector3(side * 0.75, 0.55, z),
					COLOR_DRAGON_DARK)
		var wing := Node3D.new()
		wing.name = "wing_" + ("l" if side < 0.0 else "r")
		wing.position = Vector3(side * 0.8, 2.3, 0.0)
		look.add_child(wing)
		var membrane := PrismMesh.new()
		membrane.size = Vector3(3.2, 0.12, 2.4)
		membrane.left_to_right = 0.0 if side > 0.0 else 1.0
		_add(wing, "Flughaut", membrane, Vector3(side * 1.6, 0.0, 0.3), COLOR_WING)
		_box(wing, "Knochen", Vector3(3.3, 0.16, 0.16), Vector3(side * 1.65, 0.05, -0.85), COLOR_DRAGON_DARK)
		_parts[wing.name] = wing
	for i in range(5):
		var spike := PrismMesh.new()
		spike.size = Vector3(0.12, 0.55, 0.5)
		_add(look, "Stachel%d" % i, spike, Vector3(0.0, 2.6, -0.8 + i * 0.6), COLOR_BELLY)
	for i in range(4):
		var width := 0.9 - i * 0.18
		_box(look, "Schwanz%d" % i, Vector3(width, width * 0.8, 1.0), Vector3(0.0, 1.4 - i * 0.25, 2.6 + i * 0.95),
				COLOR_DRAGON, Vector3(0.12 * i, 0.0, 0.0))
	var fire := CylinderMesh.new()
	fire.top_radius = 0.42
	fire.bottom_radius = 0.06
	fire.height = 1.8
	fire.radial_segments = 6
	var holder := Node3D.new()
	holder.name = "fire"
	holder.position = Vector3(0.0, 2.85, -3.35)
	holder.rotation.x = -0.55  # zur Straße vor ihm geneigt, das Gesicht bleibt frei
	look.add_child(holder)
	_add(holder, "Feuer", fire, Vector3(0.0, 0.0, -0.9), Color(COLOR_FIRE, 0.85), Vector3(-PI / 2.0, 0.0, 0.0), false,
			true)
	_parts["fire"] = holder


func _build_dimonis() -> void:
	var look := _look(DIMONIS)
	var spots := [Vector3(-1.5, 0.0, 0.6), Vector3(0.0, 0.0, -0.4), Vector3(1.5, 0.0, 0.8)]
	for i in range(spots.size()):
		var devil := Node3D.new()
		devil.name = "devil_%d" % i
		look.add_child(devil)
		var root := Node3D.new()
		root.position = spots[i]
		devil.add_child(root)
		var robe := CylinderMesh.new()
		robe.top_radius = 0.28
		robe.bottom_radius = 0.42
		robe.height = 1.2
		robe.radial_segments = 6
		_add(root, "Kostuem", robe, Vector3(0.0, 1.0, 0.0), COLOR_COSTUME)
		for k in range(3):
			_box(root, "Flamme%d" % k, Vector3(0.11, 0.5 if k == 1 else 0.32, 0.05),
					Vector3(-0.15 + k * 0.15, 0.78 if k == 1 else 0.7, -0.38), COLOR_FLAME, Vector3(0.0, 0.0, -0.35 + k * 0.35),
					true)  # Flammenzungen, zur Mitte geneigt
		_box(root, "Maske", Vector3(0.44, 0.5, 0.4), Vector3(0.0, 1.85, 0.0), COLOR_MASK)
		_box(root, "Maul", Vector3(0.3, 0.08, 0.06), Vector3(0.0, 1.72, -0.21), Color(0.95, 0.9, 0.8))
		_box(root, "Maehne", Vector3(0.56, 0.36, 0.3), Vector3(0.0, 1.9, 0.18), COLOR_COSTUME)
		for side in [-1.0, 1.0]:
			var tag := "L" if side < 0.0 else "R"
			var horn := CylinderMesh.new()
			horn.top_radius = 0.0
			horn.bottom_radius = 0.08
			horn.height = 0.45
			horn.radial_segments = 5
			_add(root, "Horn" + tag, horn, Vector3(side * 0.18, 2.25, 0.0), COLOR_HORN, Vector3(0.0, 0.0, -side * 0.35))
			_box(root, "Auge" + tag, Vector3(0.09, 0.06, 0.04), Vector3(side * 0.11, 1.92, -0.21), COLOR_EYE, Vector3.ZERO,
					true)
			_box(root, "Arm" + tag, Vector3(0.14, 0.62, 0.14), Vector3(side * 0.38, 1.35, 0.0), COLOR_COSTUME,
					Vector3(0.0, 0.0, side * 0.5))
			_box(root, "Bein" + tag, Vector3(0.16, 0.45, 0.16), Vector3(side * 0.14, 0.22, 0.0), COLOR_COSTUME)
		if i != 1:
			_box(root, "Stiel", Vector3(0.06, 1.8, 0.06), Vector3(0.55, 1.3, 0.0), COLOR_FORK)
			for k in range(3):
				_box(root, "Zinke%d" % k, Vector3(0.05, 0.3, 0.05), Vector3(0.45 + k * 0.1, 2.3, 0.0), COLOR_FORK)
			_box(root, "Querstueck", Vector3(0.3, 0.05, 0.05), Vector3(0.55, 2.16, 0.0), COLOR_FORK)
		_parts[devil.name] = devil


func _build_gusts() -> void:
	for i in range(GUSTS):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.07, 3.0)
		var gust := MeshInstance3D.new()
		gust.name = "Boe%d" % i
		gust.mesh = mesh
		gust.material_override = _material(Color(0.92, 0.96, 1.0, 0.55), false, true)
		gust.visible = false
		add_child(gust)
		_gusts.append(gust)
		_gust_t.append(float(i) / GUSTS)


func _look(id: String) -> Node3D:
	var look := Node3D.new()
	look.name = id.capitalize()
	look.visible = false
	_figure.add_child(look)
	_looks[id] = look
	return look


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, color: Color, rot: Vector3 = Vector3.ZERO,
		glow: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, node_name, mesh, at, color, rot, glow)


func _add(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3, color: Color, rot: Vector3 = Vector3.ZERO,
		glow: bool = false, see_through: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material(color, glow, see_through)
	instance.position = at
	instance.rotation = rot
	parent.add_child(instance)
	return instance


static func _material(color: Color, glow: bool, see_through: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
