## Höhenprofil des Rundkurses im HUD (G5): Höhe über Streckenposition, Abschnittsgrenzen mit Namen, Marker an der
## Fahrerposition und der gefahrene Teil hinterlegt.
## Das Profil wird nur bei `setup()` und Größenänderung gezeichnet; pro Frame bewegen sich nur Marker und
## Hinterlegung (eigene Knoten), und auch nur, wenn sich ihre Pixelposition ändert.
##   setup(track)               Profil aus der Strecke abtasten (Höhe = y des Pfads), Stationen übernehmen – beides in
##                              Fahrtrichtung (Track.ride_position_at, ride_stations; gegen den Uhrzeigersinn
##                              gespiegelt, #34)
##   distance_m = d             Fahrerposition (Fahrtposition) innerhalb der Runde
##   profile_point(...)         reine Rechnung Streckenposition/Höhe → Punkt im Zeichenbereich (Tests)
class_name HudProfile
extends Control

## Abtastabstand des Profils (m).
const SAMPLE_M := 20.0
## Höhe der Namenszeile über dem Profil (px) und Abstand des Profils zum Rand.
const LABEL_ROW_PX := 18.0
const INSET_PX := 4.0
const NAME_FONT_SIZE := 13
const FILL_COLOR := Color(0.95, 0.9, 0.75, 0.2)
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const BOUNDARY_COLOR := Color(1.0, 1.0, 1.0, 0.22)
const NAME_COLOR := Color(0.84, 0.88, 0.9, 0.95)
const DONE_COLOR := Color(0.45, 0.75, 0.98, 0.14)
const MARKER_COLOR := Color(1.0, 0.45, 0.3)

var length_m := 0.0
## Höhe je Abtastpunkt (gleichmäßig über die Runde, erster = letzter bei geschlossener Strecke).
var heights := PackedFloat32Array()
var min_height_m := 0.0
var max_height_m := 1.0
## [{name, start_m}] wie Track.ride_stations().
var stations: Array = []
## Fahrerposition innerhalb der Runde (m).
var distance_m := 0.0:
	set(v):
		distance_m = v
		_place_marker()

var _marker: Control
var _done: ColorRect


func _ready() -> void:
	_done = ColorRect.new()
	_done.color = DONE_COLOR
	_done.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_done)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	resized.connect(_place_marker)
	_place_marker()


func setup(track: Track) -> void:
	length_m = track.length_m()
	stations = track.ride_stations()
	heights.clear()
	var count := maxi(int(ceil(length_m / SAMPLE_M)), 1)
	for i in range(count + 1):
		heights.append(track.ride_position_at(length_m * i / count).y)
	min_height_m = heights[0]
	max_height_m = heights[0]
	for h in heights:
		min_height_m = minf(min_height_m, h)
		max_height_m = maxf(max_height_m, h)
	queue_redraw()
	_place_marker()


## Zeichenbereich des Profils (unter der Namenszeile).
func plot_rect() -> Rect2:
	return Rect2(INSET_PX, LABEL_ROW_PX, maxf(size.x - 2.0 * INSET_PX, 1.0), maxf(size.y - LABEL_ROW_PX - INSET_PX, 1.0))


## Punkt im Zeichenbereich `area` für Streckenposition `d` und Höhe `h`: links Start, rechts Rundenende,
## unten die niedrigste, oben die höchste Höhe (mit 10 % Luft nach oben).
static func profile_point(d: float, h: float, length: float, min_h: float, max_h: float, area: Rect2) -> Vector2:
	var along := clampf(d / length, 0.0, 1.0) if length > 0.0 else 0.0
	var span := maxf(max_h - min_h, 1.0) * 1.1
	var up := clampf((h - min_h) / span, 0.0, 1.0)
	return Vector2(area.position.x + area.size.x * along, area.end.y - area.size.y * up)


## Höhe des Profils an Streckenposition `d` (linear zwischen den Abtastpunkten).
func height_at(d: float) -> float:
	if heights.size() < 2 or length_m <= 0.0:
		return min_height_m
	var f := clampf(d / length_m, 0.0, 1.0) * (heights.size() - 1)
	var i := mini(int(f), heights.size() - 2)
	return lerpf(heights[i], heights[i + 1], f - i)


func _point(d: float, h: float) -> Vector2:
	return profile_point(d, h, length_m, min_height_m, max_height_m, plot_rect())


func _draw() -> void:
	if heights.size() < 2:
		return
	var area := plot_rect()
	var line := PackedVector2Array()
	for i in range(heights.size()):
		line.append(_point(length_m * i / (heights.size() - 1), heights[i]))
	var fill := line.duplicate()
	fill.append(Vector2(area.end.x, area.end.y))
	fill.append(Vector2(area.position.x, area.end.y))
	draw_colored_polygon(fill, FILL_COLOR)
	draw_polyline(line, LINE_COLOR, 2.0, true)
	var font := get_theme_default_font()
	for i in range(stations.size()):
		var from: float = stations[i]["start_m"]
		var to: float = stations[i + 1]["start_m"] if i + 1 < stations.size() else length_m
		var x0 := _point(from, 0.0).x
		var x1 := _point(to, 0.0).x
		if i > 0:
			draw_line(Vector2(x0, 2.0), Vector2(x0, area.end.y), BOUNDARY_COLOR, 1.0)
		var text: String = stations[i]["name"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x
		if width + 8.0 <= x1 - x0:  # Name nur, wenn er in den Abschnitt passt
			draw_string(font, Vector2((x0 + x1 - width) * 0.5, LABEL_ROW_PX - 4.0), text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, NAME_FONT_SIZE, NAME_COLOR)
	# Höchster Punkt mit Höhe, rechts neben dem Gipfel
	var peak := 0
	for i in range(heights.size()):
		if heights[i] > heights[peak]:
			peak = i
	var at := line[peak]
	draw_string(font, at + Vector2(6.0, 14.0), "%d m" % roundi(max_height_m), HORIZONTAL_ALIGNMENT_LEFT, -1,
			NAME_FONT_SIZE - 1, Color(NAME_COLOR, 0.75))


func _place_marker() -> void:
	if _marker == null:
		return
	var p := _point(distance_m, height_at(distance_m))
	var area := plot_rect()
	var at := Vector2(roundf(p.x), roundf(p.y))
	if _marker.position != at - Vector2(6.0, 6.0) or _marker.size.y != area.end.y - at.y + 6.0:
		_marker.position = at - Vector2(6.0, 6.0)
		_marker.size = Vector2(12.0, area.end.y - at.y + 6.0)
		_marker.queue_redraw()
	var done := Rect2(area.position.x, area.position.y, maxf(at.x - area.position.x, 0.0), area.size.y)
	if _done.position != done.position or _done.size != done.size:
		_done.position = done.position
		_done.size = done.size


## Marker: senkrechte Linie bis zum Boden des Profils und Punkt auf der Profillinie.
func _draw_marker() -> void:
	var c := Vector2(6.0, 6.0)
	_marker.draw_line(c, Vector2(6.0, _marker.size.y), Color(MARKER_COLOR, 0.8), 2.0)
	_marker.draw_circle(c, 6.0, Color.WHITE)
	_marker.draw_circle(c, 4.0, MARKER_COLOR)
