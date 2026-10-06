# Inselfahrt (`island-ride`)

Prototyp-Game (ADR-0005): 3D-Radsimulator in Godot 4.4 (GDScript). Das Spiel ist ein Client am
Bus (`docs/bus-protocol.md`); die Kadenz bewegt den Fahrer entlang eines `Path3D` – kein Lenken.
Stand: Graybox-Strecke (ein Anstieg, eine Abfahrt) mit Minimal-HUD (Kadenz, Geschwindigkeit) und
Spielzuständen (Pause bei Verbindungsverlust, manuelle Pause).

## Spielen

1. Bridge starten (siehe `bridge/README.md`), z. B. mit dem Simulator:
   `vspin-bridge --source sim --sim-cadence 80` – im Bridge-Terminal Kadenz mit Pfeil hoch/runter ändern.
2. Spiel starten – es verbindet sich automatisch mit dem Bus und verbindet bei Abbruch neu:
   ```
   godot --path games/island-ride                 # oder Projekt im Godot-Editor öffnen und F5
   ```
Reihenfolge egal: Startet das Spiel zuerst, zeigt es „Bridge nicht erreichbar … Bridge starten:
`vspin-bridge --source sim`“ und versucht alle `reconnect_s` Sekunden zu verbinden.

### Tasten

| Taste | Wirkung |
|---|---|
| `P` oder Leertaste | Pause an/aus (jederzeit) |
| `Esc` | Spiel beenden (jederzeit) |

Physische Tastenposition (gleich auf QWERTZ/QWERTY); definiert in `scenes/main.gd` (`KEY_BINDINGS`).

### Spielzustände

| Zustand (`state`) | Wann | Anzeige |
|---|---|---|
| `riding` – fahren | Bus verbunden, Quelle `connected` und seit dem letzten Abbruch Telemetrie empfangen | – |
| `paused_manual` – pausiert (manuell) | `P`/Leertaste | „Pause“ |
| `paused_connection` – pausiert (Verbindung) | Bridge nicht erreichbar, Quelle `stale`/`disconnected` oder noch keine Daten | „Bridge nicht erreichbar … Bridge starten“ bzw. „Verbindung verloren (Rad: stale)“ |

In jeder Pause steht das Fahrmodell still: Position und Geschwindigkeit bleiben, wie sie waren. Ein
Verbindungsabbruch ist **keine Kadenz 0** (ADR-0004) – der Fahrer rollt nicht aus. Sobald der Bus wieder
verbunden ist, die Quelle `connected` meldet und Telemetrie ankommt, fährt das Spiel von selbst weiter.
Die Verbindungspause hat Vorrang; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen
(kein automatisches Weiterfahren aus der manuellen Pause). Hängt ein Verbindungsaufbau länger als
`connect_timeout_s`, bricht der Bus-Client ihn ab und versucht es neu.

## Konfiguration

`config.cfg` (ConfigFile/INI) – Änderungen wirken beim nächsten Start, ohne Codeänderung:

| Schlüssel | Standard | Wirkung |
|---|---|---|
| `[bus] url` | `ws://127.0.0.1:8765` | Bus-Adresse |
| `[bus] reconnect_s` | `2.0` | Sekunden zwischen Verbindungsversuchen |
| `[bus] connect_timeout_s` | `5.0` | hängt ein Verbindungsaufbau länger, wird er abgebrochen und neu versucht |
| `[ride] k_kmh_per_rpm` | `0.33` | Übersetzungsfaktor k: `v_ziel = k · Kadenz` (km/h) auf flacher Strecke |
| `[ride] uphill_damping` | `8.0` | bergauf: `v_ziel / (1 + uphill_damping · Steigung)` |
| `[ride] downhill_boost` | `2.0` | bergab: `v_ziel · (1 + downhill_boost · \|Gefälle\|)` |
| `[ride] inertia_s` | `1.5` | Trägheit: Zeitkonstante (s) der Annäherung an `v_ziel`; 0 = sofort |

Steigung als Anteil (0.06 = 6 %, wie `set_grade`). Fehlende Schlüssel → Standardwerte aus `src/ride_config.gd`.

## Tests

Headless mit GUT 9.4 (`addons/gut`, MIT) und einem Fake-Bus-Server. Im Repo-Wurzelordner:

