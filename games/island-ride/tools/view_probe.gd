## Manuelle Sichtprüfung (#15): startet die Hauptszene gerendert (ohne `--headless`, ohne Bus), stellt den Fahrer
## an Streckenpositionen und speichert je ein Viewport-Bild; optional fährt sie einen Abschnitt mit festem Tempo ab
## und misst die Bildrate.
##   godot --path games/island-ride -s res://tools/view_probe.gd -- --out=C:/tmp/shots [--shots=0,200,450]
##         [--fps-from=0 --fps-to=2310 --speed-kmh=50] [--size=1920x1080] [--cadence=85] [--close] [--pair]
##         [--advance=1.5] [--time=21:30] [--date=2026-06-21] [--weather=rain] [--season=summer] [--profile=forward|compat]
##         [--aa=msaa_4x] [--scale=1.0] [--upscaler=bilinear] [--vsync=off] [--hud] [--debug] [--menu] [--crop=x,y,w,h]
##         [--title] [--window=left|right|fullscreen] [--laps=3] [--segments] [--ghost=1.4] [--logbook] [--rewards]
##         [--training] [--ccw] [--wardrobe=trikot_gelb,radfarbe_blau,helm_schwarz] [--fauna] [--effects-kmh=55] [--intro]
##         [--panorama=aussichtspunkt,burg] [--view=nah|verfolger|weit] [--arcade] [--gear] [--props] [--rhythm]
##         [--bosses] [--elite]
## `--shots`: Streckenpositionen (m) für Screenshots (`shot_<m>.png` in `--out`). `--fps-from/--fps-to`: Fahrt mit
## `--speed-kmh` über diesen Abschnitt, danach eine Zeile mit min/Mittel/1-%-Tief der fps. Das HUD wird ausgeblendet
## (ohne Bridge stünde dort die Verbindungsmeldung) – außer mit `--hud`: dann zeigt es Beispielwerte (Kadenz wie
## `--cadence`, Tempo des Fahrmodells, Steigung und Abschnitt der Strecke, Strecke/Zeit bis zur Position, „~142 W“),
## die Verbindungsmeldung ist unsichtbar. `--debug` blendet zusätzlich die Debug-Anzeige (F3) ein. `--menu` öffnet
## das Grafikmenü. Grafik wie bei einem frischen Start (GraphicsSettings-Standard,
## `user://settings.cfg` bleibt unberührt); `--aa`/`--scale`/`--upscaler`/`--vsync=off` überschreiben. `--crop`:
## zusätzlich Bildausschnitt `crop_<m>.png` (z. B. für den AA-Vergleich). VSync wie im Projekt (Standard: an).
## Fahrer und Rad treten mit `--cadence` (rpm, 0 = Stillstand): die Hauptszene füttert ohne Bus nur eine Attrappe
## (sie steht in der Verbindungspause), die Probe bewegt das echte Modell. Vor jedem Screenshot 1 s Tritt.
## `--close`: zusätzlich Nahaufnahmen je Position (`close_<m>_side.png`, `close_<m>_rear.png`, Kamera nur hier
## versetzt). `--pair`: zweites Bild 0,15 s später (`shot_<m>_b.png`) – Kurbelstellung muss sich unterscheiden.
## `--advance`: im Bildpaar zusätzlich die Weltanimation (WorldMotion: Flügel, Vögel, Boote, Wolken) um so viele
## Sekunden vorrücken, damit die Bewegung im Vergleich sichtbar wird (Standard 0).
## Tag/Nacht und Wetter (G6): `--time` feste Ortszeit (Mallorca, HH:MM), `--date` Datum dazu (Standard heute),
## `--weather` festes Wetter (clear, light_clouds, overcast, rain) ohne Überblendung. Ohne Angabe gilt `[sky]` aus
## config.cfg. Bei Regen wartet die Probe, bis die Tropfen gefallen sind. Jahreszeit (#39): `--season` feste Phase
## (almond, spring, summer, autumn, winter); ohne Angabe folgt sie dem Datum (`--date` oder heute). `--profile` erzwingt das Lichtprofil
## (Vergleich: Compatibility-Renderer mit `--profile=forward` zeigt das Bild ohne Web-Profil).
## Startmenü (#30): `--title` startet wie das Spiel mit Titelbild und Kameraflug und speichert `title.png`,
## `title_modes.png` (Seite „Fahren“) und `title_b.png` (3 s später, Kamera weitergeflogen) statt der Streckenbilder.
## `--window` legt das Fenster vorher wie im Grafikmenü auf die linke/rechte Bildschirmhälfte oder ins Vollbild.
## Rundfahrt (#31): `--laps=N` (0 = endlos) zeigt eine Fahrt über N Runden mit Beispiel-Bestzeit (LAP_SAMPLES_S, nur im
## Speicher). Mit `--title` zusätzlich `title_round_trip.png` (Seite „Rundfahrt“), mit `--hud` steht der Fahrer in
## Runde 2 (HUD mit Runde und Rundenzeit, Einblendung „Neue Bestzeit!“), danach `result.png` mit dem Ergebnis aller
## Runden (mit Medaillen und, über die Beispielzeiten anteilig, den Segmenten, #33).
## Segmente (#33): `--segments` (mit `--hud`) stellt den Fahrer in jedes Segment der Strecke – HUD mit Live-Zeit,
## `segment_<id>.png` – und kurz hinter sein Ende mit dem Ergebnis beim Verlassen (`segment_<id>_result.png`);
## Beispielzeit knapp unter der Silber-Schwelle. Die Torbögen zeigen `--shots` kurz vor dem Segmentstart.
## Ghost (#32): `--ghost=S` lässt einen Beispiel-Ghost mitfahren, gegen den der Fahrer S Sekunden zurückliegt (negativ:
## vorn) – gleiches Tempo wie der Fahrer (Beispielfahrt 22 km/h, bei `--fps-*` dessen Tempo), halbtransparent
## neben/vor dem Fahrer, mit `--hud` der Abstand im HUD. Mit `--title --laps=N` steht er (nur im Speicher) als
## Bestzeit und letzte Fahrt in der Ghost-Auswahl der Seite „Rundfahrt“.
## Fahrtenbuch (#35): `--title --logbook` füllt den Spielstand (nur im Speicher) mit Beispielfahrten, Bestzeiten,
## Segmentzeiten, Medaillen und Erfolgen, öffnet das Fahrtenbuch aus dem Startmenü und speichert je Seite
## `logbook_overview.png`, `logbook_achievements.png` und `logbook_rides.png` statt der Titelbilder.
## `--hud --rewards` speichert nach den Streckenbildern die Einblendung eines Erfolgs (`achievement.png`) und eines
## Levelaufstiegs (`level_up.png`) an der letzten Position aus `--shots`.
## Training (#37): `--title --training` speichert zusätzlich `title_training.png` (Seite „Training“); `--hud --training`
## fährt nach den Streckenbildern die Einheit „Intervalle kurz“ bis kurz vor die erste harte Phase (HUD mit
## Trainingszeile und Ansage, `training.png`) und dann zu Ende, mit Treffern je nach Phase (`training_result.png`).
## Zonenbalken und Tore (#58): dazwischen fährt sie mit dem Tempo des Fahrmodells bis 3 s vor die harte Phase
## (Starttor fest vor dem Fahrer, `gate_start.png`), zeigt dort den Zonenbalken mit Kadenz unter, im und über dem
## Bereich (`zone_below.png`, `zone_inside.png`, `zone_above.png`) und fährt weiter bis 3 s vor ihr Ende (Zieltor,
## `gate_finish.png`).
## Arcade (#46): `--title --arcade` speichert zusätzlich `title_arcade.png` (Seite „Arcade“); `--hud --arcade` startet
## nach den Streckenbildern einen Arcade-Lauf (Stufe 1, Kadenzbereich 60–120 rpm, Zone halten in der Mitte) kurz hinter
## dem Start: Starttor und nächste Herausforderung (`arcade_gate.png`), Zone halten mitten im Halten (`zone_hold.png`,
## Fortschritt und Zieltor), Kadenz zu hoch (`zone_hold_above.png`), geschafft (`zone_hold_success.png`) und die
## Zusammenfassung nach „Fahrt beenden“ (`arcade_result.png`). Beute (#49): direkt nach dem Erfolg die Lichtsäule des
## Fundes mit den Popups (`loot_beam.png`, die Zusammenfassung nennt den Fund).
## Ausrüstung (#49): `--gear` legt im Spielstand (nur im Speicher) je Platz ein Beispielteil an (alle Seltenheiten) und
## legt weitere ins Inventar. Mit `--title` öffnet die Probe „Fahren → Arcade → Ausrüstung“ und speichert `gear.png`
## statt der Titelbilder; mit `--hud --arcade` trägt der Fahrer die Ausrüstung im Arcade-Lauf, dazu vorher die
## Nahaufnahmen `close_5_side.png` und `close_5_rear.png`.
## Durchbruch und Jagd (#47): `--hud --arcade --props` zeigt statt des Zone-halten-Laufs die Zugbrücke des Durchbruchs
## zu, halb und offen (`bridge_closed.png`, `bridge_half.png`, `bridge_open.png`, dazu `bridge_close_*.png` aus der
## Nähe) und den Verfolger der Jagd (`pursuer_close.png` von hinten, `pursuer_front.png` und `pursuer_side.png` aus der
## Nähe, `pursuer_gone.png` nach dem Abhängen). Balken und Abstand setzt die Probe direkt.
## Takt-Tore und Sammeln (#48): `--hud --arcade --rhythm` zeigt die Takt-Tore vor dem ersten Schlag (`rhythm_ahead.png`), nach
## einem Treffer (`rhythm_hit.png`, Tor „Treffer“ hinter dem Fahrer, nächstes voraus) und nach einem verpassten Tor mit zu
## hoher Kadenz (`rhythm_missed.png`), dann das Sammeln: Objekte voraus mit großem Magnetring bei hoher Kadenz
## (`collect_high.png`), mit kleinem Ring bei niedriger (`collect_low.png`) und die Objekte aus der Nähe (`collect_close.png`).
## Bosse (#51): `--hud --arcade --bosses` stellt den Fahrer an den Ort jedes Bosses (Küstenstraße, Serpentinen, Bergdorf)
## und spielt den Kampf mit passender Kadenz: zu Beginn mit vollem Lebensbalken (`boss_<id>.png`), aus der Nähe
## (`boss_<id>_close.png`), angeschlagen (`boss_<id>_hurt.png`, Tramuntana in der Böe mit Windstreifen), dann besiegt
## (`boss_tramuntana_defeated.png`, `boss_drac_defeated.png`, beim Zusammensinken) bzw. entkommen (`boss_dimonis_escape.png`,
## ohne Treten: die Dimonis ziehen davon).
## Elite-Gruppen (#52): `--hud --arcade --elite` zeigt Champions (Jagd mit Windschnell und Gegenwind) angekündigt am
## Startpunkt (`elite_champion_announce.png`, Standarte und Schild blau) und im Kampf mit dem Verfolger
## (`elite_champion.png`), Seltene (Durchbruch mit Gegenwind und Zäh) angekündigt (`elite_selten_announce.png`), mit der
## Zugbrücke (`elite_selten.png`) und im Gefolge (`elite_selten_gefolge.png`), die wandernde Zone von Wankelmütig
## (`elite_wankelmuetig.png`) und die Standarte aus der Nähe (`elite_banner_close.png`).
## Gegenrichtung (#34): `--ccw` fährt gegen den Uhrzeigersinn – `--shots`, `--segments`, `--laps` und `--ghost` dann in
## Fahrtposition dieser Richtung, mit `--title` ist die Richtung auf der Seite „Rundfahrt“ gewählt.
## Garderobe (#36): `--wardrobe=TEIL,…` gibt dem Spielstand (nur im Speicher) Kilometer bis Level 12 und wählt die Teile
## (Wardrobe.PARTS; leer = Standard) – der Fahrer trägt sie in `--shots`/`--close`. Mit `--title` öffnet die Probe die
## Garderobe aus dem Startmenü und speichert `wardrobe.png` statt der Titelbilder.
## Tiere (#40): `--fauna` speichert nach den Streckenbildern je Tierart (IslandFauna.KINDS) eine Nahaufnahme
## (`fauna_<Art>.png`, Kamera wenige Meter neben dem Tier, Blick von der Straße) und 2,5 s Tieranimation später ein
## zweites Bild (`fauna_<Art>_b.png`). Die Ziegenquerung zeigen `--shots` 100–35 m vor IslandFauna.CROSSINGS_M.
## Delfine und Fische (#41) im Sprung, das zweite Bild 0,25 s später; ausgeblendete Arten (Tag/Nacht, Wetter) fehlen.
## Tempo-Effekte (#42): `--effects-kmh=V` zeigt Geschwindigkeitslinien und Sichtfeld-Kick in `--shots` wie bei V km/h
## (SpeedEffects.hold_kmh); die fps-Fahrt (`--fps-*`) zeigt sie immer mit ihrem Tempo, wie im Spiel (Standard: an).
## Kamera-Intro (#42): `--intro` startet vor den Streckenbildern eine Fahrt wie „Losfahren“ (mit `--ccw` gegen den
## Uhrzeigersinn) und speichert `intro_0.png` (0,3 s), `intro_1.png` (1,5 s) und `intro_2.png` (nach dem Intro).
## Panorama-Momente (#43): `--panorama=ID,…` stellt den Fahrer an den Auslösepunkt jeder genannten Sehenswürdigkeit
## (IslandWorld.panorama_spots; `--panorama` ohne Liste = alle, mit `--ccw` in dieser Richtung), startet dort das
## Panorama und speichert `panorama_<id>.png` mitten im Schwenk (mit `--hud` samt Namen) vor den Streckenbildern; der
## Fahrer fährt dabei mit dem Tempo des Fahrmodells zu `--cadence` weiter.
## Kameraperspektiven (#59): `--view=ID` (CameraViews.IDS) wählt die Perspektive für `--intro`, `--panorama` und
## `--shots` (nur im Speicher); mit `--hud` steht in `--shots` die Einblendung ihres Namens wie nach der Taste `C`.
extends SceneTree

