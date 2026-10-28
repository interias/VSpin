## Fahrtenbuch (#35) gegen den Fake-Bus: eine Fahrt löst einen Erfolg und einen Levelaufstieg mit Einblendung aus, beide
## stehen nach einem Neustart im Fahrtenbuch; das Fahrtenbuch zeigt alle Bereiche (Statistik, Bestzeiten,
## Segmentzeiten, Medaillen, Erfolge, letzte Fahrten), lässt sich mit Tastatur und Maus bedienen und passt ins
## Halbbild-Fenster wie ins Vollbild – was nicht passt, scrollt.
extends "res://tests/support/bus_test.gd"

const LOGBOOK := preload("res://scenes/logbook.gd")
var SAVE_PATH := TestIsolation.path("test_logbook_savegame.json")
## Schnelles Rad für den Durchstich (wie tests/test_round_trip.gd): eine Graybox-Runde in wenigen Sekunden.
const FAST_K := 10.0


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Hauptszene wie beim Spielstart (Startmenü) am Fake-Bus, mit Test-Spielstand; schnelles Rad ohne Trägheit.
func _spawn_game(bus: FakeBusServer) -> Node:
	var game := MAIN_SCENE.instantiate()
	var config := config_for(bus)
	config.inertia_s = 0.0
	config.k_kmh_per_rpm = FAST_K
	game.config = config
	game.quit_on_request = false
	game.settings_path = ""
	game.save_path = SAVE_PATH
	add_child_autofree(game)
	return game


## Zusammenfassung einer Fahrt über `km` am `date`.
func _ride(km: float, date: String = "2026-10-01T18:00:00Z", laps: int = 0, segments: Dictionary = {}) -> Dictionary:
	var stats := RideStats.new()
	stats.add(km * 150.0, 85.0, km * 1000.0)
	return SaveGame.ride_entry(SaveGame.MODE_ROUND_TRIP, RideConfig.TRACK_ISLAND, laps > 0, laps, stats, date, [],
			LapTiming.DIRECTION_CW, segments)


## Ein Stand mit allem, was das Fahrtenbuch zeigt; `rides` Fahrten.
func _full_save(rides: int = 30) -> SaveGame:
	var save := SaveGame.new()
	for i in range(rides):
		save.add_ride(_ride(9.21, "2026-09-%02dT18:00:00Z" % (1 + i % 28), 1,
				{"kuestenwelle": 234.6 + i, "bergwertung": 454.5, "dorfsprint": 49.4}))
	save.record_best_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, 884.7)
	save.record_best_time(RideConfig.TRACK_GRAYBOX, LapTiming.DIRECTION_CW, 61.2)
	save.record_segment_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "kuestenwelle", 192.4)
	save.record_segment_time(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "bergwertung", 455.2)
	save.record_medal(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, Medals.LAP, Medals.SILVER)
	save.record_medal(RideConfig.TRACK_ISLAND, LapTiming.DIRECTION_CW, "kuestenwelle", Medals.GOLD)
	save.unlock_achievement("night", "2026-09-12T21:30:00Z")
	save.unlock_achievement("rain", "2026-09-14T10:00:00Z")
	return save


func _one_ride_without_segments() -> SaveGame:
	var save := SaveGame.new()
	var old := _ride(3.0)
	old.erase("segment_times_s")  # Eintrag von vor der Nacharbeit
	save.add_ride(old)
	return save


func _logbook_text_has(logbook: CanvasLayer, page: String, text: String) -> bool:
	return logbook.page_text(page).contains(text)


## Fahrtenbuch in `viewport_size` (Pixel), geöffnet mit `save`.
func _logbook_in(viewport_size: Vector2i, save: SaveGame) -> CanvasLayer:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	add_child_autofree(viewport)
	var logbook: CanvasLayer = LOGBOOK.new()
	viewport.add_child(logbook)
	logbook.open(save)
	await wait_process_frames(4)
	return logbook


