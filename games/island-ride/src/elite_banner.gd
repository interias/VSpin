## Elite-Standarte (#52) auf der Strecke: ein Fahnenmast am rechten Straßenrand mit Querholz und einer leuchtenden Fahne
## in der Farbe der Elite-Stufe (blau = Champions, gelb = Seltene), unten als Schwalbenschwanz geschnitten, darüber zwei
## Schriftzeilen, immer zum Fahrer gedreht: Stufe und Herausforderung („Champions: Jagd“) und die Eigenschaften
## („Windschnell · Gegenwind“). Wohin sie gehört, entscheidet die Darstellung der Elite-Gruppen (EliteProp). Aus
## Grundkörpern (ADR-0009), hängt am Track (lokale Pfadkoordinaten). Nur Anzeige (ADR-0010).
class_name EliteBanner
extends Node3D

## Abstand vom Straßenrand-Mittelpunkt nach rechts (m) – außerhalb der Tore (4,6 m) – und Höhe des Masts (m).
const SIDE_M := 6.0
const POLE_M := 6.5
const CLOTH := Vector2(1.8, 2.6)
const COLOR_POLE := Color(0.32, 0.22, 0.14)
const COLOR_GOLD := Color(0.95, 0.78, 0.3)

## Fahrtposition, an der die Standarte steht (NAN = nicht gestellt), und Farbe der Fahne.
var ride_m := NAN
var color := Color.WHITE

var _cloth: StandardMaterial3D
var _title: Label3D
var _affixes: Label3D


func _init() -> void:
	name = "EliteBanner"
	_cloth = StandardMaterial3D.new()
	_cloth.roughness = 0.8
	_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloth.emission_enabled = true
	_cloth.emission_energy_multiplier = 0.45
	_box("Mast", Vector3(0.18, POLE_M, 0.18), Vector3(0.0, POLE_M / 2.0, 0.0), _plain(COLOR_POLE))
	_box("Querholz", Vector3(CLOTH.x + 0.3, 0.12, 0.12), Vector3(0.0, POLE_M - 0.35, 0.12), _plain(COLOR_POLE))
	var knob := MeshInstance3D.new()
	knob.name = "Knauf"
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	knob.mesh = sphere
	knob.material_override = _plain(COLOR_GOLD)
	knob.position = Vector3(0.0, POLE_M + 0.15, 0.0)
	add_child(knob)
	var top := POLE_M - 0.45
	_box("Fahne", Vector3(CLOTH.x, CLOTH.y, 0.05), Vector3(0.0, top - CLOTH.y / 2.0, 0.2), _cloth)
	for side in [-1.0, 1.0]:  # Schwalbenschwanz: zwei Spitzen nach unten
		var tip := MeshInstance3D.new()
		tip.name = "Spitze" + ("L" if side < 0.0 else "R")
		var prism := PrismMesh.new()
		prism.size = Vector3(CLOTH.x / 2.0, 0.6, 0.05)
		tip.mesh = prism
		tip.material_override = _cloth
		tip.rotation.z = PI
		tip.position = Vector3(side * CLOTH.x / 4.0, top - CLOTH.y - 0.3, 0.2)
		add_child(tip)
	_box("Zeichen", Vector3(0.6, 0.6, 0.06), Vector3(0.0, top - CLOTH.y * 0.45, 0.2), _plain(COLOR_GOLD), PI / 4.0)
	_title = _label("Titel", 96, POLE_M + 1.5)
	_affixes = _label("Eigenschaften", 68, POLE_M + 0.6)
	visible = false


## Fahne in der Farbe `rank_color`, Schrift `heading` (Stufe und Herausforderung) und `affixes` (Eigenschaften).
func show_group(rank_color: Color, heading: String, affixes: String) -> void:
	color = rank_color
	_cloth.albedo_color = rank_color
	_cloth.emission = rank_color
	_title.text = heading
	_title.modulate = rank_color.lightened(0.15)
	_affixes.text = affixes


## An Fahrtposition `at_m` auf `track` stellen, SIDE_M rechts der Straßenmitte, Fahne zum anfahrenden Fahrer.
func place(track: Track, at_m: float) -> void:
	ride_m = at_m
	var a := track.ride_position_at(at_m - 1.0)
	var b := track.ride_position_at(at_m + 1.0)
	var right := (b - a).normalized().cross(Vector3.UP).normalized()
	position = track.ride_position_at(at_m) + right * SIDE_M
	rotation = Vector3(0.0, atan2(-(b.x - a.x), -(b.z - a.z)), 0.0)


func reset() -> void:
	ride_m = NAN
	visible = false


## Für Tests und Prüfhilfen: die Schrift („Titel\nEigenschaften“).
func label_text() -> String:
	return "%s\n%s" % [_title.text, _affixes.text]


func _box(node_name: String, size: Vector3, at: Vector3, material: Material, turn: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.z = turn
	add_child(instance)


func _label(node_name: String, size: int, height: float) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font_size = size
	label.pixel_size = 0.01
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0.0, height, 0.0)
	add_child(label)
	return label


func _plain(albedo: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.9
	return material