## Beispiel-Rundenzeiten (s) für `--laps`: gespeicherte Bestzeit vorher, dann die Runden der Fahrt.
const LAP_SAMPLES_S := [905.3, 912.4, 884.7, 897.9, 890.2]

var _ride: Node3D
## Echtes Fahrer-/Radmodell in der Szene und Kadenz, mit der es tritt.
var _model: RiderModel
var _cadence := 85.0
## Bildausschnitt für `crop_<m>.png` (leer = keiner).
var _crop := Rect2i()
## Gegen den Uhrzeigersinn fahren (#34)?
var _ccw := false
## HUD mit Beispielwerten zeigen (`--hud`).
var _hud := false
## Debug-Anzeige (F3) zeigen (`--debug`).
var _debug := false
## Rundenzahl der Beispiel-Rundfahrt (`--laps`; −1 = ohne).
var _laps := -1
## Live-Zeit und Ergebnis je Segment zeigen (`--segments`).
var _segments := false
## Rückstand auf den Beispiel-Ghost in Sekunden (`--ghost`; NAN = ohne Ghost).
var _ghost_s := NAN
## Fahrtenbuch statt Titelbilder (`--logbook`), Einblendungen von Erfolg und Levelaufstieg (`--rewards`).
var _logbook := false
## Nahaufnahmen der Tiere (`--fauna`).
var _fauna := false
var _rewards := false
## Trainingsseite bzw. Training im HUD (`--training`).
var _training := false
## Arcade-Seite bzw. Arcade-Lauf im HUD (`--arcade`).
var _arcade := false
## Zugbrücke und Verfolger statt Zone halten (`--props`, #47).
var _props := false
## Takt-Tore und Sammeln statt Zone halten (`--rhythm`, #48).
var _rhythm := false
## Die drei Bosse statt Zone halten (`--bosses`, #51).
var _bosses := false
## Elite-Gruppen statt Zone halten (`--elite`, #52).
var _elite := false
## Beispiel-Ausrüstung angelegt (`--gear`, #49).
var _gear := false
## Garderobe: gewählte Teile (`--wardrobe`; null = ohne).
var _outfit = null
## Tempo der Tempo-Effekte in `--shots` (`--effects-kmh`; NAN = wie die Fahrt) und Kamera-Intro (`--intro`).
var _effects_kmh := NAN
var _intro := false
## Sehenswürdigkeiten für Panorama-Bilder (`--panorama`; null = keine, leer = alle).
var _panorama = null
## Kameraperspektive (`--view`; "" = Standard).
var _view := ""


