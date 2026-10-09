## Zonenbalken (#58): waagerechte Skala mit einem Zielbereich (z. B. 95–105 rpm) und dem aktuellen Wert als Marke.
## Wiederverwendbarer HUD-Baustein ohne Bezug zum Training – er bekommt Bereich und Wert (`show_zone`), z. B. auch für
## „Zone halten“ (#46). Der Zustand steckt in Farbe **und** Form der Marke (Barrierefreiheit):
##   darunter     kühl, Pfeil nach oben (schneller treten)
##   im Bereich   grün, Haken
##   darüber      warm, Pfeil nach unten (ruhiger treten)
## Die Skala reicht über den Bereich hinaus (`scale_range`); ein Wert außerhalb der Skala steht als Marke am Rand. Die
## Grenzen stehen als Zahlen an den Rändern der Zone. Neu gezeichnet nur, wenn sich Bereich, Wert oder Größe ändern.
class_name ZoneBar
extends Control

## Zustand des Werts zum Bereich.
const BELOW := -1
const INSIDE := 0
const ABOVE := 1
const COLOR_BELOW := Color(0.5, 0.78, 1.0)
const COLOR_INSIDE := Color(0.45, 0.9, 0.5)
const COLOR_ABOVE := Color(1.0, 0.58, 0.36)
## Skala: so weit reicht sie mindestens über den Bereich hinaus (Einheit des Werts), sonst um die Breite des Bereichs.
const MIN_MARGIN := 12.0
const COLOR_TRACK := Color(1.0, 1.0, 1.0, 0.16)
const COLOR_ZONE := Color(0.45, 0.9, 0.5, 0.32)
const LIMIT_FONT_SIZE := 15
## Form der Marke je Zustand.
const SHAPE_ARROW_UP := "arrow_up"
const SHAPE_CHECK := "check"
const SHAPE_ARROW_DOWN := "arrow_down"

var range_min := 0.0
var range_max := 0.0
var value := 0.0


## Bereich `minimum`..`maximum` (Grenzen eingeschlossen) und aktueller Wert.
func show_zone(minimum: float, maximum: float, current: float) -> void:
	if minimum == range_min and maximum == range_max and current == value:
		return
	range_min = minimum
	range_max = maximum
	value = current
	queue_redraw()


## Zustand des aktuellen Werts (BELOW, INSIDE, ABOVE).
func state() -> int:
	return zone_state(value, range_min, range_max)


## Zustand von `current` zum Bereich `minimum`..`maximum`, Grenzen eingeschlossen (wie Training.on_target).
static func zone_state(current: float, minimum: float, maximum: float) -> int:
	if current < minimum:
		return BELOW
	return ABOVE if current > maximum else INSIDE


## Farbe eines Zustands.
static func state_color(zone: int) -> Color:
	match zone:
		BELOW:
			return COLOR_BELOW
		ABOVE:
			return COLOR_ABOVE
	return COLOR_INSIDE


## Form der Marke eines Zustands: darunter Pfeil nach oben, im Bereich Haken, darüber Pfeil nach unten.
static func marker_shape(zone: int) -> String:
	match zone:
		BELOW:
			return SHAPE_ARROW_UP
		ABOVE:
			return SHAPE_ARROW_DOWN
	return SHAPE_CHECK


## Zustand in Worten für die Anzeige neben dem Balken.
static func state_text(zone: int) -> String:
	match zone:
		BELOW:
			return "zu niedrig"
		ABOVE:
			return "zu hoch"
	return "im Bereich"


## Skala (Anfang, Ende) für den Bereich: um seine Breite, mindestens MIN_MARGIN, nach beiden Seiten erweitert.
static func scale_range(minimum: float, maximum: float) -> Vector2:
	var margin := maxf(maximum - minimum, MIN_MARGIN)
	return Vector2(minimum - margin, maximum + margin)


## x-Position (px) von `current` auf einem Balken der Breite `width`; außerhalb der Skala am Rand.
static func value_x(current: float, minimum: float, maximum: float, width: float) -> float:
	var span := scale_range(minimum, maximum)
	return clampf(inverse_lerp(span.x, span.y, current), 0.0, 1.0) * width


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var marker_half := h * 0.5  # die Marke ragt nicht über den Balken hinaus
	var left := marker_half
	var width := maxf(w - 2.0 * marker_half, 1.0)
	draw_rect(Rect2(0.0, h * 0.25, w, h * 0.5), COLOR_TRACK)
	var zone_from := left + value_x(range_min, range_min, range_max, width)
	var zone_to := left + value_x(range_max, range_min, range_max, width)
	draw_rect(Rect2(zone_from, 0.0, maxf(zone_to - zone_from, 2.0), h), COLOR_ZONE)
	draw_rect(Rect2(zone_from, 0.0, maxf(zone_to - zone_from, 2.0), h), COLOR_INSIDE, false, 2.0)
	var font := get_theme_default_font()
	var low := "%d" % roundi(range_min)
	var high := "%d" % roundi(range_max)
	var baseline := (h + font.get_ascent(LIMIT_FONT_SIZE) - font.get_descent(LIMIT_FONT_SIZE)) * 0.5
	var low_width := font.get_string_size(low, HORIZONTAL_ALIGNMENT_LEFT, -1, LIMIT_FONT_SIZE).x
	draw_string(font, Vector2(zone_from - low_width - 6.0, baseline), low, HORIZONTAL_ALIGNMENT_LEFT, -1,
			LIMIT_FONT_SIZE, Color(1.0, 1.0, 1.0, 0.85))
	draw_string(font, Vector2(zone_to + 6.0, baseline), high, HORIZONTAL_ALIGNMENT_LEFT, -1, LIMIT_FONT_SIZE,
			Color(1.0, 1.0, 1.0, 0.85))
	_draw_marker(Vector2(left + value_x(value, range_min, range_max, width), h * 0.5), marker_half, state())


## Marke am Wert: Kreis in der Zustandsfarbe mit dunklem Symbol – Pfeil hoch, Haken oder Pfeil runter.
func _draw_marker(at: Vector2, r: float, zone: int) -> void:
	draw_circle(at, r, state_color(zone))
	var ink := Color(0.06, 0.08, 0.11)
	var s := r * 0.55
	match marker_shape(zone):
		SHAPE_ARROW_UP:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -s), at + Vector2(s, s * 0.6),
					at + Vector2(-s, s * 0.6)]), ink)
		SHAPE_ARROW_DOWN:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, s), at + Vector2(-s, -s * 0.6),
					at + Vector2(s, -s * 0.6)]), ink)
		_:
			draw_polyline(PackedVector2Array([at + Vector2(-s * 0.8, 0.0), at + Vector2(-s * 0.2, s * 0.6),
					at + Vector2(s * 0.85, -s * 0.6)]), ink, maxf(r * 0.28, 2.0))
