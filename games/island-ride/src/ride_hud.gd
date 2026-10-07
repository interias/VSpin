## HUD der Inselfahrt (G5, Szene `scenes/hud.tscn`): gestaltete Anzeigen statt Textzeilen.
##
##   oben links   Werte-Panel: Abschnitt, Kadenz groß mit Bogen (Wohlfühlbereich 80–100 rpm), Tempo, Steigung
##                (Keil und Farbe: bergauf warm, steil rot, bergab kühl), Strecke, Zeit, Leistung – nur wenn die
##                Quelle Watt liefert, geschätzt immer mit „~“ (ADR-0004)
##   oben rechts  Minikarte (HudMinimap): Insel, Strecke, Landmarken, Fahrer-Pfeil
##   unten        Rundenfortschritt (Balken, Prozent, Restdistanz) und Höhenprofil mit Marker (HudProfile)
##   Message/Hint/Debug  Zustandsmeldung (Mitte), `set_grade`-Hinweis (über dem unteren Panel), Debug-Anzeige F3
##                (unter dem Werte-Panel) – Inhalte setzt die Hauptszene.
## Layout nur über Anker und Container (kein fester Bildschirmort): passt in 960×1040 wie in 1920×1080, mit und
## ohne `stretch/mode="canvas_items"`.
##
## Die Hauptszene übergibt pro Frame die Werte (`show_ride`, `show_lap`); Labels und Zeichnungen ändern sich nur,
## wenn sich der angezeigte Wert ändert. `readout()` liefert genau die sichtbaren Werte als Textzeilen.
class_name RideHud
extends CanvasLayer

## Ab diesem Betrag gilt die Steigung als bergauf/bergab, ab GRADE_STEEP als steil.
const GRADE_FLAT := 0.005
const GRADE_STEEP := 0.06
const COLOR_FLAT := Color(1.0, 1.0, 1.0)
const COLOR_UP := Color(1.0, 0.72, 0.36)
const COLOR_STEEP := Color(1.0, 0.45, 0.36)
const COLOR_DOWN := Color(0.5, 0.82, 1.0)
## Abstand von Hinweis und Debug-Anzeige zu den Panels (px).
const OVERLAY_GAP_PX := 8.0

@onready var _top: Control = %Top
@onready var _stats: Control = %Stats
@onready var _bottom: Control = %Bottom
@onready var _section: Control = %Section
@onready var _section_value: Label = %SectionValue
@onready var _gauge: HudGauge = %Gauge
@onready var _cadence_value: Label = %CadenceValue
@onready var _speed_value: Label = %SpeedValue
@onready var _grade_value: Label = %GradeValue
@onready var _grade_icon: HudGradeIcon = %GradeIcon
@onready var _distance_value: Label = %DistanceValue
@onready var _time_value: Label = %TimeValue
@onready var _power: Control = %Power
@onready var _power_value: Label = %PowerValue
@onready var _lap_bar: ProgressBar = %LapBar
@onready var _lap_percent: Label = %LapPercent
@onready var _lap_remaining: Label = %LapRemaining
@onready var _profile: HudProfile = %Profile
@onready var _minimap: HudMinimap = %Minimap
@onready var _hint: Label = $Hint
@onready var _debug: Label = $Debug

var _grade_color := COLOR_FLAT


func _ready() -> void:
	_top.resized.connect(_place_overlays)
	_bottom.resized.connect(_place_overlays)
	_stats.resized.connect(_place_overlays)
	_place_overlays()


## Strecke (und Insel-Welt, sonst null) für Höhenprofil und Minikarte – einmal nach dem Aufbau der Strecke.
func setup(track: Track, world: IslandWorld = null) -> void:
	_profile.setup(track)
	_minimap.setup(track, world)


