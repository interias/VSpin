## Ton (#44): Pegel je Klang aus Tempo, Kadenz, Ort, Wetter und Tageszeit (headless gibt es keinen Audio-Ausgang – geprüft
## werden Pegel und Auslösungen in RideSound, nicht Hörbares): Fahrtwind steigt mit dem Tempo, Freilauf nur bei Kadenz 0
## und Tempo > 0, Meer nur nahe der Küste, Regen nur bei Regen, Möwen nicht nachts, Schafglocken an den Herden-Knoten,
## Dorfglocke im Bergdorf. Dazu: standardmäßig leise, Lautstärke und Aus-Schalter in der rechten Spalte des
## Einstellungsmenüs, gespeichert und nach Neustart wirksam; ein Einblendungs-Klang je sichtbarer Einblendung; Ansage-Klang
## nur beim Erscheinen und beim Phasenwechsel; keine Wirkung auf das Fahrmodell (ADR-0010, Gegenprobe); alle Klänge
## prozedural erzeugt, das Spiel läuft ohne Audio-Gerät.
extends "res://tests/support/bus_test.gd"

var SETTINGS_PATH := TestIsolation.path("test_ride_sound_settings.cfg")
const DT := 0.1


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


## Hauptszene auf der Insel; Szene und Ton laufen nicht von selbst (Tests stellen Kamera und Zeit).
func _island(settings_path: String = "") -> Node:
	var bus := start_fake_bus([FakeBusServer.status()])
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	game.quit_on_request = false
	game.settings_path = settings_path
	game.save_path = ""
	game.start_in_menu = false
	add_child_autofree(game)
	game.set_process(false)
	game.sound.set_process(false)
	game.sound.build_all()
	game.sky.set_weather_mode(Weather.MODE_FIXED, Weather.CLEAR)
	game.sky.weather.snap()
	game.sky.set_time_mode(DayNight.MODE_FIXED, 12.0)
	return game


## Hörer (Kamera) nach `at` stellen und den Ton `seconds` lang in DT-Schritten laufen lassen.
func _listen(game: Node, at: Vector3, seconds: float = DT) -> void:
	game.camera.global_position = at
	game.sound.water_m = INF
	game.sound._water_wait = 0.0
	for i in range(maxi(roundi(seconds / DT), 1)):
		game.sound.update(DT)


func _station_of(world: IslandWorld, at: Vector3) -> String:
	return world.track.station_at(world.track.curve.get_closest_offset(at))["id"]


func _road_at(world: IslandWorld, station: String) -> Vector3:
	var span := world._station_range(station)
	return world.track.position_at((span.x + span.y) / 2.0) + Vector3.UP * 2.0


func test_wind_rises_with_speed_and_freewheel_ticks_only_when_coasting() -> void:
	var last := -1.0
	for kmh in [0.0, 5.0, 10.0, 20.0, 30.0, 45.0]:
		var wind: float = RideSound.levels({"riding": true, "speed_kmh": kmh, "cadence": 80.0})["wind"]
		if kmh > RideSound.WIND_KMH.x:
			assert_gt(wind, last, "Fahrtwind bei %d km/h lauter als langsamer" % kmh)
		last = wind
	assert_eq(RideSound.levels({"riding": true, "speed_kmh": 0.0})["wind"], 0.0, "im Stand kein Fahrtwind")
	assert_eq(last, 1.0, "voll ab %d km/h" % RideSound.WIND_KMH.y)
	assert_eq(RideSound.levels({"riding": false, "speed_kmh": 30.0})["wind"], 0.0, "nicht in Pause/Menü/Ziel")
	assert_gt(RideSound.levels({"riding": true, "speed_kmh": 25.0, "cadence": 0.0})["freewheel"], 0.0,
			"Freilauf: Kadenz 0, rollt")
	assert_eq(RideSound.levels({"riding": true, "speed_kmh": 25.0, "cadence": 70.0})["freewheel"], 0.0, "tritt")
	assert_eq(RideSound.levels({"riding": true, "speed_kmh": 0.0, "cadence": 0.0})["freewheel"], 0.0, "steht")
	assert_eq(RideSound.levels({"riding": false, "speed_kmh": 25.0, "cadence": 0.0})["freewheel"], 0.0, "Pause")
	assert_gt(RideSound.freewheel_pitch(40.0), RideSound.freewheel_pitch(10.0), "schneller rollen, schneller ticken")


