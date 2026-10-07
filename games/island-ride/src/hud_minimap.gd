## Minikarte im HUD (G5): Insel von oben (Norden oben), Strecke als Linie, Start/Ziel, Landmarken als kleine
## Rauten und der Fahrer als Pfeil in Fahrtrichtung.
## Insel und Strecke werden nur bei `setup()` und Größenänderung gezeichnet (das Inselbild einmal je Gelände
## berechnet und gecacht); pro Frame bewegt sich nur der Fahrer-Pfeil (eigener Knoten, nur Position/Drehung).
##   setup(track, world)   Strecke abtasten; mit Insel-Welt (sonst null) Inselbild und Landmarken
##   show_rider(d)         Fahrer an Streckenposition d (innerhalb der Runde)
##   map_point(...)        reine Rechnung Weltposition (x, z) → Punkt auf der Karte (Tests)
class_name HudMinimap
extends Control

## Abtastabstand der Streckenlinie (m) und Zellgröße des Inselbilds (m).
const ROUTE_STEP_M := 15.0
const LAND_CELL_M := 20.0
## Kartenausschnitt mit Insel-Welt: die ganze Insel (IslandTerrain, ~2,1 × 3,1 km) mit etwas Meer.
const ISLAND_BOUNDS := Rect2(-1120.0, -1600.0, 2240.0, 3200.0)
## Rand innerhalb des Controls (px).
const PAD_PX := 6.0
const ROUTE_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const ROUTE_SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const LANDMARK_COLOR := Color(0.98, 0.84, 0.42)
const RIDER_COLOR := Color(1.0, 0.45, 0.3)
const RIDER_SIZE_PX := 18.0

static var _land_texture: ImageTexture = null
static var _land_for: IslandTerrain = null

## Streckenpunkte (x, z) in Weltkoordinaten, geschlossen.
var route := PackedVector2Array()
## Kartenausschnitt in Weltkoordinaten (x, z).
var bounds := Rect2(-1.0, -1.0, 2.0, 2.0)
## Landmarken-Positionen (x, z).
var landmarks := PackedVector2Array()

var _track: Track
var _land: Texture2D = null
var _rider: Control
var _rider_d := 0.0


func _ready() -> void:
	_rider = Control.new()
	_rider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rider.size = Vector2(RIDER_SIZE_PX, RIDER_SIZE_PX)
	_rider.pivot_offset = _rider.size * 0.5
	_rider.draw.connect(_draw_rider)
	add_child(_rider)
	resized.connect(func(): show_rider(_rider_d))


func setup(track: Track, world: IslandWorld = null) -> void:
	_track = track
	route.clear()
	var length := track.length_m()
	var count := maxi(int(ceil(length / ROUTE_STEP_M)), 2)
	for i in range(count + 1):
		var p := track.to_global(track.position_at(length * i / count))
		route.append(Vector2(p.x, p.z))
	landmarks.clear()
	_land = null
	if world != null:
		bounds = ISLAND_BOUNDS
		_land = _land_image(world.terrain)
		var root := world.get_node_or_null("Landmarks")
		if root != null:
			for node in root.get_children():
				if node is Node3D and node.has_meta("landmark_name"):
					landmarks.append(Vector2(node.global_position.x, node.global_position.z))
	else:
		var box := Rect2(route[0], Vector2.ZERO)
		for p in route:
			box = box.expand(p)
		bounds = box.grow(maxf(box.size.x, box.size.y) * 0.06)
	queue_redraw()
	show_rider(_rider_d)


## Punkt auf einer Karte der Größe `area` (px) für die Weltposition `xz`: `bounds` passt mit `pad` Rand
## unverzerrt hinein und wird mittig ausgerichtet; Norden (−z) oben, Osten (+x) rechts.
static func map_point(xz: Vector2, map_bounds: Rect2, area: Vector2, pad: float = PAD_PX) -> Vector2:
	var scale := map_scale(map_bounds, area, pad)
	var offset := (area - map_bounds.size * scale) * 0.5
	return offset + (xz - map_bounds.position) * scale


