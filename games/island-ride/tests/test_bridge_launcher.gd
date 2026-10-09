## Bridge aus dem Spiel starten (#25, BridgeLauncher): erkennen, starten, mitbenutzen, nur die eigene sauber beenden.
## Die Erreichbarkeit prüft der Launcher echt per TCP (Fake-Bus bzw. freier Port), Prozesse laufen über einen
## Fake-Prozess – nie eine echte Bridge, nie Port 8765.
extends "res://tests/support/bus_test.gd"

const STOP_FILE := "user://test_bridge_launcher.stop"
const BASE_DIR := "C:/vspin/games/island-ride"


## Fake-Prozessstarter: merkt sich Starts; eine „Bridge“ endet sauber, sobald die Stoppdatei existiert, und räumt sie
## weg – wie `vspin-bridge --stop-file`. `ignores_stop`: hängende Bridge.
class FakeProcesses:
	extends BridgeLauncher.Processes

	var started: Array = []  # je Start [program, args]
	var running := {}  # pid → bool
	var killed: Array = []
	var stopped_cleanly: Array = []
	var exists := true
	var ignores_stop := false
	var stop_file := ProjectSettings.globalize_path(STOP_FILE)

	func start(program: String, args: PackedStringArray) -> int:
		started.append([program, args])
		var pid := 4000 + started.size()
		running[pid] = true
		return pid

	func is_running(pid: int) -> bool:
		if running.get(pid, false) and not ignores_stop and FileAccess.file_exists(stop_file):
			DirAccess.remove_absolute(stop_file)
			running[pid] = false
			stopped_cleanly.append(pid)
		return running.get(pid, false)

	func kill(pid: int) -> void:
		killed.append(pid)
		running[pid] = false

	func program_exists(_path: String) -> bool:
		return exists


var processes: FakeProcesses


func before_each() -> void:
	processes = FakeProcesses.new()


func after_each() -> void:
	super.after_each()
	if FileAccess.file_exists(STOP_FILE):
		DirAccess.remove_absolute(STOP_FILE)


## Konfiguration mit Bus-Adresse `127.0.0.1:<port>`; der Launcher hält `port` für die Bridge-Adresse.
func _config(port: int) -> RideConfig:
	var config := RideConfig.new()
	config.bus_url = "ws://127.0.0.1:%d" % port
	return config


func _launcher(config: RideConfig, port: int, platform_ok := true) -> BridgeLauncher:
	return BridgeLauncher.new(config, BASE_DIR, processes, platform_ok, STOP_FILE, port)


## Port, auf dem sicher niemand lauscht (kurz belegt und wieder freigegeben).
func _closed_port() -> int:
	var bus := start_fake_bus([])
	bus.stop()
	_buses.erase(bus)
	return bus.port


## Treibt `launcher` bis zum Ende der Erreichbarkeitsprüfung (echte TCP-Verbindung).
func _settle(launcher: BridgeLauncher) -> void:
	launcher.begin()
	var start := Time.get_ticks_msec()
	while launcher.state == BridgeLauncher.STATE_PROBING and Time.get_ticks_msec() - start < 5000:
		await run_for(0.02)
		launcher.poll(0.02)


func test_running_bridge_is_shared_and_never_stopped() -> void:
	var bus := start_fake_bus([FakeBusServer.status()])
	var launcher := _launcher(_config(bus.port), bus.port)
	await _settle(launcher)
	assert_eq(launcher.state, BridgeLauncher.STATE_SHARED, "erreichbar → mitbenutzen")
	assert_eq(processes.started, [], "keine zweite Bridge")
	assert_eq(launcher.hint(), "")
	assert_true(launcher.stop(), "Spiel schließt")
	assert_false(FileAccess.file_exists(STOP_FILE), "mitbenutzte Bridge bekommt keine Stoppdatei")
	assert_eq(processes.killed, [], "mitbenutzte Bridge wird nicht beendet")


func test_unreachable_bridge_is_started_with_source_from_config() -> void:
	var port := _closed_port()
	var config := _config(port)
	config.bridge_source = "ble"
	FileAccess.open(STOP_FILE, FileAccess.WRITE).close()  # Rest eines früheren Laufs
	var launcher := _launcher(config, port)
	await _settle(launcher)
	assert_eq(launcher.state, BridgeLauncher.STATE_OWN)
	assert_eq(processes.started.size(), 1, "genau ein Start")
	var program: String = processes.started[0][0]
	var args: PackedStringArray = processes.started[0][1]
	assert_eq(program, "C:/vspin/bridge/.venv/Scripts/pythonw.exe", "pythonw (ohne Konsolenfenster), relativ zum Spiel")
	assert_eq(args, PackedStringArray(["-m", "vspin_bridge", "--source", "ble", "--sessions-dir", "C:/vspin/bridge/sessions",
			"--stop-file", ProjectSettings.globalize_path(STOP_FILE), "--parent-pid", str(OS.get_process_id())]),
			"Wächter auf das Spiel: die Bridge endet mit ihm, auch ohne Stoppdatei")
	assert_false(FileAccess.file_exists(STOP_FILE), "alte Stoppdatei weg, sonst endete die Bridge sofort")
	assert_string_contains(launcher.hint(), "wird gestartet (Quelle ble)")


