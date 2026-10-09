## Kadenzmuster (#50): Antritt, Gleichmaß, Innehalten und Rhythmus aus Kadenzverläufen – je Muster positiv und negativ
## (knapp darunter, Rauschen, Stillstand ist kein Gleichmaß, Anfahren aus dem Stand ist kein Antritt, Pause ohne vorheriges
## Treten ist kein Innehalten, Zittern ist kein Takt) und die Simulator-Profile `antritt`/`innehalten` im Meldetakt 250 ms.
extends GutTest

const DT := 0.1


## Verlauf aus Abschnitten [Dauer, von, bis] als Kadenz je Schritt (wie der Simulator der Bridge: linear, Endwert im
## letzten Schritt).
func _values(segments: Array, dt: float = DT) -> Array:
	var values := []
	for segment in segments:
		var count := maxi(1, roundi(segment[0] / dt))
		for i in range(count):
			var fraction := float(i) / (count - 1) if count > 1 else 0.0
			values.append(segment[1] + (segment[2] - segment[1]) * fraction)
	return values


## Verlauf durch den Erkenner: Liste {id, t} (t = Ende des Schritts, in s).
func _detect(values: Array, dt: float = DT, overrides: Dictionary = {}) -> Array:
	var patterns := CadencePatterns.new(overrides)
	var events := []
	for i in range(values.size()):
		for id in patterns.feed(values[i], dt):
			events.append({"id": id, "t": (i + 1) * dt})
	return events


func _ids(events: Array, id: String) -> Array:
	return events.filter(func(e): return e["id"] == id)


## Segment „hält `rpm`“ für `seconds`.
func _hold(seconds: float, rpm: float) -> Array:
	return [seconds, rpm, rpm]


## Profil der Bridge als Verlauf im Meldetakt (eine Kadenz je 250 ms).
func _profile_values(name: String) -> Array:
	var values := []
	var steps := SimProfile.to_script(SimProfile.load_toml(SimProfile.path("arcade/" + name)))
	for step in steps:
		if step["send"]["type"] == "telemetry":
			values.append(step["send"]["cadence"])
	return values


# --- Antritt -----------------------------------------------------------------------------------------------------


func test_antritt_is_found_for_a_fast_rise() -> void:
	var events := _ids(_detect(_values([_hold(6.0, 80.0), [0.5, 80.0, 110.0], _hold(4.0, 110.0)])), "antritt")
	assert_eq(events.size(), 1)
	assert_between(events[0]["t"], 6.0, 6.6, "kurz nach dem Anstieg, nicht erst später")


func test_antritt_needs_25_rpm_within_two_seconds() -> void:
	for rise in [26.0, 30.0, 40.0]:
		var found := _ids(_detect(_values([_hold(6.0, 80.0), [2.0, 80.0, 80.0 + rise], _hold(3.0, 80.0 + rise)])), "antritt")
		assert_eq(found.size(), 1, "+%d rpm in 2 s" % rise)
	for rise in [24.0, 20.0, 10.0]:
		var missed := _ids(_detect(_values([_hold(6.0, 80.0), [2.0, 80.0, 80.0 + rise], _hold(3.0, 80.0 + rise)])), "antritt")
		assert_eq(missed.size(), 0, "+%d rpm in 2 s ist knapp darunter" % rise)


func test_a_slow_climb_is_no_antritt() -> void:
	# +40 rpm, aber über 8 s verteilt: in keinem 2-s-Fenster mehr als +10
	assert_eq(_ids(_detect(_values([_hold(4.0, 70.0), [8.0, 70.0, 110.0], _hold(4.0, 110.0)])), "antritt").size(), 0)


func test_starting_from_standstill_is_no_antritt() -> void:
	assert_eq(_ids(_detect(_values([_hold(3.0, 0.0), [1.0, 0.0, 80.0], _hold(5.0, 80.0)])), "antritt").size(), 0, "0 → 80")
	assert_eq(_ids(_detect(_values([_hold(3.0, 20.0), [1.0, 20.0, 60.0], _hold(5.0, 60.0)])), "antritt").size(), 0,
			"Minimum unter 30 rpm")
	assert_eq(_ids(_detect(_values([_hold(3.0, 30.0), [1.0, 30.0, 60.0], _hold(5.0, 60.0)])), "antritt").size(), 1,
			"Minimum genau 30 rpm zählt")


func test_antritt_fires_once_per_rise_and_again_after_calming_down() -> void:
	var values := _values([_hold(5.0, 80.0), [0.5, 80.0, 110.0], _hold(4.0, 110.0), [2.0, 110.0, 80.0], _hold(4.0, 80.0),
			[0.5, 80.0, 110.0], _hold(3.0, 110.0)])
	assert_eq(_ids(_detect(values), "antritt").size(), 2, "zwei Antritte, nicht mehr")


