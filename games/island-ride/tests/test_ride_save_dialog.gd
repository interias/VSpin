## Dialog „Fahrt speichern“ (Spec #84) gegen den Fake-Bus: erscheint am Fahrtende mit Bridge (Rundfahrt, Training, Arcade),
## ohne Bridge nicht; Wahl des Upload-Schalters (Vorgabe nach Anmeldezustand, gemerkt in den Einstellungen); gesendetes
## `save_ride` (Felder, Bridge-Zeit, Spur, Runden, `upload`); Anzeige je Antwort (Erfolg, übersprungen, nicht angemeldet,
## gescheitert mit Datei, ohne Datei, keine Antwort); „Verwerfen“ sendet nichts; kein Doppelversand; Layout in 960×1040,
## 1920×1080 und 1152×648. Alle Dateien liegen unter TestIsolation.path, nie im echten `user://`.
extends "res://tests/support/bus_test.gd"

const DIALOG := preload("res://scenes/ride_save_dialog.gd")
const TRAINING_UNIT := "res://tests/fixtures/training_short.json"
const FIT_PATH := "C:\\Users\\fahrer\\git\\VSpin\\bridge\\sessions\\rides\\2026-10-28_18-04-12_20261028T180412Z-3fa91c0e.fit"
const LOGGED_IN := {"login": "logged_in"}
const NOT_LOGGED_IN := {"login": "not_logged_in"}
var SETTINGS_PATH := TestIsolation.path("test_ride_save_settings.cfg")


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


## Bus mit Status (und Anmeldezustand) und 30 s gleichmäßiger Kadenz.
func _bus(garmin: Dictionary = LOGGED_IN, cadence: float = 90.0) -> FakeBusServer:
	return start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {}, "", {}, {}, {}, garmin)]
			+ FakeBusServer.steady_cadence(cadence, 0.0, 30.0))


## Hauptszene mit Fahrt ohne Startmenü am Fake-Bus; `settings_path` "" = Einstellungen nur im Speicher.
func _spawn_game(bus: FakeBusServer, settings_path: String = "", start_m: float = 0.0) -> Node:
	var game := MAIN_SCENE.instantiate()
	game.config = config_for(bus)
	game.start_distance_m = start_m
	game.quit_on_request = false
	game.settings_path = settings_path  # vor `_ready`: das Einstellungsmenü liest sie dort
	game.save_path = ""  # nie den echten Spielstand lesen/schreiben
	game.start_in_menu = false  # sofort fahren, ohne Startmenü
	add_child_autofree(game)
	return game


func _ride_for(game: Node, seconds: float) -> void:
	assert_true(await run_until(func(): return game.state == "riding", 3.0), "Fahrt läuft")
	await run_for(seconds)


## Fahrt `seconds` lang, dann „Fahrt beenden“ aus den Einstellungen (ohne Ergebnis: der Dialog kommt sofort).
func _end_ride(game: Node, seconds: float = 3.5) -> void:
	await _ride_for(game, seconds)
	game.settings_menu.ride_end_requested.emit()


## Taste wie ein Spieler (Zeichen und physische Position, damit auch die `ui_*`-Aktionen der Oberfläche greifen).
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _saves(bus: FakeBusServer) -> Array:
	return bus.received_of_type("save_ride")


func _reply(ride_id: String, fit_path, fit_error, upload) -> Dictionary:
	return {"v": 0, "type": "ride_saved", "ride_id": ride_id, "fit_path": fit_path, "fit_error": fit_error,
			"upload": upload}


# --- erscheint -------------------------------------------------------------------------------------------------------