## Fahrtwind vor #69, fest eingetragen (nicht aus dem neuen Code gerechnet): Grundpegel 0,45, Anstieg smoothstep(5, 45, km/h),
## Tonhöhe 0,8 … 1,35; Klang (normiert, 16 Bit): Effektivwert 0,2316, Anteil der Energie der Differenz benachbarter Samples
## (einfacher Hochpass) an der Gesamtenergie 0,5052.
const OLD_WIND_GAIN := 0.45
const OLD_WIND_RMS := 0.2316
const OLD_WIND_HIGHPASS := 0.5052
const OLD_WIND_PITCH := Vector2(0.8, 1.35)
## Fingerabdruck der übrigen Klänge vor #69 – unverändert; je Klang [Samples, Effektivwert, Hochpass-Anteil, Schwerpunkt
## der Energie in der Zeit 0..1]. Bewusst kein Hash der Sample-Bytes: Der hinge an der letzten Stelle von sin/exp der
## jeweiligen Laufzeit (Windows, Linux, Web) und kippte dort schon bei einem Sample um ein Bit. Die Länge gilt exakt, die
## Zahlen mit Toleranz (weit über jeder Plattformabweichung, weit unter einer Änderung an Teiltönen, Abklingen, Filtern
## oder Seed).
const OTHER_SOUND_PRINTS := {"sea": [66150, 0.21102, 0.01605, 0.47196], "rain": [44100, 0.22477, 2.11942, 0.51597],
		"freewheel": [1103, 0.06911, 1.14872, 0.01485], "sheep": [19845, 0.15703, 0.28592, 0.16946],
		"church": [38588, 0.13935, 0.03242, 0.23423], "gull": [19845, 0.36970, 0.35538, 0.40167],
		"click": [662, 0.23027, 0.07445, 0.14022], "chime": [15435, 0.26256, 0.19634, 0.30513],
		"announce": [11025, 0.31271, 0.06995, 0.26070]}
const FINGERPRINT_TOLERANCE := 0.0005


## Länge, Effektivwert, Hochpass-Anteil (Energie der Differenz benachbarter Samples / Gesamtenergie) und Schwerpunkt der
## Energie in der Zeit (0..1) eines Klangs.
func _sample_stats(id: String) -> Dictionary:
	var data := SoundSynth.build(id).data
	var energy := 0.0
	var diff := 0.0
	var centre := 0.0
	var prev := 0.0
	var count := data.size() / 2
	for i in range(count):
		var v := data.decode_s16(i * 2) / 32768.0
		energy += v * v
		diff += (v - prev) * (v - prev)
		centre += v * v * float(i) / count
		prev = v
	return {"count": count, "rms": sqrt(energy / count), "highpass": diff / energy, "centre": centre / energy}


func test_wind_is_clearly_quieter_than_before_at_the_same_speed() -> void:
	var rms: float = _sample_stats("wind")["rms"]
	for kmh in [10.0, 20.0, 30.0, 45.0]:
		var level: float = RideSound.levels({"riding": true, "speed_kmh": kmh, "cadence": 80.0})["wind"]
		var now := level * RideSound.GAIN["wind"] * rms
		var before := smoothstep(5.0, 45.0, kmh) * OLD_WIND_GAIN * OLD_WIND_RMS
		assert_lt(now, before * 0.5, "%d km/h: mindestens 6 dB leiser (%.4f statt %.4f)" % [kmh, now, before])
	var onset: float = RideSound.levels({"riding": true, "speed_kmh": 15.0})["wind"]
	assert_lt(onset, smoothstep(5.0, 45.0, 15.0), "sanfterer Anstieg: bei 15 km/h weniger vom Höchstpegel als früher")
	assert_lt(RideSound.WIND_PITCH.y, OLD_WIND_PITCH.y, "Tonhöhe steigt nicht so hoch")
	assert_lt(RideSound.WIND_PITCH.y - RideSound.WIND_PITCH.x, OLD_WIND_PITCH.y - OLD_WIND_PITCH.x, "… und weniger weit")


func test_wind_sample_has_no_harsh_highs() -> void:
	var stats := _sample_stats("wind")
	assert_lt(stats["highpass"], OLD_WIND_HIGHPASS * 0.3, "Höhenanteil höchstens 30 %% von früher (%.4f)" % stats["highpass"])
	assert_lt(stats["rms"], OLD_WIND_RMS, "Klang selbst nicht dichter als früher")


