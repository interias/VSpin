## Der Launcher startet den Begleiter mit (Spec #76, #80): nur wenn er gewünscht ist und das Spiel die Bridge selbst
## gestartet hat, nie neben einem schon gemeldeten Begleiter, mit `-m vspin_companion --port … --stop-file …`; Ausschalten
## beendet nur den eigenen sauber über die Stoppdatei, ohne zu blocken; beim Schließen vor der Bridge. Prozesse laufen
## über einen Fake – nie ein echter Python-Prozess, nie Port 8765.
extends "res://tests/support/bus_test.gd"

const BRIDGE_STOP := "test_companion_launcher_bridge.stop"
const COMPANION_STOP := "test_companion_launcher_companion.stop"
const BASE_DIR := "C:/vspin/games/island-ride"


## Fake-Prozesse: jeder Start merkt sich seine Stoppdatei aus `--stop-file`; ein Prozess endet sauber, sobald sie existiert.
class FakeProcesses:
	extends BridgeLauncher.Processes

	var started: Array = []  # je Start [program, args]
	var running := {}
	var stop_files := {}
	var parent_env: Array = []  # je Start der Wert von VSPIN_COMPANION_PARENT_PID in diesem Moment
	var killed: Array = []
	var ignores_stop := false
	var missing_programs: Array = []  # Programme, die `program_exists` nicht findet

	func start(program: String, args: PackedStringArray) -> int:
		started.append([program, args])
		parent_env.append(OS.get_environment(BridgeLauncher.COMPANION_PARENT_ENV))
		var pid := 5000 + started.size()
		running[pid] = true
		var at := args.find("--stop-file")
		stop_files[pid] = args[at + 1] if at >= 0 else ""
		return pid

	func is_running(pid: int) -> bool:
		if running.get(pid, false) and not ignores_stop and not stop_files[pid].is_empty() \
				and FileAccess.file_exists(stop_files[pid]):
			DirAccess.remove_absolute(stop_files[pid])
			running[pid] = false
		return running.get(pid, false)

	func kill(pid: int) -> void:
		killed.append(pid)
		running[pid] = false

	func program_exists(path: String) -> bool:
		return path not in missing_programs


var processes: FakeProcesses


func before_each() -> void:
	OS.unset_environment(BridgeLauncher.COMPANION_PARENT_ENV)
	processes = FakeProcesses.new()


func after_all() -> void:
	OS.unset_environment(BridgeLauncher.COMPANION_PARENT_ENV)


func after_each() -> void:
	super.after_each()
	for file_name in [BRIDGE_STOP, COMPANION_STOP]:
		if FileAccess.file_exists(TestIsolation.path(file_name)):
			DirAccess.remove_absolute(TestIsolation.path(file_name))


func _closed_port() -> int:
	var bus := start_fake_bus([])
	bus.stop()
	_buses.erase(bus)
	return bus.port


func _launcher(port: int, platform_ok := true, config := RideConfig.new()) -> BridgeLauncher:
	config.bus_url = "ws://127.0.0.1:%d" % port
	return BridgeLauncher.new(config, BASE_DIR, processes, platform_ok, TestIsolation.path(BRIDGE_STOP), port,
			TestIsolation.path(COMPANION_STOP))


## Treibt `launcher` bis zum Ende der Erreichbarkeitsprüfung (echte TCP-Verbindung).
func _settle(launcher: BridgeLauncher) -> void:
	launcher.begin()
	var start := Time.get_ticks_msec()
	while launcher.state == BridgeLauncher.STATE_PROBING and Time.get_ticks_msec() - start < 5000:
		await run_for(0.02)
		launcher.poll(0.02)


## Launcher mit eigener Bridge (Port ohne Bridge → Start), Begleiter noch nicht gewünscht.
func _own_bridge(port: int) -> BridgeLauncher:
	var launcher := _launcher(port)
	await _settle(launcher)
	return launcher


func test_companion_starts_with_own_bridge_when_wanted() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	assert_eq(launcher.state, BridgeLauncher.STATE_OWN)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 1, "ohne Wunsch nur die Bridge")
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2, "Begleiter gestartet")
	var program: String = processes.started[1][0]
	var args: PackedStringArray = processes.started[1][1]
	assert_eq(program, "C:/vspin/bridge/.venv-companion/Scripts/pythonw.exe", "das eigene venv des Begleiters")
	assert_eq(processes.started[0][0], "C:/vspin/bridge/.venv/Scripts/pythonw.exe", "die Bridge behält ihr Programm")
	assert_ne(program, processes.started[0][0], "nie das Python der Bridge")
	assert_eq(args, PackedStringArray(["-m", "vspin_companion", "--port", str(port), "--stop-file",
			ProjectSettings.globalize_path(TestIsolation.path(COMPANION_STOP))]))
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2, "nicht noch einmal")
	assert_true(launcher.stop())


func test_companion_gets_the_parent_pid_in_its_environment_but_the_bridge_does_not() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.parent_env[0], "", "die Bridge bekommt die Variable nicht")
	assert_eq(processes.parent_env[1], str(OS.get_process_id()), "der Begleiter schon: die PID des Spiels")
	assert_eq(processes.started[1][1].size(), 6, "kein zusätzliches CLI-Argument")
	assert_true(launcher.stop())


func test_no_companion_next_to_a_shared_bridge_or_a_present_companion() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var shared := _launcher(bus.port)
	await _settle(shared)
	assert_eq(shared.state, BridgeLauncher.STATE_SHARED)
	shared.set_companion(true, false)
	shared.poll(0.1)
	assert_eq(processes.started, [], "mitbenutzte Bridge: der Begleiter gehört dem, der sie gestartet hat")
	var port := _closed_port()
	var own := await _own_bridge(port)
	own.set_companion(true, true)  # ein Begleiter ist schon am Bus
	own.poll(0.1)
	assert_eq(processes.started.size(), 1, "nie zwei Tonis")
	assert_true(own.stop())


