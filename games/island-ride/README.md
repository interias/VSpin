# Inselfahrt (`island-ride`)

Prototyp-Game (ADR-0005): 3D-Radsimulator in Godot 4.4 (GDScript). Das Spiel ist ein Client am
Bus (`docs/bus-protocol.md`); die Kadenz bewegt den Fahrer entlang eines `Path3D` – kein Lenken.
Stand: Insel-Rundkurs (~9,2 km, Grundform aus Gelände + Straße, #14) mit HUD, Debug-Anzeige, Spielzuständen
(Pause bei Verbindungsverlust, manuelle Pause, Ziel mit Zusammenfassung) und `set_grade` an die Bridge. Die kurze
Graybox-Strecke bleibt per Konfiguration wählbar (und ist die Grundlage vieler Tests).

## Insel und Rundkurs (#14, ADR-0006)

Stilisierte Insel im Mallorca-Stil, ca. **2 × 3,1 km** (Superellipse mit Hafenbucht im Süden, Felsküste im
Westen, Hochebene mit Gipfel im Nordwesten), Meer rundum. Darauf der **Rundkurs, 9,21 km**, Start/Ziel am Hafen,
gefahren im Uhrzeigersinn über West → Nord → Ost:

| Station | Strecke (km) | Höhe (m) | Steigung | Grundform |
|---|---|---|---|---|
| Hafen (Start/Ziel) | 0,00–0,42 | 3 → 4 | flach | Kai mit Pollern, Molen mit Leuchtfeuern, Boote, Häuserzeile, Palmen, Start/Ziel-Bogen (#15); Badebucht (Cala) mit Sonnenschirmen (G2) |
| Küstenstraße | 0,42–2,31 | 4 → 42 | Ø 2 %, wellig bis 4,4 % | entlang der Felsküste, Meer links, Mauer, Klippen, Pinien und Macchia (#15); Leuchtturm, Talaia, Boote in den Buchten (G2) |
| Serpentinen (Sa-Calobra-Stil) | 2,31–4,68 | 42 → 212 | Ø 7,1 %, bis 8,4 % (Einstieg ab 4,3 %) | 6 Rampen mit 5 Kehren, Natursteinmauer, Randsteine und Felsnadel je Kehre, Kalkfelsen; **Aussichtspunkt** (4,59 km) mit Plattform über der Westküste (#16); Ermita über der Westküste im Blick (G2) |
| Pinien-/Olivenhain | 4,68–5,69 | 212 → 222 | Ø 1 %, wellig bis 4,4 % | Olivenreihen hinter Trockenmauern im Wechsel mit Pinienwald (#16) |
| Bergdorf | 5,69–6,02 | 222 → 223 | flach | Natursteinhäuser mit Terrakotta-Dächern, Platz mit Kirche, Brunnen, Marktständen (#16); Bushaltestelle (G2) |
| Abfahrt | 6,02–9,21 | 223 → 3 | Ø −6,9 %, max. −8,8 %, Auslauf −1,5 % | über den Osthang mit zwei weiten Kehren zurück zum Hafen; Mauer, Pinien, Zypressen, Oliven, Fincas, Palmen (#16); Aquädukt, Burgruine, drei Windmühlen (G2) |

Steigung überall ≤ 10 %, ohne Sprünge (≤ 1 Prozentpunkt je 5 m). Exakte Werte prüfen die Tests
(`tests/test_island_course.gd`); die Tabelle ist gerundet.

**Aufbau ohne Plugin (Abweichung von ADR-0006, siehe dort „Nachtrag“):** Terrain3D war in der Build-Umgebung nicht
verfügbar, daher nur Godot-Bordmittel:

- `src/island_course.gd` – Grundriss (Wegpunkte, zentripetaler Catmull-Rom, alle 5 m abgetastet) und Höhenprofil
  (Steigung je Station aus Zielhöhen, Wellen, gleitende Glättung über 80 m, geschlossen) → `Curve3D` + Stationen.
  Strecke ändern = Wegpunkte/`SECTIONS` anpassen; die Tests sagen, ob Länge und Profil noch passen.
- `src/island_terrain.gd` – Höhenfeld (5-m-Gitter, 2,6 × 3,6 km inkl. Meer) als `ArrayMesh` mit Vertex-Farben.
  Erst großräumig an die Straßenhöhen angelehnt (kein Damm, keine Schlucht), dann **unter die Straße geformt**:
  bis 12 m von der Straßenmitte auf Straßenhöhe, bis 70 m weicher Übergang. Eine **handgemalte Höhenkarte** kann
  das prozedurale Gelände ersetzen: `IslandTerrain.from_image(image)` (R-Kanal 0..1 → −40..360 m) und danach
  `fit_to_road(IslandCourse.samples())`.
- `src/island_world.gd` – Gelände, Meer (y = 0), Fahrbahn (6 m, Randlinien), Stationsmarker
  (`World/Stations/<id>` mit Schild, Metadaten `station_name`/`distance_m`) und Deko je Station
  (`World/Props/<id>`). **Alle Stationen sind ausgestaltet** (Hafen und Küstenstraße #15, die übrigen #16); jede
  Station hat einen eigenen Zufallsgenerator (Seeds 1501–1506):
  - **Hafen:** gepflasterter Kai von der Straße bis zur Kaimauer mit Pollern, zwei Molen mit Leuchtfeuern
    (grün/rot), Segel-, Fischer- und Schlepperboote am Kai (Bug zur Mauer) und vor Anker in der Bucht, Bojen,
    Ladung auf dem Kai, landseitig eine Häuserzeile mit Terrakotta-Dächern, Palmen, Ruderboote am Strand.
  - **Küstenstraße:** seeseitig niedrige Natursteinmauer am Straßenrand, Felsküste aus einem dichten Felsband auf dem
    Hang zum Meer (4–10 m, Knoten `Hang_*`) und Klippen an der Wasserlinie, Hang zum Wasser hin felsfarben, dazwischen
    Büsche; landseitig Pinien, Büsche und Felsen. Das Gelände fällt seeseitig zum
    Meer ab (`IslandTerrain.COAST_*`: Küstenlinie ~50–120 m neben der Straße), damit das Meer beim Fahren sichtbar
    ist; Grundriss und Höhenprofil des Rundkurses sind unverändert.
  - **Serpentinen:** talseitig Natursteinmauer, in den Kehren außen durchgehend Mauer, innen weiße Randsteine und in
    der Kehrenmitte eine 18–26 m hohe Kalksteinnadel (`Nadel_*`, Sa-Calobra-Stil); bergseitig graue Kalkfelsen,
    dazwischen Macchia und Pinien. **Aussichtspunkt:** gemauerte Plattform links auf Straßenhöhe über der Westküste,
    Brüstung an drei Seiten, Bänke, Fernrohr.
  - **Pinien-/Olivenhain:** in Abschnitten von 150 m im Wechsel auf einer Seite Olivenbäume in Reihen (silbriges
    Laub) hinter einer Trockenmauer mit Gras und Blumen, auf der anderen Seite Pinienwald.
  - **Bergdorf:** Häuserzeilen beidseits aus Modulen des Fantasy Town Kit (Natursteinwände, Fensterläden,
    Rundbogentüren, Terrakotta-Satteldächer; ein MultiMesh je Modul), rechts in der Mitte ein Platz mit Kirche
    (Glockenturm mit Zeltdach), Brunnen, Marktständen und Karren; Laternen und Blumentöpfe an der Straße.
  - **Abfahrt:** talseitig Mauer, Pinien, Zypressen, Macchia, Kalksteine, bergseitig Olivenhaine (jeder dritte
    300-m-Abschnitt), fünf Fincas mit Zypressen an der Zufahrt, auf den letzten 350 m Palmen.
  - **Sehenswürdigkeiten (G2, `src/island_landmarks.gd`, Knoten `World/Landmarks/<id>` mit Metadaten
    `landmark_name`, `distance_m`, `side`):** Leuchtturm `leuchtturm` (0,88 km links, Felsküste, vom Ende des Hafens
    an voraus im Bild), Badebucht `cala` (Hafen links, Sonnenschirme, Liegen, Fischerhütten), Talaia `talaia`
    (1,72 km links, runder Wachturm auf der Klippe), Ermita `ermita` (Plateau über der Westküste, auf den
    Serpentinen-Rampen nach Westen voraus, von der Küstenstraße am Hang), Burgruine `burg` (Abfahrt 7,0 km links auf
    Felssockel über der Ostküste, ab ~6,4 km voraus), Aquädukt `aquaedukt` (Abfahrt 6,87 km rechts, parallel zur
    Straße), drei Windmühlen `windmuehlen/Muehle1..3` (8,33 / 8,52 / 8,70 km). Kleindetails unter `World/Details`:
    Kilometersteine 1–9 rechts am Rand, Agaven (teils mit Blütenstand), Feigenkakteen, Blumen, Schaf- und
    Ziegenherden, Boote und Bojen in den Buchten der Westküste, Bushaltestelle vor dem Bergdorf. Nur Godot-Grundkörper
    (je Landmarke ein Mesh) und vorhandene Kenney-Modelle, eigene Seeds 1507/1508. Animierbar (für bewegte Szenen):
    `windmuehlen/Muehle<n>/Fluegel` (Drehachse lokal z), `leuchtturm/Lampe` (Drehachse lokal y), `Details/Boote/*`.
  - Modelle: Kenney Watercraft Kit, City Kit (Suburban), Nature Kit, Fantasy Town Kit (CC0) unter `assets/kenney/`,
    nur die benutzten `.glb` (~1,4 MB) – Nachweis in `ASSETS.md`. Wiederholte Modelle (Bäume, Büsche, Felsen,
    Mauern, Hausmodule) als `MultiMeshInstance3D`. Sichtprüfung/fps: `tools/view_probe.gd` (Screenshots an Streckenpositionen, fps-Fahrt).
- Kamera (`scenes/main.gd`): sitzt 9 m hinter dem Fahrer **auf der Strecke** (schwenkt in Kehren nicht seitlich
  aus), blickt 14 m voraus, beides exponentiell geglättet (0,45 s), mindestens 1,5 m über dem Gelände.
- HUD zeigt zusätzlich den aktuellen Abschnitt („Abschnitt: Serpentinen“).

Erzeugung beim Start ca. 2 s (Gelände wird einmal pro Prozess erzeugt und gecacht).

**Sichtprüfung am Windows-PC (#15, Hafen + Küstenstraße):** Screenshots mit `tools/view_probe.gd`; fps-Fahrt
0–2310 m mit 50 km/h, 1920 × 1080, VSync an (RTX 4070): Mittel 60,0 fps; ~1 % der Frames < 50 fps, genauso wie
vor #15 (VSync-Takt im Fenster, nicht der Inhalt; ohne VSync Mittel ~1500 fps).

**Sichtprüfung #16 (Serpentinen bis Abfahrt):** fps-Fahrt 2310–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070):
Mittel 59,9 fps, 1-%-Tief 54,8 fps, 107 von 29 692 Frames < 50 fps – vor #16 auf derselben Fahrt 59,9 / 54,7 / 135.
**Offen:** Gelände-Belichtung, ruhige Kamera in den Kehren.

**Sichtprüfung G2 (Sehenswürdigkeiten):** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070): Mittel
59,9 fps, 1-%-Tief 55,4 fps, 83 von 39 677 Frames < 50 fps – vorher auf derselben Fahrt 59,9 / 54,3 / 180 (Streuung).

## Bewegung, Effekte und Licht

Die Welt lebt (G3), getrieben von `src/world_motion.gd` (`WorldMotion`, Knoten `World/Motion`, von
`IslandWorld.build()` eingehängt). Alles außer den Shadern ist eine reine Funktion der Animationszeit
(`apply(t)`), headless getestet (`tests/test_world_motion.gd`).

- **Windmühlen:** die Flügel der drei Molins drehen (0,55–0,8 rad/s, je Mühle eigene Drehzahl).
- **Leuchtturm:** die Lampe dreht (eine Umdrehung in ~7 s) mit einem dezenten, additiven Lichtkegel
  (`src/shaders/beam.gdshader`).
- **Boote:** alle Boote und Bojen im Wasser (Hafen, Buchten der Westküste) schaukeln (Hub ≤ 0,15 m, Neigung
  ≤ ~4°); zwei Segelboote kreuzen auf Ellipsen vor der Westküste und vor dem Hafen (~3,5 m/s, leichte Krängung).
- **Vögel:** Möwenschwärme über Hafen, Leuchtturm und Westküste, je ein Greifvogel über den Serpentinen und der
  Burg – Low-Poly aus Grundkörpern, Flügelschlag in Phasen mit Gleitflug dazwischen.
- **Wolken:** bis zu 36 Low-Poly-Wolken 380–560 m hoch ziehen mit dem Wind und laufen am Rand um; wie viele zu
  sehen sind, bestimmt das Wetter (G6).
- **Wind:** Bäume, Palmen, Büsche, Gras, Blumen (Kenney-Vegetation) und Agaven wiegen sanft
  (`src/shaders/wind.gdshader`, Vertex-Shader; Gewicht = Höhe im Objektraum, Fuß fest; Phase aus der Weltlage).
  Felsen und Gebäude bleiben starr.
- **Meer:** `src/shaders/sea.gdshader` – Wellen als Normalen-Störung (zur Ferne ausgeblendet), Glitzern,
  türkisfarbenes Flachwasser und laufende Brandung an der Küste. Die Wassertiefe kommt aus einer kleinen
  Höhenkarte des Geländes (261 × 361 Texel, L8, zur Laufzeit erzeugt), nicht aus dem Tiefenpuffer.
- **Brunnen** im Bergdorf mit Wasserstrahl (`CPUParticles3D`).
- **Pausen:** Verbindungs- und manuelle Pause halten nur die Fahrt an, nicht den Szenenbaum – die Welt lebt als
  Ambiente weiter (sonst wirkte ein Abbruch wie ein Absturz).

**Licht** (`scenes/main.tscn`): ProceduralSky (Mittelmeerblau, heller Horizont) statt Einfarb-Hintergrund,
Umgebungslicht halb aus dem Himmel, halb warm-neutral (Energie 1,0), Reflexionen aus dem Himmel, ACES-Tonemapping,
SSAO, dezentes Glow, Fernnebel mit Luftperspektive, Sättigung +12 %. Sonne flacher (−42°) und warm
(Energie 1,25). Hauptursache der Überbelichtung war, dass Vertex-Farben (Gelände, Straße, G2-Bauten) linear statt
als sRGB gelesen wurden – die Materialien setzen jetzt `vertex_color_is_srgb`, die Farbwerte sind unverändert.

**Web-Export (Compatibility-Renderer):** alle Shader kompilieren dort (keine Tiefen-/Bildschirmtexturen, kein
Compute); SSAO und Luftperspektive gibt es im Web nicht, sie werden ignoriert. Partikel sind CPU-Partikel.

**Sichtprüfung:** `view_probe.gd -- --pair --advance=0.4` rückt im Bildpaar zusätzlich die Weltanimation vor
(Flügel, Vögel, Boote, Wolken unterscheiden sich). Achtung: Die Mühle hat sechs Flügel – ein Vorrücken um ~1 rad
sieht wie Stillstand aus.
**Kosten:** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070): Mittel 59,8 fps, min 6,9, 1-%-Tief
53,7 fps, 186 von 39 565 Frames < 50 fps – vorher auf derselben Fahrt 59,9 / 7,2 / 54,6 / 130 (Streuung früherer
Läufe 83–180).

## Tag, Nacht und Wetter

Tageszeit, Sonnenstand und Wetter (G6) stellt `src/sky_controller.gd` (`SkyController`, Knoten `Sky`, von
`scenes/main.gd` in `_ready` angelegt). Rechnungen sind reine Funktionen, headless getestet
(`tests/test_day_night_weather.gd`).

**Zeitbasis:** echte **Ortszeit auf Mallorca** (Europe/Madrid: MEZ = UTC+1, MESZ = UTC+2 nach EU-Regel, letzter
Sonntag im März/Oktober 01:00 UTC). Die Uhr (`src/day_night.gd`, `DayNight`) zählt UTC-Sekunden aus der Systemuhr
und rechnet selbst in Mallorca-Zeit um – die Zeitzone des Rechners spielt keine Rolle (in Deutschland ohnehin
dieselbe). Annahme: die Systemuhr geht richtig. **Sonnenstand** für Palma (39,57° N, 2,65° O) nach der NOAA-Näherung
(Zeitgleichung, Deklination, Stundenwinkel); gerechnet: 21.06. Aufgang 6:22, Untergang 21:20 MESZ, Mittag 73,9°;
21.12. Aufgang 8:06, Untergang 17:28 MEZ, Mittag 27,0° (Test gegen Palma 6:20/21:20 und 8:10/17:30, ±15 min, sowie gegen unabhängig nach USNO gerechnete Werte für
20.03., 07.10. und den Umstellungstag 29.03., ±6 min).
Norden = −z, Osten = +x.

**Modi** (`[sky] time_mode`): `realtime` Echtzeit (Standard) · `fixed` feste Ortszeit `fixed_hour` · `timelapse`
Zeitraffer, ein Tag in `timelapse_day_min` Minuten (Standard 24).

**Licht über den Tag** (`SkyController.look(sonnenhöhe, wetter, compat)`): Sonne aus Höhe/Azimut, mittags wie G3
(Energie 1,25, warmweiß), tief stehend orange (Abendrot, Horizont rötlich), unter dem Horizont aus. Nachts ein
schwacher bläulicher **Mond** (vereinfacht gegenüber der Sonne, mind. 25° hoch, ohne Schatten und Phasen), Sterne
(900 Punkte, nur bei klarem Himmel), Umgebungslicht bläulich mit Energie 0,5 und Belichtung 1,2 – die Strecke bleibt
**befahrbar und erkennbar**. Unter 3° Sonnenhöhe (bei dichter Bewölkung 7°) gehen die **Lichter** an
(`src/night_lights.gd`): Leuchtpunkte an allen Laternen (Bergdorf, neu: 12 an der Uferstraße im Hafen) und an den
Molenfeuern (ein MultiMesh, `src/shaders/glow.gdshader`), echte Lichter nur an den 6 Laternen nächst der Kamera
(OmniLight3D, 16 m, ohne Schatten); **Leuchtturm** mit hellem Kegel, Spot (320 m) und Glühen; **Fahrradlicht**
vorn (Spot auf die Straße) und hinten (rot) an `Track/Rider/Model/Lean/Bike`. Vögel fliegen nachts und bei Regen
nicht. Neu angewandt wird höchstens alle 0,25 s und nur, wenn die Sonne sich ≥ 0,05° bewegt hat oder das Wetter
überblendet (der Himmel wird bei jeder Änderung neu berechnet).

**Wetter** (simuliert, kein Online-Wetter – `src/weather.gd`, `Weather`): `clear` klar · `light_clouds` leicht
bewölkt · `overcast` bewölkt/dunstig · `rain` leichter Regen. Wirkung: Wolkenbedeckung (sichtbarer Anteil, dichter
auch größer) und Tönung, grauer Himmel, weniger direkte Sonne (bedeckt ohne Sonnenscheibe), Dunst/Nebel (Regen
~8-fach), entsättigt, mehr Wind (Wolkenzug, Vegetation, Wellenhöhe `wave_scale`), Meer grauer, Regen als Tropfen
um die Kamera (Forward+: 7000 GPU-Partikel, Web: 1800 CPU-Partikel), nasse Straße dunkler und glänzend. Modus
`[sky] weather_mode`: `changing` (Standard) – meist sonnig, je Zustand 4–45 min, dann Wechsel zu einem Nachbarn
(Regen nur über „bewölkt“), weich über 4 min; `fixed` – bleibt bei `weather`, Umstellen blendet in 10 s über.

**Web-Profil** (Compatibility-Renderer, erkannt über `RenderingServer.get_current_rendering_method()`): dort wirkt
`vertex_color_is_srgb` nicht und die Lichter-Kurve unterscheidet sich – mit den Forward+-Werten war das Bild blass und
überbelichtet. Das Profil gilt für alle Tageszeiten und Wetter: untexturierte Materialien der Welt (Vertex-Farben und
einfarbige Flächen) ×0,78, Sonne/Mond ×0,8, Belichtung ×0,92, Umgebungslicht ×1,0, Sättigung ×1,04, Kontrast ×1,04
(`SkyController.COMPAT_*`). Texturierte Modelle bleiben unverändert (sie stimmten schon).

**Schnittstelle** (z. B. für das Grafikmenü): `sky.set_time_mode(mode, hour = NAN)` mit `DayNight.MODE_REALTIME`,
`MODE_FIXED`, `MODE_TIMELAPSE` (Stunde = Ortszeit 0–24) und `sky.set_weather_mode(mode, state = "")` mit
`Weather.MODE_CHANGING`/`MODE_FIXED` und `Weather.CLEAR`, `LIGHT_CLOUDS`, `OVERCAST`, `RAIN`. Lesen: `sky.clock`
(`local_hour()`, `timelapse_day_min`), `sky.weather.state`, `sky.sun_angles`. `set_compatibility(bool)` schaltet das
Lichtprofil (Tests, Vergleich).

**Sichtprüfung:** `view_probe.gd -- --time=21:30 --date=2026-06-21 --weather=rain` (feste Ortszeit/Datum/Wetter
ohne Überblendung), `--profile=forward|compat` erzwingt das Lichtprofil (Vergleich vorher/nachher im
Compatibility-Renderer: `godot --rendering-method gl_compatibility …`).
**Kosten:** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070), Datum 21.06.: Tag (13:30, klar) Mittel
59,9 / min 7,2 / 1-%-Tief 53,2 / 61 Frames < 50 fps; Nacht (23:30) 60,0 / 36,4 / 52,2 / 342; Regen (14:00) 60,0 /
8,8 / 52,6 / 30 – jeweils ~39 700 Frames (Einzelhänger wie vor G6, siehe oben).

## Fahrer und Rad

Statt der Kapsel fährt ein stilisierter Rennradfahrer (`Track/Rider/Model`), **prozedural aus Godot-Grundkörpern**
(keine fremden Assets): Rahmen aus Rohren, Laufräder (Ø 0,68 m) mit Reifen, Felge und Speichen, Rennlenker, Sattel,
Kurbel mit Kettenblatt, Kette und Pedalen, Trinkflasche; Fahrer mit Helm und Brille, Trikot, Hose, Socken, Schuhen.

- `src/rider_motion.gd` (reine Logik, getestet): Kurbelwinkel += 2π · Kadenz/60 · dt, Radwinkel += v · dt / 0,34 m,
  Schräglage atan(v² · κ / g) bis 15°, Vorbeuge bergauf bis 9°, Wiegen mit dem Tritt; Knie/Ellbogen per
  Zwei-Glieder-IK. In jedem Zustand außer `riding` stehen Kurbel, Beine und Räder; bei Kadenz 0 rollt das Rad aus.
- `src/rider_model.gd` baut die Geometrie (~90 Teile, ein Material je Farbe) und setzt die Pose;
  `scenes/main.gd` übergibt pro Frame Kadenz, Tempo, Steigung, Krümmung (`current_curvature()`) und Pause.
- Kosten: fps-Fahrt 0–2310 m ohne VSync 1202 statt 1229 fps (~0,02 ms/Frame); mit VSync unverändert ~60 fps.
- Sichtprüfung: `view_probe.gd -- --cadence=85 --close --pair` (Nahaufnahmen seitlich/schräg hinten, zweites Bild
  0,15 s später mit anderer Kurbelstellung).

## Spielen

1. Bridge starten (siehe `bridge/README.md`), z. B. mit dem Simulator:
   `vspin-bridge --source sim --sim-cadence 80` – im Bridge-Terminal Kadenz mit Pfeil hoch/runter ändern.
2. Spiel starten – es verbindet sich automatisch mit dem Bus und verbindet bei Abbruch neu:
   ```
   godot --path games/island-ride                 # oder Projekt im Godot-Editor öffnen und F5
   ```
Reihenfolge egal: Startet das Spiel zuerst, zeigt es „Bridge nicht erreichbar … Bridge starten:
`vspin-bridge --source sim`“ und versucht alle `reconnect_s` Sekunden zu verbinden.

### Tasten

| Taste | Wirkung |
|---|---|
| `P` oder Leertaste | Pause an/aus (jederzeit) |
| `Esc` | Spiel beenden (jederzeit) |
| `F3` | Debug-Anzeige an/aus |

Physische Tastenposition (gleich auf QWERTZ/QWERTY); definiert in `scenes/main.gd` (`KEY_BINDINGS`).

### Spielzustände

| Zustand (`state`) | Wann | Anzeige |
|---|---|---|
| `riding` – fahren | Bus verbunden, Quelle `connected` und seit dem letzten Abbruch Telemetrie empfangen | – |
| `paused_manual` – pausiert (manuell) | `P`/Leertaste | „Pause“ |
| `paused_connection` – pausiert (Verbindung) | Bridge nicht erreichbar, Quelle `stale`/`disconnected` oder noch keine Daten | „Bridge nicht erreichbar … Bridge starten“ bzw. „Verbindung verloren (Rad: stale)“ |
| `finished` – Ziel erreicht | Ziellinie überfahren (Endzustand, Pause-Taste wirkungslos) | „Ziel erreicht!“ mit Zeit, Ø Kadenz, Ø Tempo |

In jeder Pause steht das Fahrmodell still: Position und Geschwindigkeit bleiben, wie sie waren. Ein
Verbindungsabbruch ist **keine Kadenz 0** (ADR-0004) – der Fahrer rollt nicht aus. Sobald der Bus wieder
verbunden ist, die Quelle `connected` meldet und Telemetrie ankommt, fährt das Spiel von selbst weiter.
Die Verbindungspause hat Vorrang; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen
(kein automatisches Weiterfahren aus der manuellen Pause). Hängt ein Verbindungsaufbau länger als
`connect_timeout_s`, bricht der Bus-Client ihn ab und versucht es neu.

### HUD

Oben links: Kadenz (rpm, gerundet), Tempo (km/h), Strecke (km seit Start), Zeit (Fahrzeit, ohne Pausen),
Abschnitt (Station des Insel-Rundkurses; nicht bei der Graybox),
Steigung (%) und – **nur wenn die Quelle Watt liefert** – Leistung. Geschätzte Watt (`power_estimated`
nicht ausdrücklich `false`) immer mit „~“, z. B. „~142 W“ (ADR-0004); gemessene ohne. Darunter dezent der
`set_grade`-Hinweis, in der Mitte groß Pause-/Verbindungs-/Ziel-Meldungen.

### Debug-Anzeige (`F3`)

Oben rechts, zum Prüfen der Latenz (< 200 ms, ADR-0005): **Kadenz roh** (Feld `cadence` der letzten
Telemetrie, wie empfangen – ungerundet), **t_ms** (Bridge-Zeitstempel der letzten Telemetrie), **Alter**
der letzten Telemetrie in ms (seit Empfang im Spiel; bei 4 Hz Bridge-Takt pendelt es zwischen 0 und ~250 ms
– dauerhaft mehr heißt: Daten stocken), dazu Bus-Verbindung, Status und Quelle. Prüfen: Kadenz in der
Bridge ändern und schauen, wann „Kadenz roh“ und `t_ms` nachziehen.

### Runde und Ziel

Eine Runde startet an der Startposition (Standard: Start/Ziel-Linie) und endet beim nächsten Überfahren der
Start/Ziel-Linie (bei Start mitten auf der Strecke, z. B. in Tests, also früher). Im Ziel steht der Fahrer,
das Spiel zeigt „Ziel erreicht!“ mit Rundenzeit, Ø Kadenz (zeitgewichtet) und Ø Tempo (Strecke/Fahrzeit).
Fahrzeit und Durchschnitte zählen nur Zeit im Zustand `riding` – Pausen nicht; der letzte Zeitschritt
wird nur bis zur Ziellinie gezählt (`src/ride_stats.gd`).

### Virtuelle Steigung (`set_grade`)

Das Spiel meldet die Steigung an der Fahrerposition per `{"v": 0, "type": "set_grade", "grade": 0.06}`
(Anteil, ADR-0007; Logik in `src/grade_reporter.gd`):

- gleich nach dem Verbinden (sobald gefahren wird) den aktuellen Wert,
- danach nur bei Änderung um mindestens 0,5 Prozentpunkte (0.005) und höchstens 2-mal pro Sekunde –
  eine gedrosselte Änderung wird mit dem dann aktuellen Wert nachgeholt,
- nicht in der Verbindungspause (sinnlos); nach der Rückkehr wird der aktuelle Wert erneut gemeldet,
  auch wenn er sich nicht geändert hat.

Die Antwort (`ack`) der Bridge erscheint dezent unter den Werten: „Widerstand: nicht unterstützt“ bei
`ok: false, reason: "not_supported"` (Normalfall bis zum ESP32), „Widerstand: Fehler (…)“ bei anderem Grund,
nichts bei `ok: true`. `error`-Antworten landen als Warnung im Log. Mit dem Simulator sinkt bergauf die
Kadenz; die Steigung steht in der Session-CSV der Bridge (Spalte `grade`).

## Konfiguration

`config.cfg` (ConfigFile/INI) – Änderungen wirken beim nächsten Start, ohne Codeänderung:

| Schlüssel | Standard | Wirkung |
|---|---|---|
| `[bus] url` | `ws://127.0.0.1:8765` | Bus-Adresse |
| `[bus] reconnect_s` | `2.0` | Sekunden zwischen Verbindungsversuchen |
| `[bus] connect_timeout_s` | `5.0` | hängt ein Verbindungsaufbau länger, wird er abgebrochen und neu versucht |
| `[ride] k_kmh_per_rpm` | `0.33` | Übersetzungsfaktor k: `v_ziel = k · Kadenz` (km/h) auf flacher Strecke |
| `[ride] uphill_damping` | `8.0` | bergauf: `v_ziel / (1 + uphill_damping · Steigung)` |
| `[ride] downhill_boost` | `2.0` | bergab: `v_ziel · (1 + downhill_boost · \|Gefälle\|)` |
| `[ride] inertia_s` | `1.5` | Trägheit: Zeitkonstante (s) der Annäherung an `v_ziel`; 0 = sofort |
| `[world] track` | `island` | Strecke: `island` = Insel-Rundkurs, `graybox` = kurze Graybox-Teststrecke (~900 m); Unbekanntes → `island` |
| `[sky] time_mode` | `realtime` | Tageszeit: `realtime` = echte Ortszeit Mallorca, `fixed` = feste Stunde, `timelapse` = Zeitraffer; Unbekanntes → `realtime` |
| `[sky] fixed_hour` | `13.0` | Ortszeit (h, 0–24) für `fixed` (z. B. `21.5` = 21:30) |
| `[sky] timelapse_day_min` | `24.0` | Zeitraffer: Minuten echter Zeit je Tag |
| `[sky] weather_mode` | `changing` | Wetter: `changing` = wechselnd (meist sonnig), `fixed` = fest; Unbekanntes → `changing` |
| `[sky] weather` | `clear` | Anfangs-/festes Wetter: `clear`, `light_clouds`, `overcast`, `rain` |

Steigung als Anteil (0.06 = 6 %, wie `set_grade`). Fehlende Schlüssel → Standardwerte aus `src/ride_config.gd`.

## Tests

Headless mit GUT 9.4 (`addons/gut`, MIT) und einem Fake-Bus-Server. Im Repo-Wurzelordner:

```
godot --headless --path games/island-ride --import          # einmalig bzw. nach neuen Skripten/Klassen
godot --headless --path games/island-ride -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Ausgabe endet mit `Scripts / Tests / Passing / Failing`; Exit-Code ≠ 0 bei Fehlschlag. `.gutconfig.json`
setzt dieselben Optionen und einen Post-Run-Hook (`tests/support/post_run_check.gd`), der den Lauf
fehlschlagen lässt, wenn ein `test_*.gd` nicht ladbar ist (GUT allein überspringt es nur mit Warnung).
Einzelnes Skript: zusätzlich `-gselect=test_bus_client`. Die Tests brauchen keine Bridge und
benutzen Ports ab 18765 – nie den Bus-Port 8765.

### Testmuster: Fake-Bus und Drehbuch

Ein guter Test prüft von außen: Drehbuch rein → beobachtbares Spielverhalten raus
(`bus.cadence`/`bus.status`, `state`, `model.speed_kmh()`, `model.distance_m`, HUD), nicht Interna.

- `tests/support/fake_bus_server.gd` (`FakeBusServer`): WebSocket-Server (`TCPServer` +
  `WebSocketPeer.accept_stream`), spielt jedem Client ein **Drehbuch** vor und schreibt
  Client-Nachrichten in `received` mit (Empfangszeit in `received_ms`, gefiltert über
  `received_of_type("set_grade")`). Antworten auf Client-Nachrichten:
  `bus.replies["set_grade"] = FakeBusServer.ack("set_grade", false, "not_supported")`.
- `tests/support/bus_test.gd`: Basisklasse für Tests (`extends "res://tests/support/bus_test.gd"`):
  `start_fake_bus(steps)`, `spawn_ride(bus, start_m, config)` (Hauptszene am Fake-Bus),
  `config_for(bus, path, track)` (Spiel-Konfiguration am Fake-Bus; Strecke standardmäßig **Graybox** – kurz und mit
  Steigungen an festen Positionen; Insel-Tests übergeben `RideConfig.TRACK_ISLAND`),
  `connect_client(bus)` (nackter `BusClient`), `run_for(s)`, `run_until(cond, timeout_s)`,
  `press_key(KEY_P)` (Taste wie ein Spieler drücken); räumt nach jedem Test auf. `spawn_ride` setzt
  `quit_on_request = false` – `Esc` meldet dann nur `quit_requested`, statt den Testlauf zu beenden.

Drehbuch = Array von Schritten, `at` = Sekunden ab Verbindungsaufbau des Clients; jede Verbindung
spielt von vorn (so lässt sich auch Reconnect prüfen):

```json
[
  {"at": 0.0, "send": {"v": 0, "type": "status", "t_ms": 0, "state": "connected", "source": "sim", "capabilities": ["CADENCE"]}},
  {"at": 0.25, "send": {"v": 0, "type": "telemetry", "t_ms": 250, "cadence": 90.0, "speed_kmh": null, "power_w": null, "power_estimated": null, "heart_rate": null}},
  {"at": 2.0, "close": true}
]
```

Bausteine in GDScript: `FakeBusServer.status(state, source, capabilities, at)`, `telemetry(cadence, at, fields)`,
`steady_cadence(cadence, from_s, to_s, interval_s = 0.25, fields)`, `close_at(at)`, `ack(for, ok, reason)`
(`fields` ergänzt Telemetrie-Felder, z. B. `{"power_w": 142.0, "power_estimated": true}`); als Datei über
`FakeBusServer.load_script("res://tests/fixtures/….json")`.

```gdscript
extends "res://tests/support/bus_test.gd"

func test_more_cadence_is_faster() -> void:
	var slow := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(60.0, 0.0, 5.0)))
	var fast := spawn_ride(start_fake_bus([FakeBusServer.status()] + FakeBusServer.steady_cadence(90.0, 0.0, 5.0)))
	await run_for(3.0)
	assert_gt(fast.model.speed_kmh(), slow.model.speed_kmh())
```

### End-to-End mit echter Bridge (manuell)

`tools/e2e.sh` startet je Kadenz die echte Bridge mit Simulator (`--sim-cadence N`, Port 8765 muss frei
sein), fährt das Spiel headless (`tools/e2e_probe.gd`) und vergleicht die Geschwindigkeiten:

```
GODOT=godot PYTHON=python games/island-ride/tools/e2e.sh 60 90
```

`set_grade` von Hand prüfen: Bridge starten (`vspin-bridge --source sim --sim-cadence 80`), dann
`godot --headless --path games/island-ride -s res://tools/e2e_probe.gd -- --seconds=9 --start-m=2400`
(Insel: Serpentinen; mit `--track=graybox --start-m=120` kurz vor dem Graybox-Anstieg). Erwartet: im
Bridge-Terminal `set_grade … -> not_supported`, Kadenz sinkt bergauf, in der Session-CSV füllt sich die Spalte
`grade`; die Probe-Zeile zeigt `station=Serpentinen` und `hint=Widerstand: nicht unterstützt`.

## Aufbau

```
config.cfg              Bus-Adresse, Fahrmodell-Parameter, Strecke, Tageszeit und Wetter
scenes/main.tscn/.gd    Hauptszene: Strecke laut Konfiguration, Bus-Client → Fahrmodell → Fahrer auf dem Pfad, Kamera, Spielzustände, Tasten, HUD
src/bus_client.gd       BusClient: verbinden/reconnecten (mit Verbindungs-Timeout), status/telemetry parsen, send_message
src/ride_stats.gd       RideStats: Fahrzeit, Strecke, Ø Kadenz, Ø Tempo (ohne Pausen) – reine Logik
src/grade_reporter.gd   GradeReporter: wann `set_grade` gesendet wird (Schwelle, Drosselung) – reine Logik
src/ride_model.gd       RideModel: reine Logik (Kadenz, Steigung, Δt, Konfig → Geschwindigkeit, Position)
src/rider_motion.gd     RiderMotion: Kurbel-/Radwinkel, Schräglage, Vorbeuge, Glieder-IK – reine Logik
src/rider_model.gd      RiderModel: Fahrer und Rennrad aus Grundkörpern, Pose aus RiderMotion
src/ride_config.gd      RideConfig: liest config.cfg
src/track.gd            Track (Path3D): length_m(), grade_at(distanz), position_at(distanz), stations, station_at(), road_mesh()
src/island_course.gd    IslandCourse: Insel-Rundkurs – Grundriss, Höhenprofil, Stationen (reine Daten/Logik)
src/island_terrain.gd   IslandTerrain: Höhenfeld (prozedural oder Höhenkarte), unter die Straße geformt, Mesh
src/island_world.gd     IslandWorld: Gelände, Meer, Fahrbahn, Stationsmarker, Deko aller Stationen mit Modellen (#15, #16)
src/island_landmarks.gd IslandLandmarks: Sehenswürdigkeiten und Kleindetails (G2), Platzierungsdaten für Tests
src/world_motion.gd     WorldMotion: bewegte Szenen und Effekte (G3) – Mühlen, Leuchtturm, Boote, Vögel, Wolken, Brunnen
src/day_night.gd        DayNight: Uhr (Mallorca-Ortszeit, Modi), Sonnenstand, Auf-/Untergang – reine Logik
src/weather.gd          Weather: simuliertes Wetter, Zustände und Übergänge – reine Logik
src/sky_controller.gd   SkyController: Sonne, Mond, Himmel, Environment, Regen, Sterne, Web-Lichtprofil (G6)
src/night_lights.gd     NightLights: Laternen, Leuchtfeuer, Fahrradlicht bei Nacht
src/shaders/            Wind (Vegetation), Meer (Wellen, Flachwasser, Brandung), Lichtkegel, Leuchtpunkte
src/graybox_track.gd    GrayboxTrack: Rundkurs ~900 m, flach → +6 % → Kuppe → −6 % → flach (`[world] track="graybox"`)
tests/                  GUT-Tests, support/ (Fake-Bus, Basisklasse, Hook), fixtures/
tools/                  E2E-Prüfhilfe gegen die echte Bridge, Sichtprüfung/fps (view_probe.gd)
addons/gut/             GUT 9.4.0 (MIT, Lizenz in addons/gut/LICENSE.md)
assets/kenney/          Low-Poly-Modelle (CC0) für alle Stationen
ASSETS.md               Asset-Nachweis und Lizenzregel
```

Noch nicht enthalten: Terrain3D (ADR-0006 Nachtrag).
