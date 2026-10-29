# ADR-0010: Ehrliche Bestzeiten – Arcade-Werte wirken nur im Arcade-Modus

- **Status:** akzeptiert
- **Datum:** 2026-10-07

Der Arcade-Modus folgt dem Diablo-Kreislauf: Herausforderungen und Bosse werfen Ausrüstung ab, die den Fahrer
stärker macht. Würde diese Ausrüstung auch beim Rundenfahren und im Training wirken, ließen sich Bestzeiten,
Ghosts und Medaillen „erkaufen“. Deshalb zählen außerhalb des Arcade-Modus **nur Kadenz und Steigung**.
Ausrüstung, Werte und Talente wirken nur im Arcade-Modus. Das gemeinsame **Fahrerlevel** schaltet ausschließlich
Kosmetik frei.

## Erwogene Optionen

- Ausrüstung wirkt überall (wie Zwifts Räder mit Aero-Werten): verworfen, weil Bestzeiten dann nicht mehr die
  eigene Leistung messen.

## Nachtrag (2026-10-29, Spec #75): Wertung je Geräteart, Leistungsmodell, Arcade bleibt an der Kadenz

Liefert der Trainer **gemessene** Leistung (`power_w` mit `power_estimated: false`, Quelle `ble`), kommt das Tempo
aus dem **Leistungsmodell**: Leistung und Streckensteigung, dazu Masse, Roll- und Luftwiderstand (`config.cfg
[power]`, `RideModel.target_speed_power_mps`). Die Gänge wirken dort nicht, sie verschieben nur den Widerstand am
Trainer. Ohne gemessene Leistung (Simulator, geschätzte Watt) gilt das bisherige **Kadenzmodell**. Damit zählen außerhalb
von Arcade weiter nur die eigene Leistung bzw. Kadenz und die Steigung, nie Ausrüstung.

Weil beide Modelle für dieselbe Anstrengung verschiedene Zeiten ergeben, wird je **Geräteart** (`power`, `cadence`)
getrennt gewertet: Bestzeiten, Segment-Bestzeiten, Medaillen und Ghosts. Die Geräteart steht mit der ersten Telemetrie
einer Fahrt fest und wechselt in ihr nicht; ein Ghost fährt nur gegen dieselbe Geräteart. Im Spielstand bleiben die
bisherigen Bereiche das Kadenzmodell, das Leistungsmodell bekommt eigene mit der Vorsilbe `measured_` – additiv,
ohne Versionssprung, alte Stände gelten unverändert. Die Medaillen-Schwellen rechnet dieselbe Simulation, im
Leistungsmodell mit konstant 150/200/250 W (Bronze/Silber/Gold) statt 70/85/95 rpm.

Arcade ändert sich nicht: Herausforderungen, Bosse, Kadenzmuster und Punkte hängen weiter an der Kadenz und an der
Zeit. Nur das Fahrtempo kommt auch dort aus der Leistung; es bestimmt lediglich, wo eine Herausforderung beginnt.
