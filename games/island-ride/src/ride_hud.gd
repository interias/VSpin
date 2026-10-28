## HUD der Inselfahrt (G5, Szene `scenes/hud.tscn`): gestaltete Anzeigen statt Textzeilen.
##
##   oben links   Werte-Panel: Abschnitt, Kadenz groß mit Bogen (Wohlfühlbereich 80–100 rpm), Tempo, Steigung
##                (Keil und Farbe: bergauf warm, steil rot, bergab kühl), Strecke, Zeit (der Fahrt), Rundenzeit,
##                Leistung – nur wenn die Quelle Watt liefert, geschätzt immer mit „~“ (ADR-0004); Puls (#64) in bpm in der
##                Farbe seiner Zone mit „Z1“–„Z5“, ohne Zonen weiß ohne Zone, ohne Wert „--“; fehlt jede Pulsquelle, bleibt
##                die Anzeige weg. Darunter, nur im vollen Layout, die Verlaufskurve der letzten 3 Minuten (HudPulse)
##   oben rechts  Minikarte (HudMinimap): Insel, Strecke, Landmarken, Fahrer-Pfeil
##   unten        Runde („Runde 2 / 3“, endlos „Runde 2“, bei einer Runde nur „Runde“), Rundenfortschritt (Balken,
##                Prozent, Restdistanz; mit Ghost (#32) der Abstand zu ihm in Sekunden: „+1.4 s“ = dahinter, rot;
##                „-0.8 s“ = davor, grün) und Höhenprofil mit Marker (HudProfile)
##   Celebration  dezente Einblendung „Neue Bestzeit!“ über dem unteren Panel, blendet nach CELEBRATION_S aus (#31);
##                ebenso das Ergebnis beim Verlassen eines Segments (#33), ein neuer Erfolg und ein Levelaufstieg (#35);
##                mehrere zugleich laufen nacheinander
##   Segment      im Segment an derselben Stelle dessen Name und Live-Zeit („Bergwertung  3:12.4“, #33); eine
##                Einblendung hat Vorrang
##   Training   (#37) im unteren Panel über der Runde: Phase, Zielkadenz, Restzeit der Phase und die nächste Phase;
##                die Ansage zum Widerstandsknopf („In 8 s: Widerstand 2 Stufen hoch, 100 rpm halten“) steht groß über
##                der Einblendung
##   Zone       (#58) im Training unter der Trainingszeile: Zonenbalken (ZoneBar) mit Zielbereich und Kadenz als Marke,
##                daneben der Zustand in Worten („zu niedrig“, „im Bereich“, „zu hoch“; Farbe wie die Marke) und der
##                Treffer der laufenden Phase (die Bewertung aus Training, keine eigene Rechnung)
##   Arcade     (#46) an derselben Stelle: Herausforderung, Zielzone, Restzeit (vor dem Start: Meter bis dahin) und
##                Punkte des Laufs; während Zone halten darunter der Zonenbalken mit dem Fortschritt statt des Treffers
##   Popups     (#49) Zahlen-Popups im Arcade: „+100“ für Punkte, der Name eines Fundes in der Farbe seiner Seltenheit –
##                steigen über der Bildmitte auf und blenden aus (`popup`), mehrere zugleich übereinander
##   Landmark     Panorama-Moment (#43): Name der Sehenswürdigkeit oben im freien Feld, blendet weich ein und aus
##   CameraView   Kameraperspektive (#59): nach dem Wechsel mit `C` kurz ihr Name („Kamera: Nah“) unter dem Landmark
##   Message/Hint/Debug  Zustandsmeldung (mittig zwischen oben und unten), `set_grade`-Hinweis (über dem unteren
##                Panel), Debug-Anzeige F3 (unter dem Werte-Panel) – Inhalte setzt die Hauptszene.
## Layout nur über Anker und Container (kein fester Bildschirmort): passt in 960×1040 wie in 1920×1080, mit und
## ohne `stretch/mode="canvas_items"`.
## Niedrige Fenster (Nacharbeit #26): Ansage und Ergebnis skalieren mit der Fensterhöhe (Höhe/1080, mindestens
## MIN_TEXT_SCALE) und liegen im freien Streifen zwischen den Panels; das Ergebnis wird so weit verkleinert, dass es
## hineinpasst. Unter COMPACT_BELOW_PX klappen die Panels zu Leisten zusammen: oben die Werte in einer Zeile ohne
## Minikarte, unten Runde (und Training) ohne Höhenprofil (`compact`); der Puls bleibt in der Leiste (Zahl, Zone, Farbe), nur die
## Verlaufskurve entfällt.
##
## Die Hauptszene übergibt pro Frame die Werte (`show_ride`, `show_pulse`, `show_lap`); Labels und Zeichnungen ändern sich nur,
## wenn sich der angezeigte Wert ändert. `readout()` liefert genau die sichtbaren Werte als Textzeilen.
class_name RideHud
extends CanvasLayer

