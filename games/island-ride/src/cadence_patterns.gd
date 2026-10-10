## Kadenzmuster (#50, Spec #27): erkennt aus dem ungeglätteten Kadenzverlauf (`cadence_raw`, ADR-0004 Nachtrag #45) vier
## Gesten. Reine Logik: Eingabe sind Kadenz und Schrittdauer (`feed`), Ausgabe die in diesem Schritt erkannten Muster.
##
##   Antritt     Kadenz − Minimum der letzten `antritt_window_s` (2 s) ≥ `antritt_rise_rpm` (+25 rpm), das Minimum
##               ≥ `antritt_min_rpm` (30 rpm; Anfahren aus dem Stand ist kein Antritt). Löst einmal aus, wieder scharf,
##               wenn der Anstieg im Fenster unter `antritt_rearm_rise_rpm` (+15 rpm) fällt (sonst doppelt im Rauschen).
##   Gleichmaß   `steady_hold_s` (10 s) lang liegen alle Werte innerhalb ±`steady_band_rpm` (3 rpm) um die Mitte des
##               Fensters (größter − kleinster Wert ≤ 2 × 3 rpm), der kleinste ≥ `steady_min_rpm` (40 rpm; Stillstand
##               ist kein Gleichmaß). Hält die Ruhe an, kommt es nach weiteren 10 s wieder.
##   Innehalten  Kadenz < `pause_below_rpm` (10 rpm) ununterbrochen `pause_hold_s` (2 s) lang, einmal je Phase – und nur
##               nachdem zuvor getreten wurde (≥ `pause_armed_rpm`, 30 rpm): wer von Anfang an steht, hält nicht inne.
##   Rhythmus    Die Kadenz pulst im gleichmäßigen Takt: je Puls steigt sie um mindestens `rhythm_swing_rpm` (8 rpm)
##               über ihren letzten Tiefpunkt (Anstiegsflanke, Tiefpunkt ≥ `rhythm_min_rpm`) und fällt wieder; `rhythm_beats`
##               (4) Flanken hintereinander, Abstände zwischen `rhythm_period_min_s` und `rhythm_period_max_s`, jeder
##               Abstand höchstens `rhythm_tolerance` (25 %) vom mittleren entfernt. Der Takt ist der des Fahrers selbst
##               (die Geste „Takt treffen“): die Takt-Tore (#48, `RhythmGates`) geben dagegen Schläge vor und prüfen
##               die Kadenz in der Zone – ein anderer Baustein, die Geste braucht keine Zone und läuft in jeder
##               Herausforderung.
##
## Auswertung wie im Spiel: der letzte Wert gilt bis zum nächsten (der Bus meldet mit 250 ms bis 1 s, die Bilder sind
## schneller). Die Schwellen sind Daten an einer Stelle (`THRESHOLDS`), mit Überschreibung im Konstruktor; endgültig
## werden sie mit dem echten Gerät (JC312, #1) und aus Simulator/Replay kalibriert.
class_name CadencePatterns
extends RefCounted

const ANTRITT := "antritt"
const GLEICHMASS := "gleichmass"
const INNEHALTEN := "innehalten"
const RHYTHMUS := "rhythmus"
## Alle Muster in fester Reihenfolge (auch die Reihenfolge der Ausgabe von `feed`).
const IDS := [ANTRITT, GLEICHMASS, INNEHALTEN, RHYTHMUS]
const NAMES := {ANTRITT: "Antritt", GLEICHMASS: "Gleichmaß", INNEHALTEN: "Innehalten", RHYTHMUS: "Rhythmus"}

## Die Schwellen aller Muster (rpm bzw. s) – vorläufig, siehe Kopf.
const THRESHOLDS := {
	"antritt_rise_rpm": 25.0,
	"antritt_window_s": 2.0,
	"antritt_min_rpm": 30.0,
	"antritt_rearm_rise_rpm": 15.0,
	"steady_band_rpm": 3.0,
	"steady_hold_s": 10.0,
	"steady_min_rpm": 40.0,
	"pause_below_rpm": 10.0,
	"pause_hold_s": 2.0,
	"pause_armed_rpm": 30.0,
	"rhythm_swing_rpm": 8.0,
	"rhythm_beats": 4,
	"rhythm_period_min_s": 1.2,
	"rhythm_period_max_s": 4.0,
	"rhythm_tolerance": 0.25,
	"rhythm_min_rpm": 30.0,
}
## Rundungsspielraum für Zeitvergleiche (Summen von Schrittdauern).
const EPSILON := 1e-6

## Die geltenden Schwellen (`THRESHOLDS` mit Überschreibungen).
var thresholds := {}

var _now := 0.0
## Wertwechsel: {t: Beginn der Gültigkeit, v: Kadenz}; der letzte Wert gilt bis jetzt.
var _changes: Array = []
var _antritt_armed := true
var _steady_from := 0.0
var _pause_s := 0.0
var _pause_armed := false
var _pulse_high := false
var _pulse_extreme := NAN
var _edges: Array = []


## `overrides`: Schwellen aus `THRESHOLDS`, die anders gelten sollen (unbekannte Schlüssel fallen auf).
func _init(overrides: Dictionary = {}) -> void:
	thresholds = THRESHOLDS.duplicate()
	for key in overrides:
		if THRESHOLDS.has(key):
			thresholds[key] = overrides[key]
		else:
			push_warning("CadencePatterns: unbekannte Schwelle %s" % key)


