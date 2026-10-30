## Toni fährt mit (Spec #91) in der Hauptszene gegen den Fake-Bus: Figur nur mit Begleiter am Bus und beiden Schaltern an,
## in Rundfahrt/Arcade (nicht im Training); rechts vom Fahrer (der Ghost fährt links), eigene Farben deckend; bleibt in der
## Fahrt längs −1…+3 m und seitlich neben dem Fahrer; Kopf und Hand folgen `speaking`, bei „heiser“ fährt er stumm weiter;
## ohne Begleiter (Prozess/Bus weg) verschwindet er. Nur Darstellung (ADR-0010): die Fahrt läuft mit und ohne Toni gleich.
extends "res://tests/support/bus_test.gd"

const RIDING := "riding"


func _status(state: String, at: float, speaking = null) -> Dictionary:
	return {"at": at, "send": {"v": 0, "type": "companion_status", "state": state,
			"speaking": (state == "speaking") if speaking == null else speaking}}


func _script(extra: Array = [], to_s := 40.0) -> Array:
	return [FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, to_s) + extra


func _spawn(extra: Array = [], to_s := 40.0) -> Node:
	var bus := start_fake_bus(_script(extra, to_s))
	var ride := spawn_ride(bus)
	assert_true(await run_until(func(): return ride.state == RIDING, 3.0), "Fahrt läuft")
	return ride


## Tonis Lage in den Koordinaten des Fahrers: x seitlich (rechts +), z längs (vor dem Fahrer −).
func _local(ride: Node) -> Vector3:
	return ride.rider_model.global_transform.affine_inverse() * ride.companion_model.global_position


func test_no_figure_without_a_companion_on_the_bus() -> void:
	var ride := await _spawn()
	await run_for(0.8)
	assert_false(ride.bus.companion_seen)
	assert_false(ride.companion_rider_visible())
	assert_false(ride.companion_follower.visible, "ohne Begleiter keine Figur")


