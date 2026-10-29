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
  `vspin_bridge/ble/`, die die `TrainerSource` fürs Rad (#9) wiederverwenden soll.
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

## Nachtrag (2026-10-28, #84): Fahrt speichern – FIT-Export und Garmin-Connect-Upload

Der Punkt „Nach v1: Skript `csv → .fit`; Strava/Garmin Connect per manuellem Upload“ ist umgesetzt, als Teil der
Bridge statt als Skript:

- **Die Bridge exportiert**, weil nur sie loggt. Am Ende einer Fahrt schickt das Spiel `save_ride` mit Start, Ende,
  Rundenenden und der Streckenspur; die Bridge liest die Samples der Fahrt aus der Session-CSV des laufenden
  Bridge-Laufs (Zeitfenster der Fahrt, Bridge-Zeit) und schreibt `<sessions_dir>/rides/<zeit>_<ride_id>.fit`,
  git-ignoriert wie `sessions/`. Antwort `ride_saved` nur an den anfragenden Client (docs/bus-protocol.md).
- **Die Streckenspur kommt vom Spiel** (etwa 1 Hz), weil der JC312 keine Geschwindigkeit sendet. Sie ist eine Angabe
  über die Fahrt wie Start und Ende, kein Telemetrie-Logging durch das Spiel: „Nur die Bridge loggt“ bleibt.
  Arcade-Fahrten werden wie gefahren exportiert.
- **FIT-Inhalt** nach dem FIT-Cookbook (Activity): Records im Sekundentakt mit Kadenz, Puls, gemessener Leistung,
  Strecke und Geschwindigkeit aus der Spur, je Runde ein Lap, Sport Radfahren/virtuell, Hersteller `development`.
  **Geschätzte Watt werden weggelassen**, wie oben vorgesehen; beim JC312 hat die Datei damit keine Leistung.
  fit-tool ist das optionale Extra `fit`; fehlt es, meldet `ride_saved` das, und die Bridge läuft weiter.
- **Auto-Upload zu Garmin Connect, inoffiziell** über die Bibliothek `garminconnect` (optionales Extra `garmin`),
  höchstens ein Versuch je Speichern, nie automatisch wiederholt; hochgeladene Fahrten merkt sich die Fahrtablage
  (`rides/rides.json`), damit erneutes Speichern nicht doppelt hochlädt. Angemeldet wird einmal von Hand im Terminal
  (`python -m vspin_bridge.garmin login`), gespeichert wird nur das Token in `~/.garminconnect`, außerhalb des Repos.
  Gründe für den inoffiziellen Weg: Die Personal API von Garmin ist nur lesend, das Developer Program richtet sich an
  Firmen und nimmt derzeit niemanden auf.
- **Risiken:** Die Anmeldung der Bibliothek brach 2026 mehrfach, wenn Garmin sein Login änderte; nach Fehlversuchen
  sperrt Garmin Konten für mehr als 48 h; die Nutzung liegt in einer Grauzone der Nutzungsbedingungen. Deshalb bleibt
  **die FIT-Datei der Anker**: Sie entsteht immer, auch ohne Upload, und lässt sich jederzeit von Hand in Garmin
  Connect importieren. Der Upload ist eine Bequemlichkeit obendrauf.
- **Keine Trainingsbelastung:** Garmin berechnet sie nur für Dateien von Garmin- und Partnergeräten. VSpin gibt sich
  nicht als ein solcher Hersteller aus; wer die Belastung will, zeichnet parallel auf der Uhr auf und schaltet den
  Upload für diese Fahrt ab (bridge/README.md).

## Nachtrag (2026-10-29, Spec #89): Steuerprotokoll

- **Dritte Session-Datei** `YYYY-MM-DD_HH-MM-SS.control.jsonl` neben CSV und Rohdaten (gleicher Name, gleiche
  Bridge-Zeit `t_ms`, ebenfalls in `.gitignore`): je Zeile ein Ereignis der Trainer-Steuerung – Wechsel von
  `status.trainer.control` samt Grund, Schreiben und Indications auf `0x2AD9`, Notifications von `0x2ADA`, Fehler.
  Grund: Die Bridge aus dem Spiel läuft ohne Terminal, und die Rohdaten enthalten nur Messwerte; warum die Steuerung
  scheitert, wäre am Gerät sonst nicht nachweisbar. Keine Zugangsdaten; ohne Trainer bleibt die Datei leer.

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
