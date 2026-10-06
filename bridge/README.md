# vspin-bridge

Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert
(ADR-0002, ADR-0003). Bisher implementiert: Quelle `sim` (Simulator: manuell, Profile,
Rauschen), Verbindungsstatus `connected | stale | disconnected` und der Bus nach [`docs/bus-protocol.md`](../docs/bus-protocol.md) – nur `ws://127.0.0.1:8765`.

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

## Profile

```
vspin-bridge --source sim --profile profiles/abbruch.toml
```

Ein Profil ist ein geskripteter Simulator-Ablauf als TOML-Datei; es startet mit der Bridge und
gibt statt der Tastatur die Kadenz vor (`--sim-cadence` und `+`/`-` wirken dann nicht,
`set_grade` schon). Beispiele
unter [`profiles/`](profiles/):

| Datei | Ablauf |
|---|---|
| `einrollen.toml` | 50 → 85 rpm über 1,5 min, 2 min halten, dann Ende |
| `sprint.toml` | Intervalle 80 → 130 → 70 rpm, endlos |
| `stillstand.toml` | Fahren, 8 s Kadenz 0 (Daten laufen weiter → bleibt `connected`), endlos |
| `abbruch.toml` | Fahren → 4 s keine Daten (`stale`) → Abbruch (`disconnected`) → Neuverbindung (`connected`), endlos |

Format:

```toml
name = "Mein Profil"   # optional, fürs Terminal (Standard: Dateiname)
repeat = true          # optional: am Ende von vorn (Standard: false → Quelle endet, Status disconnected)

[[steps]]              # Fahren, konstant
duration_s = 10
cadence = 80

[[steps]]              # Fahren, linear von cadence nach cadence_to
duration_s = 5
cadence = 80
cadence_to = 120

[[steps]]              # keine Daten, Verbindung bleibt (ab 3 s ohne Daten: stale)
duration_s = 4
action = "pause"

[[steps]]              # Verbindung reißt ab: Gerät duration_s lang nicht erreichbar;
duration_s = 2         # die Bridge versucht alle 3 s neu zu verbinden (ADR-0004)
action = "disconnect"
```

Die Wiedergabe ist deterministisch: ein Fahr-Schritt liefert genau `duration_s / 0,25 s`
Samples (gerundet), Kadenzen auf 0,1 rpm gerundet, unabhängig von der Rechnerlast.
Einen „reconnect“-Schritt gibt es bewusst nicht – neu verbinden ist Aufgabe der Bridge, wie
beim echten Rad; nach der Neuverbindung geht das Profil mit dem nächsten Schritt weiter.
Unbekannte Schlüssel und ungültige Werte (Kadenz außerhalb 0–200, Dauer ≤ 0) werden beim
Start mit Meldung abgelehnt.

## Rauschen

```
vspin-bridge --source sim --sim-cadence 80 --noise
vspin-bridge --source sim --profile profiles/sprint.toml --noise --seed 42
```

`--noise` legt Rauschen auf die Kadenz (normalverteilt, σ = 2 rpm, auf 0–200 begrenzt) und
Jitter in den Sample-Takt (±50 ms um 250 ms). Kadenz 0 bleibt 0. Mit `--seed N` ist die Folge
reproduzierbar (gleicher Seed, gleiche Kadenzen), ohne ist sie zufällig.

## Verbindungsstatus

`connected` → `stale` (> 3 s keine Daten) → `disconnected` (Verbindung weg) → `connected`
(ADR-0004). Kadenz 0 ist kein Datenausfall und daher nie `stale`. Nach einem Abbruch versucht
die Bridge alle 3 s neu zu verbinden. Jede Änderung geht genau einmal als `status` an alle
Clients und steht als Zeile im Terminal, z. B. `Status: stale (seit 3 s keine Daten)`.
Endet die Quelle (Profil ohne `repeat`), meldet die Bridge `disconnected` und bleibt erreichbar.

## Sessions

Jeder Bridge-Lauf schreibt eine Session-CSV (ADR-0008) nach `sessions/YYYY-MM-DD_HH-MM-SS.csv`
– relativ zum Arbeitsverzeichnis, anderer Ort mit `--sessions-dir DIR`. Der Pfad steht beim Start
im Terminal. Eine Zeile pro Sample am Bus, Spalten
`t_ms,cadence_raw,cadence,speed_kmh,power_w,power_estimated,hr_bpm,grade,status`; fehlende Werte
bleiben leer (`grade` bis zum ersten `set_grade`, `hr_bpm` in v1 immer). Jede Zeile wird sofort
geflusht, auch nach Strg+C oder Absturz bleibt eine lesbare Datei. `sessions/` ist in `.gitignore`.

## Testen

```
python -m pytest                           # im Ordner bridge/
```

Testmuster: Tests starten die Bridge als echten Prozess (`python -m vspin_bridge`,
`PYTHONPATH=src`) und prüfen nur das am Bus beobachtbare Verhalten über Test-Clients
(`tests/bridge_harness.py`, Fixtures `bridge_process`/`bus_client` in `tests/conftest.py`).
Port 8765 muss frei sein. Kein Rad, kein Windows nötig. Laufen Tests aus mehreren Checkouts
gleichzeitig, wartet jeder Lauf auf die Sperre `/tmp/vspin-bridge-tests.lock` (flock, nur
Linux/macOS; unter Windows ohne Sperre) – Bridge-Tests laufen so nie parallel.

Struktur (teils noch geplant):

```
profiles/        Beispielprofile für den Simulator (--profile)
src/vspin_bridge/
  sources/   ble (FTMS/CSC), sim (+ profile), replay  – alle implementieren DeviceSource
  parsers/   Byte → TelemetrySample
  bus/       WebSocket-Server (docs/bus-protocol.md)
  session/   Session-CSV (ADR-0008); Roh-JSONL folgt
tests/fixtures/  echte JC312-Dumps für Parser-Tests
```