func test_figure_rides_right_of_the_rider_in_own_colors_opaque() -> void:
	var ride := await _spawn([_status("idle", 0.3)])
	assert_true(await run_until(func(): return ride.companion_follower.visible, 3.0), "Toni fährt mit")
	assert_true(ride.companion_follower.is_visible_in_tree())
	assert_gt(ride.companion_follower.h_offset, 1.2, "rechts (der Ghost fährt links)")
	assert_lt(ride.ghost_rider.h_offset, 0.0, "Ghost links")
	var jersey: Color = ride.companion_model.material_color("jersey")
	assert_eq(jersey, CompanionRider.OUTFIT["jersey"], "eigene Trikotfarbe")
	assert_ne(jersey, ride.rider_model.material_color("jersey"), "nicht die des Fahrers")
	var mesh: MeshInstance3D = ride.companion_model.find_children("*", "MeshInstance3D", true, false)[0]
	assert_eq((mesh.material_override as StandardMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"deckend, anders als der halbtransparente Ghost")
	assert_eq(ride.companion_model.find_children("*", "MeshInstance3D", true, false).size(),
			ride.ghost_model.find_children("*", "MeshInstance3D", true, false).size(), "gleiches Modell wie der Ghost")


func test_stays_beside_and_never_far_ahead_while_riding() -> void:
	var ride := await _spawn([_status("idle", 0.3)])
	assert_true(await run_until(func(): return ride.companion_follower.visible, 3.0))
	var min_z := INF
	var max_z := -INF
	var min_x := INF
	for i in range(240):
		await get_tree().process_frame
		var at := _local(ride)
		min_z = minf(min_z, at.z)
		max_z = maxf(max_z, at.z)
		min_x = minf(min_x, at.x)
	assert_gt(min_z, -3.3, "längs nie mehr als +3 m vor dem Fahrer")
	assert_lt(max_z, 1.3, "nie mehr als 1 m dahinter")
	assert_gt(min_x, 1.0, "immer rechts neben dem Fahrer, nie in der Fahrlinie")


func test_switches_hide_the_figure() -> void:
	var ride := await _spawn([_status("idle", 0.3)])
	assert_true(await run_until(func(): return ride.companion_follower.visible, 3.0))
	ride.settings_menu.settings.companion_rides = false
	await run_for(0.1)
	assert_false(ride.companion_follower.visible, "„Toni fährt mit“ aus")
	ride.settings_menu.settings.companion_rides = true
	await run_for(0.1)
	assert_true(ride.companion_follower.visible)
	ride.settings_menu.settings.companion_enabled = false
	await run_for(0.1)
	assert_false(ride.companion_follower.visible, "„Begleiter“ aus")
	ride.settings_menu.settings.companion_enabled = true


func test_not_in_training_and_not_in_the_menu() -> void:
	var ride := await _spawn([_status("idle", 0.3)])
	assert_true(await run_until(func(): return ride.companion_follower.visible, 3.0))
	ride.ride_mode = SaveGame.MODE_TRAINING
	await run_for(0.1)
	assert_false(ride.companion_follower.visible, "im Training nicht")
	ride.ride_mode = SaveGame.MODE_ARCADE
	await run_for(0.1)
	assert_true(ride.companion_follower.visible, "Arcade: ja")
	ride._enter_menu()
	await run_for(0.1)
	assert_false(ride.companion_follower.visible, "im Menü nicht")


func test_gone_with_the_bus() -> void:
	var ride := await _spawn([_status("idle", 0.3), FakeBusServer.close_at(2.0)], 60.0)
	assert_true(await run_until(func(): return ride.companion_follower.visible, 3.0))
	assert_true(await run_until(func(): return not ride.bus.companion_seen, 5.0), "Bus weg: kein Begleiter mehr")
	await run_for(0.1)
	assert_false(ride.companion_follower.visible, "Prozess/Bus weg: keine Figur")


func test_speaking_turns_head_and_lifts_hand_and_hoarse_rides_on_silent() -> void:
	var ride := await _spawn([_status("idle", 0.3), _status("speaking", 1.0), _status("idle", 3.0),
			_status("hoarse", 4.0, true)])
	assert_true(await run_until(func(): return ride.bus.companion_speaking, 3.0), "Toni spricht")
	assert_true(await run_until(func(): return ride.companion_rider.head_turn_rad() > 0.3, 2.0), "Kopf zum Fahrer")
	assert_gt(ride.companion_rider.hand_raise(), 0.4, "Hand gelöst")
	var head: Node3D = ride.companion_model.find_child("Head", true, false)
	assert_gt(absf(head.rotation.y), 0.1, "Kopf der Figur gedreht")
	var rest_head: Node3D = ride.rider_model.find_child("Head", true, false)
	assert_almost_eq(rest_head.rotation.y, 0.0, 0.001, "der Fahrer dreht den Kopf nicht")
	var hand: Node3D = ride.companion_model.find_child("Hand1", true, false)
	var rest_hand: Node3D = ride.rider_model.find_child("Hand1", true, false)
	assert_gt(hand.position.distance_to(rest_hand.position), 0.1, "linke Hand weg vom Lenker")
	assert_true(await run_until(func(): return not ride.bus.companion_speaking, 4.0), "verstummt")
	assert_true(await run_until(func(): return ride.companion_rider.head_turn_rad() < 0.01, 2.0), "Kopf wieder vorn")
	assert_true(await run_until(func(): return ride.bus.companion_state == "hoarse", 3.0), "heiser")
	await run_for(1.0)
	assert_true(ride.companion_follower.visible, "bei heiser bleibt er sichtbar")
	assert_almost_eq(ride.companion_rider.head_turn_rad(), 0.0, 0.01, "und fährt stumm weiter, ohne Geste")
	assert_almost_eq(ride.companion_rider.hand_raise(), 0.0, 0.01)
	assert_eq(ride.state, RIDING)


func test_rides_right_and_looks_at_the_rider_in_both_directions() -> void:
	var ride := await _spawn([_status("idle", 0.3), _status("speaking", 1.0), _status("idle", 30.0)])
	assert_true(await run_until(func(): return ride.bus.companion_speaking, 3.0), "Toni spricht")
	for direction in [Track.DIRECTION_CW, Track.DIRECTION_CCW]:
		ride._set_direction(direction)
		await run_for(0.4)
		assert_gt(_local(ride).x, 1.0, "rechts vom Fahrer, Richtung %s" % direction)
		var head: Node3D = ride.companion_model.find_child("Head", true, false)
		var gaze: Vector3 = head.global_transform.basis * Vector3.FORWARD
		var to_rider: Vector3 = -ride.rider_model.global_transform.basis.x
		assert_gt(gaze.dot(to_rider), 0.3, "Kopf dreht sich zum Fahrer hin, Richtung %s" % direction)


func test_ride_is_the_same_with_and_without_toni() -> void:
	var with_toni := await _spawn([_status("idle", 0.3)])
	var without := await _spawn()
	var start_with: float = with_toni.model.distance_m
	var start_without: float = without.model.distance_m
	await run_for(3.0)
	assert_false(without.companion_follower.visible)
	assert_true(with_toni.companion_follower.visible)
	var ridden: float = without.model.distance_m - start_without
	assert_gt(ridden, 10.0)
	assert_almost_eq(with_toni.model.distance_m - start_with, ridden, ridden * 0.15, "Toni ändert nichts an der Fahrt")