func test_dialog_appears_at_the_end_of_a_ride_with_a_bridge() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	assert_not_null(game.ride_save_dialog, "Dialog hängt in der Hauptszene")
	await _end_ride(game)
	var dialog: CanvasLayer = game.ride_save_dialog
	assert_true(dialog.visible, "Dialog nach „Fahrt beenden“")
	assert_eq(game.state, "saving", "Fahrt ohne Ergebnis: Zustand saving, das Fahrmodell steht")
	assert_eq(dialog.state, "ask")
	assert_eq(game.save_game.rides().size(), 1, "die Fahrt steht schon im Spielstand, der Dialog ändert daran nichts")
	assert_true(dialog.buttons["save"].has_focus(), "Fokus auf „Speichern“")
	assert_false(game.message_label.visible, "keine Ergebniszeile hinter dem Dialog")
	assert_string_contains(dialog.labels["summary"].text, "Fahrzeit 0:0", "Fahrzeit der Fahrt")
	var before: float = game.model.distance_m
	await run_for(0.5)
	assert_eq(game.model.distance_m, before, "während des Dialogs wird nicht weitergefahren")
	await _press(KEY_P)
	assert_eq(game.state, "saving", "Pause-Taste ändert nichts")
	assert_true(_saves(bus).is_empty(), "gefragt, nichts gesendet")


func test_no_dialog_without_a_bus() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _ride_for(game, 2.5)
	bus.stop()
	assert_true(await run_until(func(): return not game.bus.bus_connected, 3.0), "Bus weg")
	assert_gt(game.stats.ride_time_s, 0.0, "es wurde gefahren")
	game.settings_menu.ride_end_requested.emit()
	assert_false(game.ride_save_dialog.visible, "ohne Bridge kein Dialog")
	assert_eq(game.state, "menu", "direkt ins Menü wie bisher")
	assert_eq(game.save_game.rides().size(), 1, "Spielstand wie bisher")


func test_no_dialog_without_telemetry_time_of_the_ride() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {}, "", {}, {}, {}, LOGGED_IN)])
	var game := _spawn_game(bus)
	assert_true(await run_until(func(): return game.bus.bus_connected, 3.0))
	assert_eq(game.bus.last_telemetry_t_ms, -1, "keine Telemetrie")
	game.stats.add(5.0, 80.0, 40.0)  # Fahrzeit da, aber keine Bridge-Zeit der Fahrt
	game.settings_menu.ride_end_requested.emit()
	assert_false(game.ride_save_dialog.visible, "ohne Telemetrie-Zeit kein Dialog")
	assert_eq(game.state, "menu")


func test_no_dialog_without_ride_time() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	assert_true(await run_until(func(): return game.bus.last_telemetry_t_ms >= 0, 3.0))
	game.stats = RideStats.new()  # die ersten Bilder haben schon gefahren: Fahrzeit 0 wie vor dem Start
	game.return_to_menu()
	assert_false(game.ride_save_dialog.visible, "Fahrzeit 0: kein Dialog")
	assert_eq(game.state, "menu")


func test_finished_ride_shows_the_result_first_and_enter_opens_the_dialog() -> void:
	var track: GrayboxTrack = autofree(GrayboxTrack.new())
	var bus := _bus()
	var game := _spawn_game(bus, "", track.length_m() - 30.0)  # kurz vor der Ziellinie, eine Runde
	assert_true(await run_until(func(): return game.state == "finished", 12.0), "Ziel erreicht")
	assert_false(game.ride_save_dialog.visible, "erst das Ergebnis")
	assert_string_contains(game.status_message(), "Ziel erreicht")
	assert_true(game.message_label.visible, "Ergebnis steht im HUD")
	await _press(KEY_ENTER)
	assert_true(game.ride_save_dialog.visible, "Enter → Dialog")
	assert_eq(game.state, "finished", "der Zustand bleibt finished")
	assert_false(game.message_label.visible, "Ergebniszeile tritt hinter den Dialog zurück")
	assert_eq(game.ride_trace.lap_end_t_ms.size(), 1, "die volle Runde steht in der Spur")
	assert_eq(game.ride_trace.lap_end_t_ms[0], game.ride_trace.end_t_ms, "Rundenende = Ziel")
	game.return_to_menu()
	assert_true(game.ride_save_dialog.visible, "Menü-Aufruf bei offenem Dialog ändert nichts")
	assert_eq(game.state, "finished")
	game.ride_save_dialog.discard()
	assert_eq(game.state, "menu")
	assert_eq(game.save_game.rides().size(), 1, "nicht doppelt gespeichert")


