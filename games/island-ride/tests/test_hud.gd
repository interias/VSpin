## Gestaltetes HUD (G5): Rechnungen für Höhenprofil, Minikarte und Rundenfortschritt als reine Funktionen,
## Anzeige der Werte (Vorzeichen und Farbe der Steigung, „~“ bei geschätzten Watt) und Layout – alle Anzeigen
## liegen im Fenster, auch im schmalen Halbbild (960×1040) und wie mit `stretch/mode="canvas_items"`.
extends GutTest

const HUD_SCENE := preload("res://scenes/hud.tscn")
const LONG_MESSAGE := "Verbindung verloren: Bridge nicht erreichbar (ws://127.0.0.1:8765)\n" \
		+ "Bridge starten: vspin-bridge --source sim\nNeuer Versuch läuft …\n(manuell pausiert)"


func _hud() -> RideHud:
	var hud: RideHud = HUD_SCENE.instantiate()
	add_child_autofree(hud)
	return hud


func _island_track() -> Track:
	var track := Track.new()
	IslandCourse.apply_to(track)
	add_child_autofree(track)
	return track


func test_profile_point_maps_distance_and_height_into_area() -> void:
	var area := Rect2(10, 20, 400, 100)
	assert_eq(HudProfile.profile_point(0.0, 3.0, 9000.0, 3.0, 223.0, area), Vector2(10, 120), "Start: links unten")
	assert_eq(HudProfile.profile_point(9000.0, 3.0, 9000.0, 3.0, 223.0, area).x, 410.0, "Rundenende: rechts")
	assert_almost_eq(HudProfile.profile_point(4500.0, 3.0, 9000.0, 3.0, 223.0, area).x, 210.0, 0.001, "Mitte")
	var top := HudProfile.profile_point(0.0, 223.0, 9000.0, 3.0, 223.0, area)
	assert_between(top.y, 20.0 + 5.0, 20.0 + 15.0, "höchster Punkt oben mit etwas Luft")
	assert_eq(HudProfile.profile_point(12000.0, 500.0, 9000.0, 3.0, 223.0, area), Vector2(410, 20), "begrenzt")


func test_profile_follows_track_heights_and_marker_moves() -> void:
	var track := _island_track()
	var hud := _hud()
	hud.setup(track)
	var profile: HudProfile = hud.get_node("%Profile")
	await wait_physics_frames(2)
	assert_almost_eq(profile.height_at(0.0), track.position_at(0.0).y, 0.5)
	var serpentines: float = track.stations[2]["start_m"] + 1000.0
	assert_almost_eq(profile.height_at(serpentines), track.position_at(serpentines).y, 1.0, "Höhe aus der Strecke")
	assert_almost_eq(profile.max_height_m, 223.0, 3.0, "Bergdorf ist der höchste Punkt")
	hud.show_lap(1000.0, 0.0, track.length_m(), 1000.0)
	var marker: Control = profile.get_child(1)
	var x1 := marker.position.x
	hud.show_lap(5000.0, 0.0, track.length_m(), 5000.0)
	assert_gt(marker.position.x, x1, "Marker wandert mit der Position nach rechts")
	var expected := profile.profile_point(5000.0, profile.height_at(5000.0), profile.length_m, profile.min_height_m,
			profile.max_height_m, profile.plot_rect())
	assert_almost_eq(marker.position.x + 6.0, expected.x, 1.0, "Marker an der Profilposition")


func test_map_point_fits_bounds_undistorted_north_up() -> void:
	var bounds := Rect2(-1000, -1500, 2000, 3000)
	var area := Vector2(200, 280)
	var top_left := HudMinimap.map_point(bounds.position, bounds, area, 6.0)
	var bottom_right := HudMinimap.map_point(bounds.end, bounds, area, 6.0)
	var map := Rect2(Vector2.ZERO, area).grow(0.01)
	assert_true(map.has_point(top_left) and map.has_point(bottom_right),
			"Ausschnitt passt in die Karte: %s %s" % [top_left, bottom_right])
	var span := bottom_right - top_left
	assert_almost_eq(span.y / span.x, 1.5, 0.001, "unverzerrt")
	assert_almost_eq(HudMinimap.map_point(bounds.get_center(), bounds, area, 6.0), area * 0.5, Vector2(0.01, 0.01), "mittig")
	assert_lt(HudMinimap.map_point(Vector2(0, -1000), bounds, area).y, HudMinimap.map_point(Vector2(0, 1000), bounds, area).y,
			"Norden (−z) oben")
	assert_lt(HudMinimap.map_point(Vector2(-500, 0), bounds, area).x, HudMinimap.map_point(Vector2(500, 0), bounds, area).x,
			"Osten rechts")


