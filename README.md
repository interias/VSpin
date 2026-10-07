# VSPIN

Eigene Game-Plattform für das **Wenoker JC312** Indoor-Bike: Telemetrie per
Bluetooth LE unter Windows abgreifen und eigene Games darauf bauen.

> Status: v1 in Arbeit. Bridge (Simulator, Replay, CSC/FTMS-Parser, Session-Logging) und
> Spiel „Inselfahrt“ (Insel-Rundkurs, HUD, Pause, `set_grade`) laufen ohne Rad. Es fehlen
> die BLE-Anbindung ans echte JC312 (#9, braucht den Dump aus #1) und die Abnahme am Rad (#17).

## Schnellstart (Windows)

Voraussetzungen: Python 3.12, [Godot 4.4](https://godotengine.org/download) (Standard-Version, nicht .NET).

**1. Bridge installieren** (einmalig, PowerShell im Repo-Ordner):

```powershell
cd bridge
py -3.12 -m venv .venv
.venv\Scripts\pip install -e ".[test]"
```

**2. Bridge starten** – eine der Quellen:

```powershell
.venv\Scripts\vspin-bridge --source sim --sim-cadence 80        # Simulator, Kadenz per Pfeiltasten
.venv\Scripts\vspin-bridge --source sim --profile profiles\sprint.toml   # geskriptetes Profil
.venv\Scripts\vspin-bridge --source replay <datei>.raw.jsonl --speed 1   # Aufnahme abspielen
```

Im Bridge-Terminal: Pfeil hoch/runter = Kadenz ±5, `q` = beenden. Profile liegen in
`bridge/profiles/` (Einrollen, Sprint, Stillstand, Abbruch). Jede Session landet als
`sessions/<zeit>.csv` + `.raw.jsonl` im aktuellen Ordner (nicht im Git).
Das echte Rad (`--source ble`) folgt mit #9.

**3. Spiel starten:** Godot öffnen → `games/island-ride/project.godot` importieren → F5,
oder `godot --path games/island-ride`. Tasten: `P`/Leertaste Pause, `F3` Debug-Anzeige, `Esc` Ende.
Reihenfolge egal – das Spiel verbindet sich, sobald die Bridge läuft.

**4. Protokoll des Rads herausfinden** (sobald das JC312 da ist): siehe [`tools/README.md`](tools/README.md).

**Tests:**

```powershell
cd bridge; .venv\Scripts\python -m pytest -q          # Bridge (startet echte Bridge-Prozesse)
godot --headless --path games/island-ride --import       # Spiel, einmalig
godot --headless --path games/island-ride -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Details: [`bridge/README.md`](bridge/README.md), [`games/island-ride/README.md`](games/island-ride/README.md).

### Latenz prüfen (Abnahme < 200 ms)

Die Debug-Anzeige (`F3`) zeigt Roh-Kadenz, Bridge-Zeitstempel und das Alter der letzten Nachricht im Spiel –
das ist nur der Anteil Bus → Spiel. Die Gesamtlatenz Kurbel → Bild misst man am einfachsten mit einer
Zeitlupen-Aufnahme (Handy, 240 fps): Kurbel und Bildschirm gleichzeitig filmen, aus dem Stand kräftig antreten
und die Frames zwischen erster Kurbelbewegung und erster Reaktion im HUD zählen (1 Frame ≈ 4 ms).
Hinweis: Das Rad selbst sendet typischerweise nur ca. 1–4 Mal pro Sekunde, und die Glättung (1 s) verzögert
zusätzlich – das Ergebnis zeigt, ob Glättung oder Senderate angepasst werden müssen.

## Architektur

```
[JC312] ──BLE──▶ vspin-bridge (Python/bleak) ──WebSocket ws://127.0.0.1:8765──▶ Games (Godot 4)
[Simulator / Replay] ──▶ (gleiche Schnittstelle)                                Logger, Dashboard …
```

- **Nur die Bridge spricht BLE** – Games, Logger usw. sind Clients am Bus.
- **Kadenz** ist der einzige Game-Input in v1; Watt sind höchstens geschätzt.
- **Prototyp-Game:** 3D-Radsimulator auf einer Mallorca-Stil-Insel.
- **Später:** ESP32-Retrofit als FTMS-Smart-Bike mit Widerstandssteuerung.

## Repo

| Ordner | Inhalt |
|---|---|
| [`bridge/`](bridge/) | Python-Paket `vspin_bridge`: BLE-/Sim-/Replay-Quellen, Parser, Bus, Logging |
| [`tools/`](tools/) | Hilfsskripte, z. B. BLE-Discovery |
| [`games/`](games/) | Godot-Projekte |
| [`firmware/`](firmware/) | ESP32-Firmware (später) |
| [`docs/adr/`](docs/adr/) | Architekturentscheidungen |
| [`docs/bus-protocol.md`](docs/bus-protocol.md) | Vertrag zwischen Bridge und Clients |
| [`CONTEXT.md`](CONTEXT.md) | Glossar und Kontext |

## Entscheidungen

| ADR | Thema |
|---|---|
| [0001](docs/adr/0001-scope-v1.md) | Scope v1 |
| [0002](docs/adr/0002-tech-stack-und-bus.md) | Tech-Stack & Bus |
| [0003](docs/adr/0003-geraete-abstraktion-und-simulator.md) | Geräte-Abstraktion, Simulator, Replay |
| [0004](docs/adr/0004-datenqualitaet.md) | Datenqualität |
| [0005](docs/adr/0005-prototyp-game-radsimulator.md) | Prototyp-Game: Radsimulator |
| [0006](docs/adr/0006-insel-welt.md) | Insel-Welt im Mallorca-Stil |
| [0007](docs/adr/0007-widerstandssteuerung-esp32.md) | Widerstandssteuerung / ESP32 |
| [0008](docs/adr/0008-datenspeicherung-und-export.md) | Datenspeicherung & Export |
| [0009](docs/adr/0009-repo-organisation-und-lizenz.md) | Repo-Organisation & Lizenz |

## Lizenz

MIT – siehe [LICENSE](LICENSE). qdomyos-zwift (GPL-3.0) dient nur als Lesereferenz.
