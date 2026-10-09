## Hauptszene der Inselfahrt: verbindet Bus-Client, Fahrmodell und Strecke.
## Kadenz vom Bus → Fahrmodell (mit Steigung der Strecke) → Fahrer folgt dem Path3D. Kein Lenken.
## Strecke laut Konfiguration (`[world] track`): Insel-Rundkurs mit Insel-Welt (Standard, #14) oder Graybox.
## Die Kamera folgt dem Fahrer ruhig: Position hinter ihm auf der Strecke, Blick voraus, beides geglättet.
## Fahrer und Rad (`Track/Rider/Model`, RiderModel): Kurbel und Beine drehen mit der Kadenz, Räder rollen mit dem
## Tempo, Schräglage in Kurven, Vorbeuge bergauf; außerhalb von `riding` steht alles still.
## Grafik und Fenster: eigenes Menü (`settings_menu`, Esc/F2, F11), hier nur eingehängt; dort auch „Beenden“.
## Kamera und Tempo (#42): Die Kamera hat einen Modus (`camera_mode`, eine Stelle in `_update_camera`): folgen oder das
## Kamera-Intro beim Fahrtstart – ein Schwenk von schräg vorn um den Fahrer herum hinter ihn (CAMERA_INTRO_S, in beiden
## Richtungen und im Training). Die Fahrt und ihre Zeitmessung laufen dabei unverändert. Ab etwa 35 km/h ziehen
## Geschwindigkeitslinien und das Sichtfeld weitet sich leicht (SpeedEffects, im Einstellungsmenü abschaltbar). Beides
## ist nur Darstellung (ADR-0010).
## Panorama-Momente (#43): Fährt der Fahrer an einer Sehenswürdigkeit vorbei (IslandWorld.panorama_spots, Auslösepunkt
## ist ihre Fahrtposition `track.path_distance(path_m)`, in beiden Richtungen), schwenkt die Kamera kurz aus und das HUD
## blendet den Namen ein – je Sehenswürdigkeit höchstens einmal je Runde, nicht mit Ghost, nicht im Training, nicht
## während des Intros oder eines anderen Panoramas, im Einstellungsmenü abschaltbar. Auch das ist nur Kamera: Fahrmodell
## und Zeitmessung laufen unverändert (ADR-0010).
## Kameraperspektiven (#59, CameraViews): Nah, Verfolger (Standard) und Weit – mit `C` während der Fahrt der Reihe nach
## durchzublättern (das HUD blendet den Namen kurz ein) oder im Einstellungsmenü zu wählen. Die Wahl steht im Spielstand
## und gilt in Rundfahrt und Training, in beiden Richtungen; Intro und Panorama laufen in sie zurück, der Sichtfeld-Kick
## wirkt in allen. Nur Kamera (ADR-0010).
## HUD (`Hud`, RideHud, Szene `scenes/hud.tscn`): bekommt pro Frame die Werte, Rundenfortschritt und Position.
## Ton (#44, RideSound, Kind `Sound`): Fahrtwind, Freilauf, Meer, Regen, Möwen, Schafglocken, Dorfglocke und UI-Klänge,
## prozedural und dezent; Lautstärke und Aus-Schalter im Einstellungsmenü. Nur Ausgabe (ADR-0010).
##
## Szenenfluss (#30): Titel → Modus-Auswahl → Fahrt → Ergebnis → Menü. Nach dem Start (`start_in_menu`) steht das
## Startmenü (`scenes/start_menu.gd`) über einem langsamen Kameraflug über die lebende Insel (Licht, Wetter, Bewegung
## wie in der Fahrt; HUD und Fahrer ausgeblendet), unten der Radstatus. „Fahren → Rundfahrt“ zeigt Rundenzahl,
## Tageszeit (dasselbe Feld wie im Einstellungsmenü) und Bestzeit, „Losfahren“ startet die Fahrt (`start_ride`); zurück
## ins Menü geht es im Ziel mit Enter oder jederzeit über „Fahrt beenden“ in den Einstellungen (`return_to_menu`). Die
## beendete Fahrt landet als Zusammenfassung im Spielstand (SaveGame, `user://savegame.json`).
##
## Spielzustände (`state`):
##   riding             fahren – Bus verbunden, Quelle `connected` und Daten seit dem letzten Abbruch
##   paused_manual      pausiert per Taste (P/Leertaste), bis erneut gedrückt
##   paused_connection  pausiert wegen Verbindung: Bridge nicht erreichbar, Quelle `stale`/`disconnected`
##                      oder noch keine Daten; auch wenn die Bridge bei offenem Bus schweigt (BusClient.silent).
##                      Ein Abbruch ist keine Kadenz 0 (ADR-0004): das Fahrmodell
##                      steht still und fährt automatisch weiter, sobald wieder Daten kommen.
##   finished           Ziel erreicht – Ergebnis (Zeit, alle Rundenzeiten, Bestzeit, Ø Kadenz, Ø Tempo); Endzustand
##                      der Fahrt. Auch „Fahrt beenden“ nach mindestens einer vollen Runde (z. B. endlos) zeigt erst
##                      das Ergebnis der gefahrenen Runden.
##   menu               Startmenü mit Kameraflug, keine Fahrt (kein Fahrmodell, kein `set_grade`)
## Verbindungspause hat Vorrang vor der manuellen; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen.
##
## Virtuelle Steigung (ADR-0007): das Spiel meldet die Steigung an der Fahrerposition per `set_grade`
## (Drosselung siehe GradeReporter), nicht in der Verbindungspause; danach wird sie neu gemeldet.
##
## Runden (#31): Start an `start_distance_m`, jede Runde endet beim Überfahren der Start/Ziel-Linie (Streckenposition
## = Vielfaches der Rundenlänge), das Ziel nach `laps` Runden (0 = endlos). Rundenzeiten und Bestzeit führt die
## Rundenwertung (LapTiming) allein aus Streckenposition und Fahrzeit – also nur aus Kadenz und Steigung (ADR-0010).
## Die Bestzeit gilt je Strecke und Richtung und steht im Spielstand; eine neue
## Bestzeit blendet das HUD kurz ein. Fahrzeit und Durchschnitte (RideStats) zählen nur Zeit im Zustand `riding` –
## Pausen nicht.
##
## Segmente und Medaillen (#33): Die Strecke trägt ihre Segmente als Daten (Track.segments); die Rundenwertung misst sie
## mit (SegmentTiming). Im Segment zeigt das HUD dessen Live-Zeit, beim Verlassen blendet es Zeit, Medaille und ggf.
## „neue Bestzeit“ ein. Runden und Segmente bekommen Medaillen nach Schwellen, die Medals aus dem Fahrmodell berechnet
## (`medal_limits`); das Ergebnis zeigt sie je Runde und je Segment. Segment-Bestzeiten und beste Medaillen gehen am
## Fahrtende in den Spielstand, wie die Bestzeit.
##
## Ghost (#32): Auf der Seite „Rundfahrt“ zuschaltbar – Bestzeit-Runde (Standard, sobald es sie gibt) oder letzte Fahrt
## (die letzte volle Runde der zuletzt gespeicherten Fahrt mit mindestens einer vollen Runde). Er fährt jede Runde ab
## ihrem Start neu mit, halbtransparent (`Track/Ghost`, RiderModel als Ghost) und seitlich versetzt; das HUD zeigt den
## Abstand in Sekunden (positiv = hinter dem Ghost). Er wirkt nicht auf die eigene Fahrt. Die Rundenwertung schneidet
## jede volle Runde mit; am Fahrtende gehen Bestzeit-Runde (nur bei neuer Bestzeit) und letzte Runde in den Spielstand.
##
## Gegenrichtung (#34): Auf der Seite „Rundfahrt“ wählbar (im / gegen den Uhrzeigersinn). Die Strecke spiegelt die
## Fahrtposition auf den Pfad (Track.set_direction, path_distance) – Fahrmodell, Rundenwertung, Segmente und Ghost
## sehen in beiden Richtungen eine steigende Fahrtposition. Fahrer, Kamera und Ghost-Mitfahrer schauen in
## Fahrtrichtung, der Ghost fährt links daneben; Minikarte, Höhenprofil, Torbögen und Stationsschilder folgen der
## Richtung. Bestzeit, Segmentzeiten, Medaillen und Ghosts stehen je Richtung im Spielstand. Das Training fährt im
## Uhrzeigersinn.
##
## Erfolge und Fahrerlevel (#35): Die Fahrt meldet Ereignisse an die Erfolge (Achievements) – je volle Runde `lap`, je
## voller Kilometer (gesamt über alle Fahrten) `distance`, `weather` und `time_of_day`. Ein neuer Erfolg und ein
## Levelaufstieg (DriverLevel, aus den Gesamt-Kilometern) blenden im HUD ein, nacheinander mit Bestzeit und Segment.
## Am Fahrtende werden Strecke und Runden gesamt noch einmal geprüft (ein älterer Spielstand zieht so nach); das Ergebnis
## nennt die neuen Erfolge und das neue Level. Das Level schaltet nur Kosmetik frei (ADR-0010) und wirkt nicht auf die
## Fahrt. Das Fahrtenbuch (`scenes/logbook.gd`) öffnet aus dem Startmenü.
##
## Garderobe (#36, `scenes/wardrobe.gd`): aus dem Startmenü; Trikot, Radfarbe und Helm mit Vorschau, freigeschaltet über
## das Fahrerlevel. Eine Wahl wird sofort gespeichert und vom Fahrer (`rider_model`) getragen; nur Kosmetik (ADR-0010).
## Der Ghost-Mitfahrer bleibt im Standard-Look, aufgehellt – so bleibt er vom eigenen Fahrer unterscheidbar.
##
## Training (#37): „Fahren → Training“ startet eine Einheit (Training, aus `res://trainings`) als eigenen Modus
## (SaveGame.MODE_TRAINING). Die Insel läuft endlos (Rundenwertung mit 0 Runden); das HUD zeigt Phase, Zielkadenz,
## Restzeit und nächste Phase, dazu rechtzeitig die Ansage zum Widerstandsknopf. Die Einheit wertet nur die Kadenz
## (ADR-0010). Nach dem Ausrollen endet die Fahrt mit der Bewertung je Phase und gesamt; „Fahrt beenden“ vorher zeigt die
## Teilbewertung der gefahrenen Phasen. Runden im Training zählen nicht für Bestzeit, Medaillen, Segmente und Ghost –
## die Vorgabe wechselt, die Runden wären nicht vergleichbar. Ein zu Ende gefahrenes Training meldet `training_finished`
## an die Erfolge; Name und Gesamtbewertung der Einheit stehen im Fahrteintrag.
## Zielkadenzbereich und Intervall-Tore (#58): Das HUD zeigt im Training den Zonenbalken (Zielbereich, Kadenz, Treffer
## der laufenden Phase). Vor jeder Belastung steht ein Starttor auf der Strecke, an ihrem Ende ein Zieltor
## (Training.gates, CourseGate unter `Track`). Das Training ist zeitbasiert: Das nächste Tor steht dort, wo der Fahrer
## beim aktuellen Tempo zum Phasenwechsel ankommt (GatePlacement), und wird nachgeführt, bis es nah ist
## (GatePlacement.LOCK_AHEAD_M, LOCK_S); das durchfahrene bleibt stehen, bis es hinter der Kamera liegt. Beides ist
## nur Anzeige – Fahrmodell und Bewertung sehen es nicht (ADR-0010).
##
## Arcade (#46, #47, #49, #63): „Fahren → Arcade“ startet einen Arcade-Lauf als eigenen Modus (SaveGame.MODE_ARCADE):
## endlos, im Uhrzeigersinn, ohne Ghost, auf der gewählten Stufe im persönlichen Kadenzbereich. Alles Szenische des Arcade
## (HUD, Tore, Requisiten, Beute, Zusammenfassung, Ausrüstung am Fahrer) liegt in `ArcadeStage` (`src/arcade_stage.gd`,
## Kind `ArcadeStage`); die Hauptszene reicht nur durch: Start, Fahrschritt, Anzeige, Speichern, Ergebnis. Arcade-km zählen
## für Fahrtenbuch, Fahrerlevel und Erfolge, aber Runden im Arcade schreiben nie Bestzeit, Segmentzeit, Medaille oder Ghost
## (`records_count`, ADR-0010). Die Ausrüstung wird im Menü verwaltet („Fahren → Arcade → Ausrüstung“, `gear_menu`), die
## Talente (#53) ebenfalls („Fahren → Arcade → Talente“, `talent_menu`); ihre Wirkung im Lauf liegt in der Erweiterung
## `TalentArcade` (`src/talent_arcade.gd`, hier nach dem Aufbau der Bühne angehängt, damit ihr `run_hook` nach dem der
## Fähigkeiten läuft).
##
## Bridge aus dem Spiel (#25, BridgeLauncher, nur Windows-Desktop): Ist beim Start keine Bridge auf der Bus-Adresse
## erreichbar, startet das Spiel sie unsichtbar mit der Quelle aus `config.cfg [bridge]`; eine laufende wird nur
## mitbenutzt. Beim Schließen (Fenster, „Beenden“) beendet das Spiel nur die eigene, sauber über die Stoppdatei.
extends Node3D