func test_rider_arrow_points_in_direction_of_travel() -> void:
	assert_almost_eq(HudMinimap.heading_rotation(Vector2(0, -1)), 0.0, 0.0001, "nach Norden: Spitze oben")
	assert_almost_eq(HudMinimap.heading_rotation(Vector2(1, 0)), PI / 2.0, 0.0001, "nach Osten: nach rechts gedreht")
	assert_almost_eq(absf(HudMinimap.heading_rotation(Vector2(0, 1))), PI, 0.0001, "nach Süden: Spitze unten")


func test_minimap_shows_rider_on_the_route() -> void:
	var track := _island_track()
	var hud := _hud()
	hud.setup(track)
	var map: HudMinimap = hud.get_node("%Minimap")
	await wait_physics_frames(2)
	var d := 3000.0
	hud.show_lap(d, 0.0, track.length_m(), d)
	var arrow: Control = map.get_child(0)
	var p := track.position_at(d)
	var expected := HudMinimap.map_point(Vector2(p.x, p.z), map.bounds, map.size)
	assert_almost_eq(arrow.position + arrow.pivot_offset, expected, Vector2(0.5, 0.5), "Pfeil an der Fahrerposition")
	assert_true(Rect2(Vector2.ZERO, map.size).has_point(expected), "auf der Karte")


func test_lap_progress_and_remaining_distance() -> void:
	assert_eq(RideHud.lap_progress(0.0, 0.0, 9000.0), 0.0)
	assert_almost_eq(RideHud.lap_progress(2250.0, 0.0, 9000.0), 0.25, 0.0001)
	assert_almost_eq(RideHud.lap_progress(9000.0 - 6.0, 9000.0 - 12.0, 9000.0), 0.5, 0.0001, "Start mitten auf der Strecke")
	assert_eq(RideHud.lap_progress(9500.0, 0.0, 9000.0), 1.0, "begrenzt")
	assert_eq(RideHud.lap_progress(100.0, 0.0, INF), 0.0, "ohne Ziel kein Fortschritt")
	assert_almost_eq(RideHud.remaining_m(2250.0, 9000.0), 6750.0, 0.001)
	assert_eq(RideHud.remaining_m(9100.0, 9000.0), 0.0, "nie negativ")


func test_shows_values_with_signed_colored_grade_and_estimated_watts() -> void:
	var hud := _hud()
	hud.show_ride(85.4, 27.46, 3030.0, "8:15", 0.066, "+6.6 %", "Serpentinen", "~142 W")
	hud.show_lap(3030.0, 0.0, 9210.0, 3030.0)
	var text := hud.readout()
	for expected in ["Kadenz: 85 rpm", "Tempo: 27.5 km/h", "Strecke: 3.03 km", "Zeit: 8:15", "Steigung: +6.6 %",
			"Abschnitt: Serpentinen", "Leistung: ~142 W", "Runde: 32 % (noch 6.18 km)"]:
		assert_string_contains(text, expected)
	var grade: Label = hud.get_node("%GradeValue")
	assert_eq(grade.get_theme_color("font_color"), RideHud.COLOR_STEEP, "steil bergauf: rot")
	assert_eq(hud.get_node("%GradeIcon").direction, 1, "Keil bergauf")
	assert_eq(hud.get_node("%Gauge").value, 85.0, "Bogen zeigt die Kadenz")
	hud.show_ride(80.0, 40.0, 7000.0, "19:05", -0.074, "-7.4 %", "Abfahrt", "180 W")
	assert_string_contains(hud.readout(), "Steigung: -7.4 %")
	assert_string_contains(hud.readout(), "Leistung: 180 W", "gemessen: ohne „~“")
	assert_eq(grade.get_theme_color("font_color"), RideHud.COLOR_DOWN, "bergab: kühl")
	assert_eq(hud.get_node("%GradeIcon").direction, -1, "Keil bergab")
	hud.show_ride(80.0, 26.0, 100.0, "0:15", 0.002, "+0.2 %", "", "")
	text = hud.readout()
	assert_false(text.contains("Leistung") or text.contains("W"), "keine Watt ohne Wert: %s" % text)
	assert_false(text.contains("Abschnitt"), "kein Abschnitt ohne Stationen (Graybox)")
	assert_eq(grade.get_theme_color("font_color"), RideHud.COLOR_FLAT, "flach: neutral")
	assert_eq(RideHud.grade_color(0.03), RideHud.COLOR_UP, "bergauf: warm")