func test_antritt_does_not_fire_twice_in_a_noisy_plateau() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var values := _values([_hold(5.0, 80.0), [0.5, 80.0, 110.0]])
	for i in range(80):
		values.append(110.0 + rng.randf_range(-3.0, 3.0))
	assert_eq(_ids(_detect(values), "antritt").size(), 1)


func test_noise_around_a_steady_cadence_gives_no_antritt_pause_or_beat() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var values := []
	for i in range(900):  # 90 s ±4 rpm
		values.append(80.0 + rng.randf_range(-4.0, 4.0))
	var events := _detect(values)
	assert_eq(_ids(events, "antritt").size(), 0, "kein Antritt im Rauschen")
	assert_eq(_ids(events, "innehalten").size(), 0, "kein Innehalten")
	assert_eq(_ids(events, "rhythmus").size(), 0, "kein Takt im Rauschen")


func test_the_antritt_profile_gives_three_antritte_at_the_reporting_rate() -> void:
	var events := _detect(_profile_values("antritt.toml"), 0.25)
	assert_eq(_ids(events, "antritt").size(), 3, "explosiv, zügig und knapp")
	assert_eq(_ids(events, "innehalten").size(), 0)


# --- Innehalten --------------------------------------------------------------------------------------------------


func test_innehalten_after_two_seconds_without_pedalling() -> void:
	var events := _ids(_detect(_values([_hold(6.0, 80.0), _hold(3.0, 0.0), _hold(3.0, 80.0)])), "innehalten")
	assert_eq(events.size(), 1)
	assert_almost_eq(events[0]["t"], 8.0, 0.11, "nach 2 s Stillstand")


func test_a_shorter_pause_is_no_innehalten() -> void:
	assert_eq(_ids(_detect(_values([_hold(6.0, 80.0), _hold(1.9, 0.0), _hold(6.0, 80.0)])), "innehalten").size(), 0)
	assert_eq(_ids(_detect(_values([_hold(6.0, 80.0), _hold(5.0, 12.0), _hold(6.0, 80.0)])), "innehalten").size(), 0,
			"12 rpm ist noch Treten")


func test_innehalten_needs_pedalling_before_and_comes_once_per_pause() -> void:
	assert_eq(_ids(_detect(_values([_hold(10.0, 0.0), [1.0, 0.0, 80.0]])), "innehalten").size(), 0, "von Anfang an Stillstand")
	assert_eq(_ids(_detect(_values([_hold(6.0, 80.0), _hold(8.0, 0.0)])), "innehalten").size(), 1, "einmal je Pause")
	var twice := _values([_hold(6.0, 80.0), _hold(3.0, 0.0), _hold(5.0, 80.0), _hold(3.0, 0.0)])
	assert_eq(_ids(_detect(twice), "innehalten").size(), 2, "jede Pause für sich")


func test_a_short_dip_resets_the_pause() -> void:
	var values := _values([_hold(6.0, 80.0), _hold(1.5, 0.0), _hold(0.5, 40.0), _hold(1.5, 0.0), _hold(3.0, 80.0)])
	assert_eq(_ids(_detect(values), "innehalten").size(), 0, "zweimal 1,5 s zählt nicht zusammen")


func test_the_innehalten_profile_gives_two_pauses_at_the_reporting_rate() -> void:
	var events := _ids(_detect(_profile_values("innehalten.toml"), 0.25), "innehalten")
	assert_eq(events.size(), 2, "die 3-s-Pausen, nicht das Absetzen von 1,5 s")


# --- Gleichmaß ---------------------------------------------------------------------------------------------------


func test_gleichmass_after_ten_steady_seconds() -> void:
	var values := []
	for i in range(150):  # 15 s zwischen 77 und 83 rpm (±3)
		values.append(80.0 + (3.0 if i % 2 == 0 else -3.0))
	var events := _ids(_detect(values), "gleichmass")
	assert_eq(events.size(), 1)
	assert_almost_eq(events[0]["t"], 10.0, 0.11, "nach 10 s")


func test_gleichmass_is_not_found_outside_the_band_or_too_short() -> void:
	var wide := []
	for i in range(300):  # ±3,5 rpm
		wide.append(80.0 + (3.5 if i % 2 == 0 else -3.5))
	assert_eq(_ids(_detect(wide), "gleichmass").size(), 0, "±3,5 rpm ist zu unruhig")
	assert_eq(_ids(_detect(_values([_hold(9.5, 80.0), [0.5, 80.0, 95.0], _hold(9.0, 95.0)])), "gleichmass").size(), 0,
			"9,5 s, dann ein Sprung")


func test_standstill_and_a_very_low_cadence_are_no_gleichmass() -> void:
	assert_eq(_ids(_detect(_values([_hold(30.0, 0.0)])), "gleichmass").size(), 0, "Stillstand")
	assert_eq(_ids(_detect(_values([_hold(30.0, 30.0)])), "gleichmass").size(), 0, "30 rpm")
	assert_eq(_ids(_detect(_values([_hold(30.0, 40.0)])), "gleichmass").size(), 3, "40 rpm ist die Untergrenze")


