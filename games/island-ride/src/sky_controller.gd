## Tag/Nacht und Wetter (G6): stellt Sonne, Mond, Himmel, Environment, Lichter und die bewegte Welt nach der Uhr
## (DayNight: echte Ortszeit auf Mallorca, feste Stunde oder Zeitraffer) und dem simulierten Wetter (Weather).
## Von der Hauptszene in `_ready` angelegt (`setup(main)`), liest `[sky]` aus der Konfiguration.
##
## Die Lichtwerte rechnet `look(sun_elevation, weather, compatibility)` als reine Funktion; `_apply` setzt sie:
##   Sonne `Sun`     Richtung aus Höhe/Azimut, Farbe (Abendrot) und Energie, unter dem Horizont aus
##   Mond `Moon`     schwaches bläuliches Gegenlicht nachts (ohne Schatten, Stand vereinfacht gegenüber der Sonne)
##   Himmel/Env      Farben des ProceduralSky, Umgebungslicht, Nebel (Dunst/Regen), Belichtung, Sättigung
##   Welt            Wolkenbedeckung und -tönung, Wind, Meer, Leuchtturm, Vögel, nasse Straße (WorldMotion-Setter)
##   Lichter         Laternen, Leuchtfeuer, Fahrradlicht (NightLights) nachts und in der Dämmerung
##   Regen           Tropfen um die Kamera (GPU-Partikel; im Compatibility-Renderer CPU-Partikel), Sterne nachts
## Web-Export (Compatibility-Renderer): eigenes Lichtprofil (`COMPAT_*`) – dort wirkt `vertex_color_is_srgb` nicht
## und das Bild wäre mit den Forward+-Werten blass und überbelichtet. Weil vor allem die untexturierten Flächen
## (Vertex-Farben: Gelände, Straße, Landmarken; Einfarbig: Kai, Molen, Bogen) zu hell werden, Texturmodelle aber
## stimmen, tönt das Profil diese Materialien der Welt (`COMPAT_TINT`, Grundfarbe in Meta `profile_base`, Tönung in
## Meta `profile_tint`) und senkt das direkte Licht; Belichtung und Umgebungslicht bleiben fast gleich.
## Schnittstelle für Menüs: `set_time_mode(mode, hour)`, `set_weather_mode(mode, state)`.
class_name SkyController
extends Node

## Neu angewandt höchstens so oft (s); dazwischen nur, wenn die Sonne sich merklich bewegt hat oder das Wetter blendet.
const APPLY_INTERVAL_S := 0.25
const MIN_SUN_STEP_DEG := 0.05
## Lichter an, wenn die Sonne tiefer steht (Grad); bei dichter Bewölkung früher.
const LIGHTS_ON_DEG := 3.0
const LIGHTS_ON_OVERCAST_DEG := 7.0

## Tageswerte (Forward+, klar) = Stand aus G3 in `main.tscn`.
const SUN_COLOR_DAY := Color(1.0, 0.95, 0.86)
const SUN_COLOR_LOW := Color(1.0, 0.56, 0.3)
const SUN_ENERGY := 1.25
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY := 0.28
const SKY_TOP_DAY := Color(0.3, 0.52, 0.82)
const SKY_TOP_TWILIGHT := Color(0.17, 0.22, 0.42)
const SKY_TOP_NIGHT := Color(0.012, 0.02, 0.05)
const HORIZON_DAY := Color(0.7, 0.8, 0.88)
const HORIZON_SUNSET := Color(0.98, 0.6, 0.38)
const HORIZON_NIGHT := Color(0.07, 0.1, 0.17)
const GROUND_BOTTOM_DAY := Color(0.1, 0.26, 0.4)
const AMBIENT_DAY := Color(0.78, 0.76, 0.72)
const AMBIENT_NIGHT := Color(0.34, 0.4, 0.58)
const AMBIENT_NIGHT_ENERGY := 0.5
const FOG_DAY := Color(0.68, 0.78, 0.88)
const FOG_DENSITY := 0.00022
const SATURATION := 1.12
const SEA_DEEP := Color(0.03, 0.22, 0.42)
const SEA_SHALLOW := Color(0.12, 0.62, 0.66)
const SEA_FOAM := Color(0.95, 0.97, 0.98)
## Regen: Grau für Himmel, Wolken und Meer.
const RAIN_GREY := Color(0.52, 0.55, 0.58)
## Compatibility-Profil (Web): Faktoren auf Belichtung, Umgebungslicht, Sonne/Mond und Sättigung, dazu Kontrast.
const COMPAT_EXPOSURE := 0.92
const COMPAT_AMBIENT := 1.0
const COMPAT_SUN := 0.8
const COMPAT_SATURATION := 1.04
const COMPAT_CONTRAST := 1.04
const COMPAT_TINT := Color(0.78, 0.78, 0.78)