func test_simulator_bridge_starts_with_cadence_from_config() -> void:
	# Unter pythonw gibt es kein Terminal und keine Pfeiltasten – ohne Start-Kadenz stünde der Simulator auf 0 rpm.
	var port := _closed_port()
	var config := _config(port)
	config.bridge_source = "sim"
	config.bridge_sim_cadence = 85.0
	var launcher := _launcher(config, port)
	await _settle(launcher)
	var args: PackedStringArray = processes.started[0][1]
	assert_eq(args.slice(args.size() - 2), PackedStringArray(["--sim-cadence", "85"]), "Kadenz aus config.cfg")
	assert_string_contains(" ".join(args), "--source sim")


func test_closing_the_game_stops_own_bridge_cleanly() -> void:
	var port := _closed_port()
	var launcher := _launcher(_config(port), port)
	await _settle(launcher)
	var pid := launcher.pid
	assert_true(processes.is_running(pid))
	assert_true(launcher.stop(), "sauber beendet")
	assert_eq(processes.stopped_cleanly, [pid], "über die Stoppdatei")
	assert_eq(processes.killed, [], "nicht hart")
	assert_false(processes.is_running(pid), "Prozess ist weg")
	assert_eq(launcher.state, BridgeLauncher.STATE_STOPPED)
	assert_true(launcher.stop(), "zweites Schließen ist ein No-op")
	assert_eq(processes.started.size(), 1)


func test_hanging_bridge_is_killed_after_timeout() -> void:
	var port := _closed_port()
	processes.ignores_stop = true
	var launcher := _launcher(_config(port), port)
	await _settle(launcher)
	assert_false(launcher.stop(0.2), "nicht sauber")
	assert_eq(processes.killed, [launcher.pid], "erst nach der Wartezeit hart beendet")
	assert_false(processes.is_running(launcher.pid))


func test_missing_program_is_reported_in_wheel_status() -> void:
	var port := _closed_port()
	processes.exists = false
	var launcher := _launcher(_config(port), port)
	await _settle(launcher)
	assert_eq(launcher.state, BridgeLauncher.STATE_MISSING)
	assert_eq(processes.started, [], "nichts gestartet")
	var status: Array = preload("res://scenes/start_menu.gd").wheel_status(false, BusClient.STATE_DISCONNECTED, "",
			launcher.hint())
	assert_eq(status[0], "Bridge nicht erreichbar – Bridge-Programm fehlt (config.cfg [bridge] program)")
	assert_true(launcher.stop())


func test_own_bridge_that_exits_is_reported() -> void:
	var port := _closed_port()
	var launcher := _launcher(_config(port), port)
	await _settle(launcher)
	processes.running[launcher.pid] = false  # z. B. Quelle `ble` kann die Bridge noch nicht
	launcher.poll(BridgeLauncher.WATCH_INTERVAL_S)
	assert_eq(launcher.state, BridgeLauncher.STATE_FAILED)
	assert_string_contains(launcher.hint(), "Bridge-Start gescheitert (Quelle sim)")
	assert_true(launcher.stop())
	assert_eq(processes.killed, [])


func test_no_start_on_web_or_without_windows() -> void:
	var port := _closed_port()
	var launcher := _launcher(_config(port), port, false)
	launcher.begin()
	launcher.poll(BridgeLauncher.PROBE_TIMEOUT_S)
	assert_eq(launcher.state, BridgeLauncher.STATE_OFF)
	assert_eq(processes.started, [])
	assert_eq(launcher.hint(), "", "Hinweis zum Start von Hand bleibt")
	assert_true(launcher.stop())


func test_no_start_when_switched_off_or_bus_is_elsewhere() -> void:
	var port := _closed_port()
	var off := _config(port)
	off.bridge_autostart = false
	var elsewhere := _config(port + 1)
	for config in [off, elsewhere]:
		var launcher := _launcher(config, port)
		launcher.begin()
		launcher.poll(BridgeLauncher.PROBE_TIMEOUT_S)
		assert_eq(launcher.state, BridgeLauncher.STATE_OFF)
	assert_eq(processes.started, [])


func test_game_config_starts_simulator_bridge_from_repository() -> void:
	var config := RideConfig.load_file()
	assert_true(config.bridge_autostart)
	assert_eq(config.bridge_program, "../../bridge/.venv/Scripts/pythonw.exe")
	assert_eq(config.bridge_source, "sim")
	assert_eq(config.bridge_sim_cadence, 80.0, "Simulator aus dem Spiel tritt mit 80 rpm")
	assert_eq(config.bridge_sessions_dir, "../../bridge/sessions")
	assert_eq(config.bus_url, "ws://127.0.0.1:%d" % BridgeLauncher.BRIDGE_PORT, "Spiel startet nur für die Bridge-Adresse")


func test_tests_and_probes_never_start_a_bridge() -> void:
	# Spiel-Tests hängen am Fake-Bus (nie 8765) – dort startet der Launcher nichts.
	var bus := start_fake_bus([FakeBusServer.status()])
	var launcher := BridgeLauncher.new(config_for(bus), BASE_DIR, processes, true, STOP_FILE)
	launcher.begin()
	assert_eq(launcher.state, BridgeLauncher.STATE_OFF)
