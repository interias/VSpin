## Bridge aus dem Spiel starten (#25, nur Windows-Desktop, nie im Web-Export): Ist auf der Bus-Adresse keine Bridge
## erreichbar, startet das Spiel sie als unsichtbaren Kindprozess (`pythonw`, kein Konsolenfenster) mit der Quelle aus
## `config.cfg [bridge]`. Eine schon laufende Bridge wird nur mitbenutzt. Beim Schließen beendet das Spiel nur die
## eigene, und zwar sauber über die Stoppdatei (`vspin-bridge --stop-file`): Die Bridge schließt Session-CSV und
## Rohdaten ab wie bei Strg+C. Erst wenn sie nicht rechtzeitig endet, wird sie hart beendet.
##
## Prozesse laufen über einen austauschbaren Starter (`Processes`; Tests: Fake-Prozess). Kein Node: der Besitzer
## ruft `begin()` einmal, dann `poll(delta)` regelmäßig und beim Schließen `stop()`.
class_name BridgeLauncher
extends RefCounted

const STATE_OFF := "off"  ## kein Start: Web, nicht Windows, abgeschaltet oder Bus nicht auf der Bridge-Adresse
const STATE_PROBING := "probing"  ## prüft, ob auf der Bus-Adresse schon eine Bridge erreichbar ist
const STATE_SHARED := "shared"  ## eine Bridge lief schon – wird nur mitbenutzt, nie beendet
const STATE_OWN := "own"  ## eigene Bridge gestartet
const STATE_MISSING := "missing"  ## Programm (`[bridge] program`) fehlt
const STATE_FAILED := "failed"  ## Start gescheitert oder eigene Bridge hat sich von selbst beendet
const STATE_STOPPED := "stopped"  ## eigene Bridge beim Schließen beendet

## Adresse, auf der die Bridge lauscht (ADR-0002, fester Port). Nur dann hilft ein Start aus dem Spiel.
const BRIDGE_HOSTS := ["127.0.0.1", "localhost"]
const BRIDGE_PORT := 8765
const SOURCES := ["sim", "ble"]
## Höchstdauer der Erreichbarkeitsprüfung (Sekunden); danach gilt die Bridge als nicht erreichbar.
const PROBE_TIMEOUT_S := 3.0
## Abstand der Prüfung, ob die eigene Bridge noch läuft (Sekunden).
const WATCH_INTERVAL_S := 0.5
## So lange wartet `stop()` auf das saubere Ende (Sekunden), bevor die Bridge hart beendet wird.
const STOP_TIMEOUT_S := 5.0
const DEFAULT_STOP_FILE := "user://bridge.stop"


## Prozessstarter: echte Prozesse über `OS`. Tests ersetzen ihn durch einen Fake-Prozess.
class Processes:
	extends RefCounted

	## Startet `program` mit `args` ohne Konsolenfenster; PID oder -1.
	func start(program: String, args: PackedStringArray) -> int:
		return OS.create_process(program, args)

	func is_running(pid: int) -> bool:
		return OS.is_process_running(pid)

	## Hartes Beenden (TerminateProcess) – nur, wenn der saubere Weg scheitert.
	func kill(pid: int) -> void:
		OS.kill(pid)

	func program_exists(path: String) -> bool:
		return FileAccess.file_exists(path)


var state := STATE_OFF
## PID der eigenen Bridge (-1 = keine).
var pid := -1
## Aufrufzeile der eigenen Bridge (Programm, Argumente) – für Meldungen und Tests.
var program := ""
var args := PackedStringArray()

var _enabled: bool
var _host := ""
var _port := -1
var _source: String
var _sessions_dir: String
var _stop_file: String
var _processes: Processes
var _tcp: StreamPeerTCP = null
var _probe_s := 0.0
var _watch_s := 0.0


## `config`: Bus-Adresse und `[bridge]`; `base_dir`: Ordner, gegen den relative Pfade aus `[bridge]` aufgelöst werden
## (Spielordner, siehe `game_dir()`); `platform_ok`: Windows-Desktop. `stop_file` liegt beim Spiel. Tests setzen
## Prozessstarter, Plattform, Stoppdatei und `bridge_port` (Fake-Bus statt 8765).
func _init(config: RideConfig, base_dir: String, processes: Processes = null, platform_ok := is_supported_platform(),
		stop_file := DEFAULT_STOP_FILE, bridge_port := BRIDGE_PORT) -> void:
	_processes = processes if processes != null else Processes.new()
	program = _absolute(config.bridge_program, base_dir)
	_sessions_dir = _absolute(config.bridge_sessions_dir, base_dir)
	_source = config.bridge_source
	if _source not in SOURCES:
		push_warning("BridgeLauncher: unbekannte Quelle '%s', nutze 'sim'" % _source)
		_source = "sim"
	_stop_file = ProjectSettings.globalize_path(stop_file)
	_parse_bus_url(config.bus_url)
	_enabled = platform_ok and config.bridge_autostart and _host in BRIDGE_HOSTS and _port == bridge_port


