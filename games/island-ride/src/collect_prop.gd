## Darstellung des Sammelns (#48): goldene Sammelobjekte (kleine Kristalle aus Grundkörpern) auf und neben der Straße, dort
## wo der Fahrer zu ihrem Zeitpunkt ankommt (TimedMarkers/GatePlacement, seitlich nach `offsets`), und ein flacher
## türkiser Ring um den Fahrer, dessen Radius der Magnetradius ist (er wächst und schrumpft mit der Kadenz). Gezeigt werden
## die nächsten fünf Objekte; ein eingesammeltes verschwindet beim Vorbeifahren, ein liegengebliebenes wird grau und
## bleibt bis `keep_behind_m` hinter dem Fahrer. Das Zieltor bleibt (lockerer Abschnitt, Ende nach dem letzten Objekt).
## Nur Anzeige (ADR-0010).
class_name CollectProp
extends ArcadeProp

## So viele offene Objekte stehen höchstens im Bild.
const AHEAD := 5
## Höhe der Objekte über der Straße (m) und Größe.
const HEIGHT_M := 0.9
const SIZE_M := 0.55
const COLOR_GOLD := Color(1.0, 0.8, 0.2)
const COLOR_MISSED := Color(0.5, 0.5, 0.48)
const COLOR_RING := Color(0.25, 0.9, 0.85, 0.55)
## Anteil, um den der Ring je Anzeigeschritt zum Radius des Bausteins nachrückt.
const RING_FOLLOW := 0.3

var items: Array[MeshInstance3D] = []
var markers := TimedMarkers.new()
## Der Ring um den Fahrer und sein angezeigter Radius (m).
var ring: MeshInstance3D
var ring_radius_m := 0.0

var _block: Collect = null
var _gold: StandardMaterial3D
var _grey: StandardMaterial3D
var _offset_m: Array[float] = []
var _at_m: Array[float] = []


func attach(owner_stage) -> void:
	super(owner_stage)
	_gold = _material(COLOR_GOLD, true)
	_grey = _material(COLOR_MISSED, false)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.96
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 6
	ring = MeshInstance3D.new()
	ring.name = "Magnetring"
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_RING
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	ring.visible = false
	stage.track.add_child(ring)


func begin(block: ChallengeBlock) -> void:
	_block = block as Collect
	markers.reset(_block.count())
	ring_radius_m = 0.0
	_offset_m.clear()
	_at_m.clear()
	while items.size() < _block.count():
		var item := _new_item(items.size())
		stage.track.add_child(item)
		items.append(item)
	for i in range(items.size()):
		items[i].visible = false
		_at_m.append(NAN)
		_offset_m.append(_block.offsets[i] if i < _block.count() else 0.0)
		items[i].material_override = _gold


func follow(block: ChallengeBlock, _finish_at: float) -> bool:
	var collect := block as Collect
	if collect != _block:
		return false
	var d: float = stage.distance_m
	markers.measure(d, collect.elapsed_s)
	var first := collect.next_open()
	for i in range(collect.count()):
		match collect.state_of(i):
			Collect.PENDING:
				if first >= 0 and i < first + AHEAD:
					_put(i, markers.position_of(i, d, maxf(collect.pass_time(i) - collect.elapsed_s, 0.0)))
					items[i].visible = markers.placements[i].shown(d) and _behind_ok(i)
				else:
					items[i].visible = false
			Collect.COLLECTED:
				items[i].visible = false
			_:
				_put(i, markers.position_of(i, d, 0.0))
				items[i].material_override = _grey
				items[i].visible = _behind_ok(i)
	# Ring: mit dem Radius des Bausteins, weich nachgeführt.
	ring_radius_m = lerpf(ring_radius_m, collect.radius_m, RING_FOLLOW)
	if absf(ring_radius_m - collect.radius_m) < 0.02:
		ring_radius_m = collect.radius_m
	_ring(d)
	return false


func idle() -> void:
	for i in range(items.size()):
		if items[i].visible:
			items[i].visible = _behind_ok(i)
	ring.visible = false


func end(block: ChallengeBlock) -> void:
	var collect := block as Collect
	if collect != _block:
		return
	for i in range(collect.count()):
		if collect.state_of(i) == Collect.PENDING:
			items[i].visible = false
	ring.visible = false


func clear() -> void:
	_block = null
	hide()


func hide() -> void:
	for item in items:
		item.visible = false
	ring.visible = false


## Ring flach auf der Straße um die Fahrtposition `d`, Radius = angezeigter Magnetradius (unsichtbar bei 0).
func _ring(d: float) -> void:
	ring.visible = ring_radius_m > 0.05
	if not ring.visible:
		return
	ring.position = stage.track.ride_position_at(d) + Vector3.UP * 0.15
	ring.scale = Vector3(ring_radius_m, 1.0, ring_radius_m)


## Objekt `i` an Fahrtposition `at_m`, seitlich um seinen Abstand versetzt (rechts positiv).
func _put(i: int, at_m: float) -> void:
	if is_nan(at_m) or is_equal_approx(_at_m[i], at_m):
		return
	_at_m[i] = at_m
	var track: Track = stage.track
	var forward := (track.ride_position_at(at_m + 1.0) - track.ride_position_at(at_m - 1.0)).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	items[i].position = track.ride_position_at(at_m) + right * _offset_m[i] + Vector3.UP * HEIGHT_M


func _behind_ok(i: int) -> bool:
	var at := _at_m[i]
	return not is_nan(at) and at > stage.distance_m - stage.keep_behind_m \
			and at - stage.distance_m < stage.track.length_m() - stage.keep_behind_m


## Kristall: zwei Pyramiden Spitze an Spitze (Oktaeder aus Grundkörpern).
func _new_item(index: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "Sammelobjekt%d" % index
	instance.mesh = _crystal()
	instance.material_override = _gold
	instance.visible = false
	return instance


func _crystal() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := SIZE_M * 0.5
	var top := Vector3(0.0, SIZE_M, 0.0)
	var bottom := Vector3(0.0, -SIZE_M, 0.0)
	var ring_points := [Vector3(r, 0.0, 0.0), Vector3(0.0, 0.0, r), Vector3(-r, 0.0, 0.0), Vector3(0.0, 0.0, -r)]
	for k in range(4):
		var a: Vector3 = ring_points[k]
		var b: Vector3 = ring_points[(k + 1) % 4]
		for tri in [[top, b, a], [bottom, a, b]]:
			for point in tri:
				tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()


func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	return material