func _initialize() -> void:
	var out_dir := OS.get_user_data_dir()
	var shots: Array[float] = []
	var fps_from := -1.0
	var fps_to := -1.0
	var speed_kmh := 50.0
	var size := Vector2i(1920, 1080)
	var close := false
	var pair := false
	var advance := 0.0
	var menu := false
	var title := false
	var window := ""
	var graphics := GraphicsSettings.new()
	var hour := NAN
	var date := ""
	var weather := ""
	var season := ""
	var profile := ""
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--out="):
			out_dir = value
		elif arg.begins_with("--shots="):
			for part in value.split(",", false):
				shots.append(float(part))
		elif arg.begins_with("--fps-from="):
			fps_from = float(value)
		elif arg.begins_with("--fps-to="):
			fps_to = float(value)
		elif arg.begins_with("--speed-kmh="):
			speed_kmh = float(value)
		elif arg.begins_with("--size="):
			size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
		elif arg.begins_with("--cadence="):
			_cadence = float(value)
		elif arg == "--close":
			close = true
		elif arg == "--pair":
			pair = true
		elif arg.begins_with("--advance="):
			advance = float(value)
		elif arg.begins_with("--aa="):
			graphics.aa = value
		elif arg.begins_with("--scale="):
			graphics.render_scale = float(value)
		elif arg.begins_with("--upscaler="):
			graphics.upscaler = value
		elif arg == "--vsync=off":
			graphics.vsync = false
		elif arg == "--hud":
			_hud = true
		elif arg == "--debug":
			_debug = true
		elif arg == "--menu":
			menu = true
		elif arg == "--title":
			title = true
		elif arg.begins_with("--window="):
			window = value
		elif arg.begins_with("--laps="):
			_laps = int(value)
		elif arg == "--segments":
			_segments = true
		elif arg.begins_with("--ghost="):
			_ghost_s = float(value)
		elif arg == "--logbook":
			_logbook = true
		elif arg == "--rewards":
			_rewards = true
		elif arg == "--training":
			_training = true
		elif arg == "--arcade":
			_arcade = true
		elif arg == "--gear":
			_gear = true
		elif arg == "--props":
			_props = true
		elif arg == "--rhythm":
			_rhythm = true
		elif arg == "--bosses":
			_bosses = true
		elif arg == "--elite":
			_elite = true
		elif arg.begins_with("--wardrobe"):
			_outfit = Array(value.split(",", false)) if arg.contains("=") else []
		elif arg == "--fauna":
			_fauna = true
		elif arg == "--ccw":
			_ccw = true
		elif arg.begins_with("--effects-kmh="):
			_effects_kmh = float(value)
		elif arg == "--intro":
			_intro = true
		elif arg.begins_with("--panorama"):
			_panorama = Array(value.split(",", false)) if arg.contains("=") else []
		elif arg.begins_with("--view="):
			_view = value
		elif arg.begins_with("--crop="):
			var p := value.split(",")
			_crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
		elif arg.begins_with("--time="):
			hour = float(value.get_slice(":", 0)) + float(value.get_slice(":", 1)) / 60.0
		elif arg.begins_with("--date="):
			date = value
		elif arg.begins_with("--weather="):
			weather = value
		elif arg.begins_with("--season="):
			season = value
		elif arg.begins_with("--profile="):
			profile = value
	DisplayServer.window_set_size(size)
	var config := RideConfig.load_file()
	config.bridge_autostart = false  # Prüfhilfe startet nie selbst eine Bridge (#25)
	config.bus_url = TestIsolation.probe_bus_url(config.bus_url)  # mit VSPIN_PORT_BASE nie die Bridge des Spielers (#62)
	IslandTerrain.cache_path = TestIsolation.path("terrain_cache.bin")  # nie user:// (#62)
	config.track = RideConfig.TRACK_ISLAND
	_ride = load("res://scenes/main.tscn").instantiate()
	_ride.config = config
	_ride.settings_path = ""
	_ride.save_path = ""
	_ride.start_in_menu = title
	root.add_child(_ride)
	_ride.get_node("Hud").visible = _hud
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(10)
	_ride.settings_menu.settings = graphics  # erst nach `_ready` der Hauptszene vorhanden
	_ride.settings_menu.apply()
	if window == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif window in ["left", "right"]:
		_ride.settings_menu.place_half(window == "right")
	if not window.is_empty():
		await _frames(30)
	_ride.debug_label.visible = _debug
	if menu:
		_ride.settings_menu.open()
	if _hud:
		# Beispielwerte: die Hauptszene zeigt Kadenz und Watt des (ohne Bridge nicht verbundenen) Bus-Clients an.
		_ride.get_node("Hud/Message").modulate = Color.TRANSPARENT
		_ride.bus.cadence = _cadence
		_ride.bus.last_telemetry = {"cadence": _cadence, "power_w": 142.0}
	if not profile.is_empty():
		_ride.sky.set_compatibility(profile == "compat")
	_set_sky(hour, date, weather, season)
	if weather == Weather.RAIN:
		await _frames(100)
	if _ccw:
		_ride._set_direction(Track.DIRECTION_CCW)
		(_ride.start_menu.options["direction"] as OptionButton).select(1)
		_ride._new_lap_timing()
		_ride._update_round_trip_menu()
	if _laps >= 0:
		_ride.save_game.record_best_time(config.track, _ride.track.direction, LAP_SAMPLES_S[0])
		_ride.laps = _laps
		_ride._update_round_trip_menu()
		(_ride.start_menu.options["laps"] as OptionButton).select(_ride.start_menu.LAP_CHOICES.find(_laps))
		if not is_nan(_ghost_s):
			for kind in [Ghost.BEST, Ghost.LAST]:
				_ride.save_game.record_ghost(config.track, _ride.track.direction, kind, _sample_ghost(22.0 / 3.6))
			_ride._update_round_trip_menu()
	if _outfit != null:
		_dress()
	if _gear:
		_equip_samples()
	if title:
		if _gear:
			await _gear_shot(out_dir)
		elif _outfit != null:
			await _wardrobe_shot(out_dir)
		elif _logbook:
			await _logbook_shots(out_dir)
		else:
			await _title_shots(out_dir)
		quit(0)
		return
	if not _view.is_empty():
		_ride.set_camera_view(_view, false)
	_model = _ride.rider_model  # erst nach `_ready` der Hauptszene gesetzt
	var dummy := RiderModel.new()
	_ride.rider_model = dummy
	if _intro:
		await _intro_shots(out_dir)
	if _panorama != null:
		await _panorama_shots(out_dir)
	_ride.speed_effects.hold_kmh = _effects_kmh
	for d in shots:
		_place(d)
		_pedal(1.0)
		if _hud and not _view.is_empty():
			_ride.hud.show_camera_view(CameraViews.NAMES[_ride.camera_view])
		await _frames(8)
		_save(out_dir.path_join("shot_%d.png" % int(d)))
		if pair:
			_pedal(0.15)
			if advance > 0.0 and _ride.world != null:
				_ride.world.motion.advance(advance)
			await _frames(2)
			_save(out_dir.path_join("shot_%d_b.png" % int(d)))
		if close:
			await _close_ups(out_dir, d)
	if _fauna and _ride.world != null:
		await _fauna_shots(out_dir)
	if _segments:
		await _segment_shots(out_dir)
	if _rewards and _hud:
		await _reward_shots(out_dir)
	if _training and _hud:
		await _training_shots(out_dir)
	if _arcade and _hud and _props:
		await _prop_shots(out_dir)
	elif _arcade and _hud and _rhythm:
		await _rhythm_shots(out_dir)
	elif _arcade and _hud and _bosses:
		await _boss_shots(out_dir)
	elif _arcade and _hud and _elite:
		await _elite_shots(out_dir)
	elif _arcade and _hud:
		await _arcade_shots(out_dir)
	if fps_to > fps_from:
		await _measure(fps_from, fps_to, speed_kmh / 3.6)
	if _laps >= 0 and _hud:
		await _result_shot(out_dir)
	_ride.rider_model = _model  # die Hauptszene läuft bis zum Beenden noch einen Frame weiter
	dummy.free()
	quit(0)


