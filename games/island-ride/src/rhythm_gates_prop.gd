## Darstellung der Takt-Tore (#48): je Taktschlag ein Tor (CourseGate aus #58) auf der Straße, dort wo der Fahrer zum Schlag
## ankommt (TimedMarkers/GatePlacement). Offene Tore tragen den Takt („Takt 2/5“, grün), ein getroffenes bleibt grün
## („Treffer“), ein verpasstes wird orange („Verpasst“). Gezeigt werden die nächsten drei offenen Tore, durchfahrene
## stehen bis `keep_behind_m` hinter dem Fahrer. Die Tore ersetzen das Zieltor. Nur Anzeige (ADR-0010).
class_name RhythmGatesProp
extends ArcadeProp

## So viele offene Tore stehen höchstens im Bild.
const AHEAD := 3

var gates: Array[CourseGate] = []
var markers := TimedMarkers.new()
var _block: RhythmGates = null


func begin(block: ChallengeBlock) -> void:
	_block = block as RhythmGates
	markers.reset(_block.beats)
	while gates.size() < _block.beats:
		var gate := CourseGate.new()
		gate.name = "TaktTor%d" % gates.size()
		gate.visible = false
		stage.track.add_child(gate)
		gates.append(gate)
	for i in range(gates.size()):
		gates[i].visible = false
		gates[i].ride_m = NAN
		if i < _block.beats:
			gates[i].configure(CourseGate.KIND_START, "Takt %d/%d" % [i + 1, _block.beats])


func follow(block: ChallengeBlock, _finish_at: float) -> bool:
	var rhythm := block as RhythmGates
	if rhythm != _block:
		return false
	var d: float = stage.distance_m
	markers.measure(d, rhythm.elapsed_s)
	var first := rhythm.next_open()
	for i in range(rhythm.beats):
		var gate := gates[i]
		match rhythm.state_of(i):
			RhythmGates.PENDING:
				if first >= 0 and i < first + AHEAD:
					_place(gate, markers.position_of(i, d, maxf(rhythm.time_to_beat(i), 0.0)))
					gate.visible = markers.placements[i].shown(d) and _behind_ok(gate)
				else:
					gate.visible = false
			RhythmGates.HIT:
				_place(gate, markers.position_of(i, d, maxf(rhythm.time_to_beat(i), 0.0)))
				gate.configure(CourseGate.KIND_START, "Treffer")
				gate.visible = _behind_ok(gate)
			_:
				_place(gate, markers.position_of(i, d, 0.0))
				gate.configure(CourseGate.KIND_FINISH, "Verpasst")
				gate.visible = _behind_ok(gate)
	return true  # das letzte Tor ist das Ziel


func idle() -> void:
	for gate in gates:
		if gate.visible:
			gate.visible = _behind_ok(gate)


func end(block: ChallengeBlock) -> void:
	var rhythm := block as RhythmGates
	if rhythm != _block:
		return
	for i in range(rhythm.beats):
		if rhythm.state_of(i) == RhythmGates.PENDING:
			gates[i].visible = false  # nicht mehr erreichbar: weg


func covers_finish_gate() -> bool:
	return gates.any(func(gate: CourseGate): return gate.visible)


func clear() -> void:
	_block = null
	hide()


func hide() -> void:
	for gate in gates:
		gate.visible = false
		gate.ride_m = NAN


func _place(gate: CourseGate, at_m: float) -> void:
	if not is_nan(at_m) and (is_nan(gate.ride_m) or not is_equal_approx(gate.ride_m, at_m)):
		gate.place(stage.track, at_m)


## Liegt das Tor noch höchstens `keep_behind_m` hinter dem Fahrer (und nicht eine ganze Runde voraus)?
func _behind_ok(gate: CourseGate) -> bool:
	var at := gate.ride_m
	return not is_nan(at) and at > stage.distance_m - stage.keep_behind_m \
			and at - stage.distance_m < stage.track.length_m() - stage.keep_behind_m
