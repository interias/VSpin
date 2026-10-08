# Inselfahrt (`island-ride`)

Prototyp-Game (ADR-0005): 3D-Radsimulator in Godot 4.4 (GDScript). Das Spiel ist ein Client am
Bus (`docs/bus-protocol.md`); die Kadenz bewegt den Fahrer entlang eines `Path3D` – kein Lenken.
Stand: Insel-Rundkurs (~9,2 km, Grundform aus Gelände + Straße, #14) mit HUD, Debug-Anzeige, Spielzuständen
(Pause bei Verbindungsverlust, manuelle Pause, Ziel mit Zusammenfassung) und `set_grade` an die Bridge; Startmenü
mit Titelbild und Spielstand (#30). Die kurze Graybox-Strecke bleibt per Konfiguration wählbar (und ist die Grundlage
vieler Tests).

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

**Gegenrichtung (#34):** Im Menü „Rundfahrt“ lässt sich die Runde auch **gegen den Uhrzeigersinn** fahren – derselbe
Pfad rückwärts, gleiche Länge, Steigung gespiegelt: ab dem Hafen der lange Anstieg über den Osthang (Station heißt
dann **Osthang**, Ø ~7,5 %, bis 8,8 %), Bergdorf, Hain, die Serpentinen als Abfahrt, Küstenstraße, Ziel im Hafen.
Gespiegelt wird nur in `Track` (Fahrtposition d → Pfadposition L − d, Vorzeichen der Steigung); Rundenwertung,
Segmente und Ghost sehen in beiden Richtungen eine steigende Fahrtposition. Stationsschilder, Kilometersteine und
Segment-Torbögen stehen je Richtung richtig; Minikarte und Höhenprofil zeigen die Fahrtrichtung. Das Training fährt
im Uhrzeigersinn (`tests/test_counter_direction.gd`, `tests/test_counter_direction_ride.gd`).

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
    Kilometersteine 1–9 rechts am Rand, Agaven (teils mit Blütenstand), Feigenkakteen, Blumen, die Lagen der Schaf-
    und Ziegenherden (gebaut und bewegt von IslandFauna, #40), Boote und Bojen in den Buchten der Westküste, Bushaltestelle vor dem Bergdorf. Nur Godot-Grundkörper
    (je Landmarke ein Mesh) und vorhandene Kenney-Modelle, eigene Seeds 1507/1508. Animierbar (für bewegte Szenen):
    `windmuehlen/Muehle<n>/Fluegel` (Drehachse lokal z), `leuchtturm/Lampe` (Drehachse lokal y), `Details/Boote/*`.
  - **Vegetation und Bodentexturen (#38, `src/island_vegetation.gd`, Knoten `World/Vegetation/<Station>`):** auf jeder
    Station Grasbüschel (~210–450 je 100 m), Unterholz (~35–80) und Sträucher (~12–24) beidseits der Straße, am
    Bankett am dichtesten; Low-Poly aus Grundformen (Halme als Prismen, Polster und Sträucher aus Ikosaedern), keine
    Modelldateien, alle im Wind. Ausgespart: Fahrbahn und Mauer, Strand, Steilhänge, Kai, Häuser, Kirchplatz,
    Fincas, Aussichtspunkt, Landmarken. Je Art und 50 m Strecke ein MultiMesh mit Sichtweite (Gras 150 m,
    Unterholz 220 m, Sträucher 400 m), ohne Schatten. Gelände und Fahrbahn tragen eine dezente Detailtextur
    (prozedural, weltfest projiziert): Boden mit Flecken aus Erde und Gras und Körnung, Straße mit Asphaltkorn und
    ausgebesserten Stellen. **Browser:** halb so viel Gras und Unterholz, 70 % der Sichtweite. Alle Farben in
    `IslandVegetation.PALETTE`; `IslandVegetation.set_palette()` färbt Vegetation und Bodentextur zentral um
    (Einhängepunkt für die Jahreszeiten, #39). Eigene Seeds 1511–1516. Dazu die Arten der Jahreszeiten (#39, siehe
    „Jahreszeiten“): Mohn am Wegrand, Mandelbäume im Hain und an der Abfahrt, Getreidefelder an der Abfahrt.
    Kosten: fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070): Mittel 60,0 fps, 1-%-Tief 53,1 fps,
    24 von 39 724 Frames < 50 fps – vorher auf derselben Fahrt 60,0 / 53,2 / 18; im Compatibility-Renderer 59,9 /
    59,3 / 66.
  - **Weide- und Dorftiere (#40, `src/island_fauna.gd`, Knoten `World/Fauna`):** reine Deko (ADR-0010), Low-Poly
    aus Grundkörpern. Die Schaf- und Ziegenherden grasen (Kopf gesenkt und kauend, ein paar Schritte, Umschauen;
    MultiMesh `Details/Schafe|Ziegen` mit Köpfen `…/Koepfe`), die Schafe tragen Glocken. Ziegengruppen queren an drei
    Stellen die Straße (1,24 km Küste, 2,86 und 3,62 km Serpentinen) und springen über die Mauer: abhängig vom
    Abstand des Fahrers in Fahrtrichtung, ab 100 m voraus, ab 35 m ist die Fahrbahn frei – in beiden Richtungen.
    An jeder Finca der Abfahrt steht ein Esel am Pfosten mit Heu, im Bergdorf sitzen und streifen acht Katzen auf
    dem Gehweg und am Kirchplatz. Nicht auf der Fahrbahn, in Häusern oder auf Feldern. Bewegt werden nur Tiere bis
    250 m um die Kamera. Glocken-Einhängepunkt für den Ton (#44): `Fauna/Glocken/Herde<n>` (Meta `count`).
    Sichtprüfung: `view_probe --fauna`. Kosten: fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080,
    13:00, Frühling, VSync an (RTX 4070): Mittel 60,0 fps, 1-%-Tief 58,2 fps, 8 von 39 712 Frames < 50 fps –
    vorher auf derselben Fahrt 60,0 / 58,2 / 4.
  - **Tiere an Meer, Himmel und Wegrand (#41, `src/island_fauna.gd`, Gruppen `World/Fauna/<Art>`):** reine Deko,
    Low-Poly aus Grundkörpern. Delfinschulen kreisen in der Hafenbucht und vor der Westküste und springen
    nacheinander, Fische springen mit Spritzern nah am Kai und unter der Küstenstraße, vier Mönchsgeier kreisen in
    der Thermik über den Serpentinen (der einzelne Greifvogel aus WorldMotion bleibt als Milan), Schmetterlinge
    flattern paarweise über Gras am Wegrand, Eidechsen sonnen sich auf der Mauer an Küstenstraße und Serpentinen und
    huschen ein Stück. Wann sie sich zeigen, regelt `IslandFauna.SHOWN_WHEN` (der SkyController stellt es über
    `set_conditions`): Schmetterlinge nur tagsüber ohne Regen und nicht im Winter, Eidechsen nur bei Sonne, Geier
    tagsüber ohne Regen, Fische nicht im Regen, Delfine bei jedem Wetter – nachts keine. Im Browser halb so viele
    Fische, Schmetterlinge und Eidechsen. Sichtprüfung: `view_probe --fauna` (Delfine und Fische im Sprung).
    Kosten: fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, 13:00, Frühling, VSync an (RTX 4070): Mittel 60,0 fps,
    1-%-Tief 58,1 fps, 7 von 39 718 Frames < 50 fps – vorher (nach #40) 60,0 / 58,2 / 8.
  - Modelle: Kenney Watercraft Kit, City Kit (Suburban), Nature Kit, Fantasy Town Kit (CC0) unter `assets/kenney/`,
    nur die benutzten `.glb` (~1,4 MB) – Nachweis in `ASSETS.md`. Wiederholte Modelle (Bäume, Büsche, Felsen,
    Mauern, Hausmodule) als `MultiMeshInstance3D`. Sichtprüfung/fps: `tools/view_probe.gd` (Screenshots an Streckenpositionen, fps-Fahrt).
- Kamera (`scenes/main.gd`): sitzt 5,5 m hinter dem Fahrer **auf der Strecke** (schwenkt in Kehren nicht seitlich
  aus), 2,4 m hoch, blickt 10 m voraus, beides exponentiell geglättet (0,45 s), mindestens 1,5 m über dem Gelände.
  Abstand, Höhe und Vorausblick in `config.cfg` (`[camera]`, siehe Konfiguration); vor G5 9 m / 3,5 m / 14 m.
  Beim Fahrtstart ein **Kamera-Intro** (#42, siehe „Farbstimmung, Höhennebel und Tempo“), an Sehenswürdigkeiten
  **Panorama-Momente** (#43, ebenda).
- HUD zeigt zusätzlich den aktuellen Abschnitt, Höhenprofil und Minikarte der Insel (siehe HUD).

Weltaufbau beim Start ca. 0,6 s (mit der Vegetation aus #38 ca. 1,1 s), beim allerersten Start (oder nach Änderung
an Gelände/Rundkurs) ca. 1,8 s
(headless gemessen, #19). Das Gelände (Höhen, Straßenabstand) liegt als Cache in `user://terrain_cache.bin`
(~1 MB; unter Windows `%APPDATA%\Godot\app_userdata\Inselfahrt\`); Schlüssel ist ein SHA-256 über den Quelltext von
`src/island_terrain.gd` und `src/island_course.gd` und die Engine-Version – jede Änderung daran erzeugt neu. Datei
löschen ist gefahrlos. Im Export ohne lesbaren Quelltext (z. B. Web) wird wie bisher bei jedem Start erzeugt. Das
Mesh (~0,4 s) wird weiter jedes Mal gebaut (als Cache 6–9 MB für ~0,3 s Gewinn – lohnt nicht).

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
**Sichtprüfung G5 (HUD und Kamera):** fps-Fahrt 0–2310 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070), HUD sichtbar
(`--hud`): Mittel 60,0 fps, 1-%-Tief 55,2 fps, 14 von 9 911 Frames < 50 fps – vorher (alte Kamera, HUD aus)
59,8 / 54,1 / 33.

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
Lichtprofil (Tests, Vergleich). Im Grafikmenü (`Esc`/`F2`, G8) lassen sich Tageszeit, Wetter und Jahreszeit umstellen; die Auswahl
liegt in `user://settings.cfg [sky]` über `config.cfg [sky]` (siehe „Grafik und Fenster“).

**Sichtprüfung:** `view_probe.gd -- --time=21:30 --date=2026-06-21 --weather=rain` (feste Ortszeit/Datum/Wetter
ohne Überblendung), `--profile=forward|compat` erzwingt das Lichtprofil (Vergleich vorher/nachher im
Compatibility-Renderer: `godot --rendering-method gl_compatibility …`).
**Kosten:** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070), Datum 21.06.: Tag (13:30, klar) Mittel
59,9 / min 7,2 / 1-%-Tief 53,2 / 61 Frames < 50 fps; Nacht (23:30) 60,0 / 36,4 / 52,2 / 342; Regen (14:00) 60,0 /
8,8 / 52,6 / 30 – jeweils ~39 700 Frames (Einzelhänger wie vor G6, siehe oben).

### Jahreszeiten (#39)

Die **Jahreszeit** folgt wie die Tageszeit dem echten Datum auf Mallorca (dieselbe Uhr, `sky.clock`; Ortsdatum) –
oder steht fest (Grafikmenü, Feld *Jahreszeit*: *Nach Datum (Mallorca)* oder eine Phase; gespeichert in
`settings.cfg [sky]` als `season_mode`/`season`). Fünf Phasen (`src/season.gd`, `Season`, reine Logik):

| Phase | Datum | Insel |
|---|---|---|
| Mandelblüte (`almond`) | 25.01.–09.03. | Mandelbäume weiß-rosa, Wiesen und junges Getreide grün |
| Frühling (`spring`) | 10.03.–31.05. | saftig grün, roter Mohn am Wegrand |
| Sommer (`summer`) | 01.06.–15.09. | Gras, Unterholz und Felder goldgelb und trocken, Boden heller, Licht warm |
| Herbst (`autumn`) | 16.09.–30.11. | ockerfarbenes Gras, Stoppelfelder, Licht warm und milder |
| Winter (`winter`) | 01.12.–24.01. | grün (Regenzeit), Mandelbäume kahl, Licht kühler und blasser |

Ein Wechsel färbt die Welt um, ohne sie neu zu bauen (`IslandWorld.set_season`): Vegetation und Boden über
`IslandVegetation.set_palette()`, die Kenney-Vegetation über `IslandWorld.tint_nature()` (Faktor je Materialname
`grass`/`leafsGreen` auf die Farben vom Laden), der Mohn blendet ein/aus. Die Farben je Phase stehen in
`Season.LOOKS`, die dezente Farbstimmung des Lichts (Sonne, Umgebungslicht, Sättigung) in
`SkyController.SEASON_MOOD`. Für die Erfolge zählt die Mandelblüte als Frühling (Erfolg *Mandelblüte*).
Schnittstelle: `sky.set_season_mode(Season.MODE_REAL | MODE_FIXED, phase)`, `sky.season()`.
**Sichtprüfung:** `view_probe.gd -- --season=summer` (ohne Angabe nach `--date` bzw. heute).
**Kosten:** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070), Frühling (Mohn sichtbar): Mittel
60,0 fps, 1-%-Tief 53,0 fps, 2 von 39 723 Frames < 50 fps (vorher 60,0 / 53,2 / 2).

### Farbstimmung, Höhennebel und Tempo (#42)

**Farbstimmung** je Tageszeit und Wetter an derselben Stelle wie das Licht (`SkyController.look`, Konstanten
`MOOD_MORNING`, `MOOD_EVENING`, `MOOD_GREY`), vor der Jahreszeit-Tönung (`SEASON_MOOD`, dazu `SEASON_FOG` für die
Nebelfarbe – ein Faktor obendrauf): tiefe Sonne **morgens** (Sonne im Osten) kühl-pfirsich mit Dunst, **abends**
golden und satter, **Wolken und Regen** kühl und flauer. Am klaren Mittag und nachts bleibt das Licht wie bisher. Alle
Gewichte laufen stetig mit Sonnenhöhe, Azimut und Wetter – keine Sprünge. **Höhennebel** (`fog_height`,
`fog_height_density` des Environments): Morgendunst und Regen liegen über Meer und Hafen (bis 2,5 m bzw. 5 m über dem
Meer), bei Bewölkung schwächer, am klaren Tag aus. Er wirkt in beiden Renderern; volumetrischen Nebel gibt es nicht.

**Tempo-Effekte** (`src/speed_effects.gd`, Shader `src/shaders/speed_lines.gdshader`): ab 35 km/h ziehen feine
**Geschwindigkeitslinien** vom Bildrand nach außen und das Sichtfeld weitet sich leicht (bis +5° bei 60 km/h) –
stetig mit dem Tempo und geglättet, in Pausen weich aus. Abschaltbar im Grafikmenü (*Tempo-Effekte*). Nur Darstellung:
Fahrmodell, Zeiten und Wertung sehen davon nichts (ADR-0010).

**Kamera-Intro:** Nach „Losfahren“ (Rundfahrt in beiden Richtungen und Training) schwenkt die Kamera in 3 s von
schräg vor dem Fahrer über seine rechte Seite hinter ihn. Die Fahrt und die Zeitmessung laufen dabei normal. Die
Kamera hat dafür einen Modus (`camera_mode`: `CAMERA_FOLLOW`, `CAMERA_INTRO`, `CAMERA_PANORAMA`) an einer Stelle
(`_update_camera`).

**Panorama-Momente (#43):** An den acht vorhandenen Sehenswürdigkeiten (Aussichtspunkt, Leuchtturm, Cala, Talaia,
Ermita, Burgruine, Aquädukt, Windmühlen; `IslandWorld.panorama_spots`) schwenkt die Kamera beim Vorbeifahren 4 s lang
weich auf die abgewandte Seite des Fahrers, etwas erhöht, und blickt über ihn zur Sehenswürdigkeit; oben im HUD steht
dezent ihr Name. Danach gleitet sie ohne Sprung zurück hinter den Fahrer. Auslösepunkt ist die Fahrtposition der
Sehenswürdigkeit, also in beiden Richtungen (gegen den Uhrzeigersinn liegt der Aussichtspunkt am Ende der
Serpentinen-Abfahrt; der Blick aufs Meer funktioniert auch dort). Je Sehenswürdigkeit höchstens einmal je Runde. Kein
Panorama mit Ghost, im Training, während des Intros oder eines anderen Panoramas. Abschaltbar im Grafikmenü
(*Panorama-Momente*). Das Stationsschild am Aussichtspunkt blendet im Schwenk aus. Auch das ist nur Kamera: Fahrmodell
und Zeiten laufen unverändert (ADR-0010).

**Sichtprüfung:** `view_probe.gd -- --shots=3000 --time=08:45` (bzw. 13:00, 18:30, `--weather=rain`),
`--effects-kmh=55` (Tempo-Effekte in `--shots` wie bei 55 km/h), `--intro [--ccw]` (`intro_0.png`, `intro_1.png`,
`intro_2.png`), `--hud --panorama[=aussichtspunkt,burg]` (`panorama_<id>.png` mitten im Schwenk, ohne Liste alle,
mit `--ccw` in Gegenrichtung). Die fps-Fahrt zeigt die Tempo-Effekte bei ihrem Tempo; Panoramen löst sie nicht aus.
**Kosten:** fps-Fahrt 0–9210 m, 50 km/h, 1920 × 1080, VSync an (RTX 4070), Tempo-Effekte an (Stärke 0,65), Frühling:
13:00 klar Mittel 60,0 fps, 1-%-Tief 58,4 fps, 31 von 39 714 Frames < 50 fps (vorher nach #41: 60,0 / 58,1 / 7);
7:30 Regen mit Höhennebel 60,0 / 53,1 / 21 von 39 718.

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

   **Unter Windows geht es auch ohne Schritt 1 (#25, `src/bridge_launcher.gd`):** Ist beim Start keine Bridge auf
   `127.0.0.1:8765` erreichbar, startet das Spiel sie als unsichtbaren Kindprozess (`pythonw` aus `bridge/.venv`, kein
   Konsolenfenster) mit Quelle und Ablage aus `config.cfg [bridge]` (`autostart`, `program`, `source` = `sim`/`ble`,
   `sessions_dir`; relative Pfade ab dem Spielordner). Beim Schließen (Fenster, „Beenden“) beendet es nur diese eigene
   Bridge, sauber über die Stoppdatei (`--stop-file`, Session vollständig); erst wenn sie nach 5 s noch läuft, hart.
   Eine schon laufende Bridge wird nur mitbenutzt und nie beendet. Radstatus dabei: „Bridge nicht erreichbar – Bridge
   wird gestartet (Quelle sim) …“, „… – Bridge-Programm fehlt (config.cfg [bridge] program)“ oder „… – Bridge-Start
   gescheitert“. Im Web-Export und in Tests/Prüfhilfen (Bus nicht auf 8765 bzw. `autostart` aus) startet nichts.
3. Im Startmenü **Fahren → Rundfahrt** wählen, Rundenzahl und Tageszeit einstellen, **Losfahren** – oder
   **Fahren → Training**, Einheit wählen, **Losfahren**.

### Startmenü und Spielstand (#30)

Nach dem Start erscheint das **Titelbild**: die Kamera fliegt langsam hoch über dem Rundkurs (38 m über der Straße,
9 m/s, mindestens 22 m über dem Gelände) über die lebende Insel – Tageszeit, Wetter, Bewegung wie in der Fahrt; HUD
und Fahrer sind ausgeblendet. Darüber das Menü (`scenes/start_menu.gd`, per Maus oder Tastatur: Pfeiltasten/Tab,
Enter/Leertaste):

| Punkt | Wirkung |
|---|---|
| **Fahren** | Modus-Auswahl: **Rundfahrt**, **Training**, *Arcade – bald* ausgegraut, „Zurück“ |
| **Fahren → Rundfahrt** | **Runden** 1–20 oder *Endlos* (Standard 1), **Richtung** (*Im Uhrzeigersinn*, *Gegen den Uhrzeigersinn*, #34), **Tageszeit** (dieselbe Auswahl wie im Einstellungsmenü, Standard *Echtzeit*; wirkt und bleibt wie dort gewählt), **Ghost** (*Aus*, *Bestzeit*, *Letzte Fahrt*; ohne Aufzeichnung ausgegraut, Standard *Bestzeit*, sobald es sie gibt, #32), die **Bestzeit** der Strecke in der gewählten Richtung; **Losfahren** startet die Fahrt (#31) |
| **Fahren → Training** | **Einheit** (*Intervalle kurz*, *Pyramide*, *Tempo-Blöcke*) mit Beschreibung und Dauer; **Losfahren** startet das Training (#37, siehe unten) |
| **Fahrtenbuch** | Statistik, Bestzeiten, Segmentzeiten, Medaillen, Erfolge und die letzten Fahrten (#35, siehe unten) |
| **Garderobe** | Trikot, Radfarbe und Helm mit Vorschau, freigeschaltet über das Fahrerlevel (#36, siehe unten) |
| **Einstellungen** | öffnet das Menü „Grafik und Fenster“ (wie `Esc`/`F2`) |
| **Beenden** | beendet das Spiel (im Browser ausgeblendet) |

Unten steht dauerhaft der **Radstatus**: „Rad verbunden“ (Quelle `ble`), „Simulator läuft“ (`sim`), „Bridge nicht
erreichbar – Bridge starten: …“ oder „Bridge läuft – Rad nicht verbunden (stale)“. Im Menü läuft keine Fahrt und es geht
kein `set_grade` an die Bridge. **Zurück ins Menü**, ohne das Spiel zu schließen: im Ziel mit `Enter`, jederzeit über
„Fahrt beenden“ in den Einstellungen (`Esc`/`F2`). Eine neue Fahrt beginnt wieder am Start.

**Spielstand** (`src/save_game.gd`, ADR-0008 Nachtrag): `user://savegame.json` – unter Windows
`%APPDATA%\Godot\app_userdata\Inselfahrt\savegame.json`, im Browser im lokalen Speicher des Browsers. JSON mit
`version` (Formatversion, derzeit 1) und `active_profile` (Profilschlüssel, 16 Hex-Zeichen, ab dem ersten Speichern);
darunter je Fahrerprofil die Fahrten. Jede beendete Fahrt wird als Zusammenfassung angehängt – im Ziel sofort, bei
Abbruch („Fahrt beenden“, Beenden, Fenster schließen), sofern gefahren wurde: Datum (UTC), Modus, Strecke,
`finished`, Runden (volle), Dauer, Strecke in km, Ø Kadenz, Ø Tempo, Rundenzeiten (`lap_times_s`). Keine Rohtelemetrie
(die steht in der Session-CSV der Bridge). Bestzeiten stehen je Profil unter `best_times` (Strecke → Richtung →
Sekunden, z. B. `{"island": {"cw": 873.4}}`), Segment-Bestzeiten unter `segment_best_times` und die beste Medaille je Runde
(`lap`) und Segment unter `medals` (Strecke → Richtung → Segment-ID, #33), die Ghosts unter `ghosts` (Strecke → Richtung →
`best`/`last`, je nur `lap_length_m`, `sample_s`, `time_s` und `distance_m`, #32), die freigeschalteten Erfolge unter
`achievements` (Erfolg-ID → Datum, #35). Spätere Bereiche kommen additiv dazu; ältere
Stände werden beim Laden hochgestuft, ein Stand einer neueren Version bleibt unverändert erhalten, eine unlesbare
Datei wird als `savegame.json.defekt` beiseitegelegt statt überschrieben.

Sichtprüfung: `view_probe.gd -- --title [--window=left|right|fullscreen]` speichert `title.png`, `title_modes.png`
und `title_b.png` (3 s später); mit `--laps=3` zusätzlich `title_round_trip.png`. `--hud --laps=3 --shots=1500`
zeigt das HUD in Runde 2 und speichert danach `result.png` (Ergebnis mit allen Rundenzeiten, Medaillen und Segmenten).
`--hud --segments` speichert je Segment `segment_<id>.png` (Live-Zeit) und `segment_<id>_result.png` (Ergebnis beim
Verlassen); die Torbögen zeigt `--shots=466,2326,5686`. `--ghost=1.4` lässt einen Beispiel-Ghost mitfahren, gegen den
der Fahrer 1,4 s zurückliegt (mit `--hud` Abstand im HUD, mit `--title --laps=1` in der Ghost-Auswahl). `--ccw` fährt
gegen den Uhrzeigersinn (#34; `--shots` dann in Metern dieser Richtung, Torbögen z. B. `--shots=300,3150,6930`).

### Tasten

| Taste | Wirkung |
|---|---|
| `P` oder Leertaste | Pause an/aus (jederzeit) |
| `Esc` oder `F2` | Menü „Grafik und Fenster“ auf/zu (jederzeit, auch aus der Pause); **Beenden** über den Knopf „Beenden“ im Menü (nicht im Browser), in der Fahrt „Fahrt beenden“ zurück ins Startmenü |
| `Enter` | im Ziel: zurück ins Startmenü |
| `F3` | Debug-Anzeige an/aus |
| `F11` | Vollbild an/aus (nicht im Browser) |

Physische Tastenposition (gleich auf QWERTZ/QWERTY); definiert in `scenes/main.gd` (`KEY_BINDINGS`).

### Spielzustände

| Zustand (`state`) | Wann | Anzeige |
|---|---|---|
| `riding` – fahren | Bus verbunden, Quelle `connected` und seit dem letzten Abbruch Telemetrie empfangen | – |
| `paused_manual` – pausiert (manuell) | `P`/Leertaste | „Pause“ |
| `paused_connection` – pausiert (Verbindung) | Bridge nicht erreichbar, Quelle `stale`/`disconnected`, noch keine Daten oder Bridge schweigt bei offenem Bus | „Bridge nicht erreichbar … Bridge starten“ bzw. „Verbindung verloren (Rad: stale)“ / „(Bridge sendet seit 4 s nichts)“ |
| `finished` – Ziel erreicht | Ziellinie nach der letzten Runde überfahren oder „Fahrt beenden“ nach mindestens einer vollen Runde (Endzustand der Fahrt, Pause-Taste wirkungslos) | „Ziel erreicht!“ bzw. „Fahrt beendet“ mit Zeit, allen Rundenzeiten, Bestzeit, Ø Kadenz, Ø Tempo; `Enter` zurück ins Menü |
| `menu` – Startmenü | nach dem Start und nach jeder Fahrt | Titelbild mit Menü und Radstatus (HUD aus) |

In jeder Pause steht das Fahrmodell still: Position und Geschwindigkeit bleiben, wie sie waren. Ein
Verbindungsabbruch ist **keine Kadenz 0** (ADR-0004) – der Fahrer rollt nicht aus. Sobald der Bus wieder
verbunden ist, die Quelle `connected` meldet und Telemetrie ankommt, fährt das Spiel von selbst weiter.
Die Verbindungspause hat Vorrang; eine manuelle Pause bleibt über einen Abbruch hinweg bestehen
(kein automatisches Weiterfahren aus der manuellen Pause). Hängt ein Verbindungsaufbau länger als
`connect_timeout_s`, bricht der Bus-Client ihn ab und versucht es neu. Hängt die Bridge bei offenem
WebSocket (kein `stale` mehr von ihr), sichert das Spiel selbst ab: kommt bei `connected` länger als 4 s weder
`status` noch `telemetry` (`BusClient.SILENCE_TIMEOUT_S`; die Bridge meldet `stale` nach 3 s, 1 s Reserve), gilt
die Quelle als `stale` – Pause, keine Kadenz 0; die nächste Telemetrie setzt die Fahrt fort.

### HUD

Eigene Szene `scenes/hud.tscn` (`src/ride_hud.gd`, RideHud); die Hauptszene übergibt pro Frame die Werte.
Schlicht, halbtransparente Panels, Standardschrift der Engine:

- **Oben links – Werte:** Abschnitt (Station des Insel-Rundkurses; nicht bei der Graybox), **Kadenz** groß mit
  Bogenanzeige bis 120 rpm (Wohlfühlbereich 80–100 rpm grün markiert, darunter blau, darüber orange), **Tempo**
  (km/h), **Steigung** (% mit Vorzeichen; Keil und Farbe: bergauf orange, ab 6 % rot, bergab blau, flach weiß),
  **Strecke** (km seit Start), **Zeit** (Fahrzeit, ohne Pausen) und – **nur wenn die Quelle Watt liefert** –
  **Leistung**. Geschätzte Watt (`power_estimated` nicht ausdrücklich `false`) immer mit „~“, z. B. „~142 W“
  (ADR-0004); gemessene ohne.
- **Oben rechts – Minikarte** (`src/hud_minimap.gd`): Insel von oben (Norden oben, aus dem Gelände), Strecke,
  Start/Ziel, Landmarken als gelbe Rauten, Fahrer als Pfeil in Fahrtrichtung.
- **Unten – Runde und Höhenprofil** (`src/hud_profile.gd`): Fortschrittsbalken mit Prozent und Restdistanz, darunter
  das Höhenprofil des Rundkurses mit Abschnittsgrenzen und -namen (Name nur, wenn er in den Abschnitt passt),
  höchstem Punkt und Marker an der Fahrerposition; der gefahrene Teil ist hinterlegt. Mit Ghost rechts neben der
  Restdistanz der **Abstand** zu ihm („Ghost +1.4 s“, siehe Ghost). Im Training darüber die **Trainingszeile**:
  Phase, Zielkadenz, Restzeit der Phase und die nächste Phase; die **Ansage** zum Widerstandsknopf steht groß über
  dem unteren Panel (siehe Training).
- Über dem unteren Panel dezent der `set_grade`-Hinweis, mittig zwischen oben und unten Pause-/Verbindungs-/Ziel-Meldungen.

Layout nur über Anker und Container: passt im schmalen Halbbild-Fenster (960 × 1040) wie in 1920 × 1080 und
1600 × 900, mit und ohne `display/window/stretch/mode="canvas_items"` (geprüft in `tests/test_hud.gd`). Profil und
Karte werden nur beim Start und bei Größenänderung gezeichnet (Inselbild einmal berechnet); pro Frame bewegen sich
nur die Marker. `RideHud.readout()` liefert die sichtbaren Werte als Textzeilen („Kadenz: 90 rpm“, …) für Tests.
Sichtprüfung mit HUD: `view_probe.gd -- --hud` (Beispielwerte: Kadenz 85, Tempo/Steigung/Abschnitt der Strecke,
„~142 W“).

### Debug-Anzeige (`F3`)

Links unter den Werten, zum Prüfen der Latenz (< 200 ms, ADR-0005): **Kadenz roh** (Feld `cadence` der letzten
Telemetrie, wie empfangen – ungerundet), **t_ms** (Bridge-Zeitstempel der letzten Telemetrie), **Letzte
Telemetrie vor** … ms (Zeit seit Empfang der letzten Telemetrie im Spiel; bei 4 Hz Bridge-Takt pendelt sie zwischen 0
und ~250 ms – dauerhaft mehr heißt: Daten stocken; das ist **nicht** die Latenz Kurbel → Bild, die misst man per
Zeitlupe, siehe `docs/anleitung.md`), dazu Bus-Verbindung, Status und Quelle. Prüfen: Kadenz in der
Bridge ändern und schauen, wann „Kadenz roh“ und `t_ms` nachziehen.

### Grafik und Fenster (`Esc` / `F2`)

Das Menü wirkt sofort und speichert jede Änderung in `user://settings.cfg` – unter Windows
`%APPDATA%\Godot\app_userdata\Inselfahrt\settings.cfg` (getrennt von `config.cfg`; Datei löschen = Standardwerte).
Das Spiel läuft weiter, solange das Menü offen ist. Zwei Spalten (#42): links Grafik, rechts Tageszeit, Wetter,
Jahreszeit und Fenster – so passt das Menü in 1280 × 720 und ins Halbbild. Unten „Schließen“, in der Fahrt „Fahrt beenden“ (zurück ins
Startmenü) und „Beenden“ (beendet das Spiel; im Browser ausgeblendet) – `Esc` beendet nicht mehr direkt (#19).

| Option | Auswahl | Standard |
|---|---|---|
| Kantenglättung | Aus, FXAA, MSAA 2×/4×/8×, TAA | MSAA 4× – glättet die Kanten der Low-Poly-Welt scharf und ohne Nachziehen; FXAA macht weich, TAA verschmiert bei Kamerafahrt leicht |
| Render-Auflösung | 50–200 % der Fenstergröße (3D; HUD bleibt scharf) | 100 % |
| Skalierung | Bilinear, AMD FSR 1, AMD FSR 2 (FSR 2 glättet selbst, TAA entfällt dann) | Bilinear |
| VSync | An, Aus | An |
| fps-Limit | Ohne, 30, 60, 120, 144 | Ohne |
| Schatten | Niedrig/Mittel/Hoch (Schattenatlas 2048/4096/8192, Weichzeichnung) | Mittel (wie bisher) |
| Tempo-Effekte | An, Aus – Geschwindigkeitslinien und Sichtfeld-Kick ab 35 km/h (#42) | An |
| Panorama-Momente | An, Aus – Kameraschwenk mit Namen an Sehenswürdigkeiten (#43) | An |
| Tageszeit | Echtzeit (Mallorca), feste Uhrzeit 6:00/9:00/12:00/15:00/18:00/20:30/22:00/0:00, Zeitraffer 12/24/48 min je Tag (startet bei der aktuellen Uhrzeit des Spiels) | wie `config.cfg [sky]` (Echtzeit) |
| Wetter | Wechselnd (meist sonnig), Klar, Leicht bewölkt, Bewölkt, Regen (fest) – sofort, ohne Überblendung | wie `config.cfg [sky]` (Wechselnd) |
| Jahreszeit | Nach Datum (Mallorca), Mandelblüte, Frühling, Sommer, Herbst, Winter (fest) – sofort (#39) | Nach Datum |
| Fenstermodus | Fenster (mit Rahmen, frei skalierbar), Randloses Fenster, Vollbild | Fenster 1600 × 900, mittig |
| Fenstergröße | 960 × 1040, 1280 × 720, 1600 × 900, 1920 × 1080, 2560 × 1440 (im Vollbild: Bildschirmauflösung) | 1600 × 900 |

„Vollbild“ ist randloses Vollbild über den ganzen Bildschirm, kein exklusiver Modus: Alt+Tab zu einer anderen App
geht ohne Umschalten des Bildschirmmodus. Modus, Größe und Position des Fensters werden beim Beenden gemerkt – auch
wenn es von Hand gezogen oder per Windows-Snap verschoben wurde (liegt die Position auf keinem Bildschirm mehr,
startet es mittig).

**Neben einer anderen App (z. B. Musik):** im Menü „Rechte Hälfte“ bzw. „Linke Hälfte“ – das Fenster füllt
diese Hälfte der Arbeitsfläche (ohne Taskleiste) des aktuellen Bildschirms, Rahmen eingerechnet; aus dem Vollbild
geht es dabei zurück ins Fenster. Alternativ wie gewohnt Win+←/→. HUD, Meldungen und Debug-Anzeige bleiben im
schmalen Hochformat lesbar (die Mittelmeldung bricht um), die 3D-Sicht wird nicht verzerrt (vertikaler Blickwinkel
fest, seitlich sieht man entsprechend weniger). Ohne Fokus läuft das Spiel mit voller Bildrate weiter.

Tageszeit, Wetter und Jahreszeit landen erst nach einer Auswahl im Menü als Abschnitt `[sky]` in `settings.cfg`; beim Start
gilt zuerst `config.cfg [sky]`, ein gespeicherter `[sky]`-Abschnitt liegt darüber. Eine Uhrzeit aus `config.cfg`, die
nicht in der Liste steht (z. B. 13:00), zeigt das Menü als zusätzlichen Eintrag.

Im Browser (Web-Export) gibt es keine Fensteroptionen und kein VSync (steuert der Browser); der Compatibility-
Renderer kann nur MSAA und bilineare Skalierung, das Menü bietet dort nur diese an.

### Runden, Ziel und Bestzeit (#31)

Eine Runde startet an der Startposition (Standard: Start/Ziel-Linie) und endet beim nächsten Überfahren der
Start/Ziel-Linie (bei Start mitten auf der Strecke, z. B. in Tests, also früher). Die Fahrt hat die im Menü gewählte
Rundenzahl; das Ziel liegt nach der letzten Runde, *Endlos* hat keins und endet nur über „Fahrt beenden“ oder Beenden.
Das HUD zeigt unten die Runde („Runde 2 / 3“, endlos „Runde 2“, bei einer Runde nur „Runde“) und oben die
**Rundenzeit** neben der Fahrzeit („Zeit“). Im Ziel steht der Fahrer, das Ergebnis zeigt Fahrzeit, alle Rundenzeiten,
die Bestzeit, Ø Kadenz (zeitgewichtet) und Ø Tempo (Strecke/Fahrzeit). „Fahrt beenden“ nach mindestens einer vollen
Runde zeigt erst dieses Ergebnis („Fahrt beendet“), `Enter` führt ins Menü.

**Bestzeit:** schnellste volle Runde je Strecke und Richtung (`cw`/`ccw`); jede Runde zählt,
eine angefangene nicht. Sie steht im Spielstand und im Menü „Rundfahrt“; eine neue Bestzeit blendet das HUD kurz ein
(„Neue Bestzeit! 14:44.7“). Rundenzeiten und Bestzeit rechnet die Rundenwertung (`src/lap_timing.gd`) nur aus
Streckenposition und Fahrzeit – also nur aus Kadenz und Steigung (ADR-0010).

Fahrzeit, Rundenzeiten und Durchschnitte zählen nur Zeit im Zustand `riding` – Pausen nicht; ein Zeitschritt über die
Start/Ziel-Linie wird anteilig aufgeteilt (`src/ride_stats.gd`, `src/lap_timing.gd`).

### Segmente und Medaillen (#33)

Drei **Segmente** je Richtung mit eigener Zeit, je mit blauem Torbogen am Start (Name auf dem Banner):

| Segment | im Uhrzeigersinn (km) | gegen den Uhrzeigersinn (km) | in der Station |
|---|---|---|---|
| Küstenwelle | 0,48–2,24 | 6,97–8,73 | Küstenstraße (die drei Wellen) |
| Bergwertung | 2,34–4,59 | 0,33–3,18 | cw: Serpentinen bis zur Kuppe am Aussichtspunkt; ccw: Osthang bis vor das Bergdorf |
| Dorfsprint | 5,70–6,01 | 3,20–3,51 | Bergdorf |

Segmente sind Daten (`IslandCourse.SEGMENTS`, Start- und Endmeter je Richtung in Fahrtrichtung). Namen und IDs sind
in beiden Richtungen gleich, Bestzeiten und Medaillen stehen je Richtung im Spielstand. Im
Segment steht über dem unteren Panel dessen Name mit Live-Zeit („Bergwertung 3:01.8“), beim Verlassen blendet das HUD das
Ergebnis ein („Bergwertung 7:34.5 · Silber – neue Bestzeit!“). Gewertet wird nur ein ganz durchfahrenes Segment, jede
Runde neu, Ein- und Ausfahrt anteilig wie bei den Runden (`src/segment_timing.gd`, von `LapTiming.advance` mitgeführt).

**Medaillen** (Bronze/Silber/Gold) gibt es für jede Runde und jedes Segment. Die Schwellen sind nicht eingetragen,
sondern aus dem Fahrmodell berechnet (`src/medals.gd`): die Zeit bei konstant **70 rpm** (Bronze), **85 rpm** (Silber)
und **95 rpm** (Gold) – das echte Fahrmodell fährt dazu beim Start einmal eine Runde aus dem Stand über das
Steigungsprofil (≈ 0,2 s, danach zwischengespeichert). Ändern sich Strecke, Segmente oder `[ride]`-Werte, ändern sich die
Schwellen mit. Mit der Spiel-Konfiguration auf der Insel:

| | Gold | Silber | Bronze |
|---|---|---|---|
| Runde | 20:20.2 | 22:43.6 | 27:35.5 |
| Küstenwelle | 3:55.6 | 4:23.3 | 5:19.6 |
| Bergwertung | 6:47.5 | 7:35.5 | 9:13.1 |
| Dorfsprint | 0:37.2 | 0:41.5 | 0:50.4 |

Eine verkürzte erste Runde (Start nicht an der Start/Ziel-Linie, nur in Tests) bekommt keine Medaille. Das Ergebnis zeigt
die Medaille je Runde („Medaillen: Silber · Gold“, ab 6 Runden gezählt: „12× Gold · 8× Silber“) und je Segment die
schnellste Zeit der Fahrt mit Medaille. Eine laufende Einblendung wird im Ziel ausgeblendet. Segment-
Bestzeiten und beste Medaillen gehen wie die Bestzeit am Fahrtende in den Spielstand. Auch hier zählen nur Kadenz und
Steigung (ADR-0010).

### Ghost (#32)

Auf der Seite „Rundfahrt“ lässt sich ein **Ghost** zuschalten: ein halbtransparenter, hellblau getönter Mitfahrer
(Kopie des Fahrermodells, ohne Schatten), 1,3 m links neben der Fahrlinie, der eine frühere Runde nachfährt.

- **Bestzeit** (Standard, sobald es sie gibt): die Runde der Bestzeit je Strecke und Richtung. Sie wird gespeichert,
  wenn eine Fahrt die Bestzeit unterbietet; innerhalb einer Fahrt bleibt der gewählte Ghost derselbe.
- **Letzte Fahrt:** die letzte volle Runde der zuletzt gespeicherten Fahrt, die mindestens eine volle Runde hatte
  (eine abgebrochene Fahrt ohne volle Runde ändert ihn nicht).
- Ohne Aufzeichnung ist der Eintrag ausgegraut und es bleibt bei „Aus“.

Der Ghost fährt **jede Runde ab ihrem Start neu** mit, auch bei mehreren Runden und endlos; ist man langsamer als er,
fährt er nach seinem Rundenende seine Runde von vorn weiter, bis man selbst die Linie überquert. In Pausen steht er.
Er wirkt nicht auf die eigene Fahrt (ADR-0010).

**Abstand im HUD:** in Sekunden mit einer Nachkommastelle, berechnet über die Zeit: an der eigenen Position die eigene
Rundenzeit minus die Zeit, zu der der Ghost dieselbe Position erreichte. **Positiv = hinter dem Ghost** („+1.4 s“, rot),
**negativ = vor ihm** („-0.8 s“, grün), gleichauf „0.0 s“. Im Ziel steht der Unterschied der Rundenzeiten.

**Gespeichert** wird nur „Strecke über Zeit“ (ADR-0008 Nachtrag, keine Rohtelemetrie): die Position in der Runde
jede Sekunde (`distance_m`, auf 1 cm), dazu Rundenlänge und Rundenzeit; abgespielt wird linear dazwischen. Eine Runde
von ~15 min sind rund 900 Zahlen. Aufgezeichnet werden nur volle Runden (Beginn an der Start/Ziel-Linie); das macht
die Rundenwertung (`LapTiming.best_ghost`/`last_ghost`), Logik in `src/ghost.gd`. Für spätere Pakete (Panorama-Momente
nicht mit Ghost, #43) fragt man `ghost_active()` der Hauptszene ab.

### Erfolge, Fahrerlevel und Fahrtenbuch (#35)

**Erfolge** (`src/achievements.gd`): 27 einmalige Meilensteine in sechs Kategorien – Strecke (1/10/100/500/1000 km
gesamt, 20/50 km in einer Fahrt), Rundenzahl (1/10/50 gesamt, 3/10 in einer Fahrt), Tageszeit (5–8, 12–15, 18–21,
22–5 Uhr Ortszeit), Wetter (je Zustand), Jahreszeit und Training. Jeder Erfolg ist nur Daten (Name, Text, Ereignis,
Bedingung); ausgewertet werden **Ereignisse der Fahrt**: je volle Runde `lap`, je voller Kilometer (gesamt) `distance`,
`weather`, `time_of_day` und `season` (#39; die Mandelblüte zählt als Frühling); am Trainingsende
`training_finished` (#37). Ein neuer Erfolg blendet im HUD ein („Erfolg: Regenfahrer – Im
Regen gefahren“); mehrere Einblendungen (Bestzeit, Segment, Erfolg, Level) laufen nacheinander statt sich zu
überschreiben. Am Fahrtende prüft das Spiel Strecke und Runden gesamt noch einmal – ein Spielstand von vor #35 holt so
nach, was er schon erfüllt. Das Ergebnis nennt die neuen Erfolge und das neue Level in der Kopfzeile.

**Fahrerlevel** (`src/driver_level.gd`): folgt allein aus den Kilometern aller Fahrten in jedem Modus (nicht
gespeichert, aus den Fahrten abgeleitet). Level 2 ab 10 km, jeder weitere Schritt 5 km länger (3 ab 25 km, 5 ab 70 km,
10 ab 270 km, 20 ab 1045 km), höchstens 50. Ein Aufstieg blendet ein („Fahrerlevel 3 erreicht!“). Es schaltet **nur
Kosmetik** frei (`DriverLevel.unlock_level(teil)` für die Garderobe, #36) und wirkt nicht auf Fahrmodell, Rundenzeit,
Bestzeit oder Medaille (ADR-0010).

**Garderobe** (`scenes/wardrobe.gd`, Teile und Auswahl in `src/wardrobe.gd`, aus dem Startmenü): links eine Vorschau
(der Fahrer dreht sich langsam auf dem Rad und tritt), rechts je **Trikot**, **Radfarbe** und **Helm** sechs Teile –
Farbvarianten am vorhandenen Fahrermodell, keine neuen Dateien. Je Kategorie ist der bisherige Look ab Level 1 frei
(Inselblau, Rennrot, weißer Helm), die übrigen kommen über die Levelkurve bis Level 20 dazu; gesperrte Teile sind
ausgegraut und zeigen, ab welchem Level sie frei werden („Nachtschwarz · ab Level 15“). Ein Klick (oder Enter/Leertaste)
wählt das Teil: der Fahrer trägt es sofort in der Vorschau und in der Fahrt, der Spielstand wird gleich gespeichert
(`wardrobe`: Kategorie → Teil, Format weiter Version 1). Der Ghost-Mitfahrer bleibt im aufgehellten Standard-Look, damit
er vom eigenen Fahrer unterscheidbar ist. Nur Kosmetik (ADR-0010, `tests/test_wardrobe.gd`). Bedienung: Pfeiltasten/Tab
zwischen den Teilen, `Esc` oder „Zurück“ schließt; passt in 960 × 1040, 1920 × 1080 und 1152 × 648 (was nicht passt,
scrollt). Sichtprüfung: `view_probe.gd -- --title --wardrobe=trikot_gelb,radfarbe_blau,helm_schwarz` speichert
`wardrobe.png`; ohne `--title` trägt der Fahrer die Teile in `--shots`/`--close`.

**Fahrtenbuch** (`scenes/logbook.gd`, aus dem Startmenü): drei Seiten – *Übersicht* (Strecke, Zeit, Fahrten, Runden,
Fahrerlevel mit Rest bis zum nächsten; Bestzeiten je Strecke und Richtung; Segmentzeiten; beste Medaille je Runde und
Segment), *Erfolge* (alle nach Kategorie, freigeschaltete mit Datum, gesperrte blass) und *Fahrten* (die letzten 20,
neueste zuerst). Bedienung: Seitenknöpfe mit Pfeil links/rechts oder Maus, Pfeil hoch/runter, Bild auf/ab, Pos1/Ende
oder Mausrad scrollen, `Esc` oder „Zurück“ schließt. Passt in 960 × 1040, 1920 × 1080 und 1152 × 648
(`tests/test_logbook.gd`).

Sichtprüfung: `view_probe.gd -- --title --logbook` (Beispielstand nur im Speicher) speichert `logbook_overview.png`,
`logbook_achievements.png` und `logbook_rides.png`; `--hud --rewards --shots=1200` die Einblendungen `achievement.png`
und `level_up.png`.

### Training (#37)

**Fahren → Training** führt durch eine angeleitete **Einheit**. Die Einheiten sind Dateien in `trainings/` (JSON, je
Datei eine; eigene Einheiten entstehen nur als Datei): Name, Beschreibung und Phasen mit Art (Aufwärmen, Hauptteil,
Erholung, Ausrollen), Dauer, **Zielkadenz** (Bereich in rpm) und **Ansage** zum Widerstandsknopf; `repeat`
wiederholt einen Block. Dabei sind:

| Einheit | Aufbau | Dauer |
|---|---|---|
| **Intervalle kurz** | 8 min Aufwärmen, 10 × 30 s hart (95–105 rpm) / 30 s locker (80–90 rpm), 5 min Ausrollen | 23 min |
| **Pyramide** | 8 min Aufwärmen, je 3 min bei 70 → 80 → 90 → 100 → 90 → 80 → 70 rpm (± 3), 5 min Ausrollen | 34 min |
| **Tempo-Blöcke** | 6 min Aufwärmen, 3 × 8 min bei 85–90 rpm mit je 3 min Erholung, 4 min Ausrollen | 40 min |

Die Insel läuft dabei **endlos**. Das HUD zeigt Phase, Zielkadenz, Restzeit und die nächste Phase. Der Widerstand ist
manuell – das Spiel kennt die Knopfstellung nicht –, die Ansage ist eine Empfehlung: 10 s vor dem Wechsel als
Vorankündigung („In 8 s: Widerstand 2 Stufen hoch, 100 rpm halten“), dann noch 5 s nach dem Wechsel. Bewertet wird
allein, **wie lange die Kadenz im Zielbereich lag** (ADR-0010) – je Phase und gesamt (nach Zeit gewichtet). Nach dem
Ausrollen endet die Fahrt mit dem Ergebnis („Zielkadenz getroffen: 87 %“ und je Phase, Wiederholungen
zusammengefasst); „Fahrt beenden“ vorher zeigt die Teilbewertung der gefahrenen Phasen.

Runden im Training zählen **nicht** für Bestzeit, Medaillen, Segmentzeiten und Ghost (die Vorgabe wechselt, die
Runden wären nicht vergleichbar); die Kilometer zählen fürs Fahrerlevel. Ein zu Ende gefahrenes Training meldet
`training_finished` an die Erfolge (*Erste Einheit*, *Trainingsfleiß*, *Punktlandung* ab 90 %). Im Spielstand steht
die Fahrt im Modus `training` mit Name und Gesamtbewertung der Einheit (`training`, `training_score`); das
Fahrtenbuch zeigt sie als „Training“. Logik in `src/training.gd` (Training, ohne Szene und Bus); spätere Pakete
(keine Panorama-Momente im Training, #43) fragen `training_active()` der Hauptszene ab.

Sichtprüfung: `view_probe.gd -- --title --training` speichert `title_training.png`, `--hud --training --shots=1200`
die Trainingszeile mit Ansage (`training.png`) und das Ergebnis (`training_result.png`).

### Virtuelle Steigung (`set_grade`)

Das Spiel meldet die Steigung an der Fahrerposition per `{"v": 0, "type": "set_grade", "grade": 0.06}`
(Anteil, ADR-0007; Logik in `src/grade_reporter.gd`):

- gleich nach dem Verbinden (sobald gefahren wird) den aktuellen Wert,
- danach nur bei Änderung um mindestens 0,5 Prozentpunkte (0.005) und höchstens 2-mal pro Sekunde –
  eine gedrosselte Änderung wird mit dem dann aktuellen Wert nachgeholt,
- Endwert: weicht der gemeldete Wert (unter der Schwelle) ab und hat sich die Steigung 1 s lang nicht um
  0,5 Prozentpunkte bewegt, wird der aktuelle Wert einmal nachgesendet (danach erst wieder nach einer neuen
  Bewegung über die Schwelle) – so bleibt am Ende einer Rampe nicht ein bis zu 0,5 Prozentpunkte alter Wert stehen,
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
| `[camera] behind_m` | `5.5` | Kamera: Abstand hinter dem Fahrer entlang der Strecke (m) – kleiner = Fahrer größer im Bild |
| `[camera] height_m` | `2.4` | Kamerahöhe über der Strecke (m); mindestens 1,5 m über dem Gelände |
| `[camera] look_ahead_m` | `10.0` | Blickpunkt so viele Meter voraus auf der Strecke |
| `[camera] look_height_m` | `1.2` | Höhe des Blickpunkts über der Strecke (m) |
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
  `quit_on_request = false` – „Beenden“ im Menü meldet dann nur `quit_requested`, statt den Testlauf zu beenden.

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
config.cfg              Bus-Adresse, Fahrmodell-Parameter, Strecke, Kamera, Tageszeit und Wetter
scenes/main.tscn/.gd    Hauptszene: Strecke laut Konfiguration, Bus-Client → Fahrmodell → Fahrer auf dem Pfad, Kamera, Spielzustände, Tasten, HUD
scenes/hud.tscn         HUD-Szene (RideHud): Werte-Panel, Minikarte, Rundenfortschritt, Höhenprofil, Meldungen
src/ride_hud.gd         RideHud: Anzeige der Werte, Rundenfortschritt, readout(); Layout von Hinweis/Debug
src/hud_gauge.gd        HudGauge: Kadenz-Bogen · src/hud_grade_icon.gd HudGradeIcon: Steigungskeil
src/hud_profile.gd      HudProfile: Höhenprofil mit Marker (profile_point() als reine Rechnung)
src/hud_minimap.gd      HudMinimap: Inselkarte mit Strecke, Landmarken, Fahrer-Pfeil (map_point() als reine Rechnung)
src/bus_client.gd       BusClient: verbinden/reconnecten (mit Verbindungs-Timeout), status/telemetry parsen, send_message
src/ride_stats.gd       RideStats: Fahrzeit, Strecke, Ø Kadenz, Ø Tempo (ohne Pausen) – reine Logik
src/lap_timing.gd       LapTiming: Rundenwertung – Rundenzeiten, Ziel nach n Runden oder endlos, Bestzeit, Ghost-Aufzeichnung – reine Logik
src/segment_timing.gd   SegmentTiming: Segmentzeiten (Live-Zeit, gewertete Segmente, Segment-Bestzeit) – reine Logik
src/ghost.gd            Ghost: Runde als Strecke über Zeit – aufzeichnen, abspielen, Abstand in s – reine Logik
src/training.gd         Training: Einheit laden, Ablauf (Phase, Restzeit, Ansage), Bewertung der Zielkadenz – reine Logik
trainings/              Trainingseinheiten als Dateien (JSON): Intervalle kurz, Pyramide, Tempo-Blöcke
src/medals.gd           Medals: Medaillen-Schwellen aus dem Fahrmodell (70/85/95 rpm), Medaille einer Zeit – reine Logik
src/grade_reporter.gd   GradeReporter: wann `set_grade` gesendet wird (Schwelle, Drosselung) – reine Logik
src/ride_model.gd       RideModel: reine Logik (Kadenz, Steigung, Δt, Konfig → Geschwindigkeit, Position)
src/rider_motion.gd     RiderMotion: Kurbel-/Radwinkel, Schräglage, Vorbeuge, Glieder-IK – reine Logik
src/rider_model.gd      RiderModel: Fahrer und Rennrad aus Grundkörpern, Pose aus RiderMotion
src/ride_config.gd      RideConfig: liest config.cfg
src/graphics_settings.gd GraphicsSettings: Grafik-/Fenstereinstellungen, Tageszeit/Wetter (user://settings.cfg), Anwenden, Fensterhälften
scenes/settings_menu.*  Menü „Grafik und Fenster“ (F2, F11), von der Hauptszene eingehängt
scenes/start_menu.*     Startmenü: Titel, Fahren/Fahrtenbuch/Garderobe/Einstellungen/Beenden, Rundfahrt- und Training-Auswahl, Radstatus (#30, #31, #37)
scenes/wardrobe.gd      Garderobe: Trikot, Radfarbe, Helm mit Vorschau (SubViewport), gesperrte mit Level (#36)
src/wardrobe.gd         Wardrobe: Teile und Farben, Auswahl prüfen und wählen, Standard je Kategorie – reine Logik
src/save_game.gd        SaveGame: Spielstand (user://savegame.json) – versioniert, Profilschlüssel, Fahrten, Bestzeiten, Segment-Bestzeiten, Medaillen, Ghosts, Erfolge, Garderobe, Hochstufung
src/track.gd            Track (Path3D): length_m(), grade_at(distanz), position_at(distanz), stations, station_at(), road_mesh(); Richtung (#34): set_direction(), path_distance(), ride_position_at(), ride_stations()
src/island_course.gd    IslandCourse: Insel-Rundkurs – Grundriss, Höhenprofil, Stationen, Segmente (reine Daten/Logik)
src/island_terrain.gd   IslandTerrain: Höhenfeld (prozedural oder Höhenkarte), unter die Straße geformt, Mesh
src/island_world.gd     IslandWorld: Gelände, Meer, Fahrbahn, Stationsmarker, Deko aller Stationen mit Modellen (#15, #16)
src/island_landmarks.gd IslandLandmarks: Sehenswürdigkeiten und Kleindetails (G2), Platzierungsdaten für Tests
src/island_vegetation.gd IslandVegetation: Gras, Unterholz, Sträucher, Bodentexturen, Farbpalette (#38); Mohn, Mandelbäume, Felder (#39)
src/world_motion.gd     WorldMotion: bewegte Szenen und Effekte (G3) – Mühlen, Leuchtturm, Boote, Vögel, Wolken, Brunnen
src/day_night.gd        DayNight: Uhr (Mallorca-Ortszeit, Modi), Sonnenstand, Auf-/Untergang – reine Logik
src/season.gd           Season: Jahreszeit aus dem Datum (Mallorca), Farben je Jahreszeit – reine Logik (#39)
src/weather.gd          Weather: simuliertes Wetter, Zustände und Übergänge – reine Logik
src/sky_controller.gd   SkyController: Sonne, Mond, Himmel, Environment, Regen, Sterne, Web-Lichtprofil (G6); Farbstimmung, Höhennebel (#42)
src/night_lights.gd     NightLights: Laternen, Leuchtfeuer, Fahrradlicht bei Nacht
src/speed_effects.gd    SpeedEffects: Geschwindigkeitslinien und Sichtfeld-Kick ab 35 km/h, abschaltbar (#42)
src/shaders/            Wind (Vegetation), Meer (Wellen, Flachwasser, Brandung), Lichtkegel, Leuchtpunkte, Geschwindigkeitslinien
src/graybox_track.gd    GrayboxTrack: Rundkurs ~900 m, flach → +6 % → Kuppe → −6 % → flach (`[world] track="graybox"`)
tests/                  GUT-Tests, support/ (Fake-Bus, Basisklasse, Hook), fixtures/
tools/                  E2E-Prüfhilfe gegen die echte Bridge, Sichtprüfung/fps (view_probe.gd), Fenstermodi (window_probe.gd)
addons/gut/             GUT 9.4.0 (MIT, Lizenz in addons/gut/LICENSE.md)
assets/kenney/          Low-Poly-Modelle (CC0) für alle Stationen
icon.svg / icon.ico     VSpin-Symbol (Faltband mit Schattenfalte): Projekt-, Fenster- und Browser-Symbol; .ico für Windows
ASSETS.md               Asset-Nachweis und Lizenzregel
```

Noch nicht enthalten: Terrain3D (ADR-0006 Nachtrag).