## Start aus dem Spiel gibt es nur unter Windows als Desktop-Programm – im Web gibt es keine Prozesse.
static func is_supported_platform() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("web")


## Spielordner: im Export der Ordner der .exe, sonst der Projektordner (`games/island-ride`).
static func game_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir()
	return ProjectSettings.globalize_path("res://")


## Prüft, ob schon eine Bridge erreichbar ist; danach entscheidet `poll()`: mitbenutzen oder selbst starten.
func begin() -> void:
	if not _enabled or state != STATE_OFF:
		return
	state = STATE_PROBING
	_probe_s = 0.0
	_tcp = StreamPeerTCP.new()
	if _tcp.connect_to_host(_host, _port) != OK:
		_launch()


func poll(delta_s: float) -> void:
	match state:
		STATE_PROBING:
			_tcp.poll()
			_probe_s += delta_s
			var status := _tcp.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED:
				_tcp.disconnect_from_host()
				_tcp = null
				state = STATE_SHARED
			elif status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE] or _probe_s >= PROBE_TIMEOUT_S:
				_tcp.disconnect_from_host()
				_tcp = null
				_launch()
		STATE_OWN:
			_watch_s += delta_s
			if _watch_s >= WATCH_INTERVAL_S:
				_watch_s = 0.0
				if not _processes.is_running(pid):
					push_warning("BridgeLauncher: die gestartete Bridge hat sich beendet (%s)" % " ".join(args))
					state = STATE_FAILED


## Beendet die eigene Bridge sauber über die Stoppdatei und wartet bis `timeout_s` auf ihr Ende; danach hart.
## Eine mitbenutzte Bridge bleibt unberührt. Liefert true, wenn keine eigene Bridge mehr läuft und keine hart
## beendet werden musste.
func stop(timeout_s := STOP_TIMEOUT_S) -> bool:
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	if state != STATE_OWN and state != STATE_FAILED:
		return true
	state = STATE_STOPPED
	if not _processes.is_running(pid):
		return true
	var file := FileAccess.open(_stop_file, FileAccess.WRITE)
	if file != null:
		file.close()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while _processes.is_running(pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(50)
	if not _processes.is_running(pid):
		return true
	push_warning("BridgeLauncher: Bridge endet nicht innerhalb von %.1f s, beende sie hart" % timeout_s)
	_processes.kill(pid)
	return false


## Hinweis für den Radstatus, solange der Bus nicht verbunden ist ("" = Standardhinweis zum Start von Hand).
func hint() -> String:
	match state:
		STATE_PROBING:
			return "Suche Bridge …"
		STATE_OWN:
			return "Bridge wird gestartet (Quelle %s) …" % _source
		STATE_MISSING:
			return "Bridge-Programm fehlt (config.cfg [bridge] program)"  # voller Pfad steht im Log
		STATE_FAILED:
			return "Bridge-Start gescheitert (Quelle %s)" % _source
	return ""


func _launch() -> void:
	if not _processes.program_exists(program):
		push_warning("BridgeLauncher: Programm fehlt: %s" % program)
		state = STATE_MISSING
		return
	DirAccess.remove_absolute(_stop_file)  # Rest eines früheren Laufs
	args = PackedStringArray(["-m", "vspin_bridge", "--source", _source, "--sessions-dir", _sessions_dir,
			"--stop-file", _stop_file])
	pid = _processes.start(program, args)
	if pid <= 0:
		push_warning("BridgeLauncher: Start gescheitert: %s %s" % [program, " ".join(args)])
		state = STATE_FAILED
		return
	_watch_s = 0.0
	state = STATE_OWN


func _parse_bus_url(url: String) -> void:
	var rest := url.trim_prefix("ws://")
	if rest == url:
		return  # nur ws:// auf diesem Rechner
	var host_port := rest.get_slice("/", 0)
	_host = host_port.get_slice(":", 0)
	_port = int(host_port.get_slice(":", 1)) if host_port.contains(":") else 80


static func _absolute(path: String, base_dir: String) -> String:
	if path.is_absolute_path():
		return path.simplify_path()
	return base_dir.path_join(path).simplify_path()
