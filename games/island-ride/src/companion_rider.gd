## Toni fährt mit (Spec #91) – reine Logik ohne Szene und Bus: wo der Begleiter neben dem Fahrer fährt und wann er redet.
## Die Szene (`scenes/main.gd`) setzt daraus Position und Pose seiner Figur; Vorbild für die Aufteilung ist Ghost.
##
##   Lage      `longitudinal_m()` längs zum Fahrer (+ = vor ihm) und `lateral_m()` seitlich (Betrag; die Szene setzt ihn
##             rechts in Fahrtrichtung, der Ghost fährt links). Beides folgt nur der Fahrzeit und der Steigung – kein
##             Zufall, dieselbe Fahrt sieht immer gleich aus. Längs: weiches Zurückfallen und Aufschließen (zwei
##             überlagerte Schwingungen), am Anstieg etwas zurück, bergab vor; immer zwischen LONG_MIN_M und LONG_MAX_M.
##             Seitlich bleibt er immer mindestens LATERAL_M − LATERAL_SWAY_M neben dem Fahrer: nie in dessen Fahrlinie,
##             also nie vor der Kamera, und nie auf dem Ghost (links).
##   Reden     `set_speaking` aus `companion_status` (`speaking`): der Kopf dreht sich zum Fahrer (`head_turn_rad()`), eine
##             Hand löst sich dezent vom Lenker (`hand_raise()`). Ohne Reden (auch bei „heiser“) fährt er stumm weiter.
## Nur Darstellung: nichts davon wirkt auf Tempo, Wertung oder Beute (ADR-0010, ADR-0011).
class_name CompanionRider
extends RefCounted

## Seitlicher Sollabstand zum Fahrer (m) und Schwankung darum.
const LATERAL_M := 1.5
const LATERAL_SWAY_M := 0.12
const LATERAL_PERIOD_S := 17.0
## Längs zum Fahrer (m): Mitte, Schwankung (zwei Schwingungen), Anteil der Steigung; Grenzen sind LONG_MIN_M/LONG_MAX_M.
const LONG_CENTER_M := 1.0
const LONG_SWING_SLOW_M := 0.55
const LONG_SWING_FAST_M := 0.25
const LONG_PERIOD_SLOW_S := 37.0
const LONG_PERIOD_FAST_S := 13.0
## Bergauf zurück, bergab vor: Meter je Anteil Steigung, Steigung begrenzt auf ±GRADE_LIMIT, 2 s geglättet.
const GRADE_LIMIT := 0.10
const GRADE_SHIFT_M := 12.0
const GRADE_SMOOTHING_S := 2.0
const LONG_MIN_M := -1.0
const LONG_MAX_M := 3.0
## Kopfdrehung zum Fahrer beim Reden (rad), Zeitkonstante des Ein-/Ausblendens (s), Tempo der Geste (Hz).
const HEAD_TURN_MAX_RAD := deg_to_rad(35.0)
const TALK_SMOOTHING_S := 0.2
const GESTURE_HZ := 1.1

## Eigenes Farbschema (Material-Schlüssel wie RiderModel.wear): orange Trikot, grüner Rahmen, gelber Helm – deckend, damit er
## sich vom halbtransparenten blauen Ghost und vom Fahrer (Garderobe: blau/rot/weiß) klar abhebt.
const OUTFIT := {
	"jersey": Color(1.0, 0.55, 0.05),
	"jersey_band": Color(1.0, 0.92, 0.55),
	"frame": Color(0.1, 0.5, 0.25),
	"helmet": Color(1.0, 0.85, 0.1),
	"helmet_stripe": Color(0.1, 0.5, 0.25),
}

var _time_s := 0.0
var _grade := 0.0
var _long_m := LONG_CENTER_M
var _long_speed_mps := 0.0
var _speaking := false
var _talk := 0.0
var _gesture_phase := 0.0


func _init() -> void:
	_long_m = _target_long_m()


## Zurück auf den Anfang der Fahrt.
func reset() -> void:
	_time_s = 0.0
	_grade = 0.0
	_speaking = false
	_talk = 0.0
	_gesture_phase = 0.0
	_long_m = _target_long_m()
	_long_speed_mps = 0.0


## Redet Toni gerade? (`companion_status.speaking`, nicht bei „heiser“.)
func set_speaking(value: bool) -> void:
	_speaking = value


## Ein Zeitschritt: `grade` ist die Steigung an der Fahrerposition, `moving` false in der Pause (dann steht die
## Schwankung still, das Reden läuft weiter).
func advance(delta_s: float, grade: float, moving: bool = true) -> void:
	if delta_s <= 0.0:
		return
	var talk_target := 1.0 if _speaking else 0.0
	_talk += (talk_target - _talk) * (1.0 - exp(-delta_s / TALK_SMOOTHING_S))
	if _talk > 0.01:
		_gesture_phase = fposmod(_gesture_phase + TAU * GESTURE_HZ * delta_s, TAU)
	if not moving:
		_long_speed_mps = 0.0
		return
	_time_s += delta_s
	_grade += (clampf(grade, -GRADE_LIMIT, GRADE_LIMIT) - _grade) * (1.0 - exp(-delta_s / GRADE_SMOOTHING_S))
	var before := _long_m
	_long_m = _target_long_m()
	_long_speed_mps = (_long_m - before) / delta_s


## Abstand längs zum Fahrer (m, + = vor ihm).
func longitudinal_m() -> float:
	return _long_m


## Änderung des Längsabstands (m/s): Toni ist um so viel schneller als der Fahrer.
func longitudinal_speed_mps() -> float:
	return _long_speed_mps


## Seitlicher Abstand zum Fahrer (m, immer positiv; die Szene setzt ihn auf die rechte Seite).
func lateral_m() -> float:
	return LATERAL_M + LATERAL_SWAY_M * sin(TAU * _time_s / LATERAL_PERIOD_S + 0.4)


## Kopfdrehung zum Fahrer (rad, positiv = nach links; Toni fährt rechts vom Fahrer).
func head_turn_rad() -> float:
	return HEAD_TURN_MAX_RAD * _talk


## Wie weit die Hand vom Lenker gelöst ist (0 = am Lenker, 1 = oben der Geste); nur beim Reden, mit leichtem Auf und Ab.
func hand_raise() -> float:
	return _talk * (0.75 + 0.25 * sin(_gesture_phase))


func _target_long_m() -> float:
	var swing := LONG_SWING_SLOW_M * sin(TAU * _time_s / LONG_PERIOD_SLOW_S + 0.6) \
			+ LONG_SWING_FAST_M * sin(TAU * _time_s / LONG_PERIOD_FAST_S + 1.9)
	return clampf(LONG_CENTER_M + swing - _grade * GRADE_SHIFT_M, LONG_MIN_M, LONG_MAX_M)