## Taste wie ein Spieler (Zeichen und physische Position, wie tests/test_start_menu.gd).
func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


## Mausklick in die Mitte eines Knopfs, direkt an dessen Viewport (wie tests/test_start_menu.gd).
func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	button.get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = at
		button.get_viewport().push_input(event, true)
		await get_tree().process_frame


## Alle Einblendungen, die gerade laufen oder eingereiht sind.
func _celebrations(game: Node) -> Array:
	return [game.hud.celebration()] + game.hud.queued_celebrations()


func test_logbook_shows_pulse_values_only_for_rides_with_pulse() -> void:
	# Story 18/19 (#64): Ø, Max und Zeit je Zone bei der Fahrt mit Puls; pulslose und alte Fahrten ohne Pulswerte.
	var pulse := HeartRateStats.new(HeartRateZones.new(170.0))
	pulse.add(1110.0, 140.0)  # Z2: 18:30
	pulse.add(250.0, 155.0)  # Z3: 4:10
	var save := SaveGame.new()
	save.add_ride(_ride(3.0, "2026-09-01T18:00:00Z"))
	save.add_ride({"date": "2026-09-02T18:00:00Z", "mode": "rundfahrt", "distance_km": 5.0, "duration_s": 600.0})
	var with_pulse := _ride(9.0, "2026-09-03T18:00:00Z")
	with_pulse.merge(SaveGame.pulse_fields(pulse))
	save.add_ride(with_pulse)
	var rides: String = (await _logbook_in(Vector2i(1920, 1080), save)).page_text("rides")
	assert_string_contains(rides, "Puls je Fahrt")
	assert_string_contains(rides, "03.09.2026: Ø Puls 143 · Max 155 bpm · Zonen: Z2 18:30 · Z3 4:10")
	assert_eq(rides.count("Ø Puls"), 1, "nur die Fahrt mit Puls")
	var without := SaveGame.new()
	without.add_ride(_ride(3.0))
	assert_false(_logbook_text_has(await _logbook_in(Vector2i(1920, 1080), without), "rides", "Puls"),
			"ohne Puls keine Pulswerte")


func test_ride_unlocks_achievement_and_level_and_both_survive_restart_in_logbook() -> void:
	# Vorher 9,8 km (Level 1, noch keine Erfolge): die Fahrt überschreitet 10 km gesamt.
	var before := SaveGame.new()
	before.add_ride(_ride(9.8))
	before.save_file(SAVE_PATH)
	var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(120.0, 0.0, 30.0))
	var game := _spawn_game(bus)
	await run_for(0.2)
	assert_eq(game.ride_level, 1)
	game.start_menu.buttons["drive"].pressed.emit()
	game.start_menu.buttons["round_trip"].pressed.emit()
	(game.start_menu.options["laps"] as OptionButton).select(game.start_menu.LAP_CHOICES.find(2))
	game.start_menu.buttons["start"].pressed.emit()
	assert_true(await run_until(func(): return game.ride_level == 2, 10.0), "Levelaufstieg bei 10 km gesamt")
	var shown := _celebrations(game)
	assert_has(shown, "Fahrerlevel 2 erreicht!", "Einblendung des Aufstiegs: %s" % [shown])
	assert_has(shown, "Erfolg: Eingerollt – 10 km gesamt", "Einblendung des Erfolgs: %s" % [shown])
	assert_has(shown, "Erfolg: Erster Kilometer – 1 km gefahren", "auch der erste Kilometer fällt jetzt")
	assert_eq(shown.filter(func(t): return t == "Fahrerlevel 2 erreicht!").size(), 1, "jede Einblendung einmal")
	assert_true(await run_until(func(): return game.state == "finished", 15.0), "Ziel nach zwei Runden")
	assert_string_contains(game.status_message(), "Fahrerlevel 2 erreicht", "Ergebnis nennt das neue Level")
	assert_string_contains(game.status_message(), "neue Erfolge", "Ergebnis nennt die neuen Erfolge")
	assert_true(game.save_game.achievements().has("km_10"))
	assert_true(game.save_game.achievements().has("laps_1"), "erste Runde")
	# Neustart: eine neue Hauptszene liest denselben Spielstand; das Fahrtenbuch zeigt Erfolg und Level.
	var restarted := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.1)
	restarted.start_menu.buttons["logbook"].pressed.emit()
	var logbook: CanvasLayer = restarted.logbook
	assert_true(logbook.visible, "Fahrtenbuch offen")
	assert_false(restarted.start_menu.visible, "Startmenü tritt zurück")
	var overview: String = logbook.page_text("overview")
	assert_string_contains(overview, "Fahrerlevel")
	assert_true(overview.contains("\n2 (noch"), "Level 2 im Fahrtenbuch: %s" % overview)
	assert_string_contains(overview, "Fahrten\n2", "zwei Fahrten")
	assert_string_contains(overview, "Runden\n2", "zwei volle Runden")
	var label: Label = logbook.pages["achievements"].find_child("km_10", true, false)
	assert_eq(label.modulate, Color.WHITE, "„Eingerollt“ freigeschaltet")
	assert_string_contains(logbook.page_text("achievements"),
			LOGBOOK.date_text(restarted.save_game.achievements()["km_10"]), "mit Datum")
	var locked: Label = logbook.pages["achievements"].find_child("km_1000", true, false)
	assert_ne(locked.modulate, Color.WHITE, "gesperrte blass")


