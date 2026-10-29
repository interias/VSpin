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
| `power_estimated` | `true` = geschätzt, `false` = gemessen, `null` ohne `power_w`. Watt vom JC312 (FTMS, Replay) sind immer geschätzt; der FTMS-Trainer (`source: "ble"`) misst sie: `false` (ADR-0004, Nachtrag Spec #75). |
| `heart_rate` | bpm. Ist ein Pulsgerät verbunden (`status.heart_rate.state` `connected` oder `stale`) oder hat die Pulsquelle einen Wert jünger als 5 s, ist es der Wert der Pulsquelle (`null`, wenn er älter als 5 s ist). Sonst der Puls, den das Rad selbst liefert (FTMS Indoor Bike Data; der Simulator liefert einen, außer ein Profil schaltet ihn ab), falls es einen liefert, sonst `null`. Den Takt der `telemetry` bestimmt weiter die Radquelle. |

Clients ignorieren unbekannte Felder; neue Felder kommen additiv dazu, ohne `v` zu ändern (zuletzt `cadence_raw`, #45).
Ein Client, der `cadence_raw` nutzt, nimmt bei einer älteren Bridge ohne das Feld `cadence`.

Kommen gar keine Daten, gibt es keine erfundene Kadenz 0 – dann greift `stale` (unten).

```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble",
 "capabilities": ["CADENCE", "SPEED"]}
```
`state`: `connected | stale | disconnected`. `source`: `ble | sim | replay` (`ble` = der Trainer per FTMS,
`vspin-bridge --source ble`; seine `capabilities` stehen nach dem Verbinden fest, davor nur `CADENCE`).
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

Dahinter stehen seit Spec #75 die Blöcke `trainer` (Stand der Steuerung und verbundener Trainer), `controller`
(Lenkercontroller) und `signal` (Signalstärke je Rolle) – additiv, `v` bleibt 0:
```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble", "capabilities": ["CADENCE", "POWER", "RESISTANCE_CONTROL", "SPEED"],
 "heart_rate": {"state": "off", "device": null},
 "trainer": {"control": "active", "device": {"address": "AA:BB:CC:DD:EE:01", "name": "KICKR CORE 2"},
             "mode": "sim", "target_power": null},
 "controller": {"state": "connected", "device": {"address": "CC:00:00:00:00:08", "name": "Zwift SF2", "side": "left"},
                "battery": 81},
 "signal": {"trainer": -55, "heart_rate": null, "controller": -61}}
```
`trainer.device`: der verbundene Trainer (`address`, `name` aus den gemerkten Geräten, sonst aus der Ankündigung),
`null` ohne Verbindung und bei Simulator und Replay. Ob er verbunden ist, sagt weiter `state` (Radteil).
`trainer.mode` (ERG, Spec #75): `sim` (Steigung, Indoor Bike Simulation) oder `erg` (der Trainer hält eine
Zielleistung, `set_target_power`); `trainer.target_power`: die Zielleistung in W, `null` ohne ERG. Beides beschreibt den
Auftrag an die Bridge: Auch ohne Verbindung bleibt `erg` mit der Zielleistung stehen, die nach dem Verbinden an den
Trainer geht. Simulator und Replay melden immer `sim`/`null`. Jede Änderung von `mode` oder `target_power` ist genau
ein `status` an alle Clients.

| `trainer.control` | Bedeutung |
|---|---|
| `none` | kein Trainer verbunden (vor dem ersten Verbinden, nach einem Abbruch) |
| `requesting` | verbunden, die Bridge fordert die Steuerung an (`0x00` Request Control, `0x07` Start) |
| `active` | VSpin steuert: `set_grade` wird am Trainer zum Widerstand |
| `lost` | eine andere App (z. B. Zwift) steuert den Trainer: Machine Status `0x2ADA` meldete Control Permission Lost (`0xFF`) oder einen fremden Reset, oder der Trainer antwortete `0x05`. Die Bridge schreibt dann **nichts** mehr auf den Trainer, bis er neu verbunden ist oder ein Client `reclaim_trainer_control` schickt (Knopf „Steuerung zurückholen“); erst dann fordert sie die Steuerung wieder an. Das Spiel zeigt einen Hinweis. |
| `read_only` | Bridge mit `--read-only`: keine Anforderung, kein Schreibzugriff, unabhängig vom Trainer |
| `not_supported` | Trainer ohne Indoor Bike Simulation (Target Setting Features `0x2ACC`, Bit 13) oder ohne Control Point; Simulator und Replay |
| `error` | Anforderung gescheitert (keine Antwort im Zeitlimit, Ablehnung, Schreibfehler – z. B. ohne gebondetes Pairing); Details im Bridge-Terminal, neuer Versuch beim Neuverbinden oder auf `reclaim_trainer_control` |

Jede Änderung von `trainer.control` ist eine Statusänderung: genau ein `status` an alle Clients je Änderung.
Gelesen wird der Trainer in jedem dieser Zustände weiter.

| `controller.state` | Bedeutung |
|---|---|
| `off` | kein Controller gemerkt – so startet die Bridge, bis ein Client `set_devices` mit `kind: "controller"` schickt |
| `disconnected` | gemerkt, keiner verbunden; die Bridge sucht im Hintergrund (nach einem Abbruch frühestens nach 3 s) |
| `connected` | verbunden, der Service des Controllers ist sichtbar |
| `locked` | **gesperrt:** nach dem Verbinden fehlt in der Gerätedatenbank `0xFC82` (und `00000001-19ca-4651-86e5-fa29dcdd09d1`) – ab Firmware 1.3 versteckt der Ride V2 ihn, bis er einmal in Zwift verbunden war (gilt dann etwa 24 h). Die Bridge trennt und versucht es frühestens nach 30 s wieder. Das ist kein Fehler: das Spiel zeigt „gesperrt – einmal in Zwift verbinden“. |

`controller.device`: bei `connected` und `locked` das Gerät (`side`: `left | right` aus den Herstellerdaten, sonst
die gemerkte Seite oder `null`), sonst `null`. `controller.battery`: Akku in Prozent aus Battery Level `0x2A19`
(einmal nach dem Verbinden gelesen), `null`, wenn es ihn nicht gibt. Die Bridge **schreibt nie** auf den Controller
(kein Handshake, keine Tasten, kein Abo). Jede Änderung ist eine Statusänderung: genau ein `status` je Änderung.

`signal`: Signalstärke in dBm je Rolle (`trainer`, `heart_rate`, `controller`) – die der Ankündigung, nach der das
verbundene (bzw. gesperrte) Gerät verbunden wurde; `null` ohne Gerät. Sie wird nur beim Verbinden gesetzt und löst
für sich keinen `status` aus; laufend schwankende Werte liefert die Suche auf Anfrage (`device_found`).

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

**Am Trainer** (`trainer.control: "active"`, Spec #75) wird `set_grade` zu FTMS `0x11` (Indoor Bike Simulation: Wind 0,
Steigung in 0,01 %, Crr 0,0040, Cw 0,51 kg/m). Die Bridge **drosselt** gegenüber dem zuletzt an den Trainer
**geschriebenen** Wert: geschrieben wird nur bei einer Änderung ab 0,001 (0,1 %) und höchstens alle 0,5 s (2 Hz).
Kommt eine Änderung innerhalb des Intervalls, schreibt die Bridge nach dessen Ablauf den dann aktuellen Wert – der
zuletzt gemeldete Wert geht nie verloren. Die Steigung wird nicht begrenzt; was der Trainer ablehnt, ist ein `ack` mit
Grund. Nach einem Neuverbinden fordert die Bridge die Steuerung neu an und sendet die zuletzt gemeldete Steigung nach.

**Sichere Grundlast** (Steigung 0, nie gedrosselt): Verlassen alle Clients den Bus (Spiel abgestürzt oder
geschlossen) oder verlässt ihn der Client, der zuletzt `set_grade` geschickt hat (auch wenn andere Clients bleiben),
schreibt die Bridge sofort Steigung 0; eine noch ausstehende gedrosselte Änderung verfällt. Beim Beenden der Bridge
(Strg+C, Stoppdatei, Ende des Elternprozesses) schreibt sie Steigung 0 und dann `0x01` Reset (gibt die Steuerung
zurück), bevor sie die Verbindung schließt; bei `error`, wenn der Trainer Request Control bestätigt hatte, nur das
Reset, bei `lost` nichts. Das Spiel sendet `set_grade 0`, sobald die Fahrt
pausiert oder endet, und beim Weiterfahren wieder die echte Steigung.

Solange ERG läuft (`trainer.mode: "erg"`), beantwortet die Bridge `set_grade` mit `ok: false, reason: "erg_active"` und
schreibt nichts; die Steigung merkt sie sich und schreibt sie, sobald ERG endet.

### ERG: Zielleistung

```json
{"v": 0, "type": "set_target_power", "watts": 250}
{"v": 0, "type": "set_target_power", "watts": null}
```
`watts`: ganze Zahl 0…2000 (W; eine ganzzahlige Kommazahl wie `250.0` gilt) startet bzw. hält ERG mit dieser
Zielleistung (FTMS `0x05` Set Target Power, sint16 in W); `null` beendet ERG – zurück in die Simulation, die Bridge
sendet sofort die zuletzt gemeldete Steigung (ohne eine: 0) als `0x11` nach. Das Feld ist Pflicht; alles andere ist ein
`error` mit `reason: "invalid_watts"`. Eine eigene Nachricht `set_mode` gibt es nicht: Die Zielleistung allein legt den
Modus fest (Zahl = ERG, `null` = SIM), damit nie ein Modus ohne Ziel oder ein Ziel im falschen Modus entstehen kann.

Gedrosselt wie die Steigung: geschrieben wird nur bei einer Änderung ab 1 W und höchstens alle 0,5 s, der zuletzt
gemeldete Wert wird nachgeholt. Antwort `ack` mit `for: "set_target_power"` und den Gründen wie bei `set_grade`
(`not_supported`: Trainer ohne Power Target in den Target Setting Features `0x2ACC`, Bit 3, oder Antwort `0x02`; dazu
Simulator und Replay). Nach einem Neuverbinden und auf `reclaim_trainer_control` setzt die Bridge ERG mit der letzten
Zielleistung fort, solange ERG aktiv ist; sonst die Steigung. Antwortet der Trainer auf `0x05` mit `0x02`, verlässt die
Bridge ERG (`mode: "sim"`) und sendet kein `0x05` mehr; ebenso, wenn der Trainer beim Verbinden kein Power Target meldet.

**Grundlast in ERG:** Verlassen alle Clients den Bus oder der Client, der zuletzt `set_grade` **oder**
`set_target_power` geschickt hat, oder endet die Bridge, verlässt sie ERG (`mode: "sim"`) und schreibt Steigung 0 –
beim Beenden danach `0x01` Reset; bei `lost` nichts. Das Spiel sendet beim Verlassen der Fahrt (Pause, Ziel, Menü)
zuerst `set_target_power null`, dann `set_grade 0`, beim Weiterfahren die Zielleistung der laufenden Phase.

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

### Rollen: gemerkte Geräte und Suche (Verbindungsfenster, Spec #75)

Der Mechanismus der Pulsbefehle gilt für jede Rolle (`kind`): `trainer`, `heart_rate`, `controller`.
```json
{"v": 0, "type": "set_devices", "kind": "trainer",
 "devices": [{"address": "AA:BB:CC:DD:EE:01", "name": "KICKR CORE 2"}]}
{"v": 0, "type": "set_devices", "kind": "controller",
 "devices": [{"address": "CC:00:00:00:00:08", "name": "Zwift SF2", "side": "left"}]}
{"v": 0, "type": "start_device_search", "kind": "controller", "duration_s": 30}
{"v": 0, "type": "stop_device_search", "kind": "controller"}
```
Einträge je Rolle: `trainer` `address`, `name`; `heart_rate` wie bei `set_heart_rate_devices` (dazu `role`);
`controller` `address`, `name`, `side` (`left | right | null`, optional). Antwort jeweils `ack` mit `for` = Typ der
Anfrage. Die Listen gehören dem Spiel (`user://settings.cfg`) und gehen nach jedem (Neu-)Verbinden mit dem Bus raus;
die Bridge verbindet im Hintergrund das beste gemerkte Gerät, das gerade sendet (nach einem Abbruch frühestens nach
3 s) – **Background Pairing**, ein Start ohne Dialog. `stop_device_search` ohne `kind` beendet alle eigenen Suchen.

- **Trainer:** Sobald ein Client für `trainer` eine Liste geschickt hat, gilt nur sie: die Bridge nimmt das
  **stärkste** gemerkte Gerät, das sendet (FTMS vor Cycling Power). Eine **leere Liste** heißt: kein Trainer verbindet
  sich von selbst; gesucht wird nur auf Anfrage. Ohne jede `set_devices`-Nachricht (Bridge von Hand ohne Spiel) gilt
  `--trainer` bzw. das stärkste FTMS-Gerät; die Bridge aus dem Spiel startet mit `--known-trainers` und wartet auf die
  Liste. Fällt der verbundene Trainer aus der Liste, gibt die Bridge ihn frei (Steigung 0, `0x01` Reset – wie beim
  Beenden) und trennt; danach verbindet sie den neuen und sendet ihm die zuletzt gemeldete Steigung. Läuft die Bridge
  mit Simulator oder Replay, gibt es keinen Trainer: `set_devices` bekommt `ack` (ohne Wirkung),
  `start_device_search` `ack` mit `ok: false, reason: "not_supported"`.
- **Controller:** Gefunden wird ein Zwift-Ride-Controller an Herstellerdaten der Firma `0x094A` mit erstem
  Nutzdatenbyte 7 (rechts) oder 8 (links), ersatzweise am Namen „Zwift SF2“. Der linke hat Vorrang (er gibt die
  Tasten des rechten weiter); ein verbundener rechter wird gegen den linken getauscht, sobald dieser sendet.
- **Puls:** wie oben; `set_heart_rate_devices`, `start_heart_rate_search` und `stop_heart_rate_search` sind
  **Aliase** für `kind: "heart_rate"` und bleiben wirksam. Wer eine Suche über den Alias startet, bekommt seine
  Ergebnisse und ihr Ende weiter als `heart_rate_found`/`heart_rate_search_ended`.

Ergebnisse gehen nur an den Anfrager (gedrosselt wie beim Puls):
```json
{"v": 0, "type": "device_found", "t_ms": 123456, "kind": "controller",
 "address": "CC:00:00:00:00:08", "name": "Zwift SF2", "rssi": -60, "side": "left"}
{"v": 0, "type": "device_search_ended", "t_ms": 123456, "kind": "controller", "reason": "timeout"}
```
`side` gibt es nur bei `kind: "controller"` (`null` ohne Herstellerdaten). Je Rolle gibt es eine Suche zur Zeit;
Suchen verschiedener Rollen laufen nebeneinander. Startet ein anderer Client eine Suche derselben Rolle, bekommt der
bisherige Anfrager das Ende mit `taken_over` – in der Form, in der er gesucht hat (Alias oder neu). Trennt sich der
Anfrager, enden seine Suchen.

### Steuerung zurückholen

```json
{"v": 0, "type": "reclaim_trainer_control"}
```
Nur auf ausdrücklichen Wunsch des Fahrers (Knopf „Steuerung zurückholen“ im Verbindungsfenster, sichtbar bei
`trainer.control` `lost` und `error`): Die Bridge fordert die Steuerung neu an (`0x00`, `0x07`) und sendet die zuletzt
gemeldete Steigung nach – nach denselben Regeln wie beim Verbinden; `trainer.control` meldet `requesting`, dann
`active` (oder wieder `lost`). Von selbst fordert sie nach `lost` nie neu an. Antwort `ack` mit
`for: "reclaim_trainer_control"`, nachdem der Trainer geantwortet hat; `ok: true` auch, wenn VSpin schon steuert.
Gründe bei `ok: false`: `not_supported` (kein Trainer bzw. ohne Steuerung), `read_only`, `control_lost` (der Trainer
lehnt wieder ab), `source_error` (nicht verbunden, keine Antwort).

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

Beim steuernden Trainer heißt `ok: true`: die Steigung ist angenommen. Das gilt auch, wenn die Drosselung sie (noch)
nicht schreibt – unter der Schwelle von 0,1 % oder im laufenden 2-Hz-Intervall; scheitert das spätere Nachholen, steht
das im Bridge-Terminal (und ein Verlust der Steuerung in `status.trainer`). Die Antwort kommt, nachdem der Trainer den
geschriebenen Wert bestätigt hat (höchstens 2 s Zeitlimit), bei gedrosselten Werten sofort.

| `reason` | Ursache |
|---|---|
| `not_supported` | Quelle ohne Capability `RESISTANCE_CONTROL` (Simulator, Replay, Trainer ohne Indoor Bike Simulation), oder der Trainer antwortet `0x02` (nicht unterstützt) |
| `read_only` | Bridge läuft mit `--read-only` (Nur-lesen-Modus): sie schreibt nichts auf den Trainer |
| `control_lost` | eine andere App steuert den Trainer (`status.trainer.control: "lost"`; Antwort `0x05` Steuerung nicht erlaubt) |
| `erg_active` | nur `set_grade`: ERG läuft (`status.trainer.mode: "erg"`), die Bridge schreibt keine Steigung |
| `source_error` | Quelle hat den Befehl mit einem Fehler abgelehnt (Details im Bridge-Terminal); die Verbindung bleibt offen. Am Trainer: Antwort `0x03` (ungültiger Parameter, z. B. zu steil) oder `0x04` (gescheitert), keine Antwort im Zeitlimit, Schreibfehler, Steigung außerhalb ±327,67 %, oder gerade keine Steuerung (`none`, `requesting`, `error`) – dann setzt die Bridge die Steigung nach dem Verbinden |

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
| `invalid_devices` | `devices` fehlt, ist keine Liste, oder ein Eintrag ist kein Objekt mit `address` (nicht leerer Text), `name` (Text) und – beim Puls – `role` (`strap` oder `watch`) bzw. – beim Controller – `side` (`left`, `right` oder `null`) |
| `invalid_kind` | `kind` fehlt (bei `set_devices`, `start_device_search`) oder ist nicht `trainer`, `heart_rate` oder `controller` |
| `invalid_duration` | `duration_s` ist keine Zahl oder nicht > 0 und höchstens 120 |
