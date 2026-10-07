## Simuliertes Wetter (G6) – kein Online-Wetter (Spec #2: Online-Funktionen außerhalb des Umfangs).
## Zustände (`STATES`) mit Kennwerten 0..1: Bewölkung `cloud`, Dunst `haze`, Regen `rain`, dazu Windfaktor `wind`.
## Modi:
##   changing  wechselnd (Standard): meist sonnig, nach einer zufälligen Dauer je Zustand Wechsel zu einem Nachbarn
##             (klar ↔ leicht bewölkt ↔ bewölkt ↔ Regen), weich über `TRANSITION_S`
##   fixed     fester Zustand; ein Wechsel per `set_mode` blendet in `MANUAL_TRANSITION_S` über
## `params()` liefert die übergeblendeten Kennwerte; alles rückt nur mit `advance()` vor (Tests ohne Echtzeit).
class_name Weather
extends RefCounted

const CLEAR := "clear"
const LIGHT_CLOUDS := "light_clouds"
const OVERCAST := "overcast"
const RAIN := "rain"
const STATES := {
	CLEAR: {"cloud": 0.25, "haze": 0.0, "rain": 0.0, "wind": 1.0},
	LIGHT_CLOUDS: {"cloud": 0.55, "haze": 0.15, "rain": 0.0, "wind": 1.3},
	OVERCAST: {"cloud": 0.9, "haze": 0.55, "rain": 0.0, "wind": 1.7},
	RAIN: {"cloud": 1.0, "haze": 0.8, "rain": 1.0, "wind": 2.2},
}
const MODE_CHANGING := "changing"
const MODE_FIXED := "fixed"
const MODES := [MODE_CHANGING, MODE_FIXED]
## Verweildauer je Zustand im Modus `changing` (Minuten, min/max).
const HOLD_MIN := {
	CLEAR: Vector2(25.0, 45.0),
	LIGHT_CLOUDS: Vector2(8.0, 20.0),
	OVERCAST: Vector2(5.0, 12.0),
	RAIN: Vector2(4.0, 9.0),
}
## Nächster Zustand: [Zustand, Gewicht] – Regen nur über „bewölkt“, danach zurück Richtung Sonne.
const NEXT := {
	CLEAR: [[LIGHT_CLOUDS, 0.8], [OVERCAST, 0.2]],
	LIGHT_CLOUDS: [[CLEAR, 0.65], [OVERCAST, 0.35]],
	OVERCAST: [[LIGHT_CLOUDS, 0.5], [RAIN, 0.3], [CLEAR, 0.2]],
	RAIN: [[OVERCAST, 0.6], [LIGHT_CLOUDS, 0.4]],
}
## Überblendzeit beim selbsttätigen Wechsel und bei einer Umstellung von Hand (s).
const TRANSITION_S := 240.0
const MANUAL_TRANSITION_S := 10.0

var mode := MODE_CHANGING
## Zielzustand (bei laufender Überblendung der neue).
var state := CLEAR
## Restdauer des Zustands im Modus `changing` (s).
var hold_s := 0.0

var _rng := RandomNumberGenerator.new()
var _from: Dictionary = STATES[CLEAR]
## Fortschritt der Überblendung 0..1 und deren Dauer (s).
var _blend := 1.0
var _blend_s := TRANSITION_S


func _init(start_mode: String = MODE_CHANGING, start_state: String = CLEAR, rng_seed: int = 0) -> void:
	_rng.seed = rng_seed if rng_seed != 0 else int(Time.get_unix_time_from_system())
	mode = start_mode if start_mode in MODES else MODE_CHANGING
	state = start_state if STATES.has(start_state) else CLEAR
	_from = STATES[state]
	hold_s = _hold_for(state)


## Modus und (optional) Zustand umstellen; ein anderer Zustand wird in MANUAL_TRANSITION_S übergeblendet.
func set_mode(new_mode: String, new_state: String = "") -> void:
	if new_mode not in MODES:
		push_warning("Weather: unbekannter Modus '%s', nutze '%s'" % [new_mode, MODE_CHANGING])
		new_mode = MODE_CHANGING
	mode = new_mode
	if STATES.has(new_state) and new_state != state:
		_go(new_state, MANUAL_TRANSITION_S)
	hold_s = _hold_for(state)


## Wetter um `seconds` vorrücken: Überblendung und (im Modus `changing`) Verweildauer.
func advance(seconds: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + seconds / _blend_s, 1.0)
		if _blend > 0.9999:
			_blend = 1.0
	if mode != MODE_CHANGING:
		return
	hold_s -= seconds
	if hold_s <= 0.0 and _blend >= 1.0:
		_go(next_state(state, _rng.randf()), TRANSITION_S)
		hold_s = _hold_for(state)


## Aktuelle Kennwerte {cloud, haze, rain, wind}, weich übergeblendet.
func params() -> Dictionary:
	return blend(_from, STATES[state], smoothstep(0.0, 1.0, _blend))


## Laufende Überblendung sofort beenden (Sichtprüfung, Tests).
func snap() -> void:
	_blend = 1.0


## Läuft gerade eine Überblendung?
func changing() -> bool:
	return _blend < 1.0


## Nachfolger von `from` für die Zufallszahl `roll` (0..1) nach den Gewichten in NEXT.
static func next_state(from: String, roll: float) -> String:
	var options: Array = NEXT[from]
	var total := 0.0
	for option in options:
		total += option[1]
	var at := roll * total
	for option in options:
		at -= option[1]
		if at < 0.0:
			return option[0]
	return options[options.size() - 1][0]


## Lineare Mischung zweier Kennwert-Sätze.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result := {}
	for key in b:
		result[key] = lerpf(a.get(key, b[key]), b[key], t)
	return result


func _go(next: String, seconds: float) -> void:
	_from = params()
	state = next
	_blend = 0.0
	_blend_s = seconds


func _hold_for(which: String) -> float:
	var range_min: Vector2 = HOLD_MIN[which]
	return _rng.randf_range(range_min.x, range_min.y) * 60.0
