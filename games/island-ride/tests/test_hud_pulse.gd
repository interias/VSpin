## Puls im HUD (#64): Anzeige im Werte-Panel (bpm, Farbe und Nummer der Zone, ohne Zonen nur bpm, ohne Wert „--“, ohne
## Pulsquelle weg), die Verlaufskurve (reine Rechnung: Punkte, Lücken, Zeitfenster, Skala, Zonenbänder) und das Layout
## im vollen und im kompakten Fenster – alle Anzeigen liegen im Fenster, die Leiste bleibt eine Zeile.
extends GutTest

const HUD_SCENE := preload("res://scenes/hud.tscn")
## LTHR 160: Z1 < 130, Z2 130–143, Z3 144–149, Z4 150–159, Z5 ab 160 bpm.
const LTHR := 160


## HUD im vollen Layout (1920×1080): im Testfenster (1152×648) wäre es kompakt.
func _hud() -> RideHud:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var hud: RideHud = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	return hud


func _zones() -> HeartRateZones:
	return HeartRateZones.new(LTHR)


func _area() -> Rect2:
	return Rect2(10, 20, 360, 60)


func test_pulse_text_zone_and_color_follow_the_value_and_the_zones() -> void:
	var zones := _zones()
	assert_eq(RideHud.pulse_text(147.6), "148", "ganze bpm")
	assert_eq(RideHud.pulse_text(NAN), "--")
	assert_eq(RideHud.pulse_text(0.0), "--", "0 ist kein Puls")
	assert_eq(RideHud.pulse_text(-3.0), "--")
	assert_eq(RideHud.pulse_text(INF), "--")
	assert_eq(RideHud.pulse_zone(148.0, zones), 3)
	assert_eq(RideHud.pulse_zone(100.0, zones), 1)
	assert_eq(RideHud.pulse_zone(185.0, zones), 5)
	assert_eq(RideHud.pulse_zone(NAN, zones), 0, "ohne Wert keine Zone")
	assert_eq(RideHud.pulse_zone(148.0, null), 0)
	assert_eq(RideHud.pulse_zone(148.0, HeartRateZones.new()), 0, "ohne LTHR und Maximalpuls keine Zone")
	for zone in range(1, 6):
		var bpm := float(zones.zone_range(zone).x) + 1.0
		assert_eq(RideHud.pulse_color(bpm, zones), HeartRateZones.COLORS[zone - 1], "Zonenfarbe Z%d" % zone)
	assert_eq(RideHud.pulse_color(148.0, HeartRateZones.new()), Color.WHITE, "ohne Zonen weiß")
	assert_eq(RideHud.pulse_color(NAN, zones), RideHud.COLOR_PULSE_NONE, "ohne Wert gedämpft")


func test_value_panel_shows_bpm_zone_number_and_zone_color() -> void:
	var hud := _hud()
	hud.show_pulse(148.0, _zones(), true, 10.0)
	assert_true(hud.get_node("%Pulse").is_visible_in_tree())
	assert_string_contains(hud.readout(), "Puls: 148 bpm · Z3")
	assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), HeartRateZones.COLORS[2], "Zahl in Zonenfarbe")
	assert_eq(hud.get_node("%PulseZone").get_theme_color("font_color"), HeartRateZones.COLORS[2], "Zonennummer ebenso")
	hud.show_pulse(172.0, _zones(), true, 11.0)
	assert_string_contains(hud.readout(), "Puls: 172 bpm · Z5")
	assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), HeartRateZones.COLORS[4], "Farbe wechselt mit der Zone")


func test_without_zones_only_bpm_in_neutral_color() -> void:
	var hud := _hud()
	hud.show_pulse(148.0, HeartRateZones.new(), true, 10.0)
	assert_string_contains(hud.readout(), "Puls: 148 bpm")
	assert_false(hud.readout().contains("Z3") or hud.readout().contains(" · Z"), "keine Zone")
	assert_eq(hud.get_node("%PulseZone").text, "")
	assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), Color.WHITE)
	hud.show_pulse(148.0, null, true, 11.0)
	assert_string_contains(hud.readout(), "Puls: 148 bpm", "auch ohne Zonenobjekt")