## Neuer Spielzustand (siehe STATE_*).
signal state_changed(state: String)
## Beenden angefordert – Knopf „Beenden“ im Menü (vor dem Beenden, siehe `quit_on_request`).
signal quit_requested

const STATE_RIDING := "riding"
const STATE_PAUSED_MANUAL := "paused_manual"
const STATE_PAUSED_CONNECTION := "paused_connection"
const STATE_FINISHED := "finished"
const STATE_MENU := "menu"

## Tastenbelegung: Aktion → Tasten (physische Tastenposition, unabhängig vom Layout).
const KEY_BINDINGS := {
	"ride_pause": [KEY_P, KEY_SPACE],
	"ride_debug": [KEY_F3],
	"ride_settings": [KEY_ESCAPE, KEY_F2],
	"ride_fullscreen": [KEY_F11],
	"ride_menu": [KEY_ENTER, KEY_KP_ENTER],
	"ride_camera": [KEY_C],
}
## Menü „Grafik und Fenster“ (Esc/F2, F11, Beenden; siehe `scenes/settings_menu.gd`).
const SETTINGS_MENU := preload("res://scenes/settings_menu.tscn")
## Startmenü (Titel, Menüpunkte, Radstatus).
const START_MENU := preload("res://scenes/start_menu.tscn")
## Fahrtenbuch (Statistik, Bestzeiten, Erfolge, letzte Fahrten; #35).
const LOGBOOK := preload("res://scenes/logbook.gd")
## Garderobe (Trikot, Radfarbe, Helm mit Vorschau; #36).
const WARDROBE := preload("res://scenes/wardrobe.gd")
## Ausrüstung des Arcade-Modus (Inventar der Beute; #49).
const GEAR_MENU := preload("res://scenes/gear_menu.gd")
## Talentbaum des Arcade-Modus (Talente aus dem Arcade-Level; #53).
const TALENT_MENU := preload("res://scenes/talent_menu.gd")
## Kamera: Abstand hinter dem Fahrer, Höhe und Blickpunkt voraus je Perspektive (CameraViews, „Weit“ und Blickpunkt
## aus `config.cfg [camera]`); Glättung (Zeitkonstante).
const CAMERA_SMOOTHING_S := 0.45
## Mindesthöhe der Kamera über dem Gelände (Insel).
const CAMERA_TERRAIN_CLEARANCE_M := 1.5
## Titelbild: Kameraflug entlang des Rundkurses – Tempo, Höhe über der Straße, Blickpunkt voraus, Mindesthöhe über
## dem Gelände und Glättung (ruhig auch in den Kehren).
const TITLE_FLIGHT_MPS := 9.0
const TITLE_FLIGHT_HEIGHT_M := 38.0
const TITLE_LOOK_AHEAD_M := 170.0
const TITLE_TERRAIN_CLEARANCE_M := 22.0
const TITLE_SMOOTHING_S := 2.5
## Kamera-Modus (#42): folgen (Standard), Intro beim Fahrtstart oder Panorama-Moment an einer Sehenswürdigkeit (#43).
const CAMERA_FOLLOW := "follow"
const CAMERA_INTRO := "intro"
const CAMERA_PANORAMA := "panorama"
## Kamera-Intro: Dauer (s), Ausgangslage schräg vor dem Fahrer (Winkel um ihn herum ab „dahinter“, über seine rechte
## Seite), Abstand längs und seitlich (m; seitlich innerhalb der Torbogen-Pfosten am Start) und Höhe (m).
const CAMERA_INTRO_S := 3.0
const CAMERA_INTRO_ANGLE_DEG := 150.0
const CAMERA_INTRO_DISTANCE_M := 6.5
const CAMERA_INTRO_SIDE_M := 3.0
const CAMERA_INTRO_HEIGHT_M := 1.3
## Panorama-Moment (#43): Dauer (s), Anteil davon für das Aus- und das Zurückschwenken, Lage der Kamera auf der der
## Sehenswürdigkeit abgewandten Seite des Fahrers (Abstand, zurück entlang der Strecke – so steht der Schildpfosten
## am Aussichtspunkt am Bildrand statt mitten im Bild – und Höhe, m) und Blickpunkt in ihre Richtung (m ab Fahrer, Höhe).
const CAMERA_PANORAMA_S := 4.0
const CAMERA_PANORAMA_SWING := 0.3
const CAMERA_PANORAMA_DISTANCE_M := 9.0
const CAMERA_PANORAMA_BACK_M := 6.0
const CAMERA_PANORAMA_HEIGHT_M := 4.5
const CAMERA_PANORAMA_LOOK_M := 12.0
const CAMERA_PANORAMA_LOOK_HEIGHT_M := 2.0
## Ghost: seitlicher Versatz zum Fahrer auf der Straße (m, nach links), damit beide nebeneinander fahren.
const GHOST_OFFSET_M := -1.3
## Intervall-Tore (#58): so weit hinter dem Fahrer (m) bleibt ein durchfahrenes Tor noch stehen (hinter der Kamera).
const GATE_KEEP_BEHIND_M := 20.0
## Beute (#49): so weit vor dem Fahrer (m) steht die Lichtsäule eines Fundes (Tests lesen sie hier).
const LOOT_AHEAD_M := ArcadeStage.LOOT_AHEAD_M

const BRIDGE_START_HINT := "Bridge starten: vspin-bridge --source sim"
const RESISTANCE_NOT_SUPPORTED := "Widerstand: nicht unterstützt"

## Konfiguration; wenn vor `_ready` nicht gesetzt, wird `res://config.cfg` geladen.
var config: RideConfig = null
## Startposition auf der Strecke in Metern (Standard: Start/Ziel).
@export var start_distance_m := 0.0
## Beendet das Spiel bei „Beenden“ im Menü; Tests schalten das ab und beobachten `quit_requested`.
@export var quit_on_request := true
## Nach dem Start erst das Startmenü zeigen (Spiel); Tests und Prüfhilfen fahren sofort los.
@export var start_in_menu := true
## Grafik-/Fenstereinstellungen; "" = Standardwerte, nichts speichern, Fenster unberührt (Tests, Probe).
var settings_path := GraphicsSettings.DEFAULT_PATH
var settings_menu: CanvasLayer
var start_menu: CanvasLayer
var logbook: CanvasLayer
var wardrobe: CanvasLayer
var gear_menu: CanvasLayer
var talent_menu: CanvasLayer
## Talente und Arcade-Level im Arcade-Lauf (#53); keine Erweiterung in `ArcadeStage.EXTENSIONS`, siehe `_ready`.
var talent_arcade: TalentArcade
## Spielstand; "" = nicht laden/speichern, Fahrten nur im Speicher (Tests, Probe).
var save_path := SaveGame.DEFAULT_PATH
var save_game: SaveGame
## Spielmodus der laufenden Fahrt (SaveGame.MODE_*).
var ride_mode := SaveGame.MODE_ROUND_TRIP
## Rundenzahl der laufenden Fahrt; 0 = endlos.
var laps := 1
## Rundenwertung der laufenden Fahrt (Rundenzeiten, Bestzeit, Segmentzeiten).
var lap_timing: LapTiming
## Medaillen-Schwellen der Strecke aus dem Fahrmodell (Medals.thresholds): {Medals.LAP: {…}, "<segment-id>": {…}}.
var medal_limits: Dictionary = {}
## Ghost der laufenden Fahrt (null = aus); seine Runde beginnt mit jeder Runde der Fahrt neu.
var ghost: Ghost = null
## In dieser Fahrt neu freigeschaltete Erfolge (Einträge aus Achievements.LIST) und das Fahrerlevel jetzt.
var ride_achievements: Array = []
var ride_level := 1
## Trainingseinheit der laufenden Fahrt (null = kein Training).
var training: Training = null
## Bühne des Arcade-Laufs (#63, Kind `ArcadeStage`): hält den Lauf, die Tore, Requisiten und die Lichtsäule.
var arcade_stage: ArcadeStage
## Weiterleitungen an die Bühne für Tests und Prüfhilfen (unverändert benannt, #63): Lauf der Fahrt (null = kein Arcade),
## Würfel und Pool des Laufs (Tests setzen sie), Tore, Zugbrücke, Verfolger, Lichtsäule.
var arcade: ArcadeRun:
	get: return arcade_stage.run
	set(value): arcade_stage.run = value