## Eine Einblendung (Celebration) erscheint gerade – je sichtbarer Einblendung einmal (#44: dezenter Klang).
signal celebration_shown(text: String)

## Ab diesem Betrag gilt die Steigung als bergauf/bergab, ab GRADE_STEEP als steil.
const GRADE_FLAT := 0.005
const GRADE_STEEP := 0.06
const COLOR_FLAT := Color(1.0, 1.0, 1.0)
const COLOR_UP := Color(1.0, 0.72, 0.36)
const COLOR_STEEP := Color(1.0, 0.45, 0.36)
const COLOR_DOWN := Color(0.5, 0.82, 1.0)
## Abstand von Hinweis und Debug-Anzeige zu den Panels (px).
const OVERLAY_GAP_PX := 8.0
## Dauer der Einblendung „Neue Bestzeit!“ (s), davon die letzte Sekunde Ausblenden.
const CELEBRATION_S := 4.0
## Ein- und Ausblenden des Namens einer Sehenswürdigkeit (s, #43).
const LANDMARK_FADE_S := 0.6
## Einblendung der Kameraperspektive (s, #59), davon die letzten LANDMARK_FADE_S Ausblenden.
const CAMERA_VIEW_S := 1.5
## Farbe des Ghost-Abstands: hinter dem Ghost bzw. vor ihm (#32).
const COLOR_BEHIND := Color(1.0, 0.55, 0.45)
const COLOR_AHEAD := Color(0.5, 0.92, 0.55)
## Anzeige ohne Pulswert (Gerät weg, `stale`, kein Puls) und ihre Farbe; mit Wert ohne Zonen ist die Zahl weiß (#64).
const PULSE_NONE_TEXT := "--"
const COLOR_PULSE_NONE := Color(0.74, 0.8, 0.85)
## Unter dieser Fensterhöhe (px) klappen die Panels zu Leisten zusammen.
const COMPACT_BELOW_PX := 760.0
## Kleinster Faktor für Ansage und Ergebnis (Fensterhöhe/1080); das Ergebnis schrumpft bis MIN_MESSAGE_FONT_PX weiter.
const MIN_TEXT_SCALE := 0.6
const MIN_MESSAGE_FONT_PX := 11
## Werte-Raster: Spalten normal und als Leiste.
const GRID_COLUMNS := 2
const GRID_COLUMNS_COMPACT := 7
## Abstände (px) zwischen den Werten und zwischen Kadenz und Werten, normal und in der Leiste: dort enger, damit mit
## Leistung und Puls (#64) alle in eine Zeile passen, auch bei 1152 px und einer Fahrzeit über eine Stunde.
const GRID_SEPARATION_PX := 24
const GRID_SEPARATION_COMPACT_PX := 12
const MAIN_SEPARATION_PX := 20
const MAIN_SEPARATION_COMPACT_PX := 12
## Kadenz-Bogen (px) normal und als Leiste, dort mit kleinerer Zahl.
const GAUGE_PX := 150.0
const GAUGE_COMPACT_PX := 120.0
const CADENCE_COMPACT_FONT_PX := 44
## Zahlen-Popup (#49): Dauer (s), Weg nach oben (px), Schriftgröße, Lage (Anteil der Fensterhöhe), Abstand gestapelter
## Popups (px) und Standardfarbe (Punkte, gold).
const POPUP_S := 1.8
const POPUP_RISE_PX := 70.0
const POPUP_FONT_PX := 40
const POPUP_AT := 0.34
const POPUP_STACK_PX := 52.0
const COLOR_POPUP := Color(1.0, 0.86, 0.35)

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
@onready var _lap_time_value: Label = %LapTimeValue
@onready var _segment: Label = %Segment
@onready var _power: Control = %Power
@onready var _pulse: Control = %Pulse
@onready var _pulse_value: Label = %PulseValue
@onready var _pulse_unit: Label = %Unit
@onready var _pulse_zone: Label = %PulseZone
@onready var _pulse_graph: HudPulse = %PulseGraph
@onready var _ghost: Control = %Ghost
@onready var _ghost_value: Label = %GhostValue
@onready var _power_value: Label = %PowerValue
@onready var _lap_caption: Label = %LapCaption
@onready var _celebration: Label = %Celebration
@onready var _training: Control = %Training
@onready var _phase_value: Label = %PhaseValue
@onready var _target_value: Label = %TargetValue
@onready var _remaining_value: Label = %RemainingValue
@onready var _next_value: Label = %NextValue
@onready var _announcement: Label = %Announcement
@onready var _arcade: Control = %Arcade
@onready var _challenge_value: Label = %ChallengeValue
@onready var _challenge_target: Label = %ChallengeTarget
@onready var _challenge_remaining: Label = %ChallengeRemaining
@onready var _points_value: Label = %PointsValue
@onready var _zone: Control = %Zone
@onready var _zone_bar: ZoneBar = %ZoneBar
@onready var _zone_state: Label = %ZoneState
@onready var _zone_score: Label = %ZoneScore
@onready var _landmark: Label = %Landmark
@onready var _camera_view: Label = %CameraView
@onready var _lap_bar: ProgressBar = %LapBar
@onready var _lap_percent: Label = %LapPercent
@onready var _lap_remaining: Label = %LapRemaining
@onready var _profile: HudProfile = %Profile
@onready var _minimap: HudMinimap = %Minimap
@onready var _hint: Label = $Hint
@onready var _debug: Label = $Debug
@onready var _message: Label = $Message
@onready var _grid: GridContainer = $Layout/Rows/Top/Stats/Box/Main/Grid
@onready var _message_font_px: int = _message.get_theme_font_size("font_size")
@onready var _announcement_font_px: int = _announcement.get_theme_font_size("font_size")

