## Basisklasse für Spiel-Tests mit Fake-Bus (`extends "res://tests/support/bus_test.gd"`).
## Startet Fake-Bus-Server und Spielszenen, treibt sie in Echtzeit an und räumt nach jedem Test auf.
##
##   var bus := start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0))
##   var ride := spawn_ride(bus)            # Hauptszene, verbunden mit diesem Fake-Bus
##   await run_for(3.0)
##   assert_gt(ride.model.speed_kmh(), 20.0)
extends GutTest

const MAIN_SCENE := preload("res://scenes/main.tscn")
## Testports liegen bewusst neben dem Bus-Port 8765 der Bridge.
const FIRST_TEST_PORT := FakeBusServer.DEFAULT_PORT

var _buses: Array = []
var _clients: Array = []
var _next_port := FIRST_TEST_PORT


func after_each() -> void:
	for client in _clients:
		client.close()
	_clients.clear()
	for bus in _buses:
		bus.stop()
	_buses.clear()


## Startet einen Fake-Bus mit Drehbuch auf dem nächsten freien Testport.
func start_fake_bus(steps: Array) -> FakeBusServer:
	var bus := FakeBusServer.new(steps)
	var err := ERR_CANT_CREATE
	for attempt in range(20):
		err = bus.start(_next_port)
		_next_port += 1
		if err == OK:
			break
	assert_eq(err, OK, "Fake-Bus konnte keinen Port öffnen")
	_buses.append(bus)
	return bus


## Konfiguration aus `path` (Standard: die Spiel-Konfiguration), Bus-Adresse auf `bus` umgebogen.
func config_for(bus: FakeBusServer, path: String = RideConfig.DEFAULT_PATH) -> RideConfig:
	var config := RideConfig.load_file(path)
	config.bus_url = bus.url()
	config.bus_reconnect_s = 0.2
	return config


## Instanziert die Hauptszene mit `config` (oder Spiel-Konfiguration + `bus`) ab Streckenposition `start_m`.
func spawn_ride(bus: FakeBusServer, start_m: float = 0.0, config: RideConfig = null) -> Node:
	var ride := MAIN_SCENE.instantiate()
	ride.config = config if config != null else config_for(bus)
	ride.start_distance_m = start_m
	ride.quit_on_request = false
	add_child_autofree(ride)
	return ride


## Ein BusClient direkt am Fake-Bus (wird in `run_for` mitgepollt).
func connect_client(bus: FakeBusServer, reconnect_s: float = 0.2, connect_timeout_s: float = 5.0) -> BusClient:
	return connect_client_to(bus.url(), reconnect_s, connect_timeout_s)


## Ein BusClient an einer beliebigen Adresse (wird in `run_for` mitgepollt).
func connect_client_to(url: String, reconnect_s: float = 0.2, connect_timeout_s: float = 5.0) -> BusClient:
	var client := BusClient.new(url, reconnect_s, connect_timeout_s)
	_clients.append(client)
	return client


## Drückt eine Taste (physische Position) und lässt sie wieder los, wie ein Spieler.
func press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


## Lässt `seconds` Echtzeit vergehen; Fake-Busse und direkte Clients werden je Frame gepollt,
## Spielszenen laufen über ihr eigenes `_process`.
func run_for(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	var last := start
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		var delta := (now - last) / 1000.0
		last = now
		for bus in _buses:
			bus.poll()
		for client in _clients:
			client.poll(delta)


## Wie `run_for`, endet aber früher, sobald `condition` wahr ist. Gibt `condition` am Ende zurück.
func run_until(condition: Callable, timeout_s: float) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout_s * 1000.0:
		await run_for(0.02)
	return condition.call()