func test_dialog_also_comes_in_training_and_arcade() -> void:
	for mode in [SaveGame.MODE_TRAINING, SaveGame.MODE_ARCADE]:
		var game := _spawn_game(_bus())
		assert_true(await run_until(func(): return game.bus.last_telemetry_t_ms >= 0, 3.0))
		if mode == SaveGame.MODE_TRAINING:
			game.start_ride(mode, 0, "", Training.load_file(TRAINING_UNIT))
		else:
			game.start_ride(mode, 0, "", {}, Track.DIRECTION_CW, 1)
		await _ride_for(game, 3.0)
		game.return_to_menu()
		assert_eq(game.state, "finished", "%s: erst das Ergebnis" % mode)
		assert_false(game.ride_save_dialog.visible, "%s: noch kein Dialog" % mode)
		game.return_to_menu()
		assert_true(game.ride_save_dialog.visible, "%s: dann der Dialog" % mode)
		game.ride_save_dialog.discard()
		assert_eq(game.state, "menu", "%s: danach das Menü" % mode)


func test_dialog_comes_once_per_ride_and_each_ride_has_its_own_id() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game)
	var first: String = game.ride_trace.ride_id
	game.ride_save_dialog.discard()
	assert_eq(game.state, "menu")
	game.start_ride()
	assert_ne(game.ride_trace.ride_id, first, "neue Fahrt, neue ride_id")
	assert_true(await run_until(func(): return game.state == "riding", 3.0))
	await run_for(2.5)
	game.return_to_menu()
	assert_true(game.ride_save_dialog.visible, "die nächste Fahrt fragt wieder")


# --- Schalter ----------------------------------------------------------------------------------------------------------

func test_switch_default_follows_the_login_state() -> void:
	var cases := [[LOGGED_IN, true], [NOT_LOGGED_IN, false], [{"login": "unavailable"}, false], [{}, false]]
	for entry in cases:
		var game := _spawn_game(_bus(entry[0]))
		await _end_ride(game, 1.5)
		assert_eq(game.ride_save_dialog.upload_check.button_pressed, entry[1], "Vorgabe bei %s" % [entry[0]])
		game.ride_save_dialog.discard()
		game.queue_free()


func test_switch_choice_is_remembered_across_a_restart() -> void:
	var game := _spawn_game(_bus(LOGGED_IN), SETTINGS_PATH)
	await _end_ride(game, 1.5)
	var check: CheckBox = game.ride_save_dialog.upload_check
	assert_true(check.button_pressed, "angemeldet: an")
	check.button_pressed = false  # wie ein Klick
	assert_true(FileAccess.file_exists(SETTINGS_PATH), "Wahl liegt in der Einstellungsdatei")
	assert_eq(GraphicsSettings.load_file(SETTINGS_PATH).garmin_upload, false, "neue Settings-Instanz liest sie")
	game.ride_save_dialog.discard()
	game.queue_free()
	var restarted := _spawn_game(_bus(LOGGED_IN), SETTINGS_PATH)
	await _end_ride(restarted, 1.5)
	assert_false(restarted.ride_save_dialog.upload_check.button_pressed, "nach dem Neustart bleibt es aus, obwohl angemeldet")
	restarted.ride_save_dialog.upload_check.button_pressed = true
	assert_eq(GraphicsSettings.load_file(SETTINGS_PATH).garmin_upload, true, "und lässt sich wieder umlegen")