## Panels als Leisten (Fensterhöhe unter COMPACT_BELOW_PX).
var compact := false
## Wofür die Meldung zuletzt eingepasst wurde ([Text, Streifenhöhe, Fensterhöhe]).
var _message_fitted_for := []
var _grade_color := COLOR_FLAT
## Pulsanzeige gerade sichtbar (`show_pulse`), mit Wert, und ihre Farbe.
var _pulse_shown := false
var _pulse_has_value := false
var _pulse_color := Color.TRANSPARENT  # durchsichtig = noch keine Farbe gesetzt
## Laufendes Segment für `readout()` („Bergwertung: 3:12.4“, "" = keins).
var _segment_line := ""
var _celebration_tween: Tween
var _landmark_tween: Tween
var _camera_view_tween: Tween
## Eingereihte Einblendungen, die nach der laufenden folgen (#35).
var _celebration_queue: Array = []
## Ebene der Zahlen-Popups (#49).
var _popups: Control


func _ready() -> void:
	_top.resized.connect(_place_overlays)
	_bottom.item_rect_changed.connect(_place_overlays)  # mit der Lage: wächst das Panel (#37), kam `resized` zu früh
	_stats.resized.connect(_place_overlays)
	(_celebration.get_parent() as Control).resized.connect(_place_overlays)
	_message.minimum_size_changed.connect(_fit_message)  # neuer Text
	_popups = Control.new()
	_popups.name = "Popups"
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
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


