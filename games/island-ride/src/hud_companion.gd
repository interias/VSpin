## Symbol des Begleiters Toni im HUD (Spec #76): zeigt `companion_status.state`, gezeichnet aus Grundformen (ADR-0009,
## keine Bilddatei) auf einer dunklen Scheibe.
##   idle        Mikrofon, gedämpft grau – Toni ist da und schweigt
##   listening   Mikrofon grün mit Ring – die Sprechtaste ist gedrückt, Toni hört zu
##   thinking    drei Punkte, bernsteinfarben – Toni denkt über die Antwort nach
##   speaking    drei Schallbalken, blau – Toni spricht
##   hoarse      Mikrofon rot, durchgestrichen – Toni ist heiser (Fehler), die Fahrt läuft weiter
## Neu gezeichnet nur bei Wechsel des Zustands. "" = kein Begleiter am Bus: das Symbol ist weg.
class_name HudCompanion
extends Control

const STATES := [
	BusClient.COMPANION_IDLE, BusClient.COMPANION_LISTENING, BusClient.COMPANION_THINKING,
	BusClient.COMPANION_SPEAKING, BusClient.COMPANION_HOARSE,
]
const COLORS := {
	BusClient.COMPANION_IDLE: Color(0.78, 0.82, 0.86, 0.6),
	BusClient.COMPANION_LISTENING: Color(0.5, 0.92, 0.55),
	BusClient.COMPANION_THINKING: Color(1.0, 0.78, 0.36),
	BusClient.COMPANION_SPEAKING: Color(0.5, 0.82, 1.0),
	BusClient.COMPANION_HOARSE: Color(1.0, 0.45, 0.36),
}
## Wörter zum Zustand für `readout()` und Hinweise.
const WORDS := {
	BusClient.COMPANION_IDLE: "bereit",
	BusClient.COMPANION_LISTENING: "hört zu",
	BusClient.COMPANION_THINKING: "denkt nach",
	BusClient.COMPANION_SPEAKING: "spricht",
	BusClient.COMPANION_HOARSE: "ist heiser",
}
const SIZE_PX := 44.0

## Gezeigter Zustand (STATES) oder "" für kein Symbol.
var state := "":
	set(value):
		if value == state:
			return
		state = value
		visible = state in STATES
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2.ONE * SIZE_PX
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	if state not in STATES:
		return
	var color: Color = COLORS[state]
	var c := size / 2.0
	draw_circle(c, minf(size.x, size.y) / 2.0, Color(0.0, 0.0, 0.0, 0.45))
	match state:
		BusClient.COMPANION_THINKING:
			for dx in [-12.0, 0.0, 12.0]:
				draw_circle(c + Vector2(dx, 0.0), 3.5, color)
		BusClient.COMPANION_SPEAKING:
			for bar in [[-10.0, 12.0], [0.0, 24.0], [10.0, 16.0]]:
				draw_rect(Rect2(c + Vector2(bar[0] - 2.5, -bar[1] / 2.0), Vector2(5.0, bar[1])), color)
		_:
			_draw_microphone(c, color)
			if state == BusClient.COMPANION_LISTENING:
				draw_arc(c, 20.0, 0.0, TAU, 32, color, 2.0)
			elif state == BusClient.COMPANION_HOARSE:
				draw_line(c + Vector2(-13.0, -15.0), c + Vector2(13.0, 15.0), color, 3.0)


## Mikrofon aus Kapsel (zwei Halbkreise und ein Rechteck), Bügel, Fuß und Standfläche, um `c` zentriert.
func _draw_microphone(c: Vector2, color: Color) -> void:
	draw_circle(c + Vector2(0.0, -7.0), 5.0, color)
	draw_circle(c + Vector2(0.0, 1.0), 5.0, color)
	draw_rect(Rect2(c + Vector2(-5.0, -7.0), Vector2(10.0, 8.0)), color)
	draw_arc(c + Vector2(0.0, 1.0), 9.0, 0.0, PI, 16, color, 2.0)
	draw_line(c + Vector2(0.0, 10.0), c + Vector2(0.0, 15.0), color, 2.0)
	draw_line(c + Vector2(-5.0, 15.0), c + Vector2(5.0, 15.0), color, 2.0)
