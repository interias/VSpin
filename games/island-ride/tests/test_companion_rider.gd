## Toni fährt mit (Spec #91), reine Logik `CompanionRider`: Abstand längs (−1…+3 m) und seitlich (immer neben dem Fahrer,
## nie in dessen Fahrlinie) über eine ganze Insel-Runde mit Anstieg und Abfahrt, deterministisch, Zurückfallen und
## Aufschließen, bergauf zurück und bergab vor; Reden dreht den Kopf und löst eine Hand, ohne Reden bleibt alles still.
extends "res://tests/support/bus_test.gd"

const DT := 0.1
## Tempo der Rundenprobe (m/s).
const SPEED_MPS := 10.0


## Die Insel-Strecke aus der Hauptszene (nur die Strecke, keine Fahrt).
func _island_track() -> Track:
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus, 0.0, config_for(bus, RideConfig.DEFAULT_PATH, RideConfig.TRACK_ISLAND))
	return ride.track


## Eine ganze Runde mit 10 m/s: Liste von {grade, long, lateral}.
func _lap(track: Track) -> Array:
	var rider := CompanionRider.new()
	var samples: Array = []
	var d := 0.0
	while d < track.length_m():
		var grade := track.grade_at(d)
		rider.advance(DT, grade)
		samples.append({"grade": grade, "long": rider.longitudinal_m(), "lateral": rider.lateral_m()})
		d += SPEED_MPS * DT
	return samples


func test_whole_lap_stays_within_the_limits_and_never_in_the_riding_line() -> void:
	var track := _island_track()
	var samples := _lap(track)
	assert_gt(samples.size(), 500, "eine ganze Runde")
	assert_eq(CompanionRider.LONG_MIN_M, -1.0, "Spec: längs ab 1 m hinter dem Fahrer")
	assert_eq(CompanionRider.LONG_MAX_M, 3.0, "Spec: bis 3 m vor dem Fahrer")
	var steepest_up := 0.0
	var steepest_down := 0.0
	for sample in samples:
		assert_between(sample["long"], CompanionRider.LONG_MIN_M, CompanionRider.LONG_MAX_M, "längs −1…+3 m")
		assert_between(sample["lateral"], CompanionRider.LATERAL_M - CompanionRider.LATERAL_SWAY_M,
				CompanionRider.LATERAL_M + CompanionRider.LATERAL_SWAY_M, "seitlich um 1,5 m")
		assert_gt(sample["lateral"], 1.2, "nie in der Fahrlinie des Fahrers (seitlich 0)")
		steepest_up = maxf(steepest_up, sample["grade"])
		steepest_down = minf(steepest_down, sample["grade"])
	assert_gt(steepest_up, 0.05, "die Runde hat einen Anstieg")
	assert_lt(steepest_down, -0.03, "und eine Abfahrt")


func test_falls_back_uphill_and_goes_ahead_downhill() -> void:
	var track := _island_track()
	var up := []
	var down := []
	for sample in _lap(track):
		if sample["grade"] > 0.05:
			up.append(sample["long"])
		elif sample["grade"] < -0.03:
			down.append(sample["long"])
	assert_gt(up.size(), 20)
	assert_gt(down.size(), 20)
	assert_lt(_mean(up), _mean(down) - 0.5, "am Anstieg weiter zurück als in der Abfahrt")
	assert_lt(_mean(up), CompanionRider.LONG_CENTER_M, "am Anstieg hinter der Mitte")
	assert_gt(_mean(down), CompanionRider.LONG_CENTER_M, "bergab vor der Mitte")


func test_falls_back_and_catches_up_on_the_flat_and_is_deterministic() -> void:
	var rider := CompanionRider.new()
	var first: Array[float] = []
	for i in range(int(120.0 / DT)):
		rider.advance(DT, 0.0)
		first.append(rider.longitudinal_m())
	assert_lt(first.min(), CompanionRider.LONG_CENTER_M - 0.5, "fällt zurück")
	assert_gt(first.max(), CompanionRider.LONG_CENTER_M + 0.5, "schließt wieder auf und fährt etwas vor")
	var again := CompanionRider.new()
	for i in range(first.size()):
		again.advance(DT, 0.0)
		assert_eq(again.longitudinal_m(), first[i], "kein Zufall: dieselbe Fahrt, dieselbe Bewegung")
	# Ruhig: keine Sprünge zwischen zwei Schritten.
	for i in range(1, first.size()):
		assert_lt(absf(first[i] - first[i - 1]), 0.05, "weiche Schwankung")
	rider.reset()
	assert_eq(rider.longitudinal_m(), CompanionRider.new().longitudinal_m(), "reset")


func test_pause_freezes_the_swing() -> void:
	var rider := CompanionRider.new()
	rider.advance(5.0, 0.0)
	var at := rider.longitudinal_m()
	rider.advance(5.0, 0.0, false)
	assert_eq(rider.longitudinal_m(), at, "in der Pause steht er")
	assert_eq(rider.longitudinal_speed_mps(), 0.0)


func test_speaking_turns_the_head_and_lifts_a_hand_and_silence_stops_it() -> void:
	var rider := CompanionRider.new()
	rider.advance(1.0, 0.0)
	assert_eq(rider.head_turn_rad(), 0.0, "stumm: Blick nach vorn")
	assert_eq(rider.hand_raise(), 0.0, "stumm: beide Hände am Lenker")
	rider.set_speaking(true)
	var raises := []
	for i in range(30):
		rider.advance(DT, 0.0)
		raises.append(rider.hand_raise())
	assert_almost_eq(rider.head_turn_rad(), CompanionRider.HEAD_TURN_MAX_RAD, 0.01, "Kopf zum Fahrer")
	assert_gt(rider.head_turn_rad(), 0.3)
	assert_between(raises.max(), 0.9, 1.0, "Hand gelöst")
	assert_lt(raises.slice(10).min(), raises.slice(10).max() - 0.1, "mit leichtem Auf und Ab (dezente Geste)")
	rider.set_speaking(false)
	for i in range(30):
		rider.advance(DT, 0.0)
	assert_almost_eq(rider.head_turn_rad(), 0.0, 0.001, "wieder nach vorn")
	assert_almost_eq(rider.hand_raise(), 0.0, 0.001, "Hand wieder am Lenker")


func _mean(values: Array) -> float:
	var sum := 0.0
	for value in values:
		sum += value
	return sum / values.size()