func test_remembered_choice_survives_other_settings_writes() -> void:
	var settings := GraphicsSettings.new()
	settings.garmin_upload = false
	settings.save_file(SETTINGS_PATH)
	var devices := HeartRateDevices.new()
	devices.remember("strap", "F1:2A:33:44:55:66", "HRM 600")
	devices.save_file(SETTINGS_PATH)
	var loaded := GraphicsSettings.load_file(SETTINGS_PATH)
	assert_eq(loaded.garmin_upload, false, "Gurt merken lässt die Wahl stehen")
	loaded.aa = GraphicsSettings.AA_FXAA
	loaded.save_file(SETTINGS_PATH)
	assert_eq(HeartRateDevices.load_file(SETTINGS_PATH).device("strap")["name"], "HRM 600", "Grafik speichern lässt die Geräte stehen")
	assert_null(GraphicsSettings.new().garmin_upload, "nie gewählt = null")


# --- gesendetes save_ride ------------------------------------------------------------------------------------------------

func test_save_sends_ride_with_bridge_time_and_a_strictly_rising_trace() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game, 3.5)
	var dialog: CanvasLayer = game.ride_save_dialog
	await _press(KEY_ENTER)  # Fokus liegt auf „Speichern“
	assert_eq(dialog.state, "saving", "Enter speichert")
	await run_until(func(): return not _saves(bus).is_empty(), 2.0)
	assert_eq(_saves(bus).size(), 1)
	var message: Dictionary = _saves(bus)[0]["message"]
	assert_eq(message["v"], 0.0)
	assert_eq(message["ride_id"], game.ride_trace.ride_id)
	assert_true(RideTrace.is_valid_id(message["ride_id"]))
	assert_true(message["upload"], "angemeldet: Upload an")
	var start: float = message["start_t_ms"]
	var end: float = message["end_t_ms"]
	assert_eq(start, floorf(start), "ganze Zahl")
	assert_eq(fmod(start, 250.0), 0.0, "Beginn in Bridge-Zeit (Telemetrie-Takt), nicht in Spielzeit")
	assert_gt(end, start, "Ende nach dem Beginn")
	assert_lte(end, float(game.bus.last_telemetry_t_ms), "Ende nicht nach der Bridge-Zeit")
	assert_eq(message["lap_end_t_ms"], [], "keine volle Runde")
	var trace: Array = message["distance"]
	assert_gte(trace.size(), 3, "etwa 1 Hz über 3 s")
	assert_eq(trace[0], [start, 0.0], "die Spur beginnt beim Beginn mit 0 m")
	assert_eq(trace[-1][0], end, "und endet beim Ende")
	for i in range(1, trace.size()):
		assert_gt(trace[i][0], trace[i - 1][0], "t_ms streng steigend")
		assert_true(trace[i][1] >= trace[i - 1][1], "Meter fallen nie")
	assert_gt(trace[-1][1], 0.0, "es wurde Strecke gefahren")
	assert_almost_eq(trace[-1][1], game.stats.distance_m, 0.06, "Meter wie in der Zusammenfassung")


func test_switch_off_sends_upload_false_and_pauses_stay_in_the_trace() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _ride_for(game, 1.5)
	await _press(KEY_P)  # manuelle Pause: Telemetrie läuft weiter
	assert_eq(game.state, "paused_manual")
	await run_for(2.2)
	var standing: float = game.stats.distance_m
	game.settings_menu.ride_end_requested.emit()
	assert_eq(game.state, "saving")
	game.ride_save_dialog.upload_check.button_pressed = false
	game.ride_save_dialog.buttons["save"].pressed.emit()
	await run_until(func(): return not _saves(bus).is_empty(), 2.0)
	var message: Dictionary = _saves(bus)[0]["message"]
	assert_false(message["upload"], "Schalter aus: upload false")
	var trace: Array = message["distance"]
	assert_almost_eq(trace[-1][1], standing, 0.06, "Strecke der Pause steht still")
	assert_eq(trace[-2][1], trace[-1][1], "Pause als Stillstand in der Spur")