## Maßstab (px je m) der Karte.
static func map_scale(map_bounds: Rect2, area: Vector2, pad: float = PAD_PX) -> float:
	var room := (area - Vector2(pad, pad) * 2.0).max(Vector2.ONE)
	return minf(room.x / maxf(map_bounds.size.x, 1.0), room.y / maxf(map_bounds.size.y, 1.0))


## Drehung des Fahrer-Pfeils (Spitze lokal nach oben) für die Fahrtrichtung `direction` (x, z).
static func heading_rotation(direction: Vector2) -> float:
	return atan2(direction.x, -direction.y)


## Fahrer an Streckenposition `d`: Pfeil an die Kartenposition, in Fahrtrichtung gedreht.
func show_rider(d: float) -> void:
	_rider_d = d
	if _track == null or _rider == null:
		return
	var here := _track.to_global(_track.position_at(d))
	var ahead := _track.to_global(_track.position_at(d + 3.0))
	var behind := _track.to_global(_track.position_at(d - 3.0))
	var at := map_point(Vector2(here.x, here.z), bounds, size) - _rider.pivot_offset
	var turn := heading_rotation(Vector2(ahead.x - behind.x, ahead.z - behind.z))
	if not _rider.position.is_equal_approx(at) or not is_equal_approx(_rider.rotation, turn):
		_rider.position = at
		_rider.rotation = turn


## Inselbild aus dem Gelände: Meer durchscheinend blau, Land nach Höhe von Sand über Grün zu Fels. Gecacht.
static func _land_image(terrain: IslandTerrain) -> Texture2D:
	if _land_texture != null and _land_for == terrain:
		return _land_texture
	var w := int(ISLAND_BOUNDS.size.x / LAND_CELL_M)
	var h := int(ISLAND_BOUNDS.size.y / LAND_CELL_M)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sea := Color(0.16, 0.45, 0.66, 0.55)
	var sand := Color(0.88, 0.82, 0.62, 0.92)
	var green := Color(0.58, 0.66, 0.42, 0.92)
	var rock := Color(0.7, 0.64, 0.56, 0.92)
	for row in range(h):
		for col in range(w):
			var x := ISLAND_BOUNDS.position.x + (col + 0.5) * LAND_CELL_M
			var z := ISLAND_BOUNDS.position.y + (row + 0.5) * LAND_CELL_M
			var height := terrain.height_at(x, z)
			var color := sea
			if height > 0.5:
				color = sand.lerp(green, smoothstep(2.0, 30.0, height)).lerp(rock, smoothstep(150.0, 300.0, height))
			image.set_pixel(col, row, color)
	_land_texture = ImageTexture.create_from_image(image)
	_land_for = terrain
	return _land_texture


func _draw() -> void:
	if route.size() < 2:
		return
	if _land != null:
		var corner := map_point(bounds.position, bounds, size)
		draw_texture_rect(_land, Rect2(corner, bounds.size * map_scale(bounds, size)), false)
	var line := PackedVector2Array()
	for p in route:
		line.append(map_point(p, bounds, size))
	draw_polyline(line, ROUTE_SHADOW, 4.5, true)
	draw_polyline(line, ROUTE_COLOR, 2.5, true)
	for p in landmarks:
		var c := map_point(p, bounds, size)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]),
				LANDMARK_COLOR)
	# Start/Ziel: kleines Schachbrett
	var start := map_point(route[0], bounds, size)
	for i in range(4):
		var cell := Vector2(i % 2, i / 2) * 4.0
		draw_rect(Rect2(start - Vector2(4, 4) + cell, Vector2(4, 4)), Color.WHITE if (i % 2) == (i / 2) else Color.BLACK)


## Fahrer-Pfeil: Spitze oben, weiß umrandet.
func _draw_rider() -> void:
	var s := RIDER_SIZE_PX
	var arrow := PackedVector2Array([Vector2(s * 0.5, 0.0), Vector2(s, s), Vector2(s * 0.5, s * 0.72), Vector2(0.0, s)])
	_rider.draw_colored_polygon(arrow, RIDER_COLOR)
	_rider.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.WHITE, 1.5, true)
