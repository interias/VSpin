## Pulsverlauf im HUD (#64): kleine Kurve der letzten WINDOW_S Sekunden Fahrzeit, der Hintergrund in den Zonenfarben
## der laufenden Fahrt (dezent, ohne Zonen neutral). Nur Anzeige – nichts davon landet im Spielstand.
##   push(time_s, bpm, zones)   Fahrzeit der Fahrt und Puls (NAN = kein Wert) übernehmen; die Zeit steht in Pausen, dann
##                              kommt auch kein neuer Punkt dazu; springt sie zurück, beginnt der Verlauf neu
##   reset()                    Verlauf leeren (neue Fahrt)
##   curve_points / band_rects  reine Rechnung (Punkte, Lücken, Skala, Zonenbänder) → Zeichenbereich (Tests)
## Lücken ohne Puls bleiben Lücken: Liegen zwei Punkte weiter als GAP_S auseinander, wird die Linie getrennt, es wird
## nicht interpoliert. Gezeichnet wird nur, wenn ein neuer Punkt dazukommt oder sich die Zonen ändern.
class_name HudPulse
extends Control

## Länge des Zeitfensters (s Fahrzeit) und Mindestabstand zweier gespeicherter Punkte (s).
const WINDOW_S := 180.0
const SAMPLE_S := 0.5
## Ab diesem Abstand (s) zweier Punkte ist es eine Lücke.
const GAP_S := 3.0
## Skala ohne Daten und kleinste Spanne (bpm); sonst Daten ± Luft, auf 10 bpm gerundet.
const DEFAULT_RANGE := Vector2(60.0, 180.0)
const MIN_SPAN_BPM := 40.0
const RANGE_MARGIN_BPM := 5.0
const INSET_PX := 2.0
const LABEL_FONT_SIZE := 12
const BAND_ALPHA := 0.24
const NEUTRAL_COLOR := Color(1.0, 1.0, 1.0, 0.08)
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const LABEL_COLOR := Color(0.84, 0.88, 0.9, 0.8)

## (Fahrzeit s, Puls bpm) je gespeichertem Punkt, älteste zuerst.
var samples: Array[Vector2] = []
var zones: HeartRateZones
## Fahrzeit des letzten `push` (s).
var now_s := 0.0

var _drawn_at := -INF


func _ready() -> void:
	resized.connect(queue_redraw)


## Fahrzeit `time_s` und Puls `bpm` (NAN, 0 oder negativ = kein Wert) übernehmen, `zones` sind die der laufenden Fahrt.
func push(time_s: float, bpm: float, zones_of_ride: HeartRateZones) -> void:
	if time_s < now_s:
		samples.clear()  # neue Fahrt: die Zeit beginnt von vorn
		_drawn_at = -INF
	now_s = time_s
	var redraw := zones_of_ride != zones or now_s - _drawn_at >= SAMPLE_S
	zones = zones_of_ride
	if is_finite(bpm) and bpm > 0.0 and (samples.is_empty() or time_s - samples[-1].x >= SAMPLE_S):
		samples.append(Vector2(time_s, bpm))
		redraw = true
	while not samples.is_empty() and samples[0].x < now_s - WINDOW_S:
		samples.pop_front()
	if redraw:
		_drawn_at = now_s
		queue_redraw()


func reset() -> void:
	samples.clear()
	now_s = 0.0
	_drawn_at = -INF
	queue_redraw()


## Zeichenbereich der Kurve.
func plot_rect() -> Rect2:
	return Rect2(INSET_PX, INSET_PX, maxf(size.x - 2.0 * INSET_PX, 1.0), maxf(size.y - 2.0 * INSET_PX, 1.0))


## Skala (untere, obere bpm) für die Punkte im Zeitfenster bis `now`: Daten mit etwas Luft auf 10 bpm gerundet, mindestens
## MIN_SPAN_BPM breit; ohne Daten DEFAULT_RANGE.
static func bpm_range(points: Array, now: float) -> Vector2:
	var low := INF
	var high := -INF
	for p: Vector2 in points:
		if p.x >= now - WINDOW_S and p.x <= now:
			low = minf(low, p.y)
			high = maxf(high, p.y)
	if low > high:
		return DEFAULT_RANGE
	low = floorf((low - RANGE_MARGIN_BPM) / 10.0) * 10.0
	high = ceilf((high + RANGE_MARGIN_BPM) / 10.0) * 10.0
	if high - low < MIN_SPAN_BPM:
		var mid := (low + high) * 0.5
		low = mid - MIN_SPAN_BPM * 0.5
		high = mid + MIN_SPAN_BPM * 0.5
	return Vector2(low, high)