func test_retry_sends_the_same_ride_id() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game)
	var dialog: CanvasLayer = game.ride_save_dialog
	dialog.buttons["save"].pressed.emit()
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, null, "FIT-Export nicht möglich: fit-tool fehlt", null))
	assert_eq(dialog.state, "done")
	dialog.buttons["save"].pressed.emit()
	await run_until(func(): return _saves(bus).size() == 2, 2.0)
	assert_eq(_saves(bus).size(), 2, "erneut speichern geht")
	assert_eq(_saves(bus)[0]["message"]["ride_id"], _saves(bus)[1]["message"]["ride_id"], "dieselbe Fahrt")
	assert_eq(_saves(bus)[0]["message"]["distance"], _saves(bus)[1]["message"]["distance"], "dieselben Angaben")


func test_full_wire_roundtrip_with_a_fake_bridge_reply() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game)
	bus.replies["save_ride"] = _reply(game.ride_trace.ride_id, FIT_PATH, null,
			{"state": "uploaded", "message": "Fahrt zu Garmin Connect hochgeladen."})
	game.ride_save_dialog.buttons["save"].pressed.emit()
	assert_true(await run_until(func(): return game.ride_save_dialog.state == "done", 3.0), "Antwort verarbeitet")
	assert_string_contains(game.ride_save_dialog.page_text(), "Fahrt zu Garmin Connect hochgeladen.")


# --- Verwerfen, Doppelversand --------------------------------------------------------------------------------------------

func test_discard_sends_nothing_and_leaves_the_game_save_alone() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game)
	var rides: Array = game.save_game.rides().duplicate(true)
	watch_signals(game.ride_save_dialog)
	game.ride_save_dialog.buttons["discard"].pressed.emit()
	await run_for(0.4)
	assert_signal_emitted(game.ride_save_dialog, "closed")
	assert_false(game.ride_save_dialog.visible)
	assert_eq(game.state, "menu", "weiter ins Menü")
	assert_true(_saves(bus).is_empty(), "Verwerfen sendet nichts")
	assert_eq(game.save_game.rides(), rides, "Spielstand unberührt")


func test_no_double_send_while_a_reply_is_pending() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game)
	var dialog: CanvasLayer = game.ride_save_dialog
	dialog.buttons["save"].pressed.emit()
	assert_true(dialog.buttons["save"].disabled, "Speichern gesperrt, solange die Antwort aussteht")
	assert_eq(dialog.buttons["save"].text, "Speichert …")
	assert_true(dialog.labels["status"].visible, "„speichert …“ sichtbar")
	assert_false(dialog.buttons["discard"].visible, "nicht verwerfen, während gespeichert wird")
	dialog.buttons["save"].pressed.emit()  # Doppelklick
	dialog.save()
	await run_for(0.5)
	assert_eq(_saves(bus).size(), 1, "genau ein save_ride")
	dialog.discard()
	assert_true(dialog.visible, "Verwerfen wirkt während des Speicherns nicht")


# --- Anzeige je Antwort --------------------------------------------------------------------------------------------------

## Dialog nach „Speichern“, wartend auf die Antwort.
func _saving(garmin: Dictionary = LOGGED_IN) -> Array:
	var game := _spawn_game(_bus(garmin))
	await _end_ride(game, 1.5)
	game.ride_save_dialog.buttons["save"].pressed.emit()
	assert_eq(game.ride_save_dialog.state, "saving")
	return [game, game.ride_save_dialog]


func test_result_uploaded_shows_path_import_way_and_the_bridge_message() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	var dialog: CanvasLayer = parts[1]
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, FIT_PATH, null,
			{"state": "uploaded", "message": "Fahrt zu Garmin Connect hochgeladen."}))
	var text: String = dialog.page_text()
	assert_string_contains(text, "FIT-Datei gespeichert")
	assert_string_contains(text, FIT_PATH, "Ablageort der Datei")
	assert_string_contains(text, "Von Hand in Garmin Connect importieren (Web: „Importieren“)", "Importweg")
	assert_string_contains(text, "Fahrt zu Garmin Connect hochgeladen.", "Meldung der Bridge")
	assert_eq(dialog.state, "done")
	assert_false(dialog.buttons["save"].visible, "erledigt: kein „Erneut speichern“")
	assert_true(dialog.buttons["done"].visible)
	assert_true(dialog.buttons["done"].has_focus(), "Fokus auf „Weiter“")
	assert_false(dialog.labels["status"].visible, "„speichert …“ weg")
	dialog.buttons["done"].pressed.emit()
	assert_eq(game.state, "menu", "Weiter → Menü")


