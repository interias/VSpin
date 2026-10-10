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