var arcade_seed: int:
	get: return arcade_stage.seed_value
	set(value): arcade_stage.seed_value = value
var arcade_pool: Array:
	get: return arcade_stage.pool
	set(value): arcade_stage.pool = value
var arcade_start_gate: CourseGate:
	get: return arcade_stage.start_gate
var arcade_finish_gate: CourseGate:
	get: return arcade_stage.finish_gate
var arcade_gate_placement: GatePlacement:
	get: return arcade_stage.gate_placement
var arcade_bridge: Drawbridge:
	get: return arcade_stage.bridge
var arcade_pursuer: Pursuer:
	get: return arcade_stage.pursuer
var loot_beam: LootBeam:
	get: return arcade_stage.loot_beam
## Mitfahrer des Ghosts auf der Strecke und sein halbtransparentes Fahrermodell.
var ghost_rider: PathFollow3D
var ghost_model: RiderModel
## Intervall-Tore im Training (#58): das nächste und das zuletzt durchfahrene (Kinder von `Track`) und die Lage des
## nächsten.
var gate_next: CourseGate
var gate_passed: CourseGate
var gate_placement := GatePlacement.new()

var bus: BusClient
## Start der Bridge aus dem Spiel; startet nur, wenn `config.bus_url` die Bridge-Adresse ist (Tests: Fake-Bus-Port).
var bridge_launcher: BridgeLauncher
var model: RideModel
## Aktueller Spielzustand (STATE_*).
var state := STATE_PAUSED_CONNECTION
## Hinweis aus der letzten `ack` auf `set_grade` ("" = umgesetzt oder noch keine Antwort).
var resistance_hint := ""
var grade_reporter := GradeReporter.new()
## Fahrzeit, Strecke und Durchschnitte der laufenden Fahrt (ohne Pausen).
var stats := RideStats.new()
## Streckenposition (wie `model.distance_m`) der Ziellinie nach der letzten Runde (INF = endlos).
var finish_distance_m := 0.0

## Insel-Welt (null bei der Graybox-Strecke).
var world: IslandWorld = null
## Tag/Nacht und Wetter (G6), Kind `Sky`.
var sky: SkyController = null
## Geschwindigkeitslinien und Sichtfeld-Kick (#42), Kind `SpeedEffects`.
var speed_effects: SpeedEffects
## Ton (#44), Kind `Sound`.
var sound: RideSound
## Kamera-Modus (CAMERA_*) und Zeit seit seinem Beginn (s).
var camera_mode := CAMERA_FOLLOW
var camera_shot_s := 0.0
## Kameraperspektive (CameraViews.IDS, #59); gewählt mit `C` oder im Einstellungsmenü, gespeichert im Spielstand.
var camera_view := CameraViews.DEFAULT
## Panorama-Momente (#43): Sehenswürdigkeiten der Strecke (IslandWorld.panorama_spots; leer bei der Graybox), an/aus
## laut Einstellungsmenü und die laufende ({} = keine).
var panorama_spots: Array = []
var panorama_enabled := true
var panorama: Dictionary = {}

var _manual_pause := false
var _camera_look := Vector3.ZERO
## Fahrtposition, bis zu der die Panorama-Auslösepunkte geprüft sind.
var _panorama_m := 0.0
## Telemetrie seit dem letzten Verbindungsverlust empfangen? Erst dann wird weitergefahren.
var _data_since_loss := false
var _ever_connected := false
## Tore der laufenden Einheit (Training.gates), für welche Einheit, und Index des nächsten (-1 = noch keins).
var _gates: Array = []
var _gates_of: Training = null
var _gate_index := -1
## Laufende Fahrt schon im Spielstand?
var _ride_saved := false
## Streckenposition des Kameraflugs im Titelbild.
var _flight_m := 0.0
## Vor der Fahrt: Kilometer und volle Runden gesamt, Fahrerlevel; nächster voller Kilometer (gesamt) für die Ereignisse.
var _km_before := 0.0
var _laps_before := 0
var _level_before := 1
var _next_km := 1.0

@onready var track: Track = $Track
@onready var rider: PathFollow3D = $Track/Rider
@onready var rider_model: RiderModel = $Track/Rider/Model
@onready var hud: RideHud = $Hud
@onready var message_label: Label = $Hud/Message
@onready var hint_label: Label = $Hud/Hint
@onready var debug_label: Label = $Hud/Debug
@onready var camera: Camera3D = $Camera


func _ready() -> void:
	if config == null:
		config = RideConfig.load_file()
	_register_key_bindings()
	settings_menu = SETTINGS_MENU.instantiate()
	settings_menu.settings_path = settings_path
	settings_menu.quit_requested.connect(_on_quit_requested)
	settings_menu.ride_end_requested.connect(return_to_menu)
	add_child(settings_menu)
	save_game = SaveGame.load_file(save_path) if not save_path.is_empty() else SaveGame.new()
	camera_view = CameraViews.selection(save_game)
	settings_menu.camera_view = camera_view
	start_menu = START_MENU.instantiate()
	start_menu.ride_requested.connect(_on_ride_requested)
	start_menu.settings_requested.connect(settings_menu.open)
	start_menu.quit_requested.connect(_on_quit_requested)
	start_menu.logbook_requested.connect(open_logbook)
	start_menu.wardrobe_requested.connect(open_wardrobe)
	start_menu.direction_changed.connect(func(_direction): _update_round_trip_menu())
	start_menu.arcade_changed.connect(_on_arcade_changed)
	add_child(start_menu)
	logbook = LOGBOOK.new()
	logbook.name = "Logbook"
	logbook.closed.connect(_on_logbook_closed)
	add_child(logbook)
	wardrobe = WARDROBE.new()
	wardrobe.name = "Wardrobe"
	wardrobe.closed.connect(_on_wardrobe_closed)
	wardrobe.part_chosen.connect(_on_part_chosen)
	add_child(wardrobe)
	gear_menu = GEAR_MENU.new()
	gear_menu.name = "GearMenu"
	gear_menu.closed.connect(_on_gear_menu_closed)
	gear_menu.gear_changed.connect(_on_gear_changed)
	add_child(gear_menu)
	start_menu.gear_requested.connect(open_gear_menu)
	talent_menu = TALENT_MENU.new()
	talent_menu.name = "TalentMenu"
	talent_menu.closed.connect(_on_talent_menu_closed)
	talent_menu.talents_changed.connect(_on_talents_changed)
	add_child(talent_menu)
	start_menu.talents_requested.connect(open_talent_menu)
	settings_menu.visibility_changed.connect(_on_settings_visibility_changed)
	_setup_track()
	_setup_ghost_rider()
	gate_next = _new_gate("IntervalGate")
	gate_passed = _new_gate("IntervalGatePassed")
	arcade_stage = ArcadeStage.new()
	add_child(arcade_stage)
	arcade_stage.setup(track, hud, format_time, GATE_KEEP_BEHIND_M)
	talent_arcade = TalentArcade.new()  # nach den Fähigkeiten (#50, in EXTENSIONS): ihr `run_hook` verändert deren Daten
	talent_arcade.attach(arcade_stage)
	_apply_wardrobe()
	sky = SkyController.new()
	add_child(sky)
	sky.setup(self)
	_setup_sky_settings()
	speed_effects = SpeedEffects.new()
	add_child(speed_effects)
	speed_effects.setup(camera)
	speed_effects.enabled = settings_menu.settings.speed_effects
	panorama_enabled = settings_menu.settings.panorama
	sound = RideSound.new()
	add_child(sound)
	sound.setup(self)
	sound.apply_settings(settings_menu.settings.sound_enabled, settings_menu.settings.sound_volume)
	hud.celebration_shown.connect(func(_text): sound.play_ui(RideSound.UI_CELEBRATION))
	bus = BusClient.from_config(config)
	arcade_stage.bus = bus
	bus.telemetry_received.connect(_on_telemetry)
	bus.status_changed.connect(_on_status_changed)
	bus.bus_connection_changed.connect(_on_bus_connection_changed)
	bus.ack_received.connect(_on_ack)
	bridge_launcher = BridgeLauncher.new(config, BridgeLauncher.game_dir())
	bridge_launcher.begin()
	model = RideModel.new(config, start_distance_m)
	_new_lap_timing()
	_reset_progress()
	hud.setup(track, world)
	_update_view()
	_update_camera(0.0, true)
	if start_in_menu:
		_enter_menu()
	else:
		start_menu.close()
		settings_menu.set_ride_active(true)


func _process(delta: float) -> void:
	bus.poll(delta)
	bridge_launcher.poll(delta)
	_update_state()
	if state == STATE_MENU:
		_fly_title(delta)
		start_menu.show_wheel_status(bus, bridge_launcher.hint())
		return
	if state == STATE_RIDING:
		_ride(delta)
	_report_grade(delta)
	_update_view()
	_update_rider(delta)
	_update_camera(delta)
	speed_effects.update(model.speed_kmh() if state == STATE_RIDING else 0.0, delta)


