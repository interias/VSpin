## Medaillen-Schwellen (#33) als reine Logik: aus dem Fahrmodell berechnet (Bronze 70, Silber 85, Gold 95 rpm konstant)
## je Strecke und Segment, nicht eingetragen. Gold < Silber < Bronze, eine konstante Fahrt mit 85 rpm im Modell ergibt
## Silber, ein anderes Fahrmodell ergibt andere Schwellen.
extends GutTest

const DT := 1.0 / 60.0


func _island() -> Track:
	var track: Track = autofree(Track.new())
	IslandCourse.apply_to(track)
	return track


## Eine Runde mit konstanter Kadenz Schritt für Schritt (DT, wie ein Bild im Spiel) durch Fahrmodell und Rundenwertung
## – unabhängig von der Simulation in Medals. Liefert {Medals.LAP: s, "<segment-id>": s}.
func _ride_lap(track: Track, config: RideConfig, cadence: float) -> Dictionary:
	var model := RideModel.new(config)
	var timing := LapTiming.new(track.length_m(), 0.0, 1, INF, track.segments)
	while not timing.finished():
		model.step(cadence, track.grade_at(model.distance_m), DT)
		timing.advance(model.distance_m, DT)
	var times := {Medals.LAP: timing.lap_times[0]}
	for result in timing.segments.results:
		times[result["id"]] = result["time_s"]
	return times


func test_thresholds_for_lap_and_every_segment_in_order_gold_silver_bronze() -> void:
	var limits := Medals.thresholds(_island(), RideConfig.new())
	assert_eq(limits.keys(), [Medals.LAP, "kuestenwelle", "bergwertung", "dorfsprint"], "Runde und alle Segmente")
	for key in limits:
		var l: Dictionary = limits[key]
		assert_lt(l[Medals.GOLD], l[Medals.SILVER], "%s: Gold schneller als Silber" % key)
		assert_lt(l[Medals.SILVER], l[Medals.BRONZE], "%s: Silber schneller als Bronze" % key)
		assert_gt(l[Medals.GOLD], 0.0)
	assert_lt(limits["dorfsprint"][Medals.BRONZE], limits["bergwertung"][Medals.GOLD], "kurzer Sprint, lange Bergwertung")


func test_thresholds_are_the_times_of_the_ride_model_at_constant_cadence() -> void:
	var track := _island()
	var config := RideConfig.new()
	var limits := Medals.thresholds(track, config)
	for medal in Medals.ORDER:
		var ridden := _ride_lap(track, config, Medals.CADENCE_RPM[medal])
		for key in limits:
			assert_almost_eq(limits[key][medal], ridden[key], 0.1,
					"%s %s = Zeit bei konstant %d rpm" % [key, medal, Medals.CADENCE_RPM[medal]])
	# Grobe Probe gegen die Formel des Fahrmodells: flach k · Kadenz.
	var flat_kmh := config.k_kmh_per_rpm * 85.0
	assert_gt(limits[Medals.LAP][Medals.SILVER], track.length_m() / (flat_kmh * 1.3 / 3.6), "plausibel langsam")
	assert_lt(limits[Medals.LAP][Medals.SILVER], track.length_m() / (flat_kmh * 0.5 / 3.6), "plausibel schnell")


func test_steady_85_rpm_earns_silver_not_gold() -> void:
	var track := _island()
	var config := RideConfig.new()
	var limits := Medals.thresholds(track, config)
	var expected := {70.0: Medals.BRONZE, 85.0: Medals.SILVER, 95.0: Medals.GOLD, 60.0: Medals.NONE, 100.0: Medals.GOLD}
	for cadence in expected:
		var ridden := _ride_lap(track, config, cadence)
		for key in limits:
			assert_eq(Medals.medal_for(ridden[key], limits[key]), expected[cadence], "%s bei %d rpm" % [key, cadence])


func test_thresholds_follow_the_ride_model() -> void:
	var track := _island()
	var base := Medals.thresholds(track, RideConfig.new())
	var faster_bike := RideConfig.new()
	faster_bike.k_kmh_per_rpm = 0.4
	var faster := Medals.thresholds(track, faster_bike)
	for key in base:
		assert_lt(faster[key][Medals.SILVER], base[key][Medals.SILVER], "%s: größeres k → kürzere Schwelle" % key)
	var steeper := RideConfig.new()
	steeper.uphill_damping = 12.0
	var climb := Medals.thresholds(track, steeper)
	assert_gt(climb["bergwertung"][Medals.GOLD], base["bergwertung"][Medals.GOLD], "stärker gedämpft bergauf → länger")
	assert_eq(Medals.thresholds(track, RideConfig.new()), base, "gleiches Modell → gleiche Schwellen")


func test_graybox_has_lap_thresholds_only() -> void:
	var track: Track = autofree(GrayboxTrack.new())
	var limits := Medals.thresholds(track, RideConfig.new())
	assert_eq(limits.keys(), [Medals.LAP], "keine Segmente auf der Graybox")
	assert_lt(limits[Medals.LAP][Medals.GOLD], limits[Medals.LAP][Medals.BRONZE])


func test_medal_for_rank_and_names() -> void:
	var limits := {Medals.GOLD: 100.0, Medals.SILVER: 110.0, Medals.BRONZE: 130.0}
	assert_eq(Medals.medal_for(99.0, limits), Medals.GOLD)
	assert_eq(Medals.medal_for(100.0, limits), Medals.GOLD, "genau auf der Schwelle")
	assert_eq(Medals.medal_for(105.0, limits), Medals.SILVER)
	assert_eq(Medals.medal_for(130.0, limits), Medals.BRONZE)
	assert_eq(Medals.medal_for(131.0, limits), Medals.NONE, "zu langsam")
	assert_eq(Medals.medal_for(10.0, {}), Medals.NONE, "ohne Schwellen keine Medaille")
	assert_gt(Medals.rank(Medals.GOLD), Medals.rank(Medals.SILVER))
	assert_gt(Medals.rank(Medals.SILVER), Medals.rank(Medals.BRONZE))
	assert_gt(Medals.rank(Medals.BRONZE), Medals.rank(Medals.NONE))
	assert_eq(Medals.rank("platin"), 0, "Unbekanntes zählt nicht")
	assert_eq([Medals.name_of(Medals.GOLD), Medals.name_of(Medals.SILVER), Medals.name_of(Medals.BRONZE)],
			["Gold", "Silber", "Bronze"])
	assert_eq(Medals.name_of(Medals.NONE), "")


func test_summary_lists_up_to_five_laps_one_by_one() -> void:
	assert_eq(Medals.summary([Medals.GOLD]), "Gold")
	assert_eq(Medals.summary([Medals.SILVER, Medals.NONE, Medals.GOLD, Medals.BRONZE, Medals.GOLD]),
			"Silber · – · Gold · Bronze · Gold", "fünf Runden einzeln, in Fahrtreihenfolge")


func test_summary_counts_from_six_laps_best_first_without_empty_tiers() -> void:
	var medals := []
	for i in range(20):
		medals.append(Medals.GOLD if i % 5 < 3 else Medals.SILVER)
	assert_eq(Medals.summary(medals), "12× Gold · 8× Silber", "gezählt, beste zuerst, ohne Bronze")
	assert_eq(Medals.summary([Medals.NONE, Medals.BRONZE, Medals.NONE, Medals.GOLD, Medals.NONE, Medals.BRONZE]),
			"1× Gold · 2× Bronze · 3× ohne", "Runden ohne Medaille zuletzt")
