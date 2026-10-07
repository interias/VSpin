# ADR-0007: Widerstandssteuerung – virtuelle Steigung über FTMS, ESP32 als Smart-Bike

- **Status:** akzeptiert
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
