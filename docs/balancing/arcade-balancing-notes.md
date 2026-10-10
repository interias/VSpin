## Lesart und Grenzen

- Die Kadenzverläufe sind **erfundene, dokumentierte Daten** (`Balancing.PROFILES`), keine Messungen. Absolute Quoten (z. B. „Einsteiger schafft Stufe 1 zu 46 %“) hängen an diesen Annahmen; belastbar sind **Verhältnisse und Brüche**: eine Herausforderung, die gegenüber ihrer Schwester oder gegenüber den Nachbarstufen abbricht, oder eine Stufe, die kein Verlauf erreicht. Kalibrieren mit echten Fahrten (JC312, #1) bleibt offen.
- Fähigkeiten (#50) und legendäre Effekte sind **nicht** simuliert (sie brauchen `cadence_raw` mit gezielten Gesten, die ein synthetischer Verlauf nur erfinden könnte). Alle Quoten sind deshalb eine Untergrenze: Fähigkeiten verstärken nur den Fortschritt mit Kadenz in der Zone.
- Fahrer „bei der Sache“ gelten für die Dauer einer Herausforderung als Zweizustandsmodell (siehe Kopf von `src/balancing.gd`); Laufbahnen legen das jeweils bessere Teil je Platz an, verwerten den Rest und geben Talentpunkte zuerst für Ausrüstungswerte aus.

## Auffälligkeiten und Nachjustierung

**Schwellen** (vorab festgelegt, gelten für diesen Lauf):

1. Eine Herausforderung, die der Trainierte auf irgendeiner Stufe zu weniger als 50 % schafft, während ihre Schwester (gleicher Baustein) dort mindestens 85 % schafft.
2. Eine Herausforderung, die der Trainierte auf Stufe 1 zu weniger als 50 % schafft.
3. Eine Seltenheit, die in einer Zelle (Verlauf × Stufe) nie fällt.
4. Eine Stufe, die weniger als die Hälfte der Laufbahnen innerhalb von 120 Läufen (90 Stunden) freischaltet.
5. Eine Schwelle (Durchbruch, Jagd, Sammeln), die auf der Obergrenze des Bereichs liegt (Tabelle „Zielzonen und Schwellen je Stufe“).

**Befunde:** (1) und (5) treffen auf *Spurt* (`durchbruch_spurt`) zu; (2), (3) und (4) auf nichts: schwächste Herausforderung des Trainierten auf Stufe 1 ist *Ufer* mit 70 %, jede Seltenheit fällt in jeder Zelle (seltenste Zelle: Einsteiger Stufe 1, 349 Legendäre in 1000 Fahrten), und alle 100 Laufbahnen jedes Verlaufs schalten Stufe 4, 5 und 6 frei (Einsteiger bis Stufe 6 in höchstens 11 Läufen).

*Spurt* lag mit `threshold_at` 0,9 bei 114 rpm und stieß ab Stufe 3 (Hub +5 rpm → 119) an die Obergrenze 120 rpm, ab Stufe 4 sitzt die Schwelle genau darauf („ab 120 rpm“ – nur das Maximum selbst genügt, dahinter der Wächter). Folge: Der Trainierte fällt von 85 % (Stufe 2) auf 49 % (Stufe 3) und 29 % (Stufe 6), die Schwester *Zugbrücke* bleibt bei 91–93 %.

| Datei | Wert vorher → nachher | Auffälligkeit vorher → nachher |
|---|---|---|
| `src/challenges/breakthrough_challenges.gd` (*Spurt*) | `threshold_at` 0,9 → 0,85 (114 → 111 rpm auf Stufe 1; Stufe 6: 120 → 118 rpm) | Trainierter, Stufe 1–6: 92 / 85 / 49 / 34 / 33 / 29 % → 94 / 93 / 89 / 89 / 86 / 84 %; Sprinter: 81 / 73 / 39 / 27 / 23 / 26 % → 84 / 81 / 77 / 76 / 72 / 71 %; Einsteiger: 27 / 4 / 0 / 0 / 0 / 0 % → 44 / 22 / 6 / 3 / 4 / 0 %; Schwelle auf der Obergrenze: Stufe 4–6 → keine (höchste 118 rpm) |

Mitgezogen: alle zusammen (Trainierter, Stufe 3–6) 83 / 80 / 79 / 78 % → 85 / 83 / 82 / 80 %, Sprinter 70 / 67 / 63 / 59 % → 72 / 70 / 66 / 61 %. Der Vorher-Bericht liegt als `arcade-balancing-vorher.md` bei (gleicher Seed, gleicher Befehl, alte Daten).

**Geänderte Testzeile** – `tests/test_arcade_tiers.gd`, `test_the_guard_catches_what_tier_and_round_would_push_out`: `var spurt := Encounters.find("durchbruch_spurt")` → `….duplicate()` plus `spurt["threshold_at"] = 0.9`. Begründung: Die Gegenprobe des Wächters (`limit_zone`) braucht eine Definition, die **ohne** Wächter über den Bereich hinausschösse; das war *Spurt* mit 90 %. Mit 85 % liegt *Spurt* auch auf Stufe 6, Runde 4 bei 118 rpm und überschießt nicht mehr. Die Assertions (`assert_gt(… + lift, 120.0)`, `Vector2(120, 120)`, `threshold_rpm == 120`) bleiben unverändert und gleich scharf – der Test hält seine eigene Kopie der alten Schwelle, statt vom Pool abzuhängen. Der Wächter selbst und jede Assertion sind unberührt.

Nicht geändert: Wächter, Kadenzbereich, Stufen (`ArcadeTiers.LIST`), Beute (`Loot`), Elite, Fähigkeiten, Muster.

## Offene Fragen an den Nutzer

Ohne messbare Schwelle, daher nicht still entschieden. Zahlen: Trainierter, ohne Ausrüstung, Stufe 1 → 6, falls nicht anders genannt.

1. **Bosse zu lang oder zu kurz?** *Drac de na Coca* Stufe 6: Zeitfenster des ganzen Kampfes 192 s; gewonnen Median 119 s, 90 % in 135 s (Sprinter 136 / 154 s). Stufe 1: 42 s. *Tramuntana* Stufe 6: Median 84 s, *Dimonis* nur 41 s (Stufe 1: 18 s). Ist Drac auf Stufe 6 zu lang, Dimonis zu kurz?
2. **Takt-Tore zu leicht bei konstanter Kadenz?** Direkt am Baustein gemessen: Wer konstant in der Zonenmitte tritt (*Ruhiger Takt* 84 rpm, *Flotter Takt* 99 rpm), schafft beide auf **allen** sechs Stufen. Trainierter: *Ruhiger Takt* 100 → 97 %, *Flotter Takt* 94 → 84 %. Takt-Tore sind also Zone-halten-zu-Schlagzeiten; soll es einen echten Wechsel von Kadenz verlangen?
3. **Elite-Chance unabhängig von der Stufe?** Anteil der Elite-Gruppen an den Herausforderungen ohne Boss: 15 / 15 / 15 / 15 / 14 / 15 % (Chance 0,15 überall). Ihre Quote sinkt dabei von 86 → 64 % (Champions) und 80 → 44 % (Seltene). Soll die Chance mit der Stufe steigen?
4. **Beute-Tempo.** 21 → 19 Funde je Stunde (Einsteiger 9,5 → 4,6). Die Empfohlene Stärke 35 / 50 / 70 erreichen Laufbahnen nach 1 Lauf (0,75 h; Einsteiger 1 / 1 / 2 Läufe), danach liegt die Stärke bei 100 (Obergrenze) und das Arcade-Level bei 12. Legendäre Teile machen 6 % (Stufe 1) bis 29 % (Stufe 6) der Funde aus, also 1,3 bis 5,6 je Stunde (Grundgewicht 2 %; Boss- und Elite-Qualität, Stufe heben es). Fallen zu viele Teile, ist die Stärke-Empfehlung zu früh erfüllt?
5. **Freischalttempo.** Stufe 4 / 5 / 6 nach 1 / 2 / 3 Läufen (0,75 / 1,5 / 2,25 h), Stufe 6 abgeschlossen nach 4 Läufen (3 h); Einsteiger 3 / 5 / 9 Läufe (2,25 / 3,75 / 6,75 h), abgeschlossen nach 11. Hauptgrund ist die schnell wachsende Ausrüstung (Frage 4), nicht das Treten. Soll das länger dauern?
6. **Sammeln für Einsteiger.** Auf Stufe 1 schafft der Einsteiger *Wiese* zu 13 % und *Ufer* zu 3 % (Trainierter 92 / 70 %); alle anderen Herausforderungen liegen für ihn bei 44–90 %. Ursache ist die Zahl der nötigen Objekte (*Wiese* braucht Radius 2,5 m ≈ 92 rpm). Ein Eingriff (`need` 5 → 4) ändert Tests (`test_elite_groups.gd`, `test_arcade_rhythm_collect*.gd`, Bridge-Profile `sammeln_*`) und README – nicht ohne Entscheidung angefasst.
7. **Einsteiger und die Spitzen.** Mit höchstens 118 rpm (Profilannahme) schafft der Einsteiger *Spurt* ab Stufe 3 und *Letzter Ansturm* ab Stufe 4 praktisch nie (0–6 %). Das ist eine Folge der Annahme, nicht der Daten – aber ob ein Einsteiger mit Standardbereich 60–120 rpm diese Schwellen je erreichen soll (oder erst mit angepasstem Bereich), ist eine Produktfrage.
8. **Empfehlung oder Pflicht?** Stufe 6 ohne Ausrüstung: alle Herausforderungen zusammen schafft der Trainierte zu 80 %, der Einsteiger zu 14 %. Mit der Empfohlenen Stärke (70) steigt der Einsteiger bei normalen Herausforderungen von 24 auf 61 %, bei Bossen von 4 auf 34 %; der Trainierte von 85 auf 95 % bzw. von 79 auf 92 %. Für den Einsteiger wirkt die Empfehlung damit wie eine Pflicht – gewollt, oder soll Fitness allein weiter tragen („Ausrüstung ersetzt nie das Treten“)?
9. **Sammeln: *Ufer* ab Stufe 4.** *Ufer* sinkt beim Trainierten von 70 % (Stufe 1) auf 44 / 39 / 33 % (Stufe 4 / 5 / 6), während die Schwester *Wiese* bei 84 % bleibt (Sprinter: *Ufer* 70–79 %). Die vorab festgelegte Schwelle (1) greift nur knapp nicht (*Wiese* 84 statt 85 %), daher nicht angepasst. Ist *Ufer* als schwerste Sammel-Aufgabe der oberen Stufen gewollt, oder sollen ihre Daten (`src/challenges/collect_challenges.gd`: `need`, Radius) näher an *Wiese* rücken?
