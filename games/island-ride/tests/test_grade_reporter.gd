## Drosselung der `set_grade`-Meldungen als reine Logik: Schwelle 0,5 Prozentpunkte, höchstens 2/s.
extends GutTest

var reporter: GradeReporter


func before_each() -> void:
	reporter = GradeReporter.new()


func _send_if_wanted(grade: float) -> bool:
	if reporter.wants_to_send(grade):
		reporter.sent(grade)
		return true
	return false


func test_first_grade_is_sent_immediately() -> void:
	assert_true(_send_if_wanted(0.0))
	assert_eq(reporter.last_sent, 0.0)


func test_change_below_threshold_is_not_sent() -> void:
	_send_if_wanted(0.02)
	reporter.tick(1.0)
	assert_false(_send_if_wanted(0.024), "0,4 Prozentpunkte reichen nicht")
	assert_false(_send_if_wanted(0.016))
	assert_true(_send_if_wanted(0.025), "0,5 Prozentpunkte reichen")
	reporter.tick(1.0)
	assert_true(_send_if_wanted(0.02), "auch bergab-Änderung")


func test_at_most_two_per_second() -> void:
	var sent := 0
	var grade := 0.0
	for frame in range(120):  # 2 s bei 60 fps, Steigung ändert sich jedes Frame um 0,1 Prozentpunkte
		reporter.tick(1.0 / 60.0)
		grade += 0.001
		if _send_if_wanted(grade):
			sent += 1
	assert_between(sent, 3, 5, "≈ 2 pro Sekunde (erste sofort)")


func test_throttled_change_is_sent_with_current_value_when_interval_is_over() -> void:
	_send_if_wanted(0.0)
	reporter.tick(0.1)
	assert_false(_send_if_wanted(0.06), "gedrosselt")
	reporter.tick(0.4)
	assert_true(_send_if_wanted(0.061))
	assert_almost_eq(reporter.last_sent, 0.061, 1e-9)


func test_reset_resends_same_grade() -> void:
	_send_if_wanted(0.03)
	reporter.tick(1.0)
	assert_false(_send_if_wanted(0.03))
	reporter.reset()
	assert_true(_send_if_wanted(0.03), "nach Verbindungsverlust erneut melden")


func test_quantize_removes_noise_and_negative_zero() -> void:
	assert_almost_eq(GradeReporter.quantize(0.0599999), 0.06, 1e-9)
	assert_eq(str(GradeReporter.quantize(-0.00001)), "0.0")
