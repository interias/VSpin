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
Fehlende Werte sind `null`. `cadence` ist geglättet (ADR-0004).

```json
{"v": 0, "type": "status", "t_ms": 123456,
 "state": "connected", "source": "ble",
 "capabilities": ["CADENCE", "SPEED"]}
```
`state`: `connected | stale | disconnected`. `source`: `ble | sim | replay`.

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