func test_result_skipped_shows_the_file_and_the_bridge_message() -> void:
	var parts := await _saving()
	parts[1].upload_check.button_pressed = false
	var game: Node = parts[0]
	var message := "Nicht hochgeladen – der Upload ist für diese Fahrt abgeschaltet."
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, FIT_PATH, null, {"state": "skipped", "message": message}))
	var text: String = parts[1].page_text()
	assert_string_contains(text, FIT_PATH)
	assert_string_contains(text, message)
	assert_true(parts[1].buttons["save"].visible, "übersprungen: nachträglich hochladen bleibt möglich")


func test_result_not_logged_in_names_the_login_command() -> void:
	var parts := await _saving(NOT_LOGGED_IN)
	var game: Node = parts[0]
	var message := "Nicht bei Garmin angemeldet – im Terminal anmelden: python -m vspin_bridge.garmin login"
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, FIT_PATH, null, {"state": "not_logged_in", "message": message}))
	var text: String = parts[1].page_text()
	assert_string_contains(text, message)
	assert_string_contains(text, FIT_PATH, "die Datei bleibt")
	assert_eq(parts[1].buttons["save"].text, "Erneut speichern")
	assert_true(parts[1].buttons["save"].visible)


func test_result_failed_upload_says_the_file_stays() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	var message := "Upload zu Garmin Connect gescheitert (Netzwerk). Die FIT-Datei bleibt für den manuellen Import liegen."
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, FIT_PATH, null, {"state": "failed", "message": message}))
	var text: String = parts[1].page_text()
	assert_string_contains(text, message, "Meldung der Bridge")
	assert_string_contains(text, FIT_PATH)
	assert_string_contains(text, "Von Hand in Garmin Connect importieren", "Importweg bei Fehlschlag")
	assert_true(parts[1].buttons["save"].visible and parts[1].buttons["done"].visible, "erneut speichern oder weiter")


func test_result_without_a_file_shows_the_reason() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	var reason := "FIT-Export nicht möglich: fit-tool fehlt (im Ordner bridge/: pip install -e \".[fit]\")"
	game.bus.ride_saved.emit(_reply(game.ride_trace.ride_id, null, reason, null))
	var text: String = parts[1].page_text()
	assert_string_contains(text, "Keine FIT-Datei geschrieben")
	assert_string_contains(text, reason)
	assert_string_contains(text, "Hochgeladen wurde nichts")
	assert_false(text.contains("Importieren"), "ohne Datei kein Importweg")
	assert_true(parts[1].buttons["save"].visible, "erneut speichern, nachdem fit-tool installiert ist")


func test_reply_for_another_ride_is_ignored() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	game.bus.ride_saved.emit(_reply("anderer-lauf", FIT_PATH, null, null))
	assert_eq(parts[1].state, "saving", "wartet weiter auf die eigene Fahrt")


func test_bridge_rejection_is_shown_at_once() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	game.bus.ride_rejected.emit("distance: t_ms nicht steigend")
	assert_eq(parts[1].state, "done", "keine 60 s warten")
	assert_string_contains(parts[1].page_text(), "Die Bridge hat die Fahrt abgelehnt: distance: t_ms nicht steigend")
	assert_true(parts[1].buttons["done"].visible, "Weg zurück ins Menü")


func test_no_reply_gives_a_message_and_a_way_back() -> void:
	var parts := await _saving()
	var game: Node = parts[0]
	var dialog: CanvasLayer = parts[1]
	dialog.reply_timeout_s = 0.4
	assert_true(await run_until(func(): return dialog.state == "done", 3.0), "nach der Wartezeit geht es weiter")
	var text: String = dialog.page_text()
	assert_string_contains(text, "nicht geantwortet", "verständliche Meldung")
	assert_string_contains(text, "sessions/rides/", "wo die Datei läge")
	assert_true(dialog.buttons["done"].visible and dialog.buttons["save"].visible, "weiter oder erneut speichern")
	dialog.buttons["done"].pressed.emit()
	assert_eq(game.state, "menu", "zurück ins Menü")