## Puls (#64): `bpm` (NAN, 0 oder negativ = kein Wert → „--“), `zones` sind die der laufenden Fahrt (null oder ohne Zonen:
## nur bpm), `shown` blendet die Anzeige ein – die Hauptszene blendet sie aus, solange es weder ein Pulsgerät noch einen
## Wert gibt. `time_s` ist die Fahrzeit (für die Verlaufskurve; sie steht in Pausen).
func show_pulse(bpm: float, zones: HeartRateZones, shown: bool, time_s: float) -> void:
	_pulse_shown = shown
	_pulse.visible = shown
	_update_pulse_graph()
	if not shown:
		return
	_pulse_has_value = pulse_valid(bpm)
	_pulse_value.text = pulse_text(bpm)
	_update_pulse_unit()
	var zone := pulse_zone(bpm, zones)
	_pulse_zone.text = "Z%d" % zone if zone > 0 else ""
	var color := pulse_color(bpm, zones)
	if color != _pulse_color:
		_pulse_color = color
		_pulse_value.add_theme_color_override("font_color", color)
		_pulse_zone.add_theme_color_override("font_color", color)
	_pulse_graph.push(time_s, bpm if _pulse_has_value else NAN, zones)


## Verlaufskurve leeren (neue Fahrt).
func reset_pulse() -> void:
	_pulse_graph.reset()


## Rundenfortschritt: Streckenposition `distance_m` (wie das Fahrmodell, nicht umgerechnet) zwischen Start
## `lap_start_m` und Ziel `finish_m`; Marker auf Profil und Karte an der Position innerhalb der Runde.
func show_lap(distance_m: float, lap_start_m: float, finish_m: float, lap_distance_m: float) -> void:
	var progress := lap_progress(distance_m, lap_start_m, finish_m)
	_lap_bar.value = progress * 100.0
	_lap_percent.text = "%d %%" % floori(progress * 100.0)
	_lap_remaining.text = "noch %.2f km" % (remaining_m(distance_m, finish_m) / 1000.0)
	_profile.distance_m = lap_distance_m
	_minimap.show_rider(lap_distance_m)


## Runde `number` (ab 1) von `total` (0 = endlos) und Zeit der laufenden Runde als fertiger Anzeigetext.
func show_lap_count(number: int, total: int, lap_time_text: String) -> void:
	_lap_caption.text = lap_caption(number, total)
	_lap_time_value.text = lap_time_text


## Laufendes Segment: Name als Beschriftung und Live-Zeit als fertiger Anzeigetext; "" als Name blendet aus.
## Solange eine Einblendung läuft, bleibt die Live-Zeit verborgen.
func show_segment(segment_name: String, time_text: String) -> void:
	_segment_line = "" if segment_name.is_empty() else "%s: %s" % [segment_name, time_text]
	_segment.text = "%s  %s" % [segment_name, time_text]
	_segment.visible = not segment_name.is_empty() and not _celebration.visible


## Abstand zum Ghost als fertiger Anzeigetext ("" = kein Ghost, ausblenden); `behind`: hinter dem Ghost (Farbe).
func show_ghost(gap_text: String, behind: bool) -> void:
	_ghost.visible = not gap_text.is_empty()
	_ghost_value.text = gap_text
	var color := COLOR_BEHIND if behind else COLOR_AHEAD
	if _ghost_value.get_theme_color("font_color") != color:
		_ghost_value.add_theme_color_override("font_color", color)


## Training (#37): Phase, Zielkadenz, Restzeit der Phase und nächste Phase als fertige Anzeigetexte; "" als Phase
## blendet die Zeile aus.
func show_training(phase_text: String, target_text: String, remaining_text: String, next_text: String) -> void:
	_training.visible = not phase_text.is_empty()
	_phase_value.text = phase_text
	_target_value.text = target_text
	_remaining_value.text = remaining_text
	_next_value.text = next_text


