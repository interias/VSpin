# ADR-0008: Datenspeicherung und Export

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

v1 verlangt, dass jede Session als Datei vorliegt (ADR-0001). Rohdaten werden
außerdem für Replay/Parser-Tests gebraucht (ADR-0003). Export nach FIT/Strava
ist erwünscht, aber nicht dringend.

## Entscheidung

- **Nur die Bridge loggt.** Games schreiben keine Telemetrie.
- **Session = ein Bridge-Start** (automatische Erkennung später).
- Pro Session zwei Dateien unter `sessions/` (in `.gitignore`):
  - `YYYY-MM-DD_HH-MM-SS.csv` – Spalten:
    `t_ms, cadence_raw, cadence, speed_kmh, power_w, power_estimated, hr_bpm, grade, status`
  - `YYYY-MM-DD_HH-MM-SS.raw.jsonl` – rohe BLE-Notifications mit Zeitstempel
    (Eingabe für `ReplaySource`).
- Keine Datenbank in v1.
- **Nach v1:** Skript `csv → .fit`; Strava/Garmin Connect per manuellem Upload.
  Geschätzte Watt werden beim Export standardmäßig weggelassen.

## Herzfrequenz

Garmin Connect ist ein Cloud-Dienst und liefert **keine** Echtzeitdaten.
Echtzeit-Puls geht stattdessen direkt per BLE Heart Rate Service (`0x180D`)
– von einem Brustgurt oder einer Garmin-Uhr im Modus „Herzfrequenz übertragen“.
Dafür ist eine zweite Quelle `HeartRateSource` in der Bridge vorgesehen
(`TelemetrySample.heart_rate`, CSV-Spalte `hr_bpm`). Umsetzung nach v1;
Spalte bleibt bis dahin leer.

## Konsequenzen

- Einfach, werkzeugneutral, keine personenbezogenen Daten im Repo.
- Bridge muss mehrere BLE-Verbindungen parallel halten können (Rad + Puls).

## Nachtrag (2026-10-07): Spielstand gehört dem Spiel

„Nur die Bridge loggt“ gilt für **Telemetrie**. Spielstand ist etwas anderes und liegt beim Spiel selbst
(`user://`): Fahrtenbuch, Bestzeiten, Ghosts (Strecke über Zeit einer Runde), Medaillen, Erfolge, Fahrerlevel und
Arcade-Fortschritt. Das Spiel schreibt keine Rohtelemetrie; wer Kadenzverläufe braucht, liest die Session-CSV der
Bridge.

## Nachtrag (2026-10-09, #64): Puls als zweite Quelle

Die `HeartRateSource` ist umgesetzt und läuft in der Bridge **neben** der Radquelle, nie an ihrer Stelle:

- **Zwei Quellen:** Die Radquelle bestimmt weiter den Telemetrie-Takt und `status.state`. Die Pulsquelle hält
  eine eigene BLE-Verbindung zu einem Brustgurt oder einer Uhr (Heart Rate Service `0x180D`) und meldet ihren
  Zustand im eigenen Block `status.heart_rate`. Die Folge „Bridge muss mehrere BLE-Verbindungen parallel halten
  können (Rad + Puls)“ ist damit eingelöst: Die Pulsquelle hat ihre eigene Verbindung hinter der BLE-Nahtstelle
  `vspin_bridge/ble/`, die die `BleSource` fürs Rad (#9) wiederverwenden soll.
- **Vorrang Gurt vor Uhr** ergibt sich allein aus der Reihenfolge der gemerkten Geräte. Eine verbundene Uhr wird
  gegen den Gurt getauscht, sobald er sendet; ihr Wert gilt, bis der Gurt den ersten liefert.
- **`telemetry.heart_rate` / `hr_bpm`:** Wert der Pulsquelle, solange ein Pulsgerät verbunden ist oder ihr Wert
  jünger als 5 s ist; älter als 5 s ist er `null` (`stale`). Liefert das Rad selbst Puls (FTMS), zählt das nur
  ohne verbundenes Pulsgerät. Die CSV-Spalte `hr_bpm` ist derselbe Wert wie am Bus; die rohen
  `0x2A37`-Notifications stehen wie die des Rads in der Session-Rohdatei.
- **Bus-Erweiterung (Version 0, additiv):** Block `heart_rate` in `status`; Befehle `set_heart_rate_devices`,
  `start_heart_rate_search`, `stop_heart_rate_search`; Suchergebnisse `heart_rate_found` nur an den anfragenden
  Client (docs/bus-protocol.md).
- **Die gemerkten Geräte gehören dem Spiel** (`user://settings.cfg`), nicht der Bridge: Das Spiel schickt sie nach
  jedem (Neu-)Verbinden mit dem Bus. Die Bridge speichert nichts dauerhaft und startet mit dem Puls `off`; der
  Launcher braucht keine neuen Startparameter.
