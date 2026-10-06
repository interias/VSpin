# VSPIN – Kontext & Glossar

Lebendes Dokument. Begriffe, die im Projekt eine feste Bedeutung haben.
Entscheidungen stehen als ADRs unter [`docs/adr/`](docs/adr/).

## Ausgangslage

- **Gerät:** Wenoker JC312 Spinning-Bike, Bluetooth LE, laut Hersteller Zwift/Kinomap-kompatibel.
- **Widerstand:** manuell per Drehknopf (Magnetbremse), keine elektronische Steuerung.
- **Host:** Windows-PC mit USB-Bluetooth-Dongle.
- **Protokoll:** noch unbekannt – vermutlich FTMS oder CSC; Verifikation per nRF-Connect-Dump.

## Glossar

| Begriff | Bedeutung |
|---|---|
| **JC312** | Das konkrete Indoor-Bike (Wenoker JC312). |
| **Telemetrie** | Vom Rad gelieferte Messwerte: Kadenz, Geschwindigkeit, ggf. Leistung. |
| **Kadenz** | Kurbelumdrehungen pro Minute (rpm). Primärer Game-Input. |
| **FTMS** | Bluetooth Fitness Machine Service (UUID `0x1826`), u. a. Indoor Bike Data `0x2AD2`, Control Point `0x2AD9`. |
| **CSC** | Bluetooth Cycling Speed and Cadence Service (UUID `0x1816`), CSC Measurement `0x2A5B`. |
| **DeviceSource** | Gemeinsame Schnittstelle aller Datenquellen in der Bridge (BLE, Replay, Simulator). |
| **TelemetrySample** | Protokollneutraler Messpunkt (Zeit, Kadenz, Geschwindigkeit, Leistung), jeder Wert mit Herkunft `measured`/`estimated`. |
| **Capability** | Fähigkeit einer Quelle, z. B. `CADENCE`, `POWER`, `RESISTANCE_CONTROL`. |
| **Simulator** | `DeviceSource`, die Telemetrie erzeugt (manuell, Profil, Rauschen) – Entwicklung ohne Rad. |
| **Replay** | `DeviceSource`, die aufgezeichnete rohe BLE-Notifications erneut durch die Parser schickt. |
| **Profil** | Geskripteter Simulator-Ablauf, z. B. Intervalle oder provozierter Verbindungsabbruch. |
| **Prototyp-Game** | Das eine Spiel in v1, das die Kette Kurbel → Spiel end-to-end beweist. |
| **Bridge** (`vspin-bridge`) | Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert. |
| **Bus** | Lokaler WebSocket (`ws://127.0.0.1:8765`, JSON), über den Bridge und Clients kommunizieren. |
| **Client** | Alles, was am Bus hängt: Games, Logger, Dashboard. |
| **measured / estimated** | Herkunft eines Werts: gemessen vom Gerät bzw. hochgerechnet. Geschätzte Watt werden als „~142 W“ angezeigt. |
| **stale** | Verbindungsstatus: verbunden, aber > 3 s keine Daten. Games pausieren. |
| **Session** | Ein zusammenhängender Trainings-/Spiel-Zeitraum, dessen Telemetrie aufgezeichnet wird. |

## Scope v1

Siehe [ADR-0001](docs/adr/0001-scope-v1.md). Telemetrie + Simulator + genau ein Prototyp-Game.

## Architektur

Siehe [ADR-0002](docs/adr/0002-tech-stack-und-bus.md): Python-Bridge (bleak) → WebSocket-Bus → Godot-Games.

Geräte-Abstraktion: [ADR-0003](docs/adr/0003-geraete-abstraktion-und-simulator.md).

Datenqualität: [ADR-0004](docs/adr/0004-datenqualitaet.md) – Kadenz ist einziger Game-Input, Watt nur geschätzt.