## Arcade (#46): Herausforderung, Zielzone, Restzeit bzw. Weg bis zum Start und Punkte als fertige Anzeigetexte; ""
## als Herausforderung blendet die Zeile aus.
func show_arcade(challenge_text: String, target_text: String, remaining_text: String, points_text: String) -> void:
	_arcade.visible = not challenge_text.is_empty()
	_challenge_value.text = challenge_text
	_challenge_target.text = target_text
	_challenge_remaining.text = remaining_text
	_points_value.text = points_text


## Zonenbalken (#58): Zielbereich `range_min`..`range_max` (Grenzen eingeschlossen), aktuelle Kadenz `cadence_rpm`
## und der Treffer der laufenden Phase als fertiger Anzeigetext (z. B. „87 %“); `score_caption` benennt ihn (Arcade:
## „Fortschritt“, #46).
func show_zone(range_min: float, range_max: float, cadence_rpm: float, score_text: String,
		score_caption: String = "Treffer") -> void:
	_zone.visible = true
	(_zone.get_node("ScoreCaption") as Label).text = score_caption
	_zone_bar.show_zone(range_min, range_max, cadence_rpm)
	var zone := _zone_bar.state()
	_zone_state.text = ZoneBar.state_text(zone)
	var color := ZoneBar.state_color(zone)
	if _zone_state.get_theme_color("font_color") != color:
		_zone_state.add_theme_color_override("font_color", color)
	_zone_score.text = score_text


## Zonenbalken ausblenden (ohne Training oder laufende Herausforderung, im Ergebnis).
func hide_zone() -> void:
	_zone.visible = false


## Ansage zum Widerstandsknopf ("" = keine).
func show_announcement(text: String) -> void:
	_announcement.visible = not text.is_empty()
	_announcement.text = text


## Name einer Sehenswürdigkeit im Panorama-Moment (#43): blendet ein, steht und ist nach `seconds` wieder weg; ""
## blendet sofort aus.
func show_landmark(text: String, seconds: float = 4.0) -> void:
	if _landmark_tween != null:
		_landmark_tween.kill()
	_landmark.text = text
	_landmark.visible = not text.is_empty()
	if text.is_empty():
		return
	_landmark.modulate.a = 0.0
	_landmark_tween = create_tween()
	_landmark_tween.tween_property(_landmark, "modulate:a", 1.0, LANDMARK_FADE_S)
	_landmark_tween.tween_interval(maxf(seconds - 2.0 * LANDMARK_FADE_S, 0.0))
	_landmark_tween.tween_property(_landmark, "modulate:a", 0.0, LANDMARK_FADE_S)
	_landmark_tween.tween_callback(_landmark.hide)


## Eingeblendeter Name einer Sehenswürdigkeit ("" = keiner).
func landmark() -> String:
	return _landmark.text if _landmark.visible else ""


## Name der Kameraperspektive (#59) kurz einblenden; ein neuer Name ersetzt den alten sofort.
func show_camera_view(perspective: String) -> void:
	if _camera_view_tween != null:
		_camera_view_tween.kill()
	_camera_view.text = "Kamera: %s" % perspective
	_camera_view.visible = true
	_camera_view.modulate.a = 1.0
	_camera_view_tween = create_tween()
	_camera_view_tween.tween_interval(CAMERA_VIEW_S - LANDMARK_FADE_S)
	_camera_view_tween.tween_property(_camera_view, "modulate:a", 0.0, LANDMARK_FADE_S)
	_camera_view_tween.tween_callback(_camera_view.hide)


## Eingeblendete Kameraperspektive („Kamera: Nah“, "" = keine).
func camera_view() -> String:
	return _camera_view.text if _camera_view.visible else ""


