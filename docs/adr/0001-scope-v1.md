# ADR-0001: Scope v1 – Telemetrie, Simulator, ein Prototyp-Game

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Ziel ist eine eigene Game-Plattform für das JC312. Optionen für v1:
(A) nur Telemetrie, (B) Telemetrie + Simulator + ein Prototyp-Game, (C) Game-Hub.

## Entscheidung

**B.** v1 umfasst:

- Telemetrie vom echten JC312 unter Windows
- Simulator als gleichwertige Datenquelle
- genau ein Prototyp-Game
- Session-Logging auf Platte

**Abnahmekriterium v1:** 10 Minuten am echten JC312 treten, ein Spiel reagiert
spürbar verzögerungsfrei (< 200 ms Kurbel → Bildschirm) auf die Kadenz, die
Session liegt danach als Datei vor. Dasselbe Spiel läuft ohne Rad mit dem Simulator.

**Explizit nicht in v1:** Launcher/Hub, Profile, Online-Features, Strava-Upload,
Widerstandssteuerung.

## Konsequenzen

- Alle Schichten (BLE → Bus → Game) werden früh end-to-end durchstochen.
- Eine Game-API wird erst nach dem ersten Spiel abstrahiert; der Hub entsteht
  später als „weiterer Client am Bus“.
- Risiko: Das Prototyp-Game bleibt bewusst simpel und wird ggf. weggeworfen.