func test_without_value_shows_dashes_while_a_device_is_known() -> void:
	var hud := _hud()
	hud.show_pulse(148.0, _zones(), true, 10.0)
	hud.show_pulse(NAN, _zones(), true, 11.0)
	assert_true(hud.get_node("%Pulse").is_visible_in_tree(), "Gerät bekannt, kein Wert: Anzeige bleibt")
	assert_string_contains(hud.readout(), "Puls: --")
	assert_false(hud.readout().contains("Puls: -- bpm"), "ohne Wert keine Einheit")
	assert_false(hud.get_node("%Unit").visible, "„--“ ohne Einheit")
	assert_eq(hud.get_node("%PulseZone").text, "", "ohne Wert keine Zone")
	assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), RideHud.COLOR_PULSE_NONE)
	hud.show_pulse(150.0, _zones(), true, 12.0)
	assert_string_contains(hud.readout(), "Puls: 150 bpm · Z4", "der Wert kommt zurück")


func test_dashes_are_dimmed_even_as_the_very_first_state() -> void:
	var hud := _hud()
	hud.show_pulse(NAN, _zones(), true, 0.0)  # Gerät verbunden, noch kein Wert: gleich „--“
	assert_string_contains(hud.readout(), "Puls: --")
	assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), RideHud.COLOR_PULSE_NONE, "gedämpft, nicht Standardweiß")


func test_without_any_pulse_source_the_display_is_hidden() -> void:
	var hud := _hud()
	hud.show_pulse(NAN, _zones(), false, 10.0)
	assert_false(hud.get_node("%Pulse").is_visible_in_tree())
	assert_false(hud.get_node("%PulseGraph").is_visible_in_tree())
	assert_false(hud.readout().contains("Puls"), "nicht im Readout")
	hud.show_pulse(140.0, _zones(), true, 11.0)
	assert_true(hud.get_node("%Pulse").is_visible_in_tree())
	hud.show_pulse(NAN, _zones(), false, 12.0)
	assert_false(hud.get_node("%Pulse").is_visible_in_tree(), "wieder weg")


# --- Verlaufskurve: reine Rechnung ---------------------------------------------------------------------------------

func test_point_maps_time_and_bpm_into_the_area() -> void:
	var area := _area()
	assert_eq(HudPulse.point(1000.0, 60.0, 1000.0, 60.0, 180.0, area), Vector2(370, 80), "jetzt, unterste bpm: rechts unten")
	assert_eq(HudPulse.point(1000.0 - HudPulse.WINDOW_S, 180.0, 1000.0, 60.0, 180.0, area), Vector2(10, 20),
			"3 min früher, oberste bpm: links oben")
	assert_almost_eq(HudPulse.point(910.0, 120.0, 1000.0, 60.0, 180.0, area), Vector2(190, 50), Vector2(0.001, 0.001), "Mitte")
	assert_eq(HudPulse.point(0.0, 500.0, 1000.0, 60.0, 180.0, area), Vector2(10, 20), "außerhalb wird begrenzt")


func test_curve_splits_at_gaps_and_does_not_interpolate() -> void:
	var samples := [Vector2(0.0, 120), Vector2(0.5, 121), Vector2(1.0, 122), Vector2(10.0, 130), Vector2(10.5, 131)]
	var lines := HudPulse.curve_points(samples, 11.0, 100.0, 140.0, _area())
	assert_eq(lines.size(), 2, "Lücke von 9 s trennt den Zug")
	assert_eq(lines[0].size(), 3)
	assert_eq(lines[1].size(), 2)
	assert_lt(lines[0][2].x, lines[1][0].x)
	var close := [Vector2(0.0, 120), Vector2(HudPulse.GAP_S, 121)]
	assert_eq(HudPulse.curve_points(close, 4.0, 100.0, 140.0, _area()).size(), 1, "genau GAP_S ist noch keine Lücke")
	var apart := [Vector2(0.0, 120), Vector2(HudPulse.GAP_S + 0.1, 121)]
	assert_eq(HudPulse.curve_points(apart, 4.0, 100.0, 140.0, _area()).size(), 2, "darüber schon")
	assert_eq(HudPulse.curve_points([Vector2(5.0, 120)], 6.0, 100.0, 140.0, _area())[0].size(), 1, "einzelner Punkt")
	assert_eq(HudPulse.curve_points([], 6.0, 100.0, 140.0, _area()).size(), 0, "ohne Punkte keine Linie")