var clock: DayNight
var weather: Weather
## Compatibility-Renderer (Web)? Bestimmt das Lichtprofil; injizierbar über `set_compatibility`.
var compatibility := false
## Zuletzt angewandte Werte (`look`) und Sonnenstand (Höhe, Azimut in Grad).
var current: Dictionary = {}
var sun_angles := Vector2.ZERO

var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var camera: Camera3D
var world: IslandWorld
var lights: NightLights
var rain: GeometryInstance3D
var stars: MeshInstance3D

## Untexturierte Materialien der Welt (für COMPAT_TINT).
var _tinted: Array[StandardMaterial3D] = []
var _since_apply := INF
var _applied_sun := Vector2(INF, INF)


## Hängt sich an die Hauptszene `main` (WorldEnvironment, Sun, Camera, World, Fahrer) und stellt den Anfangszustand.
func setup(main: Node3D, compat: bool = is_compatibility_renderer()) -> void:
	name = "Sky"
	compatibility = compat
	var config: RideConfig = main.config
	clock = DayNight.new(config.sky_time_mode, config.sky_fixed_hour, config.sky_timelapse_day_min)
	weather = Weather.new(config.sky_weather_mode, config.sky_weather)
	environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	sky_material = environment.sky.sky_material as ProceduralSkyMaterial
	sun = main.get_node("Sun")
	camera = main.camera
	world = main.world
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = MOON_COLOR
	moon.light_angular_distance = 0.6
	moon.shadow_enabled = false
	moon.visible = false
	add_child(moon)
	lights = NightLights.new()
	add_child(lights)
	lights.setup(world, main.get_node_or_null("Track/Rider/Model/Lean/Bike"))
	_build_rain()
	_build_stars()
	if world != null:
		for node in world.find_children("*", "GeometryInstance3D", true, false):
			var material := (node as GeometryInstance3D).material_override as StandardMaterial3D
			if material != null and material.albedo_texture == null and material != world.motion.cloud_material \
					and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material not in _tinted:
				material.set_meta("profile_base", material.albedo_color)
				_tinted.append(material)
	apply_now()


