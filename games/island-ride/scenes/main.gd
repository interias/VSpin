## Hauptszene der Inselfahrt (Graybox): verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
extends Node3D

## Konfiguration; wenn vor `_ready` nicht gesetzt, wird `res://config.cfg` geladen.
var config: RideConfig = null
## Startposition auf der Strecke in Metern (Standard: Start/Ziel).
@export var start_distance_m := 0.0

var bus: BusClient
var model: RideModel

@onready var track: Track = $Track
@onready var rider: PathFollow3D = $Track/Rider
@onready var hud_label: Label = $Hud/Label


func _ready() -> void:
	if config == null:
		config = RideConfig.load_file()
	bus = BusClient.from_config(config)
	model = RideModel.new(config, start_distance_m)
	_update_view()


func _process(delta: float) -> void:
	bus.poll(delta)
	model.step(bus.cadence, track.grade_at(model.distance_m), delta)
	_update_view()


func _exit_tree() -> void:
	if bus != null:
		bus.close()


## Aktuelle Steigung an der Position des Fahrers (Anteil).
func current_grade() -> float:
	return track.grade_at(model.distance_m)


func _update_view() -> void:
	rider.progress = track.wrap_distance(model.distance_m)
	hud_label.text = "Kadenz: %d rpm\nTempo: %.1f km/h" % [roundi(bus.cadence), model.speed_kmh()]