## Fahrwerte: Kadenz (rpm), Tempo (km/h), Strecke (m), Zeit und Steigung als fertiger Anzeigetext, Steigung als
## Anteil (für Symbol und Farbe), Abschnitt ("" = ausblenden), Leistung als Anzeigetext ("" = ausblenden).
func show_ride(cadence_rpm: float, speed_kmh: float, distance_m: float, time_text: String, grade: float,
		grade_text: String, station: String, power_text: String) -> void:
	_gauge.value = cadence_rpm
	_cadence_value.text = "%d" % roundi(cadence_rpm)
	_speed_value.text = "%.1f" % speed_kmh
	_distance_value.text = "%.2f" % (distance_m / 1000.0)
	_time_value.text = time_text
	_grade_value.text = grade_text
	var color := grade_color(grade)
	if color != _grade_color:
		_grade_color = color
		_grade_value.add_theme_color_override("font_color", color)
	_grade_icon.color = color
	_grade_icon.direction = grade_direction(grade)
	_section.visible = not station.is_empty()
	_section_value.text = station
	_power.visible = not power_text.is_empty()
	_power_value.text = power_text


## Rundenfortschritt: Streckenposition `distance_m` (wie das Fahrmodell, nicht umgerechnet) zwischen Start
## `lap_start_m` und Ziel `finish_m`; Marker auf Profil und Karte an der Position innerhalb der Runde.
func show_lap(distance_m: float, lap_start_m: float, finish_m: float, lap_distance_m: float) -> void:
	var progress := lap_progress(distance_m, lap_start_m, finish_m)
	_lap_bar.value = progress * 100.0
	_lap_percent.text = "%d %%" % floori(progress * 100.0)
	_lap_remaining.text = "noch %.2f km" % (remaining_m(distance_m, finish_m) / 1000.0)
	_profile.distance_m = lap_distance_m
	_minimap.show_rider(lap_distance_m)


## Anteil 0..1 der Runde von `start_m` bis `finish_m` an Position `distance_m`.
static func lap_progress(distance_m: float, start_m: float, finish_m: float) -> float:
	if not is_finite(finish_m) or finish_m <= start_m:
		return 0.0
	return clampf((distance_m - start_m) / (finish_m - start_m), 0.0, 1.0)


## Restdistanz bis zum Ziel (m), nie negativ.
static func remaining_m(distance_m: float, finish_m: float) -> float:
	return maxf(finish_m - distance_m, 0.0) if is_finite(finish_m) else 0.0


## Farbe der Steigungsanzeige: bergauf warm, ab GRADE_STEEP rot, bergab kühl, flach neutral.
static func grade_color(grade: float) -> Color:
	if grade >= GRADE_STEEP:
		return COLOR_STEEP
	if grade >= GRADE_FLAT:
		return COLOR_UP
	return COLOR_DOWN if grade <= -GRADE_FLAT else COLOR_FLAT


## Richtung für das Steigungssymbol: 1 bergauf, −1 bergab, 0 flach.
static func grade_direction(grade: float) -> int:
	if absf(grade) < GRADE_FLAT:
		return 0
	return 1 if grade > 0.0 else -1


## Die sichtbaren Werte als Textzeilen „Name: Wert Einheit“, genau wie angezeigt (Tests, Logs), z. B.
## "Kadenz: 90 rpm", "Steigung: +6.0 %", "Leistung: ~142 W", "Runde: 34 % (noch 6.08 km)".
func readout() -> String:
	var lines := []
	for field in [%Cadence, %Speed, %Distance, %Time, %Grade, _section, _power]:
		if not field.is_visible_in_tree():
			continue
		var caption: Label = field.get_node("Caption")
		var value: Label = field.find_child("*Value", true, false)
		var unit: Label = field.find_child("Unit", true, false)
		var text := "%s: %s" % [caption.text, value.text]
		if unit != null and not unit.text.is_empty():
			text += " " + unit.text
		lines.append(text)
	lines.append("Runde: %s (%s)" % [_lap_percent.text, _lap_remaining.text])
	return "\n".join(lines)


## Hinweis über dem unteren Panel, Debug-Anzeige unter dem Werte-Panel – beide folgen dem Layout.
func _place_overlays() -> void:
	if _hint == null:
		return
	var bottom_top := _bottom.get_global_rect().position.y
	_hint.offset_top = bottom_top - OVERLAY_GAP_PX - 28.0
	_hint.offset_bottom = bottom_top - OVERLAY_GAP_PX
	var stats := _stats.get_global_rect()
	_debug.offset_top = stats.end.y + OVERLAY_GAP_PX
	_debug.offset_bottom = stats.end.y + OVERLAY_GAP_PX + 150.0