## Hat `bpm` einen Pulswert? NAN, 0 und negative Werte sind kein Puls.
static func pulse_valid(bpm: float) -> bool:
	return is_finite(bpm) and bpm > 0.0


## Pulswert für die Anzeige: ganze bpm, ohne Wert „--“.
static func pulse_text(bpm: float) -> String:
	return "%d" % roundi(bpm) if pulse_valid(bpm) else PULSE_NONE_TEXT


## Zone (1–5) des Pulses `bpm`; 0 ohne Wert oder ohne Zonen (null oder keine LTHR/kein Maximalpuls).
static func pulse_zone(bpm: float, zones: HeartRateZones) -> int:
	if not pulse_valid(bpm) or zones == null:
		return 0
	return zones.zone_for(bpm)


## Farbe der Pulsanzeige: Zonenfarbe, ohne Zonen weiß, ohne Wert gedämpft.
static func pulse_color(bpm: float, zones: HeartRateZones) -> Color:
	if not pulse_valid(bpm):
		return COLOR_PULSE_NONE
	return HeartRateZones.color_for(pulse_zone(bpm, zones))


## Beschriftung des Rundenfortschritts: „Runde“ bei einer Runde, „Runde 2 / 3“, endlos „Runde 2“.
static func lap_caption(number: int, total: int) -> String:
	if total == 1:
		return "Runde"
	return "Runde %d / %d" % [number, total] if total > 1 else "Runde %d" % number


## Dezente Einblendung (z. B. „Neue Bestzeit! 1:23.4“), die nach CELEBRATION_S wieder verschwindet. Läuft schon
## eine, wird die neue hinten eingereiht und folgt danach – Bestzeit, Segment, Erfolg und Levelaufstieg überschreiben
## sich nicht (#35).
func celebrate(text: String) -> void:
	if _celebration.visible:
		_celebration_queue.append(text)
		return
	_show_celebration(text)


## Eingereihte Einblendungen, die nach der laufenden folgen (älteste zuerst).
func queued_celebrations() -> Array:
	return _celebration_queue.duplicate()


## Die einzige Stelle, an der eine Einblendung wirklich erscheint (auch eingereihte); meldet `celebration_shown` (Klang,
## #44).
func _show_celebration(text: String) -> void:
	celebration_shown.emit(text)
	_celebration.text = text
	_celebration.visible = true
	_celebration.modulate.a = 1.0
	if _celebration_tween != null:
		_celebration_tween.kill()
	_celebration_tween = create_tween()
	_celebration_tween.tween_interval(CELEBRATION_S - 1.0)
	_celebration_tween.tween_property(_celebration, "modulate:a", 0.0, 1.0)
	_celebration_tween.tween_callback(_next_celebration)


func _next_celebration() -> void:
	_celebration.hide()
	if not _celebration_queue.is_empty():
		_show_celebration(_celebration_queue.pop_front())


## Laufende und eingereihte Einblendungen sofort ausblenden (im Ziel steht sonst das Ergebnis davor).
func end_celebration() -> void:
	_celebration_queue.clear()
	if _celebration_tween != null:
		_celebration_tween.kill()
	_celebration.hide()


## Zahlen-Popup (#49): `text` (z. B. „+100“ oder „Seltener Helm“) in `color` steigt über der Bildmitte auf und blendet in
## POPUP_S aus; laufen schon welche, steht das neue darunter.
func popup(text: String, color: Color = COLOR_POPUP) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", roundi(POPUP_FONT_PX * text_scale(_viewport_height())))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var top := _viewport_height() * POPUP_AT + popups().size() * POPUP_STACK_PX
	label.offset_top = top
	label.offset_bottom = top + POPUP_STACK_PX
	_popups.add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "offset_top", top - POPUP_RISE_PX, POPUP_S)
	tween.tween_property(label, "offset_bottom", top - POPUP_RISE_PX + POPUP_STACK_PX, POPUP_S)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_S * 0.4).set_delay(POPUP_S * 0.6)
	tween.chain().tween_callback(label.queue_free)