func test_no_companion_on_web() -> void:
	var port := _closed_port()
	var web := _launcher(port, false)
	web.begin()
	web.set_companion(true, false)
	web.poll(BridgeLauncher.PROBE_TIMEOUT_S)
	assert_eq(processes.started, [])
	assert_true(web.stop())


func test_switching_off_stops_only_the_own_companion_without_blocking() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	var pid := launcher.companion_pid
	assert_gt(pid, 0)
	launcher.set_companion(false, true)
	launcher.poll(0.1)
	assert_true(FileAccess.file_exists(TestIsolation.path(COMPANION_STOP)), "Stoppdatei geschrieben")
	launcher.poll(0.1)
	assert_eq(launcher.companion_pid, -1, "beendet")
	assert_false(processes.running[pid])
	assert_eq(processes.killed, [], "sauber, nicht hart")
	assert_true(processes.running[launcher.pid], "die Bridge läuft weiter")
	launcher.set_companion(true, false)  # wieder an: neuer Start
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 3, "Bridge, Begleiter, Begleiter")
	assert_true(launcher.stop())


func test_hanging_companion_is_killed_after_the_timeout() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	var pid := launcher.companion_pid
	processes.ignores_stop = true
	launcher.set_companion(false, false)
	launcher.poll(0.1)
	launcher.poll(BridgeLauncher.STOP_TIMEOUT_S)
	assert_eq(processes.killed, [pid], "erst nach der Wartezeit hart")
	assert_eq(launcher.companion_pid, -1)
	processes.ignores_stop = false
	assert_true(launcher.stop())


func test_closing_the_game_stops_companion_then_bridge_cleanly() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	var companion := launcher.companion_pid
	var bridge := launcher.pid
	assert_true(launcher.stop(), "sauber beendet")
	assert_false(processes.running[companion])
	assert_false(processes.running[bridge])
	assert_eq(processes.killed, [])
	assert_eq(launcher.companion_pid, -1)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2, "nach dem Schließen startet nichts mehr")


func test_companion_that_exits_is_not_restarted_until_switched_off_and_on() -> void:
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	processes.running[launcher.companion_pid] = false  # z. B. die Konfiguration des Begleiters ist ungültig
	launcher.poll(BridgeLauncher.WATCH_INTERVAL_S)
	assert_true(launcher.companion_failed)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2, "kein Neustart in Dauerschleife")
	launcher.set_companion(false, false)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 3, "aus und an versucht es neu")
	assert_true(launcher.stop())


func test_companion_program_comes_from_config_and_the_bridge_keeps_its_own() -> void:
	var port := _closed_port()
	var config := RideConfig.new()
	config.bridge_program = "C:/py/bridge/pythonw.exe"
	config.companion_program = "D:/py/companion/pythonw.exe"
	var launcher := _launcher(port, true, config)
	await _settle(launcher)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2)
	assert_eq(processes.started[0][0], "C:/py/bridge/pythonw.exe")
	assert_eq(processes.started[1][0], "D:/py/companion/pythonw.exe")
	assert_true(launcher.stop())


func test_companion_program_defaults_to_its_own_venv_without_the_key() -> void:
	var from_file := RideConfig.load_file("res://tests/fixtures/partial.cfg")
	assert_eq(from_file.companion_program, "../../bridge/.venv-companion/Scripts/pythonw.exe")
	var port := _closed_port()
	var launcher := _launcher(port, true, from_file)
	assert_eq(launcher.companion_program, "C:/vspin/bridge/.venv-companion/Scripts/pythonw.exe")


func test_relative_companion_program_is_resolved_from_the_game_folder() -> void:
	var config := RideConfig.new()
	config.companion_program = "tools/py/pythonw.exe"
	assert_eq(_launcher(_closed_port(), true, config).companion_program, BASE_DIR + "/tools/py/pythonw.exe")
	config.companion_program = "../venv/pythonw.exe"
	assert_eq(_launcher(_closed_port(), true, config).companion_program, "C:/vspin/games/venv/pythonw.exe")


func test_missing_companion_program_starts_no_companion_but_the_bridge_runs_and_does_not_retry() -> void:
	# Die Warnung (push_warning) lässt sich in GUT hier nicht abfangen; sichtbar ist `companion_failed`.
	var port := _closed_port()
	var launcher := await _own_bridge(port)
	processes.missing_programs = [launcher.companion_program]
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 1, "nur die Bridge, kein Begleiter")
	assert_eq(launcher.companion_pid, -1)
	assert_true(launcher.companion_failed)
	assert_eq(launcher.state, BridgeLauncher.STATE_OWN, "die Bridge läuft weiter")
	for i in 5:
		launcher.poll(1.0)
	assert_eq(processes.started.size(), 1, "kein neuer Versuch")
	processes.missing_programs = []
	launcher.set_companion(false, false)
	launcher.set_companion(true, false)
	launcher.poll(0.1)
	assert_eq(processes.started.size(), 2, "aus und an versucht es neu")
	assert_true(launcher.stop())


func test_main_scene_at_a_fake_bus_starts_nothing() -> void:
	# Das Spiel am Fake-Bus (nicht Port 8765): der Launcher ist aus, es startet weder Bridge noch Begleiter.
	var bus := start_fake_bus([FakeBusServer.status()])
	var ride := spawn_ride(bus)
	await run_for(0.3)
	assert_eq(ride.bridge_launcher.state, BridgeLauncher.STATE_OFF)
	assert_eq(ride.bridge_launcher.companion_pid, -1)
