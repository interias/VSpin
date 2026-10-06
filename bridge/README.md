# vspin-bridge

Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert
(ADR-0002, ADR-0003). Bisher implementiert: Quelle `sim` (Simulator, manueller Modus)
und der Bus nach [`docs/bus-protocol.md`](../docs/bus-protocol.md) – nur `ws://127.0.0.1:8765`.

## Installieren

Python 3.12, im Ordner `bridge/`:

```
python -m venv .venv
.venv/bin/pip install -e ".[test]"        # Windows: .venv\Scripts\pip install -e ".[test]"
```

## Starten

```
vspin-bridge --source sim                  # oder: python -m vspin_bridge --source sim
vspin-bridge --source sim --sim-cadence 80 # Start-Kadenz in rpm (Standard 0)
```

Im Terminal: Pfeil hoch/`+` = Kadenz +5, Pfeil runter/`-` = Kadenz −5 (0–200 rpm), `q` oder
Strg+C = beenden. Die Statuszeile zeigt Quelle, Verbindungsstatus, Kadenz und Anzahl Clients.
Ohne Terminal (stdin kein TTY) ist die Tastatur aus, die Bridge läuft normal weiter.

Clients können `set_grade` senden (virtuelle Steigung, ADR-0007). Die Bridge antwortet dem
Absender mit `ack` (bis zur Widerstandssteuerung `ok: false, reason: "not_supported"`) und
schreibt eine Zeile ins Terminal, z. B. `set_grade +0.070 (+7.0 %) -> not_supported`.
Der Simulator senkt bergauf die Kadenz (um 2 × Steigung, höchstens auf die Hälfte);
bei Steigung 0 oder bergab gilt wieder die per Tastatur eingestellte Kadenz.
Kaputte oder unbekannte Nachrichten werden mit `error` beantwortet (docs/bus-protocol.md).

## Testen

```
python -m pytest                           # im Ordner bridge/
```

Testmuster: Tests starten die Bridge als echten Prozess (`python -m vspin_bridge`,
`PYTHONPATH=src`) und prüfen nur das am Bus beobachtbare Verhalten über Test-Clients
(`tests/bridge_harness.py`, Fixtures `bridge_process`/`bus_client` in `tests/conftest.py`).
Port 8765 muss frei sein. Kein Rad, kein Windows nötig.

Struktur (teils noch geplant):

```
src/vspin_bridge/
  sources/   ble (FTMS/CSC), sim, replay  – alle implementieren DeviceSource
  parsers/   Byte → TelemetrySample
  bus/       WebSocket-Server (docs/bus-protocol.md)
  logging/   Session-CSV + Roh-JSONL (ADR-0008)
tests/fixtures/  echte JC312-Dumps für Parser-Tests
```