func test_curve_shows_only_the_last_three_minutes() -> void:
	var samples: Array = []
	for i in range(0, 401):
		samples.append(Vector2(i * 1.0, 120.0 + i % 7))
	var lines := HudPulse.curve_points(samples, 400.0, 100.0, 140.0, _area())
	var count := 0
	for line in lines:
		count += line.size()
	assert_eq(count, int(HudPulse.WINDOW_S) + 1, "180 s + der Punkt auf der Grenze")
	assert_almost_eq(lines[0][0].x, _area().position.x, 0.001, "ältester Punkt links")
	assert_almost_eq(lines[-1][-1].x, _area().end.x, 0.001, "neuester rechts")


func test_scale_follows_the_data_with_margin_and_a_minimum_span() -> void:
	assert_eq(HudPulse.bpm_range([], 100.0), HudPulse.DEFAULT_RANGE, "ohne Daten Standardskala")
	assert_eq(HudPulse.bpm_range([Vector2(1.0, 118), Vector2(2.0, 152)], 3.0), Vector2(110, 160), "Daten ± Luft, auf 10 gerundet")
	var narrow := HudPulse.bpm_range([Vector2(1.0, 140), Vector2(2.0, 141)], 3.0)
	assert_almost_eq(narrow.y - narrow.x, HudPulse.MIN_SPAN_BPM, 0.001, "kleinste Spanne")
	assert_between(140.0, narrow.x, narrow.y)
	assert_eq(HudPulse.bpm_range([Vector2(1.0, 200), Vector2(500.0, 130)], 505.0), Vector2(110, 150),
			"Punkte außerhalb des Fensters zählen nicht")


func test_zone_bands_cover_the_scale_in_zone_order() -> void:
	var area := _area()
	var bands := HudPulse.band_rects(_zones(), 100.0, 180.0, area)
	assert_eq(bands.size(), 5, "alle fünf Zonen im Bild")
	var covered := 0.0
	for i in range(bands.size()):
		assert_eq(bands[i]["zone"], i + 1)
		var rect: Rect2 = bands[i]["rect"]
		covered += rect.size.y
		assert_eq(rect.position.x, area.position.x)
		assert_eq(rect.size.x, area.size.x)
		if i > 0:
			assert_almost_eq(rect.end.y, (bands[i - 1]["rect"] as Rect2).position.y, 0.001, "Z%d schließt an Z%d an" % [i + 1, i])
	assert_almost_eq(covered, area.size.y, 0.001, "Bänder füllen die Fläche")
	assert_almost_eq((bands[0]["rect"] as Rect2).end.y, area.end.y, 0.001, "Z1 unten (nach unten offen)")
	assert_almost_eq((bands[4]["rect"] as Rect2).position.y, area.position.y, 0.001, "Z5 oben (nach oben offen)")
	# Z2 = 130–143 bpm: von 130 bis 144 auf der Skala 100–180
	var z2: Rect2 = bands[1]["rect"]
	assert_almost_eq(z2.size.y, area.size.y * 14.0 / 80.0, 0.001, "Höhe nach bpm-Spanne")
	assert_almost_eq(z2.end.y, area.end.y - area.size.y * 30.0 / 80.0, 0.001, "Lage nach bpm")


func test_zone_bands_only_for_zones_in_the_scale_and_neutral_without_zones() -> void:
	var bands := HudPulse.band_rects(_zones(), 140.0, 170.0, _area())
	assert_eq(bands.map(func(b): return b["zone"]), [2, 3, 4, 5], "Z1 liegt unter der Skala")
	assert_eq(HudPulse.band_rects(HeartRateZones.new(), 100.0, 180.0, _area()).size(), 0, "ohne Zonen keine Bänder")
	assert_eq(HudPulse.band_rects(null, 100.0, 180.0, _area()).size(), 0)
	var from_max := HudPulse.band_rects(HeartRateZones.new(0, 190), 60.0, 200.0, _area())
	assert_eq(from_max.size(), 5, "auch Zonen aus dem Maximalpuls")
	assert_almost_eq((from_max[0]["rect"] as Rect2).end.y, _area().end.y, 0.001, "Z1 reicht unter ihre 50 % nach unten")
	assert_almost_eq((from_max[4]["rect"] as Rect2).position.y, _area().position.y, 0.001, "Z5 reicht über HFmax nach oben")


# --- Verlauf aufnehmen ---------------------------------------------------------------------------------------------

func _graph() -> HudPulse:
	var graph := HudPulse.new()
	graph.size = Vector2(360, 64)
	add_child_autofree(graph)
	return graph


