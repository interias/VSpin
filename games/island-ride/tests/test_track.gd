## Graybox-Strecke: Steigung je Streckenposition ablesbar (ein Anstieg, eine Abfahrt).
extends GutTest

## Streckenpositionen in der Mitte der Abschnitte (siehe GrayboxTrack.PROFILE).
const FLAT_M := 60.0
const CLIMB_M := 275.0
const DESCENT_M := 640.0

var track: GrayboxTrack


func before_each() -> void:
	track = autofree(GrayboxTrack.new())


func test_track_is_a_round_course() -> void:
	assert_gt(track.length_m(), 850.0)
	assert_almost_eq(track.position_at(0.0).distance_to(track.position_at(track.length_m())), 0.0, 0.5)


func test_grade_on_flat_climb_and_descent() -> void:
	assert_almost_eq(track.grade_at(FLAT_M), 0.0, 0.001)
	assert_almost_eq(track.grade_at(CLIMB_M), 0.06, 0.002)
	assert_almost_eq(track.grade_at(DESCENT_M), -0.06, 0.002)


func test_grade_wraps_around_the_lap() -> void:
	assert_almost_eq(track.grade_at(CLIMB_M + track.length_m()), track.grade_at(CLIMB_M), 0.0001)
	assert_almost_eq(track.wrap_distance(-10.0), track.length_m() - 10.0, 0.0001)


func test_grade_matches_height_change() -> void:
	var a := track.position_at(CLIMB_M - 20.0)
	var b := track.position_at(CLIMB_M + 20.0)
	assert_gt(b.y, a.y, "Anstieg: Höhe nimmt zu")
	var c := track.position_at(DESCENT_M - 20.0)
	var d := track.position_at(DESCENT_M + 20.0)
	assert_lt(d.y, c.y, "Abfahrt: Höhe nimmt ab")