func test_gleichmass_comes_again_after_another_ten_seconds() -> void:
	var events := _ids(_detect(_values([_hold(21.0, 85.0)])), "gleichmass")
	assert_eq(events.size(), 2)
	assert_almost_eq(events[1]["t"] - events[0]["t"], 10.0, 0.11)


func test_a_wobble_resets_gleichmass() -> void:
	var values := _values([_hold(8.0, 80.0), _hold(0.5, 100.0), _hold(9.0, 80.0)])
	assert_eq(_ids(_detect(values), "gleichmass").size(), 0, "der Ausschlag liegt noch im Fenster")
	values.append_array(_values([_hold(3.0, 80.0)]))
	assert_eq(_ids(_detect(values), "gleichmass").size(), 1, "10 s nach dem Ausschlag ist wieder Ruhe")


# --- Rhythmus ----------------------------------------------------------------------------------------------------


## `count` Pulse im Abstand `period` s zwischen `low` und `high` rpm (halbe Periode hoch, halbe runter).
func _pulses(count: int, period: float, low: float, high: float) -> Array:
	var segments := [_hold(3.0, low)]
	for i in range(count):
		segments.append([period / 2.0, low, high])
		segments.append([period / 2.0, high, low])
	return _values(segments)


func test_rhythmus_after_four_even_pulses() -> void:
	var events := _ids(_detect(_pulses(6, 3.0, 80.0, 96.0)), "rhythmus")
	assert_eq(events.size(), 1, "vier Flanken im Takt: einmal, dann zählt der Takt neu")
	assert_between(events[0]["t"], 3.0 + 9.0, 3.0 + 12.0, "mit dem vierten Puls")
	assert_eq(_ids(_detect(_pulses(10, 3.0, 80.0, 96.0)), "rhythmus").size(), 3, "weiterpulsen: wieder nach drei Pulsen")


func test_rhythmus_needs_an_even_beat() -> void:
	var uneven := [_hold(3.0, 80.0)]
	for period in [1.5, 4.0, 1.5, 4.0, 1.5]:
		uneven.append([period / 2.0, 80.0, 96.0])
		uneven.append([period / 2.0, 96.0, 80.0])
	assert_eq(_ids(_detect(_values(uneven)), "rhythmus").size(), 0, "ungleiche Abstände")
	assert_eq(_ids(_detect(_pulses(8, 3.0, 80.0, 86.0)), "rhythmus").size(), 0, "Ausschlag 6 rpm ist zu klein")
	assert_eq(_ids(_detect(_pulses(10, 0.8, 80.0, 96.0)), "rhythmus").size(), 0, "zu schnell (Zittern)")
	assert_eq(_ids(_detect(_pulses(6, 6.0, 80.0, 96.0)), "rhythmus").size(), 0, "zu lahm")


func test_rhythmus_is_no_stop_and_go() -> void:
	assert_eq(_ids(_detect(_pulses(6, 3.0, 0.0, 60.0)), "rhythmus").size(), 0, "Tiefpunkt aus dem Stand")


func test_a_pulse_chain_with_a_gap_starts_over() -> void:
	var segments := [_hold(3.0, 80.0)]
	for i in range(3):
		segments.append([1.5, 80.0, 96.0])
		segments.append([1.5, 96.0, 80.0])
	segments.append(_hold(7.0, 80.0))  # der Takt reißt ab
	for i in range(3):
		segments.append([1.5, 80.0, 96.0])
		segments.append([1.5, 96.0, 80.0])
	assert_eq(_ids(_detect(_values(segments)), "rhythmus").size(), 0, "3 + 3 Pulse sind kein Takt aus 4")


# --- Schwellen ---------------------------------------------------------------------------------------------------


func test_thresholds_are_data_and_can_be_overridden() -> void:
	var rise := _values([_hold(6.0, 80.0), [2.0, 80.0, 100.0], _hold(3.0, 100.0)])  # +20
	assert_eq(_ids(_detect(rise), "antritt").size(), 0, "Standard: +25")
	assert_eq(_ids(_detect(rise, DT, {"antritt_rise_rpm": 15.0}), "antritt").size(), 1, "leichter eingestellt")
	assert_eq(CadencePatterns.new().thresholds["pause_hold_s"], 2.0)
	assert_eq(CadencePatterns.new({"pause_hold_s": 3.0}).thresholds["pause_hold_s"], 3.0)
	assert_eq(CadencePatterns.THRESHOLDS["pause_hold_s"], 2.0, "die Konstante bleibt")


func test_a_step_without_duration_counts_nothing_and_reset_starts_over() -> void:
	var patterns := CadencePatterns.new()
	assert_eq(patterns.feed(80.0, 0.0), [])
	for i in range(60):
		patterns.feed(80.0, DT)
	for i in range(5):
		patterns.feed(110.0, DT)
	patterns.reset()
	assert_eq(patterns.feed(140.0, DT), [], "nach reset gibt es keinen Verlauf mehr")