func test_other_sounds_are_unchanged_and_their_gains_unchanged() -> void:
	for id in OTHER_SOUND_PRINTS:
		var stats := _sample_stats(id)
		var expected: Array = OTHER_SOUND_PRINTS[id]
		assert_eq(stats["count"], expected[0], "%s: Länge unverändert" % id)
		assert_almost_eq(stats["rms"], expected[1], FINGERPRINT_TOLERANCE, "%s: Effektivwert unverändert" % id)
		assert_almost_eq(stats["highpass"], expected[2], FINGERPRINT_TOLERANCE, "%s: Höhenanteil unverändert" % id)
		assert_almost_eq(stats["centre"], expected[3], FINGERPRINT_TOLERANCE, "%s: Zeitverlauf unverändert" % id)
	var others := {"freewheel": 0.2, "sea": 0.4, "rain": 0.35, "gulls": 0.3, "sheep": 0.3, "church": 0.45, "click": 0.25,
			"chime": 0.3, "announce": 0.35}
	for key in others:
		assert_eq(RideSound.GAIN[key], others[key], "Grundpegel %s unverändert" % key)
	assert_eq(RideSound.GAIN.size(), others.size() + 1)
	var c := {"riding": true, "speed_kmh": 25.0, "cadence": 0.0, "water_m": 100.0, "rain": 0.5}
	assert_almost_eq(RideSound.levels(c)["freewheel"], lerpf(0.6, 1.0, smoothstep(1.0, 30.0, 25.0)), 0.0001)
	assert_almost_eq(RideSound.levels(c)["sea"], 1.0 - smoothstep(25.0, 220.0, 100.0), 0.0001)
	assert_eq(RideSound.levels(c)["rain"], 0.5)


func test_wind_volume_scales_only_the_wind_and_zero_is_off() -> void:
	var game := _island()
	var sound: RideSound = game.sound
	var player: AudioStreamPlayer = sound.players["wind"]
	game.state = game.STATE_RIDING
	game.model.speed_mps = 30.0 / 3.6
	var at: Vector3 = game.world.track.position_at(0.0) + Vector3.UP * 2.0
	_listen(game, at)
	assert_gt(sound.current["wind"], 0.3, "Fahrtwind bei 30 km/h")
	var full_db := player.volume_db
	assert_almost_eq(full_db, linear_to_db(sound.current["wind"] * RideSound.GAIN["wind"]), 0.01, "Regler voll: wie berechnet")
	var bus := AudioServer.get_bus_index(RideSound.BUS)
	sound.apply_settings(true, 0.3, 0.5)
	_listen(game, at)
	assert_almost_eq(player.volume_db, full_db + linear_to_db(0.5), 0.01, "halber Regler: halber Pegel, sofort")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.3), 0.01, "Gesamtlautstärke unberührt")
	sound.apply_settings(true, 0.3, 0.0)
	_listen(game, at)
	assert_false(player.playing, "Regler Aus: Fahrtwind still")
	assert_false(AudioServer.is_bus_mute(bus), "Ton insgesamt an")
	sound.apply_settings(true, 0.3, 1.0)
	_listen(game, at)
	assert_almost_eq(player.volume_db, full_db, 0.01, "wieder voll")


func test_wind_row_in_menu_applies_at_once_and_is_saved() -> void:
	var game := _island(SETTINGS_PATH)
	var menu: CanvasLayer = game.settings_menu
	var right: Node = menu.options["time"].get_parent()
	assert_eq(menu.options["wind_volume"].get_parent(), right, "neben Ton und Lautstärke")
	assert_eq(menu.options["wind_volume"].get_index(), menu.options["sound_volume"].get_index() + 2, "direkt unter der Lautstärke (Beschriftung + Auswahl)")
	var option: OptionButton = menu.options["wind_volume"]
	assert_eq(option.get_item_text(0), "Aus")
	assert_eq(option.get_item_text(option.item_count - 1), "100 %")
	assert_eq(option.get_item_text(option.selected), "100 %", "Standard voll")
	_choose(menu, "wind_volume", 0.5)
	assert_eq(game.sound.wind_volume, 0.5, "wirkt sofort")
	_choose(menu, "wind_volume", 0.0)
	assert_eq(game.sound.wind_volume, 0.0)
	assert_eq(GraphicsSettings.load_file(SETTINGS_PATH).wind_volume, 0.0, "gespeichert")
	remove_child(game)
	game.free()
	game = _island(SETTINGS_PATH)
	assert_eq(game.sound.wind_volume, 0.0, "nach Neustart wirksam")
	option = game.settings_menu.options["wind_volume"]
	assert_eq(option.get_item_text(option.selected), "Aus", "Menü zeigt den Stand")