## Feste Uhrzeit/Datum/Wetter/Jahreszeit (siehe Kopf); leere Angaben lassen `[sky]` gelten.
func _set_sky(hour: float, date: String, weather: String, season: String) -> void:
	var sky: SkyController = _ride.sky
	if not is_nan(hour):
		sky.set_time_mode(DayNight.MODE_FIXED, hour)
	if not date.is_empty():
		var parts := date.split("-")
		sky.clock.set_mode(DayNight.MODE_FIXED)
		sky.clock.unix_s = DayNight.local_to_unix(int(parts[0]), int(parts[1]), int(parts[2]), sky.clock.fixed_hour)
	if not weather.is_empty():
		sky.set_weather_mode(Weather.MODE_FIXED, weather)
		sky.weather.snap()
	if not season.is_empty():
		sky.set_season_mode(Season.MODE_FIXED, season)
	sky.apply_now()
	print("SKY local=%.2f h sun=%.1f°/%.1f° weather=%s season=%s compat=%s lights=%s" % [sky.clock.local_hour(),
			sky.sun_angles.x, sky.sun_angles.y, sky.weather.state, sky.season(), sky.compatibility, sky.current["lights_on"]])


## Titelbild mit Startmenü (Hauptseite, Seite „Fahren“) und ein Bild 3 s später (Kameraflug).
func _title_shots(out_dir: String) -> void:
	await _frames(20)
	_save_image(out_dir.path_join("title.png"))
	_ride.start_menu.show_page(true)
	await _frames(4)
	_save_image(out_dir.path_join("title_modes.png"))
	if _laps >= 0:
		_ride.start_menu.show_round_trip()
		await _frames(4)
		_save_image(out_dir.path_join("title_round_trip.png"))
	if _training:
		_ride.start_menu.show_training()
		await _frames(4)
		_save_image(out_dir.path_join("title_training.png"))
	if _arcade:
		_ride.start_menu.show_arcade()
		await _frames(4)
		_save_image(out_dir.path_join("title_arcade.png"))
	_ride.start_menu.show_page(false)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		await process_frame
	_save_image(out_dir.path_join("title_b.png"))


## Kamera-Intro wie nach „Losfahren“: Bilder 0,3 s und 1,5 s nach dem Start und nach dem Intro.
func _intro_shots(out_dir: String) -> void:
	_ride.start_ride(SaveGame.MODE_ROUND_TRIP, 1, "", {}, Track.DIRECTION_CCW if _ccw else Track.DIRECTION_CW)
	_ride.get_node("Hud").visible = _hud
	var start := Time.get_ticks_msec()
	for shot in [[0.3, "intro_0.png"], [1.5, "intro_1.png"], [_ride.CAMERA_INTRO_S + 0.3, "intro_2.png"]]:
		while Time.get_ticks_msec() - start < shot[0] * 1000.0:
			await process_frame
		_pedal(0.1)
		await _frames(1)
		_save_image(out_dir.path_join(shot[1]))


## Panorama-Moment an jeder gewählten Sehenswürdigkeit: Fahrer an ihren Auslösepunkt, Panorama wie im Spiel gestartet,
## Bild mitten im Schwenk (die Hauptszene führt die Kamera mit der echten Bildzeit, der Fahrer rollt weiter).
func _panorama_shots(out_dir: String) -> void:
	for spot in _ride.panorama_spots:
		if not _panorama.is_empty() and spot["id"] not in _panorama:
			continue
		_place(_ride.track.path_distance(spot["path_m"]))
		_ride.panorama = spot
		_ride._set_camera_mode(_ride.CAMERA_PANORAMA)
		_ride.hud.show_landmark(spot["name"], _ride.CAMERA_PANORAMA_S)
		var start := Time.get_ticks_msec()
		var last := start
		while Time.get_ticks_msec() - start < _ride.CAMERA_PANORAMA_S * 500.0:
			await process_frame
			var now := Time.get_ticks_msec()
			_ride.model.distance_m += _ride.model.target_speed_mps(_cadence, _ride.current_grade()) * (now - last) / 1000.0
			last = now
		_pedal(0.1)
		await _frames(1)
		_save_image(out_dir.path_join("panorama_%s.png" % spot["id"]))
		_ride._end_panorama()


## Fahrtenbuch mit Beispielstand (nur im Speicher): je Seite ein Bild.
func _logbook_shots(out_dir: String) -> void:
	var save: SaveGame = _ride.save_game
	var track := RideConfig.TRACK_ISLAND
	for i in range(24):
		var stats := RideStats.new()
		var laps := 1 + i % 3
		stats.add(LAP_SAMPLES_S[1 + i % 4] * laps, 84.0 + i % 7, 9210.0 * laps)
		save.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, track, i % 5 != 0, laps, stats,
				"2026-09-%02dT%02d:30:00Z" % [1 + i, 6 + i % 15]))
	save.record_best_time(track, LapTiming.DIRECTION_CW, LAP_SAMPLES_S[2])
	save.record_medal(track, LapTiming.DIRECTION_CW, Medals.LAP, Medals.SILVER)
	var medals := [Medals.GOLD, Medals.SILVER, Medals.BRONZE]
	for i in range(_ride.track.segments.size()):
		var segment: Dictionary = _ride.track.segments[i]
		save.record_segment_time(track, LapTiming.DIRECTION_CW, segment["id"],
				_ride.medal_limits[segment["id"]][medals[i]] - 1.0)
		save.record_medal(track, LapTiming.DIRECTION_CW, segment["id"], medals[i])
	for id in ["km_1", "km_10", "km_100", "ride_km_20", "laps_1", "laps_10", "ride_laps_3", "morning", "evening",
			"night", "clear", "clouds", "rain"]:
		save.unlock_achievement(id, "2026-09-%02dT18:00:00Z" % (1 + id.length()))
	await _frames(20)
	_ride.start_menu.buttons["logbook"].pressed.emit()
	for page in ["overview", "achievements", "rides"]:
		_ride.logbook.show_page(page)
		await _frames(4)
		_save_image(out_dir.path_join("logbook_%s.png" % page))


## Garderobe (nur im Speicher): Kilometer bis Level 12, dann die Teile aus `--wardrobe` wählen; der Fahrer trägt sie.
func _dress() -> void:
	var stats := RideStats.new()
	var km := DriverLevel.km_for(12)
	stats.add(km * 150.0, 85.0, km * 1000.0)
	_ride.save_game.add_ride(SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, false, 0, stats,
			"2026-09-20T18:00:00Z"))
	for item in _outfit:
		if not Wardrobe.choose(_ride.save_game, item):
			push_warning("view_probe: Teil %s unbekannt oder gesperrt" % item)
	_ride._apply_wardrobe()


## Ausrüstung (nur im Speicher, #49): je Platz ein angelegtes Beispielteil in allen Seltenheiten, dazu Kandidaten im
## Inventar und ein paar Splitter.
func _equip_samples() -> void:
	var save: SaveGame = _ride.save_game
	var worn := [
		{"slot": "rahmen", "rarity": Loot.LEGENDARY, "stats": {"progress_pct": 15, "points_pct": 22, "luck_pct": 18,
			"zone_width_rpm": 4}},
		{"slot": "laufraeder", "rarity": Loot.RARE, "stats": {"progress_pct": 11, "points_pct": 16, "luck_pct": 14}},
		{"slot": "trikot", "rarity": Loot.MAGIC, "stats": {"points_pct": 12, "zone_width_rpm": 2}},
		{"slot": "helm", "rarity": Loot.LEGENDARY, "stats": {"zone_width_rpm": 5, "progress_pct": 14, "points_pct": 25,
			"luck_pct": 21}},
		{"slot": "schuhe", "rarity": Loot.COMMON, "stats": {"zone_width_rpm": 2}},
		{"slot": "talisman", "rarity": Loot.RARE, "stats": {"luck_pct": 19, "progress_pct": 9, "points_pct": 14}},
	]
	for item in worn:
		item["effect"] = ""
		Inventory.equip(save, Inventory.add(save, item)["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 49
	for i in range(9):
		Inventory.add(save, Loot.roll(rng, 2.0))
	save.arcade()["shards"] = 27


## Ausrüstung aus der Seite „Arcade“ des Startmenüs; gewählt ist ein Helm (Vergleich mit dem angelegten).
func _gear_shot(out_dir: String) -> void:
	await _frames(20)
	_ride.start_menu.buttons["drive"].pressed.emit()
	_ride.start_menu.buttons["arcade"].pressed.emit()
	_ride.start_menu.buttons["arcade_gear"].pressed.emit()
	var helms := Inventory.items(_ride.save_game).filter(func(item): return item["slot"] == "helm" \
			and not Inventory.is_equipped(_ride.save_game, int(item["id"])))
	if not helms.is_empty():
		_ride.gear_menu.select(int(helms[0]["id"]))
	await _frames(10)
	_save_image(out_dir.path_join("gear.png"))


## Garderobe aus dem Startmenü mit Vorschau.
func _wardrobe_shot(out_dir: String) -> void:
	await _frames(20)
	_ride.start_menu.buttons["wardrobe"].pressed.emit()
	await _frames(30)
	_save_image(out_dir.path_join("wardrobe.png"))


## Einblendungen wie in der Fahrt: ein neuer Erfolg, danach ein Levelaufstieg (die laufende Einblendung beendet).
func _reward_shots(out_dir: String) -> void:
	_ride.hud.end_celebration()
	_ride._achievement_event({"type": Achievements.EVENT_WEATHER, "state": Weather.RAIN})
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("achievement.png"))
	_ride.hud.end_celebration()
	_ride._km_before = DriverLevel.km_for(3) - _ride.stats.distance_m / 1000.0
	_ride._check_level()
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("level_up.png"))


