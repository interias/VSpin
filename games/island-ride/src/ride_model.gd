## Fahrmodell der Inselfahrt – reine Logik ohne Darstellung (ADR-0006).
##
## Eingaben je Zeitschritt: Kadenz (rpm), Steigung (Anteil, 0.06 = 6 %), Zeitschritt (s),
## Parameter aus RideConfig. Ausgaben: Geschwindigkeit und Streckenposition (Meter entlang des Pfads).
##
##   v_ziel = k · Kadenz · Steigungsfaktor
##   Steigungsfaktor = 1 / (1 + uphill_damping · Steigung)   bergauf (gedämpft)
##                   = 1 + downhill_boost · |Steigung|        bergab (leicht verstärkt)
##   Trägheit: v nähert sich v_ziel exponentiell mit Zeitkonstante inertia_s.
##
## Leistungsmodell (Spec #75, ADR-0010 Nachtrag): Liefert der Trainer gemessene Watt, kommt v_ziel statt aus der Kadenz
## aus der Leistung P und der Streckensteigung θ (ohne Wind, Parameter `power_*` aus RideConfig):
##   P = v · m·g·(sin θ + Crr·cos θ) + ½·ρ·CdA·v³
## gelöst nach v ≥ 0 (größte Lösung; bergab rollt man auch mit 0 W, höchstens `power_max_kmh`). Die Trägheit ist
## dieselbe. Welches Modell eine Fahrt nutzt, ist ihre Geräteart (`kind_for`), sie wechselt in der Fahrt nicht.
class_name RideModel
extends RefCounted

const KMH_PER_MPS := 3.6
const GRAVITY := 9.81
## Gerätearten (Wertung je Geräteart, ADR-0010 Nachtrag): Leistungsmodell (Trainer mit gemessener Leistung) und
## Kadenzmodell (Simulator, Rad ohne gemessene Watt).
const KIND_POWER := "power"
const KIND_CADENCE := "cadence"
## Fehlt im Leistungsmodell der Wattwert, gilt der letzte noch so lange, danach 0 W – dieselbe Frist wie Kadenz 0
## (ADR-0004).
const POWER_TIMEOUT_S := 2.5
## Halbierungen des Lösers (auf 20 m/s genau bis ~5 µm/s).
const SOLVER_STEPS := 32

var config: RideConfig
## Aktuelle Geschwindigkeit in m/s.
var speed_mps := 0.0
## Zurückgelegte Strecke in Metern seit Start (Streckenposition, nicht modulo Rundenlänge).
var distance_m := 0.0
## Leistungsmodell: zuletzt gültige Leistung (W) und wie lange schon kein Wert kam (s).
var _last_power_w := 0.0
var _power_missing_s := 0.0


func _init(ride_config: RideConfig = null, start_distance_m: float = 0.0) -> void:
	config = ride_config if ride_config != null else RideConfig.new()
	distance_m = start_distance_m


## Geräteart zu einer Telemetrie: gemessene Leistung (`power_w` vorhanden, `power_estimated == false`) → KIND_POWER,
## sonst KIND_CADENCE (geschätzte Leistung des Simulators zählt nicht).
static func kind_for(power_w: float, power_estimated: bool) -> String:
	return KIND_POWER if not is_nan(power_w) and not power_estimated else KIND_CADENCE


## Zielgeschwindigkeit in m/s für Kadenz und Steigung, ohne Trägheit.
func target_speed_mps(cadence_rpm: float, grade: float) -> float:
	var flat_kmh := config.k_kmh_per_rpm * maxf(cadence_rpm, 0.0)
	return flat_kmh * grade_factor(grade) / KMH_PER_MPS


## Faktor, um den die Steigung die Zielgeschwindigkeit verändert (1.0 = flach).
func grade_factor(grade: float) -> float:
	if grade > 0.0:
		return 1.0 / (1.0 + config.uphill_damping * grade)
	return 1.0 + config.downhill_boost * -grade


## Rückt das Modell um `delta_s` Sekunden vor.
func step(cadence_rpm: float, grade: float, delta_s: float) -> void:
	if delta_s <= 0.0:
		return
	_follow(target_speed_mps(cadence_rpm, grade), delta_s)


## Trägheit und Weg: v nähert sich `target` mit inertia_s, die Strecke wächst um v · delta_s.
func _follow(target: float, delta_s: float) -> void:
	if config.inertia_s <= 0.0:
		speed_mps = target
	else:
		speed_mps += (target - speed_mps) * (1.0 - exp(-delta_s / config.inertia_s))
	distance_m += speed_mps * delta_s


## Zielgeschwindigkeit in m/s für die Leistung `power_w` (W) auf der Streckensteigung `grade` (Anteil), ohne Trägheit.
## Löst P = v·F + k·v³ (F = m·g·(sin θ + Crr·cos θ), k = ½·ρ·CdA) per Bisektion: f(v) = k·v³ + F·v − P ist ab ihrem
## Minimum (v = 0 oder, bergab, √(−F / 3k)) steigend und dort ≤ 0 – die größte Lösung ist eindeutig, auch bei 0 W und
## Gefälle. Ohne Luftwiderstand (k ≤ 0) gilt v = P / F. Höchstens `power_max_kmh`.
func target_speed_power_mps(power_w: float, grade: float) -> float:
	var power := maxf(power_w, 0.0) if not is_nan(power_w) else 0.0
	var norm := sqrt(1.0 + grade * grade)
	var force := config.power_mass_kg * GRAVITY * (grade + config.power_crr) / norm
	var drag := 0.5 * config.power_air_density * config.power_cda_m2
	var v_max := maxf(config.power_max_kmh, 0.0) / KMH_PER_MPS
	if drag <= 0.0:
		return v_max if force <= 0.0 else minf(power / force, v_max)
	var lo := sqrt(maxf(-force, 0.0) / (3.0 * drag))
	if drag * v_max * v_max * v_max + force * v_max - power <= 0.0:
		return v_max
	var hi := v_max
	for i in range(SOLVER_STEPS):
		var mid := (lo + hi) * 0.5
		if drag * mid * mid * mid + force * mid - power > 0.0:
			hi = mid
		else:
			lo = mid
	return lo


## Rückt das Modell im Leistungsmodell um `delta_s` Sekunden vor. `power_w` NAN = kein Wert: der letzte gilt noch
## POWER_TIMEOUT_S, danach 0 W.
func step_power(power_w: float, grade: float, delta_s: float) -> void:
	if delta_s <= 0.0:
		return
	if is_nan(power_w):
		_power_missing_s += delta_s
		if _power_missing_s >= POWER_TIMEOUT_S:
			_last_power_w = 0.0
	else:
		_power_missing_s = 0.0
		_last_power_w = power_w
	_follow(target_speed_power_mps(_last_power_w, grade), delta_s)


## Ein Schritt in der Geräteart `kind`: Leistungsmodell mit `power_w`, sonst Kadenzmodell mit `cadence_rpm`.
func step_kind(kind: String, cadence_rpm: float, power_w: float, grade: float, delta_s: float) -> void:
	if kind == KIND_POWER:
		step_power(power_w, grade, delta_s)
	else:
		step(cadence_rpm, grade, delta_s)


func speed_kmh() -> float:
	return speed_mps * KMH_PER_MPS
