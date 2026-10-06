# vspin-bridge

Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert
(ADR-0002, ADR-0003). Noch nicht implementiert.

Geplante Struktur:

```
src/vspin_bridge/
  sources/   ble (FTMS/CSC), sim, replay  – alle implementieren DeviceSource
  parsers/   Byte → TelemetrySample
  bus/       WebSocket-Server (docs/bus-protocol.md)
  logging/   Session-CSV + Roh-JSONL (ADR-0008)
tests/fixtures/  echte JC312-Dumps für Parser-Tests
```