func test_segment_live_time_only_inside_a_segment() -> void:
	var hud := _hud()
	assert_false(hud.readout().contains("Bergwertung"), "außerhalb eines Segments keine Segmentzeit")
	hud.show_segment("Bergwertung", "1:12.4")
	assert_string_contains(hud.readout(), "Bergwertung: 1:12.4", "im Segment: Name und Live-Zeit")
	hud.show_segment("", "")
	assert_false(hud.readout().contains("Bergwertung"), "nach dem Segment ausgeblendet")
	hud.celebrate("Bergwertung  7:35.2 · Silber – neue Bestzeit!")
	assert_eq(hud.celebration(), "Bergwertung  7:35.2 · Silber – neue Bestzeit!", "Ergebnis beim Verlassen")


func test_simultaneous_celebrations_queue_instead_of_overwriting() -> void:
	var hud := _hud()
	hud.celebrate("Neue Bestzeit!  14:44.7")
	hud.celebrate("Dorfsprint  0:41.2 · Gold")
	hud.celebrate("Erfolg: Erste Runde – Eine Runde zu Ende gefahren")
	hud.celebrate("Fahrerlevel 2 erreicht!")
	assert_eq(hud.celebration(), "Neue Bestzeit!  14:44.7", "die erste läuft")
	assert_eq(hud.queued_celebrations(), ["Dorfsprint  0:41.2 · Gold",
			"Erfolg: Erste Runde – Eine Runde zu Ende gefahren", "Fahrerlevel 2 erreicht!"], "die übrigen eingereiht")
	await wait_seconds(RideHud.CELEBRATION_S + 0.2)
	assert_eq(hud.celebration(), "Dorfsprint  0:41.2 · Gold", "nach CELEBRATION_S die nächste")
	assert_eq(hud.queued_celebrations().size(), 2)
	hud.end_celebration()
	assert_eq(hud.celebration(), "", "im Ziel: alle aus")
	assert_eq(hud.queued_celebrations(), [], "auch die eingereihten")
	hud.celebrate("Fahrerlevel 3 erreicht!")
	assert_eq(hud.celebration(), "Fahrerlevel 3 erreicht!", "danach sofort wieder sichtbar")


func test_ghost_gap_with_sign_and_color() -> void:
	var hud := _hud()
	assert_false(hud.readout().contains("Ghost"), "ohne Ghost kein Abstand")
	hud.show_ghost("+1.4", true)
	assert_string_contains(hud.readout(), "Ghost: +1.4 s", "hinter dem Ghost")
	assert_eq(hud.get_node("%GhostValue").get_theme_color("font_color"), RideHud.COLOR_BEHIND)
	hud.show_ghost("-0.8", false)
	assert_string_contains(hud.readout(), "Ghost: -0.8 s", "vor dem Ghost")
	assert_eq(hud.get_node("%GhostValue").get_theme_color("font_color"), RideHud.COLOR_AHEAD)
	hud.show_ghost("", false)
	assert_false(hud.readout().contains("Ghost"), "Ghost aus: ausgeblendet")


## Alle sichtbaren HUD-Anzeigen in `viewport_size` (Pixel); `canvas_size` ≠ Null wie `stretch/mode="canvas_items"`
## (die Oberfläche wird in dieser Größe angelegt und skaliert). Liefert das HUD nach dem Layout.
func _layout_in(viewport_size: Vector2i, canvas_size: Vector2i = Vector2i.ZERO) -> RideHud:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	if canvas_size != Vector2i.ZERO:
		viewport.size_2d_override = canvas_size
		viewport.size_2d_override_stretch = true
	add_child_autofree(viewport)
	var track := Track.new()
	IslandCourse.apply_to(track)
	viewport.add_child(track)
	var hud: RideHud = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	hud.setup(track)
	hud.show_ride(118.0, 58.4, 9210.0, "1:02:33", -0.088, "-8.8 %", "Pinien-/Olivenhain", "~1042 W")
	hud.show_lap(4000.0, 0.0, 9210.0, 4000.0)
	hud.show_lap_count(12, 20, "1:02:33")
	hud.show_segment("Küstenwelle", "12:34.5")
	hud.show_ghost("+123.4", true)
	hud.celebrate("Neue Bestzeit!  1:02:33.4")
	(hud.get_node("Hint") as Label).text = "Widerstand: nicht unterstützt"
	(hud.get_node("Debug") as Label).text = \
			"DEBUG\nKadenz roh: 72.5\nt_ms: 123456\nLetzte Telemetrie vor: 120 ms\nBus: verbunden · Quelle: connected (sim)"
	hud.get_node("Debug").visible = true
	(hud.get_node("Message") as Label).text = LONG_MESSAGE
	hud.get_node("Message").visible = true
	await wait_process_frames(4)
	return hud