func test_logbook_shows_all_areas() -> void:
	var logbook := await _logbook_in(Vector2i(1920, 1080), _full_save())
	var overview: String = logbook.page_text("overview")
	for text in ["Statistik", "Strecke\n276.3 km", "Zeit\n11 h 30 min", "Fahrten\n30", "Runden\n30", "Fahrerlevel",
			"Bestzeiten", "Insel-Rundkurs, im Uhrzeigersinn\n14:44.7", "Graybox, im Uhrzeigersinn\n1:01.2",
			"Segmentzeiten", "Küstenwelle\nInsel-Rundkurs, im Uhrzeigersinn\n3:12.4", "Bergwertung", "Medaillen",
			"Runde\nInsel-Rundkurs, im Uhrzeigersinn\nSilber", "Küstenwelle\nInsel-Rundkurs, im Uhrzeigersinn\nGold",
			"1× Gold · 1× Silber"]:
		assert_string_contains(overview, text)
	var achievements: String = logbook.page_text("achievements")
	assert_string_contains(achievements, "2 von %d Erfolgen freigeschaltet" % Achievements.LIST.size())
	for category in Achievements.CATEGORIES.values():
		assert_string_contains(achievements, category, "Kategorie %s" % category)
	assert_string_contains(achievements, "Nachtfahrt\nZwischen 22 und 5 Uhr gefahren\n12.09.2026", "mit Datum")
	assert_string_contains(achievements, "Mandelblüte\nIm Frühling gefahren\ngesperrt", "gesperrt")
	var rides: String = logbook.page_text("rides")
	assert_string_contains(rides, "Die letzten %d von 30 Fahrten" % LOGBOOK.RECENT_RIDES)
	var dates := []
	for label in logbook.pages["rides"].find_children("*", "Label", true, false):
		if label.text.ends_with(".2026"):
			dates.append(label.text)
	assert_eq(dates.size(), LOGBOOK.RECENT_RIDES, "nur die letzten Fahrten")
	assert_eq(dates[0], "02.09.2026", "neueste zuerst (Fahrt 30)")
	# Segmentzeiten je Fahrt (Nacharbeit #26): in Streckenreihenfolge, neueste Fahrt zuerst.
	assert_string_contains(rides, "Segmentzeiten je Fahrt")
	assert_string_contains(rides, "02.09.2026: Küstenwelle 4:23.6 · Bergwertung 7:34.5 · Dorfsprint 0:49.4")
	assert_false(_logbook_text_has(await _logbook_in(Vector2i(1920, 1080), _one_ride_without_segments()), "rides",
			"Segmentzeiten je Fahrt"), "ohne Segmente (Training, alte Einträge) kein Block")
	var empty := await _logbook_in(Vector2i(1920, 1080), SaveGame.new())
	assert_string_contains(empty.page_text("overview"), "noch keine", "leerer Stand: noch keine Bestzeiten")
	assert_string_contains(empty.page_text("rides"), "Noch keine Fahrten")