## Texte der sichtbaren Zahlen-Popups (älteste zuerst).
func popups() -> Array:
	return _popups.get_children().filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)


## Popups sofort entfernen (Ergebnis, Menü).
func clear_popups() -> void:
	for label in _popups.get_children():
		label.queue_free()


## Text der Einblendung, solange sie sichtbar ist ("" sonst).
func celebration() -> String:
	return _celebration.text if _celebration.visible else ""


## Bereich für die Anzeige, z. B. „95–105 rpm“.
static func zone_range_text(range_min: float, range_max: float) -> String:
	return "%d–%d rpm" % [roundi(range_min), roundi(range_max)]


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
## "Kadenz: 90 rpm", "Steigung: +6.0 %", "Leistung: ~142 W", "Puls: 148 bpm · Z3" (in der Leiste ohne „bpm“, ohne Zonen ohne „· Z3“, ohne Wert „Puls: --“), "Rundenzeit: 3:05", "Ghost: +1.4 s", "Bergwertung: 1:12.4",
## "Runde 2 / 3: 34 % (noch 6.08 km)"; im Training "Phase: Hart 3/10", "Zielkadenz: 95–105 rpm", "Restzeit: 0:23",
## "Danach: Locker 3/10 · 80–90 rpm", "Zone: im Bereich (95–105 rpm, 98 rpm)", "Treffer: 87 %", "Ansage: In 8 s: …";
## in Arcade "Herausforderung: Zone halten", "Ziel: 80–100 rpm", "Noch: 0:12", "Punkte: 100", "Fortschritt: 60 %".
func readout() -> String:
	var lines := []
	for field in [%Cadence, %Speed, %Distance, %Time, %LapTime, %Grade, _section, _power, _ghost]:
		if not field.is_visible_in_tree():
			continue
		var caption: Label = field.get_node("Caption")
		var value: Label = field.find_child("*Value", true, false)
		var unit: Label = field.find_child("Unit", true, false)
		var text := "%s: %s" % [caption.text, value.text]
		if unit != null and not unit.text.is_empty():
			text += " " + unit.text
		lines.append(text)
	if _pulse.is_visible_in_tree():
		var pulse := "Puls: %s" % _pulse_value.text
		if _pulse_has_value:
			pulse += " bpm" if _pulse_unit.is_visible_in_tree() else ""
			pulse += " · " + _pulse_zone.text if not _pulse_zone.text.is_empty() else ""
		lines.append(pulse)
	if _segment.is_visible_in_tree():
		lines.append(_segment_line)
	if _training.is_visible_in_tree():
		lines.append("Phase: %s" % _phase_value.text)
		lines.append("Zielkadenz: %s" % _target_value.text)
		lines.append("Restzeit: %s" % _remaining_value.text)
		lines.append("Danach: %s" % _next_value.text)
	if _arcade.is_visible_in_tree():
		lines.append("Herausforderung: %s" % _challenge_value.text)
		lines.append("Ziel: %s" % _challenge_target.text)
		lines.append("Noch: %s" % _challenge_remaining.text)
		lines.append("Punkte: %s" % _points_value.text)
	if _zone.is_visible_in_tree():
		lines.append("Zone: %s (%s, %d rpm)" % [_zone_state.text, zone_range_text(_zone_bar.range_min,
				_zone_bar.range_max), roundi(_zone_bar.value)])
		lines.append("%s: %s" % [(_zone.get_node("ScoreCaption") as Label).text, _zone_score.text])
	if _announcement.is_visible_in_tree():
		lines.append("Ansage: %s" % _announcement.text)
	lines.append("%s: %s (%s)" % [_lap_caption.text, _lap_percent.text, _lap_remaining.text])
	return "\n".join(lines)