## Tageszeit/Wetter aus dem Menü: gespeicherte Werte (`settings.cfg [sky]`) über `config.cfg` legen, sonst den
## Stand aus `config.cfg` im Menü anzeigen; danach wirkt jede Auswahl sofort.
func _setup_sky_settings() -> void:
	var settings: GraphicsSettings = settings_menu.settings
	if settings.sky_saved:
		settings.apply_sky(sky)
	else:
		settings.capture_sky(sky)
	settings_menu.settings_changed.connect(_on_settings_changed)


func _on_settings_changed(key: String) -> void:
	if key == "speed_effects":
		speed_effects.enabled = settings_menu.settings.speed_effects
	if key == "panorama":
		panorama_enabled = settings_menu.settings.panorama
	if key in ["sound", "sound_volume"]:
		sound.apply_settings(settings_menu.settings.sound_enabled, settings_menu.settings.sound_volume)
	if key == "camera_view":
		set_camera_view(settings_menu.camera_view, false)
	if key in ["time", "weather", "season"]:
		settings_menu.settings.apply_sky(sky)
	if key == "time" and state == STATE_MENU:
		_update_round_trip_menu()


## Strecke laut Konfiguration: Insel-Rundkurs mit Welt (Gelände, Meer, Stationen) oder Graybox mit Boden.
func _setup_track() -> void:
	if config.track == RideConfig.TRACK_GRAYBOX:
		track.curve = GrayboxTrack.build_curve()
		var ground := MeshInstance3D.new()
		ground.name = "Ground"
		var plane := PlaneMesh.new()
		plane.size = Vector2(600.0, 600.0)
		ground.mesh = plane
		var ground_material := StandardMaterial3D.new()
		ground_material.albedo_color = Color(0.45, 0.55, 0.4)
		ground.material_override = ground_material
		ground.position = Vector3(0.0, -0.05, 143.0)
		add_child(ground)
		var road := MeshInstance3D.new()
		road.name = "Road"
		road.mesh = track.road_mesh(0.02, 16.0)
		var road_material := StandardMaterial3D.new()
		road_material.vertex_color_use_as_albedo = true
		road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		road.material_override = road_material
		track.add_child(road)
		return
	IslandCourse.apply_to(track)
	world = IslandWorld.new()
	world.name = "World"
	add_child(world)
	world.build(track)
	panorama_spots = world.panorama_spots()


## Mitfahrer für den Ghost neben dem Fahrer: eigene Kopie des Fahrermodells, halbtransparent; ausgeblendet ohne Ghost.
func _setup_ghost_rider() -> void:
	ghost_rider = PathFollow3D.new()
	ghost_rider.name = "Ghost"
	ghost_rider.loop = true
	ghost_rider.h_offset = GHOST_OFFSET_M
	ghost_rider.visible = false
	track.add_child(ghost_rider)
	ghost_model = RiderModel.new()
	ghost_model.name = "Model"
	ghost_model.position = rider_model.position
	ghost_rider.add_child(ghost_model)
	ghost_model.make_ghost()


## Abschnitt (Station) an der Fahrerposition, "" ohne Stationen (Graybox).
func current_station() -> String:
	return track.ride_station_at(model.distance_m).get("name", "")


## Kamera ruhig hinter dem Fahrer: Zielposition hinter ihm auf der Strecke (folgt Kurven und Kehren, statt
## seitlich auszuschwenken), Blick auf einen Punkt voraus; beides exponentiell geglättet. `snap` springt sofort.
## Im Modus CAMERA_INTRO stattdessen der Schwenk des Intros, danach wieder folgen (#42); ebenso ein Panorama-Moment
## (CAMERA_PANORAMA, #43), den das Vorbeifahren an einer Sehenswürdigkeit auslöst.
func _update_camera(delta: float, snap: bool = false) -> void:
	var d := model.distance_m
	var follow_view := camera_follow_view(d)
	var target: Vector3 = follow_view[0]
	var look: Vector3 = follow_view[1]
	_check_panorama(d, snap)
	if camera_mode == CAMERA_INTRO:
		camera_shot_s += delta
		if camera_shot_s < CAMERA_INTRO_S:
			var shot := _intro_shot(d, target, look, camera_shot_s / CAMERA_INTRO_S)
			_aim_camera(shot[0], shot[1], 1.0)
			return
		_set_camera_mode(CAMERA_FOLLOW)
	var follow := 1.0 if snap else 1.0 - exp(-delta / CAMERA_SMOOTHING_S)
	if camera_mode == CAMERA_PANORAMA:
		camera_shot_s += delta
		if camera_shot_s < CAMERA_PANORAMA_S:
			var view := _panorama_shot(d, target, look, camera_shot_s / CAMERA_PANORAMA_S)
			_aim_camera(view[0], view[1], follow)
			return
		_end_panorama()
	_aim_camera(target, look, follow)


## Folgekamera der gewählten Perspektive (`camera_view`) an Fahrtposition `d`: [Position, Blickpunkt]. Die Position
## liegt hinter dem Fahrer auf der Strecke, mindestens CAMERA_TERRAIN_CLEARANCE_M über dem Gelände.
func camera_follow_view(d: float) -> Array:
	var view := CameraViews.values(camera_view, config)
	var up := Vector3.UP
	var target: Vector3 = track.to_global(track.ride_position_at(d - view["behind_m"])) + up * view["height_m"]
	var look: Vector3 = track.to_global(track.ride_position_at(d + view["look_ahead_m"])) + up * view["look_height_m"]
	if world != null:
		target.y = maxf(target.y, world.terrain.height_at(target.x, target.z) + CAMERA_TERRAIN_CLEARANCE_M)
	return [target, look]


## Kameraperspektive `id` (CameraViews.IDS) wählen und im Spielstand speichern; das Einstellungsmenü zeigt sie. Mit
## `announce` blendet das HUD ihren Namen kurz ein. Die Kamera gleitet über ihre Glättung in die neue Lage.
func set_camera_view(id: String, announce: bool = true) -> void:
	camera_view = CameraViews.valid(id)
	settings_menu.camera_view = camera_view
	CameraViews.choose(save_game, camera_view)
	if not save_path.is_empty():
		save_game.save_file(save_path)
	if announce:
		hud.show_camera_view(CameraViews.NAMES[camera_view])


## Taste `C`: nächste Perspektive (Nah → Verfolger → Weit → Nah).
func cycle_camera_view() -> void:
	set_camera_view(CameraViews.next(camera_view))


## Kamera-Modus wechseln (CAMERA_*); die Zeit im Modus beginnt bei 0.
func _set_camera_mode(mode: String) -> void:
	camera_mode = mode
	camera_shot_s = 0.0


## Kamera-Intro beim Anteil `t` (0..1): auf einem flachen Bogen um den Fahrer an Fahrtposition `d` von schräg vorn
## rechts nach hinten, Blick vom Fahrer nach vorn; zum Ende hin genau in die Folgekamera (`target`, `look`).
## Ergebnis: [Position, Blickpunkt].
func _intro_shot(d: float, target: Vector3, look: Vector3, t: float) -> Array:
	var at := track.to_global(track.ride_position_at(d))
	var forward := track.to_global(track.ride_position_at(d + 1.0)) - at
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var ease := smoothstep(0.0, 1.0, t)
	var angle := deg_to_rad(CAMERA_INTRO_ANGLE_DEG) * (1.0 - ease)
	var view := CameraViews.values(camera_view, config)
	var radius := lerpf(CAMERA_INTRO_DISTANCE_M, view["behind_m"], ease)
	var height := lerpf(CAMERA_INTRO_HEIGHT_M, view["height_m"], ease)
	var orbit := at - forward * cos(angle) * radius + right * sin(angle) * CAMERA_INTRO_SIDE_M + Vector3.UP * height
	if world != null:
		orbit.y = maxf(orbit.y, world.terrain.height_at(orbit.x, orbit.z) + CAMERA_TERRAIN_CLEARANCE_M)
	var rider_eye := at + Vector3.UP * 1.1
	return [orbit.lerp(target, smoothstep(0.6, 1.0, t)), rider_eye.lerp(look, ease)]


## Panorama-Moment auslösen, wenn der Fahrer seit der letzten Prüfung den Auslösepunkt einer Sehenswürdigkeit (ihre
## Fahrtposition in einer Runde) überfahren hat – nur beim Fahren mit Folgekamera (nicht im Intro), ohne Ghost, ohne
## Training und eingeschaltet. Überfahrene Punkte gelten als geprüft, auch wenn kein Panorama kommt; so kommt jede
## Sehenswürdigkeit höchstens einmal je Runde. `snap` (Sprung der Fahrtposition) prüft nichts.
func _check_panorama(d: float, snap: bool) -> void:
	var before := _panorama_m
	_panorama_m = d
	if snap or d <= before or state != STATE_RIDING or camera_mode != CAMERA_FOLLOW or not panorama_enabled \
			or ghost_active() or training_active():
		return
	var length := track.length_m()
	for spot in panorama_spots:
		var ride_m := track.path_distance(spot["path_m"])
		if floorf((d - ride_m) / length) > floorf((before - ride_m) / length):
			panorama = spot
			_set_camera_mode(CAMERA_PANORAMA)
			hud.show_landmark(spot["name"], CAMERA_PANORAMA_S)
			return


## Panorama vorbei (oder abgebrochen): Folgekamera, Stationsschild wieder voll sichtbar.
func _end_panorama() -> void:
	_fade_spot_sign(1.0)
	panorama = {}
	if camera_mode == CAMERA_PANORAMA:
		_set_camera_mode(CAMERA_FOLLOW)


## Ein Stationsschild am Ort des Panoramas (der Aussichtspunkt hat eins über der Straße) blendet im Schwenk aus – es
## stünde sonst groß vor der Kamera; den Namen zeigt dann das HUD.
func _fade_spot_sign(alpha: float) -> void:
	if world == null or panorama.is_empty():
		return
	var sign := world.get_node_or_null("Stations/%s/Label" % panorama["id"]) as Label3D
	if sign != null:
		sign.modulate.a = alpha
		sign.outline_modulate.a = alpha