## Punkt im Zeichenbereich `area` für Fahrzeit `t` und Puls `bpm`: rechts jetzt (`now`), links WINDOW_S früher, unten
## `low`, oben `high` (begrenzt).
static func point(t: float, bpm: float, now: float, low: float, high: float, area: Rect2) -> Vector2:
	var along := clampf(1.0 - (now - t) / WINDOW_S, 0.0, 1.0)
	var up := clampf((bpm - low) / maxf(high - low, 1.0), 0.0, 1.0)
	return Vector2(area.position.x + area.size.x * along, area.end.y - area.size.y * up)


## Die Kurve als Linienzüge im Zeichenbereich: je ein Zug pro zusammenhängendem Stück, getrennt an jeder Lücke (Abstand
## über GAP_S). Nur Punkte im Zeitfenster; ein einzelner Punkt ergibt einen Zug mit einem Punkt.
static func curve_points(points: Array, now: float, low: float, high: float, area: Rect2) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	var last_t := -INF
	for p: Vector2 in points:
		if p.x < now - WINDOW_S or p.x > now:
			continue
		if not run.is_empty() and p.x - last_t > GAP_S:
			lines.append(run)
			run = PackedVector2Array()
		run.append(point(p.x, p.y, now, low, high, area))
		last_t = p.x
	if not run.is_empty():
		lines.append(run)
	return lines


## Zonenbänder im Zeichenbereich für die Skala `low`..`high`: [{zone, rect}] von Z1 (unten) bis Z5, nur die im Bild. Wie
## `HeartRateZones.zone_for` ist Z1 nach unten und Z5 nach oben offen. Ohne Zonen (oder null) leer.
static func band_rects(zones_of_ride: HeartRateZones, low: float, high: float, area: Rect2) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	if zones_of_ride == null or not zones_of_ride.has_zones():
		return bands
	for zone in range(1, HeartRateZones.ZONE_COUNT + 1):
		var r := zones_of_ride.zone_range(zone)
		var from := -INF if zone == 1 else float(r.x)
		var to := INF if zone == HeartRateZones.ZONE_COUNT else float(r.y + 1)  # obere Grenze ist eingeschlossen
		from = maxf(from, low)
		to = minf(to, high)
		if to <= from:
			continue
		var y_top := point(0.0, to, 0.0, low, high, area).y
		var y_bottom := point(0.0, from, 0.0, low, high, area).y
		bands.append({"zone": zone, "rect": Rect2(area.position.x, y_top, area.size.x, y_bottom - y_top)})
	return bands


func _draw() -> void:
	var area := plot_rect()
	var span := bpm_range(samples, now_s)
	var bands := band_rects(zones, span.x, span.y, area)
	if bands.is_empty():
		draw_rect(area, NEUTRAL_COLOR)
	for band in bands:
		draw_rect(band["rect"], Color(HeartRateZones.color_for(band["zone"]), BAND_ALPHA))
	var font := get_theme_default_font()
	draw_string(font, Vector2(area.position.x + 3.0, area.end.y - 3.0), "%d" % roundi(span.x),
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
	draw_string(font, Vector2(area.position.x + 3.0, area.position.y + LABEL_FONT_SIZE), "%d" % roundi(span.y),
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)
	for line in curve_points(samples, now_s, span.x, span.y, area):
		if line.size() == 1:
			draw_circle(line[0], 1.5, LINE_COLOR)
		else:
			draw_polyline(line, LINE_COLOR, 2.0, true)
	if not samples.is_empty() and now_s - samples[-1].x <= GAP_S:
		var last := samples[-1]
		var dot := Color.WHITE if zones == null else HeartRateZones.color_for(zones.zone_for(last.y))
		draw_circle(point(last.x, last.y, now_s, span.x, span.y, area), 4.0, dot)