func _assert_inside(hud: RideHud, label: String) -> void:
	var screen: Rect2 = hud.get_node("Layout").get_viewport_rect()
	var checked := 0
	for control in hud.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control.get_parent() is HudProfile or control.get_parent() is HudMinimap:
			continue  # Marker liegen innerhalb ihrer Zeichenfläche und dürfen über deren Rand ragen
		var rect: Rect2 = control.get_global_rect()
		checked += 1
		assert_true(screen.grow(0.5).encloses(rect), "%s: %s liegt im Fenster %s (%s)" % [label, control.name, screen, rect])
	assert_gt(checked, 30, "%s: alle Anzeigen geprüft" % label)
	var stats: Rect2 = hud.get_node("%Stats").get_global_rect()
	var map: Rect2 = hud.get_node("%Minimap").get_parent().get_global_rect()
	var bottom: Rect2 = hud.get_node("%Bottom").get_global_rect()
	assert_false(stats.intersects(map), "%s: Werte und Karte überlappen nicht" % label)
	assert_false(stats.intersects(bottom) or map.intersects(bottom), "%s: oben und unten überlappen nicht" % label)
	assert_false((hud.get_node("Hint") as Control).get_global_rect().intersects(bottom), "%s: Hinweis über dem Panel" % label)
	var celebration: Control = hud.get_node("%Celebration")
	assert_true(celebration.is_visible_in_tree(), "%s: Einblendung „Neue Bestzeit!“ sichtbar" % label)
	for other in [stats, map, bottom, (hud.get_node("Hint") as Control).get_global_rect()]:
		assert_false(celebration.get_global_rect().intersects(other), "%s: Einblendung frei von %s" % [label, other])


func test_layout_fits_half_screen_window() -> void:
	var hud := await _layout_in(Vector2i(960, 1040))
	_assert_inside(hud, "960×1040")
	var message: Rect2 = (hud.get_node("Message") as Control).get_global_rect()
	assert_false(message.intersects(hud.get_node("%Stats").get_global_rect()), "Meldung frei von den Werten")
	assert_false(message.intersects(hud.get_node("%Bottom").get_global_rect()), "Meldung frei vom Profil")


func test_layout_fits_full_hd_and_1600x900() -> void:
	_assert_inside(await _layout_in(Vector2i(1920, 1080)), "1920×1080")
	_assert_inside(await _layout_in(Vector2i(1600, 900)), "1600×900")
	_assert_inside(await _layout_in(Vector2i(1152, 648)), "1152×648 (Godot-Standardfenster)")


func test_layout_fits_with_canvas_items_stretch() -> void:
	# canvas_items mit Basis 1920×1080: Halbbild 960×1040 mit aspect "expand" → Oberfläche 1920×2080, "keep" → 1920×1080.
	_assert_inside(await _layout_in(Vector2i(960, 1040), Vector2i(1920, 2080)), "canvas_items expand")
	_assert_inside(await _layout_in(Vector2i(960, 540), Vector2i(1920, 1080)), "canvas_items keep")


func test_segment_live_time_fits_between_panels() -> void:
	for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var hud := await _layout_in(size)
		hud.get_node("%Celebration").hide()  # die Live-Zeit steht an der Stelle der Einblendung, die Vorrang hat
		hud.show_segment("Küstenwelle", "12:34.5")
		await wait_process_frames(2)
		var segment: Control = hud.get_node("%Segment")
		assert_true(segment.is_visible_in_tree(), "%s: Live-Zeit sichtbar" % size)
		var rect := segment.get_global_rect()
		assert_true(hud.get_node("Layout").get_viewport_rect().encloses(rect), "%s: im Fenster" % size)
		for other in ["%Stats", "%Bottom", "Hint"]:
			assert_false(rect.intersects((hud.get_node(other) as Control).get_global_rect()), "%s: frei von %s" % [size, other])
		assert_false(rect.intersects(hud.get_node("%Minimap").get_parent().get_global_rect()), "%s: frei von der Karte" % size)
