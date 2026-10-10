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
- Kamera (`scenes/main.gd`): sitzt hinter dem Fahrer **auf der Strecke** (schwenkt in Kehren nicht seitlich
  aus), blickt 10 m voraus, beides exponentiell geglättet (0,45 s), mindestens 1,5 m über dem Gelände; vor G5
  9 m / 3,5 m / 14 m. **Drei Perspektiven** (#59, `src/camera_views.gd`): *Nah* 3,5 m hinter / 1,8 m hoch (Fahrer groß
  im Bild), *Verfolger* 4,5 m / 2,1 m (Standard) und *Weit* 5,5 m / 2,4 m (für die Landschaft). Taste `C` blättert
  während der Fahrt der Reihe nach durch (Name kurz im HUD), dasselbe im Grafikmenü (*Kamera*). Die Wahl steht im
  Spielstand (`camera`: `{"view": "nah"|…}`, Format weiter Version 1) und gilt in Rundfahrt und Training, in
  beiden Richtungen; Intro und Panorama laufen in sie zurück, der Sichtfeld-Kick wirkt in allen drei. Nur
  Darstellung (ADR-0010). `config.cfg [camera]`: `behind_m` und `height_m` sind die Perspektive *Weit* (eine
  bestehende Konfiguration wirkt dort weiter), `look_ahead_m` und `look_height_m` gelten für alle drei.
  Sichtprüfung: `view_probe.gd -- --view=nah|verfolger|weit` (mit `--hud` samt Namenseinblendung).
  Beim Fahrtstart ein **Kamera-Intro** (#42, siehe „Farbstimmung, Höhennebel und Tempo“), an Sehenswürdigkeiten
  **Panorama-Momente** (#43, ebenda).
- HUD zeigt zusätzlich den aktuellen Abschnitt, Höhenprofil und Minikarte der Insel (siehe HUD).

Weltaufbau beim Start ca. 0,6 s (mit der Vegetation aus #38 ca. 1,1 s), beim allerersten Start (oder nach Änderung
an Gelände/Rundkurs) ca. 1,8 s
(headless gemessen, #19). Das Gelände (Höhen, Straßenabstand) liegt als Cache in `user://terrain_cache.bin`
(~1 MB; unter Windows `%APPDATA%\Godot\app_userdata\Inselfahrt\`; Tests und Prüfhilfen: eigener Cache
unter `.godot/test_user/<n>/`); Schlüssel ist ein SHA-256 über den Quelltext von
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
- Aussehen: `wear(outfit)` färbt Trikot (mit Brustband), Rahmen und Helm (mit Streifen) für die Garderobe (#36); im
  Arcade zusätzlich Felgen, Schuhe und den **Talisman** – eine leuchtende Raute an einer Schnur hinten am Sattel, nur
  sichtbar, solange ein Talisman angelegt ist (#49, siehe „Beute und Ausrüstung“). `reset_look()` stellt vor jedem
  Anziehen den gebauten Grund-Look her.
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
   `sessions_dir`, beim Simulator die Start-Kadenz `sim_cadence`, Standard 80 rpm – unter `pythonw` gibt es keine
   Pfeiltasten; relative Pfade ab dem Spielordner). Beim Schließen (Fenster, „Beenden“) beendet es nur diese eigene
   Bridge, sauber über die Stoppdatei (`--stop-file`, Session vollständig); erst wenn sie nach 5 s noch läuft, hart.
   Endet das Spiel ohne Stoppdatei (Absturz, „Stop“ im Editor), beendet sich die Bridge selbst (`--parent-pid`).
   Eine schon laufende Bridge wird nur mitbenutzt und nie beendet. Radstatus dabei: „Bridge nicht erreichbar – Bridge
   wird gestartet (Quelle sim) …“, „… – Bridge-Programm fehlt (config.cfg [bridge] program)“ oder „… – Bridge-Start
   gescheitert“. Im Web-Export und in Tests/Prüfhilfen (Bus nicht auf 8765 bzw. `autostart` aus) startet nichts.
3. Im Startmenü **Fahren → Rundfahrt** wählen, Rundenzahl und Tageszeit einstellen, **Losfahren** – oder
   **Fahren → Training**, Einheit wählen, **Losfahren** – oder **Fahren → Arcade**, Stufe und Kadenzbereich wählen,
   **Losfahren**.

### Startmenü und Spielstand (#30)

Nach dem Start erscheint das **Titelbild**: die Kamera fliegt langsam hoch über dem Rundkurs (38 m über der Straße,
9 m/s, mindestens 22 m über dem Gelände) über die lebende Insel – Tageszeit, Wetter, Bewegung wie in der Fahrt; HUD
und Fahrer sind ausgeblendet. Darüber das Menü (`scenes/start_menu.gd`, per Maus oder Tastatur: Pfeiltasten/Tab,
Enter/Leertaste):

| Punkt | Wirkung |
|---|---|
| **Fahren** | Modus-Auswahl: **Rundfahrt**, **Training**, **Arcade**, „Zurück“ |
| **Fahren → Rundfahrt** | **Runden** 1–20 oder *Endlos* (Standard 1), **Richtung** (*Im Uhrzeigersinn*, *Gegen den Uhrzeigersinn*, #34), **Tageszeit** (dieselbe Auswahl wie im Einstellungsmenü, Standard *Echtzeit*; wirkt und bleibt wie dort gewählt), **Ghost** (*Aus*, *Bestzeit*, *Letzte Fahrt*; ohne Aufzeichnung ausgegraut, Standard *Bestzeit*, sobald es sie gibt, #32), die **Bestzeit** der Strecke in der gewählten Richtung; **Losfahren** startet die Fahrt (#31) |
| **Fahren → Training** | **Einheit** (*Intervalle kurz*, *Pyramide*, *Tempo-Blöcke*) mit Beschreibung und Dauer; **Losfahren** startet das Training (#37, siehe unten) |
| **Fahren → Arcade** | **Stufe** (*Stufe 1–6*; 1–3 von Anfang an, höhere ausgegraut, bis sie freigeschaltet sind – die nächste zeigt den Stand, z. B. „Stufe 4 (gesperrt – Bosse auf Stufe 3: 2/3)“, #54) mit Beschreibung, persönlicher **Kadenzbereich** (von 40–80 bis 100–150 rpm, Standard 60–120 rpm), die **Bestpunktzahl** der Stufe, das **Arcade-Level** (#53) und die eigene gegen die **Empfohlene Stärke** der Stufe („Stärke 21 / empfohlen 35“, grün ab der Empfehlung, sonst gelb – eine Empfehlung, keine Sperre, #54); **Losfahren** startet den Arcade-Lauf (#46, siehe unten), **Ausrüstung** öffnet das Inventar der Beute (#49, siehe „Beute und Ausrüstung“), **Talente** den Talentbaum (#53, siehe „Talente“; der Knopf zeigt die freien Talentpunkte, z. B. „Talente (2)“). Stufe und Kadenzbereich werden bei jeder Änderung gespeichert |
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
`finished`, Runden (volle), Dauer, Strecke in km, Ø Kadenz, Ø Tempo, Rundenzeiten (`lap_times_s`), Richtung
(`direction`) und je Segment die beste Zeit dieser Fahrt (`segment_times_s`, Nacharbeit #26). Keine Rohtelemetrie
(die steht in der Session-CSV der Bridge). Bestzeiten stehen je Profil unter `best_times` (Strecke → Richtung →
Sekunden, z. B. `{"island": {"cw": 873.4}}`), Segment-Bestzeiten unter `segment_best_times` und die beste Medaille je Runde
(`lap`) und Segment unter `medals` (Strecke → Richtung → Segment-ID, #33), die Ghosts unter `ghosts` (Strecke → Richtung →
`best`/`last`, je nur `lap_length_m`, `sample_s`, `time_s` und `distance_m`, #32), die freigeschalteten Erfolge unter
`achievements` (Erfolg-ID → Datum, #35), Arcade unter `arcade` (Kadenzbereich `cadence_range`, gewählte Stufe `tier`,
beste Punktzahl je Stufe `best_points`, #46; Stufen #54: höchste wählbare Stufe `unlocked` – fehlt sie, gelten die drei
Startstufen – und je Stufe die dort besiegten Bosse `defeated`, z. B. `{"3": ["tramuntana", "drac"]}`; Beute #49: Inventar
`inventory` – je Teil `id`, `slot`, `rarity`, `stats`,
`effect` (bei legendären Teilen der Spezialeffekt, #53, sonst leer) –, angelegte Teile `equipped` (Platz → `id`), Splitter
`shards` und die nächste freie `next_item_id`; Talente #53: `points_total` (Summe der Punkte aller gespeicherten
Arcade-Fahrten, daraus das Arcade-Level) und `talents` (erlernte Knoten in der Reihenfolge des Erlernens); eine
Arcade-Fahrt trägt zusätzlich `arcade` mit Stufe, Punkten, geschafften und verfehlten Herausforderungen). Spätere Bereiche
kommen additiv dazu – so auch `arcade`, die Formatversion bleibt 1; ältere
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
| `C` | Kameraperspektive wechseln: Nah → Verfolger → Weit (in der Fahrt, nicht bei offenem Menü; #59) |
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
  Phase, Zielkadenz, Restzeit der Phase und die nächste Phase, darunter der **Zonenbalken** (#58); die **Ansage** zum
  Widerstandsknopf steht groß über dem unteren Panel (siehe Training). Im Arcade an derselben Stelle die
  **Arcade-Zeile** (Herausforderung, Ziel, Restzeit bzw. Meter bis zum Start, Punkte) und während einer Herausforderung
  der Zonenbalken mit dem **Fortschritt**, beim Durchbruch dem **Balken**, bei der Jagd dem **Abstand** (siehe Arcade).
- Über dem unteren Panel dezent der `set_grade`-Hinweis, mittig zwischen oben und unten Pause-/Verbindungs-/Ziel-Meldungen.

Layout nur über Anker und Container: passt im schmalen Halbbild-Fenster (960 × 1040) wie in 1920 × 1080 und
1600 × 900, mit und ohne `display/window/stretch/mode="canvas_items"` (geprüft in `tests/test_hud.gd`). In niedrigen
Fenstern skalieren Ansage und Meldung mit der Fensterhöhe (Höhe/1080, mindestens 60 %), ein langes Ergebnis wird so
weit verkleinert, dass es zwischen die Panels passt; unter 760 px Höhe (z. B. 1280 × 720, 1152 × 648) werden die Panels
zu Leisten – oben die Werte in einer Zeile ohne Minikarte, unten ohne Höhenprofil. Nichts überdeckt dann ein Panel. Profil und
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
„Kadenz roh“ ist hier das Feld `cadence` wie empfangen (geglättet, nur ungerundet) – nicht das Bus-Feld
`cadence_raw` (ungeglättet, nur für die Kadenzmuster, #45).

### Grafik und Fenster (`Esc` / `F2`)

Das Menü wirkt sofort und speichert jede Änderung in `user://settings.cfg` – unter Windows
`%APPDATA%\Godot\app_userdata\Inselfahrt\settings.cfg` (getrennt von `config.cfg`; Datei löschen = Standardwerte).
Das Spiel läuft weiter, solange das Menü offen ist. Zwei Spalten (#42): links Grafik, rechts Tageszeit, Wetter,
Jahreszeit, Ton und Fenster – so passt das Menü in 1280 × 720 und ins Halbbild. Unten „Schließen“, in der Fahrt „Fahrt beenden“ (zurück ins
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
| Kamera | Nah, Verfolger, Weit – wie Taste `C`; steht im Spielstand, nicht in `settings.cfg` (#59) | Verfolger |
| Tageszeit | Echtzeit (Mallorca), feste Uhrzeit 6:00/9:00/12:00/15:00/18:00/20:30/22:00/0:00, Zeitraffer 12/24/48 min je Tag (startet bei der aktuellen Uhrzeit des Spiels) | wie `config.cfg [sky]` (Echtzeit) |
| Wetter | Wechselnd (meist sonnig), Klar, Leicht bewölkt, Bewölkt, Regen (fest) – sofort, ohne Überblendung | wie `config.cfg [sky]` (Wechselnd) |
| Jahreszeit | Nach Datum (Mallorca), Mandelblüte, Frühling, Sommer, Herbst, Winter (fest) – sofort (#39) | Nach Datum |
| Ton | An, Aus – alle Klänge des Spiels (#44) | An |
| Lautstärke | 10, 20, 30, 50, 70, 100 % – eigener Audio-Bus „Spiel“, Musik nebenher bleibt hörbar | 30 % (leise) |
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
neueste zuerst, darunter die Segmentzeiten je Fahrt). Bedienung: Seitenknöpfe mit Pfeil links/rechts oder Maus, Pfeil hoch/runter, Bild auf/ab, Pos1/Ende
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

**Zielkadenzbereich und Intervall-Tore (#58):** Unter der Trainingszeile zeigt der **Zonenbalken** den Zielbereich der
Phase mit der Kadenz als Marke – in Farbe *und* Form: darunter blau mit Pfeil hoch, im Bereich grün mit Haken, darüber
orange mit Pfeil runter, daneben in Worten („zu niedrig“, „im Bereich“, „zu hoch“) und der **Treffer** der laufenden
Phase (die Bewertung oben). Vor jeder Belastung steht ein grünes **Starttor** („Start 95–105 rpm“) auf der Strecke, an
ihrem Ende ein orange-weiß kariertes **Zieltor** („Ziel“); Aufwärmen, Erholung und Ausrollen allein bekommen keine.
Das Training läuft nach Zeit: Das nächste Tor steht, wo der Fahrer beim aktuellen Tempo zum Phasenwechsel ankommt, und
wird nachgeführt, bis es höchstens 40 m und 10 s voraus ist; dann steht es fest. So fallen Durchfahrt und Wechsel auf
etwa eine Sekunde zusammen, solange sich das Tempo auf den letzten Metern nicht stark ändert. Im Stand oder beim
Anfahren bleibt ein nahes, noch nicht festes Tor verborgen. Beides ist nur Anzeige (ADR-0010). Bausteine für Epic 4:
`src/zone_bar.gd` (ZoneBar), `src/gate_placement.gd` (GatePlacement), `src/course_gate.gd` (CourseGate).

Sichtprüfung: `view_probe.gd -- --title --training` speichert `title_training.png`, `--hud --training --shots=1200`
die Trainingszeile mit Ansage (`training.png`), Starttor (`gate_start.png`), Zonenbalken unter, im und über dem Bereich
(`zone_below.png`, `zone_inside.png`, `zone_above.png`), Zieltor (`gate_finish.png`) und das Ergebnis
(`training_result.png`).

### Arcade (#46)

**Fahren → Arcade** startet einen **Arcade-Lauf** auf der gewählten **Stufe**: endlos (beliebig viele Runden), im
Uhrzeigersinn, ohne Ghost. Je Runde und Abschnitt (Station des Rundkurses; auf der Graybox ist die ganze Runde ein
Abschnitt) würfelt der Lauf 1–2 **Herausforderungen** – jede Runde neu, die nächste Runde schon beim Einfahren in die
laufende. Die erste eines Abschnitts beginnt 50 m hinter seinem Anfang, eine zweite in der Mitte des Rests; läuft dort
noch eine, beginnt sie direkt danach, solange ihr Abschnitt nicht verlassen ist (sonst verfällt sie ungespielt).

| Stufe | Zielzone | Dauer | Bosse (Dauer zusätzlich) | Punkte | Beute-Qualität | Empfohlene Stärke | frei |
|---|---|---|---|---|---|---|---|
| Stufe 1 | 20 rpm breit | × 1 | × 1 | × 1 | × 1 | 0 | von Anfang an |
| Stufe 2 | 14 rpm | × 1,25 | × 1 | × 2 | × 1,25 | 10 | von Anfang an |
| Stufe 3 | 10 rpm | × 1,5 | × 1 | × 3 | × 1,5 | 20 | von Anfang an |
| Stufe 4 | 9 rpm | × 1,6 | × 1,1 | × 4 | × 1,8 | 35 | Stufe 3 abgeschlossen |
| Stufe 5 | 8 rpm | × 1,7 | × 1,2 | × 5 | × 2,2 | 50 | Stufe 4 abgeschlossen |
| Stufe 6 | 7 rpm | × 1,8 | × 1,3 | × 6 | × 2,7 | 70 | Stufe 5 abgeschlossen |

**Stufen, Freischalten und Empfohlene Stärke (#54):** Stufen sind Daten wie Diablos Qualstufen (`src/arcade_tiers.gd`):
engere Zielzonen, längere Herausforderungen, zähere Bosse (jede Boss-Phase hält und läuft zusätzlich × Boss-Faktor, ihr
Zeitfenster wächst mit), mehr Punkte und eine höhere Grundqualität der Beute (`ArcadeRun.loot_quality`, multipliziert sich
mit der Beute-Qualität von Bossen und Elite-Gruppen; öfter seltene Teile). Schwellen steigen wie bisher um die halbe
Differenz zur Zonenbreite von Stufe 1, auf ganze rpm gerundet (Stufe 4 und 5 +6 rpm, Stufe 6 +7 rpm; *Zugbrücke* 114 / 114 /
115 rpm, *Spurt* 117 / 117 / 118 rpm). Stufe 1–3 sind von Anfang an wählbar und bleiben, wie sie waren. Eine Stufe
ist **abgeschlossen**, wenn auf ihr jeder Boss des Rundkurses (Tramuntana, Drac de na Coca, Dimonis) mindestens einmal
besiegt wurde – über beliebig viele Läufe gesammelt, gespeichert mit dem Fahrteintrag. Der Abschluss der **höchsten freien**
Stufe schaltet die nächste frei; der Abschluss einer niedrigeren schaltet nichts frei. Die Zusammenfassung nennt „Stufe 4
freigeschaltet!“ bzw. auf der höchsten freien Stufe den Stand („Für Stufe 4: 2/3 Bosse auf Stufe 3 besiegt“). Die
**Empfohlene Stärke** jeder Stufe steht auf der Seite „Arcade“ neben der eigenen: Stärke = 4 je rpm Zonenbreite + 1 je %
Fortschritt aus angelegter Ausrüstung und Talenten, je Wert gedeckelt wie im Lauf (0–100; Punkte und Beute-Glück machen
lohnender, nicht stärker). Sie ist eine **Empfehlung, keine Sperre**: Ausrüstung ersetzt nie das Treten, jede freie Stufe
ist auch mit Stärke 0 wählbar, und freigeschaltet wird nur über den Abschluss.

**Rundensteigerung (#54):** Jede weitere Runde im selben Arcade-Lauf wird etwas härter und lohnender – je Runde die
Zielzone 1 rpm schmaler (höchstens 3 rpm, nie schmaler als 6 rpm; Schwellen steigen entsprechend), die Dauer 4 % länger
(höchstens + 20 %), die Punkte 10 % höher und die Beute-Qualität 5 % höher (höchstens + 50 %). Gezählt wird die Runde im
Lauf (die erste Runde des Laufs ist Runde 1, wo auch immer er beginnt); Auswahl und Lage der Herausforderungen bleiben bei
gleichem Seed gleich, nur ihre Parameter ändern sich, und die erste Runde jeder Stufe ist genau die Stufe. Die Steigerung
erreicht jede Herausforderung, jede Boss- und Elite-Phase und die wandernde Zone, immer vor dem Wächter des Kadenzbereichs.
Beim Einfahren in eine neue Runde erscheint „Runde 2 – härter und lohnender“; die Zusammenfassung nennt die erreichte
Steigerung („Runde 3 erreicht: Zonen 2 rpm schmaler · Punkte +20 %“). Tests: `tests/test_arcade_tiers.gd` (Stufen als Daten,
Freischalten mit Gegenproben, Spielstand mit altem Stand, Stärke aus Ausrüstung und Talenten, Empfehlung ohne Sperre,
Rundensteigerung bei gleichen Würfen, Wächter über alle Stufen × Runden × wählbaren Bereiche × Bausteintypen samt Boss- und
Elite-Phasen mit Gegenprobe) und `tests/test_arcade_tiers_ride.gd` (echtes Spiel: Seite „Arcade“ mit gesperrten Stufen und
Stärke, auch nach neuer Ausrüstung, Layout in 960×1040, 1920×1080 und 1152×648; Sieg über den letzten fehlenden Boss schaltet
frei und steht auf der Platte; Rundensteigerung über drei Runden mit Hinweis und Zusammenfassung).

Erster Baustein ist **Zone halten** (nach Lanebreaks „Streams“): die Kadenz eine Zeit lang in einer Zielzone halten. Jede
Sekunde in der Zone (Grenzen eingeschlossen) füllt den Fortschritt, außerhalb steht er. Voll → **geschafft** (Punkte,
Einblendung „Zone halten geschafft! +100 Punkte“); läuft vorher das Zeitfenster ab → **verfehlt** – weich: keine Punkte,
eine Einblendung („Zone halten verfehlt – weiter geht's“), die Fahrt geht weiter. Die Herausforderungen sind Daten
(`Encounters.CHALLENGES`): Zone halten in der Mitte (15 s in 30 s, 100 Punkte), im unteren Drittel (20 s in 35 s, 120)
und zügig (12 s in 25 s, 120); die Lage der Zone ist relativ zum eigenen Kadenzbereich, ihre Breite gibt die Stufe vor.

**Durchbruch und Jagd (#47):** Zwei weitere Bausteine, beide mit einer **Schwelle** statt einer Zone: es zählt jede
Sekunde mit Kadenz ab der Schwelle (sie selbst eingeschlossen); mehr als der Bereich zählt weiter, schneller wird es
dadurch nicht. Die Schwelle liegt relativ im eigenen Kadenzbereich (`threshold_at`, bei 60–120 rpm z. B. 0,8 → 108 rpm);
die Zielzone der Anzeige reicht von der Schwelle bis zum oberen Ende des Bereichs. Im HUD steht „Ziel ab 108 rpm“, das
Starttor trägt „Start  ab 108 rpm“, der Zonenbalken zeigt [Schwelle, oberes Ende].

- **Durchbruch** (nach Lanebreaks „Sprint“, kurze harte Anstrengung): Ein **Balken** füllt sich in `fill_s` Sekunden über
  der Schwelle, darunter sinkt er langsam (mit halber Füllrate, `decay` 0,5, nie unter null) – ein Nachlassen kostet,
  ein Einbruch nicht alles. Voll → **geschafft** („Durchbruch geschafft! +140 Punkte“); läuft vorher das Zeitfenster
  ab → **verfehlt** – weich: keine Punkte, „Durchbruch verfehlt – weiter geht's“, die Fahrt geht weiter. Zwei
  Einträge: *Zugbrücke* (Schwelle bei 80 % des Bereichs = 108 rpm, 6 s in 18 s, 140 Punkte) und *Spurt* (85 % = 111 rpm,
  4 s in 14 s, 160 Punkte).
- **Jagd** (nach Lanebreaks „Verfolgung“): Ein Verfolger ist hinter dir. Der **Abstand** (0 = auf den Fersen, 1 =
  abgehängt) beginnt mit einem Vorsprung (`start_gap`), wächst über der Schwelle (in `escape_s` Sekunden von 0 auf 1)
  und schrumpft darunter (in `catch_s` Sekunden von 1 auf 0). Abstand 1 → **abgehängt** (geschafft, „Jagd geschafft!
  +140 Punkte“); Abstand 0 (eingeholt) oder Zeitfenster vorbei → **verfehlt**, weich: der Verfolger zieht ab, die Fahrt
  geht weiter. Zwei Einträge: *Verfolger* (Schwelle 55 % = 93 rpm, 12 s abhängen, 12 s bis zum Einholen, Fenster 30 s,
  Vorsprung 0,4, 140 Punkte) und *wild* (65 % = 99 rpm, 10 s / 8 s, Fenster 28 s, Vorsprung 0,35, 170 Punkte).

**Stufe:** Höhere Stufen heben die Schwelle um die halbe Differenz zur Zonenbreite von Stufe 1 (Stufe 2 +3 rpm, Stufe 3
+5 rpm; höchstens bis zum oberen Ende des Bereichs – *Spurt* auf Stufe 3: 116 rpm, *Zugbrücke* 108 / 111 / 113 rpm). Die
Dauer (`fill_s`, `escape_s`, Zeitfenster) wächst wie bei Zone halten × 1 / 1,25 / 1,5, die Punkte × 1 / 2 / 3; die Zeit
bis zum Einholen (`catch_s`) bleibt.

**Wächter:** Auch die Schwelle läuft durch `Encounters.build` (`Encounters.zone_for` → `CadenceRange.limit_zone`): sie
liegt nie über dem oberen Ende und nie unter dem unteren Ende des Bereichs, auch nicht durch Stufe oder Ausrüstung. Die
Zielzone [Schwelle, oberes Ende] ist nie breiter als der Bereich.

**Ausrüstung ersetzt nie das Treten:** Fortschritt (`progress_pct`) beschleunigt das Füllen des Balkens und das Wachsen des
Abstands nur mit Kadenz über der Schwelle; darunter und ohne Kadenz ändert sich nichts, auch das Zeitfenster bleibt. Zonenbreite
(`zone_width_rpm`) senkt die Schwelle um die halbe Breite (nie unter das Minimum des Bereichs).

**Beute:** wie bei Zone halten – geschafft sicher, verfehlt mit 0,5 × Fortschritt. Beim Durchbruch zählt der Balken,
bei der Jagd nur der **erarbeitete** Abstand (größter erreichter Abstand über dem Vorsprung, auf 0–1 umgerechnet;
`ChallengeBlock.loot_progress()`), nicht der geschenkte Vorsprung: wer nie über der Schwelle tritt, bekommt nie etwas.

**Zugbrücke** (`src/drawbridge.gd`): Beim Durchbruch steht statt des Zieltors zwischen zwei Steintürmen eine hochgezogene
Holzklappe quer über der Straße, dort wo das Zeitfenster endet (GatePlacement wie beim Zieltor). Sie senkt sich mit dem
Balken, bis sie auf der Straße liegt; nach dem Erfolg öffnet sie sich zügig ganz, nach dem Scheitern trotzdem – nur langsam
(ohne Punkte und Beute). Wie ein durchfahrenes Tor bleibt sie kurz stehen. **Verfolger** (`src/pursuer.gd`): Beim Jagen
läuft ein dunkelroter Hund mit Hörnern und glühenden Augen 1,9 m links hinter dem Fahrer, bei Abstand 0 in 4 m, bei
Abstand 1 in 45 m (außer Sicht); nach der Jagd fällt er zurück und verschwindet. Beides ist reine Anzeige aus Grundkörpern
(ADR-0010); die Bühne des Arcade-Laufs stellt sie (`src/breakthrough_prop.gd`, `src/chase_prop.gd`, #63). Beide Herausforderungen kommen wie Zone halten in die Würfel
der Arcade-Läufe (`Encounters.CHALLENGES`, mit Takt-Tore und Sammeln (#48) jetzt elf Einträge).

**Takt-Tore und Sammeln (#48):** Zwei weitere Bausteine, beide nur über die Kadenz zu lösen (keine zweite Eingabe). Ihre
Herausforderungen sind wie die übrigen Daten (`src/challenges/rhythm_gates_challenges.gd`, `collect_challenges.gd`) und
kommen mit vier neuen Einträgen in die Würfel der Arcade-Läufe.

- **Takt-Tore** (`src/rhythm_gates.gd`): Markierungen auf der Straße, die im vorgegebenen Takt durchfahren werden. Die
  Taktschläge sind Zeitpunkte: der erste `first_s` Sekunden nach Beginn, dann alle `interval_s`. Ein Tor ist **getroffen**,
  wenn die Kadenz im Zeitfenster von `tolerance_s` vor bis `tolerance_s` nach dem Schlag in der Zielzone liegt (Grenzen
  eingeschlossen); zwischen den Schlägen ist die Kadenz frei – locker rollen und rechtzeitig in die Zone gehen genügt. Endet
  das Fenster ohne Kadenz in der Zone, ist das Tor **verpasst**. Nach dem letzten Schlag zählt das Ergebnis: mindestens
  `need` Treffer → **geschafft** („Takt-Tore geschafft! +120 Punkte“); ist `need` nicht mehr zu erreichen, → **verfehlt** –
  weich und schon in dem Moment, in dem es feststeht („Takt-Tore verfehlt – weiter geht's“), die Fahrt geht weiter. Die
  Zielzone entsteht wie bei Zone halten (`zone_at`, Breite aus der Stufe, Ausrüstung, Wächter). Zwei Einträge (Stufe 1,
  Kadenzbereich 60–120 rpm): *Ruhiger Takt* (`takt_ruhig`: Zone bei 40 % = 74–94 rpm, 5 Tore, 4 Treffer nötig, erster
  Schlag nach 6 s, dann alle 5 s, Fenster ± 1 s, 120 Punkte) und *Flotter Takt* (`takt_flott`: 65 % = 89–109 rpm, 6 Tore,
  5 Treffer, alle 4 s, ± 0,8 s, 160 Punkte); beide heißen im Spiel „Takt-Tore“. Mit dem Kadenzmuster „Rhythmus“ (#50, siehe
  „Kadenzmuster und Fähigkeiten“) hat der Baustein nichts zu tun: die Takt-Tore geben den Takt vor, das Muster erkennt den eigenen.
- **Sammeln** (`src/collect.gd`): Ein lockerer Abschnitt mit Belohnung – Kristalle liegen auf und neben der Straße, und die
  **Kadenz bestimmt den Magnetradius** um den Fahrer. Objekt `k` wird `first_s + k × interval_s` Sekunden nach Beginn passiert
  und ist **eingesammelt**, wenn sein seitlicher Abstand von der Straßenmitte (`offsets`, in m) höchstens so groß ist wie der
  Radius in diesem Moment. Der Radius ist 0 unter der **Rampe** (ohne Kadenz kein Magnet), `radius_min_m` an ihrem Beginn und
  wächst linear bis `radius_max_m` am oberen Ende des Kadenzbereichs; darüber wird er nicht größer. Die Rampe liegt relativ im
  eigenen Bereich (`threshold_at`, wie die Schwelle bei Durchbruch und Jagd); im HUD steht „Ziel ab 75 rpm“. Nach dem letzten
  Objekt: mindestens `need` eingesammelt → **geschafft** („Sammeln geschafft! +110 Punkte“), sonst **verfehlt** – weich
  („Sammeln verfehlt – weiter geht's“), und früher, sobald `need` nicht mehr zu erreichen ist. Zwei Einträge (Stufe 1,
  60–120 rpm): *Wiese* (`sammeln_wiese`: Rampe ab 25 % = 75 rpm, 8 Objekte alle 3 s ab 5 s mit 0,5–4 m Abstand, 5 nötig, Radius
  1 m bis 5 m – bei 108 rpm 3,9 m –, 110 Punkte) und *Ufer* (`sammeln_ufer`: ab 40 % = 84 rpm, 10 Objekte alle 2,5 s mit bis zu
  5 m Abstand, 6 nötig, Radius 1 m bis 5,5 m, 150 Punkte).

**Stufe** (Takt-Tore und Sammeln): Zahl der Tore bzw. Objekte und die nötige Zahl wachsen × 1 / 1,25 / 1,5 (*Ruhiger Takt*
5 / 6 / 8 Tore mit 4 / 5 / 6 Treffern; *Wiese* 8 / 10 / 12 Objekte – reihum wiederholt – mit 5 / 6 / 8 nötigen), die Punkte
× 1 / 2 / 3. Die Zone der Takt-Tore wird schmaler (20 / 14 / 10 rpm), die Rampe des Sammelns beginnt später (*Wiese* 75 / 78 /
80 rpm, das Ende bleibt das obere Ende des Bereichs). Taktabstand und Zeitfenster bleiben.

**Wächter:** Zone und Rampe laufen wie jede Zielzone durch `Encounters.build` (`Encounters.zone_for` →
`CadenceRange.limit_zone`) und liegen nie außerhalb des Kadenzbereichs, auch nicht durch Stufe oder Ausrüstung: die
Zonenbreite der Ausrüstung verbreitert die Zone der Takt-Tore und senkt den Beginn der Rampe um die halbe Breite (nie unter
das Minimum des Bereichs).

**Ausrüstung ersetzt nie das Treten:** Fortschritt (`progress_pct`) lässt jeden **Treffer** der Takt-Tore mehrfach zählen
(Anzeige „Takte“) und vergrößert beim Sammeln den **Radius** – beides nur dort, wo die Kadenz schon etwas ergibt (im Fenster
in der Zone bzw. in der Rampe). Ohne Kadenz dort bleiben Treffer, Radius, Punkte und Beute bei 0, mit Ausrüstung genauso wie
ohne; Zeitfenster und Taktzeiten bleiben unberührt. **Beute:** wie bei Zone halten – geschafft sicher, verfehlt mit
0,5 × Fortschritt (Takt-Tore: Treffer im Verhältnis zu den nötigen, Sammeln: Eingesammeltes im Verhältnis zu den nötigen); ohne
Treffer bzw. ohne Eingesammeltes nie.

**Darstellung** (reine Anzeige aus Grundkörpern, ADR-0010; `src/rhythm_gates_prop.gd`, `src/collect_prop.gd`, eingetragen
in `ArcadeStage.PROPS`): Tore und Kristalle stehen dort, wo der Fahrer zum Zeitpunkt des Schlags bzw. Objekts beim aktuellen
Tempo ankommt (`src/timed_markers.gd`: GatePlacement je Markierung, Tempo aus der Fahrt; im Stand und beim Anfahren unter
0,5 m/s wird nichts gesetzt). Takt-Tore: je Schlag ein grünes Tor (das Tor aus #58) mit „Takt 2/5“, die nächsten drei stehen
im Bild; ein getroffenes bleibt grün und trägt „Treffer“, ein verpasstes wird orange und trägt „Verpasst“, durchfahrene
bleiben so lange hinter dem Fahrer stehen wie das Zieltor; die Tore ersetzen das Zieltor. Sammeln: goldene Kristalle (die
nächsten fünf), seitlich nach ihrem Abstand versetzt, und ein flacher türkiser **Magnetring** um den Fahrer, dessen Radius der
Magnetradius ist – er wächst und schrumpft mit der Kadenz und fehlt, wo es keinen Magneten gibt; ein eingesammeltes Objekt
verschwindet beim Vorbeifahren, ein liegengebliebenes wird grau; das Zieltor bleibt. Im HUD stehen „Ziel 74–94 rpm“ bzw.
„Ziel ab 75 rpm“, die Restzeit und der Fortschritt („Takte“ bzw. „Gesammelt“). In jeder Pause steht alles still.

**Kadenzbereich** (Standard 60–120 rpm, auf der Seite „Arcade“ einstellbar): keine Zielzone liegt außerhalb. Ragt eine
Zone hinaus, rückt sie mit gleicher Breite hinein; ist sie breiter als der Bereich, wird sie der ganze Bereich. Das
geschieht an einer Stelle (`Encounters.build` → `CadenceRange.limit_zone`), durch die jede Zielzone muss – auch die von
Stufen, späterer Runden (#54) und Elite-Eigenschaften (#52; auch die wandernde Zone von *Wankelmütig* in jedem Augenblick).

Im HUD steht die Arcade-Zeile (vor dem Start „Nächste: Zone halten · Ziel 80–100 rpm · noch 45 m“, während der
Herausforderung Restzeit und Zonenbalken mit Fortschritt); auf der Strecke steht am Startpunkt ein grünes **Starttor**
(„Start 80–100 rpm“) und während der Herausforderung ein **Zieltor** dort, wo der Fahrer beim aktuellen Tempo das Ende
des Zeitfensters erreicht (wie die Intervall-Tore, #58). In jeder Pause (manuell oder Verbindung, ADR-0004) läuft keine
Herausforderung weiter und keine scheitert. **Fahrt beenden** zeigt die **Zusammenfassung**: Stufe, Zeit, Runden, Strecke,
Punkte (mit „neue Bestpunktzahl!“), Herausforderungen geschafft/verfehlt und je Herausforderung.

**Getrennte Welten (ADR-0010):** Arcade-Kilometer und -Runden zählen für Fahrtenbuch („Arcade“), Fahrerlevel und Erfolge;
Runden im Arcade schreiben nie Bestzeit, Segmentzeit, Medaille oder Ghost (`records_count()` der Hauptszene). Logik in
`src/challenge_block.gd`, `src/zone_hold.gd`, `src/breakthrough.gd`, `src/chase.gd`, `src/rhythm_gates.gd`, `src/collect.gd`,
`src/boss_fight.gd`, `src/elite_group.gd`, `src/elite_groups.gd`,
`src/encounters.gd`,
`src/encounter_registry.gd` und `src/challenges/` (Daten und Bauanleitung je Bausteintyp),
`src/arcade_tiers.gd`, `src/cadence_range.gd` und
`src/arcade_run.gd` (alles ohne Szene und Bus).

**Aufbau und Einhängepunkte (#63):** Alles Szenische des Arcade liegt in der **Bühne** (`ArcadeStage`,
`src/arcade_stage.gd`), einem dauerhaften Kind der Hauptszene (`arcade_stage`). Sie hält den reinen Lauf (`run`, null = kein
Arcade) und zeigt in Rundfahrt und Training nichts (ADR-0010). `scenes/main.gd` behält nur den Einhängepunkt: `begin` (Fahrtbeginn),
`advance` (Fahrschritt, nicht in Pausen), `update_view` (HUD-Zeile, Tore, Requisiten, Lichtsäule), `save` (Fahrteintrag,
Bestpunktzahl, Beute ins Inventar), `result_text` (Zusammenfassung), `enter_menu` und `dress` (Ausrüstung am Fahrer); die
Menüs (Stufe mit Freischalten und Empfohlener Stärke, Kadenzbereich, Ausrüstung, Talente) bleiben in der Hauptszene, und
`arcade`, `arcade_seed`, `arcade_pool`, die Tore,
`arcade_bridge`, `arcade_pursuer` und `loot_beam` leiten für Tests und Prüfhilfen an die Bühne weiter. Neue Arcade-Bausteine
(Bosse, Kadenzmuster, …) hängen sich – wie Takt-Tore und Sammeln (#48) – mit **eigenen Dateien und höchstens einer Zeile je Liste** ein, ohne
`main.gd` anzufassen:

- **Typ** (Baustein, Herausforderungen als Daten): `src/challenges/<name>_challenges.gd` mit `ID`, `CHALLENGES` und
  `build(definition, level, zone)`, dazu eine Zeile in `EncounterRegistry.TYPES` (`src/encounter_registry.gd`). Die
  Reihenfolge der Zeilen ist die Reihenfolge des Würfel-Pools (`Encounters.CHALLENGES`): neue Typen ans Ende, sonst
  ändern sich die Würfe bestehender Seeds (`tests/test_arcade_stage.gd` prüft den Anfang des Pools). Zielzonen laufen weiter
  durch `Encounters.zone_for` und den Wächter des Kadenzbereichs.
- **Feste Begegnungen** (Bosse, #51): ein Typ mit leerem `CHALLENGES` und einer Konstante `FIXED`, deren Einträge einen
  Abschnitt (`section`) nennen. `ArcadeRun` plant sie jede Runde in diesem Abschnitt statt der Würfe ein (gewürfelt wird
  trotzdem, die übrigen Abschnitte bleiben bei gleichem Seed gleich); nicht im Würfel-Pool. Einträge mit `phases` baut
  `Encounters.build` Phase für Phase (Wächter, Stufe, Ausrüstung) und gibt sie `build_phases` des Typs; Ziel und Zieltext
  vor dem Start sind die der ersten Phase. Eine Definition mit `loot_quality` hebt die Grundqualität ihrer Beute, `boss`
  führt sie in Ergebnis und Zusammenfassung als Boss.
- **Zufällige Begegnungen** (Elite-Gruppen, #52): keine Zeile im Pool, sondern ein eigener Würfel in `ArcadeRun`
  (`EliteGroups.roll`), der eine gewürfelte Herausforderung zur Elite-Gruppe macht – eine Definition mit `phases` wie ein Boss
  (Typ `elite`, `src/challenges/elite_challenges.gd`, `CHALLENGES` leer). Eigenschaften ändern nur die Daten der Phasen vor
  `Encounters.zone_for`; eine wandernde Zone (`wander`) liefert `Encounters.zone_for(…, at_s)` je Augenblick, ebenfalls durch
  den Wächter.
- **Darstellung** (Requisiten, nur Anzeige): `src/<name>_prop.gd` (`extends ArcadeProp`) und eine Zeile in
  `ArcadeStage.PROPS`. Bausteine ohne Darstellung zeigen das Zieltor wie Zone halten.
- **Hooks, Signale, Zusammenfassung:** eine Erweiterung (Skript mit `attach(stage)`) und eine Zeile in
  `ArcadeStage.EXTENSIONS`. Sie hört auf die Signale der Bühne – `challenge_started`, `challenge_ended`, `loot_found`,
  `stepped` (je Fahrschritt mit geglätteter und ungeglätteter Kadenz, für Kadenzmuster) und `run_finished` –, stellt den
  Lauf über `run_hooks` ein (`gear`, `loot_quality`) und hängt über `summary_providers` Zeilen an die Zusammenfassung.

Die Schnittstelle steht ausführlich im Kopf von `arcade_stage.gd`, `arcade_prop.gd` und `encounter_registry.gd`.

**Simulator-Szenarien:** `bridge/profiles/arcade/` – *perfekt in der Zone* (`zone_perfekt.toml`, 90 rpm: geschafft),
*knapp daneben* (`zone_knapp_daneben.toml`, 102 rpm: weich verfehlt), *Abbruch* (`zone_abbruch.toml`: mitten im Halten
stale und 30 s disconnected – Pause, danach geschafft). Von Hand: `vspin-bridge --source sim --profile
profiles/arcade/zone_perfekt.toml`, im Spiel Arcade auf Stufe 1 mit 60–120 rpm. `tests/test_arcade_ride.gd` spielt
dieselben Dateien über den Fake-Bus durchs Spiel.

Zu Durchbruch und Jagd (#47) vier weitere Szenarien (Stufe 1, 60–120 rpm; je 12 s 90 rpm bis zum Startpunkt, danach das
Szenario, am Ende 10 s 90 rpm): *Durchbruch geschafft* (`durchbruch_geschafft.toml`, 8 s mit 114 rpm über der Schwelle
108: Brücke offen, +140 Punkte), *Durchbruch zu schwach* (`durchbruch_zu_schwach.toml`, 22 s mit 104 rpm: Balken bleibt
leer, weich verfehlt, die Brücke öffnet sich trotzdem langsam, keine Beute), *Jagd entkommen* (`jagd_entkommen.toml`, 14 s
mit 100 rpm über 93: abgehängt, +140 Punkte und Beute) und *Jagd eingeholt* (`jagd_eingeholt.toml`, 14 s mit 80 rpm:
eingeholt, keine Punkte, keine Beute). `tests/test_arcade_ride.gd` spielt sie mit der jeweils erzwungenen Herausforderung
(`_play_profile(name, challenge)`) durchs Spiel; von Hand würfelt der Lauf die Herausforderung selbst. Tests der reinen
Logik: `tests/test_arcade_blocks.gd` (Erfolg, Scheitern, Pause, Wächter mit Gegenprobe, Ausrüstung nur über der Schwelle,
Stufen, Punkte und Beute im Lauf). `tests/test_arcade_stage.gd` (#63): Reihenfolge des Würfel-Pools (gleiche Würfe bei
gleichem Seed), jeder Typ der Registry baut seinen Baustein, Ereignisse der Bühne, Hooks und Erweiterungen.

Zu Takt-Tore und Sammeln (#48) vier weitere Szenarien (Stufe 1, 60–120 rpm; der Test erzwingt je Szenario die
Herausforderung *Ruhiger Takt* bzw. *Wiese*, von Hand würfelt der Lauf selbst): *Takt getroffen* (`takt_getroffen.toml`: 12 s 70 rpm bis zum Start, dann
fünfmal im Takt von 5 s auf 86 rpm hoch – je 1,5 s oben, in der Zone 74–94 – und zurück auf 70: alle fünf Tore getroffen,
+120 Punkte und Beute), *Takt verfehlt* (`takt_verfehlt.toml`, 45 s 100 rpm über der Zone: kein Tor getroffen, weich
verfehlt, keine Beute), *Sammeln viel* (`sammeln_viel.toml`, 45 s 108 rpm: Radius rund 3,9 m, 7 von 8 Objekten, +110 Punkte
und Beute) und *Sammeln wenig* (`sammeln_wenig.toml`, 45 s 78 rpm: Radius rund 1,3 m, 2 von 8 Objekten, weich verfehlt,
keine Beute). `tests/test_arcade_rhythm_collect_ride.gd` spielt sie über den Fake-Bus durchs Spiel und prüft dazu die
Darstellung auf der Strecke (Tore voraus in Taktfolge, „Treffer“ und „Verpasst“, Kristalle und Magnetring folgen der
Kadenz); Tests der reinen Logik: `tests/test_arcade_rhythm_collect.gd` (Treffer, Fenster- und Zonengrenzen, Erfolg und
Scheitern, Pause, Wächter mit Gegenprobe, Ausrüstung nur mit Kadenz, Stufen, Punkte und Beute im Lauf, Lage der
Markierungen).

Sichtprüfung: `view_probe.gd -- --title --arcade` speichert `title_arcade.png`, `--hud --arcade` Starttor mit nächster
Herausforderung (`arcade_gate.png`), Zone halten (`zone_hold.png`, Kadenz zu hoch `zone_hold_above.png`), Erfolg
(`zone_hold_success.png`) und die Zusammenfassung (`arcade_result.png`).

Durchbruch und Jagd (#47): `view_probe.gd -- --hud --arcade --props` speichert statt der Zone-halten-Bilder die Zugbrücke
zu, halb und offen (`bridge_closed.png`, `bridge_half.png`, `bridge_open.png`, dazu `bridge_close_*.png` aus der Nähe) und
den Verfolger der Jagd (`pursuer_close.png` von hinten, `pursuer_front.png` und `pursuer_side.png` aus der Nähe,
`pursuer_gone.png` nach dem Abhängen). Balken und Abstand setzt die Probe direkt.

Takt-Tore und Sammeln (#48): `view_probe.gd -- --hud --arcade --rhythm` speichert die Takt-Tore voraus (`rhythm_ahead.png`),
nach einem Treffer (`rhythm_hit.png`) und nach einem verpassten Tor bei zu hoher Kadenz (`rhythm_missed.png`), dann das
Sammeln: Objekte voraus mit großem Magnetring bei hoher Kadenz (`collect_high.png`), mit kleinem bei niedriger
(`collect_low.png`) und die Objekte aus der Nähe (`collect_close.png`).

### Bosse (#51)

Drei **Bosse** – Sagengestalten der Insel – warten jede Runde an ihrem festen Ort des Rundkurses: **Tramuntana** auf der
Küstenstraße, **Drac de na Coca** in den Serpentinen, die **Dimonis** im Bergdorf. In ihrem Abschnitt steht statt der
gewürfelten Herausforderungen der Boss (Beginn 50 m hinter dem Anfang des Abschnitts); Bosse werden nicht gewürfelt und
stehen nicht im Würfel-Pool (`Encounters.CHALLENGES`). Gewürfelt wird dort trotzdem, damit alle übrigen Abschnitte bei
gleichem Seed dieselben Herausforderungen bekommen. Die Graybox hat keine Stationen und damit keine Bosse.

Ein Boss ist eine Folge von **Phasen**, jede ein vorhandener Baustein mit eigenen Parametern – Daten, keine Sonderlogik
(`src/challenges/boss_challenges.gd`, Konstante `FIXED`). Die Phasen laufen nacheinander, jede mit eigenem Zeitfenster ab
ihrem Beginn; Stufe (Zonenbreite, Dauer, Punkte), Kadenzbereich-Wächter und Ausrüstung wirken auf jede Phase wie auf jede
Herausforderung (`Encounters.build`). Werte für Stufe 1 und 60–120 rpm:

| Boss | Ort | Phasen | Punkte | Beute-Qualität |
|---|---|---|---|---|
| Tramuntana (Böen von vorn, die Zone halten) | Küstenstraße | *Gegenwind*: Zone halten 80–100 rpm, 10 s in 20 s · *Böe*: Durchbruch ab 105 rpm, 5 s in 15 s · *Sturmfront*: Zone halten 86–106 rpm, 12 s in 24 s | 400 | × 2 |
| Drac de na Coca (der große Kampf) | Serpentinen | *Feueratem*: Zone halten 77–97 rpm, 12 s in 24 s · *Flügelschlag*: Durchbruch ab 108 rpm, 6 s in 18 s · *Schuppenpanzer*: Zone halten 86–106 rpm, 12 s in 24 s · *Letzter Ansturm*: Durchbruch ab 111 rpm, 5 s in 16 s | 600 | × 2,5 |
| Dimonis (Jagd durchs Dorf) | Bergdorf | *Durch die Gassen*: Jagd ab 93 rpm (in 10 s eingeholt, unter der Schwelle in 12 s entwischt, Fenster 25 s, Vorsprung 0,4) · *Über den Dorfplatz*: Durchbruch ab 105 rpm, 5 s in 15 s · *Hinaus aus dem Dorf*: Jagd ab 99 rpm (8 s / 10 s, Fenster 22 s, Vorsprung 0,35) | 450 | × 2 |

Bei den Dimonis jagt der Fahrer: der Abstand der Jagd ist sein Aufholen (1 = eingeholt, die Phase ist geschafft; 0 =
entwischt, die Phase ist verfehlt).

**Lebensbalken:** Oben in der Bildmitte stehen der Name des Bosses, ein roter Lebensbalken und die laufende Phase mit Ziel
und Restzeit („Phase 2/3 · Böe · ab 105 rpm · noch 12 s“). Der Balken sinkt nur mit dem, was die Kadenz in der Zielzone
bzw. über der Schwelle erarbeitet: jede geschaffte Phase nimmt ein n-tel, die laufende ihren Fortschritt (bei der Jagd nur
das Aufgeholte, nicht der geschenkte Vorsprung). Fällt der Balken einer Durchbruch-Phase zurück, erholt sich der Boss
entsprechend. Unten im HUD stehen der Boss, das Ziel der laufenden Phase in ihrem Format (Zone „80–100 rpm“, Schwelle
„ab 105 rpm“; Nacharbeit #27), die Restzeit des ganzen Kampfes (laufende Phase plus die Zeitfenster
der folgenden) und der Stand („Kampf“); auf der Strecke ersetzt der Boss das Zieltor.

**Besiegt** – alle Phasen geschafft: Punkte („Tramuntana besiegt!  +400 Punkte“), der Balken meldet „Tramuntana besiegt!“
und „Boss-Beute gefunden“; Beute gibt es sicher, mit der Beute-Qualität des Bosses als Faktor auf die Grundqualität (mehr
seltene Teile). **Entkommen** – scheitert eine Phase (Zeitfenster vorbei, bei den Dimonis: entwischt), entkommt der Boss
sofort. Das ist weich: keine Punkte, eine Einblendung („Dimonis entkommen – weiter geht's“), der Balken meldet „Dimonis
entkommen“, die Fahrt geht weiter; Beute wie bei jeder verfehlten Herausforderung nur mit der Chance 0,5 × Schaden (ohne
Treten in der Zone nie). In jeder Pause (manuell oder Verbindung, ADR-0004) stehen Kampf, Phase, Zeit und Lebensbalken
still; nach der Rückkehr geht der Kampf weiter. Die **Zusammenfassung** zählt Bosse bei „Herausforderungen: … geschafft ·
… verfehlt“ mit und nennt sie in einer eigenen Zeile („Bosse: Tramuntana besiegt · Dimonis entkommen“); der Fahrteintrag
bleibt `{tier, points, won, failed}`.

**Ausrüstung und Fähigkeiten** (#49, #50) wirken über den Fortschrittsfaktor auf die laufende Phase – nur mit Kadenz in der
Zone bzw. über der Schwelle; Zielzone und Zeitfenster bleiben. Das Schild nimmt das Erholen des Bosses (sinkender
Durchbruch-Balken) zurück.

**Darstellung** (reine Anzeige aus Grundkörpern, ADR-0010; `src/boss_prop.gd` in `ArcadeStage.PROPS`, `src/boss_figure.gd`,
`src/boss_bar.gd`): **Tramuntana** ist ein Sturmgeist – eine Wolke mit Gesicht und zwei kreisenden Windringen, die rund 30 m
voraus über der Straße schwebt und Windstreifen auf den Fahrer bläst (in einer Durchbruch-Phase schneller). **Drac de na
Coca** ist ein grüner Drache mit roten Flügeln, Hörnern, Stachelkamm und Feueratem, der rund 24 m voraus auf der Straße
steht und den Fahrer ansieht; in einer Durchbruch-Phase schlagen die Flügel schneller. Die **Dimonis** sind drei
Teufelsgestalten der Dorffeste (rote Masken mit Hörnern, schwarze Kostüme mit Flammen, zwei mit Gabel), die voraus
davonspringen – in einer Jagd-Phase 42 m voraus, solange sie entwischen, bis 7 m, wenn sie eingeholt sind. Jeder Boss wird
mit sinkendem Lebensbalken kleiner (bis 70 %); besiegt sinkt er an seiner Stelle zusammen, entkommen zieht er voraus davon
(Sturmgeist und Drache auch in die Höhe). Nach dem Kampf steht das Ergebnis 4 s im Balken.

**Simulator-Szenarien** (`bridge/profiles/arcade/`, Stufe 1, 60–120 rpm; der Test erzwingt je Szenario den Boss, von Hand
gibt es ihn auf dem Rundkurs an seinem Ort): *Abbruch mitten im Bosskampf* (`boss_abbruch.toml`, Tramuntana: 12 s 90 rpm,
dann im Gegenwind 4 s keine Daten und 30 s `disconnected` – länger als das Zeitfenster der Phase –, danach 90 / 112 / 96 rpm:
Pause mit stehendem Lebensbalken, danach Weiterfahrt und Sieg), *Tramuntana besiegt* (`boss_tramuntana.toml`), *Drac de na
Coca besiegt* (`boss_drac.toml`, alle vier Phasen), *Dimonis besiegt* (`boss_dimonis_besiegt.toml`, 100 / 112 / 104 rpm)
und *Dimonis entkommen* (`boss_dimonis_entkommen.toml`, 25 s mit 85 rpm unter der Schwelle 93: entwischt, keine Punkte,
keine Beute). `tests/test_bosses_ride.gd` spielt sie über den Fake-Bus durchs Spiel und prüft dazu Lebensbalken, Gestalt
und die festen Orte auf dem Rundkurs; Tests der reinen Logik: `tests/test_bosses.gd` (Phasen als Daten, Lebensbalken nur
mit Kadenz in der Zone, Sieg, Entkommen, Pause, Wächter für jede Phase mit Gegenprobe, Ausrüstung und Fähigkeiten nur mit
Kadenz, Schild, Planung an festen Orten mit unveränderten übrigen Würfen, Punkte, Boss-Beute und Zusammenfassung).

Sichtprüfung: `view_probe.gd -- --hud --arcade --bosses` stellt den Fahrer an den Ort jedes Bosses und spielt den Kampf:
`boss_<id>.png` (Beginn, voller Lebensbalken), `boss_<id>_close.png` (aus der Nähe), `boss_<id>_hurt.png` (angeschlagen;
Tramuntana in der Böe), `boss_tramuntana_defeated.png`, `boss_drac_defeated.png` (beim Zusammensinken) und
`boss_dimonis_escape.png` (ohne Treten entkommen).

### Elite-Gruppen (#52)

Jede gewürfelte Herausforderung kann als **Elite-Gruppe** kommen (Chance 15 %): eine stärkere Fassung derselben
Herausforderung mit 1–3 **Eigenschaften**, erkennbar an ihrer Farbe – **blau = Champions**, **gelb = Seltene mit Gefolge**
(gut ein Drittel der Elite-Gruppen sind Seltene). Bosse werden nie zu Elite-Gruppen; in ihrem Abschnitt steht weiter der
Boss. Gewürfelt wird mit einem eigenen Würfel: bei gleichem Seed bleiben Zahl, Auswahl und Lage der Herausforderungen
gleich, nur einzelne kommen als Elite-Gruppe. Elite-Gruppen gibt es im Standard-Pool; ein vorgegebener Pool (Tests,
Prüfhilfe) bekommt keine, außer er nennt die Chance selbst.

| Elite-Stufe | Farbe | Eigenschaften | Gefolge | Punkte | Beute-Qualität |
|---|---|---|---|---|---|
| Champions | blau (wie „magisch“) | 1–2 | – | × 1,5 | × 1,5 |
| Seltene | gelb (wie „selten“) | 2–3 | 1 | × 2 | × 2 |

Die **Eigenschaften** sind Daten (`src/elite_groups.gd`, `AFFIXES`): Jede verschiebt Parameter der Herausforderung je
Bausteintyp oder fügt eine Phase an; gewürfelt werden nur Eigenschaften, die den Typ der Herausforderung verändern. Werte
relativ zum Kadenzbereich:

| Eigenschaft | Wirkung |
|---|---|
| *Windschnell* | weniger Zeit: Zeitfenster von Zone halten und Durchbruch × 0,8; Jagd: Abhängen dauert × 1,25, der Verfolger holt × 0,8 schneller auf; Takt-Tore: Fenster je Schlag × 0,7 |
| *Wankelmütig* | die Zielzone wandert (Zone halten, Takt-Tore): sie beginnt an ihrem Platz und schwingt um ± 20 % des Bereichs auf und ab, eine Schwingung 16 s |
| *Gegenwind* | Zone bzw. Schwelle höher: Zone + 10 % des Bereichs (höchstens 85 %), Durchbruch + 6 % (höchstens 93 %), Jagd + 8 % (höchstens 85 %), Beginn der Sammel-Rampe + 10 % (höchstens 60 %) |
| *Zäh* | länger halten (× 1,3), Balken des Durchbruchs × 1,3, Vorsprung der Jagd × 0,75, ein Treffer der Takt-Tore bzw. ein Objekt beim Sammeln mehr |
| *Taktwechsel* | Takt-Tore: die zweite Hälfte der Tore als eigene Phase im Abstand × 0,7 – der Takt wird schneller |
| *Rudelführer* | ein Gefolge mehr (Champions bringen eins mit, Seltene ein zweites) |

Eine Elite-Gruppe ist eine Folge von **Phasen** wie ein Boss (#51): erst der **Anführer** (die veränderte Herausforderung,
bei *Taktwechsel* in zwei Phasen), dann das **Gefolge** – eine kleine Herausforderung im Zielformat des Anführers (Zone
halten bei 45 %, 6 s in 12 s; Durchbruch ab 70 %, 3 s in 9 s; oder Jagd ab 50 %, 6 s / 8 s in 14 s, Vorsprung 0,4; je
40 Punkte). Jede Phase läuft mit eigenem Zeitfenster ab ihrem Beginn; Stufe, Ausrüstung und Fähigkeiten wirken auf sie wie
auf jede Herausforderung, aber nur mit Kadenz in der Zone bzw. über der Schwelle. **Geschafft** – alle Phasen: Punkte (die
des Anführers × Faktor der Elite-Stufe plus die des Gefolges, dann × Stufe; Champions der Jagd *Verfolger*: 140 × 1,5 =
210) und sichere Beute mit der Beute-Qualität der Elite-Stufe als Faktor auf die Grundqualität (öfter seltene Teile).
**Verfehlt** – scheitert eine Phase, ist die Gruppe verfehlt: weich, keine Punkte, „… verfehlt – weiter geht's“, die Fahrt
geht weiter; Beute wie bei jeder verfehlten Herausforderung. In jeder Pause steht alles still.

**Kadenzbereich:** Eigenschaften ändern nur die Daten (Lage, Dauern, Zahlen); die Zielzone entsteht danach wie jede in
`Encounters.zone_for` → `CadenceRange.limit_zone`. Auch die wandernde Zone geht in jedem Augenblick durch den Wächter: am
Rand des Bereichs bleibt sie mit gleicher Breite stehen, in einem Bereich so schmal wie die Zone wandert sie nicht. Jede
Eigenschaft und jede Kombination bleibt auf jeder Stufe mit Kadenz allein lösbar.

**Darstellung** (reine Anzeige aus Grundkörpern, ADR-0010; `src/elite_prop.gd` in `ArcadeStage.PROPS`, `src/elite_banner.gd`,
`src/elite_badge.gd`): Jede Phase zeigt die Darstellung ihres Bausteins (Zugbrücke, Verfolger, Takt-Tore, Kristalle). Dazu
die **Standarte** – ein Fahnenmast am rechten Straßenrand mit einer leuchtenden Fahne in der Farbe der Elite-Stufe
(Schwalbenschwanz, goldene Raute) und darüber Stufe, Herausforderung und Eigenschaften („Champions: Jagd“, „Windschnell ·
Gegenwind“): ab 300 m vor dem Start steht sie am Startpunkt, im Kampf zieht sie 24 m voraus mit. Oben in der Bildmitte
steht das **Schild**: Name in der Farbe der Stufe, die Eigenschaften und vor dem Start „voraus · noch 28 m“ (bei Seltenen
„· mit Gefolge (1)“), im Kampf die Phase mit Ziel („Anführer · ab 98 rpm“, „Gefolge 1/1 · ab 102 rpm“), danach 4 s das
Ergebnis („geschafft – Elite-Beute“ bzw. grau „verfehlt – weiter geht's“); steht der Lebensbalken eines Bosses noch im
Bild, rückt es darunter. Die Arcade-Zeile unten nennt die Gruppe („Nächste: Champions: Jagd · Ziel ab 98 rpm“).

**Simulator-Szenarien** (`bridge/profiles/arcade/`, Stufe 1, 60–120 rpm; der Test erzwingt die Gruppe): *Champions* (`elite_champion.toml`,
Jagd *Verfolger* mit Windschnell und Gegenwind, Schwelle 98 rpm: 6 s 90 rpm, 16 s 104 rpm, 10 s 90 rpm – abgehängt, +210 Punkte,
Elite-Beute) und *Seltene* (`elite_selten.toml`, Durchbruch *Zugbrücke* mit Gegenwind und Zäh, Schwelle 112 rpm, Gefolge ab
102 rpm: 12 s 90 rpm, 10 s 116 rpm, 12 s 95 rpm, 8 s 90 rpm – der Anführer fällt, das Gefolge entkommt: weich verfehlt).
`tests/test_elite_groups_ride.gd` spielt sie über den Fake-Bus durchs Spiel und prüft Standarte, Schild, Farbe und
Eigenschaften sowie eine zufällig gewürfelte Elite-Gruppe im Standard-Pool; Tests der reinen Logik: `tests/test_elite_groups.gd`
(Eigenschaften und Stufen als Daten, jede Eigenschaft lösbar mit Kadenz allein und ohne Treten verfehlt, Wächter für jede Zone
und die wandernde in jedem Augenblick mit Gegenprobe, Würfeln mit Seed bei unveränderten übrigen Würfen, Bosse nie Elite,
weiches Scheitern, Ausrüstung nur mit Kadenz, Elite-Beute besser als normale).

Sichtprüfung: `view_probe.gd -- --hud --arcade --elite`: `elite_champion_announce.png` und `elite_champion.png` (Ankündigung,
Kampf mit dem Verfolger), `elite_selten_announce.png`, `elite_selten.png` (Zugbrücke) und `elite_selten_gefolge.png`,
`elite_wankelmuetig.png` (wandernde Zone) und `elite_banner_close.png` (Standarte aus der Nähe).

### Kadenzmuster und Fähigkeiten (#50)

Das Spiel erkennt aus der Kadenz vier **Kadenzmuster** – **Antritt**, **Gleichmaß**, **Innehalten** und **Rhythmus** – und
löst damit **Fähigkeiten** aus: **Windböe**, **Fokus**, **Schild** und **Kombo**. Nur im Arcade (ADR-0010) und nur über das
Treten – eine Fähigkeit ersetzt es nie. („Antritt“ bezeichnet nur dieses Kadenzmuster; die Herausforderung heißt Durchbruch.)

Die Muster liest `src/cadence_patterns.gd` (`CadencePatterns`, reine Logik) aus der **ungeglätteten** Kadenz `cadence_raw`
(ADR-0004 Nachtrag #45); HUD, Fahrmodell und Bausteine bleiben bei der geglätteten. Der letzte Wert gilt bis zum nächsten
(der Bus meldet mit 250 ms bis 1 s, die Bilder sind schneller). Alle Schwellen stehen an einer Stelle
(`CadencePatterns.THRESHOLDS`), sind je Lauf über `patterns.thresholds` der Erweiterung und im Konstruktor überschreibbar
und gelten **vorläufig** – endgültig werden sie mit dem echten Gerät (#1) und aus Simulator/Replay kalibriert.

| Muster | Erkannt, wenn … | Fähigkeit |
|---|---|---|
| Antritt | die Kadenz in 2 s um mindestens 25 rpm über das Minimum dieser 2 s steigt, das Minimum ≥ 30 rpm; einmal je Anstieg, wieder scharf, wenn der Anstieg unter 15 rpm fällt. Anfahren aus dem Stand (Minimum unter 30 rpm) ist kein Antritt und löst auch später keinen aus | Windböe |
| Gleichmaß | 10 s lang alle Werte innerhalb von ±3 rpm um die Mitte (größter − kleinster ≤ 6 rpm), der kleinste ≥ 40 rpm; bei anhaltender Ruhe nach weiteren 10 s wieder. Stillstand ist kein Gleichmaß | Fokus |
| Innehalten | die Kadenz 2 s ununterbrochen unter 10 rpm liegt, einmal je Pause – und nur, nachdem zuvor mit mindestens 30 rpm getreten wurde (wer von Anfang an steht, hält nicht inne) | Schild |
| Rhythmus | die Kadenz im gleichmäßigen Takt pulst: vier Anstiegsflanken hintereinander (Ausschlag ≥ 8 rpm über dem letzten Tiefpunkt, Tiefpunkt ≥ 30 rpm), Abstände 1,2–4 s, jeder höchstens 25 % vom mittleren entfernt; weitertreten im Takt: wieder nach drei weiteren Pulsen | Kombo |

| Fähigkeit | Wirkung | Dauer | Abklingzeit |
|---|---|---|---|
| Windböe | „Rückenwind“: Fortschritt mit Kadenz in der Zone ×3 (Faktor + 2,0) | 2,5 s | 18 s |
| Fokus | „Konzentration“: derselbe Fortschritt ×1,5 (Faktor + 0,5) | 8 s | 25 s |
| Schild | „Durchatmen“: jeder Schritt, der den Fortschritt senken würde (Balken sinkt, Verfolger holt auf), wird zurückgenommen; Gewinne und die Zeit laufen weiter | 6 s | 30 s |
| Kombo | Punkte sofort: 30 × (1 + Zahl der anderen Fähigkeiten, die in den letzten 20 s ausgelöst wurden) | – | 15 s |

**Wirkung:** Eine Fähigkeit löst nur aus, wenn sie **bereit** ist (Abklingzeit abgelaufen) und **eine Herausforderung läuft** –
davor, danach und in Pausen passiert nichts, ein Muster ohne laufende Herausforderung verfällt und die Fähigkeit bleibt bereit. Windböe und Fokus
addieren sich auf den Fortschrittsfaktor des Bausteins (`progress_factor`; die Ausrüstung #49 liefert den Ausgangswert: mit +20 %
Fortschritt 1,2, mit Windböe 3,2) und verschwinden nach der Wirkdauer wieder. Der Faktor wirkt wie bei der Ausrüstung nur
dort, wo schon Kadenz etwas ergibt: Zone halten (Zeit in der Zone), Durchbruch (Füllen über der Schwelle), Jagd (Abstand über
der Schwelle), Takt-Tore (jeder Treffer zählt mehrfach), Sammeln (Magnetradius). **Ohne Kadenz dort hilft keine Fähigkeit** –
kein Fortschritt, und die Zielzone und der Kadenzbereich bleiben unberührt (kein Eingriff in `zone()`). Das Schild kostet das
Tempo, das das Innehalten selbst kostet (zwei Sekunden ohne Treten, das Fahrmodell läuft aus); der Schritt, in dem ein Baustein
schon endet, lässt sich nicht mehr zurücknehmen, und das Zeitfenster läuft unter dem Schild weiter ab. Eine Windböe, die
beim Wechsel der Herausforderung noch wirkt, gilt für die nächste weiter. Die Werte sind Daten (`Abilities.DEFS`); je Lauf liegt
eine Kopie in `abilities.defs` (Wirkung `power`, Abklingzeit `cooldown_s`, Dauer `duration_s`), die die Talente und die legendäre
Beute (#53, siehe „Talente“) beim Start des Laufs aus einem `run_hook` heraus verändern.

**Anzeige:** Eine Leiste mit vier Plaketten rechts über dem unteren Panel des HUDs (`src/ability_hud.gd`, als Kind unter dem
HUD; `ride_hud.gd` weiß davon nichts): Name und Zustand – grün „Antritt · bereit“ (mit dem auslösenden Muster), gold „aktiv · 3 s“
(Restzeit der Wirkung), grau die Abklingzeit „14 s“. Beim Auslösen blendet oben im Bild „Windböe ausgelöst“ ein (1,8 s), die Kombo
zeigt zusätzlich das Popup „+30 Kombo“. Die Leiste gibt es nur im laufenden Arcade-Lauf: in Rundfahrt, Training, Menü und
Ergebnis fehlt sie, und kein Muster löst etwas aus. Die Zusammenfassung nennt, was gewirkt hat („Fähigkeiten: Windböe 2× · Kombo 1×
(+30 Punkte)“; ohne Auslösung keine Zeile).

**Aufbau:** `ArcadeStage.EXTENSIONS` hat dafür eine Zeile (`src/ability_extension.gd`, `AbilityExtension`, erreichbar über
`AbilityExtension.of(game.arcade_stage)`): je Fahrschritt (`stepped`, nach `ArcadeRun.advance`) füttert sie die Muster mit
`cadence_raw` und lässt die Fähigkeiten (`src/abilities.gd`, `Abilities`, reine Logik) wirken; `main.gd` ist unberührt. Die
Erweiterung ist immer an. **Tests** mit konstanter Kadenz und exakten Fortschrittswerten (z. B. 90 rpm über viele Sekunden:
das Gleichmaß löst nach 10 s den Fokus aus) schalten sie auf ihren eigenen Gegenstand beschränkt ab – eine Zeile
`AbilityExtension.of(game.arcade_stage).enabled = false` in ihrem `_start_arcade` (so in `tests/test_arcade_ride.gd` und
`tests/test_arcade_rhythm_collect_ride.gd`; neue Ride-Tests dieser Art tun dasselbe). Das Zusammenspiel mit laufenden Bausteinen
prüfen `tests/test_abilities.gd` (Zone halten, Durchbruch, Jagd) und `tests/test_abilities_ride.gd` (echtes Spiel, Zone und Jagd).

**Simulator-Szenarien** (Stufe 1, 60–120 rpm; der Test erzwingt eine lange Herausforderung, sie laufen durch das echte Spiel):
*Antritt* (`antritt.toml`, aus #45: drei Antritte aus 80 rpm; die Windböe wird ausgelöst, die Plakette zeigt „aktiv“ und dann die
Abklingzeit, der Faktor im Baustein ist ×3, der erste Antritt vor dem Startpunkt verbraucht nichts), *Innehalten*
(`innehalten.toml`, zweimal 3 s Kadenz 0, am Ende 1,5 s: das Schild hält den Verfolger der Jagd auf Abstand, das kurze Absetzen
zählt nicht), *Gleichmaß* (`gleichmass.toml`: Stillstand, Anfahren, 12 s ruhig um 80 rpm: Fokus ×1,5 erst nach zehn ruhigen
Sekunden) und *Rhythmus* (`rhythmus.toml`: sechs Pulse im Takt von 3 s lösen die Kombo mit „+30 Kombo“ aus, die ungleichen Pulse
danach nicht). `SimProfile.to_script` bildet `cadence_raw` nicht ab (der Fake-Bus fällt auf `cadence` zurück); dass die Muster die
ungeglättete Kadenz lesen, prüft `test_patterns_read_the_unsmoothed_cadence` mit getrennten Werten. Tests der reinen Logik:
`tests/test_cadence_patterns.gd` (je Muster positiv und negativ, Rauschen, Anfahren aus dem Stand, Schwellen als Daten, die
Profile im Meldetakt 250 ms) und `tests/test_abilities.gd` (Wirkung nur mit Kadenz, nur in Herausforderungen, Abklingzeit, Schild,
Kombo-Kette, Daten, Zielzone unverändert).

**Mit echtem Gerät offen (#1):** Die Kadenz 0 steht in `cadence_raw` bei einem CSC-Sensor erst 2,5 s nach dem letzten Kurbelereignis
(Messung #45); das Innehalten wird dort entsprechend später erkannt als im Simulator. Die Schwellen sind noch nicht am Gerät kalibriert.

### Beute und Ausrüstung (#49)

Jede beendete Herausforderung im Arcade würfelt **Beute**: nach **geschafft** sicher, nach **verfehlt** nur mit der
Chance 0,5 × erreichter Fortschritt (knapp verfehlt gibt manchmal etwas, ohne Kadenz in der Zone bzw. über der Schwelle –
Fortschritt 0 – nie).
Ein Fund zeigt sich sofort: 18 m vor dem Fahrer steht eine **Lichtsäule** (16 m hoch, Bodenring, darüber schwebend und
drehend das Fundstück als Raute) in der **Farbe seiner Seltenheit**, bis sie 20 m hinter dem Fahrer liegt; über der
Bildmitte steigen **Zahlen-Popups** auf („+100“ für die Punkte in Gold, der Name des Fundes in Seltenheitsfarbe,
z. B. „Magischer Helm“) und blenden nach 1,8 s aus. Die **Zusammenfassung** nennt die Funde („Beute: Magischer Helm ·
Seltene Schuhe“); ins Inventar kommen sie am Fahrtende. In der Fahrt wird nichts verwaltet.

**Sechs Plätze** mit Hauptwert: Rahmen und Laufräder (Fortschritt in der Zone), Trikot (Punkte), Helm und Schuhe
(Zonenbreite), Talisman (Beute-Glück). Der Platz ist gleichverteilt; jedes Teil hat den Hauptwert seines Platzes und je
nach Seltenheit weitere, verschiedene Werte.

| Seltenheit | Farbe | Anteil | Werte | Stärke | Splitter |
|---|---|---|---|---|---|
| Gewöhnlich | weiß/grau | 60 % | 1 | × 1 | 1 |
| Magisch | blau | 28 % | 2 | × 1,5 | 3 |
| Selten | gelb | 10 % | 3 | × 2,2 | 8 |
| Legendär | orange | 2 % | 4 | × 3 | 20 |

| Wert | je Teil (gewöhnlich, × Stärke) | Obergrenze aller angelegten Teile | Wirkung |
|---|---|---|---|
| Zonenbreite | 1–2 rpm | 10 rpm | Zielzone breiter (je zur Hälfte unten und oben) – nachsichtiger |
| Fortschritt in der Zone | 3–6 % | 60 % | jede Sekunde **in der Zone** zählt mehr – wirkungsvoller |
| Punkte | 5–10 % | 100 % | mehr Punkte für eine geschaffte Herausforderung – lohnender |
| Beute-Glück | 5–10 % | 100 % | seltenere Funde: Gewicht der Seltenheit mit Rang r (0 = gewöhnlich) × (1 + Glück)^r |

**Ausrüstung ersetzt nie das Treten:** ohne Kadenz in der Zone (bei Durchbruch und Jagd: über der Schwelle, bei Sammeln: in der Rampe, bei Takt-Tore: im Fenster eines Schlags) passiert nichts – kein Fortschritt, keine Punkte, keine
Beute, mit Ausrüstung genauso wie ohne. Auch die verbreiterte Zone läuft durch den Wächter des Kadenzbereichs
(`Encounters.zone_for` → `CadenceRange.limit_zone`), liegt also nie außerhalb. Legendäre Teile haben zusätzlich einen
**Spezialeffekt** (`effect`, #53, siehe „Talente“): er verändert eine Fähigkeit, solange das Teil angelegt ist; die Werte der
Teile wirken wie bei allen anderen. Das Ausrüstungsmenü nennt den Effekt eines legendären Teils in der Liste („· Rückstoß“) und im Detail („Effekt: Rückstoß“ mit Beschreibung).

**Ausrüstung** (Startmenü **Fahren → Arcade → Ausrüstung**, `scenes/gear_menu.gd`) ist die einzige Stelle, an der Beute
verwaltet wird. Oben Splitter und Zahl der Teile; links die Teile nach Platz, darin die neuesten zuerst (Name in
Seltenheitsfarbe, Werte, angelegte mit „· angelegt“), rechts das gewählte Teil mit dem **Vergleich** gegen das angelegte
Teil desselben Platzes (je Wert besser grün, schlechter rot, sonst „gleich“), **Anlegen** und **Verwerten
(+n Splitter)** – angelegte Teile lassen sich nicht verwerten –, darunter „Angelegt je Platz“. Jede Änderung wird sofort
gespeichert. Splitter werden nur gesammelt (kein Handwerk). Bedienung mit Maus oder Tastatur (Pfeiltasten/Tab,
Enter/Leertaste); **Esc** oder **Zurück** führt auf die Seite „Arcade“.

**Am Fahrer:** Im Arcade-Lauf trägt der Fahrer die angelegten Teile in der Farbe ihrer Seltenheit – Rahmen, Felgen,
Trikot (Brustband dunkler), Helm (Streifen dunkler), Schuhe und den Talisman am Sattel. Jedes angelegte Teil überdeckt
die Garderobe nur an seinem Platz; Plätze ohne Teil zeigen die Garderobe.

**Getrennte Welten (ADR-0010):** Ausrüstung wirkt nur im Arcade-Lauf (`ArcadeRun.gear`); Rundfahrt und Training fahren
mit ihr identisch und zeigen nur die Garderobe. Logik in `src/loot.gd` (Daten und Würfel, mit Seed reproduzierbar) und
`src/inventory.gd` (Inventar im Spielstand), beides ohne Szene; die Beute würfelt ein eigener Würfel, die Planung der
Herausforderungen bleibt bei gleichem Seed unverändert. Tests: `tests/test_loot.gd` (Würfel, Inventar, Werte nur mit
Kadenz in der Zone), `tests/test_arcade_loot_ride.gd` (Simulator-Profile *perfekt in der Zone*: Beute mit Lichtsäule und
Popups; *knapp daneben*: keine – mit +6 rpm Zonenbreite geschafft; Menü).

Sichtprüfung: `view_probe.gd -- --hud --arcade` speichert zusätzlich die Lichtsäule mit Popups direkt nach dem Erfolg
(`loot_beam.png`); `--gear` legt im Spielstand (nur im Speicher) je Platz ein Beispielteil in allen Seltenheiten an und
legt weitere ins Inventar – mit `--title --gear` die Ausrüstung aus dem Startmenü (`gear.png`, ein Helm im Vergleich),
mit `--hud --arcade --gear` trägt der Fahrer sie im Arcade-Lauf, dazu die Nahaufnahmen `close_5_side.png` und
`close_5_rear.png`.

### Talente (#53)

Der Arcade hat ein eigenes **Arcade-Level**, getrennt vom **Fahrerlevel** (ADR-0010: das Fahrerlevel wächst mit gefahrenen
Kilometern und schaltet nur Kosmetik frei; vom Arcade-Level hängt keine Garderobe, Bestzeit, Medaille oder Ghost ab). Das
Arcade-Level wächst mit den **Punkten der Arcade-Fahrten**: Jede gespeicherte Fahrt zählt ihre Punkte zu `arcade.points_total`
im Spielstand (`ArcadeLevel`, `src/arcade_level.gd`; Punkte gibt es nur für geschaffte Herausforderungen mit Kadenz in der Zone –
ohne Kadenz kein Punkt, kein Level; Fahrten von vor #53 zählen nicht rückwirkend, und eine Fahrt wird nur einmal gezählt, auch bei
Rückkehr ins Menü oder erneutem Speichern). Level 1 gilt ab 0 Punkten, Level 2 ab 400; der Schritt von Level n zu n + 1 kostet
400 + 200 · (n − 1) Punkte (Level 3 ab 1000, Level 4 ab 1800 …, Höchstlevel 12 ab 15 400). Ab Level 2 gibt jedes Level
**einen Talentpunkt** (höchstens 11 bei 15 Knoten: der Baum füllt sich nie ganz – es sind Build-Entscheidungen). Das Ergebnis
einer Arcade-Fahrt nennt unter den Zeilen der Fähigkeiten das Arcade-Level, bei einem Aufstieg „neues Level!“ und die freien
Talentpunkte („Arcade-Level 2 – neues Level! · 1 Talentpunkt frei“), sonst die Punkte bis zum nächsten Level.

**Talentbaum** (Startmenü **Fahren → Arcade → Talente**, `scenes/talent_menu.gd`; die einzige Stelle, an der Punkte verteilt
werden – in der Fahrt nichts): oben Arcade-Level, freie und ausgegebene Talentpunkte und die Punkte bis zum nächsten Level; darunter
drei Äste nebeneinander mit je fünf Knoten, von der Wurzel abwärts. Ein Knoten kostet einen Talentpunkt und braucht seinen
Vorgänger im selben Ast; erlernte stehen grün, erlernbare weiß, gesperrte grau mit dem Grund („braucht …“, „kein Talentpunkt
frei“). **Zurücksetzen** gibt alle Punkte **kostenlos** zurück (kein Handwerk, keine Währung – der Baum lädt zum Ausprobieren
ein); jede Änderung wird sofort gespeichert. Bedienung mit Maus oder Tastatur (Pfeiltasten/Tab, Enter/Leertaste); **Esc** oder
**Zurück** führt auf die Seite „Arcade“. In kleinen Fenstern (1152×648) scrollen die Äste. Was der Stand von der Platte
nicht hergibt (unbekannte oder doppelte Knoten, Knoten ohne erlernten Vorgänger, mehr Knoten als Punkte), zählt nicht.

| Ast | Knoten (Voraussetzung) | Wirkung |
|---|---|---|
| Sprinter | Kräftiger Antritt | Windböe ×3,5 statt ×3 (Wirkung + 0,5) |
| | Kurze Pause (Kräftiger Antritt) | Windböe lädt 4 s schneller |
| | Wacher Antritt (Kräftiger Antritt) | Antritt schon bei +20 statt +25 rpm erkannt |
| | Langer Spurt (Kurze Pause) | Windböe wirkt 1 s länger |
| | Durchbruchskraft (Wacher Antritt) | +6 % Fortschritt in der Zone |
| Kletterer | Zäher Kletterer | +4 % Fortschritt in der Zone |
| | Tiefes Durchatmen (Zäher Kletterer) | Schild hält 2 s länger |
| | Ruhiger Puls (Zäher Kletterer) | Innehalten schon nach 1,5 statt 2 s erkannt |
| | Kurze Rast (Tiefes Durchatmen) | Schild lädt 6 s schneller |
| | Gipfelsammler (Ruhiger Puls) | +8 % Punkte |
| Ausdauer | Gleichmäßiger Tritt | Gleichmaß nach 8 statt 10 s erkannt |
| | Tiefer Fokus (Gleichmäßiger Tritt) | Fokus ×1,75 statt ×1,5 (Wirkung + 0,25) |
| | Breiter Tritt (Gleichmäßiger Tritt) | +2 rpm Zonenbreite |
| | Taktgefühl (Tiefer Fokus) | Kombo-Grundpunkte + 15 (45 statt 30) |
| | Glückspilz (Breiter Tritt) | +10 % Beute-Glück |

**Legendäre Effekte:** Der Würfel vergibt `effect` **nur bei legendären Teilen** (2 % der Funde), gleichverteilt aus fünf
Effekten (`Loot.EFFECTS`, Daten); alle anderen Teile behalten `""`. Ältere legendäre Teile ohne Effekt (oder mit unbekanntem
Eintrag) bleiben gültig und wirken nur mit ihren Werten. Ein Effekt wirkt nur, solange das Teil **angelegt** ist; derselbe
Effekt auf zwei angelegten Teilen zählt einmal.

| Effekt | Wirkung |
|---|---|
| Rückstoß | „Antritt wirft Gegner zurück“: löst die Windböe aus, rückt der Verfolger der **Jagd** um 15 % Abstand ab und füllt sich der Balken des **Durchbruchs** um 10 % – nur wenn die Kadenz in diesem Schritt über der Schwelle des Bausteins liegt und höchstens bis 95 % (der Erfolg bleibt dem Treten vorbehalten); andere Bausteine merken nichts; in einem Bosskampf oder einer Elite-Gruppe trifft er die laufende Phase (Nacharbeit #27); Rückmeldung „Rückstoß!“ |
| Tiefer Atem | Schild hält 4 s länger |
| Kombo-Ernte | Kombo-Grundpunkte verdoppelt (60 statt 30) |
| Im Fluss | Fokus doppelt so stark (×2,0 statt ×1,5; Wirkung + 1,0 statt + 0,5) und 4 s länger |
| Auf dem Sprung | Windböe lädt 8 s schneller (10 statt 18 s) |

**Wirkung im Lauf:** Beim Start eines Arcade-Laufs legt die Erweiterung `TalentArcade` (`src/talent_arcade.gd`) die erlernten
Talente, danach die Effekte der angelegten legendären Teile auf den Lauf (`BuildEffects`, `src/build_effects.gd`, reine Logik).
Jede Änderung ist Daten (`changes`) in einer von vier Formen: Wirkung, Dauer oder Abklingzeit einer Fähigkeit
(`abilities.defs`, `add` oder `mul`), eine Schwelle eines Kadenzmusters (`patterns.thresholds`), ein Ausrüstungswert des Laufs
(`run.gear`, gedeckelt durch die Obergrenze des Wertes) oder der Rückstoß. Abklingzeiten fallen nie unter 3 s, Schwellen nie
unter 1; Schwellen, die ein Lauf verschoben hat, stehen im nächsten Lauf wieder auf dem Standard. Die Standarddaten
(`Abilities.DEFS`, `CadencePatterns.THRESHOLDS`) bleiben unverändert. Der Hook läuft **nach** dem der Fähigkeiten (der setzt `defs`
beim Start zurück); darum hängt die Hauptszene die Erweiterung nach dem Aufbau der Bühne mit `attach` an – sie steht nicht in
`ArcadeStage.EXTENSIONS`, weil dort die Reihenfolge der Anmeldung zählt. Die Gutschrift der Punkte kommt über das Signal
`run_finished` der Bühne.

**Talente und Effekte ersetzen nie das Treten:** Sie verschieben nur Daten der Fähigkeiten (die selbst nur mit Kadenz in der Zone
wirken), Schwellen und Ausrüstungswerte – ohne Kadenz dort kein Fortschritt, keine Punkte, keine Beute. Die Zielzone liegt nie
außerhalb des Kadenzbereichs, auch nicht mit +Zonenbreite (Wächter `CadenceRange.limit_zone`). **Getrennte Welten (ADR-0010):**
Talente und Effekte wirken nur im Arcade-Lauf; Rundfahrt und Training fahren mit allen Talenten und Effekten identisch zu ohne,
und das Fahrerlevel bleibt allein bei den Kilometern.

Für die **Empfohlene Stärke** (#54) liefert `Talents.gear_bonus(save)` die Ausrüstungswerte der Talente im Format von
`Loot.modifiers`. Tests: `tests/test_talents.gd` (Arcade-Level, Baum, Zurücksetzen, Spielstand mit alten Ständen, jede Änderung
verändert Fähigkeiten, Schwellen oder Werte; Gegenproben ohne Kadenz und zur Zielzone; Würfel, Effekte, Rückstoß) und
`tests/test_talents_ride.gd` (echtes Spiel: Hook nach den Fähigkeiten, Simulator-Profil *Antritt* mit stärkerer Windböe und mit
Rückstoß der Jagd, Punkte der Fahrt zählen zum Arcade-Level und stehen im Ergebnis, Rundfahrt und Training unverändert,
Talentmenü samt Layout in 960×1040, 1920×1080 und 1152×648, Ausrüstungsmenü zeigt den Effekt).

### Balancing-Simulation (#55)

Eine Simulation ohne Grafik fährt Tausende Arcade-Läufe und schreibt einen Bericht, an dem die Werte der Daten (Stufen,
Herausforderungen, Beute) geprüft und nachjustiert werden (`src/balancing.gd`, Startskript `tools/balancing_sim.gd`). Sie
baut nichts nach: Jede Fahrt ist ein echter `ArcadeRun` auf dem echten Rundkurs (`Track` mit `IslandCourse`, seine Abschnitte,
die Bosse an ihren Orten, Standardbereich 60–120 rpm); Zonen, Schwellen, Stufen, Rundensteigerung, Elite-Gruppen, Würfe und
Beute kommen aus `Encounters`, `EliteGroups`, `ArcadeTiers`, `Loot` und den übrigen Modulen, das Tempo aus `RideModel`
(Standardwerte von `RideConfig`; Kadenz → Tempo → Strecke, mit der Steigung des Kurses). Die Werte bleiben in den Daten – die
Simulation liest sie nur, und was sie verändert, ändert das Spiel. Gefahren wird in Schritten von 0,5 s in und kurz vor
Herausforderungen, sonst 2 s.

Gestartet wird im Repo-Wurzelordner (Godot 4.4.1; nach neuen Skripten einmal `--import`, wie bei den Tests):

    godot --headless --path games/island-ride -s res://tools/balancing_sim.gd -- --runs=1000 --gear-runs=300 --careers=100 --seed=1

Das dauert rund 6 Minuten auf einem Kern. Optionen (alle optional): `--runs=N` Fahrten je Kadenzverlauf und Stufe ohne
Ausrüstung (Standard 200), `--gear-runs=N` dasselbe mit der Ausrüstung der Empfohlenen Stärke (100), `--careers=N`
Laufbahnen je Kadenzverlauf (30), `--career-max-runs=N` (120), `--seed=S` (1), `--ride-minutes=M` Länge einer Fahrt (45),
`--out=<Pfad>` (Standard `docs/balancing/arcade-balancing.md`), `--commit=`, `--date=` und `--note=` für den Kopf des
Berichts, `--appendix=<Datei>` hängt Markdown an (Auffälligkeiten und Nachjustierung). **Reproduzierbar:** Jede Fahrt
bekommt aus Seed, Kadenzverlauf, Stufe, Ausrüstungsvariante und Nummer einen eigenen Seed; gleicher Seed und gleiche
Optionen ergeben denselben Bericht, Byte für Byte, ein anderer Seed einen anderen (Kopf: Seed, Befehl, Stand, Datum). Die
Simulation schreibt nur den Bericht – nie in `user://`, der Spielstand der Laufbahnen liegt im Speicher.

**Kadenzverläufe** (Daten in `Balancing.PROFILES`, erfunden und beschrieben, keine Messung): Die Kadenz folgt einer
Grundkadenz mit langsamer Schwankung, Rauschen und Ermüdung; vor und in einer Herausforderung stellt sich der Fahrer auf die
Zone ein (mit Verzögerung), ist aber nur einen Teil der Zeit „bei der Sache“.

| Verlauf | Grundkadenz | Bei der Sache | Folgt der Zone in | Höchstens | Ermüdung |
|---|---|---|---|---|---|
| Einsteiger | 74 rpm (±7) | 70 % | 3,5 s | 118 rpm | −10 rpm/h |
| Trainierter | 88 rpm (±4) | 90 % | 1,5 s | 124 rpm | −4 rpm/h |
| Sprinter | 92 rpm (±6), Spitzen +22 rpm für 6 s alle ~90 s | 75 % | 0,9 s | 140 rpm | −8 rpm/h |

**Nicht simuliert** sind Fähigkeiten und legendäre Effekte: Sie brauchen die ungeglättete Kadenz mit gezielten Gesten (Antritt,
Gleichmaß, Innehalten, Rhythmus), die ein erfundener Verlauf nur vortäuschen könnte. Alle Zahlen sind deshalb eine Untergrenze (Fähigkeiten verstärken nur den Fortschritt
mit Kadenz in der Zone). Wer nicht tritt, bekommt auch hier nichts, mit Ausrüstung ebenso wenig. Absolut zählen die Quoten
nur unter diesen Annahmen; belastbar sind Verhältnisse und Brüche (eine Herausforderung, die gegenüber ihrer Schwester oder
den Nachbarstufen abbricht, eine Stufe, die niemand erreicht).

**Der Bericht** (Markdown, Standard `docs/balancing/arcade-balancing.md`) nennt je Kadenzverlauf und Stufe: die
**Häufigkeit je Seltenheit** (Funde, Funde je Stunde), die **Erfolgsquote je Herausforderung und Stufe** (jede Herausforderung
des Pools, die Elite-Gruppen *Champions* und *Seltene*, die drei Bosse, alle zusammen, Elite-Anteil) und der Boss-Phasen, die
**Dauer je Boss** (Sieg und Entkommen, Median und 90 %-Quantil in Sekunden) sowie die Erfolgsquote mit Ausrüstung der
Empfohlenen Stärke; dazu die Zielzonen und Schwellen je Stufe aus den Daten und die **Erreichbarkeit der Stufen**:
Laufbahnen (neuer Spielstand im Speicher, immer auf der höchsten freien Stufe gefahren, bessere Teile angelegt, Rest
verwertet, Talente und Arcade-Level wachsen mit) mit der Zahl der Läufe und Stunden bis zur Freischaltung von Stufe 4–6, bis
Stufe 6 abgeschlossen ist und bis die Ausrüstung die Empfohlene Stärke erreicht.

**Nachjustiert** wurde nach vorab festgelegten Schwellen nur eine Auffälligkeit: *Spurt* (`durchbruch_spurt`) lag mit
`threshold_at` 0,9 bei 114 rpm und erreichte ab Stufe 4 mit Hub das obere Ende des Bereichs (120 rpm – dort genügt nur das
Maximum selbst); der Trainierte schaffte ihn auf Stufe 1–6 zu 92 / 85 / 49 / 34 / 33 / 29 %, die Schwester *Zugbrücke* zu
91–93 %. Mit 0,85 (111 rpm auf Stufe 1, 118 rpm auf Stufe 6) sind es 94 / 93 / 89 / 89 / 86 / 84 %. Geändert ist allein dieser
Wert in `src/challenges/breakthrough_challenges.gd`; der Wächter des Kadenzbereichs und alle Prüfungen blieben, wie sie waren.
Alles, was eine Frage des Spielgefühls ist (Länge der Bosse, Takt-Tore bei konstanter Kadenz, Elite-Chance je Stufe, Tempo von
Beute und Freischalten, Sammeln für Einsteiger und auf *Ufer*, Empfehlung oder Pflicht), steht als offene Frage im Anhang
des Berichts und ist nicht entschieden. Der Bericht vom Datenstand davor liegt als `docs/balancing/arcade-balancing-vorher.md`
bei, die Auffälligkeiten und Fragen in `arcade-balancing-notes.md` (Anhang des Berichts).

Tests: `tests/test_balancing.gd` (Kadenzverläufe als Daten im Standardbereich, Kadenz nie unter 0 und über der Spitze, stabile
und verschiedene Seeds, die Ausrüstung der Variante „empfohlen“ ergibt genau die Empfohlene Stärke, Rundkurs mit den Abschnitten
der Bosse, Fahrt mit Seed reproduzierbar und mit aufgezeichneten Herausforderungen, ohne Treten nichts – auch mit Ausrüstung,
Bericht reproduzierbar und vom Seed abhängig, Bericht nennt alle Kennzahlen, Laufbahn im Speicher, Quantile); kleine Läufe, die
volle Simulation startet das Skript. Die Gegenprobe des Wächters (`tests/test_arcade_tiers.gd`) hält seit #55 eine eigene Kopie
von *Spurt* mit 0,9 – eine Definition, die ohne Wächter über den Bereich hinausschösse –, statt vom Pool abzuhängen; ihre
Prüfungen sind unverändert.

### Ton (#44)

Dezent und standardmäßig leise (Lautstärke 30 %, jeder Klang zusätzlich gedämpft), auf einem eigenen Audio-Bus
„Spiel“ – Lautstärke und Aus-Schalter stehen im Einstellungsmenü und in `settings.cfg [sound]`. Alle Klänge entstehen
**prozedural** im Spiel (`src/sound_synth.gd`, SoundSynth), es gibt keine Klangdateien; erzeugt wird einmal beim Start,
ein Klang je Frame. Was wann wie laut klingt, rechnet `RideSound.levels()` (`src/ride_sound.gd`) aus Tempo, Kadenz, Ort,
Wetter und Tageslicht; Hörer ist die Kamera. Ton ist nur Ausgabe (ADR-0010).

| Klang | Wann und wo | Erzeugung |
|---|---|---|
| Fahrtwind | beim Fahren, ab 5 km/h, voll und heller (Abspieltempo 0,8 → 1,35) ab 45 km/h | Rauschen, Tiefpass, plus ein Band um ~600 Hz mit langsam schwankender Stärke (Böen); 3-s-Schleife, 11 kHz |
| Freilauf | Kadenz 0 und Tempo ≥ 1 km/h; 12 Klicks je Radumdrehung | ein Klick (Rauschstoß 1,2 ms + 3,2 kHz, 2 ms) je 1/20 s; das Abspieltempo setzt die Klicks je Sekunde |
| Meer | bis 25 m vom Wasser voll, ab 220 m still (Messringe um den Hörer im Höhenfeld) | braunes Rauschen (Brandung) und Zischen der auslaufenden Welle, zwei Wellen je 6-s-Schleife, 11 kHz |
| Regen | nach der Regenstärke des Wetters, wie die sichtbaren Tropfen | hochpassgefiltertes Rauschen plus vereinzelte Tropfen (abklingende 3,2-kHz-Klicks); 2-s-Schleife |
| Möwen | an den drei Möwenschwärmen (Hafen, Leuchtturm, Westküste), voll bis 40 m, still ab 260 m, Ruf alle 3–9 s; nicht nachts, nicht im Regen (dieselbe Regel wie die sichtbaren Vögel) | zwei Rufe „kjau“: Grundton gleitet 1150 → 1500 → 900 Hz, Obertöne 2–4, Vibrato 24 Hz |
| Schafglocken | an jeder Schafherde (`World/Fauna/Glocken/Herde<n>`), voll bis 15 m, still ab 110 m, alle 1,5–5 s | Blechglocke: Teiltöne 1150 Hz × 1 · 2,31 · 3,89 · 5,6, Abklingen 0,35–0,1 s, Anschlag |
| Dorfglocke | am Kirchturm im Bergdorf, voll bis 60 m, still ab 520 m; nach 6 s in Hörweite ein Geläut aus 5 Schlägen (zwei Glocken im Wechsel), dann alle 60–120 s | Glocke: Unterton 0,5, Prim 1, kleine Terz 1,19, Quinte 1,5, Oktave 2, 2,5, 3 × 220 Hz, Abklingen bis 3,5 s |
| UI | Klick je Knopfdruck und beim Öffnen/Schließen der Einstellungen; Doppelton je sichtbarer Einblendung (Bestzeit, Segment, Erfolg, Level); weicher Ton, wenn im Training eine Ansage erscheint und beim Phasenwechsel | Klick: Sinus 1000 → 700 Hz, 30 ms; Doppelton E6 + A6; Ansage A5 mit Oktave |

Im Browser startet der Ton erst nach der ersten Nutzergeste (Regel der Browser); ohne Audio-Gerät (oder wenn die
Audio-Worklets nicht laden) läuft das Spiel gleich, nur still.

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
| `[camera] behind_m` | `5.5` | Perspektive *Weit* (#59): Abstand hinter dem Fahrer entlang der Strecke (m) – kleiner = Fahrer größer im Bild; Nah und Verfolger sind fest (`src/camera_views.gd`) |
| `[camera] height_m` | `2.4` | Perspektive *Weit*: Kamerahöhe über der Strecke (m); mindestens 1,5 m über dem Gelände |
| `[camera] look_ahead_m` | `10.0` | alle Perspektiven: Blickpunkt so viele Meter voraus auf der Strecke |
| `[camera] look_height_m` | `1.2` | alle Perspektiven: Höhe des Blickpunkts über der Strecke (m) |
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
setzt dieselben Optionen, einen Pre-Run-Hook (`tests/support/pre_run_isolation.gd`, Testisolation, siehe unten) und
einen Post-Run-Hook (`tests/support/post_run_check.gd`), der den Lauf
fehlschlagen lässt, wenn ein `test_*.gd` nicht ladbar ist (GUT allein überspringt es nur mit Warnung).
Einzelnes Skript: zusätzlich `-gselect=test_bus_client`. Die Tests brauchen keine Bridge und
benutzen Ports ab 18765 – nie den Bus-Port 8765.

**Testisolation (#62, `tests/support/test_isolation.gd`):** Kein Test schreibt in das echte `user://` (Spielstand,
Einstellungen, Gelände-Cache). Testdateien legen Tests über `TestIsolation.path("test_….json")` an, nicht unter
`user://`; sie liegen unter `.godot/test_user/<n>/` (git-ignoriert, je Worktree). Ein Wächter in den GUT-Hooks
(`.gutconfig.json`: `tests/support/pre_run_isolation.gd` hält das echte `user://` vor dem Lauf fest,
`post_run_check.gd` vergleicht danach) lässt den Lauf scheitern, sobald sich dort etwas ändert – außer dem, was die
Engine selbst schreibt (`logs/`, `.recovery_mode_lock`, `shader_cache/`, `vulkan/`, `objectdb_snapshots/` – etwa wenn
gleichzeitig das Spiel oder `view_probe` rendert). Wer während eines Testlaufs spielt und dabei speichert, lässt den
Lauf ebenfalls scheitern. **Mehrere Läufe gleichzeitig** (z. B. je Worktree): jedem Lauf eine eigene Zahl
`VSPIN_PORT_BASE=n` (0–466) geben – Fake-Bus ab Port 18765 + 100·n, eigenes Testverzeichnis; ohne Variable gilt
n = 0. Ein ungültiger Wert bricht den Lauf ab. Die Bridge-Tests nutzen denselben Wert (`bridge/README.md`, „Testen“).

```
VSPIN_PORT_BASE=2 godot --headless --path games/island-ride -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

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
- `tests/support/test_isolation.gd` (`TestIsolation`): `path(name)` für jede Datei, die ein Test schreibt (statt
  `user://`), `first_test_port()` für feste Testports (`TestIsolation.first_test_port() + 50`), `probe_bus_url()` für
  Prüfhilfen gegen die echte Bridge.

Drehbuch = Array von Schritten, `at` = Sekunden ab Verbindungsaufbau des Clients; jede Verbindung
spielt von vorn (so lässt sich auch Reconnect prüfen):

```json
[
  {"at": 0.0, "send": {"v": 0, "type": "status", "t_ms": 0, "state": "connected", "source": "sim", "capabilities": ["CADENCE"]}},
  {"at": 0.25, "send": {"v": 0, "type": "telemetry", "t_ms": 250, "cadence": 90.0, "speed_kmh": null, "power_w": null, "power_estimated": null, "heart_rate": null}},
  {"at": 2.0, "close": true}
]
```

Simulator-Profile der Bridge als Drehbuch (#46): `SimProfile.to_script(SimProfile.load_toml(SimProfile.path(
"arcade/zone_perfekt.toml")))` (`tests/support/sim_profile.gd`) – derselbe Kadenzverlauf, mit `stale`/`disconnected`
wie von der Bridge. Mit `bus.manual_clock_ms = 0` läuft das Drehbuch nicht in Echtzeit, sondern so, wie der Test die Uhr
vorrückt – gleichauf mit einer Hauptszene, die er in festen Schritten fährt (`tests/test_arcade_ride.gd`).

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

`tools/e2e.sh` startet je Kadenz die echte Bridge mit Simulator (`--sim-cadence N`, Port 8765 bzw. 8765 + n
muss frei sein), fährt das Spiel headless (`tools/e2e_probe.gd`) und vergleicht die Geschwindigkeiten:

```
GODOT=godot PYTHON=python games/island-ride/tools/e2e.sh 60 90
```

Mit gesetztem `VSPIN_PORT_BASE=n` fahren `e2e.sh`, `e2e_probe.gd` und `view_probe.gd` gegen Port 8765 + n (statt
`config.cfg [bus] url`) – parallel zu anderen Läufen und ohne die Bridge des Spielers; `e2e.sh` startet die Bridge
selbst mit `--port`, beim `set_grade`-Handtest die Bridge entsprechend mit `vspin-bridge … --port <8765+n>` starten.
Den Gelände-Cache legen die Prüfhilfen nach `.godot/test_user/<n>/`. Ein ungültiger Wert bricht auch die Prüfhilfen mit
Exit-Code 1 ab, statt still auf 8765 zu fahren (Nacharbeit #27).

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
src/ride_hud.gd         RideHud: Anzeige der Werte, Rundenfortschritt, readout(); Layout von Hinweis/Debug; Zahlen-Popups (#49)
src/hud_gauge.gd        HudGauge: Kadenz-Bogen · src/hud_grade_icon.gd HudGradeIcon: Steigungskeil
src/hud_profile.gd      HudProfile: Höhenprofil mit Marker (profile_point() als reine Rechnung)
src/hud_minimap.gd      HudMinimap: Inselkarte mit Strecke, Landmarken, Fahrer-Pfeil (map_point() als reine Rechnung)
src/bus_client.gd       BusClient: verbinden/reconnecten (mit Verbindungs-Timeout), status/telemetry parsen (`cadence` geglättet für HUD/Fahrmodell, `cadence_raw` ungeglättet für Kadenzmuster, #45), send_message
src/ride_stats.gd       RideStats: Fahrzeit, Strecke, Ø Kadenz, Ø Tempo (ohne Pausen) – reine Logik
src/lap_timing.gd       LapTiming: Rundenwertung – Rundenzeiten, Ziel nach n Runden oder endlos, Bestzeit, Ghost-Aufzeichnung – reine Logik
src/segment_timing.gd   SegmentTiming: Segmentzeiten (Live-Zeit, gewertete Segmente, Segment-Bestzeit) – reine Logik
src/ghost.gd            Ghost: Runde als Strecke über Zeit – aufzeichnen, abspielen, Abstand in s – reine Logik
src/training.gd         Training: Einheit laden, Ablauf (Phase, Restzeit, Ansage), Bewertung der Zielkadenz – reine Logik
src/zone_bar.gd         ZoneBar: Zonenbalken – Zielbereich, Wert als Marke, Zustand in Farbe und Form (#58)
src/gate_placement.gd   GatePlacement: Lage eines zeitgebundenen Tors aus Restzeit und Tempo, Festsetzen – reine Logik (#58)
src/course_gate.gd      CourseGate: Start- und Zieltor über der Straße, an einer Fahrtposition gestellt (#58)
src/challenge_block.gd  ChallengeBlock: Baustein einer Herausforderung – update(Kadenz, Zeit) → Fortschritt, Zustand; Haken loot_progress, score_caption (#46, #47)
src/zone_hold.gd        ZoneHold: Baustein „Zone halten“ – reine Logik (#46)
src/breakthrough.gd     Breakthrough: Baustein „Durchbruch“ – Balken über einer Schwelle füllen, darunter langsam sinkend – reine Logik (#47)
src/chase.gd            Chase: Baustein „Jagd“ – Verfolger abhängen (Abstand wächst über, schrumpft unter der Schwelle) – reine Logik (#47)
src/rhythm_gates.gd     RhythmGates: Baustein „Takt-Tore“ – Taktschläge treffen, wenn die Kadenz im Zeitfenster in der Zone liegt – reine Logik (#48)
src/collect.gd          Collect: Baustein „Sammeln“ – die Kadenz bestimmt den Magnetradius, Objekte im Radius werden eingesammelt – reine Logik (#48)
src/boss_fight.gd       BossFight: Bosskampf – Phasen aus vorhandenen Bausteinen nacheinander, Lebensbalken, besiegt oder entkommen – reine Logik (#51)
src/elite_groups.gd     EliteGroups: Elite-Gruppen als Daten – Elite-Stufen (Champions, Seltene), Eigenschaften je Bausteintyp, Gefolge, Würfel – reine Logik (#52)
src/elite_group.gd      EliteGroup: Elite-Gruppe – Anführer und Gefolge als Phasen (wie BossFight), wandernde Zone durch den Wächter – reine Logik (#52)
src/encounters.gd       Encounters: Herausforderungen (Zone, Schwelle), Würfeln, Bau der Bausteine mit Wächter des Kadenzbereichs; die Daten je Typ liegen in src/challenges/ (#46, #47, #63)
src/encounter_registry.gd EncounterRegistry: Bausteintypen des Arcade – eine Zeile je Typ, Reihenfolge = Würfel-Pool (#63)
src/challenges/         Herausforderungen als Daten und Bauanleitung je Bausteintyp: zone_hold_, breakthrough_, chase_, rhythm_gates_, collect_challenges.gd (#63, verschoben aus encounters.gd; #48); boss_challenges.gd: Bosse als Phasen an festen Orten (#51); elite_challenges.gd: Typ der Elite-Gruppen (#52)
src/arcade_tiers.gd     ArcadeTiers: Stufen als Daten (Zonenbreite, Dauer, Boss-Faktor, Punkte, Beute-Qualität, Empfohlene Stärke), Rundensteigerung, Freischalten und Auswahl im Spielstand, eigene Stärke – reine Logik (#46, #54)
src/cadence_range.gd    CadenceRange: persönlicher Kadenzbereich, begrenzt jede Zielzone (limit_zone) (#46)
src/arcade_run.gd       ArcadeRun: Arcade-Lauf – Herausforderungen je Abschnitt und Runde, Elite-Gruppen mit eigenem Würfel, Bosse an festen Orten, Rundensteigerung, Punkte, Beute, Ausrüstung, Zusammenfassung (#46, #49, #51, #52, #54)
src/arcade_stage.gd     ArcadeStage: Bühne des Arcade-Laufs – Lauf, HUD-Anbindung, Tore, Requisiten, Beute-Anzeige, Zusammenfassung, Signale, Hooks, Erweiterungen (#63)
src/arcade_prop.gd      ArcadeProp: Basis der Darstellungen je Bausteintyp (nur Anzeige, ADR-0010), eingetragen in ArcadeStage.PROPS (#63)
src/breakthrough_prop.gd BreakthroughProp: Darstellung des Durchbruchs – Zugbrücke statt Zieltor (#47, #63)
src/chase_prop.gd       ChaseProp: Darstellung der Jagd – Verfolger hinter dem Fahrer (#47, #63)
src/rhythm_gates_prop.gd RhythmGatesProp: Darstellung der Takt-Tore – ein Tor je Schlag auf der Straße, grün oder orange nach Treffer oder Verpasst, statt des Zieltors (#48)
src/collect_prop.gd     CollectProp: Darstellung des Sammelns – Kristalle auf und neben der Straße, Magnetring um den Fahrer (#48)
src/boss_prop.gd        BossProp: Darstellung der Bosse – Gestalt voraus statt des Zieltors, Lebensbalken im HUD (#51)
src/boss_figure.gd      BossFigure: Gestalten der Bosse aus Grundkörpern – Tramuntana (Sturmgeist), Drac de na Coca (Drache), Dimonis (drei Teufel); kleiner mit sinkendem Lebensbalken, besiegt oder entkommen (#51)
src/boss_bar.gd         BossBar: Lebensbalken eines Bosses oben im HUD – Name, Balken, laufende Phase mit Ziel und Restzeit, Ergebnis des Kampfes (#51)
src/elite_prop.gd       EliteProp: Darstellung der Elite-Gruppen – reicht die Phasen an die Darstellung ihres Bausteins weiter, Standarte und Schild (#52)
src/elite_banner.gd     EliteBanner: Elite-Standarte aus Grundkörpern in der Farbe der Elite-Stufe mit Stufe, Herausforderung und Eigenschaften (#52)
src/elite_badge.gd      EliteBadge: Elite-Schild oben im HUD – Ankündigung, Phase mit Ziel, Ergebnis (#52)
src/timed_markers.gd    TimedMarkers: Lage zeitgebundener Markierungen (Takt-Tore, Sammelobjekte) aus Fahrtposition, Restzeit und gefahrenem Tempo über GatePlacement (#48)
src/loot.gd             Loot: Beute – Plätze, Seltenheiten, Werte als Daten, Würfel, Vergleich, Modifikatoren, Aussehen – Spezialeffekte legendärer Teile – reine Logik (#49, #53)
src/inventory.gd        Inventory: Inventar im Spielstand – ablegen, anlegen, vergleichen, zu Splittern verwerten – reine Logik (#49)
src/arcade_level.gd     ArcadeLevel: Arcade-Level aus den Punkten der Arcade-Fahrten (getrennt vom Fahrerlevel), Talentpunkte – reine Logik (#53)
src/talents.gd          Talents: Talentbaum mit 15 Knoten in drei Ästen als Daten, Erlernen, Zurücksetzen, Ausrüstungswerte für die Empfohlene Stärke – reine Logik (#53)
src/build_effects.gd    BuildEffects: Wirkung von Talenten und legendären Effekten auf Fähigkeiten, Schwellen, Ausrüstungswerte, Rückstoß – reine Logik (#53)
src/talent_arcade.gd    TalentArcade: Erweiterung der Arcade-Bühne (von `main.gd` angehängt) – Talente und Effekte beim Laufstart, Rückstoß, Punkte zum Arcade-Level (#53)
src/loot_beam.gd        LootBeam: Lichtsäule eines Fundes in Seltenheitsfarbe, an einer Fahrtposition gestellt (#49)
src/drawbridge.gd       Drawbridge: Zugbrücke des Durchbruchs – Türme und Klappe aus Quadern, senkt sich mit dem Balken, an einer Fahrtposition gestellt (#47)
src/pursuer.gd          Pursuer: Verfolger der Jagd (Hund aus Grundkörpern) hinter dem Fahrer, Abstand folgt der Jagd (#47)
src/cadence_patterns.gd CadencePatterns: Kadenzmuster Antritt, Gleichmaß, Innehalten, Rhythmus aus der ungeglätteten Kadenz, Schwellen als Daten – reine Logik (#50)
src/abilities.gd        Abilities: Fähigkeiten Windböe, Fokus, Schild, Kombo – Auslösung durch Muster, Abklingzeit, Wirkung auf den laufenden Baustein – reine Logik (#50)
src/ability_extension.gd AbilityExtension: Erweiterung der Arcade-Bühne (`ArcadeStage.EXTENSIONS`) – füttert Muster und Fähigkeiten je Fahrschritt, Anzeige, Zusammenfassungszeile (#50)
src/tier_arcade.gd      TierArcade: Erweiterung der Arcade-Bühne (`ArcadeStage.EXTENSIONS`) – Hinweis beim Rundenwechsel, besiegte Bosse eintragen und die nächste Stufe freischalten, Zusammenfassungszeilen (#54)
src/balancing.gd        Balancing: Simulation des Arcade-Modus ohne Grafik – Kadenzverläufe (Einsteiger, Trainierter, Sprinter) als Daten, Läufe und Laufbahnen über die echten Module, Bericht als Markdown – reine Logik (#55)
src/ability_hud.gd      AbilityHud: Leiste „bereit / aktiv / Abklingzeit“ und Einblendung „… ausgelöst“ unter dem HUD (#50)
trainings/              Trainingseinheiten als Dateien (JSON): Intervalle kurz, Pyramide, Tempo-Blöcke
src/medals.gd           Medals: Medaillen-Schwellen aus dem Fahrmodell (70/85/95 rpm), Medaille einer Zeit – reine Logik
src/grade_reporter.gd   GradeReporter: wann `set_grade` gesendet wird (Schwelle, Drosselung) – reine Logik
src/ride_model.gd       RideModel: reine Logik (Kadenz, Steigung, Δt, Konfig → Geschwindigkeit, Position)
src/rider_motion.gd     RiderMotion: Kurbel-/Radwinkel, Schräglage, Vorbeuge, Glieder-IK – reine Logik
src/rider_model.gd      RiderModel: Fahrer und Rennrad aus Grundkörpern, Pose aus RiderMotion; Garderobe und Arcade-Ausrüstung mit Talisman (#36, #49)
src/ride_config.gd      RideConfig: liest config.cfg
src/graphics_settings.gd GraphicsSettings: Grafik-/Fenstereinstellungen, Tageszeit/Wetter (user://settings.cfg), Anwenden, Fensterhälften
scenes/settings_menu.*  Menü „Grafik und Fenster“ (F2, F11), von der Hauptszene eingehängt
scenes/start_menu.*     Startmenü: Titel, Fahren/Fahrtenbuch/Garderobe/Einstellungen/Beenden, Rundfahrt-, Training- und Arcade-Auswahl (mit „Ausrüstung“, „Talente“, Arcade-Level, gesperrten Stufen und Empfohlener Stärke), Radstatus (#30, #31, #37, #46, #49, #53, #54)
scenes/gear_menu.gd     Ausrüstung: Inventar der Beute mit Vergleich, Anlegen und Verwerten, Effekt legendärer Teile, aus „Fahren → Arcade“ (#49, #53)
scenes/talent_menu.gd   Talente: Talentbaum mit drei Ästen, Erlernen, kostenloses Zurücksetzen, Arcade-Level, aus „Fahren → Arcade“ (#53)
scenes/wardrobe.gd      Garderobe: Trikot, Radfarbe, Helm mit Vorschau (SubViewport), gesperrte mit Level (#36)
src/wardrobe.gd         Wardrobe: Teile und Farben, Auswahl prüfen und wählen, Standard je Kategorie – reine Logik
src/save_game.gd        SaveGame: Spielstand (user://savegame.json) – versioniert, Profilschlüssel, Fahrten, Bestzeiten, Segment-Bestzeiten, Medaillen, Ghosts, Erfolge, Garderobe, Kamera, Arcade, Hochstufung
src/camera_views.gd     CameraViews: Kameraperspektiven Nah/Verfolger/Weit als Daten, Durchblättern, Auswahl im Spielstand (#59) – reine Logik
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
src/ride_sound.gd       RideSound: Ton – Pegel aus Tempo, Ort, Wetter, Tageslicht (levels() als reine Rechnung), Bus „Spiel“, Auslöser (#44)
src/sound_synth.gd      SoundSynth: alle Klänge prozedural als AudioStreamWAV (Rauschen, Filter, Teiltöne), keine Dateien (#44)
src/shaders/            Wind (Vegetation), Meer (Wellen, Flachwasser, Brandung), Lichtkegel, Leuchtpunkte, Geschwindigkeitslinien
src/graybox_track.gd    GrayboxTrack: Rundkurs ~900 m, flach → +6 % → Kuppe → −6 % → flach (`[world] track="graybox"`)
tests/                  GUT-Tests, support/ (Fake-Bus, Bridge-Profile als Drehbuch, Basisklasse, Testisolation und Wächter, Hooks), fixtures/
tools/                  E2E-Prüfhilfe gegen die echte Bridge, Sichtprüfung/fps (view_probe.gd), Fenstermodi (window_probe.gd), Balancing-Simulation (balancing_sim.gd, #55)
addons/gut/             GUT 9.4.0 (MIT, Lizenz in addons/gut/LICENSE.md)
assets/kenney/          Low-Poly-Modelle (CC0) für alle Stationen
icon.svg / icon.ico     VSpin-Symbol (Faltband mit Schattenfalte): Projekt-, Fenster- und Browser-Symbol; .ico für Windows
ASSETS.md               Asset-Nachweis und Lizenzregel
```

Noch nicht enthalten: Terrain3D (ADR-0006 Nachtrag).