func test_push_keeps_points_at_sample_spacing_and_drops_old_ones() -> void:
	var graph := _graph()
	for i in range(0, 2001):
		graph.push(i * 0.1, 140.0, _zones())  # 200 s in 10-Hz-Schritten
	assert_lt(graph.samples.size(), 2000 * 0.1 / HudPulse.SAMPLE_S + 2, "höchstens ein Punkt je SAMPLE_S")
	assert_gte(graph.samples[0].x, 200.0 - HudPulse.WINDOW_S - 0.001, "nichts vor dem Zeitfenster")
	assert_gt(graph.samples.size(), 300, "das Fenster ist gefüllt")


func test_push_without_value_leaves_a_gap_and_stands_still_in_pauses() -> void:
	var graph := _graph()
	for i in range(0, 21):
		graph.push(i * 0.5, 130.0, null)
	var before := graph.samples.size()
	for i in range(21, 61):
		graph.push(i * 0.5, NAN, null)  # 20 s ohne Puls
	for i in range(61, 81):
		graph.push(i * 0.5, 135.0, null)
	assert_eq(graph.samples.size(), before + 20, "Lücke ohne Ersatzpunkte")
	var lines := HudPulse.curve_points(graph.samples, graph.now_s, 100.0, 160.0, graph.plot_rect())
	assert_eq(lines.size(), 2, "zwei Stücke")
	var count := graph.samples.size()
	for i in range(0, 50):
		graph.push(40.0, 136.0, null)  # Pause: die Fahrzeit steht
	assert_eq(graph.samples.size(), count, "in der Pause kommt nichts dazu")
	for value in [0.0, -1.0, INF]:
		graph.push(41.0, value, null)
	assert_eq(graph.samples.size(), count, "0, negativ und unendlich sind kein Puls")


func test_new_ride_starts_a_new_curve() -> void:
	var graph := _graph()
	for i in range(0, 41):
		graph.push(i * 0.5, 140.0, null)
	graph.push(0.0, 120.0, null)
	assert_eq(graph.samples.size(), 1, "Zeit zurück: neuer Verlauf")
	graph.push(30.0, 140.0, null)
	graph.reset()
	assert_eq(graph.samples.size(), 0)
	assert_eq(graph.now_s, 0.0)


func test_graph_draws_without_errors_with_and_without_zones_and_gaps() -> void:
	var graph := _graph()
	for i in range(0, 120):
		graph.push(i * 0.5, 120.0 + i if i < 40 or i > 80 else NAN, _zones() if i % 2 == 0 else null)
	await wait_process_frames(2)
	graph.size = Vector2(1, 1)
	await wait_process_frames(2)
	assert_gt(graph.samples.size(), 0)


# --- Anbindung im HUD ----------------------------------------------------------------------------------------------

func test_hud_records_the_curve_only_from_fresh_values() -> void:
	var hud := _hud()
	var graph: HudPulse = hud.get_node("%PulseGraph")
	for i in range(0, 20):
		hud.show_pulse(140.0 + i, _zones(), true, i * 0.5)
	assert_eq(graph.samples.size(), 20)
	for i in range(20, 30):
		hud.show_pulse(NAN, _zones(), true, i * 0.5)
	assert_eq(graph.samples.size(), 20, "„--“ legt keinen Punkt an")
	hud.reset_pulse()
	assert_eq(graph.samples.size(), 0)


# --- Layout --------------------------------------------------------------------------------------------------------

## HUD in `viewport_size` mit Pulsanzeige und gefülltem Verlauf; Wert `bpm` (NAN = „--“).
func _layout_in(viewport_size: Vector2i, bpm: float = 148.0, shown: bool = true) -> RideHud:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
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
	for i in range(0, 361):
		hud.show_pulse(bpm + 20.0 * sin(i * 0.05), _zones(), shown, i * 0.5)
	hud.show_pulse(bpm, _zones(), shown, 181.0)
	(hud.get_node("Message") as Label).text = "Verbindung verloren\nNeuer Versuch läuft …"
	hud.get_node("Message").visible = true
	await wait_process_frames(4)
	return hud