func test_rain_only_when_it_rains() -> void:
	assert_eq(RideSound.levels({"rain": 0.0})["rain"], 0.0)
	assert_eq(RideSound.levels({"rain": 1.0})["rain"], 1.0)
	var game := _island()
	_listen(game, _road_at(game.world, "hain"))
	assert_eq(game.sound.current["rain"], 0.0, "klar: kein Regen")
	game.sky.set_weather_mode(Weather.MODE_FIXED, Weather.RAIN)
	game.sky.weather.snap()
	game.sky.apply_now()
	_listen(game, _road_at(game.world, "hain"))
	assert_eq(game.sound.current["rain"], 1.0, "Regen hörbar wie sichtbar")
	assert_eq(game.sound.plays.get("rain", 0), 1, "Regenschleife gestartet")


## Ortsabhängig: Meer an Hafen und Küste, nicht im Bergdorf; Möwen am Hafen bei Tag, nicht nachts; Schafglocken als
## Kind jedes Herden-Knotens und nur dort zu hören; Dorfglocke am Kirchturm im Bergdorf.
func test_sounds_follow_place_and_daylight() -> void:
	var game := _island()
	var world: IslandWorld = game.world
	var sound: RideSound = game.sound
	# Meer
	_listen(game, world.track.position_at(0.0) + Vector3.UP * 2.0)
	assert_gt(sound.current["sea"], 0.9, "Hafen: Meer laut (%.0f m bis zum Wasser)" % sound.water_m)
	_listen(game, _road_at(world, "kueste"))
	assert_gt(sound.current["sea"], 0.0, "Küstenstraße: Meer zu hören (%.0f m bis zum Wasser)" % sound.water_m)
	_listen(game, _road_at(world, "bergdorf"))
	assert_eq(sound.current["sea"], 0.0, "Bergdorf: kein Meer")
	assert_eq(sound.water_m, INF)
	# Möwen an den Schwärmen aus WorldMotion – Tag ja, Nacht nein
	var places := RideSound.gull_places(world.motion)
	assert_eq(places.size(), 3, "Hafen, Leuchtturm, Westküste")
	assert_eq(sound.gull_players.size(), places.size())
	var harbour_gulls: Vector3 = sound.gull_players[0].global_position
	_listen(game, harbour_gulls + Vector3.DOWN * 20.0, 10.0)
	assert_eq(sound.current["gulls"][0], 1.0, "am Schwarm laut")
	assert_gt(sound.plays.get("gulls", 0), 0, "Möwen rufen")
	assert_eq(_station_of(world, harbour_gulls), "hafen")
	game.sky.set_time_mode(DayNight.MODE_FIXED, 0.0)
	var calls: int = sound.plays["gulls"]
	_listen(game, harbour_gulls + Vector3.DOWN * 20.0, 10.0)
	assert_eq(sound.current["gulls"].max(), 0.0, "nachts keine Möwen")
	assert_eq(sound.plays["gulls"], calls, "nachts kein Ruf")
	game.sky.set_time_mode(DayNight.MODE_FIXED, 12.0)
	_listen(game, _road_at(world, "bergdorf"))
	assert_eq(sound.current["gulls"].max(), 0.0, "Bergdorf: keine Möwen")
	# Schafglocken an den Herden-Knoten
	var herds: Array = world.fauna.bell_herds
	assert_gt(herds.size(), 0)
	assert_eq(sound.sheep_players.size(), herds.size())
	for i in range(herds.size()):
		var bell: AudioStreamPlayer3D = herds[i]["node"].get_node("Schafglocke")
		assert_eq(sound.sheep_players[i], bell, "Kind von %s" % herds[i]["node"].get_path())
		assert_eq(bell.get_parent().get_parent().get_path(), world.get_node("Fauna/Glocken").get_path())
	_listen(game, herds[0]["centre"] + Vector3.UP * 2.0, 8.0)
	assert_eq(sound.current["sheep"][0], 1.0, "an der Herde")
	assert_gt(sound.plays.get("sheep", 0), 0, "Glocken bimmeln")
	_listen(game, world.track.position_at(0.0) + Vector3.UP * 2.0)
	assert_eq(sound.current["sheep"].max(), 0.0, "am Hafen keine Schafglocken")
	# Dorfglocke im Bergdorf
	var belfry := world.get_node("Props/bergdorf/Kirche/Glockenstuhl") as Node3D
	assert_eq(sound.church_player.get_parent(), belfry)
	assert_eq(_station_of(world, belfry.global_position), "bergdorf")
	assert_gt(belfry.global_position.y, world.terrain.height_at(belfry.global_position.x, belfry.global_position.z) + 10.0,
			"oben im Turm")
	_listen(game, _road_at(world, "hafen"), 20.0)
	assert_eq(sound.current["church"], 0.0, "am Hafen keine Dorfglocke")
	assert_eq(sound.plays.get("church", 0), 0)
	_listen(game, _road_at(world, "bergdorf"), 20.0)
	assert_eq(sound.current["church"], 1.0, "im Bergdorf voll")
	assert_eq(sound.plays.get("church", 0), RideSound.CHURCH_STRIKES, "ein Geläut, dann Pause")


