# ADR-0001: Scope v1 – Telemetrie, Simulator, ein Prototyp-Game

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Ziel ist eine eigene Game-Plattform für den Indoor-Trainer (FTMS). Optionen für v1:
(A) nur Telemetrie, (B) Telemetrie + Simulator + ein Prototyp-Game, (C) Game-Hub.

## Entscheidung

**B.** v1 umfasst:

- Telemetrie vom echten Trainer unter Windows
- Simulator als gleichwertige Datenquelle
- genau ein Prototyp-Game
- Session-Logging auf Platte

**Abnahmekriterium v1:** 10 Minuten am echten Trainer treten, ein Spiel reagiert
spürbar verzögerungsfrei (< 200 ms Kurbel → Bildschirm) auf die Kadenz, die
Session liegt danach als Datei vor. Dasselbe Spiel läuft ohne Rad mit dem Simulator.

**Explizit nicht in v1:** Launcher/Hub, Profile, Online-Features, Strava-Upload,
Widerstandssteuerung.

## Konsequenzen

- Alle Schichten (BLE → Bus → Game) werden früh end-to-end durchstochen.
- Eine Game-API wird erst nach dem ersten Spiel abstrahiert; der Hub entsteht
  später als „weiterer Client am Bus“.
- Risiko: Das Prototyp-Game bleibt bewusst simpel und wird ggf. weggeworfen.

## Nachtrag (2026-10-28, Spec #75): Widerstand ist im Umfang

„Widerstandssteuerung“ steht nicht mehr unter „nicht in v1“: Mit Spec #75 (Zwift Ride und KICKR CORE 2) setzt die
Bridge die virtuelle Steigung am FTMS-Trainer als Widerstand um (ADR-0007, Nachtrag Spec #75). Simulator und Replay
bleiben gleichwertige Quellen ohne Widerstand (`not_supported`).

## Nachtrag (2026-10-28, #84): Garmin-Upload als optionales Online-Feature

„Online-Features“ waren für v1 ausgeschlossen. Mit #84 ist eines im Umfang: der Upload einer gespeicherten Fahrt zu
Garmin Connect – **nur optional**. Er braucht das Extra `garmin` und eine Anmeldung im Terminal, lässt sich je Fahrt
abschalten, und ohne ihn läuft alles wie bisher; die FIT-Datei entsteht lokal immer (ADR-0008, Nachtrag #84).
Strava und andere Dienste bleiben draußen.