## Panorama-Moment beim Anteil `t` (0..1) an Fahrtposition `d`: die Kamera schwenkt weich aus der Folgekamera
## (`target`, `look`) auf die der Sehenswürdigkeit abgewandte Seite des Fahrers, etwas erhöht, und blickt über ihn zu
## ihr hin; zum Ende wieder genau in die Folgekamera. Ein Stationsschild dort blendet so lange aus. Ergebnis: [Position,
## Blickpunkt].
func _panorama_shot(d: float, target: Vector3, look: Vector3, t: float) -> Array:
	var at := track.to_global(track.ride_position_at(d)) + Vector3.UP * 1.5
	var to: Vector3 = panorama["at"] - at
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 0.001:
		return [target, look]
	var forward := track.to_global(track.ride_position_at(d + 1.0)) - track.to_global(track.ride_position_at(d))
	forward.y = 0.0
	var wide := at - flat.normalized() * CAMERA_PANORAMA_DISTANCE_M - forward.normalized() * CAMERA_PANORAMA_BACK_M \
			+ Vector3.UP * CAMERA_PANORAMA_HEIGHT_M
	if world != null:
		wide.y = maxf(wide.y, world.terrain.height_at(wide.x, wide.z) + CAMERA_TERRAIN_CLEARANCE_M)
	var swing := smoothstep(0.0, CAMERA_PANORAMA_SWING, t) * (1.0 - smoothstep(1.0 - CAMERA_PANORAMA_SWING, 1.0, t))
	_fade_spot_sign(1.0 - swing)
	var view := at + to.normalized() * CAMERA_PANORAMA_LOOK_M + Vector3.UP * CAMERA_PANORAMA_LOOK_HEIGHT_M
	return [target.lerp(wide, swing), look.lerp(view, swing)]


## Titelbild: die Kamera fliegt langsam hoch über dem Rundkurs voraus und blickt weit nach vorn. `snap` springt.
func _fly_title(delta: float, snap: bool = false) -> void:
	_flight_m += TITLE_FLIGHT_MPS * delta
	var up := Vector3.UP
	var target := track.to_global(track.position_at(_flight_m)) + up * TITLE_FLIGHT_HEIGHT_M
	var look := track.to_global(track.position_at(_flight_m + TITLE_LOOK_AHEAD_M)) + up * 4.0
	if world != null:
		target.y = maxf(target.y, world.terrain.height_at(target.x, target.z) + TITLE_TERRAIN_CLEARANCE_M)
	_aim_camera(target, look, 1.0 if snap else 1.0 - exp(-delta / TITLE_SMOOTHING_S))


## Kamera um den Anteil `follow` (0..1) zur Position `target` und zum Blickpunkt `look` hin bewegen.
func _aim_camera(target: Vector3, look: Vector3, follow: float) -> void:
	camera.global_position = camera.global_position.lerp(target, follow)
	_camera_look = _camera_look.lerp(look, follow)
	if camera.global_position.distance_to(_camera_look) > 0.01:
		camera.look_at(_camera_look, Vector3.UP)


## „Losfahren“: neue Fahrt ab `start_distance_m` über `lap_count` Runden (0 = endlos) mit Ghost `ghost_kind`
## (Ghost.BEST/LAST, "" = aus; ohne Aufzeichnung aus) – Fahrmodell, Statistik, Rundenwertung und Pausen
## zurückgesetzt; gefahren wird, sobald das Rad Daten liefert (wie bisher beim Start). Mit `training_unit` (wie
## Training.load_file) ein Training: endlos, ohne Ghost, im Uhrzeigersinn. `direction` = Fahrtrichtung
## (Track.DIRECTION_*, #34). Modus SaveGame.MODE_ARCADE startet einen Arcade-Lauf auf Stufe `tier` im Kadenzbereich
## des Spielstands (#46): endlos, ohne Ghost, im Uhrzeigersinn. Die Kamera beginnt mit dem Intro (#42); die Fahrt
## wartet nicht darauf.
func start_ride(mode: String = SaveGame.MODE_ROUND_TRIP, lap_count: int = 1, ghost_kind: String = "",
		training_unit: Dictionary = {}, direction: String = Track.DIRECTION_CW,
		tier: int = ArcadeTiers.DEFAULT) -> void:
	ride_mode = mode
	training = Training.new(training_unit) if not training_unit.is_empty() else null
	if training != null or mode == SaveGame.MODE_ARCADE:
		lap_count = 0
		ghost_kind = ""
		direction = Track.DIRECTION_CW
	laps = lap_count
	_set_direction(direction)
	arcade_stage.begin(mode == SaveGame.MODE_ARCADE and training == null, tier, save_game, start_distance_m)
	_apply_wardrobe()
	ghost = save_game.ghost(config.track, track.direction, ghost_kind) if not ghost_kind.is_empty() else null
	model = RideModel.new(config, start_distance_m)
	stats = RideStats.new()
	_new_lap_timing()
	_reset_progress()
	grade_reporter.reset()
	resistance_hint = ""
	_manual_pause = false
	_ride_saved = false
	start_menu.close()
	settings_menu.set_ride_active(true)
	hud.visible = true
	rider.visible = true
	ghost_rider.visible = ghost != null
	state = STATE_PAUSED_CONNECTION
	state_changed.emit(state)
	_update_state()
	_update_view()
	_end_panorama()
	hud.show_landmark("")
	_set_camera_mode(CAMERA_INTRO)
	_update_camera(0.0, true)


## Rundfahrt aus dem Startmenü: gewählte Tageszeit wie im Einstellungsmenü setzen, dann mit der Rundenzahl und dem
## gewählten Ghost losfahren.
func _on_ride_requested(mode: String) -> void:
	settings_menu.select_time(start_menu.time_index())
	if mode == SaveGame.MODE_TRAINING:
		start_ride(mode, 0, "", start_menu.training_unit())
		return
	if mode == SaveGame.MODE_ARCADE:
		_on_arcade_changed()
		start_ride(mode, 0, "", {}, Track.DIRECTION_CW, start_menu.arcade_tier())
		return
	start_ride(mode, start_menu.round_trip_laps(), start_menu.ghost_choice(), {}, start_menu.ride_direction())


## Fahrtrichtung der Strecke setzen (#34): Fahrer und Ghost-Mitfahrer schauen in Fahrtrichtung (gegen den
## Uhrzeigersinn um 180° gedreht), der Ghost bleibt links in Fahrtrichtung; Welt und HUD (Profil, Minikarte) folgen.
func _set_direction(direction: String) -> void:
	track.set_direction(direction)
	var turn := PI if track.reversed() else 0.0
	rider_model.rotation.y = turn
	ghost_model.rotation.y = turn
	ghost_rider.h_offset = -GHOST_OFFSET_M if track.reversed() else GHOST_OFFSET_M
	if world != null:
		world.set_direction(direction)
	hud.setup(track, world)


## Neue Rundenwertung ab `start_distance_m` mit `laps` Runden, den Segmenten der Strecke und den gespeicherten
## Bestzeiten; dazu die Medaillen-Schwellen (beim ersten Mal berechnet, danach zwischengespeichert). Im Training und im
## Arcade ohne Segmente und Bestzeiten: dort zählen Runden nicht (`records_count`).
func _new_lap_timing() -> void:
	if not records_count():
		lap_timing = LapTiming.new(track.length_m(), start_distance_m, laps)
	else:
		lap_timing = LapTiming.new(track.length_m(), start_distance_m, laps,
				save_game.best_time_s(config.track, track.direction), track.segments,
				save_game.segment_best_times(config.track, track.direction))
	finish_distance_m = lap_timing.finish_m()
	medal_limits = Medals.thresholds(track, config)


## Erfolge und Fahrerlevel für eine neue Fahrt: Stand vor der Fahrt aus dem Spielstand (Kilometer und Runden aller
## Fahrten), noch nichts Neues.
func _reset_progress() -> void:
	_km_before = save_game.total_km()
	_laps_before = save_game.total_laps()
	_level_before = DriverLevel.level_for(_km_before)
	ride_level = _level_before
	_next_km = floorf(_km_before) + 1.0
	ride_achievements = []


## Ein Ereignis der Fahrt an die Erfolge: neu erfüllte werden freigeschaltet (im Spielstand, gespeichert mit der Fahrt)
## und mit `announce` eingeblendet.
func _achievement_event(event: Dictionary, announce: bool = true) -> void:
	for achievement in Achievements.check(event, save_game.achievements()):
		save_game.unlock_achievement(achievement["id"])
		ride_achievements.append(achievement)
		if announce:
			hud.celebrate("Erfolg: %s – %s" % [achievement["name"], achievement["text"]])


## Fahrerlevel aus den Gesamt-Kilometern (bisher plus diese Fahrt); ein Aufstieg blendet mit `announce` ein.
func _check_level(announce: bool = true) -> void:
	var level := DriverLevel.level_for(_km_before + stats.distance_m / 1000.0)
	if level > ride_level:
		ride_level = level
		if announce:
			hud.celebrate("Fahrerlevel %d erreicht!" % level)


## Ereignisse je voller Kilometer (gesamt): Strecke, Wetter, Tageszeit und Jahreszeit (#39; die Mandelblüte zählt als
## Frühling, Season.achievement_season) beim Fahren.
func _km_events() -> Array:
	return [
		{"type": Achievements.EVENT_DISTANCE, "total_km": _km_before + stats.distance_m / 1000.0,
			"ride_km": stats.distance_m / 1000.0},
		{"type": Achievements.EVENT_WEATHER, "state": sky.weather.state},
		{"type": Achievements.EVENT_TIME_OF_DAY, "hour": sky.clock.local_hour()},
		{"type": Achievements.EVENT_SEASON, "season": Season.achievement_season(sky.season())},
	]


## Zählen die Runden dieser Fahrt für Bestzeit, Medaillen, Segmentzeiten und Ghost? Nur in der Rundfahrt – im Training
## wechselt die Vorgabe, im Arcade wirken Arcade-Werte (ADR-0010).
func records_count() -> bool:
	return training == null and not arcade_stage.is_active()


