# ADR-0006: Insel-Welt – handgebaut, Mallorca-Stil

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Der Radsimulator (ADR-0005) braucht eine schöne, abwechslungsreiche
Insel-Teststrecke. Optionen: (A) echte Geodaten (DEM + OSM),
(B) handgebaute Insel angelehnt an ein Vorbild, (C) Fahrtvideo.

## Entscheidung

**B – handgebaute, stilisierte Insel im Mallorca-Stil.**

- Kompakte Insel (ca. 2×3 km), gebaut in Godot 4 mit dem Terrain3D-Plugin und
  freien Low-Poly-/stilisierten Assets (z. B. Quaternius, Kenney; nur
  CC0/kompatible Lizenzen).
- **Rundkurs ca. 8–10 km**, Stationen:
  1. Hafen (Start/Ziel)
  2. Küstenstraße entlang Felsküste und Mittelmeer
  3. Serpentinen-Anstieg à la Sa Calobra mit Aussichtspunkt
  4. Pinien-/Olivenhain
  5. kleines Bergdorf
  6. Abfahrt zurück zum Hafen
- Strecke als `Path3D`; die Kamera folgt dem Pfad, keine Lenk-Physik.
- **Geschwindigkeitsmodell:** `v = k · Kadenz`, bergauf gedämpft, bergab leicht
  beschleunigt, mit etwas Trägheit. Parameter in einer Konfigurationsdatei.

## Konsequenzen

- Volle Gestaltungskontrolle, schnell „schön“ erreichbar, kein Geodaten-Pipeline-Aufwand.
- Nicht 1:1 real; Asset-Lizenzen werden in `games/*/ASSETS.md` dokumentiert.
- Die Strecke liefert eine Steigung pro Position → Grundlage für spätere
  Widerstandssteuerung (ESP32).

## Später möglich

- Option A (reale Strecken, GPX-Import) als weiterer Streckentyp.

## Nachtrag (2026-10-06, #14): Terrain3D zurückgestellt

- **Terrain3D ist vorerst nicht im Einsatz.** In der Build-/Testumgebung (headless Linux-Container ohne
  Zugriff auf Plugin-Releases und Asset-Quellen) war das Plugin nicht verfügbar.
- Stattdessen: **eingebautes Höhenfeld** aus Godot-Bordmitteln (`games/island-ride/src/island_terrain.gd`):
  regelmäßiges Gitter (5 m) als `ArrayMesh`, prozedural erzeugt (Inselform, Küste, Gipfel) und **unter die
  Straße geformt**. Eine handgemalte Höhenkarte kann das prozedurale Gelände ersetzen
  (`IslandTerrain.from_image()` + `fit_to_road()`).
- Grundriss und Höhenprofil des Rundkurses sind von der Geländequelle unabhängig
  (`games/island-ride/src/island_course.gd`) – die Steigung kommt weiter aus dem `Path3D`.
- **Terrain3D kann später auf dem Windows-PC übernommen werden** (z. B. Höhenkarte aus dem Höhenfeld
  exportieren und in Terrain3D importieren); Strecke, Fahrmodell und Tests bleiben davon unberührt.
- Assets: bisher nur selbst erstellte/prozedurale Grundformen (`games/island-ride/ASSETS.md`).
