# ADR-0004: Datenqualität – so einfach wie möglich

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Das JC312 kennt die Stellung des Widerstandsknopfs nicht. Eventuell gemeldete
Watt sind daher vermutlich nur aus der Kadenz hochgerechnet. Daten können
rauschen, aussetzen oder abreißen. Vorgabe: für den Anfang so einfach wie möglich.

## Entscheidung

- **Kadenz ist der einzige Game-Input in v1.**
- **Watt** werden – falls das Rad sie liefert – nur durchgereicht, geloggt und
  als `estimated` markiert (Anzeige „~142 W“). Keine Game-Mechanik hängt daran.
  Keine eigene Watt-Schätzung, keine manuelle Gang-Eingabe.
- **Glättung:** ein einfacher EMA (0,3 s) in der Bridge. Auf den Bus geht der
  geglättete Wert, der Logger speichert zusätzlich den Rohwert.
- **Kadenz 0:** Kommt 2,5 s kein neues Kurbel-Event, ist die Kadenz 0
  (verhindert „eingefrorene“ Werte, v. a. bei CSC).
- **Ausreißer:** nur harte Plausibilitätsgrenze (0–200 rpm), Werte außerhalb
  werden verworfen. Keine weitere Statistik.
- **Verbindung:** Status `connected | stale | disconnected` auf dem Bus
  (`stale` = > 3 s keine Daten). Bridge versucht alle 3 s neu zu verbinden.
  Games pausieren bei `stale`/`disconnected` und deuten Abbruch nicht als Kadenz 0.
- **Nur eine BLE-Verbindung:** durch die Bridge gelöst (ADR-0002); bei „Gerät
  nicht gefunden“ Hinweis auf evtl. noch verbundene Kinomap/Zwift/Hersteller-App.
- **Zeitstempel:** jedes Sample bekommt einen monotonen Bridge-Zeitstempel.

## Konsequenzen

- Minimaler Code, alle Werte bleiben ehrlich gekennzeichnet.
- Bessere Watt kommen erst mit echter Messung (ESP32-Retrofit).

## Zurückgestellt

- Manuelle Gang-Eingabe zur Watt-Schätzung, Sprungerkennung, Backoff-Strategien.

## Nachtrag (2026-10-07, #19): Glättung 0,3 s statt ~1 s

- Zeitkonstante des EMA von ~1 s auf **0,3 s** gesenkt (Entscheidung des Nutzers nach dem v1-Lauf).
- Grund: Mit 1 s lief die Kadenz am Bus ca. 1 s hinter dem Treten her – unvereinbar mit dem
  Abnahmekriterium < 200 ms Kurbel → Bildschirm (ADR-0001).
- Meldet das Gerät ausdrücklich Kadenz 0, ist sie 0, sobald der geglättete Wert unter 1 rpm
  fällt – sonst erreicht der EMA 0 nur asymptotisch (mit 1 s fiel die Kadenz über 5–7 s ab).

## Nachtrag (2026-10-07): rohe Kadenz zusätzlich auf dem Bus

Für Kadenzmuster im Arcade-Modus (Antritt, Innehalten) war die geglättete Kadenz mit ~1 s zu träge. Beschlossen:
Die Bridge schickt zusätzlich `cadence_raw` (ungeglättet) in `telemetry`. Die Regel bleibt: **Anzeige und
Fahrmodell nutzen den geglätteten Wert**; `cadence_raw` dient nur der Mustererkennung. Umsetzung mit Epic 4 (#45);
der Bus-Vertrag wird additiv erweitert. Seit der Glättung von 0,3 s (Nachtrag #19) prüft #45 zuerst, ob der
geglättete Wert für die Muster schon reicht.

**Ergebnis (2026-10-09, #45): `cadence_raw` ist nötig – umgesetzt.** Gemessen mit
`bridge/tests/cadence_latency.py` (Profile `bridge/profiles/arcade/antritt.toml`, `innehalten.toml`; Replay-Fixtures
CSC; reproduzierbar, Zahlen festgehalten in `bridge/tests/test_cadence_raw.py`). Vorläufige Detektoren: Antritt =
Kadenz − Minimum der letzten 2 s ≥ +25 rpm; Innehalten = Kadenz < 10 rpm seit 2 s. Bezug ist der stetige Verlauf,
den der Fahrer tritt; das Spiel hält den letzten Wert bis zum nächsten.

| Meldetakt des Geräts | Antritt: EMA kostet | Innehalten: EMA kostet | knapper Antritt (+26 rpm in 2 s) |
|---|---|---|---|
| 250 ms (Simulator; schnelles FTMS) | 250 ms (mit Rauschen Median 220–240, max. 530) | 500 ms (Median ~490, max. 680) | geglättet verpasst (mit Rauschen 11 von 20), ungeglättet erkannt (2 von 20 verpasst) |
| 1 s (FTMS oft) | 0 | 0 | wie ungeglättet |

- **Maßstab:** Die Glättung darf der Erkennung höchstens **200 ms** hinzufügen – das Budget Kurbel → Bildschirm
  aus ADR-0001; eine Fähigkeit soll sich wie eine direkte Antwort auf die Beine anfühlen, und der Meldetakt des
  Geräts (bis zu einem Takt) kommt ohnehin dazu und lässt sich in der Bridge nicht beheben. Bei 250 ms Takt kostet der
  EMA 250–500 ms und verschiebt Schwellen (ein knapper Antritt wird geglättet nie +25 rpm) – das reicht nicht.
- **Warum bei 1 s nicht:** Der EMA ist zeitbasiert; nach 1 s holt ein neuer Wert 96 % auf. Je seltener das Gerät
  meldet, desto mehr bestimmt allein der Meldetakt die Verzögerung (Antritt bei 1 s: bis ~0,6 s, mit Jitter
  bis 1,5 s – für beide Werte gleich).
- **Umsetzung:** `cadence_raw` in jeder `telemetry`: dieselben Regeln wie `cadence` (Plausibilität, Kadenz 0 nach
  2,5 s), nur ohne EMA; der letzte angenommene Wert gilt bis zum nächsten (docs/bus-protocol.md). `cadence` bleibt
  unverändert. Das Spiel liest es als `BusClient.cadence_raw`; die Kadenzmuster (#50) nutzen **`cadence_raw`**,
  HUD und Fahrmodell weiter `cadence`.
- **Erst mit dem JC312 endgültig (#1):** Meldetakt (FTMS-Notifications bzw. CSC-Kurbel-Events je Umdrehung) und
  ob das Rad selbst glättet. Bei **CSC bestimmt die 2,5-s-Regel das Innehalten**, nicht der EMA: hört der Fahrer
  auf, wiederholt der Sensor nur das letzte Event, die Kadenz bleibt 2,5 s stehen – Innehalten (2 s) kommt
  ~2,5 s zu spät (Fixture `csc_stop`: letztes Event bei 3 s, Kadenz 0 bei 5,5 s, Innehalten bei 7,5 s statt 5 s),
  geglättet wie ungeglättet. Liefert das JC312 nur CSC, braucht Innehalten eine andere Stopp-Regel (z. B. aus dem
  letzten Kurbel-Intervall) – eine Änderung dieser ADR, nicht von #45. Die Schwellen der Muster kalibriert #50
  (Spec #27: konfigurierbar, endgültig mit #1).