func _assert_inside(hud: RideHud, label: String) -> void:
	var screen: Rect2 = hud.get_node("Layout").get_viewport_rect()
	for control in hud.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control.get_parent() is HudProfile or control.get_parent() is HudMinimap:
			continue
		assert_true(screen.grow(0.5).encloses(control.get_global_rect()),
				"%s: %s liegt im Fenster %s (%s)" % [label, control.name, screen, control.get_global_rect()])
	var panels: Array[Rect2] = [hud.get_node("%Stats").get_global_rect(), hud.get_node("%Bottom").get_global_rect()]
	var map: Control = hud.get_node("%Minimap").get_parent()
	if map.is_visible_in_tree():
		panels.append(map.get_global_rect())
	for i in panels.size():
		for j in range(i + 1, panels.size()):
			assert_false(panels[i].intersects(panels[j]), "%s: Panels %s und %s überlappen nicht" % [label, panels[i], panels[j]])
	var message: Rect2 = (hud.get_node("Message") as Control).get_global_rect()
	for panel in panels:
		assert_false(message.intersects(panel), "%s: Meldung %s frei vom Panel %s" % [label, message, panel])


func test_full_layout_shows_value_and_curve_inside_the_window() -> void:
	for size in [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(960, 1040), Vector2i(1366, 768), Vector2i(1280, 800)]:
		var hud := await _layout_in(size)
		assert_false(hud.compact, "%s: volles Layout" % size)
		assert_true(hud.get_node("%Pulse").is_visible_in_tree(), "%s: Puls" % size)
		assert_true(hud.get_node("%PulseGraph").is_visible_in_tree(), "%s: Kurve" % size)
		var graph: Control = hud.get_node("%PulseGraph")
		assert_gt(graph.size.x, 150.0, "%s: Kurve hat Breite" % size)
		assert_gte(graph.size.y, 60.0, "%s: Kurve hat Höhe" % size)
		assert_string_contains(hud.readout(), "Puls: 148 bpm · Z3")
		_assert_inside(hud, "%s" % size)


func test_compact_bar_keeps_value_and_zone_color_but_drops_the_curve() -> void:
	for size in [Vector2i(1152, 648), Vector2i(1280, 720)]:
		var hud := await _layout_in(size)
		assert_true(hud.compact, "%s: Leiste" % size)
		assert_true(hud.get_node("%Pulse").is_visible_in_tree(), "%s: Puls in der Leiste" % size)
		assert_false(hud.get_node("%PulseGraph").is_visible_in_tree(), "%s: keine Kurve in der Leiste" % size)
		assert_string_contains(hud.readout(), "Puls: 148 · Z3")
		assert_eq(hud.get_node("%PulseValue").get_theme_color("font_color"), HeartRateZones.COLORS[2], "%s: Zonenfarbe" % size)
		_assert_inside(hud, "%s" % size)
		# Die Leiste bleibt eine Zeile: dieselbe Höhe wie ohne Pulsanzeige.
		var with_pulse: float = hud.get_node("%Stats").size.y
		hud.show_pulse(NAN, _zones(), false, 200.0)
		await wait_process_frames(3)
		assert_almost_eq(with_pulse, hud.get_node("%Stats").size.y, 0.5, "%s: Werte weiter in einer Zeile" % size)
		var grid: GridContainer = hud.get_node("Layout/Rows/Top/Stats/Box/Main/Grid")
		assert_eq(grid.columns, RideHud.GRID_COLUMNS_COMPACT)


func test_curve_comes_back_when_the_window_grows_and_goes_when_it_shrinks() -> void:
	var hud := await _layout_in(Vector2i(1152, 648))
	var graph: Control = hud.get_node("%PulseGraph")
	assert_false(graph.is_visible_in_tree())
	var viewport: SubViewport = hud.get_parent()
	viewport.size = Vector2i(1920, 1080)
	hud.show_pulse(148.0, _zones(), true, 182.0)
	await wait_process_frames(4)
	assert_true(graph.is_visible_in_tree(), "hohes Fenster: Kurve da")
	viewport.size = Vector2i(1152, 648)
	await wait_process_frames(4)
	assert_false(graph.is_visible_in_tree(), "niedriges Fenster: Kurve weg")
	assert_true(hud.get_node("%Pulse").is_visible_in_tree(), "Zahl bleibt")


func test_dashes_fit_in_both_layouts() -> void:
	for size in [Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var hud := await _layout_in(size, NAN)
		assert_string_contains(hud.readout(), "Puls: --")
		_assert_inside(hud, "%s ohne Wert" % size)


func test_no_pulse_source_leaves_the_layout_as_before() -> void:
	for size in [Vector2i(1920, 1080), Vector2i(1152, 648)]:
		var hud := await _layout_in(size, 148.0, false)
		assert_false(hud.get_node("%Pulse").is_visible_in_tree())
		assert_false(hud.get_node("%PulseGraph").is_visible_in_tree())
		_assert_inside(hud, "%s ohne Pulsquelle" % size)
