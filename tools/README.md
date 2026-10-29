# tools

## Geräteprüfung – Trainer und Zwift-Controller einmal am echten Rad erfassen

Ein kleines Prüfwerkzeug für den Rechner am Rad. Es **liest nur**: Am Trainer wird nichts verstellt,
nichts geschrieben, und es verschickt nichts. Aus den Ergebnissen wird später entschieden, wie VSpin
den Trainer (Kadenz, Leistung, Widerstand) und die Lenker-Controller (Zwift Ride) ansprechen kann.

### Was es tut

1. Sucht ca. 15 s nach Bluetooth-Geräten und zeigt die Funde an. Es erkennt den **Trainer** (z. B. KICKR CORE 2)
   und alle **Zwift-Controller** („Zwift SF2“, links/rechts). Gibt es mehrere Trainer, nimmt es den mit dem
   stärksten Signal.
2. Verbindet sich mit dem Trainer, listet alle Services und Werte auf und **schreibt 60 s lang die
   Messdaten mit**. Dazu gibt es eine Anleitung mit Countdown.
3. Verbindet sich nacheinander mit jedem Controller, listet seine Services auf, liest die Firmware und sagt
   in Klartext, ob die Tasten für VSpin erreichbar wären („sichtbar“) oder gesperrt sind.
4. Schreibt eine Ergebnisdatei und sagt am Ende, welche Dateien du zurückschicken sollst.

Scheitert eine Verbindung, läuft der Rest trotzdem weiter.

### Vorbereitung

- **Zwift, die Wahoo-App und alle anderen Trainer-Apps schließen** (auch auf Handy und Tablet). Der Trainer
  erlaubt nur 3 Bluetooth-Verbindungen gleichzeitig.
- Trainer einschalten und mit einer Pedalumdrehung aufwecken. Zwift-Controller mit einer Taste aufwecken.
- Den KICKR CORE 2 vorher in den Windows-Einstellungen unter **Bluetooth & Geräte** koppeln (er verlangt
  gebondetes Pairing).
- Einmalig das Python-Umfeld der Bridge einrichten (siehe [`bridge/README.md`](../bridge/README.md),
  „Installieren“). Fehlt es, sagt das Werkzeug, was zu tun ist.

### Starten

Doppelklick auf `tools\geraete-pruefen.cmd` oder in der Kommandozeile im Repo-Ordner:

```
tools\geraete-pruefen.cmd
```

Mehr braucht es nicht. Optional:

| Option | Wirkung |
|---|---|
| `--scan-only` | nur suchen und die Funde auflisten |
| `--duration 90` | Dauer der Mitschrift am Rad in Sekunden (Standard 60) |
| `--address AA:BB:CC:DD:EE:FF` | den Trainer fest wählen statt automatisch |
| `--out ORDNER` | anderen Ausgabeordner wählen |
| `--help` | alle Optionen |

### Am Rad

Sobald die Mitschrift läuft, erscheint die Anleitung (bei 60 s):

1. 30 s **locker treten**,
2. 15 s **schneller treten**,
3. 15 s **aufhören** (Pedale stehen lassen).

Der Countdown steht in der Ausgabe. Den Widerstand musst du nicht verstellen.

### Was du zurückschickst

Die Ergebnisse liegen im Ordner `pruefung\<Datum_Zeit>\` im Repo (er wird nicht in Git aufgenommen). Am Ende
nennt das Werkzeug die genauen Pfade. Bitte schick **beide Dateien**:

| Datei | Inhalt |
|---|---|
| `geraetepruefung_<zeit>.json` | alle Funde, die Services, Features des Trainers in Klartext, Mitschrift-Auswertung, Controller-Urteil |
| `trainer_<zeit>.raw.jsonl` | die rohen Messdaten, eine Zeile je Meldung (`{"t_ms", "char", "hex"}`, Replay-Format der Bridge, ADR-0008) |

### Wenn etwas schiefgeht

| Meldung | Was tun |
|---|---|
| Bluetooth nicht verfügbar | Bluetooth-Adapter einstecken, Bluetooth in Windows einschalten |
| Kein Trainer gefunden | Trainer aufwecken, Apps schließen, Handy-Bluetooth kurz ausschalten (nur 3 Verbindungen) |
| Verbindung zum Trainer fehlgeschlagen | Trainer in Windows unter „Bluetooth & Geräte“ koppeln und erneut starten |
| Controller „nicht geprüft“ | Controller mit einer Taste aufwecken, von Zwift-App und Handy trennen |

Der Exit-Code sagt, ob etwas erfasst wurde: 0 = ja, 1 = kein Bluetooth, 2 = nichts gefunden,
3 = gefunden, aber keine Verbindung möglich, 9 = das Python-Umfeld der Bridge fehlt.

### Für Entwickler

Das Werkzeug ist `ble_discovery.py` (nur `bleak`, kein Import aus der Bridge). Der Test
`bridge/tests/test_geraetepruefung.py` fährt es gegen Fake-`bleak` und belegt, dass nie geschrieben und nie
der Control Point `0x2AD9` abonniert wird.