## Läuft das Spiel im Compatibility-Renderer (Web-Export, `--rendering-method gl_compatibility`)?
static func is_compatibility_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Zeitmodus: DayNight.MODE_REALTIME (Echtzeit), MODE_FIXED (feste Ortszeit `hour`), MODE_TIMELAPSE (Zeitraffer,
## ab `hour` falls angegeben). Wirkt sofort.
func set_time_mode(mode: String, hour: float = NAN) -> void:
	clock.set_mode(mode, hour)
	apply_now()


## Wettermodus: Weather.MODE_CHANGING (wechselnd) oder MODE_FIXED; `state` (Weather.CLEAR, LIGHT_CLOUDS, OVERCAST,
## RAIN) blendet in Weather.MANUAL_TRANSITION_S über.
func set_weather_mode(mode: String, state: String = "") -> void:
	weather.set_mode(mode, state)
	apply_now()


## Lichtprofil umschalten (Tests, Fehlersuche).
func set_compatibility(value: bool) -> void:
	compatibility = value
	apply_now()


func _process(delta: float) -> void:
	clock.advance(delta)
	weather.advance(delta)
	_since_apply += delta
	if _since_apply >= APPLY_INTERVAL_S:
		var angles := clock.sun()
		if weather.changing() or absf(angles.x - _applied_sun.x) > MIN_SUN_STEP_DEG \
				or absf(angles.y - _applied_sun.y) > MIN_SUN_STEP_DEG:
			apply_now()
		else:
			_since_apply = 0.0
		if camera != null:
			lights.follow(camera.global_position)
	if camera != null:
		_follow_camera()


## Werte für die Sonnenhöhe `elevation` (Grad) und die Wetter-Kennwerte `w` ({cloud, haze, rain, wind}, siehe Weather)
## im Profil Forward+ oder Compatibility (`compat`). Reine Funktion.
static func look(elevation: float, w: Dictionary, compat: bool = false) -> Dictionary:
	var cloud: float = w["cloud"]
	var haze: float = w["haze"]
	var wet: float = w["rain"]
	var overcast := clampf((cloud - 0.45) / 0.45, 0.0, 1.0)  # 0 bis leicht bewölkt … 1 bedeckt
	var day := smoothstep(-2.0, 10.0, elevation)
	var lit := smoothstep(-9.0, 6.0, elevation)  # Umgebungslicht: bleibt in der Dämmerung länger hell
	var dusk := smoothstep(-12.0, -3.0, elevation)  # 0 = Nacht, 1 = ab bürgerlicher Dämmerung
	var night := 1.0 - dusk
	var low := (1.0 - smoothstep(3.0, 22.0, elevation)) * smoothstep(-5.0, 0.0, elevation)  # Abendrot
	var v := {}
	# Sonne und Mond
	var sun_energy := SUN_ENERGY * smoothstep(-1.5, 10.0, elevation) * (1.0 - 0.88 * overcast)
	v["sun_energy"] = sun_energy * (COMPAT_SUN if compat else 1.0)
	v["sun_color"] = SUN_COLOR_DAY.lerp(SUN_COLOR_LOW, low)
	v["moon_energy"] = MOON_ENERGY * night * (1.0 - 0.6 * overcast) * (COMPAT_SUN if compat else 1.0)
	# Himmel
	var grey := RAIN_GREY * lerpf(0.25, 1.0, dusk) * lerpf(0.35, 1.0, day)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_TWILIGHT, dusk).lerp(SKY_TOP_DAY, day)
	var horizon := HORIZON_NIGHT.lerp(HORIZON_SUNSET, smoothstep(-10.0, -2.0, elevation)).lerp(HORIZON_DAY, smoothstep(2.0, 16.0, elevation))
	v["sky_top"] = top.lerp(grey * 0.92, overcast * 0.95)
	v["sky_horizon"] = horizon.lerp(grey * 1.08, minf(overcast * 0.85 + haze * 0.2, 1.0))
	v["ground_bottom"] = GROUND_BOTTOM_DAY * lerpf(0.15, 1.0, dusk) * lerpf(1.0, 0.7, overcast)
	# Umgebungslicht: nachts bläulich und nicht schwarz (Strecke bleibt erkennbar)
	var ambient := AMBIENT_NIGHT.lerp(AMBIENT_DAY, lit).lerp(RAIN_GREY * 1.4, overcast * 0.5 * lit)
	v["ambient_color"] = ambient
	v["ambient_energy"] = lerpf(AMBIENT_NIGHT_ENERGY, 1.0 + 0.15 * overcast, lit) * (COMPAT_AMBIENT if compat else 1.0)
	v["ambient_sky"] = lerpf(0.15, 0.5, lit)
	# Nebel/Dunst: Regen dicht, nachts dunkel
	v["fog_color"] = horizon.lerp(FOG_DAY, day * (1.0 - low)).lerp(grey, maxf(overcast * 0.8, haze * 0.5))
	v["fog_density"] = FOG_DENSITY * (1.0 + 3.0 * haze + 5.0 * wet)
	v["fog_sun_scatter"] = 0.15 * (1.0 - overcast)
	v["exposure"] = lerpf(1.2, 1.0, day) * (COMPAT_EXPOSURE if compat else 1.0)
	v["saturation"] = SATURATION * (1.0 - 0.3 * wet - 0.12 * haze) * lerpf(0.85, 1.0, day) * (COMPAT_SATURATION if compat else 1.0)
	v["contrast"] = 1.04 * (COMPAT_CONTRAST if compat else 1.0)
	v["tint"] = COMPAT_TINT if compat else Color.WHITE
	# Welt
	var cloud_tint := Color.WHITE.lerp(Color(1.0, 0.78, 0.66), low).lerp(RAIN_GREY * 1.2, overcast * 0.8)
	v["cloud_tint"] = cloud_tint * lerpf(0.3, 1.0, dusk)
	v["cloud_rim"] = 0.4 * day
	v["sea_deep"] = SEA_DEEP.lerp(Color(0.1, 0.16, 0.2), wet * 0.8 + overcast * 0.2)
	v["sea_shallow"] = SEA_SHALLOW.lerp(Color(0.22, 0.36, 0.38), wet * 0.8 + overcast * 0.2)
	v["sea_foam"] = SEA_FOAM
	var lights_at := lerpf(LIGHTS_ON_DEG, LIGHTS_ON_OVERCAST_DEG, overcast)
	v["lights_on"] = elevation < lights_at
	v["beacon"] = 1.0 - smoothstep(lights_at - 6.0, lights_at, elevation)
	v["stars"] = night * (1.0 - overcast)
	v["birds"] = elevation > -2.0 and wet < 0.5
	v["rain"] = wet
	v["rain_color"] = Color(0.78, 0.82, 0.9) * lerpf(0.3, 1.0, lit)
	v["overcast"] = overcast
	v["wind"] = w["wind"]
	v["night"] = night
	return v


