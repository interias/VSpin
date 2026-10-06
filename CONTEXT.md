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
| **Simulator** | Software-Gerät, das Telemetrie erzeugt, damit ohne Rad entwickelt werden kann. |
| **Prototyp-Game** | Das eine Spiel in v1, das die Kette Kurbel → Spiel end-to-end beweist. |
| **Bridge** (`vspin-bridge`) | Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert. |
| **Bus** | Lokaler WebSocket (`ws://127.0.0.1:8765`, JSON), über den Bridge und Clients kommunizieren. |
| **Client** | Alles, was am Bus hängt: Games, Logger, Dashboard. |
| **Session** | Ein zusammenhängender Trainings-/Spiel-Zeitraum, dessen Telemetrie aufgezeichnet wird. |

## Scope v1

Siehe [ADR-0001](docs/adr/0001-scope-v1.md). Telemetrie + Simulator + genau ein Prototyp-Game.

## Architektur

Siehe [ADR-0002](docs/adr/0002-tech-stack-und-bus.md): Python-Bridge (bleak) → WebSocket-Bus → Godot-Games.
