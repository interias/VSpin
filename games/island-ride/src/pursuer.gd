## Verfolger der Jagd (#47): ein Dimoni-Hund aus Grundkörpern (dunkelrot, Hörner, glühende Augen), der hinter dem Fahrer
## herläuft. Je größer der Abstand der Jagd (`gap` 0..1), desto weiter hinten – bei 0 auf den Fersen, bei 1 abgehängt
## (außer Sicht). Nach der Jagd zieht er ab: er fällt zurück und verschwindet (weich – gleich nach Erfolg oder
## Scheitern). Der Abstand ist reine Anzeige (er wirkt nie auf das Fahrmodell, ADR-0010). Hängt am Track (lokale
## Pfadkoordinaten), steht über `follow` hinter einer Fahrtposition, in jeder Richtung (#34); Blick in Fahrtrichtung.
class_name Pursuer
extends Node3D

## Abstand hinter dem Fahrer (m) bei Abstand 0 (auf den Fersen) und 1 (abgehängt, nicht mehr zu sehen).
const CLOSE_M := 4.0
const FAR_M := 45.0
## Seitlich versetzt (m, links), damit er auf den Fersen nicht die Sicht auf die Straße versperrt.
const SIDE_M := 1.9
## Wie schnell der Abstand zum Fahrer nachgeführt wird (m/s) und wie schnell er nach der Jagd abzieht.
const CATCH_UP_MPS := 14.0
const LEAVE_MPS := 10.0
const COLOR_BODY := Color(0.62, 0.15, 0.1)
const COLOR_DARK := Color(0.3, 0.1, 0.08)
const COLOR_HORN := Color(0.9, 0.85, 0.7)
const COLOR_EYE := Color(1.0, 0.55, 0.1)

## Abstand der Jagd, Abstand hinter dem Fahrer in m (angezeigt) und dessen Ziel.
var gap := 0.0
var behind_m := CLOSE_M
var target_behind_m := CLOSE_M
## Zieht er gerade ab? Läuft er (sonst unsichtbar)?
var leaving := false
var active := false

var _track: Track
var _rider_m := 0.0
var _body: Node3D
var _time := 0.0


func _init() -> void:
	name = "Pursuer"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_box("Rumpf", Vector3(1.0, 0.9, 2.2), Vector3(0.0, 1.0, 0.0), COLOR_BODY)
	_box("Brust", Vector3(1.15, 1.05, 0.9), Vector3(0.0, 1.05, -0.8), COLOR_DARK)
	_box("Kopf", Vector3(0.7, 0.6, 0.8), Vector3(0.0, 1.45, -1.55), COLOR_BODY)
	_box("Schnauze", Vector3(0.4, 0.3, 0.5), Vector3(0.0, 1.3, -2.05), COLOR_DARK)
	var tail := PrismMesh.new()
	tail.size = Vector3(0.3, 0.9, 0.3)
	_add("Schwanz", tail, Vector3(0.0, 1.2, 1.3), COLOR_DARK, Vector3(-PI / 2.4, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		var tag := "L" if side < 0.0 else "R"
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.11
		horn.height = 0.55
		horn.radial_segments = 5
		_add("Horn" + tag, horn, Vector3(side * 0.26, 1.9, -1.45), COLOR_HORN, Vector3(0.0, 0.0, -side * 0.25))
		var ear := PrismMesh.new()
		ear.size = Vector3(0.18, 0.3, 0.1)
		_add("Ohr" + tag, ear, Vector3(side * 0.3, 1.78, -1.7), COLOR_DARK)
		_box("Auge" + tag, Vector3(0.14, 0.1, 0.06), Vector3(side * 0.2, 1.55, -1.97), COLOR_EYE, true)
		for z in [-0.75, 0.8]:
			_box("Bein%s%s" % [tag, "V" if z < 0.0 else "H"], Vector3(0.24, 0.8, 0.28), Vector3(side * 0.38, 0.4, z),
					COLOR_DARK)
	visible = false


## Hinter Fahrtposition `ride_m` auf `track` laufen lassen, bei Abstand `gap_value` (0..1).
func follow(track: Track, ride_m: float, gap_value: float) -> void:
	_track = track
	_rider_m = ride_m
	active = true
	gap = clampf(gap_value, 0.0, 1.0)
	if not leaving:
		target_behind_m = lerpf(CLOSE_M, FAR_M, gap)
	_apply()


## Jagd zu Ende: zurückfallen und verschwinden.
func dismiss() -> void:
	leaving = true
	target_behind_m = FAR_M


## Neue Jagd mit Abstand `start_gap`.
func reset(start_gap: float) -> void:
	leaving = false
	active = false
	gap = start_gap
	behind_m = lerpf(CLOSE_M, FAR_M, start_gap)
	target_behind_m = behind_m
	visible = false


func _process(delta: float) -> void:
	_time += delta
	behind_m = move_toward(behind_m, target_behind_m, (LEAVE_MPS if leaving else CATCH_UP_MPS) * delta)
	_body.position.y = absf(sin(_time * 9.0)) * 0.12  # Galopp: leichtes Wippen
	_apply()


func _apply() -> void:
	if _track == null:
		return
	var at := _rider_m - behind_m
	var a := _track.ride_position_at(at - 1.0)
	var b := _track.ride_position_at(at + 1.0)
	rotation = Vector3(0.0, atan2(-(b.x - a.x), -(b.z - a.z)), 0.0)
	position = _track.ride_position_at(at) - basis.x * SIDE_M
	visible = active and behind_m < FAR_M - 0.5


func _box(node_name: String, size: Vector3, at: Vector3, color: Color, glow: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(node_name, mesh, at, color, Vector3.ZERO, glow)


func _add(node_name: String, mesh: Mesh, at: Vector3, color: Color, rot: Vector3 = Vector3.ZERO,
		glow: bool = false) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	instance.material_override = material
	instance.position = at
	instance.rotation = rot
	_body.add_child(instance)