## Seite „Arcade“ im Startmenü geändert (oder Losfahren): Stufe und Kadenzbereich in den Spielstand, die beste Punktzahl
## der Stufe ins Menü.
func _on_arcade_changed() -> void:
	ArcadeTiers.choose(save_game, start_menu.arcade_tier())
	CadenceRange.choose(save_game, start_menu.cadence_range())
	if not save_path.is_empty():
		save_game.save_file(save_path)
	start_menu.show_arcade_best(save_game.best_arcade_points(start_menu.arcade_tier()))


## Seite „Arcade“: Stufe und Kadenzbereich wie im Spielstand, dazu die beste Punktzahl der Stufe.
func _update_arcade_menu() -> void:
	var tier := ArcadeTiers.selection(save_game)
	start_menu.set_arcade_choices(tier, CadenceRange.selection(save_game))
	start_menu.show_arcade_best(save_game.best_arcade_points(tier))
	start_menu.show_arcade_level(ArcadeLevel.level(save_game), Talents.available(save_game))


## Fahrtenbuch aus dem Startmenü öffnen (das Menü tritt so lange zurück).
func open_logbook() -> void:
	start_menu.close()
	logbook.open(save_game)


func _on_logbook_closed() -> void:
	start_menu.open()
	start_menu.buttons["logbook"].grab_focus()


## Garderobe aus dem Startmenü öffnen (das Menü tritt so lange zurück).
func open_wardrobe() -> void:
	start_menu.close()
	wardrobe.open(save_game)


func _on_wardrobe_closed() -> void:
	start_menu.open()
	start_menu.buttons["wardrobe"].grab_focus()


## Teil in der Garderobe gewählt: der Fahrer trägt es, der Spielstand wird gleich gespeichert.
func _on_part_chosen(_item: String) -> void:
	_apply_wardrobe()
	if not save_path.is_empty():
		save_game.save_file(save_path)


## Der Fahrer trägt die gewählten Teile der Garderobe (der Ghost-Mitfahrer nicht); im Arcade-Lauf überdeckt die
## angelegte Ausrüstung sie an ihren Plätzen (#49) – nur dort, Rundfahrt und Training zeigen nur die Garderobe.
func _apply_wardrobe() -> void:
	rider_model.reset_look()
	rider_model.wear(Wardrobe.outfit(Wardrobe.selection(save_game)))
	arcade_stage.dress(rider_model, save_game)


## Ausrüstung (#49) aus der Seite „Arcade“ öffnen (das Menü tritt so lange zurück).
func open_gear_menu() -> void:
	start_menu.close()
	gear_menu.open(save_game)


## Talentbaum (#53) aus der Seite „Arcade“ öffnen (das Menü tritt so lange zurück).
func open_talent_menu() -> void:
	start_menu.close()
	talent_menu.open(save_game)


func _on_talent_menu_closed() -> void:
	start_menu.open()
	start_menu.show_arcade()
	_update_arcade_menu()
	start_menu.buttons["arcade_talents"].grab_focus()


## Talent erlernt oder zurückgesetzt: gleich speichern.
func _on_talents_changed() -> void:
	if not save_path.is_empty():
		save_game.save_file(save_path)


func _on_gear_menu_closed() -> void:
	start_menu.open()
	start_menu.show_arcade()
	start_menu.buttons["arcade_gear"].grab_focus()


## Teil angelegt oder verwertet: gleich speichern.
func _on_gear_changed() -> void:
	if not save_path.is_empty():
		save_game.save_file(save_path)


func _on_settings_visibility_changed() -> void:
	sound.play_ui(RideSound.UI_CLICK)
	start_menu.set_covered(settings_menu.visible)
	if not settings_menu.visible:
		logbook.focus_default.call_deferred()  # Einstellungen über dem Fahrtenbuch geschlossen
		wardrobe.focus_default.call_deferred()  # … oder über der Garderobe
		gear_menu.focus_default.call_deferred()  # … oder über der Ausrüstung
		talent_menu.focus_default.call_deferred()  # … oder über den Talenten


## Seite „Rundfahrt“ im Startmenü: Tageszeiten wie im Einstellungsmenü, die gespeicherten Ghosts und die Bestzeit der
## Strecke in der gewählten Richtung.
func _update_round_trip_menu() -> void:
	var times: Array = settings_menu.time_choices()
	start_menu.set_time_choices(times[0], times[1])
	var direction: String = start_menu.ride_direction()
	start_menu.set_ghost_choices(save_game.ghost(config.track, direction, Ghost.BEST) != null,
			save_game.ghost(config.track, direction, Ghost.LAST) != null)
	var best := save_game.best_time_s(config.track, direction)
	start_menu.show_best_time(format_time(best, true) if is_finite(best) else "")


## Fahrt beenden (Ziel oder Abbruch) und zurück ins Startmenü; das Spiel läuft weiter. Die Fahrt kommt in den
## Spielstand, sofern nicht schon geschehen. Mit mindestens einer vollen Runde (z. B. endlos) erst das Ergebnis, im
## Training nach gefahrener Zeit die Teilbewertung.
func return_to_menu() -> void:
	if state == STATE_MENU:
		return
	var has_result := not lap_timing.lap_times.is_empty()
	if training != null:
		has_result = training.elapsed_s > 0.0
	elif arcade_stage.is_active():
		has_result = arcade_stage.has_result()
	if state != STATE_FINISHED and has_result:
		_finish_ride()
		return
	_save_ride()
	_flight_m = track.path_distance(model.distance_m)
	_enter_menu()


func _enter_menu() -> void:
	logbook.close()
	wardrobe.close()
	gear_menu.close()
	talent_menu.close()
	state = STATE_MENU
	_manual_pause = false
	hud.visible = false
	rider.visible = false
	ghost_rider.visible = false
	settings_menu.set_ride_active(false)
	_end_panorama()
	_set_camera_mode(CAMERA_FOLLOW)
	hud.show_landmark("")
	arcade_stage.enter_menu()
	speed_effects.reset()
	_update_round_trip_menu()
	_update_arcade_menu()
	start_menu.open()
	state_changed.emit(state)
	_fly_title(0.0, true)


## Ergebnis: Zustand `finished`, Fahrt in den Spielstand. Ein zu Ende gefahrenes Training meldet sich vorher bei den
## Erfolgen (ohne Einblendung – die neuen Erfolge stehen im Ergebnis).
func _finish_ride() -> void:
	state = STATE_FINISHED
	hud.end_celebration()  # „neu!“ steht im Ergebnis; die Einblendung stünde dahinter
	hud.clear_popups()  # ebenso die Popups (#49)
	if training != null and training.finished() and not _ride_saved:
		_achievement_event({"type": Achievements.EVENT_TRAINING,
				"total_trainings": save_game.finished_trainings() + 1, "score": training.total_score()}, false)
	_save_ride()
	state_changed.emit(state)


## Die laufende Fahrt als Zusammenfassung in den Spielstand (einmal je Fahrt), mit den Zeiten der vollen Runden und
## einer neuen Bestzeit samt ihrer Runde als Ghost; die letzte volle Runde wird der Ghost „letzte Fahrt“. Eine
## abgebrochene Fahrt nur, wenn gefahren wurde. Ein Training trägt Einheit und Gesamtbewertung ein, aber keine
## Bestzeit, Medaille, Segmentzeit oder Ghost.
## Je Segment die beste Zeit dieser Fahrt (für den Fahrteintrag); im Training gibt es keine Segmente.
func _ride_segment_times() -> Dictionary:
	var best := {}
	if lap_timing == null or lap_timing.segments == null:
		return best
	for result in lap_timing.segments.results:
		var id: String = result["id"]
		if not best.has(id) or float(result["time_s"]) < float(best[id]):
			best[id] = float(result["time_s"])
	return best


func _save_ride() -> void:
	if state == STATE_MENU or _ride_saved or (state != STATE_FINISHED and stats.ride_time_s <= 0.0):
		return
	_ride_saved = true
	var entry := SaveGame.ride_entry(ride_mode, config.track,
			training.finished() if training != null else lap_timing.finished(), lap_timing.lap_times.size(), stats,
			SaveGame.utc_now(), lap_timing.lap_times, track.direction, _ride_segment_times())
	if training != null:
		var score := training.total_score()
		entry["training"] = training.unit["name"]
		entry["training_score"] = snappedf(score, 0.001) if not is_nan(score) else 0.0
	arcade_stage.save(entry, save_game)
	save_game.add_ride(entry)
	if records_count():
		_record_round_trip()
	# Gesamtstand mit dieser Fahrt: holt auch nach, was ein älterer Spielstand schon erfüllt (ohne Einblendung – im
	# Ergebnis stehen die neuen Erfolge und das Level).
	_achievement_event({"type": Achievements.EVENT_DISTANCE, "total_km": save_game.total_km(),
			"ride_km": stats.distance_m / 1000.0}, false)
	_achievement_event({"type": Achievements.EVENT_LAP, "total_laps": save_game.total_laps(),
			"ride_laps": lap_timing.lap_times.size()}, false)
	_check_level(false)
	if not save_path.is_empty():
		save_game.save_file(save_path)


## Rundfahrt: neue Bestzeit samt Ghost, letzte Runde als Ghost, Medaillen und Segmentzeiten in den Spielstand.
func _record_round_trip() -> void:
	var best_ghost := lap_timing.best_ghost
	var direction := track.direction
	if save_game.record_best_time(config.track, direction, lap_timing.ride_best_s()) \
			and best_ghost != null and is_equal_approx(best_ghost.time_s, lap_timing.ride_best_s()):
		save_game.record_ghost(config.track, direction, Ghost.BEST, best_ghost)
	if lap_timing.last_ghost != null:
		save_game.record_ghost(config.track, direction, Ghost.LAST, lap_timing.last_ghost)
	for i in range(lap_timing.lap_times.size()):
		save_game.record_medal(config.track, direction, Medals.LAP, lap_medal(i))
	for result in lap_timing.segments.results:
		save_game.record_segment_time(config.track, direction, result["id"], result["time_s"])
		save_game.record_medal(config.track, direction, result["id"], segment_medal(result))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ride_debug"):
		debug_label.visible = not debug_label.visible
		_update_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_menu") and state == STATE_FINISHED:
		return_to_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_camera") and state != STATE_MENU and not settings_menu.visible:
		cycle_camera_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ride_pause") and state != STATE_MENU:
		if state != STATE_FINISHED:
			_manual_pause = not _manual_pause
		_update_state()
		_update_view()
		get_viewport().set_input_as_handled()