## Training „Intervalle kurz“ an der aktuellen Position: 7,5 s vor der ersten harten Phase (Ansage im HUD), danach die
## ganze Einheit mit Beispieltreffern (jede dritte Phase knapp daneben) bis zum Ergebnis.
func _training_shots(out_dir: String) -> void:
	var unit: Dictionary = Training.load_all()[0]
	var training := Training.new(unit)
	training.advance(_cadence, unit["phases"][0]["duration_s"] - 7.5)
	_ride.ride_mode = SaveGame.MODE_TRAINING
	_ride.training = training
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 0)
	_ride.lap_timing.advance(_ride.model.distance_m, _ride.stats.ride_time_s)
	_ride.hud.end_celebration()
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("training.png"))
	await _ride_training(training, training.remaining_s() - 3.0)
	_save_image(out_dir.path_join("gate_start.png"))
	var warmup: Dictionary = training.phase()
	for zone in [["below", warmup["cadence_min"] - 8.0], ["inside", (warmup["cadence_min"] + warmup["cadence_max"]) / 2.0],
			["above", warmup["cadence_max"] + 8.0]]:
		_ride.bus.cadence = zone[1]
		_ride._update_view()
		await _frames(4)
		_save_image(out_dir.path_join("zone_%s.png" % zone[0]))
	_ride.bus.cadence = _cadence
	await _ride_training(training, training.remaining_s() + training.next_phase()["duration_s"] - 3.0)
	_save_image(out_dir.path_join("gate_finish.png"))
	for i in range(training.phase_index(), training.phases.size()):
		var phase: Dictionary = training.phases[i]
		var cadence: float = (phase["cadence_min"] + phase["cadence_max"]) / 2.0
		training.advance(cadence, training.remaining_s() * 0.8)
		training.advance(cadence - 12.0 if i % 3 == 1 else cadence, training.remaining_s())
	_ride.stats = RideStats.new()
	_ride.stats.add(training.duration_s(), 88.0, training.duration_s() * 22.0 / 3.6)
	_ride._finish_ride()  # wie im Spiel: Erfolg „Erste Einheit“, Spielstand nur im Speicher (save_path "")
	_ride.get_node("Hud/Message").modulate = Color.WHITE
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("training_result.png"))


## Training `seconds` lang mit `_cadence` und dem Tempo des Fahrmodells fahren (Strecke, Einheit, Anzeige, Kamera wie
## im Spiel, ohne Bus), danach die Kamera ruhig dahinter.
func _ride_training(training: Training, seconds: float, dt: float = 1.0 / 30.0) -> void:
	for i in range(maxi(int(seconds / dt), 1)):
		_ride.model.step(_cadence, _ride.current_grade(), dt)
		training.advance(_cadence, dt)
		_ride._update_view()
		_ride._update_camera(dt)
	_ride._update_camera(0.0, true)
	await _frames(8)


## Arcade-Lauf wie nach „Losfahren“ (Stufe 1, Standard-Kadenzbereich, nur „Zone halten“ in der Mitte), Fahrer kurz
## hinter dem Start/Ziel: Starttor, Zone halten, Erfolg, Zusammenfassung.
func _arcade_shots(out_dir: String) -> void:
	var length: float = _ride.track.length_m()
	_place(5.0)
	_ride.ride_mode = SaveGame.MODE_ARCADE
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(length, 0.0, 0)
	_ride.stats = RideStats.new()
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), ArcadeRun.sections_from_stations(_ride.track.ride_stations(),
			length), length, 0.0, 3, [Encounters.find("zone_mitte")])
	_ride.arcade.gear = Inventory.modifiers(_ride.save_game)
	var dummy: RiderModel = _ride.rider_model
	_ride.rider_model = _model  # das echte Modell trägt die Ausrüstung (wie start_ride im Arcade)
	_ride._apply_wardrobe()
	_ride.rider_model = dummy
	if _gear:
		await _close_ups(out_dir, 5.0)
	_ride.hud.end_celebration()
	_ride._update_view()
	_ride._update_camera(0.0, true)
	await _frames(8)
	_save_image(out_dir.path_join("arcade_gate.png"))
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	await _ride_arcade(7.0)
	_save_image(out_dir.path_join("zone_hold.png"))
	_ride.bus.cadence = 106.0
	_ride._update_view()
	await _frames(4)
	_save_image(out_dir.path_join("zone_hold_above.png"))
	_ride.bus.cadence = _cadence
	while not _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	_ride._update_camera(0.0, true)
	await _frames(6)
	_save_image(out_dir.path_join("loot_beam.png"))
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("zone_hold_success.png"))
	_ride._finish_ride()  # wie „Fahrt beenden“; Spielstand nur im Speicher (save_path "")
	_ride.get_node("Hud/Message").modulate = Color.WHITE
	_ride._update_view()
	await _frames(8)
	_save_image(out_dir.path_join("arcade_result.png"))


## Durchbruch und Jagd (#47): Arcade-Lauf mit nur dieser Herausforderung, Fahrer kurz hinter dem Start/Ziel. Die Zugbrücke
## zu (Balken leer), halb und offen; der Verfolger auf den Fersen, aus der Nähe von vorn und der Seite, abgehängt.
func _prop_shots(out_dir: String) -> void:
	var length: float = _ride.track.length_m()
	_place(5.0)
	_ride.ride_mode = SaveGame.MODE_ARCADE
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(length, 0.0, 0)
	_ride.stats = RideStats.new()
	var sections := ArcadeRun.sections_from_stations(_ride.track.ride_stations(), length)
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, 3, [Encounters.find("durchbruch_bruecke")])
	_ride.hud.end_celebration()
	_ride._update_view()
	_ride._update_camera(0.0, true)
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	var block: Breakthrough = _ride.arcade.active["block"]
	_ride.bus.cadence = 90.0
	# Weiterfahren, bis die Brücke fest steht und etwa 22 m voraus liegt.
	while _ride.arcade_bridge.ride_m - _ride.model.distance_m > 22.0 or not _ride.arcade_gate_placement.locked:
		await _ride_arcade(0.25, false)
	await _ride_arcade(0.1)
	_save_image(out_dir.path_join("bridge_closed.png"))
	await _bridge_close(out_dir, "closed")
	block.level = 0.5
	await _ride_arcade(0.1, false)
	await _wait_bridge()
	_save_image(out_dir.path_join("bridge_half.png"))
	await _bridge_close(out_dir, "half")
	block.level = 0.999
	_ride.bus.cadence = 114.0
	await _ride_arcade(0.5, false)
	await _wait_bridge()
	_save_image(out_dir.path_join("bridge_open.png"))
	await _bridge_close(out_dir, "open")
	# Jagd.
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, _ride.model.distance_m, 3,
			[Encounters.find("jagd_verfolger")])
	_ride.bus.cadence = 90.0
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	var chase: Chase = _ride.arcade.active["block"]
	chase.gap = 0.04
	await _ride_arcade(0.3, true)
	for i in range(40):
		await _ride_arcade(0.05, false)
		chase.gap = 0.04
		await _frames(3)
	_save_image(out_dir.path_join("pursuer_close.png"))
	_ride.set_process(false)
	var pursuer: Pursuer = _ride.arcade_pursuer
	var at: Transform3D = pursuer.global_transform
	var camera: Camera3D = _ride.camera
	var views := {"front": at.origin - at.basis.z * 5.0 + at.basis.x * 2.0 + Vector3.UP * 1.8,
			"side": at.origin + at.basis.x * 5.0 + Vector3.UP * 1.4}
	for view in views:
		camera.global_position = views[view]
		camera.look_at(at.origin + Vector3.UP * 1.0, Vector3.UP)
		await _frames(4)
		_save(out_dir.path_join("pursuer_%s.png" % view))
	_ride.set_process(true)
	# Abgehängt: Abstand 1, er fällt zurück und verschwindet.
	chase.gap = 0.999
	_ride.bus.cadence = 100.0
	await _ride_arcade(0.5, false)
	for i in range(80):
		await _ride_arcade(0.05, false)
		await _frames(3)
	_save_image(out_dir.path_join("pursuer_gone.png"))


