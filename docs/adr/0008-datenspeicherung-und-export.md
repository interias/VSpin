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

## Nachtrag (2026-10-28, #76): Daten des Begleiters

- **Ablage außerhalb des Repos:** `%APPDATA%\VSpin\companion\` mit `soul.md` (Seele), `memory.md` (Gedächtnis),
  `companion.json` (Einstellungen, z. B. Wecker-Takt, Stimme), `.bak`-Sicherungen vor jedem Aufräumen und dem
  Protokoll des Begleiters (Antwortzeiten, Sprachkosten). Tests lenken die Ablage um (`--data-dir` oder
  `VSPIN_COMPANION_DIR`) und schreiben nie in das echte `%APPDATA%`.
- **Kein Audio wird gespeichert** – weder die Stimme des Fahrers noch Tonis Sprachausgabe.
- **Der Gesprächsverlauf lebt nur im Speicher**, eine Sitzung je Fahrt; was bleiben soll, steht danach in
  `memory.md`.
- **Geheimnisse** (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`) stehen nur in einer lokalen
  `.env`, nie im Repo.
