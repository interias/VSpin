## Tempo-Effekte (#42): Geschwindigkeitslinien am Bildrand und ein leichter Sichtfeld-Kick der Kamera ab etwa 35 km/h,
## stetig mit dem Tempo (`strength_for`, voll ab FULL_KMH) und geglättet, ohne Sprünge. Nur Darstellung: liest das
## Tempo, wirkt nie auf Fahrmodell, Rundenzeit oder Wertung (ADR-0010). Abschaltbar im Einstellungsmenü
## (GraphicsSettings.speed_effects, `enabled`). Die Linien zeichnet ein canvas_item-Shader über dem 3D-Bild, unter HUD
## und Menüs; er läuft auch im Compatibility-Renderer (Web).
class_name SpeedEffects
extends CanvasLayer

## Ab diesem Tempo beginnen die Effekte, ab FULL_KMH wirken sie voll (km/h).
const START_KMH := 35.0
const FULL_KMH := 60.0
## Sichtfeld-Kick bei voller Stärke (Grad, auf das Sichtfeld der Kamera).
const FOV_KICK_DEG := 5.0
## Glättung (Zeitkonstante, s): Tempowechsel und Pausen blenden weich.
const SMOOTHING_S := 0.3
const SHADER := preload("res://src/shaders/speed_lines.gdshader")

## Effekte an? Aus: sofort Stärke 0, Sichtfeld wie eingestellt.
var enabled := true
## Aktuelle Stärke 0..1 (geglättet).
var strength := 0.0
## Sichtfeld der Kamera ohne Kick.
var base_fov := 75.0
## Prüfhilfe (view_probe): festes Tempo statt dem der Fahrt (NAN = Tempo der Fahrt).
var hold_kmh := NAN
var camera: Camera3D
var lines: ColorRect


## Kamera, deren Sichtfeld der Kick verändert; Linien als Vollbild-Fläche.
func setup(view_camera: Camera3D) -> void:
	name = "SpeedEffects"
	layer = -1  # unter HUD und Menüs
	camera = view_camera
	base_fov = camera.fov
	lines = ColorRect.new()
	lines.name = "Linien"
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	lines.material = material
	lines.visible = false
	add_child(lines)


## Stärke der Effekte für ein Tempo (km/h): 0 bis START_KMH, dann stetig steigend bis 1 ab FULL_KMH.
static func strength_for(speed_kmh: float) -> float:
	return smoothstep(START_KMH, FULL_KMH, speed_kmh)


## Einen Frame weiter: Stärke geglättet zum Tempo `speed_kmh` hin, Linien und Sichtfeld setzen.
func update(speed_kmh: float, delta: float) -> void:
	var target := strength_for(hold_kmh if not is_nan(hold_kmh) else speed_kmh) if enabled else 0.0
	if not enabled:
		strength = target
	else:
		strength = lerpf(strength, target, 1.0 - exp(-maxf(delta, 0.0) / SMOOTHING_S))
	if target == 0.0 and strength < 0.001:
		strength = 0.0
	_show()


## Effekte sofort aus (z. B. zurück im Startmenü).
func reset() -> void:
	strength = 0.0
	_show()


func _show() -> void:
	if camera != null:
		camera.fov = base_fov + FOV_KICK_DEG * strength
	lines.visible = strength > 0.0
	(lines.material as ShaderMaterial).set_shader_parameter("strength", strength)
