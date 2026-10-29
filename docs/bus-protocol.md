# Bus-Protokoll (Entwurf, Version 0)

WebSocket `ws://127.0.0.1:8765`, UTF-8-JSON, eine Nachricht pro Frame.
Jede Nachricht hat `"v": 0` und `"type"`. Zeitstempel `t_ms` = monotone
Bridge-Zeit in Millisekunden. Wird finalisiert, sobald das JC312-Protokoll bekannt ist.

## Bridge → Clients

```json
{"v": 0, "type": "telemetry", "t_ms": 123456,
 "cadence": 84.2, "cadence_raw": 86.5, "speed_kmh": 27.9,
 "power_w": 142, "power_estimated": true,
 "heart_rate": null}
```
Fehlende Werte sind `null`. Eine `telemetry` je Sample der Quelle (Simulator: alle 250 ms;
Replay/BLE: je auswertbarer Notification). `t_ms` ist immer die Bridge-Zeit beim Senden,
auch beim Replay (die Zeiten der Aufnahme stehen nur in den Rohdaten).

Datenaufbereitung (ADR-0004, für alle Quellen gleich):

| Feld | Bedeutung |
|---|---|
| `cadence` | rpm, geglättet (EMA, Zeitkonstante 0,3 s, auf 0,1 gerundet). `null`, solange die Quelle noch keinen Wert hatte (CSC: erst ab dem zweiten Kurbel-Event). `0`, wenn 2,5 s lang kein neuer Wert kam, obwohl Daten kommen (CSC: kein neues Kurbel-Event; FTMS: kein Kadenzfeld). Meldet die Quelle ausdrücklich 0, ist sie `0`, sobald der geglättete Wert unter 1 rpm fällt. Liefert die Quelle gar keine Kadenz, bleibt sie `null`. Werte außerhalb 0–200 rpm verwirft die Bridge (sie werden nicht begrenzt). |
| `cadence_raw` | rpm, **ungeglättet** (auf 0,1 gerundet) – nur für die Kadenzmuster (Antritt, Innehalten …); Anzeige und Fahrmodell nutzen `cadence` (Nachtrag #45 in ADR-0004). Dieselben Regeln wie `cadence`, nur ohne EMA: Werte außerhalb 0–200 rpm verworfen, `0` nach 2,5 s ohne neuen Wert, `null` bis zum ersten Wert. Zwischen zwei neuen Werten (CSC: wiederholtes Kurbel-Event) und nach einem verworfenen Ausreißer gilt der letzte angenommene Wert weiter. Nicht zu verwechseln mit der CSV-Spalte `cadence_raw` (Rohwert je Sample der Quelle, leer ohne neuen Wert, auch Ausreißer). Seit #45 – additiv, `v` bleibt `0`; Clients ohne das Feld ignorieren es. |
| `speed_kmh` | km/h, ungeglättet; `null`, wenn die Quelle keine liefert (Simulator, CSC – Radumfang unbekannt). |
| `power_w` | Watt, ungeglättet; `null` ohne Wert. |
| `power_estimated` | `true` = geschätzt, `false` = gemessen, `null` ohne `power_w`. Watt vom JC312 (FTMS) sind immer geschätzt. |
| `heart_rate` | bpm. Ist ein Pulsgerät verbunden (`status.heart_rate.state` `connected` oder `stale`) oder hat die Pulsquelle einen Wert jünger als 5 s, ist es der Wert der Pulsquelle (`null`, wenn er älter als 5 s ist). Sonst der Puls, den das Rad selbst liefert (FTMS Indoor Bike Data; der Simulator liefert einen, außer ein Profil schaltet ihn ab), falls es einen liefert, sonst `null`. Den Takt der `telemetry` bestimmt weiter die Radquelle. |

Clients ignorieren unbekannte Felder; neue Felder kommen additiv dazu, ohne `v` zu ändern (zuletzt `cadence_raw`, #45).
Ein Client, der `cadence_raw` nutzt, nimmt bei einer älteren Bridge ohne das Feld `cadence`.

Kommen gar keine Daten, gibt es keine erfundene Kadenz 0 – dann greift `stale` (unten).

```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble",
 "capabilities": ["CADENCE", "SPEED"]}
```
`state`: `connected | stale | disconnected`. `source`: `ble | sim | replay`.
`capabilities`: was die Quelle liefert (`CADENCE`, `SPEED`, `POWER`, `RESISTANCE_CONTROL`);
beim Replay das, was die Aufnahme enthält.

Hinter dem Radteil steht in jedem `status` der Block `heart_rate` der Pulsquelle (Brustgurt oder Uhr):
```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble", "capabilities": ["CADENCE", "SPEED"],
 "heart_rate": {"state": "connected",
                "device": {"address": "F1:2A:33:44:55:66", "name": "HRM-Pro", "role": "strap"}}}
```
`heart_rate.state`: `connected | stale | disconnected | off`. `device`: das verbundene Gerät (`address` wie
tatsächlich verbunden, `name` und `role` aus den gemerkten Geräten, `role` `strap | watch`), sonst `null`.

| `heart_rate.state` | Bedeutung |
|---|---|
| `off` | keine Geräte gemerkt – so startet die Bridge, bis ein Client `set_heart_rate_devices` schickt |
| `disconnected` | Geräte gemerkt, keines verbunden; die Bridge sucht im Hintergrund und verbindet sich mit dem besten gemerkten, das sendet (nach einem Abbruch frühestens nach 3 s) |
| `connected` | Pulsgerät verbunden, Werte kommen |
| `stale` | verbunden, aber seit > 5 s kein Pulswert; `telemetry.heart_rate` ist `null` |

Der Radteil (`state`, `source`, `capabilities`) bedeutet dasselbe wie oben und hängt nicht vom Puls ab. Eine
Änderung des Pulszustands oder des verbundenen Geräts ist eine Statusänderung wie beim Rad: genau ein `status`
an alle Clients je Änderung, nie doppelt, nie ohne Änderung; neue Clients bekommen den aktuellen Block im ersten
`status`. Ein verbundenes Gerät mit geringerem Vorrang (Uhr) wird gegen eines mit höherem (Gurt) getauscht, sobald
dieses sendet – das ist ein `status` mit neuem `device`, ohne `disconnected` dazwischen.

`status` kommt
- als **erste Nachricht** an jeden neuen Client (aktueller Stand), und
- als Broadcast an alle Clients **genau einmal je Änderung** des Zustands – nie doppelt,
  nie ohne Änderung.

| `state` | Bedeutung (ADR-0004) |
|---|---|
| `connected` | Quelle verbunden, Daten kommen. Kadenz 0 mit weiterlaufenden Daten bleibt `connected`. |
| `stale` | verbunden, aber seit > 3 s keine Daten. Games pausieren. |
| `disconnected` | Verbindung weg (oder Quelle beendet, z. B. Ende des Replays). Die Bridge versucht alle 3 s neu zu verbinden. Games pausieren. Auch vor dem Start der Quelle (Replay mit `--wait-client` bis zum ersten Client). |

Übergänge: `connected → stale → connected` (Daten kommen wieder), `connected | stale →
disconnected → connected`. `telemetry` gibt es nur bei `connected`: kommen nach `stale`
wieder Daten, geht zuerst `status: connected` raus, dann die Telemetrie.

## Clients → Bridge

```json
{"v": 0, "type": "set_grade", "grade": 0.07}
```
`grade` ist die virtuelle Steigung als Anteil (0.07 = 7 %, negativ = bergab), eine
endliche Zahl (kein String, kein `true`/`false`, kein NaN/Infinity). Einen Wertebereich
prüft die Bridge nicht – Sicherheitsgrenzen liegen im Gerät (ADR-0007).

### Puls: gemerkte Geräte

```json
{"v": 0, "type": "set_heart_rate_devices",
 "devices": [{"address": "F1:2A:33:44:55:66", "name": "HRM-Pro", "role": "strap"},
             {"address": "C8:11:22:33:44:55", "name": "Forerunner 970", "role": "watch"}]}
```
Die gemerkten Geräte gehören dem Spiel (`user://settings.cfg`); die Bridge speichert nichts. Das Spiel schickt sie
nach jedem (Neu-)Verbinden mit dem Bus, auch an eine geteilte, schon laufende Bridge. Die Reihenfolge ist der
Vorrang (Gurt vor Uhr: zuerst der Gurt). Jeder Client darf sie setzen, zuletzt gesetzt gewinnt. Eine leere Liste
schaltet den Puls aus (`off`, eine Verbindung wird getrennt). Jeder Eintrag braucht `address` (nicht leerer
Text), `name` (Text; ein Gerät wird an der Adresse oder, wenn die nicht passt, am Namen erkannt) und `role`
(`strap | watch`). Antwort: `ack` mit `for: "set_heart_rate_devices"`, `ok: true`; ändert sich dadurch der
Pulszustand, kommt der `status` vor dem `ack`. Dieselbe Liste noch einmal ändert nichts (kein `status`).

### Puls: Suche auf Anfrage

```json
{"v": 0, "type": "start_heart_rate_search", "duration_s": 30}
{"v": 0, "type": "stop_heart_rate_search"}
```
Sucht nach Geräten mit Heart Rate Service `0x180D` – für einen Gerätedialog im Spiel. `duration_s` ist optional
(fehlt oder `null`: 30 s), eine Zahl > 0 und höchstens 120. Antwort jeweils `ack` (`ok: true`). Die Ergebnisse
gehen **nur an den Client, der die Suche gestartet hat**, nie als Broadcast:
```json
{"v": 0, "type": "heart_rate_found", "t_ms": 123456,
 "address": "F1:2A:33:44:55:66", "name": "HRM-Pro", "rssi": -58}
```
Auch nicht gemerkte Geräte. `name` ist `null`, wenn das Gerät keinen sendet; `rssi` ist die Signalstärke in dBm.
Ein Gerät kommt beim ersten Fund und danach höchstens einmal je Sekunde mit der aktuellen Signalstärke, sofort nur,
wenn sich sein Name ändert (Geräte kündigen sich mehrmals je Sekunde an; die Signalstärke schwankt dabei ständig
und zählt deshalb nicht als Änderung). Die Hintergrundsuche nach gemerkten Geräten läuft unabhängig davon weiter.

Es gibt eine Suche zur Zeit. Startet ein anderer Client eine Suche, gehören die Ergebnisse ab dann ihm; der
bisherige Anfrager bekommt `heart_rate_search_ended`. Startet derselbe Client neu, beginnt die Suche mit der neuen
Dauer von vorn (ohne Meldung). `stop_heart_rate_search` beendet nur die eigene Suche (Antwort nur `ack`); ohne
eigene Suche hat es keine Wirkung. Trennt sich der Anfrager, endet seine Suche.
```json
{"v": 0, "type": "heart_rate_search_ended", "t_ms": 123456, "reason": "timeout"}
```
Nur an den Anfrager, wenn seine Suche ohne sein `stop` endet. `reason`: `timeout` (Dauer abgelaufen) oder
`taken_over` (ein anderer Client sucht jetzt). Ohne Bluetooth-Adapter scheitert die Suche still: `ack`, keine
Ergebnisse, nach Ablauf `timeout`.

### Fahrt speichern (Spec #84)

```json
{"v": 0, "type": "save_ride", "ride_id": "a1b2c3",
 "start_t_ms": 123456, "end_t_ms": 3723456, "lap_end_t_ms": [1923456],
 "distance": [[123456, 0.0], [124456, 8.1], [3723456, 28012.5]], "upload": true}
```
Am Ende einer Fahrt: Die Bridge schreibt die FIT-Datei der Fahrt aus der Session-CSV dieses Bridge-Laufs und lädt sie
auf Wunsch einmal zu Garmin Connect hoch (ADR-0008, Nachtrag #84). Alle `t_ms` sind Bridge-Zeit (`telemetry.t_ms`).

| Feld | Regel |
|---|---|
| `ride_id` | 1–64 Zeichen aus `A–Z a–z 0–9 _ -`; Teil des Dateinamens. Gleiche `ride_id` = dieselbe Fahrt (Datei und Upload-Marke). |
| `start_t_ms`, `end_t_ms` | ganze Zahlen ≥ 0 (auch `123.0`), `end_t_ms` > `start_t_ms` und nicht nach der aktuellen Bridge-Zeit – eine Fahrt aus einem früheren Bridge-Lauf steht nicht in dieser Session-CSV. Ausnahme: Die Fahrtablage kennt die `ride_id` schon aus einem früheren Bridge-Lauf (siehe unten). |
| `lap_end_t_ms` | optional (fehlt/`null` = keine Runde): Liste ganzer Zahlen, das Ende jeder vollen Runde. Werte außerhalb (Start, Ende] zählen nicht; ein Rest nach der letzten vollen Runde wird ein eigener Lap. |
| `distance` | Streckenspur des Spiels, etwa 1 Hz: Liste von `[t_ms, Meter]`, `t_ms` streng steigend, Meter endliche Zahl ≥ 0 und nicht fallend; leer = Datei ohne Strecke und Geschwindigkeit. Arcade-Fahrten wie gefahren. Ein Frame darf höchstens 1 MiB groß sein (bei 1 Hz und auf 0,1 m gerundeten Metern reicht das für über 10 h). |
| `upload` | `true` oder `false`: zu Garmin Connect hochladen? Die FIT-Datei entsteht immer. |

Ein ungültiger Befehl bekommt sofort `error` mit `reason: "invalid_ride"`. Sonst gibt es kein `ack`: Die Antwort ist
`ride_saved`, **nur an den Client, der gespeichert hat**, nie als Broadcast, sobald Datei und Upload fertig sind (der
Upload kann Sekunden dauern; Telemetrie und Bus laufen weiter, auch für den Absender):
```json
{"v": 0, "type": "ride_saved", "ride_id": "a1b2c3",
 "fit_path": "C:\\Users\\…\\sessions\\rides\\2026-10-28_18-04-12_a1b2c3.fit", "fit_error": null,
 "upload": {"state": "uploaded", "message": "Fahrt zu Garmin Connect hochgeladen."}}
```
`fit_path`: absoluter Pfad der Datei `<sessions_dir>/rides/<zeit>_<ride_id>.fit` (`<zeit>` = Start der Fahrt in Ortszeit,
`YYYY-MM-DD_HH-MM-SS`), `null`, wenn keine entstand; dann steht in `fit_error` der Grund (deutsch, für den Dialog), etwa
`FIT-Export nicht möglich: fit-tool fehlt (im Ordner bridge/: pip install -e ".[fit]")`, und `upload` ist `null`.
Erneutes Speichern derselben `ride_id` **im selben Bridge-Lauf** schreibt dieselbe Datei neu (gleiche Angaben, gleiche
Bytes). **In einem späteren Bridge-Lauf** (etwa nach einem gescheiterten Upload, `pip install -e ".[garmin]"` und Neustart)
baut die Bridge die Datei nie neu – die Bridge-Zeit beginnt je Lauf bei 0, die neue Session-CSV hätte unter denselben
`t_ms` fremde Samples. Sie nimmt die vorhandene Datei unverändert: `fit_path` nennt sie, der Upload läuft wie sonst mit
genau dieser Datei (Upload-Marke, höchstens ein Versuch); die Angaben des neuen `save_ride` außer `upload` zählen dann
nicht, auch die Bridge-Zeit nicht. Fehlt die Datei, ist `fit_path` `null`, `upload` `null`, und `fit_error` sagt es:
`FIT-Datei <name> fehlt in der Fahrtablage. Die Fahrt stammt aus einem früheren Bridge-Lauf und lässt sich nicht neu
schreiben – ihre Samples stehen nicht in dieser Session.` Welcher Lauf eine Fahrt geschrieben hat, merkt sich die
Fahrtablage (`rides/rides.json`, Name der Session-CSV je `ride_id`). `upload.message` ist ein deutscher Text für den
Dialog, ohne Zugangsdaten und ohne Fehlertexte der Bibliothek:

| `upload.state` | Bedeutung | `message` |
|---|---|---|
| `uploaded` | hochgeladen (Erfolg) | `Fahrt zu Garmin Connect hochgeladen.` |
| `duplicate` | Garmin kennt die Fahrt schon (Erfolg) | `Die Fahrt ist schon in Garmin Connect.` |
| `already_uploaded` | schon von dieser Bridge hochgeladen, kein zweiter Versuch (Erfolg) | `Die Fahrt ist schon in Garmin Connect – nicht erneut hochgeladen.` |
| `skipped` | `upload: false` | `Nicht hochgeladen – der Upload ist für diese Fahrt abgeschaltet.` |
| `not_logged_in` | keine Token-Datei, Garmin nicht gefragt | `Nicht bei Garmin angemeldet – im Terminal anmelden: python -m vspin_bridge.garmin login` |
| `auth_expired` | Token abgelaufen oder abgelehnt | `Anmeldung abgelaufen – bitte neu anmelden (python -m vspin_bridge.garmin login).` |
| `rejected` | Garmin lehnt ab (4xx, auch 429) | `Garmin Connect meldet zu viele Anfragen – später erneut versuchen. Die FIT-Datei bleibt für den manuellen Import liegen.` bzw. `Garmin Connect hat die Fahrt abgelehnt (HTTP 4xx). Die FIT-Datei bleibt für den manuellen Import liegen.` |
| `failed` | Netz, 5xx, Unbekanntes, Bibliothek passt nicht | `Upload zu Garmin Connect gescheitert (…). Die FIT-Datei bleibt für den manuellen Import liegen.` (Varianten in `garmin/uploader.py`) |
| `unavailable` | Bibliothek `garminconnect` nicht installiert | `Garmin-Upload nicht installiert: pip install -e ".[garmin]" im Ordner bridge/.` |

Höchstens ein Upload-Versuch je `save_ride`, nichts wird wiederholt (Garmin sperrt Konten nach Fehlversuchen). Nach
einem Erfolg (`uploaded`, `duplicate`) merkt sich die Bridge die `ride_id` in der Fahrtablage (`rides/rides.json`, auch
über einen Neustart); ein gescheiterter Upload nicht – erneutes Speichern darf es noch einmal versuchen. Gespeichert wird
eine Fahrt zur Zeit, weitere `save_ride` warten.

**Anmeldezustand:** Hinter dem Pulsblock steht in jedem `status` der Block `garmin`:
```json
{"v": 0, "type": "status", "t_ms": 123456, "state": "connected", "source": "sim", "capabilities": ["CADENCE"],
 "heart_rate": {"state": "off", "device": null}, "garmin": {"login": "logged_in"}}
```
`garmin.login`: `logged_in` heißt nur, dass die Token-Datei `garmin_tokens.json` im Token-Verzeichnis existiert (sie
wird nicht gelesen; ob das Token noch gilt, zeigt erst ein Upload); das Verzeichnis allein zählt nicht – es bleibt nach
`logout` der Bibliothek stehen und liegt während der Anmeldung im Terminal schon leer da. `not_logged_in` (Anmelden im
Terminal: `python -m vspin_bridge.garmin login`), `unavailable` (Bibliothek fehlt). Die Bridge prüft ihn beim Start, nach
jedem `save_ride` und alle 5 s (Anmeldung im Terminal, während die Bridge läuft); eine Änderung ist eine Statusänderung:
genau ein `status` an alle, nie ohne Änderung. Seit #84 – additiv, `v` bleibt `0`.

## Clients → alle anderen Clients (Spiel ↔ Begleiter)

Seit #77, additiv, `v` bleibt `0`. Spiel und Begleiter (`vspin-companion`, ADR-0002 Nachtrag #76) sprechen über
die Bridge miteinander: `ride_state`, `ride_event`, `companion_ptt` und `companion_status` leitet die Bridge an
**alle anderen** verbundenen Clients weiter, **nie an den Sender**.

- **Unverändert:** Der empfangene Textframe geht Zeichen für Zeichen weiter. Die Bridge prüft nur den Umschlag wie
  bei jeder Client-Nachricht – JSON-Objekt, `type` vorhanden, `v` gleich `0` –, sonst kommt das übliche `error`
  (unten) und nichts wird weitergeleitet. Die übrigen Felder prüft sie nicht und kennt sie nicht; neue Felder
  gehen ohne Änderung der Bridge durch.
- **Keine Antwort:** Der Sender bekommt weder `ack` noch `error` (bei `ride_state` alle 5 s und der Sprechtaste
  wäre jede Antwort nur Last). Ist sonst niemand verbunden, geht die Nachricht ins Leere.
- Die Bridge speichert nichts davon und schreibt nichts davon in die Session.
- Empfänger ignorieren unbekannte Typen, unbekannte Felder und unbekannte Werte (`kind`, `action`, `state`).
- Fehlende Werte sind `null` (z. B. Puls ohne Pulsgerät, #64; Watt ohne Messung, #75).

### `ride_state` (Spiel → Begleiter)

Fahrtzustand, alle 5 s während einer Fahrt (nicht im Menü, nicht in der Pause):

```json
{"v": 0, "type": "ride_state",
 "mode": "rundfahrt", "direction": "cw", "lap": 2, "laps": 3,
 "km_done": 12.4, "km_left": 5.6,
 "section": "Serpentinen", "next_sight": "Bergdorf", "next_sight_km": 1.8,
 "grade": 0.07, "speed_kmh": 18.2, "cadence": 84.0, "power_w": null, "power_estimated": null,
 "heart_rate": 142, "hr_zone": 2,
 "ghost_gap_s": -3.2, "best_time_s": 1234.5, "companion_volume": 0.8}
```

| Feld | Bedeutung |
|---|---|
| `mode` | Spielmodus wie im Fahrtenbuch: `rundfahrt`, `training`, `arcade` |
| `direction` | Richtung der Runde: `cw` (im Uhrzeigersinn), `ccw` |
| `lap`, `laps` | aktuelle Runde (ab 1); geplante Runden, `null` = endlos |
| `km_done`, `km_left` | km gefahren in dieser Fahrt; km bis zum Ziel, `null` = endlos |
| `section`, `next_sight`, `next_sight_km` | aktueller Abschnitt des Rundkurses; nächste Sehenswürdigkeit und km bis dorthin (`null`, wenn keine mehr kommt) |
| `grade` | virtuelle Steigung als Anteil (wie `set_grade`) |
| `speed_kmh`, `cadence` | Spieltempo; Kadenz wie in `telemetry.cadence` |
| `power_w`, `power_estimated` | wie in `telemetry` |
| `heart_rate`, `hr_zone` | bpm und Pulszone 1–5; `null` ohne Puls |
| `ghost_gap_s` | Abstand zum Ghost in Sekunden, negativ = vor dem Ghost; `null` ohne Ghost |
| `best_time_s` | Bestzeit für Strecke und Richtung in Sekunden; `null` ohne Bestzeit |
| `companion_volume` | Lautstärke der Stimme des Begleiters, 0–1, wie im Einstellungsmenü des Spiels („Toni-Stimme“). Der Begleiter spricht über das Windows-Standardgerät, nicht über das Spiel – deshalb gibt das Spiel den Wert weiter, und eine Änderung wirkt spätestens nach 5 s. Kommt auch bei `ride_start` |

### `ride_event` (Spiel → Begleiter)

Ereignis in der Fahrt, sofort beim Eintreten. Pflichtfeld `kind`, weitere Felder je `kind`:

```json
{"v": 0, "type": "ride_event", "kind": "medal", "medal": "gold", "for": "lap"}
```

| `kind` | weitere Felder |
|---|---|
| `ride_start` | `mode`, `direction`, `laps` (wie `ride_state`), `companion_volume` (wie bei `ride_state`) und `logbook`: Kurzfassung des Fahrtenbuchs `{"rides": 42, "km_total": 812.5, "recent": [{"date": "2026-10-27T17:02:11Z", "mode": "rundfahrt", "distance_km": 18.2, "duration_s": 2700.0, "avg_cadence_rpm": 82.0}]}` (höchstens 5 letzte Fahrten, neueste zuerst, Felder wie im Fahrtenbuch; ohne die Fahrt, die gerade beginnt) |
| `ride_end` | `finished` (Ziel erreicht), `distance_km`, `duration_s` |
| `lap` | `lap` (abgeschlossene Runde), `time_s` |
| `medal` | `medal`: `bronze`/`silver`/`gold`; `for`: `lap` oder die Segment-ID (z. B. `bergwertung`) |
| `best_time` | `time_s`, `previous_s` (`null` bei der ersten Bestzeit); `for`: `lap` oder die Segment-ID |
| `achievement` | `id`, `name` des Erfolgs |
| `boss_start`, `boss_end` | `boss` (Name); bei `boss_end` zusätzlich `defeated` (`true`/`false`) |
| `interval_start` | `target_cadence` (rpm), `duration_s` |
| `pause` | `paused`: `true` beim Anhalten, `false` beim Weiterfahren |

### `companion_ptt` (Spiel → Begleiter)

Sprechtaste (Leertaste in der Fahrt):

```json
{"v": 0, "type": "companion_ptt", "action": "down"}
```
`action`: `down` beim Drücken, `up` beim Loslassen. Der Begleiter hört nur zwischen `down` und `up` zu. Ein `up`
ohne vorheriges `down` ignoriert er.

### `companion_status` (Begleiter → Spiel)

```json
{"v": 0, "type": "companion_status", "state": "speaking", "speaking": true}
```

| `state` | Bedeutung |
|---|---|
| `idle` | bereit, schweigt |
| `listening` | Sprechtaste gedrückt, Toni hört zu |
| `thinking` | Toni denkt über die Antwort nach |
| `speaking` | Toni spricht |
| `hoarse` | **heiser**: ein Fehler (kein Netz, Anmeldung abgelaufen, Abo-Limit, Dienst gestört) – Toni schweigt, die Fahrt läuft weiter. Das nächste `companion_ptt down` versucht es neu. |

`speaking` ist `true`, solange Toni spricht – das Spiel duckt dann seinen Ton. Der Begleiter sendet
`companion_status` nach jedem (Neu-)Verbinden mit dem Bus, bei jeder Änderung von `state` (nie doppelt) und als
Antwort auf jedes `ride_event` mit `kind: "ride_start"` – so kennt ein Spiel, das nach ihm an den Bus kam, seinen
Stand spätestens zu Fahrtbeginn. Hat das Spiel noch kein `companion_status` gesehen, gilt: kein Begleiter am Bus.

## Antworten an den sendenden Client

`ack` und `error` gehen **nur an den Client, der die Nachricht gesendet hat**, nie als
Broadcast. Die Verbindung bleibt danach offen; andere Clients merken nichts davon.

### `ack`

```json
{"v": 0, "type": "ack", "for": "set_grade", "ok": false, "reason": "not_supported"}
```
`for`: Typ der beantworteten Nachricht. `ok`: ob die Quelle den Befehl umgesetzt hat.
`reason`: bei `ok: false` der Grund, sonst `null`. Solange die Quelle keine Capability
`RESISTANCE_CONTROL` hat, ist die Antwort auf `set_grade` immer
`ok: false, reason: "not_supported"`. Der Simulator wertet die Steigung trotzdem aus
(bergauf sinkt die simulierte Kadenz).

| `reason` | Ursache |
|---|---|
| `not_supported` | Quelle ohne Capability `RESISTANCE_CONTROL` |
| `source_error` | Quelle hat den Befehl mit einem Fehler abgelehnt (Details im Bridge-Terminal); die Verbindung bleibt offen |

### `error`

Antwort auf eine kaputte oder unbekannte Client-Nachricht:
```json
{"v": 0, "type": "error", "reason": "invalid_grade", "detail": "'grade' muss eine Zahl sein, war '0.07'"}
```
`detail` ist ein menschenlesbarer Text (kein fester Inhalt). `reason`:

| `reason` | Ursache |
|---|---|
| `invalid_json` | kein gültiges JSON oder Binärframe statt Textframe |
| `invalid_message` | kein JSON-Objekt oder Feld `type` fehlt |
| `unsupported_version` | `v` fehlt oder ist nicht `0` |
| `unknown_type` | `type` ist keine bekannte Client-Nachricht |
| `invalid_grade` | `grade` fehlt oder ist keine endliche Zahl |
| `invalid_devices` | `devices` fehlt, ist keine Liste, oder ein Eintrag ist kein Objekt mit `address` (nicht leerer Text), `name` (Text) und `role` (`strap` oder `watch`) |
| `invalid_duration` | `duration_s` ist keine Zahl oder nicht > 0 und höchstens 120 |
| `invalid_ride` | `save_ride` verletzt eine Regel aus „Fahrt speichern“ (Feld fehlt, falscher Typ, `ride_id` unzulässig, Ende nicht nach dem Start oder nach der Bridge-Zeit, Streckenspur nicht steigend) |