## Takt-Tore und Sammeln (#48): Arcade-Lauf mit nur dieser Herausforderung, Fahrer kurz hinter dem Start/Ziel. Die Tore
## voraus, getroffen (grün „Treffer“) und verpasst (orange „Verpasst“); die Sammelobjekte mit Magnetring bei hoher und
## niedriger Kadenz und aus der Nähe.
func _rhythm_shots(out_dir: String) -> void:
	var length: float = _ride.track.length_m()
	_place(5.0)
	_ride.ride_mode = SaveGame.MODE_ARCADE
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(length, 0.0, 0)
	_ride.stats = RideStats.new()
	var sections := ArcadeRun.sections_from_stations(_ride.track.ride_stations(), length)
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, 3, [Encounters.find("takt_ruhig")])
	_ride.hud.end_celebration()
	_ride.bus.cadence = 84.0  # in der Zone 74–94
	_ride._update_view()
	_ride._update_camera(0.0, true)
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	var gates: RhythmGates = _ride.arcade.active["block"]
	await _ride_arcade(3.0)
	_save_image(out_dir.path_join("rhythm_ahead.png"))
	while gates.state_of(0) == RhythmGates.PENDING:
		await _ride_arcade(0.25, false)
	await _ride_arcade(3.0)
	_save_image(out_dir.path_join("rhythm_hit.png"))
	_ride.bus.cadence = 105.0  # über der Zone: das nächste Tor wird verpasst
	while gates.state_of(1) == RhythmGates.PENDING and not gates.finished():
		await _ride_arcade(0.25, false)
	await _ride_arcade(2.5)
	_save_image(out_dir.path_join("rhythm_missed.png"))
	# Sammeln: hohe Kadenz, großer Ring.
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, _ride.model.distance_m, 3,
			[Encounters.find("sammeln_wiese")])
	_ride.bus.cadence = 108.0
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.5, false)
	var collect: Collect = _ride.arcade.active["block"]
	while collect.state_of(1) == Collect.PENDING:
		await _ride_arcade(0.25, false)
	await _ride_arcade(0.6)
	_save_image(out_dir.path_join("collect_high.png"))
	_ride.bus.cadence = 80.0
	await _ride_arcade(1.0)
	_save_image(out_dir.path_join("collect_low.png"))
	# Aus der Nähe: die Kamera seitlich über dem Fahrer, Objekte voraus (Kamera nur hier versetzt).
	_ride.bus.cadence = 108.0
	await _ride_arcade(1.0, false)
	_ride.set_process(false)
	var at: Transform3D = _ride.rider.global_transform
	var camera: Camera3D = _ride.camera
	camera.global_position = at.origin + at.basis.x * 5.0 + at.basis.z * 3.0 + Vector3.UP * 2.6
	camera.look_at(at.origin - at.basis.z * 6.0 + Vector3.UP * 0.8, Vector3.UP)
	await _frames(4)
	_save_image(out_dir.path_join("collect_close.png"))
	_ride.set_process(true)
	_ride._update_camera(0.0, true)


## Bosse (#51): je Boss ein Arcade-Lauf nur mit ihm an seinem festen Ort (Fahrer kurz vor dem Startpunkt); Kampfbeginn,
## Nahaufnahme, angeschlagen, besiegt bzw. entkommen. Die Kadenz folgt dem Ziel der laufenden Phase.
func _boss_shots(out_dir: String) -> void:
	var length: float = _ride.track.length_m()
	var sections := ArcadeRun.sections_from_stations(_ride.track.ride_stations(), length)
	_ride.ride_mode = SaveGame.MODE_ARCADE
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(length, 0.0, 0)
	_ride.stats = RideStats.new()
	_ride.hud.end_celebration()
	var bosses := preload("res://src/challenges/boss_challenges.gd")
	for definition in bosses.FIXED:
		var id: String = definition["id"]
		var section: Dictionary = sections.filter(func(s): return s["name"] == definition["section"])[0]
		_place(section["start_m"] + 10.0)
		_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, _ride.model.distance_m, 3, [], [definition])
		_ride.bus.cadence = 90.0
		_ride._update_view()
		_ride._update_camera(0.0, true)
		while _ride.arcade.active.is_empty():
			await _ride_arcade(0.25, false)
		var boss: BossFight = _ride.arcade.active["block"]
		await _boss_ride(boss, 2.0)
		await _frames(30)  # die Gestalt gleitet auf ihren Abstand
		_save_image(out_dir.path_join("boss_%s.png" % id))
		await _boss_close(out_dir, id)
		while boss.health() > 0.45 and not boss.finished():
			await _boss_ride(boss, 0.25, false)
		if id == "tramuntana":  # in der Böe: Windstreifen
			while not boss.current_phase() is Breakthrough and not boss.finished():
				await _boss_ride(boss, 0.25, false)
			await _boss_ride(boss, 1.0)
		await _frames(20)
		_save_image(out_dir.path_join("boss_%s_hurt.png" % id))
		if id == "dimonis":  # entkommen: ohne Treten entwischen sie
			_ride.bus.cadence = 0.0
			while not boss.finished():
				await _ride_arcade(0.25, false)
			_ride.bus.cadence = 60.0
			await _ride_arcade(0.3)
			await _frames(30)
			_save_image(out_dir.path_join("boss_dimonis_escape.png"))
		else:
			while not boss.finished():
				await _boss_ride(boss, 0.25, false)
			await _ride_arcade(0.1, false)
			await _frames(12)  # mitten im Zusammensinken
			_save_image(out_dir.path_join("boss_%s_defeated.png" % id))
		await _frames(240)  # Gestalt und Ergebnis des Kampfes laufen aus


## Arcade `seconds` lang mit der Kadenz, die das Ziel der laufenden Phase von `boss` trifft (Mitte der Zone, über einer
## Schwelle 4 rpm darüber).
func _boss_ride(boss: BossFight, seconds: float, settle: bool = true) -> void:
	var dt := 1.0 / 30.0
	for i in range(maxi(int(seconds / dt), 1)):
		if boss.finished():
			break
		var zone := boss.zone()
		var phase := boss.current_phase()
		_ride.bus.cadence = zone.x + 4.0 if phase is Breakthrough or phase is Chase else (zone.x + zone.y) / 2.0
		await _ride_arcade(dt, false, dt)
	if settle:
		_ride._update_camera(0.0, true)
		await _frames(8)


## Nahaufnahme der Gestalt schräg von vorn (Kamera nur hier versetzt).
func _boss_close(out_dir: String, id: String) -> void:
	_ride.set_process(false)
	var figure: BossFigure = _ride.arcade_stage.props["boss"].figure
	var at: Transform3D = (figure.get_node("Figure") as Node3D).global_transform
	var camera: Camera3D = _ride.camera
	var size: float = {"tramuntana": 7.0, "drac": 6.5}.get(id, 4.0)
	camera.global_position = at.origin - at.basis.z.normalized() * size * 2.0 + at.basis.x.normalized() * size \
			+ Vector3.UP * size * 0.6
	camera.look_at(at.origin + Vector3.UP * size * 0.25, Vector3.UP)
	await _frames(6)
	_save(out_dir.path_join("boss_%s_close.png" % id))
	_ride.set_process(true)
	_ride._update_camera(0.0, true)
	await _frames(4)


