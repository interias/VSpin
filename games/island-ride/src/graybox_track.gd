## Graybox-Teststrecke: ein Rundkurs (Kreis im Grundriss) mit einem Anstieg und einer Abfahrt.
## Erzeugt die Kurve beim Erstellen aus einem Höhenprofil; #14 ersetzt sie durch den Insel-Rundkurs.
class_name GrayboxTrack
extends Track

## Höhenprofil: [Länge in Metern (horizontal), Steigung]. Summe der Höhen = 0 (Rundkurs).
const PROFILE := [
	[150.0, 0.0],    # Start, flach
	[250.0, 0.06],   # Anstieg 6 % (+15 m)
	[100.0, 0.0],    # Kuppe
	[250.0, -0.06],  # Abfahrt −6 % (−15 m)
	[150.0, 0.0],    # flach zurück zum Start
]
## Abstand der Kurvenpunkte in Metern.
const POINT_SPACING_M := 5.0


func _init() -> void:
	curve = build_curve()


## Baut die Kurve aus PROFILE. Statisch, damit sie auch ohne Szene nutzbar ist.
static func build_curve() -> Curve3D:
	var total := 0.0
	for section in PROFILE:
		total += section[0]
	var radius := total / TAU
	var result := Curve3D.new()
	result.bake_interval = 0.5
	var steps := int(round(total / POINT_SPACING_M))
	for i in range(steps + 1):
		var d := total * i / steps
		var angle := TAU * d / total
		result.add_point(Vector3(radius * sin(angle), height_at(d), radius * (1.0 - cos(angle))))
	return result


## Höhe des Profils nach `d` Metern horizontaler Strecke.
static func height_at(d: float) -> float:
	var height := 0.0
	var start := 0.0
	for section in PROFILE:
		var run := clampf(d - start, 0.0, section[0])
		height += run * section[1]
		start += section[0]
	return height
