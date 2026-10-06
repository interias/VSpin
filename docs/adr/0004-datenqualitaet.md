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
- **Glättung:** ein einfacher EMA (~1 s) in der Bridge. Auf den Bus geht der
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