## Uhr und Wetter jetzt anwenden.
func apply_now() -> void:
	_since_apply = 0.0
	sun_angles = clock.sun()
	_applied_sun = sun_angles
	current = look(sun_angles.x, weather.params(), compatibility)
	_apply(current)


func _apply(v: Dictionary) -> void:
	var to_sun := DayNight.sun_direction(sun_angles.x, sun_angles.y)
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_energy = v["sun_energy"]
	sun.light_color = v["sun_color"]
	sun.visible = v["sun_energy"] > 0.001
	# Bei dichter Bewölkung keine Sonnen-/Mondscheibe am Himmel
	var disc := DirectionalLight3D.SKY_MODE_LIGHT_ONLY if v["overcast"] > 0.6 else DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	sun.sky_mode = disc
	moon.sky_mode = disc
	# Mond vereinfacht: gegenüber der Sonne, mindestens 25° hoch (Vollmond-Stand, keine Phasen)
	var to_moon := DayNight.sun_direction(clampf(-sun_angles.x, 25.0, 60.0), sun_angles.y + 180.0)
	moon.basis = Basis.looking_at(-to_moon, Vector3.UP)
	moon.light_energy = v["moon_energy"]
	moon.visible = v["moon_energy"] > 0.001
	sky_material.sky_top_color = v["sky_top"]
	sky_material.sky_horizon_color = v["sky_horizon"]
	sky_material.ground_horizon_color = v["sky_horizon"]
	sky_material.ground_bottom_color = v["ground_bottom"]
	environment.ambient_light_color = v["ambient_color"]
	environment.ambient_light_energy = v["ambient_energy"]
	environment.ambient_light_sky_contribution = v["ambient_sky"]
	environment.fog_light_color = v["fog_color"]
	environment.fog_density = v["fog_density"]
	environment.fog_sun_scatter = v["fog_sun_scatter"]
	environment.tonemap_exposure = v["exposure"]
	environment.adjustment_saturation = v["saturation"]
	environment.adjustment_contrast = v["contrast"]
	for material in _tinted:
		material.set_meta("profile_tint", v["tint"])
		material.albedo_color = material.get_meta("profile_base") * v["tint"]
	lights.set_on(v["lights_on"])
	if world != null:
		var motion := world.motion
		motion.set_clouds(weather.params()["cloud"], v["cloud_tint"], v["cloud_rim"])
		if not is_equal_approx(motion.wind, v["wind"]):
			motion.set_wind(v["wind"])
		motion.set_sea(v["sea_deep"], v["sea_shallow"], v["sea_foam"])
		motion.set_beacon(v["beacon"])
		motion.set_birds_visible(v["birds"])
		motion.set_road_wetness(v["rain"])
	rain.visible = v["rain"] > 0.05
	_set_emitting(v["rain"] > 0.05)
	var drops: Color = v["rain_color"]
	drops.a = 0.45 * v["rain"]
	(rain.material_override as StandardMaterial3D).albedo_color = drops
	stars.visible = v["stars"] > 0.02
	(stars.material_override as StandardMaterial3D).albedo_color.a = v["stars"]


