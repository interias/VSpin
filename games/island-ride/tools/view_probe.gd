## Manuelle Sichtprüfung (#15): startet die Hauptszene gerendert (ohne `--headless`, ohne Bus), stellt den Fahrer
## an Streckenpositionen und speichert je ein Viewport-Bild; optional fährt sie einen Abschnitt mit festem Tempo ab
## und misst die Bildrate.
##   godot --path games/island-ride -s res://tools/view_probe.gd -- --out=C:/tmp/shots [--shots=0,200,450]
##         [--fps-from=0 --fps-to=2310 --speed-kmh=50] [--size=1920x1080] [--cadence=85] [--close] [--pair]
##         [--advance=1.5]
##         [--aa=msaa_4x] [--scale=1.0] [--upscaler=bilinear] [--vsync=off] [--hud] [--menu] [--crop=x,y,w,h]
## `--shots`: Streckenpositionen (m) für Screenshots (`shot_<m>.png` in `--out`). `--fps-from/--fps-to`: Fahrt mit
## `--speed-kmh` über diesen Abschnitt, danach eine Zeile mit min/Mittel/1-%-Tief der fps. Das HUD wird ausgeblendet
## (ohne Bridge stünde dort die Verbindungsmeldung) – außer mit `--hud`: dann zeigt es Beispielwerte (Kadenz wie
## `--cadence`, Tempo des Fahrmodells, Steigung und Abschnitt der Strecke, Strecke/Zeit bis zur Position, „~142 W“),
## die Verbindungsmeldung ist unsichtbar, dazu die Debug-Anzeige (F3). `--menu` öffnet das Grafikmenü. Grafik wie bei einem frischen Start (GraphicsSettings-Standard,
## `user://settings.cfg` bleibt unberührt); `--aa`/`--scale`/`--upscaler`/`--vsync=off` überschreiben. `--crop`:
## zusätzlich Bildausschnitt `crop_<m>.png` (z. B. für den AA-Vergleich). VSync wie im Projekt (Standard: an).
## Fahrer und Rad treten mit `--cadence` (rpm, 0 = Stillstand): die Hauptszene füttert ohne Bus nur eine Attrappe
## (sie steht in der Verbindungspause), die Probe bewegt das echte Modell. Vor jedem Screenshot 1 s Tritt.
## `--close`: zusätzlich Nahaufnahmen je Position (`close_<m>_side.png`, `close_<m>_rear.png`, Kamera nur hier
## versetzt). `--pair`: zweites Bild 0,15 s später (`shot_<m>_b.png`) – Kurbelstellung muss sich unterscheiden.
## `--advance`: im Bildpaar zusätzlich die Weltanimation (WorldMotion: Flügel, Vögel, Boote, Wolken) um so viele
## Sekunden vorrücken, damit die Bewegung im Vergleich sichtbar wird (Standard 0).
extends SceneTree

var _ride: Node3D
## Echtes Fahrer-/Radmodell in der Szene und Kadenz, mit der es tritt.
var _model: RiderModel
var _cadence := 85.0
## Bildausschnitt für `crop_<m>.png` (leer = keiner).
var _crop := Rect2i()
## HUD mit Beispielwerten zeigen (`--hud`).
var _hud := false


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
	var graphics := GraphicsSettings.new()
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
		elif arg == "--menu":
			menu = true
		elif arg.begins_with("--crop="):
			var p := value.split(",")
			_crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	DisplayServer.window_set_size(size)
	var config := RideConfig.load_file()
	config.track = RideConfig.TRACK_ISLAND
	_ride = load("res://scenes/main.tscn").instantiate()
	_ride.config = config
	_ride.settings_path = ""
	root.add_child(_ride)
	_ride.get_node("Hud").visible = _hud
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(10)
	_ride.settings_menu.settings = graphics  # erst nach `_ready` der Hauptszene vorhanden
	_ride.settings_menu.apply()
	_ride.debug_label.visible = _hud
	if menu:
		_ride.settings_menu.open()
	if _hud:
		# Beispielwerte: die Hauptszene zeigt Kadenz und Watt des (ohne Bridge nicht verbundenen) Bus-Clients an.
		_ride.get_node("Hud/Message").modulate = Color.TRANSPARENT
		_ride.bus.cadence = _cadence
		_ride.bus.last_telemetry = {"cadence": _cadence, "power_w": 142.0}
	_model = _ride.rider_model  # erst nach `_ready` der Hauptszene gesetzt
	var dummy := RiderModel.new()
	_ride.rider_model = dummy
	for d in shots:
		_place(d)
		_pedal(1.0)
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
	if fps_to > fps_from:
		await _measure(fps_from, fps_to, speed_kmh / 3.6)
	_ride.rider_model = _model  # die Hauptszene läuft bis zum Beenden noch einen Frame weiter
	dummy.free()
	quit(0)


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


## Fahrer an Position `d`, Kamera sofort dahinter. Mit `--hud`: Tempo des Fahrmodells, Strecke und Zeit bis hier
## (Beispiel: Ø 22 km/h).
func _place(d: float) -> void:
	_ride.model.distance_m = d
	if _hud:
		_ride.model.speed_mps = _ride.model.target_speed_mps(_cadence, _ride.current_grade())
		_ride.stats.distance_m = d
		_ride.stats.ride_time_s = d / (22.0 / 3.6)
	_ride._update_view()
	_ride._update_camera(0.0, true)


func _frames(count: int) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw


## Fährt von `from` bis `to` mit `speed` m/s (eigener Vorschub, das Fahrmodell steht ohne Bus) und misst die
## Frame-Zeiten. Die erste Sekunde (Aufwärmen) zählt nicht.
func _measure(from: float, to: float, speed: float) -> void:
	_place(from)
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
	print("FPS from=%.0f to=%.0f speed_kmh=%.0f frames=%d mean=%.1f min=%.1f low1pct=%.1f below50=%d size=%s vsync=%s adapter=%s" % [
		from, to, speed * 3.6, times.size(), times.size() / total, 1.0 / worst, 1.0 / low_1, slow,
		DisplayServer.window_get_size(), DisplayServer.window_get_vsync_mode(), RenderingServer.get_video_adapter_name()])