```
godot --headless --path games/island-ride --import          # einmalig bzw. nach neuen Skripten/Klassen
godot --headless --path games/island-ride -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Ausgabe endet mit `Scripts / Tests / Passing / Failing`; Exit-Code ≠ 0 bei Fehlschlag. `.gutconfig.json`
setzt dieselben Optionen und einen Post-Run-Hook (`tests/support/post_run_check.gd`), der den Lauf
fehlschlagen lässt, wenn ein `test_*.gd` nicht ladbar ist (GUT allein überspringt es nur mit Warnung).
Einzelnes Skript: zusätzlich `-gselect=test_bus_client`. Die Tests brauchen keine Bridge und
benutzen Ports ab 18765 – nie den Bus-Port 8765.

### Testmuster: Fake-Bus und Drehbuch

Ein guter Test prüft von außen: Drehbuch rein → beobachtbares Spielverhalten raus
(`bus.cadence`/`bus.status`, `state`, `model.speed_kmh()`, `model.distance_m`, HUD), nicht Interna.

- `tests/support/fake_bus_server.gd` (`FakeBusServer`): WebSocket-Server (`TCPServer` +
  `WebSocketPeer.accept_stream`), spielt jedem Client ein **Drehbuch** vor und schreibt
  Client-Nachrichten in `received` mit (für `set_grade`-Tests).
- `tests/support/bus_test.gd`: Basisklasse für Tests (`extends "res://tests/support/bus_test.gd"`):
  `start_fake_bus(steps)`, `spawn_ride(bus, start_m, config)` (Hauptszene am Fake-Bus),
  `connect_client(bus)` (nackter `BusClient`), `run_for(s)`, `run_until(cond, timeout_s)`,
  `press_key(KEY_P)` (Taste wie ein Spieler drücken); räumt nach jedem Test auf. `spawn_ride` setzt
  `quit_on_request = false` – `Esc` meldet dann nur `quit_requested`, statt den Testlauf zu beenden.

Drehbuch = Array von Schritten, `at` = Sekunden ab Verbindungsaufbau des Clients; jede Verbindung
spielt von vorn (so lässt sich auch Reconnect prüfen):

```json
[
  {"at": 0.0, "send": {"v": 0, "type": "status", "t_ms": 0, "state": "connected", "source": "sim", "capabilities": ["CADENCE"]}},
  {"at": 0.25, "send": {"v": 0, "type": "telemetry", "t_ms": 250, "cadence": 90.0, "speed_kmh": null, "power_w": null, "power_estimated": null, "heart_rate": null}},
  {"at": 2.0, "close": true}
]
```

Bausteine in GDScript: `FakeBusServer.status(state, source, capabilities, at)`, `telemetry(cadence, at)`,
`steady_cadence(cadence, from_s, to_s, interval_s = 0.25)`, `close_at(at)`; als Datei über
`FakeBusServer.load_script("res://tests/fixtures/….json")`.

```gdscript
extends "res://tests/support/bus_test.gd"

func test_more_cadence_is_faster() -> void:
	var slow := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(60.0, 0.0, 5.0)))
	var fast := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0)))
	await run_for(3.0)
	assert_gt(fast.model.speed_kmh(), slow.model.speed_kmh())
```

### End-to-End mit echter Bridge (manuell)

`tools/e2e.sh` startet je Kadenz die echte Bridge mit Simulator (`--sim-cadence N`, Port 8765 muss frei
sein), fährt das Spiel headless (`tools/e2e_probe.gd`) und vergleicht die Geschwindigkeiten:

```
GODOT=godot PYTHON=python games/island-ride/tools/e2e.sh 60 90
```

## Aufbau

```
config.cfg              Bus-Adresse + Fahrmodell-Parameter
scenes/main.tscn/.gd    Hauptszene: Bus-Client → Fahrmodell → Fahrer auf dem Pfad, Spielzustände, Tasten, HUD
src/bus_client.gd       BusClient: verbinden/reconnecten (mit Verbindungs-Timeout), status/telemetry parsen, send_message
src/ride_model.gd       RideModel: reine Logik (Kadenz, Steigung, Δt, Konfig → Geschwindigkeit, Position)
src/ride_config.gd      RideConfig: liest config.cfg
src/track.gd            Track (Path3D): length_m(), grade_at(distanz), position_at(distanz)
src/graybox_track.gd    GrayboxTrack: Rundkurs ~900 m, flach → +6 % → Kuppe → −6 % → flach
tests/                  GUT-Tests, support/ (Fake-Bus, Basisklasse, Hook), fixtures/
tools/                  E2E-Prüfhilfe gegen die echte Bridge
addons/gut/             GUT 9.4.0 (MIT, Lizenz in addons/gut/LICENSE.md)
```

Noch nicht enthalten (Folgetickets): `set_grade` senden (#12), vollständiges HUD (#13),
Insel-Rundkurs statt Graybox (#14).