func test_losing_the_bus_while_saving_ends_the_wait() -> void:
	var bus := _bus()
	var game := _spawn_game(bus)
	await _end_ride(game, 1.5)
	var dialog: CanvasLayer = game.ride_save_dialog
	dialog.buttons["save"].pressed.emit()
	bus.stop()
	assert_true(await run_until(func(): return dialog.state == "done", 3.0), "Bus weg: nicht 60 s warten")
	assert_string_contains(dialog.page_text(), "Verbindung zur Bridge ist abgebrochen")
	assert_true(dialog.buttons["done"].visible)


# --- Anmeldezustand ----------------------------------------------------------------------------------------------------

func test_login_texts_per_state() -> void:
	var ok: Dictionary = DIALOG.login_info(BusClient.GARMIN_LOGGED_IN)
	assert_eq(ok["text"], "Garmin Connect: angemeldet")
	assert_eq(ok["howto"], "", "angemeldet: nichts zu tun")
	var out: Dictionary = DIALOG.login_info(BusClient.GARMIN_NOT_LOGGED_IN)
	assert_string_contains(out["text"], "nicht angemeldet – so geht's")
	assert_string_contains(out["howto"], "python -m vspin_bridge.garmin login")
	assert_string_contains(out["howto"], "bridge/", "im Ordner bridge/")
	var missing: Dictionary = DIALOG.login_info(BusClient.GARMIN_UNAVAILABLE)
	assert_string_contains(missing["howto"], "pip install -e \".[garmin]\"")
	var unknown: Dictionary = DIALOG.login_info(BusClient.GARMIN_UNKNOWN)
	assert_string_contains(unknown["text"], "unbekannt")


func test_dialog_shows_the_login_state_and_follows_a_login_in_the_terminal() -> void:
	var bus := start_fake_bus([FakeBusServer.status("connected", "sim", ["CADENCE"], 0.0, {}, "", {}, {}, {}, NOT_LOGGED_IN),
			FakeBusServer.status("connected", "sim", ["CADENCE"], 2.5, {}, "", {}, {}, {}, LOGGED_IN)]
			+ FakeBusServer.steady_cadence(90.0, 0.0, 30.0))
	var game := _spawn_game(bus)
	await _end_ride(game, 1.2)
	var dialog: CanvasLayer = game.ride_save_dialog
	await run_for(0.1)
	assert_string_contains(dialog.page_text(), "nicht angemeldet – so geht's")
	assert_string_contains(dialog.page_text(), "python -m vspin_bridge.garmin login")
	assert_false(dialog.upload_check.button_pressed, "nicht angemeldet: Schalter aus")
	assert_true(await run_until(func(): return game.bus.garmin_login == "logged_in", 4.0), "Anmeldung im Terminal erkannt")
	await run_for(0.1)
	assert_string_contains(dialog.labels["login"].text, "angemeldet")
	assert_false(dialog.labels["howto"].visible, "Anleitung verschwindet")
	assert_false(dialog.upload_check.button_pressed, "der Schalter springt nicht unter den Fingern")


func test_older_bridge_without_the_block_shows_unknown() -> void:
	var bus := _bus({})
	var game := _spawn_game(bus)
	await _end_ride(game, 1.5)
	await run_for(0.1)
	assert_eq(game.bus.garmin_login, "unknown")
	assert_string_contains(game.ride_save_dialog.labels["login"].text, "Anmeldung unbekannt")


# --- Layout ------------------------------------------------------------------------------------------------------------

