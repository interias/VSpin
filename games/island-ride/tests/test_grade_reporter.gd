## Drosselung der `set_grade`-Meldungen als reine Logik: Schwelle 0,5 Prozentpunkte, höchstens 2/s, Endwert.
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


## Wie in der Hauptszene: je Frame Zeit vergehen lassen und ggf. senden; liefert die gesendeten Werte.
func _ride_frames(grade: float, seconds: float) -> Array:
	var sent: Array = []
	for frame in range(roundi(seconds * 60.0)):
		reporter.tick(1.0 / 60.0)
		if _send_if_wanted(grade):
			sent.append(reporter.last_sent)
	return sent


func test_settled_grade_below_threshold_is_sent_once() -> void:
	# Rampe 0 → 6 %: die letzte Meldung liegt unter 6 %, danach bleibt die Steigung stehen.
	_send_if_wanted(0.0)
	reporter.tick(0.6)
	assert_true(_send_if_wanted(0.056))
	assert_eq(_ride_frames(0.06, 0.9), [], "noch nicht lange genug ruhig")
	assert_eq(_ride_frames(0.06, 0.3), [GradeReporter.quantize(0.06)], "nach 1 s Ruhe den Endwert nachsenden")
	assert_eq(_ride_frames(0.06, 3.0), [], "nur einmal")


func test_settled_resend_is_only_once_per_quiet_phase() -> void:
	_send_if_wanted(0.02)
	assert_eq(_ride_frames(0.023, 1.5), [GradeReporter.quantize(0.023)])
	assert_eq(_ride_frames(0.026, 2.0), [], "kleine Drift danach: nicht erneut (Abweichung < Schwelle)")
	assert_eq(_ride_frames(0.019, 1.5), [GradeReporter.quantize(0.019)],
			"neue Bewegung über die Schwelle → neue Ruhephase")


func test_moving_grade_is_not_resent_as_settled() -> void:
	_send_if_wanted(0.0)
	var sent: Array = []
	var expected: Array = []
	for step in range(1, 11):  # alle 0,6 s 0,6 Prozentpunkte weiter: nie 1 s ruhig
		sent += _ride_frames(step * 0.006, 0.6)
		expected.append(GradeReporter.quantize(step * 0.006))
	assert_eq(sent, expected, "nur Schwellen-Meldungen, kein Nachsenden")


func test_quantize_removes_noise_and_negative_zero() -> void:
	assert_almost_eq(GradeReporter.quantize(0.0599999), 0.06, 1e-9)
	assert_eq(str(GradeReporter.quantize(-0.00001)), "0.0")