func test_default_quiet_volume_and_off_saved_and_effective_after_restart() -> void:
	var defaults := GraphicsSettings.new()
	assert_true(defaults.sound_enabled, "Ton standardmäßig an …")
	assert_lte(defaults.sound_volume, 0.3, "… aber leise")
	for key in RideSound.GAIN:
		assert_lte(RideSound.GAIN[key], 0.5, "%s dezent" % key)
	var game := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	var bus := AudioServer.get_bus_index(RideSound.BUS)
	assert_gte(bus, 0, "eigener Bus")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(defaults.sound_volume), 0.01)
	assert_lte(AudioServer.get_bus_volume_db(bus), -10.0, "leise: höchstens −10 dB")
	assert_false(AudioServer.is_bus_mute(bus))
	assert_eq(game.sound.players["wind"].bus, RideSound.BUS)
	remove_child(game)
	game.free()
	# Menü: rechte Spalte, gespeichert, nach Neustart wirksam
	game = _island(SETTINGS_PATH)
	var menu: CanvasLayer = game.settings_menu
	var right: Node = menu.options["time"].get_parent()
	assert_eq(menu.options["sound"].get_parent(), right, "Ton in der rechten Spalte")
	assert_eq(menu.options["sound_volume"].get_parent(), right)
	assert_ne(right, menu.options["aa"].get_parent())
	assert_lt(menu.options["sound_volume"].get_index(), menu.options["window_mode"].get_index(), "vor den Fensterfeldern")
	_choose(menu, "sound_volume", 0.7)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.7), 0.01, "wirkt sofort")
	_choose(menu, "sound", false)
	assert_true(AudioServer.is_bus_mute(bus), "aus")
	assert_false(game.sound.enabled)
	var saved := GraphicsSettings.load_file(SETTINGS_PATH)
	assert_false(saved.sound_enabled, "gespeichert")
	assert_eq(saved.sound_volume, 0.7)
	remove_child(game)
	game.free()
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	game = _island(SETTINGS_PATH)
	assert_true(AudioServer.is_bus_mute(bus), "nach Neustart aus")
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.7), 0.01, "nach Neustart 70 %")
	_listen(game, game.world.track.position_at(0.0) + Vector3.UP * 2.0, 1.0)
	assert_eq(game.sound.plays.get("sea", 0), 0, "aus: nichts ausgelöst")
	game.settings_menu.open()
	var option: OptionButton = game.settings_menu.options["sound"]
	assert_eq(option.get_item_text(option.selected), "Aus", "Menü zeigt den Stand")
	_choose(game.settings_menu, "sound", true)
	assert_false(AudioServer.is_bus_mute(bus))
	_listen(game, game.world.track.position_at(0.0) + Vector3.UP * 2.0, 1.0)
	assert_eq(game.sound.plays.get("sea", 0), 1, "wieder an: Meer am Hafen")


