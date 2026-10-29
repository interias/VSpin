# ADR-0007: Widerstandssteuerung – virtuelle Steigung über FTMS, ESP32 als Smart-Bike

- **Status:** abgelöst durch den Nachtrag vom 28.10.2026 (Spec #75): Widerstand kommt aus FTMS-Smart-Trainern, der ESP32-Umbau entfällt. Der ursprüngliche Text bleibt als Zeitdokument stehen.
- **Datum:** 2026-10-06

## Kontext

Das JC312 hat einen manuellen Magnet-Widerstand. Geplant ist ein ESP32-Retrofit
(Stepper am Drehknopf + Hall-Sensor). Die Architektur soll schon jetzt so
gewählt werden, dass Widerstandssteuerung später ohne Umbau andockt.
Optionen: Game sendet (A) Widerstandsstufe oder (B) virtuelle Steigung.

## Entscheidung

**B – das Game sendet die virtuelle Steigung, das Gerät setzt sie um.**

- Bus-Nachricht ab v1: `{"type": "set_grade", "grade": 0.07}` (Anteil, 0.07 = 7 %).
- Die Bridge übersetzt das in den **FTMS Control Point** (`0x2AD9`),
  Op-Code `0x11` *Set Indoor Bike Simulation Parameters* (Steigung, Wind,
  Rollwiderstand).
- Das ESP32 meldet sich als **standardkonformes FTMS-Smart-Bike** mit Control
  Point und `RESISTANCE_CONTROL`-Capability – kein Sonderprotokoll.
- **v1:** Das Game sendet `set_grade` bereits. Die Bridge antwortet
  `not_supported` und loggt, solange die Quelle die Capability nicht hat. Der
  Simulator darf die Steigung auswerten (z. B. sinkende Kadenz bergauf).
- **Sicherheit liegt im ESP32:** begrenzte Stellgeschwindigkeit, Referenzfahrt
  für Endanschläge, Rückfall auf leichte Stufe bei Verbindungsverlust, manuelles
  Drehen hat Vorrang.
- Firmware: PlatformIO + NimBLE, unter `firmware/`, Umsetzung nach v1.

## Konsequenzen

- Das ESP32-Bike funktioniert auch mit Zwift/Kinomap.
- Die Bridge braucht keinen Sondercode: ESP32 = `BleSource` mit FTMS.
- Mapping Steigung → Stepper-Position lebt in der Firmware und wird dort kalibriert.
- Der Andockpunkt ist ab v1 end-to-end testbar (Game → Bus → Bridge).

## Verworfen

- **A (Widerstandsstufe vom Game):** Game müsste Gerätemechanik kennen;
  nicht kompatibel mit Standard-Apps.

## Nachtrag (2026-10-28, Spec #75): Widerstand aus dem FTMS-Smart-Trainer, ESP32-Retrofit entfällt

Die Entscheidung B (das Game sendet die virtuelle Steigung, das Gerät setzt sie um) bleibt. Geändert hat sich das
Gerät:

- **Widerstand kommt aus FTMS-Smart-Trainern**, erstes Gerät der Wahoo KICKR CORE 2. Der **ESP32-Retrofit entfällt
  ganz** (Entscheidung des Nutzers vom 28.10.2026); `firmware/` wird nicht gebaut.
- **Die Klasse heißt `TrainerSource`** (`bridge/src/vspin_bridge/sources/trainer.py`), nicht `BleSource`; Bus-`source`
  bleibt `ble`. Die FTMS-Bausteine stehen in `sources/trainer_control.py`.
- **Umsetzung nach FTMS 1.0:** `RESISTANCE_CONTROL` nur, wenn die Target Setting Features (`0x2ACC`, zweites
  `uint32`) Indoor Bike Simulation (Bit 13) melden und sich der Control Point `0x2AD9` abonnieren lässt. Beim Verbinden:
  Indications von `0x2AD9` **vor** dem ersten Schreiben abonnieren, `0x2ADA` beobachten, `0x00` Request Control,
  `0x07` Start, dann je `set_grade` `0x11` (Wind 0, Steigung in 0,01 %, Crr 0,0040, Cw 0,51 kg/m). Jede Anfrage wird
  mit Antwort geschrieben, die Antwort-Indication `0x80` hat ein Zeitlimit (2 s). Die Steigung wird nicht begrenzt;
  lehnt der Trainer ab (`0x03`), bekommt der Client ein `ack` mit Grund.
- **Immer nur ein Steuerer.** Meldet `0x2ADA` Control Permission Lost (`0xFF`) oder einen fremden Reset, oder antwortet
  der Trainer `0x05`, gilt die Steuerung als verloren (`status.trainer.control: "lost"`); die Bridge schreibt bis zum
  Neuverbinden nichts mehr und fordert erst dann neu an. `--read-only` schaltet das Steuern ganz ab.
- **Sicherheit liegt in der Trainer-Firmware** (statt im ESP32), **plus Grundlast in der Bridge:** Verlassen alle
  Clients den Bus oder der Client der letzten Steigung, setzt sie sofort Steigung 0; beim Beenden Steigung 0 und
  `0x01` Reset, bevor die Verbindung schließt. Das Spiel sendet beim Pausieren `set_grade 0`. Beides wird nie gedrosselt. Was bei einem harten Absturz
  der Bridge selbst geschieht, entscheidet die Firmware – das ist am Gerät zu prüfen.
- **Drosselung in der Bridge:** `0x11` nur bei einer Änderung ab 0,1 % und höchstens 2 Hz gegenüber dem zuletzt
  geschriebenen Wert; eine gedrosselte Änderung wird mit dem dann aktuellen Wert nachgeholt.
- Bus additiv, `v` bleibt 0: `status.trainer`, neue `ack`-Gründe `read_only` und `control_lost` (docs/bus-protocol.md).

ERG (P7 von Spec #75): Als zweiter Steuermodus kommt ERG über denselben FTMS Control Point dazu (`0x05` Set Target
Power); es gilt dieselbe Regel „immer nur ein Steuerer“, und die Grundlast verlässt ERG mit Steigung 0.
