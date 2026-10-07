## Kadenz-Anzeige des HUD (G5): Bogen über 240° von 0 bis `max_value`, gefüllt bis zum aktuellen Wert, der
## Wohlfühlbereich (`zone_from`..`zone_to`) als feiner Bogen außen. Füllfarbe: unter dem Bereich kühl, darin grün,
## darüber warm. Neu gezeichnet wird nur, wenn sich der gerundete Wert ändert (oder die Größe).
class_name HudGauge
extends Control

## Anfang des Bogens (Grad, 0 = rechts, im Uhrzeigersinn) und Spannweite.
const START_DEG := 150.0
const SWEEP_DEG := 240.0

@export var max_value := 120.0
@export var zone_from := 80.0
@export var zone_to := 100.0
@export var thickness := 12.0
@export var track_color := Color(1.0, 1.0, 1.0, 0.16)
@export var low_color := Color(0.45, 0.75, 0.98)
@export var zone_color := Color(0.45, 0.88, 0.55)
@export var high_color := Color(0.98, 0.66, 0.3)

## Angezeigter Wert (gerundet, auf 0..max_value begrenzt).
var value := 0.0:
	set(v):
		var shown := clampf(roundf(v), 0.0, max_value)
		if shown != value:
			value = shown
			queue_redraw()


## Zeichenwinkel (Bogenmaß) für `v` auf einer Skala bis `max_v`.
static func angle_for(v: float, max_v: float) -> float:
	return deg_to_rad(START_DEG + SWEEP_DEG * clampf(v / max_v, 0.0, 1.0))


## Füllfarbe für den aktuellen Wert.
func fill_color() -> Color:
	if value < zone_from:
		return low_color
	return zone_color if value <= zone_to else high_color


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - thickness
	draw_arc(center, radius, angle_for(0.0, max_value), angle_for(max_value, max_value), 72, track_color, thickness, true)
	draw_arc(center, radius + thickness * 0.5 + 4.0, angle_for(zone_from, max_value), angle_for(zone_to, max_value),
			24, Color(zone_color, 0.7), 3.0, true)
	if value > 0.0:
		draw_arc(center, radius, angle_for(0.0, max_value), angle_for(value, max_value), 72, fill_color(), thickness, true)
