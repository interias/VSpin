## Steigungssymbol des HUD (G5): Keil, der bergauf nach rechts ansteigt, bergab abfällt, flach nichts (ein Balken
## läse sich wie ein Minuszeichen); Farbe wie der Steigungswert (RideHud.grade_color). Neu gezeichnet nur bei
## Wechsel der Richtung oder Farbe.
class_name HudGradeIcon
extends Control

## -1 bergab, 0 flach, 1 bergauf.
var direction := 0:
	set(v):
		if v != direction:
			direction = v
			queue_redraw()
var color := Color.WHITE:
	set(v):
		if v != color:
			color = v
			queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	match direction:
		1:
			draw_colored_polygon(PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(w, h * 0.15)]), color)
		-1:
			draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.15), Vector2(0, h), Vector2(w, h)]), color)