func _choose(menu: CanvasLayer, key: String, value) -> void:
	var option: OptionButton = menu.options[key]
	option.select(option.get_meta("values").find(value))
	option.item_selected.emit(option.selected)


func test_ui_sounds_once_per_visible_celebration_and_announcement() -> void:
	var game := spawn_ride(start_fake_bus([FakeBusServer.status()]))
	var sound: RideSound = game.sound
	sound.build_all()
	game.hud.celebrate("Neue Bestzeit!")
	game.hud.celebrate("Erfolg: Erste Runde")
	game.hud.celebrate("Fahrerlevel 2 erreicht!")
	assert_eq(sound.plays.get(RideSound.UI_CELEBRATION, 0), 1, "eine sichtbar, zwei eingereiht")
	game.hud._next_celebration()
	game.hud._next_celebration()
	assert_eq(sound.plays[RideSound.UI_CELEBRATION], 3, "je sichtbarer Einblendung einmal")
	game.hud._next_celebration()
	assert_eq(sound.plays[RideSound.UI_CELEBRATION], 3, "Warteschlange leer: kein Klang mehr")
	# Trainingsansage: beim Erscheinen und beim Phasenwechsel, nicht beim Countdown
	for step in [["", 0], ["In 10 s: Widerstand hoch", 0], ["In 9 s: Widerstand hoch", 0], ["In 1 s: Widerstand hoch", 0],
			["Widerstand hoch", 1], ["Widerstand hoch", 1], ["", 1], ["", 2], ["", -1]]:
		sound.announce(step[0], step[1])
	assert_eq(sound.plays.get(RideSound.UI_ANNOUNCEMENT, 0), 3, "Erscheinen, Wechsel 0→1, Wechsel 1→2")
	# Knopfdruck klickt
	var clicks: int = sound.plays.get(RideSound.UI_CLICK, 0)
	(game.settings_menu.find_child("Quit", true, false) as Button).pressed.emit()
	assert_eq(sound.plays.get(RideSound.UI_CLICK, 0), clicks + 1, "Knopf")


## Gegenprobe (ADR-0010): Mit lautem Fahrtwind fährt das Fahrmodell genau wie eines ohne Ton daneben.
func test_sound_does_not_touch_the_ride() -> void:
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 120.0))
	var game := spawn_ride(bus)
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "fährt")
	game.set_process(false)
	game.sound.set_process(false)
	game.sound.build_all()
	var reference := RideModel.new(game.config, game.model.distance_m)
	reference.speed_mps = game.model.speed_mps
	var drift := 0.0
	for i in range(600):
		game._ride(DT)
		game.sound.update(DT)
		reference.step(90.0, game.track.grade_at(reference.distance_m), DT)
		drift = maxf(drift, absf(game.model.distance_m - reference.distance_m))
	assert_gt(game.sound.current["wind"], 0.1, "Fahrtwind läuft")
	assert_eq(drift, 0.0, "Fahrmodell unverändert")


## Alle Klänge entstehen im Spiel (keine Dateien) und das Spiel läuft headless – ohne Audio-Gerät – mit Ton fehlerfrei.
func test_procedural_sounds_and_running_without_audio_device() -> void:
	for id in SoundSynth.IDS:
		var wav := SoundSynth.build(id)
		assert_not_null(wav, id)
		assert_gt(wav.data.size(), 400, "%s hat Inhalt" % id)
		assert_eq(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, SoundSynth.loops(id), "%s Schleife" % id)
		var peak := 0
		for k in range(0, wav.data.size(), 2):
			peak = maxi(peak, absi(wav.data.decode_s16(k)))
		assert_between(peak, 20000, 32767, "%s ausgesteuert, nicht übersteuert" % id)
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(start_fake_bus([FakeBusServer.status()]), RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND)
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = ""
	add_child_autofree(game)
	await run_for(1.5)
	assert_eq(game.state, "menu", "Titel mit Kameraflug")
	assert_true(game.sound.pending.is_empty(), "alle Klänge erzeugt, einer je Frame")
	for id in SoundSynth.IDS:
		assert_true(game.sound.streams[id] is AudioStreamWAV, id)
	assert_eq(game.sound.players["sea"].stream, game.sound.streams["sea"])
	assert_eq(game.sound.current["wind"], 0.0, "im Menü kein Fahrtwind")
