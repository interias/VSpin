# ADR-0002: Tech-Stack – Python-Bridge, WebSocket-Bus, Godot-Games

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Telemetrie muss unter Windows per BLE gelesen und an Games weitergereicht werden.
Optionen: Python/bleak, C#/.NET WinRT-BLE, BLE direkt in Godot/Unity.
Ein BLE-Peripheral erlaubt typischerweise nur **eine** Central-Verbindung gleichzeitig.

## Entscheidung

Drei getrennte Prozesse/Schichten:

1. **vspin-bridge** – Python 3.12 + [bleak](https://github.com/hbldh/bleak).
   Einziger Prozess, der BLE spricht. Enthält auch den Simulator.
2. **Bus** – WebSocket auf `ws://127.0.0.1:8765`, JSON-Nachrichten mit
   Schema-Version. Bidirektional (für spätere Widerstandssteuerung).
3. **Games** – Godot 4 (GDScript), verbinden sich als WebSocket-Clients.

## Begründung

- bleak nutzt unter Windows WinRT, ist plattformübergreifend testbar und
  passt zum Discovery-Skript.
- WebSocket: eingebaute Clients in Godot/Browser/Python, mehrere Clients
  gleichzeitig, Latenz auf localhost < 1 ms; UDP hätte keinen Verbindungsstatus.
- Godot: leichtgewichtig, Open Source, `WebSocketPeer` eingebaut.
- Python ist die bevorzugte Sprache des Projektinhabers.

## Konsequenzen

- Das „nur eine BLE-Verbindung“-Problem ist architektonisch gelöst: Games,
  Logger, Dashboard sind Bus-Clients, nie BLE-Clients.
- Das Bus-Protokoll ist der zentrale Vertrag und wird versioniert dokumentiert.
- Zwei Sprachen im Repo (Python, GDScript).

## Verworfen

- **C#/.NET:** nur Windows, keine Bridge-Entwicklung/CI ohne Windows.
- **BLE im Game-Engine-Plugin:** harte Kopplung, nur ein Game gleichzeitig.