## Hinweis über dem unteren Panel, Debug-Anzeige unter dem Werte-Panel, Zustandsmeldung mittig im freien Feld
## zwischen oben und unten (dort hat auch ein langes Fahrtergebnis Platz) – alle folgen dem Layout. Die Fensterhöhe
## entscheidet über Leisten (`compact`) und die Schriftgröße von Ansage und Meldung.
func _place_overlays() -> void:
	if _hint == null:
		return
	_set_compact(_viewport_height() < COMPACT_BELOW_PX)
	var announcement_px := roundi(_announcement_font_px * text_scale(_viewport_height()))
	if _announcement.get_theme_font_size("font_size") != announcement_px:
		_announcement.add_theme_font_size_override("font_size", announcement_px)
	var bottom_top := _bottom.get_global_rect().position.y
	_hint.offset_top = bottom_top - OVERLAY_GAP_PX - 28.0
	_hint.offset_bottom = bottom_top - OVERLAY_GAP_PX
	var stats := _stats.get_global_rect()
	_debug.offset_top = stats.end.y + OVERLAY_GAP_PX
	_debug.offset_bottom = stats.end.y + OVERLAY_GAP_PX + 150.0
	_fit_message()


## Faktor für Ansage und Meldung bei `height` px Fensterhöhe: Höhe/1080, zwischen MIN_TEXT_SCALE und 1.
static func text_scale(height: float) -> float:
	return clampf(height / 1080.0, MIN_TEXT_SCALE, 1.0)


func _viewport_height() -> float:
	return _top.get_viewport_rect().size.y


## Leisten an/aus: oben ohne Minikarte, Abschnitt-Überschrift und Pulskurve, kleinerer Kadenz-Bogen, die Werte in einer
## Zeile; unten ohne Höhenprofil.
func _set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	_minimap.get_parent().visible = not on
	_profile.visible = not on
	_update_pulse_graph()
	_grid.columns = GRID_COLUMNS_COMPACT if on else GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", GRID_SEPARATION_COMPACT_PX if on else GRID_SEPARATION_PX)
	_grid.get_parent().add_theme_constant_override("separation", MAIN_SEPARATION_COMPACT_PX if on else MAIN_SEPARATION_PX)
	_update_pulse_unit()
	_section.get_node("Caption").visible = not on
	_gauge.custom_minimum_size = Vector2.ONE * (GAUGE_COMPACT_PX if on else GAUGE_PX)
	if on:
		_cadence_value.add_theme_font_size_override("font_size", CADENCE_COMPACT_FONT_PX)
	else:
		_cadence_value.remove_theme_font_size_override("font_size")


## „bpm“ steht nur neben einem Wert und nicht in der Leiste (dort fehlt der Platz; die Beschriftung „Puls“ bleibt).
func _update_pulse_unit() -> void:
	_pulse_unit.visible = _pulse_has_value and not compact


## Die Verlaufskurve gibt es nur im vollen Layout und solange die Pulsanzeige da ist.
func _update_pulse_graph() -> void:
	_pulse_graph.visible = _pulse_shown and not compact


## Zustandsmeldung mittig im freien Streifen zwischen den Panels; die Schrift folgt der Fensterhöhe und wird so weit
## verkleinert, dass die Meldung in den Streifen passt (nur bei neuem Text oder neuem Streifen).
func _fit_message() -> void:
	var strip := (_celebration.get_parent() as Control).get_global_rect()
	var fitted_for := [_message.text, strip.size.y, _viewport_height()]
	if fitted_for == _message_fitted_for:
		return
	_message_fitted_for = fitted_for
	var px := roundi(_message_font_px * text_scale(_viewport_height()))
	_message.add_theme_font_size_override("font_size", px)
	while px > MIN_MESSAGE_FONT_PX and _message.get_minimum_size().y > strip.size.y:
		px -= 1
		_message.add_theme_font_size_override("font_size", px)
	# Anker in der Fenstermitte, die Meldung wächst nach oben und unten
	var center := strip.get_center().y - _message.get_parent_area_size().y / 2.0
	var half := minf(100.0, strip.size.y / 2.0)
	_message.offset_top = center - half
	_message.offset_bottom = center + half