## Dialog in `viewport_size` (Pixel) im Zustand `state`: "ask" oder "done" mit dem längsten Ergebnis (nicht angemeldet:
## Anleitung, langer Pfad, Meldung des Uploads).
func _dialog_in(viewport_size: Vector2i, state: String) -> CanvasLayer:
	var bus := _bus(NOT_LOGGED_IN)
	var client := connect_client(bus)
	assert_true(await run_until(func(): return client.bus_connected and client.garmin_login != "unknown", 3.0))
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var trace := RideTrace.new()
	trace.sample(1000, 0.0, true)
	trace.sample(2000, 8.0, true)
	trace.finish(2500, 12.0)
	var dialog: CanvasLayer = DIALOG.new()
	viewport.add_child(dialog)
	dialog.open(client, trace, "Fahrzeit 1:23:45 · 31.2 km", GraphicsSettings.new(), "")
	if state == "done":
		dialog.buttons["save"].pressed.emit()
		client.ride_saved.emit(_reply(trace.ride_id, FIT_PATH, null, {"state": "not_logged_in",
				"message": "Nicht bei Garmin angemeldet – im Terminal anmelden: python -m vspin_bridge.garmin login"}))
	await wait_process_frames(4)
	return dialog


func _assert_inside(dialog: CanvasLayer, label: String) -> void:
	var panel: Rect2 = dialog.find_child("Panel", true, false).get_global_rect()
	var screen: Rect2 = dialog.get_node("Layout").get_viewport_rect()
	assert_true(screen.grow(0.5).encloses(panel), "%s: Inhalt im Fenster %s (%s)" % [label, screen, panel])
	assert_gt(panel.size.y, 200.0, "%s: Platz für den Inhalt" % label)
	var shown: Array[Rect2] = []
	for key in dialog.buttons:
		var button: Button = dialog.buttons[key]
		if not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		assert_true(screen.grow(0.5).encloses(rect), "%s: Knopf %s im Fenster (%s)" % [label, key, rect])
		assert_false(rect.intersects(panel), "%s: Knopf %s frei vom Inhalt" % [label, key])
		for other in shown:
			assert_false(rect.intersects(other), "%s: Knöpfe überdecken sich nicht" % label)
		shown.append(rect)
	var scroll: ScrollContainer = dialog.find_child("Scroll", true, false)
	var area := scroll.get_global_rect()
	for cell in scroll.find_children("*", "Control", true, false):
		if not cell.is_visible_in_tree() or not (cell is Label or cell is CheckBox):
			continue
		var rect: Rect2 = cell.get_global_rect()
		assert_true(rect.position.x >= area.position.x - 0.5 and rect.end.x <= area.end.x + 0.5,
				"%s: „%s“ seitlich im Inhalt (%s in %s)" % [label, str(cell.text).left(30), rect, area])
	var content: Control = scroll.get_node("Content")
	if content.size.y > area.size.y:
		var bar := scroll.get_v_scroll_bar()
		assert_true(bar.visible, "%s: zu lang → scrollt" % label)
		assert_almost_eq(bar.max_value, content.size.y, 1.0, "%s: alles erreichbar" % label)
	# Waagrecht untereinander, ohne Überdeckung: je zwei sichtbare Zeilen des Inhalts.
	var rows: Array[Rect2] = []
	for cell in content.get_children():
		if cell is Control and cell.visible:
			rows.append(cell.get_global_rect())
	for i in range(1, rows.size()):
		assert_lte(rows[i - 1].end.y, rows[i].position.y + 0.5, "%s: Zeile %d überdeckt die davor" % [label, i])


func test_layout_fits_low_window() -> void:
	var asking := await _dialog_in(Vector2i(1152, 648), "ask")
	_assert_inside(asking, "1152×648 fragen")
	var done := await _dialog_in(Vector2i(1152, 648), "done")
	_assert_inside(done, "1152×648 Ergebnis")


func test_layout_fits_half_screen_and_full_screen_windows() -> void:
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080)]:
		_assert_inside(await _dialog_in(size, "ask"), "%s fragen" % size)
		_assert_inside(await _dialog_in(size, "done"), "%s Ergebnis" % size)
