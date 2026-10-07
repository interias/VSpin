# ADR-0005: Prototyp-Game – Radsimulator auf einer Insel-Teststrecke

- **Status:** akzeptiert (Welt-Erstellung siehe offene Punkte)
- **Datum:** 2026-10-06

## Kontext

Mit Kadenz als einzigem Input (ADR-0004) bieten sich die Mechaniken
Geschwindigkeit, Position/Höhe, Zielzone und Energie an. Vorgeschlagen war ein
2D-„Höhe = Kadenz“-Spiel; der Projektinhaber wünscht sich stattdessen einen
schön anzusehenden Radsimulator.

## Entscheidung

- Das Prototyp-Game ist ein **3D-Radsimulator in Godot 4**.
- **Mechanik: Kadenz → Geschwindigkeit.** Der Fahrer folgt automatisch der
  Strecke (kein Lenken).
- **Teststrecke:** eine abwechslungsreiche, schön anzusehende Strecke auf einer
  Insel, möglichst angelehnt an ein reales Vorbild.

## Konsequenzen

- Der Prototyp ist deutlich aufwendiger als ein 2D-Spiel (Terrain, Strecke,
  Kamera, Assets). Das v1-Abnahmekriterium (ADR-0001) bleibt bestehen.
- Latenz fällt bei Kadenz → Geschwindigkeit weniger auf; die < 200 ms werden
  daher zusätzlich über eine Debug-Anzeige (Kadenz-Rohwert vs. Zeitstempel) geprüft.
- Steigungen wirken nur virtuell (langsamer bei gleicher Kadenz), da der
  Widerstand manuell ist – spürbar erst mit ESP32-Retrofit.

## Offen

- Wie die Insel-Welt entsteht (reale Geodaten vs. handgebaut vs. Video) – entschieden in ADR-0006 (handgebaut, Mallorca-Stil).