## Elite-Gruppen (#52): je Gruppe ein Arcade-Lauf nur mit ihr (erzwungen über den Pool); Ankündigung am Startpunkt, Kampf,
## bei den Seltenen das Gefolge; Wankelmütig mit wandernder Zone; die Standarte aus der Nähe.
func _elite_shots(out_dir: String) -> void:
	var length: float = _ride.track.length_m()
	var sections := ArcadeRun.sections_from_stations(_ride.track.ride_stations(), length)
	_ride.ride_mode = SaveGame.MODE_ARCADE
	_ride.laps = 0
	_ride.lap_timing = LapTiming.new(length, 0.0, 0)
	_ride.stats = RideStats.new()
	_ride.hud.end_celebration()
	_place(5.0)
	var groups := [["champion", "jagd_verfolger", ["windschnell", "gegenwind"], 104.0],
			["selten", "durchbruch_bruecke", ["gegenwind", "zaeh"], 116.0]]
	for entry in groups:
		var definition := EliteGroups.make(Encounters.find(entry[1]), entry[0], entry[2])
		_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, _ride.model.distance_m, 3, [definition], [])
		_ride.arcade_stage.start_gate.ride_m = NAN  # neuer Lauf ohne `begin`: Starttor und Schild neu
		_ride.arcade_stage.props["elite"].clear()
		_ride.bus.cadence = entry[3]
		_ride._update_view()
		_ride._update_camera(0.0, true)
		while _ride.arcade.next_challenge()["at_m"] - _ride.model.distance_m > 30.0:
			await _ride_arcade(0.25, false)
		await _ride_arcade(0.1)
		_save_image(out_dir.path_join("elite_%s_announce.png" % entry[0]))
		while _ride.arcade.active.is_empty():
			await _ride_arcade(0.25, false)
		var group: EliteGroup = _ride.arcade.active["block"]
		await _ride_arcade(3.0)
		_save_image(out_dir.path_join("elite_%s.png" % entry[0]))
		if entry[0] == "selten":
			while not group.in_retinue() and not group.finished():
				await _ride_arcade(0.25, false)
			await _ride_arcade(2.0)
			_save_image(out_dir.path_join("elite_selten_gefolge.png"))
			await _elite_close(out_dir)
		while not _ride.arcade.active.is_empty():
			await _ride_arcade(0.25, false)
		await _ride_arcade(5.0, false)
		_ride.hud.end_celebration()
		_ride.hud.clear_popups()
	# Wankelmütig: die Kadenz folgt der Mitte der wandernden Zone.
	var fickle := EliteGroups.make(Encounters.find("zone_mitte"), "champion", ["wankelmuetig"])
	_ride.arcade = ArcadeRun.new(1, CadenceRange.new(), sections, length, _ride.model.distance_m, 3, [fickle], [])
	_ride.bus.cadence = 90.0
	while _ride.arcade.active.is_empty():
		await _ride_arcade(0.25, false)
	var zone_group: EliteGroup = _ride.arcade.active["block"]
	for i in range(120):  # gut 4 s: eine Viertelschwingung, die Zone liegt 12 rpm höher
		var zone := zone_group.zone()
		_ride.bus.cadence = (zone.x + zone.y) / 2.0
		await _ride_arcade(1.0 / 30.0, false)
	_ride._update_camera(0.0, true)
	await _frames(8)
	_save_image(out_dir.path_join("elite_wankelmuetig.png"))


## Nahaufnahme der Elite-Standarte schräg von vorn (Kamera nur hier versetzt).
func _elite_close(out_dir: String) -> void:
	_ride.set_process(false)
	var banner: EliteBanner = _ride.arcade_stage.props["elite"].banner
	var at: Transform3D = banner.global_transform
	var camera: Camera3D = _ride.camera
	camera.global_position = at.origin + at.basis.z.normalized() * 9.0 - at.basis.x.normalized() * 3.0 + Vector3.UP * 4.0
	camera.look_at(at.origin + Vector3.UP * 5.0, Vector3.UP)
	await _frames(6)
	_save(out_dir.path_join("elite_banner_close.png"))
	_ride.set_process(true)
	_ride._update_camera(0.0, true)
	await _frames(4)


## Wartet, bis die Zugbrücke ihren Öffnungsgrad erreicht hat.
func _wait_bridge() -> void:
	for i in range(240):
		if is_equal_approx(_ride.arcade_bridge.open, _ride.arcade_bridge.target):
			break
		await _frames(2)
	await _frames(4)


## Nahaufnahme der Zugbrücke von vorn und schräg (Kamera nur hier versetzt).
func _bridge_close(out_dir: String, tag: String) -> void:
	_ride.set_process(false)
	var at: Transform3D = _ride.arcade_bridge.global_transform
	var camera: Camera3D = _ride.camera
	camera.global_position = at.origin + at.basis.z * 14.0 + at.basis.x * 5.0 + Vector3.UP * 2.8
	camera.look_at(at.origin + Vector3.UP * 3.0, Vector3.UP)
	await _frames(4)
	_save(out_dir.path_join("bridge_close_%s.png" % tag))
	_ride.set_process(true)
	_ride._update_camera(0.0, true)
	await _frames(4)


## Arcade `seconds` lang mit `_cadence` (Kadenz des Bus-Clients) und dem Tempo des Fahrmodells fahren – Strecke,
## Statistik, Lauf, Anzeige und Kamera wie im Spiel, ohne Bus; mit `settle` danach die Kamera ruhig dahinter.
func _ride_arcade(seconds: float, settle: bool = true, dt: float = 1.0 / 30.0) -> void:
	for i in range(maxi(int(seconds / dt), 1)):
		var before: float = _ride.model.distance_m
		_ride.model.step(_ride.bus.cadence, _ride.current_grade(), dt)
		_ride.stats.add(dt, _ride.bus.cadence, _ride.model.distance_m - before)
		_ride.lap_timing.advance(_ride.model.distance_m, dt)
		_ride.arcade_stage.advance(_ride.model.distance_m, dt)
		_ride._update_view()
		_ride._update_camera(dt)
	if settle:
		_ride._update_camera(0.0, true)
		await _frames(8)


func _save_image(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("SHOT %s window=%s+%s mode=%d camera=%s" % [path, DisplayServer.window_get_position(),
		DisplayServer.window_get_size(), DisplayServer.window_get_mode(), _ride.camera.global_position])


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png(path)
	if _crop.has_area() and path.get_file().begins_with("shot_"):
		image.get_region(_crop).save_png(path.get_base_dir().path_join(path.get_file().replace("shot_", "crop_")))
	print("SHOT %s station=%s crank=%.0f° lean=%.1f° bend=%.1f°" % [path, _ride.current_station(),
		rad_to_deg(_model.motion.crank_angle), rad_to_deg(_model.motion.lean), rad_to_deg(_model.motion.bend)])


## Bewegt das echte Modell `seconds` lang mit `_cadence` und dem passenden Tempo des Fahrmodells.
func _pedal(seconds: float, dt: float = 1.0 / 60.0) -> void:
	var grade: float = _ride.current_grade()
	var speed: float = _ride.model.target_speed_mps(_cadence, grade)
	for i in range(maxi(int(seconds / dt), 1)):
		_model.update(_cadence, speed, grade, _ride.current_curvature(), false, dt)


## Nahaufnahmen von der Seite (rechts) und schräg von hinten links; die Kamera der Hauptszene ruht so lange.
func _close_ups(out_dir: String, d: float) -> void:
	_ride.set_process(false)
	var at: Transform3D = _ride.rider.global_transform
	var camera: Camera3D = _ride.camera
	var views := {
		"side": at.origin + at.basis.x * 3.2 + Vector3.UP * 1.0,
		"rear": at.origin + at.basis.z * 2.6 - at.basis.x * 1.6 + Vector3.UP * 1.7,
	}
	for view in views:
		camera.global_position = views[view]
		camera.look_at(at.origin + Vector3.UP * 0.75, Vector3.UP)
		await _frames(4)
		_save(out_dir.path_join("close_%d_%s.png" % [int(d), view]))
	_ride.set_process(true)
	_place(d)


## Je Tierart das erste Tier (Herdentiere zuerst) aus der Nähe, Blick von der Straßenseite; zweites Bild 2,5 s
## Tieranimation später. Fahrer und Kamera der Hauptszene ruhen so lange.
func _fauna_shots(out_dir: String) -> void:
	var fauna: IslandFauna = _ride.world.fauna
	var track: Track = _ride.track
	fauna.set_process(false)
	for kind in IslandFauna.KINDS:
		var all := fauna.positions(kind)
		if all.is_empty():
			continue
		var target: Vector3 = all[0]
		var d := track.curve.get_closest_offset(target)
		_place(track.path_distance(d))
		await _frames(4)
		_ride.set_process(false)
		var road := track.position_at(d)
		var towards := Vector3(road.x - target.x, 0.0, road.z - target.z).normalized()
		var distance: float = {"Schafe": 6.0, "Ziegen": 6.0, "Esel": 4.5, "Katzen": 2.2, "Delfine": 12.0, "Fische": 3.5,
				"Geier": 9.0, "Schmetterlinge": 1.0, "Eidechsen": 0.9}[kind]
		var small: bool = kind in ["Schmetterlinge", "Eidechsen"]
		var camera: Camera3D = _ride.camera
		var eye := target + towards * distance + Vector3.UP * (0.9 if kind == "Katzen" else 0.4 if small else 1.8)
		eye.y = maxf(eye.y, _ride.world.terrain.height_at(eye.x, eye.z) + 0.8)
		# Springende Tiere (#41): erstes Bild im Sprung, zweites 0,25 s später; sonst 2,5 s Tieranimation dazwischen.
		var t := 2.0
		var leaping: bool = kind in ["Delfine", "Fische"]
		fauna.apply(t, fauna.rider_path_m)
		while leaping and fauna.positions(kind)[0].y < 0.2 and t < 30.0:
			t += 0.05
			fauna.apply(t, fauna.rider_path_m)
		for suffix in ["", "_b"]:
			fauna.apply(t if suffix.is_empty() else t + (0.25 if leaping else 2.5), fauna.rider_path_m)
			var now: Vector3 = fauna.positions(kind)[0]
			if small and suffix.is_empty():
				eye = now + towards * distance + Vector3.UP * 0.4
			camera.global_position = eye
			camera.look_at(now + Vector3.UP * (0.15 if kind == "Katzen" else 0.0 if small or leaping else 0.6), Vector3.UP)
			await _frames(4)
			_save(out_dir.path_join("fauna_%s%s.png" % [kind, suffix]))
		_ride.set_process(true)
	fauna.set_process(true)


## Fahrer an Position `d`, Kamera sofort dahinter. Mit `--hud`: Tempo des Fahrmodells, Strecke und Zeit bis hier
## (Beispiel: Ø 22 km/h); mit `--laps` in Runde 2 nach einer Beispielrunde mit neuer Bestzeit.
func _place(d: float) -> void:
	_ride.model.distance_m = d
	if _hud:
		_ride.model.speed_mps = _ride.model.target_speed_mps(_cadence, _ride.current_grade())
		_ride.stats.distance_m = d
		_ride.stats.ride_time_s = d / (22.0 / 3.6)
	if _hud and _laps >= 0:
		var lap: float = _ride.track.length_m()
		_ride.lap_timing = LapTiming.new(lap, 0.0, _laps, LAP_SAMPLES_S[0])
		_ride.lap_timing.advance(lap, LAP_SAMPLES_S[2])
		_ride.lap_timing.advance(lap + d, d / (22.0 / 3.6))
		_ride.model.distance_m = lap + d
		_ride.stats.ride_time_s += LAP_SAMPLES_S[2]
		_ride.stats.distance_m += lap
		_ride.hud.celebrate("Neue Bestzeit!  %s" % _ride.format_time(LAP_SAMPLES_S[2], true))
	if not is_nan(_ghost_s):
		if not (_hud and _laps >= 0):  # sonst steht die Rundenwertung schon in Runde 2 bei `d`
			_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 1)
			_ride.lap_timing.advance(d, d / (22.0 / 3.6))
		_ride.ghost = _sample_ghost(22.0 / 3.6)
		_ride.ghost_rider.visible = true
	_ride._update_view()
	_ride._update_camera(0.0, true)


