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
| `kenney/nature/*.glb`: `stone_tallA`, `stone_tallB`, `stone_tallC`, `stone_largeA`, `stone_largeB`, `stone_largeC`, `tree_fat`, `tree_oak`, `tree_tall`, `grass_large`, `plant_flatShort`, `flower_redA`, `flower_purpleA`, `flower_yellowA`, `pot_large` | Kalkfelsen und Felsnadeln (Serpentinen), Olivenbäume (`tree_fat`/`tree_oak` mit silbrigem Laub, `OLIVE_COLORS`), Zypressen (`tree_tall`), Gras, Blumen, Blumentöpfe in Hain, Dorf und Abfahrt (#16); Dateien unverändert, zur Laufzeit umgefärbt | [Nature Kit 2.1](https://kenney.nl/assets/nature-kit) | Kenney (kenney.nl) | CC0 1.0 (`kenney/nature/License.txt`) |
| `kenney/fantasy-town/*.glb`: `wall`, `wall-window-shutters`, `wall-window-small`, `wall-window-round`, `wall-doorway-round`, `roof-high`, `roof-high-point`, `fountain-round`, `lantern`, `stall-red`, `cart` | Module der Dorfhäuser und der Kirche, Brunnen, Laternen, Marktstände, Karren im Bergdorf (#16) | [Fantasy Town Kit 2.0](https://kenney.nl/assets/fantasy-town-kit) | Kenney (kenney.nl) | CC0 1.0 (`kenney/fantasy-town/License.txt`) |
| `kenney/fantasy-town/Textures/colormap.png` | Farbpalette des Kits, **abgewandelt**: Wandstein (lavendelgrau) → Sandstein, Holzrahmen → dunkler Kalkstein, Dachrot und Giebelgrün → Terrakotta, Schiefer → warmes Grau | wie oben (`colormap.png` des Kits) | Kenney; Abwandlung für VSpin | CC0 1.0 |

## Selbst erstellt

| Inhalt | Herkunft | Lizenz |
|---|---|---|
| Insel-Gelände (Höhenfeld, Vertex-Farben) | prozedural, `src/island_terrain.gd` | MIT (Projektlizenz) |
| Rundkurs (Grundriss, Höhenprofil), Fahrbahn | selbst erstellt, `src/island_course.gd`, `src/track.gd` | MIT (Projektlizenz) |
| Meer, Kai, Molen, Leuchtturm, Poller, Straßen- und Trockenmauern, Randsteine, Plattform am Aussichtspunkt (Brüstung, Bänke, Fernrohr), Start/Ziel-Bogen, Stationsmarker | Godot-Grundkörper (Box, Zylinder), `src/island_world.gd` | MIT (Projektlizenz) |
| Sehenswürdigkeiten (Leuchtturm auf der Felsküste, Talaia, Burgruine, Aquädukt, Windmühlen, Cala mit Sonnenschirmen und Fischerhütten, Terrasse der Ermita) und Kleindetails (Kilometersteine, Agaven, Feigenkakteen, Schafe, Ziegen, Bushaltestelle) – G2; Kirche/Kloster der Ermita, Felsen, Zypressen, Blumen und Boote aus den Kenney-Modellen oben, **keine neuen Dateien** | Godot-Grundkörper (Box, Kegelstumpf, Kugel), je Landmarke zu einem Mesh zusammengesetzt, `src/island_landmarks.gd` | MIT (Projektlizenz) |
| Bewegte Szenen und Effekte (G3): Möwen, Greifvögel, Wolken, Lichtkegel, Brunnenstrahl; Shader für Wind, Meer und Lichtkegel; Segelboote aus den Kenney-Booten oben, **keine neuen Dateien** außer Shader-Quelltext | Godot-Grundkörper und Partikel, `src/world_motion.gd`, `src/shaders/*.gdshader` | MIT (Projektlizenz) |
| Vegetation entlang der Strecke (Gras, Unterholz, Sträucher) und Detailtexturen von Gelände und Fahrbahn (#38) – **keine Dateien**, zur Laufzeit erzeugt | Low-Poly-Meshes aus Grundformen und Rauschen (FastNoiseLite), `src/island_vegetation.gd` | MIT (Projektlizenz) |
| Alle Klänge (#44): Fahrtwind, Freilauf, Meer, Regen, Möwen, Schafglocken, Dorfglocke, UI-Klick, Einblendungs- und Ansageton – **keine Klangdateien**, zur Laufzeit erzeugt | prozedural (gefiltertes Rauschen, Synthese aus Teiltönen und Frequenzgleitung), `src/sound_synth.gd`; abgespielt von `src/ride_sound.gd` | MIT (Projektlizenz) |
| VSpin-Symbol „Faltband mit Schattenfalte“ (Fenster, Taskleiste, Browser-Tab): `icon.svg`, daraus gerastert `icon.ico` (16–256 px) | selbst erstellt | MIT (Projektlizenz) |
| Schrift (HUD, Stationsschilder) | in die Engine eingebaute Standardschrift (Open Sans), keine Datei im Repo | SIL OFL 1.1 (Godot-Lizenzhinweise) |

Testwerkzeug, nicht Teil des Spiels: GUT 9.4 (`addons/gut`, MIT, Lizenz in `addons/gut/LICENSE.md`).

## Vorgesehen (noch nicht übernommen)

Ggf. Terrain3D (MIT) – siehe ADR-0006 und dessen Nachtrag. Bei Übernahme hier eintragen.