func _on_quit_requested() -> void:
	_save_ride()
	quit_requested.emit()
	if quit_on_request:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_ride()  # Fenster geschlossen mitten in der Fahrt


func _exit_tree() -> void:
	if bus != null:
		bus.close()
	if bridge_launcher != null:
		bridge_launcher.stop()  # nur die eigene Bridge, sauber; eine mitbenutzte läuft weiter


## Fahrzeit der Fahrt in Sekunden (ohne Pausen); bei einer Runde die Rundenzeit. Die Zeit der laufenden Runde steht
## in `lap_timing.lap_time_s`.
func lap_time_s() -> float:
	return stats.ride_time_s


## Aktuelle Steigung an der Position des Fahrers (Anteil).
func current_grade() -> float:
	return track.grade_at(model.distance_m)


## Krümmung der Strecke an der Position des Fahrers (1/m, positiv = Linkskurve).
func current_curvature() -> float:
	return curvature_at(model.distance_m)


## Krümmung der Strecke an Fahrtposition `d` (1/m, positiv = Linkskurve in Fahrtrichtung).
func curvature_at(d: float) -> float:
	return RiderMotion.signed_curvature(track.ride_position_at(d - RiderMotion.CURVE_SAMPLE_M),
			track.ride_position_at(d), track.ride_position_at(d + RiderMotion.CURVE_SAMPLE_M))


## Fährt ein Ghost mit? (Dann keine Panorama-Momente, #43.)
func ghost_active() -> bool:
	return ghost != null and state != STATE_MENU


## Läuft ein Training? (Dann keine Panorama-Momente, #43.)
func training_active() -> bool:
	return training != null and state != STATE_MENU


## Streckenposition des Ghosts (wie `model.distance_m`): Beginn der laufenden Runde plus seine Position zur Rundenzeit.
func ghost_distance_m() -> float:
	return lap_timing.lap_start_m() + ghost.position_at(lap_timing.lap_time_s)


## Abstand zum Ghost in Sekunden an der Position des Fahrers: positiv = dahinter, negativ = davor (NAN ohne Ghost).
func ghost_gap_s() -> float:
	return ghost.gap_s(lap_timing.lap_distance_m(), lap_timing.lap_time_s) if ghost != null else NAN


## Abstand zum Ghost für die Anzeige (Sekunden, eine Nachkommastelle): 1.43 → "+1.4", −0.8 → "-0.8", gleichauf "0.0".
static func format_gap(seconds: float) -> String:
	var rounded := snappedf(seconds, 0.1)
	if is_zero_approx(rounded):
		return "0.0"
	return "%+.1f" % rounded


## Steigung (Anteil) für die Anzeige, z. B. 0.06 → "+6.0 %", flach → "0.0 %".
static func format_grade(grade: float) -> String:
	var percent := snappedf(grade * 100.0, 0.1)
	if is_zero_approx(percent):
		return "0.0 %"
	return "%+.1f %%" % percent