## Beispiel-Ghost mit festem Tempo `mps`, gegen den ein Fahrer mit demselben Tempo `_ghost_s` Sekunden zurückliegt.
func _sample_ghost(mps: float) -> Ghost:
	var lap: float = _ride.track.length_m()
	var ghost := Ghost.new(lap)
	if _ghost_s >= 0.0:
		ghost.record(mps * (1.0 + _ghost_s), 1.0)  # vorweg: in der ersten Sekunde den Vorsprung herausgefahren
	else:
		ghost.record(0.0, -_ghost_s)  # zurück: steht so lange an der Linie
	ghost.finish(lap / mps - _ghost_s)
	return ghost


## Ergebnis einer Rundfahrt über `--laps` Runden (endlos: drei Runden, dann „Fahrt beenden“) mit Beispielzeiten.
func _result_shot(out_dir: String) -> void:
	var lap: float = _ride.track.length_m()
	var count := _laps if _laps > 0 else 3
	_ride.lap_timing = LapTiming.new(lap, 0.0, _laps, LAP_SAMPLES_S[0], _ride.track.segments)
	_ride.stats = RideStats.new()
	for i in range(count):
		var t: float = LAP_SAMPLES_S[1 + i % (LAP_SAMPLES_S.size() - 1)]
		_ride.lap_timing.advance(lap * (i + 1), t)
		_ride.stats.add(t, 86.0, lap)
	_ride.model.distance_m = lap * count
	_ride._finish_ride()  # wie im Spiel: Einblendung aus, Spielstand nur im Speicher (save_path "")
	_ride.get_node("Hud/Message").modulate = Color.WHITE
	_ride._update_view()
	_ride._update_camera(0.0, true)
	await _frames(8)
	_save_image(out_dir.path_join("result.png"))


## Je Segment: Fahrer bei 40 % des Segments (HUD mit Live-Zeit), dann 15 m hinter dem Ende (Ergebnis beim
## Verlassen). Beispielfahrt: das Segment in knapp der Silber-Zeit, vorher 22 km/h.
func _segment_shots(out_dir: String) -> void:
	var celebration: Control = _ride.hud.get_node("%Celebration")
	for segment in _ride.track.segments:
		var start: float = segment["start_m"]
		var length: float = segment["end_m"] - start
		var inside_mps: float = length / (_ride.medal_limits[segment["id"]][Medals.SILVER] - 1.0)
		var timing := LapTiming.new(_ride.track.length_m(), 0.0, 0, INF, _ride.track.segments)
		timing.advance(start, start / (22.0 / 3.6))
		timing.advance(start + 0.4 * length, 0.4 * length / inside_mps)
		_place(start + 0.4 * length)  # setzt mit `--laps` eine eigene Rundenwertung – danach ersetzen
		_ride.lap_timing = timing
		_ride.model.distance_m = start + 0.4 * length
		celebration.hide()
		_ride._update_view()
		_pedal(1.0)
		await _frames(8)
		_save_image(out_dir.path_join("segment_%s.png" % segment["id"]))
		timing.advance(segment["end_m"], 0.6 * length / inside_mps)
		timing.advance(segment["end_m"] + 15.0, 15.0 / inside_mps)
		_place(segment["end_m"] + 15.0)
		_ride.lap_timing = timing
		_ride.model.distance_m = segment["end_m"] + 15.0
		_ride.hud.celebrate(_ride.segment_result_text(timing.segments.results[-1]))
		_ride._update_view()
		_ride._update_camera(0.0, true)
		_pedal(0.2)
		await _frames(8)
		_save_image(out_dir.path_join("segment_%s_result.png" % segment["id"]))


func _frames(count: int) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw


## Fährt von `from` bis `to` mit `speed` m/s (eigener Vorschub, das Fahrmodell steht ohne Bus) und misst die
## Frame-Zeiten. Die erste Sekunde (Aufwärmen) zählt nicht. Tempo-Effekte wie im Spiel bei diesem Tempo.
func _measure(from: float, to: float, speed: float) -> void:
	_place(from)
	_ride.speed_effects.hold_kmh = speed * 3.6
	if not is_nan(_ghost_s):  # Ghost im Tempo der Messfahrt; die Rundenwertung läuft mit, damit er mitfährt
		_ride.ghost = _sample_ghost(speed)
		_ride.lap_timing = LapTiming.new(_ride.track.length_m(), 0.0, 1)
		_ride.lap_timing.advance(from, from / speed)
	await _frames(30)
	var times := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	var d := from
	var warmup := 1.0
	while d < to:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		d += speed * dt
		_ride.model.distance_m = d
		if not is_nan(_ghost_s):
			_ride.lap_timing.advance(d, dt)
		var grade: float = _ride.current_grade()
		_model.update(_cadence, speed, grade, _ride.current_curvature(), false, dt)
		if warmup > 0.0:
			warmup -= dt
			continue
		times.append(dt)
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	var worst := sorted[sorted.size() - 1]
	var low_1 := sorted[int(sorted.size() * 0.99)]
	var slow := 0
	for t in times:
		if t > 1.0 / 50.0:
			slow += 1
	print("FPS from=%.0f to=%.0f speed_kmh=%.0f frames=%d mean=%.1f min=%.1f low1pct=%.1f below50=%d size=%s vsync=%s adapter=%s effects=%.2f" % [
		from, to, speed * 3.6, times.size(), times.size() / total, 1.0 / worst, 1.0 / low_1, slow,
		DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), RenderingServer.get_video_adapter_name(),
		_ride.speed_effects.strength])
