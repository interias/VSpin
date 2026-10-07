# Assets – Inselfahrt (`island-ride`)

Nachweis aller Assets im Spiel (ADR-0006). **Lizenzregel:** nur CC0 oder damit kompatible freie Lizenzen
(z. B. CC-BY mit Namensnennung hier); jede fremde Datei wird hier mit Quelle, Autor, Lizenz und Pfad eingetragen,
bevor sie ins Repo kommt.

## Fremde Assets

Nur die tatsächlich benutzten Modelle (`.glb`), keine ganzen Packs; die Lizenzdatei der Quelle liegt jeweils
daneben. Kein Git LFS.

| Pfad (unter `assets/`) | Inhalt | Quelle | Autor | Lizenz |
|---|---|---|---|---|
| `kenney/watercraft/*.glb`: `boat-sail-a`, `boat-sail-b`, `boat-fishing-small`, `boat-row-small`, `boat-tug-a`, `buoy-flag`, `cargo-pile-a`, `cargo-pile-b`; `Textures/colormap.png` | Boote, Bojen, Ladung im Hafen (#15) | [Watercraft Kit 2.1](https://kenney.nl/assets/watercraft-kit) | Kenney (kenney.nl) | CC0 1.0 (`kenney/watercraft/License.txt`) |
| `kenney/city-suburban/*.glb`: `building-type-a`, `building-type-c`, `building-type-g`, `building-type-h`, `building-type-k`, `building-type-r` | Häuser an der Hafenstraße (#15) | [City Kit (Suburban) 2.0](https://kenney.nl/assets/city-kit-suburban) | Kenney (kenney.nl) | CC0 1.0 (`kenney/city-suburban/License.txt`) |
| `kenney/city-suburban/Textures/colormap.png` | Farbpalette der Häuser, **abgewandelt**: Dachgrün → Terrakotta, Wandweiß → Cremeweiß (Mallorca-Stil) | wie oben (`colormap.png` des Kits) | Kenney; Abwandlung für VSpin | CC0 1.0 |
| `kenney/nature/*.glb`: `rock_largeA`, `rock_largeB`, `rock_largeD`, `rock_tallA`, `rock_tallB`, `rock_tallG`, `tree_palmTall`, `tree_palmBend`, `tree_simple`, `tree_plateau`, `tree_detailed`, `plant_bushLarge`, `plant_bushDetailed`, `plant_bush` | Felsen/Klippen, Palmen, Pinien, Büsche an Hafen und Küstenstraße (#15); Materialfarben werden im Spiel mediterran umgefärbt (`NATURE_COLORS` in `src/island_world.gd`), die Dateien sind unverändert | [Nature Kit 2.1](https://kenney.nl/assets/nature-kit) | Kenney (kenney.nl) | CC0 1.0 (`kenney/nature/License.txt`) |

## Selbst erstellt

| Inhalt | Herkunft | Lizenz |
|---|---|---|
| Insel-Gelände (Höhenfeld, Vertex-Farben) | prozedural, `src/island_terrain.gd` | MIT (Projektlizenz) |
| Rundkurs (Grundriss, Höhenprofil), Fahrbahn | selbst erstellt, `src/island_course.gd`, `src/track.gd` | MIT (Projektlizenz) |
| Meer, Kai, Molen, Leuchtturm, Poller, Küstenmauer, Start/Ziel-Bogen, Deko der übrigen Stationen (Felsen, Bäume, Häuser, Kirche, Marker) | Godot-Grundkörper (Box, Kugel, Zylinder, Prisma), `src/island_world.gd` | MIT (Projektlizenz) |
| Schrift (HUD, Stationsschilder) | in die Engine eingebaute Standardschrift (Open Sans), keine Datei im Repo | SIL OFL 1.1 (Godot-Lizenzhinweise) |

Testwerkzeug, nicht Teil des Spiels: GUT 9.4 (`addons/gut`, MIT, Lizenz in `addons/gut/LICENSE.md`).

## Vorgesehen (noch nicht übernommen)

Weitere Low-Poly-Modelle für Serpentinen, Hain und Bergdorf (#16) und ggf. Terrain3D (MIT) – siehe ADR-0006 und
dessen Nachtrag. Bei Übernahme hier eintragen.