func test_keyboard_opens_pages_scrolls_and_closes() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	var save: SaveGame = game.save_game
	for i in range(30):
		save.add_ride(_ride(9.21, "2026-09-%02dT18:00:00Z" % (1 + i % 28), 1))
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.start_menu.buttons["drive"])
	await _press(KEY_DOWN)
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.start_menu.buttons["logbook"], "Fahrtenbuch wählbar")
	await _press(KEY_ENTER)
	var logbook: CanvasLayer = game.logbook
	assert_true(logbook.visible, "Enter öffnet das Fahrtenbuch")
	assert_eq(logbook.current_page(), "overview")
	assert_eq(game.get_viewport().gui_get_focus_owner(), logbook.buttons["overview"], "Fokus auf „Übersicht“")
	await _press(KEY_RIGHT)
	await _press(KEY_ENTER)
	assert_eq(logbook.current_page(), "achievements", "Pfeil rechts, Enter: Seite „Erfolge“")
	var scroll: ScrollContainer = logbook.pages["achievements"]
	await _press(KEY_DOWN)
	await get_tree().process_frame
	assert_gt(scroll.scroll_vertical, 0, "Pfeil runter scrollt")
	await _press(KEY_END)
	await get_tree().process_frame
	assert_gt(scroll.scroll_vertical, LOGBOOK.SCROLL_STEP_PX, "Ende: ganz nach unten")
	await _press(KEY_HOME)
	await get_tree().process_frame
	assert_eq(scroll.scroll_vertical, 0, "Pos1: ganz nach oben")
	assert_eq(game.get_viewport().gui_get_focus_owner(), logbook.buttons["achievements"], "Fokus bleibt in den Seiten")
	await _press(KEY_RIGHT)
	await _press(KEY_SPACE)
	assert_eq(logbook.current_page(), "rides", "Leertaste wählt auch")
	await _press(KEY_ESCAPE)
	assert_false(logbook.visible, "Esc schließt")
	assert_false(game.settings_menu.is_open(), "Esc öffnet dabei nicht die Einstellungen")
	assert_true(game.start_menu.visible, "zurück im Startmenü")
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.start_menu.buttons["logbook"], "Fokus auf „Fahrtenbuch“")
	assert_eq(game.state, "menu")


func test_settings_over_logbook_keep_their_keys() -> void:
	var game := _spawn_game(start_fake_bus([FakeBusServer.status()]))
	await run_for(0.2)
	game.open_logbook()
	await _press(KEY_F2)
	assert_true(game.settings_menu.is_open(), "F2 öffnet die Einstellungen über dem Fahrtenbuch")
	var first: Control = game.get_viewport().gui_get_focus_owner()
	await _press(KEY_DOWN)
	assert_ne(game.get_viewport().gui_get_focus_owner(), first, "Pfeil runter bewegt den Fokus in den Einstellungen")
	await _press(KEY_ESCAPE)
	await get_tree().process_frame
	assert_false(game.settings_menu.is_open(), "Esc schließt die Einstellungen")
	assert_true(game.logbook.visible, "das Fahrtenbuch bleibt offen")
	assert_eq(game.get_viewport().gui_get_focus_owner(), game.logbook.buttons["overview"], "Fokus zurück im Fahrtenbuch")