## Zeit für die Anzeige: "m:ss", mit `tenths` "m:ss.z".
static func format_time(seconds: float, tenths: bool = false) -> String:
	if tenths:
		var t := snappedf(maxf(seconds, 0.0), 0.1)
		return "%d:%04.1f" % [int(t / 60.0), fmod(t, 60.0)]
	var whole := int(maxf(seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


## Leistung für die Anzeige: geschätzt immer mit „~“ (ADR-0004), z. B. "~142 W"; "" ohne Wert.
static func format_power(watts: float, estimated: bool) -> String:
	if is_nan(watts):
		return ""
	return "%s%d W" % ["~" if estimated else "", roundi(watts)]


## Hinweistext zum Zustand (leer beim Fahren), wie er groß im HUD steht.
func status_message() -> String:
	match state:
		STATE_FINISHED:
			if training != null:
				return training_result()
			if arcade_stage.is_active():
				return arcade_result()
			var rewards := rewards_result()  # in der Kopfzeile: als eigene Zeile passten 20 Runden nicht mehr in 1152×648
			return "%s%s\nZeit: %s\n%s\nØ Kadenz: %d rpm\nØ Tempo: %.1f km/h\nEnter: zurück ins Menü · Esc: Einstellungen" % [
					"Ziel erreicht!" if lap_timing.finished() else "Fahrt beendet",
					" · " + rewards if not rewards.is_empty() else "", format_time(lap_time_s(), true),
					lap_result(), roundi(stats.avg_cadence()), stats.avg_speed_kmh()]
		STATE_PAUSED_MANUAL:
			return "Pause\nP / Leertaste: weiter\nEsc / F2: Einstellungen (Fahrt beenden, Beenden)"
		STATE_PAUSED_CONNECTION:
			var text: String
			if not bus.bus_connected:
				text = "%sBridge nicht erreichbar (%s)\n%s\nNeuer Versuch läuft …" % [
						"Verbindung verloren: " if _ever_connected else "", bus.url,
						bridge_launcher.hint() if not bridge_launcher.hint().is_empty() else BRIDGE_START_HINT]
			elif bus.silent:
				text = "Verbindung verloren (Bridge sendet seit %d s nichts)\nWarte auf Daten …" % roundi(
						bus.silence_timeout_s)
			elif bus.status != BusClient.STATE_CONNECTED:
				text = "Verbindung verloren (Rad: %s)\nWarte auf Daten …" % bus.status
			else:
				text = "Verbunden – warte auf Daten …"
			if _manual_pause:
				text += "\n(manuell pausiert)"
			return text
	return ""


## Rundenzeiten, Medaillen, Bestzeit und Segmente fürs Ergebnis, z. B. "Runden: 1:52.3 · 1:49.8\nMedaillen: Silber ·
## Gold\nBestzeit: 1:49.8 – neu!\nSegmente: Dorfsprint 0:41.2 Gold" – je Segment die schnellste Zeit der Fahrt.
func lap_result() -> String:
	var times := lap_timing.lap_times.map(func(t): return format_time(t, true))
	var medals := []
	for i in range(times.size()):
		medals.append(lap_medal(i))
	var best := lap_timing.best_s()
	var text := "%s: %s\n%s: %s\nBestzeit: %s%s" % ["Runde" if times.size() == 1 else "Runden", " · ".join(times),
			"Medaille" if times.size() == 1 else "Medaillen", Medals.summary(medals),
			format_time(best, true) if is_finite(best) else "–", " – neu!" if lap_timing.new_best() else ""]
	var segments := []
	for segment in track.segments:
		var fastest := {}
		for result in lap_timing.segments.results:
			if result["id"] == segment["id"] and (fastest.is_empty() or result["time_s"] < fastest["time_s"]):
				fastest = result
		if not fastest.is_empty():
			segments.append(("%s %s %s" % [segment["name"], format_time(fastest["time_s"], true),
					Medals.name_of(segment_medal(fastest))]).strip_edges())
	if not segments.is_empty():
		text += "\nSegmente: " + " · ".join(segments)
	return text


## Ergebnis eines Trainings: Einheit, Zeit, Treffer der Zielkadenz gesamt und je gefahrener Phase, z. B.
## „Training beendet! · Neuer Erfolg: Erste Einheit\nPyramide · Zeit: 34:00.0\nZielkadenz getroffen: 87 %\nJe Phase:
## Aufwärmen 100 % · 70 rpm 80 % · …“. Abgebrochen: die Teilbewertung der gefahrenen Phasen.
func training_result() -> String:
	var rewards := rewards_result()
	return "%s%s\n%s · Zeit: %s\nZielkadenz getroffen: %s\nJe Phase: %s\nØ Kadenz: %d rpm · Ø Tempo: %.1f km/h\n%s" % [
			"Training beendet!" if training.finished() else "Training abgebrochen",
			" · " + rewards if not rewards.is_empty() else "", training.unit["name"], format_time(lap_time_s(), true),
			Training.percent_text(training.total_score()), training.phase_summary(), roundi(stats.avg_cadence()),
			stats.avg_speed_kmh(), "Enter: zurück ins Menü · Esc: Einstellungen"]


## Zusammenfassung eines Arcade-Laufs (#46): Text der Bühne mit den Werten der Fahrt.
func arcade_result() -> String:
	return arcade_stage.result_text(rewards_result(), format_time(lap_time_s(), true), lap_timing.lap_times.size(),
			stats.distance_m / 1000.0, roundi(stats.avg_cadence()), stats.avg_speed_kmh())


## Neue Erfolge und Levelaufstieg dieser Fahrt fürs Ergebnis in einer Zeile, z. B. „Neuer Erfolg: Erste Runde ·
## Fahrerlevel 2 erreicht“ oder „3 neue Erfolge“ ("" = nichts Neues). Alle stehen im Fahrtenbuch.
func rewards_result() -> String:
	var parts := []
	if ride_achievements.size() == 1:
		parts.append("Neuer Erfolg: %s" % ride_achievements[0]["name"])
	elif ride_achievements.size() > 1:
		parts.append("%d neue Erfolge" % ride_achievements.size())
	if ride_level > _level_before:
		parts.append("Fahrerlevel %d erreicht" % ride_level)
	return " · ".join(parts)


## Medaille der Runde `index` (ab 0). Eine verkürzte erste Runde (Start nicht an der Start/Ziel-Linie) bekommt keine.
func lap_medal(index: int) -> String:
	if index == 0 and not is_zero_approx(track.wrap_distance(start_distance_m)):
		return Medals.NONE
	return Medals.medal_for(lap_timing.lap_times[index], medal_limits.get(Medals.LAP, {}))


## Medaille eines gewerteten Segments ({id, time_s, …} aus SegmentTiming.results).
func segment_medal(result: Dictionary) -> String:
	return Medals.medal_for(result["time_s"], medal_limits.get(result["id"], {}))


## Einblendung beim Verlassen eines Segments, z. B. "Dorfsprint  0:41.2 · Gold – neue Bestzeit!".
func segment_result_text(result: Dictionary) -> String:
	var text := "%s  %s" % [result["name"], format_time(result["time_s"], true)]
	var medal := Medals.name_of(segment_medal(result))
	if not medal.is_empty():
		text += " · " + medal
	if result["new_best"]:
		text += " – neue Bestzeit!"
	return text


func _update_state() -> void:
	if bus.bus_connected:
		_ever_connected = true
	if state == STATE_FINISHED or state == STATE_MENU:
		return
	var connection_ok := bus.bus_connected and bus.status == BusClient.STATE_CONNECTED and _data_since_loss
	var next := STATE_RIDING
	if not connection_ok:
		next = STATE_PAUSED_CONNECTION
	elif _manual_pause:
		next = STATE_PAUSED_MANUAL
	if next != state:
		state = next
		if state == STATE_PAUSED_CONNECTION:
			grade_reporter.reset()  # nach der Rückkehr Steigung neu melden
		state_changed.emit(state)


## Ein Zeitschritt Fahrt: Fahrmodell, Statistik, Rundenwertung, Training und Ziel. Den Schritt über die Ziellinie
## (bzw. über das Ende der Einheit) zählen Statistik und Rundenwertung nur anteilig, damit Zeiten und Durchschnitte
## genau sind.
func _ride(delta: float) -> void:
	var before := model.distance_m
	model.step(bus.cadence, current_grade(), delta)
	var moved := model.distance_m - before
	var used := delta
	if model.distance_m >= finish_distance_m:
		used = delta * ((finish_distance_m - before) / moved if moved > 0.0 else 1.0)
		model.distance_m = finish_distance_m
	if training != null and training.remaining_total_s() < used:
		model.distance_m = before + moved * training.remaining_total_s() / delta
		used = training.remaining_total_s()
	stats.add(used, bus.cadence, model.distance_m - before)
	if training != null:
		training.advance(bus.cadence, used)
	arcade_stage.advance(model.distance_m, used)
	var segments_before := lap_timing.segments.results.size()
	var laps_done := lap_timing.advance(model.distance_m, used)
	if laps_done > 0 and records_count() and lap_timing.last_lap_is_new_best():
		hud.celebrate("Neue Bestzeit!  %s" % format_time(lap_timing.lap_times[-1], true))
	for i in range(segments_before, lap_timing.segments.results.size()):
		hud.celebrate(segment_result_text(lap_timing.segments.results[i]))
	if laps_done > 0:
		_achievement_event({"type": Achievements.EVENT_LAP, "total_laps": _laps_before + lap_timing.lap_times.size(),
				"ride_laps": lap_timing.lap_times.size()})
	while _km_before + stats.distance_m / 1000.0 >= _next_km:
		_next_km += 1.0
		for event in _km_events():
			_achievement_event(event)
		_check_level()
	if lap_timing.finished() or (training != null and training.finished()):
		_finish_ride()


## Meldet die Steigung per `set_grade`, wenn sie sich genug geändert hat (gedrosselt, siehe GradeReporter).
## In der Verbindungspause nicht – Senden wäre sinnlos.
func _report_grade(delta: float) -> void:
	grade_reporter.tick(delta)
	if state == STATE_PAUSED_CONNECTION:
		return
	var grade := GradeReporter.quantize(current_grade())
	if grade_reporter.wants_to_send(grade) and bus.send_message({"type": "set_grade", "grade": grade}) == OK:
		grade_reporter.sent(grade)


func _on_ack(message: Dictionary) -> void:
	if message.get("for") != "set_grade":
		return
	if message.get("ok") == true:
		resistance_hint = ""
	elif message.get("reason") == "not_supported":
		resistance_hint = RESISTANCE_NOT_SUPPORTED
	else:
		resistance_hint = "Widerstand: Fehler (%s)" % message.get("reason")


func _on_telemetry(_message: Dictionary) -> void:
	_data_since_loss = true


func _on_status_changed(new_state: String) -> void:
	if new_state != BusClient.STATE_CONNECTED:
		_data_since_loss = false


func _on_bus_connection_changed(connected: bool) -> void:
	if not connected:
		_data_since_loss = false


## Inhalt der Debug-Anzeige (F3): Kadenz-Rohwert wie empfangen, Bridge-Zeitstempel und Zeit seit Empfang der
## letzten Telemetrie im Spiel – zur Prüfung der Latenz (< 200 ms, ADR-0005). Die Zeit seit Empfang zeigt nur, ob
## Daten stocken; die Gesamtlatenz Kurbel → Bild misst sie nicht (siehe docs/anleitung.md).
func debug_text() -> String:
	var raw = bus.last_telemetry.get("cadence")
	var age := bus.telemetry_age_ms()
	return "DEBUG\nKadenz roh: %s\nt_ms: %s\nLetzte Telemetrie vor: %s\nBus: %s · Quelle: %s (%s)" % [
			"–" if raw == null else str(raw),
			"–" if bus.last_telemetry_t_ms < 0 else str(bus.last_telemetry_t_ms),
			"–" if age < 0 else "%d ms" % age,
			"verbunden" if bus.bus_connected else "getrennt", bus.status,
			bus.source if not bus.source.is_empty() else "?"]


func _register_key_bindings() -> void:
	for action in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


## Pose von Fahrer und Rad: Kadenz und Tempo wie gefahren, Pause in jedem Zustand außer `riding`.
func _update_rider(delta: float) -> void:
	rider_model.update(bus.cadence, model.speed_mps, current_grade(), current_curvature(), state != STATE_RIDING, delta)
	if ghost == null:
		return
	# Der Ghost kennt nur Strecke über Zeit: Tempo daraus, Kadenz für die Kurbel über das Fahrmodell zurückgerechnet.
	var t := lap_timing.lap_time_s
	var d := ghost_distance_m()
	var speed := ghost.position_at(t + 0.5) - ghost.position_at(t - 0.5)
	var grade := track.grade_at(d)
	var per_rpm := model.target_speed_mps(1.0, grade)
	ghost_model.update(speed / per_rpm if per_rpm > 0.0 else 0.0, speed, grade, curvature_at(d), state != STATE_RIDING,
			delta)


## Trainingszeile, Zonenbalken und Ansage im HUD (ausgeblendet ohne Training und im Ergebnis).
func _show_training() -> void:
	if training == null or state == STATE_FINISHED:
		hud.show_training("", "", "", "")
		hud.hide_zone()
		hud.show_announcement("")
		sound.announce("", -1)
		return
	var phase := training.phase()
	var next := training.next_phase()
	hud.show_training(phase["name"], Training.target_text(phase), format_time(ceilf(training.remaining_s())),
			"%s · %s" % [next["name"], Training.target_text(next)] if not next.is_empty() else "Ende der Einheit")
	hud.show_zone(phase["cadence_min"], phase["cadence_max"], bus.cadence,
			Training.percent_text(training.phase_score(training.phase_index())))
	var announcement := training.announcement()
	hud.show_announcement(announcement)
	sound.announce(announcement, training.phase_index())


func _new_gate(node_name: String) -> CourseGate:
	var gate := CourseGate.new()
	gate.name = node_name
	gate.visible = false
	track.add_child(gate)
	return gate


## Intervall-Tore (#58): das nächste Tor der Einheit an der Lage beim aktuellen Tempo (GatePlacement, zu sehen nur fest
## oder weit voraus), das zuletzt durchfahrene bis GATE_KEEP_BEHIND_M hinter dem Fahrer; ohne Training und im Menü
## keine. Ein Tor, das mehr als eine Runde voraus läge, bleibt unsichtbar. Liest nur Training und Fahrmodell, ändert
## nichts daran.
func _update_gates() -> void:
	if training == null or state == STATE_MENU:
		gate_next.visible = false
		gate_passed.visible = false
		return
	if training != _gates_of:
		_gates_of = training
		_gates = training.gates()
		_gate_index = -1
		gate_next.ride_m = NAN
		gate_passed.ride_m = NAN
	var i := 0
	while i < _gates.size() and _gates[i]["time_s"] <= training.elapsed_s + 1e-6:
		i += 1
	if i != _gate_index:
		if not is_nan(gate_next.ride_m):  # durchfahren: bleibt stehen, das andere Tor wird das nächste
			var passed := gate_next
			gate_next = gate_passed
			gate_passed = passed
		_gate_index = i
		gate_placement.reset()
		gate_next.ride_m = NAN
		if i < _gates.size():
			gate_next.configure(_gates[i]["kind"], _gates[i]["text"])
	var d := model.distance_m
	gate_passed.visible = not is_nan(gate_passed.ride_m) and gate_passed.ride_m > d - GATE_KEEP_BEHIND_M
	if i >= _gates.size():
		gate_next.visible = false
		return
	var at := gate_placement.update(d, _gates[i]["time_s"] - training.elapsed_s, model.speed_mps)
	gate_next.place(track, at)
	gate_next.visible = gate_placement.shown(d) and at - d < track.length_m() - GATE_KEEP_BEHIND_M


func _update_view() -> void:
	rider.progress = track.path_distance(model.distance_m)
	var grade := current_grade()
	hud.show_ride(bus.cadence, model.speed_kmh(), stats.distance_m, format_time(lap_time_s()), grade,
			format_grade(grade), current_station(), format_power(bus.power_w(), bus.power_estimated()))
	hud.show_lap(model.distance_m, lap_timing.lap_start_m(), lap_timing.lap_end_m(), track.wrap_distance(model.distance_m))
	hud.show_lap_count(lap_timing.lap_number(), laps, format_time(lap_timing.lap_time_s))
	if ghost != null:
		ghost_rider.progress = track.path_distance(ghost_distance_m())
		var gap := ghost_gap_s()
		hud.show_ghost(format_gap(gap), gap > 0.0)
	else:
		hud.show_ghost("", false)
	_show_training()
	_update_gates()
	arcade_stage.update_view(model.distance_m, model.speed_mps, state == STATE_MENU, state == STATE_FINISHED)
	var segment := lap_timing.segments.current()
	hud.show_segment(segment.get("name", ""), format_time(segment["time_s"], true) if not segment.is_empty() else "")
	if debug_label.visible:
		debug_label.text = debug_text()
	hint_label.text = resistance_hint
	var message := status_message()
	message_label.text = message
	message_label.visible = not message.is_empty()