## Regen und Sterne folgen der Kamera.
func _follow_camera() -> void:
	var at := camera.global_position
	if rain.visible:
		var ahead := -camera.global_basis.z * 12.0
		(rain as Node3D).global_position = at + Vector3(ahead.x, 14.0, ahead.z)
	if stars.visible:
		stars.global_position = at


## Regentropfen: dünne, zur Kamera gedrehte Striche fallen in einem Kasten über der Kamera (Weltkoordinaten).
## Forward+: GPUParticles3D; Compatibility (Web): CPUParticles3D mit weniger Tropfen.
func _build_rain() -> void:
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.7)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.albedo_color = Color(0.78, 0.82, 0.9, 0.45)
	material.disable_receive_shadows = true
	var box := Vector3(38.0, 7.0, 38.0)
	var fall := Vector3(0.12, -1.0, 0.05).normalized()
	if compatibility:
		var particles := CPUParticles3D.new()
		particles.amount = 1800
		particles.lifetime = 1.6
		particles.mesh = drop
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = box
		particles.direction = fall
		particles.spread = 2.0
		particles.gravity = Vector3.ZERO
		particles.initial_velocity_min = 15.0
		particles.initial_velocity_max = 18.0
		particles.local_coords = false
		rain = particles
	else:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = box
		process.direction = fall
		process.spread = 2.0
		process.gravity = Vector3.ZERO
		process.initial_velocity_min = 15.0
		process.initial_velocity_max = 18.0
		var particles := GPUParticles3D.new()
		particles.amount = 7000
		particles.lifetime = 1.6
		particles.draw_pass_1 = drop
		particles.process_material = process
		particles.local_coords = false
		particles.visibility_aabb = AABB(Vector3(-50.0, -40.0, -50.0), Vector3(100.0, 60.0, 100.0))
		rain = particles
	rain.name = "Regen"
	rain.material_override = material
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain.top_level = true
	rain.visible = false
	add_child(rain)
	_set_emitting(false)


func _set_emitting(value: bool) -> void:
	if rain.get("emitting") != value:
		rain.set("emitting", value)


## Sterne: Punkte auf der oberen Halbkugel (fester Zufall), ohne Nebel, Helligkeit über Alpha.
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1606
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for k in range(900):
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.04, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		points.append(dir * 4500.0)
		var b := rng.randf_range(0.45, 1.0)
		colors.append(Color(b, b, b * rng.randf_range(0.95, 1.1)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.use_point_size = true
	material.point_size = 2.0
	material.disable_fog = true
	stars = MeshInstance3D.new()
	stars.name = "Sterne"
	stars.mesh = mesh
	stars.material_override = material
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.top_level = true
	stars.visible = false
	add_child(stars)
