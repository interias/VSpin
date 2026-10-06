# VSPIN

Eigene Game-Plattform für das **Wenoker JC312** Indoor-Bike: Telemetrie per
Bluetooth LE unter Windows abgreifen und eigene Games darauf bauen.

> Status: Grundgerüst. Noch keine Implementierung – als Nächstes kommt das
> BLE-Discovery-Skript (siehe Issues).

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
