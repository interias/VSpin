# vspin-bridge

Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert
(ADR-0002, ADR-0003). Bisher implementiert: Quellen `sim` (Simulator: manuell, Profile,
Rauschen) und `replay` (aufgezeichnete Roh-Notifications durch die Parser: CSC und FTMS),
die Datenaufbereitung (Glättung, Kadenz 0, Ausreißer – ADR-0004), Verbindungsstatus
`connected | stale | disconnected`, Session-Dateien und der Bus nach
[`docs/bus-protocol.md`](../docs/bus-protocol.md) – nur `ws://127.0.0.1:8765`.

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
vspin-bridge --source replay DATEI.raw.jsonl --speed 10   # Aufnahme abspielen (siehe Replay)
```

Im Terminal: Pfeil hoch/`+` = Kadenz +5, Pfeil runter/`-` = Kadenz −5 (0–200 rpm), `q` oder
Strg+C = beenden. Die Statuszeile zeigt Quelle, Verbindungsstatus, Kadenz und Anzahl Clients.
Ohne Terminal (stdin kein TTY) ist die Tastatur aus, die Bridge läuft normal weiter.

**Sauber beenden** (Session-CSV und Rohdaten vollständig, Exit-Code 0): Strg+C, `q`, unter Linux/macOS SIGTERM,
unter Windows auch Strg+Untbr. Ohne Terminal und Signal – so beendet das Spiel unter Windows seine Bridge –
`--stop-file DATEI`: Sobald die Datei existiert, endet die Bridge sauber und räumt sie weg (eine alte Datei beim
Start wird vorher entfernt). Ein harter Abschuss (Task-Manager, TerminateProcess) lässt sich nicht abfangen; dann
bleiben nur die bis dahin geschriebenen ganzen Zeilen. `--parent-pid PID`: Läuft dieser Prozess nicht mehr (Prüfung
alle 0,5 s), endet die Bridge ebenfalls sauber; eine PID, die es nicht gibt, beendet sie sofort. Unter `pythonw` (kein Konsolenfenster) schreibt die Bridge
keine Terminal-Ausgabe.

**Start aus dem Spiel (Windows):** Ist beim Start der Inselfahrt keine Bridge auf `127.0.0.1:8765` erreichbar,
startet das Spiel sie selbst unsichtbar (`pythonw -m vspin_bridge --source sim --sessions-dir … --stop-file …
--parent-pid <Spiel>`, Einstellungen in `games/island-ride/config.cfg [bridge]`) und beendet sie beim Schließen über
die Stoppdatei. Endet das Spiel ohne sie – Absturz, „Stop“ im Godot-Editor –, beendet sich die Bridge über
`--parent-pid` selbst. Eine
schon laufende Bridge (z. B. hier von Hand gestartet) nutzt das Spiel nur mit und lässt sie laufen.

Der Bus lauscht standardmäßig nur auf `127.0.0.1`. `--host ADRESSE` (z. B. `--host 0.0.0.0`) ist für den
Container gedacht (`docker-compose.yml`, siehe [Anleitung](../docs/anleitung.md) „Mit Docker Desktop starten“), dessen Port nur auf
`127.0.0.1` des Rechners veröffentlicht wird – nativ nicht verwenden, sonst ist der Bus im Netz erreichbar.
`--port PORT` (Standard 8765) ist nur für parallele Test- und Prüfläufe gedacht (siehe „Testen“); das Spiel verbindet
sich mit `config.cfg [bus] url`. Die Bridge selbst liest `VSPIN_PORT_BASE` nicht.

Clients können `set_grade` senden (virtuelle Steigung, ADR-0007). Die Bridge antwortet dem
Absender mit `ack` (bis zur Widerstandssteuerung `ok: false, reason: "not_supported"`) und
schreibt eine Zeile ins Terminal, z. B. `set_grade +0.070 (+7.0 %) -> not_supported`.
Scheitert die Quelle mit einem anderen Fehler, lautet die Antwort `reason: "source_error"`
(der Fehler steht im Terminal); die Verbindung bleibt offen.
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
| `arcade/zone_perfekt.toml` | Arcade-Szenario (#46) „perfekt in der Zone“: 45 s 90 rpm, dann Ende |
| `arcade/zone_knapp_daneben.toml` | Arcade-Szenario „knapp daneben“: 50 s 102 rpm (2 rpm über der Zone), dann Ende |
| `arcade/zone_abbruch.toml` | Arcade-Szenario „Abbruch“: 15 s 90 rpm → 4 s keine Daten → 30 s `disconnected` → 30 s 90 rpm, dann Ende |
| `arcade/durchbruch_geschafft.toml` | Arcade-Szenario (#47) „Durchbruch geschafft“: 12 s 90 rpm, 8 s 114 rpm (über der Schwelle 108 rpm), 10 s 90 rpm, dann Ende |
| `arcade/durchbruch_zu_schwach.toml` | Arcade-Szenario „Durchbruch zu schwach“: 12 s 90 rpm, 22 s 104 rpm (unter der Schwelle), 10 s 90 rpm, dann Ende |
| `arcade/jagd_entkommen.toml` | Arcade-Szenario „Jagd entkommen“: 12 s 90 rpm, 14 s 100 rpm (über der Schwelle 93 rpm), 10 s 90 rpm, dann Ende |
| `arcade/jagd_eingeholt.toml` | Arcade-Szenario „Jagd eingeholt“: 12 s 90 rpm, 14 s 80 rpm (unter der Schwelle), 10 s 90 rpm, dann Ende |
| `arcade/takt_getroffen.toml` | Arcade-Szenario (#48) „Takt getroffen“: 12 s 70 rpm, dann fünfmal im Takt von 5 s auf 86 rpm hoch (je 1,5 s oben) und zurück auf 70 rpm, 8 s 70 rpm, dann Ende |
| `arcade/takt_verfehlt.toml` | Arcade-Szenario „Takt verfehlt“: 45 s 100 rpm (über der Zone 74–94 rpm der Takt-Tore), dann Ende |
| `arcade/sammeln_viel.toml` | Arcade-Szenario „Sammeln viel“: 45 s 108 rpm (Magnetradius rund 3,9 m), dann Ende |
| `arcade/sammeln_wenig.toml` | Arcade-Szenario „Sammeln wenig“: 45 s 78 rpm (knapp über der Rampe 75 rpm, Magnetradius rund 1,3 m), dann Ende |
| `arcade/antritt.toml` | Messprofil Kadenzmuster (#45): drei Antritte aus 80 rpm (+30 in 0,5 s, +30 in 1,5 s, +26 in 2 s), dann Ende |
| `arcade/innehalten.toml` | Messprofil Kadenzmuster (#45): zweimal 3 s Kadenz 0 (aus 80 und 110 rpm), am Ende 1,5 s (kein Innehalten), dann Ende |

Die Arcade-Szenarien `zone_*` spielt das Spiel auch in seinen Tests nach (`games/island-ride/tests/test_arcade_ride.gd`, gleicher
Kadenzverlauf über den Fake-Bus) und prüft dort das Ergebnis: geschafft, weich verfehlt, Pause bei Abbruch. `takt_*` und `sammeln_*` (#48) spielt
`games/island-ride/tests/test_arcade_rhythm_collect_ride.gd` nach (Takt getroffen/verfehlt, Sammeln viel/wenig).

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

## Replay

```
vspin-bridge --source replay aufnahme.raw.jsonl              # im Takt der Aufnahme
vspin-bridge --source replay aufnahme.raw.jsonl --speed 10   # zehnmal so schnell
vspin-bridge --source replay aufnahme.raw.jsonl --wait-client
```

Spielt rohe BLE-Notifications ab – aus `tools/ble_discovery.py` (`jc312_notify_*.raw.jsonl`)
oder aus einer Session (`sessions/*.raw.jsonl`) – und schickt sie durch dieselben Parser wie
später beim echten Rad. Format: eine Zeile pro Notification,

```
{"t_ms": 1750, "char": "00002a5b-0000-1000-8000-00805f9b34fb", "hex": "03ef030000000301000003"}
```

(`t_ms` Zeit der Aufnahme in ms, nicht fallend; `char` volle 128-Bit-UUID; `hex` die Bytes).
Leere Zeilen werden übersprungen; eine kaputte Zeile bricht den Start mit Zeilennummer ab.
`--speed` (> 0, Standard 1) teilt die Abstände der Aufnahme. Mit `--wait-client` beginnt das
Abspielen erst, wenn sich der erste Client mit dem Bus verbindet (bis dahin `disconnected`) –
so verpasst ein Game oder Test nichts. Am Ende der Datei endet die Quelle (`disconnected`), die
Bridge bleibt erreichbar. `capabilities` im `status` ist das, was die Aufnahme enthält.

Ausgewertete Characteristics:

| Characteristic | Werte |
|---|---|
| CSC Measurement `0x2A5B` | Kadenz aus den Kurbeldaten (Δ Umdrehungen / Δ Event-Zeit, Überlauf beider uint16-Zähler berücksichtigt). Raddaten werden gelesen, aber nicht ausgewertet: ohne Radumfang keine Geschwindigkeit (`speed_kmh` bleibt `null`). Nach > 64 s ohne neues Kurbel-Event ist die Event-Zeit nicht mehr eindeutig – das nächste Event ist dann nur neuer Bezugspunkt. |
| FTMS Indoor Bike Data `0x2AD2` | Flag-basiert (uint16 Flags): alle Felder werden gelesen, damit die Offsets stimmen; genutzt werden Instantaneous Speed (0,01 km/h – vorhanden, wenn Bit 0 „More Data“ **nicht** gesetzt ist), Instantaneous Cadence (0,5 rpm), Instantaneous Power (W) und Heart Rate (bpm; 0 = kein Sensor → `null`). Was laut Flags fehlt, ist `null`. Die Leistung gilt als geschätzt: `power_estimated` ist `true` (ADR-0004 – das JC312 kennt die Stellung des Widerstandsknopfs nicht). Bytes hinter den angekündigten Feldern werden ignoriert. |

Andere Characteristics und zu kurze Pakete werden übersprungen (eine Zeile im Terminal je Art),
stehen aber trotzdem in den Session-Rohdaten. Jede ausgewertete Notification ergibt genau ein
Sample am Bus.

## Datenaufbereitung

Gilt für alle Quellen gleich, auch für den Simulator (ADR-0004):

- **Ausreißer:** Kadenzwerte außerhalb 0–200 rpm werden verworfen (nicht begrenzt); im
  Terminal steht z. B. `Kadenz 800.0 rpm verworfen (außerhalb 0–200 rpm)`.
- **Glättung:** EMA mit Zeitkonstante 0,3 s, zeitbasiert (`ema += (1 − e^(−Δt/0,3 s)) · (wert − ema)`),
  nicht pro Sample. Auf den Bus geht der geglättete Wert (0,1 rpm), in die CSV zusätzlich der
  Rohwert (`cadence_raw`). Konstante Kadenz bleibt exakt; nach einer Änderung läuft der Wert in
  ~0,3 s zu 63 % nach.
- **Kadenz 0:** kommt 2,5 s lang kein neuer Kadenzwert, obwohl Samples kommen (CSC: der
  Sensor wiederholt nur das letzte Kurbel-Event; FTMS: Notifications ohne Kadenzfeld), ist
  die Kadenz 0. FTMS-Kadenz ist ein Momentanwert – jede Notification mit Kadenzfeld ist ein
  neuer Wert, auch eine gemeldete 0. Liefert eine Quelle grundsätzlich keine Kadenz
  (Capability `CADENCE` fehlt, z. B. FTMS nur mit Speed), bleibt sie `null`. Wiederholte Events liefern
  keinen neuen Wert, zählen aber für diese Regel. Kommen gar keine Daten, erfindet die Bridge
  nichts – dann wird der Status nach 3 s `stale`. Der nächste Wert nach ≥ 2,5 s ohne Wert
  startet die Glättung neu.
- **Ungeglättet für die Kadenzmuster:** Zusätzlich geht `cadence_raw` auf den Bus – dieselben Regeln (Ausreißer,
  Kadenz 0 nach 2,5 s), nur ohne EMA; zwischen zwei neuen Werten gilt der letzte. Anzeige und Fahrmodell nutzen
  `cadence`. Grund: Bei 250 ms Meldetakt kostet der EMA Antritt und Innehalten 250–500 ms (Messung unten unter
  „Testen“, Nachtrag #45 in ADR-0004).
- Geschwindigkeit, Leistung und Puls gehen ungeglättet durch.

Gerechnet wird auf der Zeitachse der Quelle – beim Replay der Aufnahme. Ein Replay liefert
daher bei jedem `--speed` dieselben Werte; am Bus steht trotzdem die Bridge-Zeit.

Meldet die Quelle ausdrücklich Kadenz 0 (Simulator, FTMS), fällt die geglättete Kadenz
(EMA) und ist 0, sobald sie unter 1 rpm liegt – von 80 rpm nach ~1,3 s, statt 0 nur
asymptotisch zu erreichen.

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

Jeder Bridge-Lauf schreibt zwei Dateien (ADR-0008) nach `sessions/` – relativ zum
Arbeitsverzeichnis, anderer Ort mit `--sessions-dir DIR`. Die Pfade stehen beim Start im Terminal.

- `YYYY-MM-DD_HH-MM-SS.csv`: eine Zeile pro Sample am Bus, Spalten
  `t_ms,cadence_raw,cadence,speed_kmh,power_w,power_estimated,hr_bpm,grade,status`. `t_ms`,
  `cadence` usw. wie am Bus; `cadence_raw` ist der Rohwert der Quelle vor der Aufbereitung –
  leer, wenn das Sample keinen neuen Wert hatte (CSC: wiederholtes Event; FTMS: kein
  Kadenzfeld), und auch verworfene
  Ausreißer stehen hier. Fehlende Werte bleiben leer (`grade` bis zum ersten `set_grade`,
  `hr_bpm`, solange die Quelle keinen Puls liefert – bisher nur FTMS mit Heart-Rate-Feld).
- `YYYY-MM-DD_HH-MM-SS.raw.jsonl`: alle rohen Notifications im Replay-Format (oben), auch nicht
  ausgewertete. Beim Replay mit unverändertem `t_ms` der Aufnahme – für eine Eingabe im Format
  von `ble_discovery.py` (Standard-`json.dumps`, `hex` klein) ist die Datei Byte für Byte gleich
  der Eingabe. Der Simulator hat keine rohen Notifications: die Datei bleibt leer, damit eine
  Session immer aus beiden Dateien besteht.

Ist einer der beiden Namen schon belegt, bekommen beide `_2`, `_3`, … angehängt. Jede Zeile wird
sofort geflusht, auch nach Strg+C oder Absturz bleiben lesbare Dateien. Scheitert das Schreiben
mitten im Lauf (z. B. Platte voll), meldet die Bridge das im Terminal, schreibt für diese Session
nichts mehr und läuft weiter. `sessions/` ist in `.gitignore`.

## Testen

```
python -m pytest                           # im Ordner bridge/
```

Testmuster: Tests starten die Bridge als echten Prozess (`python -m vspin_bridge`,
`PYTHONPATH=src`) und prüfen nur das am Bus beobachtbare Verhalten über Test-Clients
(`tests/bridge_harness.py`, Fixtures `bridge_process`/`bus_client` in `tests/conftest.py`).
Port 8765 (mit `VSPIN_PORT_BASE` 8765 + n, siehe unten) muss frei sein. Kein Rad, kein Windows nötig.

**Parallele Testläufe (#62):** `VSPIN_PORT_BASE=n` (ganze Zahl 0–466, ohne Variable 0) gibt einem Lauf – etwa je
Worktree – den eigenen Bus-Port 8765 + n; der Harness startet jede Bridge mit `--port`. Läufe mit gleichem Wert
warten aufeinander (Sperre `vspin-bridge-tests-<port>.lock` im Temp-Ordner: `fcntl.flock` unter Linux/macOS,
`msvcrt.locking` unter Windows), Läufe mit anderem Wert laufen gleichzeitig. Dazu je Lauf ein eigenes `--basetemp`:

```
VSPIN_PORT_BASE=2 python -m pytest -q -p no:cacheprovider --basetemp=<temp>/pytest-2
```

Das Spiel leitet aus demselben Wert seine Testports ab (`games/island-ride/README.md`, „Tests“). Ein ungültiger Wert
bricht den Lauf ab, statt still auf 8765 zu fallen.
Der Harness beendet die Bridge wie im Betrieb: unter Linux/macOS mit SIGTERM, unter Windows über die Stoppdatei
wie das Spiel; „Strg+C“ ist SIGINT bzw. unter Windows Strg+Untbr an die eigene Prozessgruppe.

**Messung Kadenzmuster (#45):** `python tests/cadence_latency.py` (im Ordner `bridge/`, mit `PYTHONPATH=src` oder
installiertem Paket) misst die Erkennungsverzögerung von Antritt und Innehalten am geglätteten gegen den
ungeglätteten Wert – Profile mit Meldetakt 250 ms und 1 s, Rauschen mit Seeds 1–20, dazu CSC-Replays – und gibt eine
Tabelle aus. `--profile DATEI`, `--interval MS`, `--seeds N`, `--replay DATEI.raw.jsonl` (z. B. ein JC312-Mitschnitt,
#1) wählen andere Eingaben. Die Detektoren dort sind vorläufig (Definition im Kopf der Datei); die Zahlen ohne
Rauschen hält `tests/test_cadence_raw.py` fest.

Parser und Aufbereitung werden ebenso nur von außen getestet: Replay-Fixtures unter
`tests/fixtures/` (handgebaut, erzeugt von `tests/fixtures/make_fixtures.py`; neu erzeugen mit
`python tests/fixtures/make_fixtures.py`) laufen beschleunigt durch die Bridge, geprüft werden Bus,
Session-Dateien und Terminal.

Struktur (teils noch geplant):

```
profiles/        Beispielprofile für den Simulator (--profile); arcade/: Arcade-Szenarien des Spiels (#46, #47), Messprofile Kadenzmuster (#45)
src/vspin_bridge/
  sources/      sim (+ profile), replay, später ble  – alle implementieren DeviceSource
  parsers/      rohe Notification → TelemetrySample (CSC, FTMS Indoor Bike Data)
  processing.py Datenaufbereitung (ADR-0004)
  bus/          WebSocket-Server (docs/bus-protocol.md)
  session/      Session-CSV und Rohdaten (ADR-0008)
tests/fixtures/  Replay-Fixtures (handgebaut; später echte JC312-Dumps)
tests/cadence_latency.py  Messung Erkennungsverzögerung der Kadenzmuster (#45)
```
