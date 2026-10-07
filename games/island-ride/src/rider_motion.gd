## Bewegung von Fahrer und Rad – reine Logik ohne Darstellung (Darstellung: RiderModel).
##
## Eingaben je Zeitschritt: Kadenz (rpm), Geschwindigkeit (m/s), Steigung (Anteil), Krümmung der Strecke
## (1/m, positiv = Linkskurve), Pause, Zeitschritt (s). Ausgaben:
##   crank_angle  Kurbelwinkel (rad, 0 = rechtes Pedal oben, wächst in Tretrichtung): + 2π · Kadenz/60 · dt
##   wheel_angle  Radwinkel (rad, wächst beim Vorwärtsrollen): + v · dt / r, r = WHEEL_DIAMETER_M / 2
##   lean         Schräglage (rad, positiv = nach links): atan(v² · κ / g), begrenzt, geglättet
##   bend         zusätzliche Vorbeuge des Oberkörpers bergauf (rad), geglättet
##   effort       Tretanteil 0..1 (geglättet) – skaliert das Wiegen des Oberkörpers
## In der Pause (und bei Kadenz 0) stehen Kurbel und Beine; die Räder stehen nur in der Pause
## (bei Kadenz 0 rollt das Rad mit dem Fahrmodell aus).
class_name RiderMotion
extends RefCounted

const WHEEL_DIAMETER_M := 0.68
const GRAVITY := 9.81
## Größte Schräglage in Kurven („leicht“, ADR-0006: keine Lenk-Physik).
const MAX_LEAN_RAD := deg_to_rad(15.0)
## Vorbeuge je Anteil Steigung bergauf und Obergrenze.
const BEND_PER_GRADE := 1.2
const MAX_BEND_RAD := deg_to_rad(9.0)
## Zeitkonstanten der Glättung (s).
const LEAN_SMOOTHING_S := 0.3
const BEND_SMOOTHING_S := 1.0
const EFFORT_SMOOTHING_S := 0.4
## Halber Abstand der Messpunkte für die Krümmung der Strecke (m).
const CURVE_SAMPLE_M := 4.0

var crank_angle := 0.0
var wheel_angle := 0.0
var lean := 0.0
var bend := 0.0
var effort := 0.0


## Rückt die Bewegung um `delta_s` Sekunden vor.
func step(cadence_rpm: float, speed_mps: float, grade: float, curvature: float, paused: bool, delta_s: float) -> void:
	if delta_s <= 0.0:
		return
	var cadence := 0.0 if paused else maxf(cadence_rpm, 0.0)
	var speed := 0.0 if paused else maxf(speed_mps, 0.0)
	crank_angle = fposmod(crank_angle + crank_advance(cadence, delta_s), TAU)
	wheel_angle = fposmod(wheel_angle + wheel_advance(speed, delta_s), TAU)
	lean = _smooth(lean, lean_for(speed, curvature), delta_s, LEAN_SMOOTHING_S)
	bend = _smooth(bend, clampf(grade * BEND_PER_GRADE, 0.0, MAX_BEND_RAD), delta_s, BEND_SMOOTHING_S)
	effort = _smooth(effort, 1.0 if cadence > 0.0 else 0.0, delta_s, EFFORT_SMOOTHING_S)


## Seitliches Wiegen mit dem Tritt (−1..1): nach rechts, solange das rechte Pedal nach unten tritt.
func sway() -> float:
	return effort * sin(crank_angle)


## Kurbelwinkel, um den sich die Kurbel bei `cadence_rpm` in `delta_s` dreht (rad).
static func crank_advance(cadence_rpm: float, delta_s: float) -> float:
	return TAU * maxf(cadence_rpm, 0.0) / 60.0 * delta_s


## Radwinkel, um den das Laufrad bei `speed_mps` in `delta_s` rollt (rad).
static func wheel_advance(speed_mps: float, delta_s: float) -> float:
	return maxf(speed_mps, 0.0) * delta_s / (WHEEL_DIAMETER_M / 2.0)


## Schräglage für Tempo und Krümmung (rad, positiv = links), auf ±MAX_LEAN_RAD begrenzt.
static func lean_for(speed_mps: float, curvature: float) -> float:
	return clampf(atan(speed_mps * speed_mps * curvature / GRAVITY), -MAX_LEAN_RAD, MAX_LEAN_RAD)


## Krümmung (1/m) durch drei aufeinanderfolgende Punkte, in der Ebene (x, z); positiv = Linkskurve
## (Drehung um +Y bei Fahrtrichtung −Z).
static func signed_curvature(before: Vector3, here: Vector3, after: Vector3) -> float:
	var a := Vector2(here.x - before.x, here.z - before.z)
	var b := Vector2(after.x - here.x, after.z - here.z)
	var la := a.length()
	var lb := b.length()
	if la < 0.001 or lb < 0.001:
		return 0.0
	var turn := (a.y * b.x - a.x * b.y) / (la * lb)  # sin des Richtungswechsels, + = links
	return 2.0 * turn / (la + lb)


## Mittleres Gelenk (Knie/Ellbogen) eines Zwei-Glieder-Arms von `root` nach `tip` mit den Längen
## `upper`/`lower`, gebeugt in Richtung `pole`. Ist `tip` zu weit weg, wird der Arm gestreckt.
static func joint_point(root: Vector3, tip: Vector3, upper: float, lower: float, pole: Vector3) -> Vector3:
	var to_tip := tip - root
	var dir := to_tip.normalized()
	var dist := clampf(to_tip.length(), absf(upper - lower) + 0.001, upper + lower - 0.0001)
	var along := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var out := sqrt(maxf(upper * upper - along * along, 0.0))
	var side := (pole - dir * pole.dot(dir)).normalized()
	return root + dir * along + side * out


static func _smooth(value: float, target: float, delta_s: float, time_constant_s: float) -> float:
	return value + (target - value) * (1.0 - exp(-delta_s / time_constant_s))
