# Assets – Inselfahrt (`island-ride`)

Nachweis aller Assets im Spiel (ADR-0006). **Lizenzregel:** nur CC0 oder damit kompatible freie Lizenzen
(z. B. CC-BY mit Namensnennung hier); jede fremde Datei wird hier mit Quelle, Autor, Lizenz und Pfad eingetragen,
bevor sie ins Repo kommt.

## Stand

**Bisher enthält das Spiel keine fremden Assets.** Alles ist selbst erstellt bzw. zur Laufzeit erzeugt:

| Inhalt | Herkunft | Lizenz |
|---|---|---|
| Insel-Gelände (Höhenfeld, Vertex-Farben) | prozedural, `src/island_terrain.gd` | MIT (Projektlizenz) |
| Rundkurs (Grundriss, Höhenprofil), Fahrbahn | selbst erstellt, `src/island_course.gd`, `src/track.gd` | MIT (Projektlizenz) |
| Meer, Deko (Kai, Boote, Felsen, Bäume, Häuser, Kirche, Marker) | Godot-Grundkörper (Box, Kugel, Zylinder, Prisma), `src/island_world.gd` | MIT (Projektlizenz) |
| Schrift (HUD, Stationsschilder) | in die Engine eingebaute Standardschrift (Open Sans), keine Datei im Repo | SIL OFL 1.1 (Godot-Lizenzhinweise) |

Testwerkzeug, nicht Teil des Spiels: GUT 9.4 (`addons/gut`, MIT, Lizenz in `addons/gut/LICENSE.md`).

## Vorgesehen (noch nicht übernommen)

Low-Poly-/stilisierte Modelle z. B. von Quaternius oder Kenney (CC0) und ggf. Terrain3D (MIT) – siehe
ADR-0006 und dessen Nachtrag. Bei Übernahme hier eintragen.