func test_mouse_selects_pages_and_back() -> void:
	var logbook := await _logbook_in(Vector2i(1600, 900), _full_save())
	watch_signals(logbook)
	await _click(logbook.buttons["achievements"])
	assert_eq(logbook.current_page(), "achievements", "Klick auf „Erfolge“")
	assert_true(logbook.pages["achievements"].is_visible_in_tree())
	assert_false(logbook.pages["overview"].is_visible_in_tree(), "eine Seite zur Zeit")
	await _click(logbook.buttons["rides"])
	assert_eq(logbook.current_page(), "rides")
	await _click(logbook.buttons["back"])
	assert_false(logbook.visible, "Zurück schließt")
	assert_signal_emitted(logbook, "closed")


## Alles außerhalb der Seiteninhalte liegt im Fenster und überlappt nicht; die Seiten scrollen statt abzuschneiden:
## kein Inhalt ragt seitlich über die Seite hinaus, und was nicht in die Höhe passt, erreicht der Scrollbalken.
func _assert_logbook_inside(logbook: CanvasLayer, label: String) -> void:
	var screen: Rect2 = logbook.get_node("Layout").get_viewport_rect()
	var checked := 0
	for control in logbook.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control.get_parent() is ScrollContainer \
				or control.get_parent().get_parent() is ScrollContainer or control is ScrollBar:
			continue
		if control.get_parent() is GridContainer or control.get_parent().name == "Content":
			continue  # Seiteninhalt: unten geprüft
		checked += 1
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()), "%s: %s liegt im Fenster %s (%s)" % [
				label, control.name, screen, control.get_global_rect()])
	assert_gt(checked, 6, "%s: alle Anzeigen geprüft" % label)
	var tabs: Rect2 = logbook.find_child("Tabs", true, false).get_global_rect()
	var panel: Rect2 = logbook.find_child("Panel", true, false).get_global_rect()
	assert_false(tabs.intersects(panel), "%s: Seitenknöpfe frei vom Inhalt" % label)
	assert_false(tabs.intersects(logbook.find_child("Title", true, false).get_global_rect()), "%s: frei vom Titel" % label)
	assert_gt(panel.size.y, 200.0, "%s: Platz für den Inhalt" % label)
	for page in logbook.PAGES:
		logbook.show_page(page)
		await wait_process_frames(2)
		var scroll: ScrollContainer = logbook.pages[page]
		var area := scroll.get_global_rect()
		for cell in scroll.find_children("*", "Label", true, false):
			var rect: Rect2 = cell.get_global_rect()
			assert_true(rect.position.x >= area.position.x - 0.5 and rect.end.x <= area.end.x + 0.5,
					"%s/%s: „%s“ seitlich in der Seite (%s in %s)" % [label, page, cell.text, rect, area])
		var content: Control = scroll.get_node("Content")
		if content.size.y > area.size.y:
			var bar := scroll.get_v_scroll_bar()
			assert_true(bar.visible, "%s/%s: zu lang → scrollt" % [label, page])
			assert_almost_eq(bar.max_value, content.size.y, 1.0, "%s/%s: alles erreichbar" % [label, page])


func test_layout_fits_half_screen_window() -> void:
	var logbook := await _logbook_in(Vector2i(960, 1040), _full_save())
	await _assert_logbook_inside(logbook, "960×1040")


func test_layout_fits_full_screen_sizes() -> void:
	await _assert_logbook_inside(await _logbook_in(Vector2i(1920, 1080), _full_save()), "1920×1080")
	var small := await _logbook_in(Vector2i(1152, 648), _full_save())
	await _assert_logbook_inside(small, "1152×648 (Godot-Standardfenster)")
	small.show_page("achievements")
	await wait_process_frames(2)
	assert_true(small.pages["achievements"].get_v_scroll_bar().visible, "1152×648: viele Erfolge → scrollt")