## Zurück auf Anfang (neue Fahrt).
func reset() -> void:
	_now = 0.0
	_changes.clear()
	_antritt_armed = true
	_steady_from = 0.0
	_pause_s = 0.0
	_pause_armed = false
	_pulse_high = false
	_pulse_extreme = NAN
	_edges.clear()


## Ein Schritt von `delta_s` Sekunden mit der ungeglätteten Kadenz `cadence_rpm`. Liefert die in diesem Schritt
## erkannten Muster (IDS in fester Reihenfolge, meist leer). Schritte ohne Dauer zählen nicht.
func feed(cadence_rpm: float, delta_s: float) -> Array:
	var found := []
	if delta_s <= 0.0:
		return found
	if _changes.is_empty() or _changes[-1]["v"] != cadence_rpm:
		_changes.append({"t": _now, "v": cadence_rpm})
	_now += delta_s
	_trim()
	if _antritt(cadence_rpm):
		found.append(ANTRITT)
	if _steady():
		found.append(GLEICHMASS)
	if _pause(cadence_rpm, delta_s):
		found.append(INNEHALTEN)
	if _rhythm(cadence_rpm):
		found.append(RHYTHMUS)
	return found


## Größter und kleinster Wert der letzten `window_s` Sekunden (der zu Fensterbeginn geltende Wert zählt mit).
func _extremes(window_s: float) -> Vector2:
	var from := _now - window_s + EPSILON
	var low := INF
	var high := -INF
	for i in range(_changes.size() - 1, -1, -1):
		var v: float = _changes[i]["v"]
		low = minf(low, v)
		high = maxf(high, v)
		if _changes[i]["t"] <= from:
			break
	return Vector2(low, high)


## Verlauf vor dem längsten Fenster vergessen (den zu dessen Beginn geltenden Wert behalten).
func _trim() -> void:
	var longest := maxf(float(thresholds["steady_hold_s"]), float(thresholds["antritt_window_s"]))
	var from := _now - longest
	while _changes.size() > 1 and _changes[1]["t"] <= from:
		_changes.pop_front()


func _antritt(cadence_rpm: float) -> bool:
	var window := _extremes(float(thresholds["antritt_window_s"]))
	var rise := cadence_rpm - window.x
	if _antritt_armed:
		if rise >= float(thresholds["antritt_rise_rpm"]) - EPSILON:
			# Auch ein Anstieg aus dem Stand verbraucht die Auslösung – sonst käme der Antritt, sobald der Tiefpunkt aus
			# dem Fenster wandert und das Minimum über die Schwelle steigt.
			_antritt_armed = false
			return window.x >= float(thresholds["antritt_min_rpm"])
	elif rise < float(thresholds["antritt_rearm_rise_rpm"]):
		_antritt_armed = true
	return false


func _steady() -> bool:
	var hold := float(thresholds["steady_hold_s"])
	if _now - _steady_from < hold - EPSILON:
		return false
	var window := _extremes(hold)
	if window.x < float(thresholds["steady_min_rpm"]) or window.y - window.x > 2.0 * float(thresholds["steady_band_rpm"]) + EPSILON:
		return false
	_steady_from = _now  # das nächste Gleichmaß braucht ein neues Fenster
	return true


func _pause(cadence_rpm: float, delta_s: float) -> bool:
	if cadence_rpm >= float(thresholds["pause_armed_rpm"]):
		_pause_armed = true
	if cadence_rpm >= float(thresholds["pause_below_rpm"]):
		_pause_s = 0.0
		return false
	_pause_s += delta_s
	if _pause_armed and _pause_s >= float(thresholds["pause_hold_s"]) - EPSILON:
		_pause_armed = false
		return true
	return false


func _rhythm(cadence_rpm: float) -> bool:
	var swing := float(thresholds["rhythm_swing_rpm"])
	if is_nan(_pulse_extreme):
		_pulse_extreme = cadence_rpm
	if not _pulse_high:
		_pulse_extreme = minf(_pulse_extreme, cadence_rpm)
		if cadence_rpm - _pulse_extreme < swing:
			return false
		var base := _pulse_extreme
		_pulse_high = true
		_pulse_extreme = cadence_rpm
		if base < float(thresholds["rhythm_min_rpm"]):
			_edges.clear()  # aus dem Stand oder nach dem Absetzen: kein Takt
			return false
		return _rising_edge()
	_pulse_extreme = maxf(_pulse_extreme, cadence_rpm)
	if _pulse_extreme - cadence_rpm >= swing:
		_pulse_high = false
		_pulse_extreme = cadence_rpm
	return false


## Eine Anstiegsflanke zum Zeitpunkt `_now`: true, wenn die letzten `rhythm_beats` Flanken einen gleichmäßigen Takt bilden.
func _rising_edge() -> bool:
	var beats := maxi(int(thresholds["rhythm_beats"]), 2)
	if not _edges.is_empty():
		var gap: float = _now - _edges[-1]
		if gap < float(thresholds["rhythm_period_min_s"]) or gap > float(thresholds["rhythm_period_max_s"]):
			_edges.clear()  # zu schnell (Zittern) oder zu lahm (Pause): der Takt beginnt neu
	_edges.append(_now)
	while _edges.size() > beats:
		_edges.pop_front()
	if _edges.size() < beats:
		return false
	var mean: float = (_edges[-1] - _edges[0]) / (beats - 1)
	for i in range(1, beats):
		if absf((_edges[i] - _edges[i - 1]) - mean) > mean * float(thresholds["rhythm_tolerance"]) + EPSILON:
			return false
	_edges = [_now]  # weitertreten im Takt: das nächste Mal nach `beats - 1` weiteren Pulsen
	return true
