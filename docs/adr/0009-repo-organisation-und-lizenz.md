# ADR-0009: Repo-Organisation, Sichtbarkeit, Lizenz

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Entscheidung

- **Monorepo** `interias/VSpin` mit `bridge/`, `tools/`, `games/`, `firmware/`, `docs/`.
- **Privat** – Projekt ist nur für den Eigengebrauch.
- **Lizenz: MIT.**
- **qdomyos-zwift (GPL-3.0) nur als Referenz lesen**, keinen Code daraus
  kopieren – sonst müsste VSpin unter GPL-3.0 stehen.
- Game-Assets nur CC0/kompatibel, dokumentiert in `games/<game>/ASSETS.md`.
- Persönliche Daten (`sessions/`) sind per `.gitignore` ausgeschlossen.

## Konsequenzen

- Bus-Protokoll, Bridge, Game und Firmware können gemeinsam in einem Commit geändert werden.
- Eine spätere Veröffentlichung bleibt ohne Lizenz-Aufräumen möglich.
