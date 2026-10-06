# Bus-Protokoll (Entwurf, Version 0)

WebSocket `ws://127.0.0.1:8765`, UTF-8-JSON, eine Nachricht pro Frame.
Jede Nachricht hat `"v": 0` und `"type"`. Zeitstempel `t_ms` = monotone
Bridge-Zeit in Millisekunden. Wird finalisiert, sobald das JC312-Protokoll bekannt ist.

## Bridge → Clients

```json
{"v": 0, "type": "telemetry", "t_ms": 123456,
 "cadence": 84.2, "speed_kmh": 27.9,
 "power_w": 142, "power_estimated": true,
 "heart_rate": null}
```
Fehlende Werte sind `null`. Eine `telemetry` je Sample der Quelle (Simulator: alle 250 ms;
Replay/BLE: je auswertbarer Notification). `t_ms` ist immer die Bridge-Zeit beim Senden,
auch beim Replay (die Zeiten der Aufnahme stehen nur in den Rohdaten).

Datenaufbereitung (ADR-0004, für alle Quellen gleich):

| Feld | Bedeutung |
|---|---|
| `cadence` | rpm, geglättet (EMA, Zeitkonstante 1 s, auf 0,1 gerundet). `null`, solange die Quelle noch keinen Wert hatte (CSC: erst ab dem zweiten Kurbel-Event). `0`, wenn 2,5 s lang kein neuer Wert kam, obwohl Daten kommen (CSC: kein neues Kurbel-Event; FTMS: kein Kadenzfeld). Liefert die Quelle gar keine Kadenz, bleibt sie `null`. Werte außerhalb 0–200 rpm verwirft die Bridge (sie werden nicht begrenzt). |
| `speed_kmh` | km/h, ungeglättet; `null`, wenn die Quelle keine liefert (Simulator, CSC – Radumfang unbekannt). |
| `power_w` | Watt, ungeglättet; `null` ohne Wert. |
| `power_estimated` | `true` = geschätzt, `false` = gemessen, `null` ohne `power_w`. Watt vom JC312 (FTMS) sind immer geschätzt. |
| `heart_rate` | bpm, falls die Quelle ihn mitliefert (FTMS Indoor Bike Data), sonst `null`. |

Kommen gar keine Daten, gibt es keine erfundene Kadenz 0 – dann greift `stale` (unten).

```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble",
 "capabilities": ["CADENCE", "SPEED"]}
```
`state`: `connected | stale | disconnected`. `source`: `ble | sim | replay`.
`capabilities`: was die Quelle liefert (`CADENCE`, `SPEED`, `POWER`, `RESISTANCE_CONTROL`);
beim Replay das, was die Aufnahme enthält.

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
