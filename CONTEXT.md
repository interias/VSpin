# VSPIN – Kontext & Glossar

Lebendes Dokument. Begriffe, die im Projekt eine feste Bedeutung haben.
Entscheidungen stehen als ADRs unter [`docs/adr/`](docs/adr/).

## Ausgangslage

- **Gerät:** Wenoker JC312 Spinning-Bike, Bluetooth LE, laut Hersteller Zwift/Kinomap-kompatibel.
- **Widerstand:** manuell per Drehknopf (Magnetbremse), keine elektronische Steuerung.
- **Host:** Windows-PC mit USB-Bluetooth-Dongle.
- **Protokoll:** noch unbekannt – vermutlich FTMS oder CSC; Verifikation per nRF-Connect-Dump.

## Glossar

| Begriff | Bedeutung |
|---|---|
| **JC312** | Das konkrete Indoor-Bike (Wenoker JC312). |
| **Telemetrie** | Vom Rad gelieferte Messwerte: Kadenz, Geschwindigkeit, ggf. Leistung. |
| **Kadenz** | Kurbelumdrehungen pro Minute (rpm). Primärer Game-Input. |
| **FTMS** | Bluetooth Fitness Machine Service (UUID `0x1826`), u. a. Indoor Bike Data `0x2AD2`, Control Point `0x2AD9`. |
| **CSC** | Bluetooth Cycling Speed and Cadence Service (UUID `0x1816`), CSC Measurement `0x2A5B`. |
| **DeviceSource** | Gemeinsame Schnittstelle aller Datenquellen in der Bridge (BLE, Replay, Simulator). |
| **TelemetrySample** | Protokollneutraler Messpunkt (Zeit, Kadenz, Geschwindigkeit, Leistung), jeder Wert mit Herkunft `measured`/`estimated`. |
| **Capability** | Fähigkeit einer Quelle, z. B. `CADENCE`, `POWER`, `RESISTANCE_CONTROL`. |
| **Simulator** | `DeviceSource`, die Telemetrie erzeugt (manuell, Profil, Rauschen) – Entwicklung ohne Rad. |
| **Replay** | `DeviceSource`, die aufgezeichnete rohe BLE-Notifications erneut durch die Parser schickt. |
| **Profil** | Geskripteter Simulator-Ablauf, z. B. Intervalle oder provozierter Verbindungsabbruch. |
| **Prototyp-Game** | Das eine Spiel in v1: ein 3D-Radsimulator (Kadenz → Geschwindigkeit), siehe ADR-0005. |
| **Teststrecke** | Die Insel-Strecke des Radsimulators – abwechslungsreich, möglichst an ein reales Vorbild angelehnt. |
| **Rundkurs** | Die ca. 8–10 km lange Mallorca-Stil-Strecke: Hafen → Küste → Serpentinen → Pinienhain → Bergdorf → Abfahrt. |
| **virtuelle Steigung** | Steigung der Strecke, die nur die Spielgeschwindigkeit beeinflusst, nicht den echten Widerstand. |
| **Bridge** (`vspin-bridge`) | Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert. |
| **Bus** | Lokaler WebSocket (`ws://127.0.0.1:8765`, JSON), über den Bridge und Clients kommunizieren. |
| **Client** | Alles, was am Bus hängt: Games, Logger, Dashboard. |
| **measured / estimated** | Herkunft eines Werts: gemessen vom Gerät bzw. hochgerechnet. Geschätzte Watt werden als „~142 W“ angezeigt. |
| **stale** | Verbindungsstatus: verbunden, aber > 3 s keine Daten. Games pausieren. |
| **set_grade** | Bus-Nachricht vom Game an die Bridge mit der aktuellen virtuellen Steigung; ab v1 gesendet, bis zum ESP32 mit `not_supported` beantwortet. |
| **ESP32-Retrofit** | Spätere Ausbaustufe: Stepper am Widerstandsknopf + Hall-Sensor; meldet sich als FTMS-Smart-Bike mit Control Point. |
| **Control Point** | FTMS-Characteristic `0x2AD9` zum Steuern des Geräts; wir nutzen Op `0x11` (Indoor Bike Simulation). |
| **Session** | Ein Bridge-Lauf; erzeugt `sessions/<zeit>.csv` und `sessions/<zeit>.raw.jsonl`. |
| **HeartRateSource** | Spätere zweite Quelle: Puls per BLE Heart Rate Service `0x180D` (Brustgurt oder Garmin-Uhr mit „Herzfrequenz übertragen“). |

### Spiel

| Begriff | Bedeutung |
|---|---|
| **Runde** | Einmal den Rundkurs abfahren, in einer **Richtung** (im oder gegen den Uhrzeigersinn). |
| **Fahrt** | Alles von Start bis Ende im Spiel: eine oder mehrere Runden, oder endlos. Nicht zu verwechseln mit der **Session** (ein Bridge-Lauf). |
| **Bestzeit** | Schnellste Runde je Strecke und Richtung. |
| **Ghost** | Halbtransparenter Mitfahrer, der eine frühere Runde nachfährt – standardmäßig die Bestzeit, wahlweise die letzte Fahrt. |
| **Segment** | Fester Abschnitt des Rundkurses mit eigener Zeit, z. B. die Bergwertung in den Serpentinen. |
| **Medaille** | Bronze/Silber/Gold für eine Runden- oder Segmentzeit nach festen Schwellen. _Vermeiden:_ Medaille für Meilensteine. |
| **Erfolg** | Einmaliger Meilenstein, z. B. „100 km gesamt“, „Nachtfahrt“, „im Regen gefahren“. _Vermeiden:_ Achievement, Abzeichen. |
| **Fahrerprofil** | Der eine lokale Spieler mit Fahrtenbuch, Bestzeiten, Erfolgen und Fahrerlevel. |
| **Fahrerlevel** | Wächst mit jedem gefahrenen Kilometer in jedem Modus; schaltet nur Kosmetik frei (Trikots, Radfarben, Helme). |
| **Jahreszeit** | Folgt wie die Tageszeit dem echten Datum auf Mallorca (Mandelblüte im Februar, trockener Sommer …), im Menü umstellbar. |
| **Rundfahrt** | Spielmodus: Runden auf dem Rundkurs in gewählter Richtung, 1–n oder endlos; jede Runde zählt für Bestzeit und Medaille, Ghost zuschaltbar. |
| **Training** | Spielmodus: angeleitete Einheit (z. B. Intervalle, Pyramide, Tempo-Blöcke) mit Zielkadenz und Ansagen zum Widerstandsknopf; bewertet wird, wie gut die Zielkadenz getroffen wurde. |
| **Arcade** | Spielmodus nach dem Diablo-Kreislauf: Herausforderungen und Bosse → Beute → stärker → höhere Stufe. Seine Werte wirken nur hier (ADR-0010). |
| **Panorama-Moment** | Kurzer Kameraschwenk mit Namenseinblendung an Sehenswürdigkeiten; nicht bei Ghost oder Training. |
| **Herausforderung** | Arcade: Aufgabe auf der Strecke, die nur über die Kadenz gelöst wird: Zone halten, Durchbruch (Balken über einer Schwelle füllen), Takt-Tore, Jagd, Sammeln. Scheitern ist weich: weniger oder keine Beute, die Fahrt geht weiter. |
| **Boss** | Arcade: Sagengestalt der Insel (z. B. Drac de na Coca, Tramuntana, Dimonis) an festem Ort; sein Lebensbalken sinkt, solange die Kadenz in der Zielzone liegt. |
| **Beute** | Arcade: Ausrüstung mit Seltenheit; macht nachsichtiger, wirkungsvoller und lohnender, ersetzt aber nie das Treten. |
| **Stufe** | Arcade: gewählter Schwierigkeitsgrad (wie Diablos Qualstufen); bestimmt Zielzonen, Dauer und Beute-Qualität. Höhere Stufen werden freigeschaltet. |
| **Elite-Gruppe** | Arcade: zufällig auftauchende Gegnergruppe mit 1–3 **Eigenschaften** (Affixen: Windschnell, Wankelmütig, Gegenwind, Zäh, Taktwechsel, Rudelführer); blau = Champions, gelb = Seltene mit **Gefolge** (kleine Herausforderung im Anschluss an den Anführer). Bessere Beute. |
| **Kadenzmuster** | Aus dem Kadenzverlauf erkannte Geste: **Antritt** (schnell hochziehen), **Gleichmaß** (Kadenz ruhig halten), **Innehalten** (kurz nicht treten), **Rhythmus** (Takt treffen). _Vermeiden:_ „Antritt“ für die Herausforderung – die heißt **Durchbruch**. |
| **Fähigkeit** | Arcade: Wirkung, die ein Kadenzmuster auslöst (Windböe, Fokus, Schild, Kombo); Talente und legendäre Beute verändern sie. |
| **Empfohlene Stärke** | Arcade: Wert aus Ausrüstung und Talenten, den eine Stufe voraussetzt; höhere Stufen brauchen Fitness und Build. |
| **Arcade-Level** | Arcade: eigenes Level aus den Punkten aller Arcade-Läufe; gibt Talentpunkte. Getrennt vom **Fahrerlevel**, das nur Kosmetik freischaltet (ADR-0010). |
| **Talent** | Arcade: Knoten im Talentbaum (Äste Sprinter, Kletterer, Ausdauer), gelernt mit Talentpunkten aus dem Arcade-Level; verändert Fähigkeiten und Ausrüstungswerte nur im Arcade. |

## Scope v1

Siehe [ADR-0001](docs/adr/0001-scope-v1.md). Telemetrie + Simulator + genau ein Prototyp-Game.

## Architektur

Siehe [ADR-0002](docs/adr/0002-tech-stack-und-bus.md): Python-Bridge (bleak) → WebSocket-Bus → Godot-Games.

Geräte-Abstraktion: [ADR-0003](docs/adr/0003-geraete-abstraktion-und-simulator.md).

Datenqualität: [ADR-0004](docs/adr/0004-datenqualitaet.md) – Kadenz ist einziger Game-Input, Watt nur geschätzt.

Insel-Welt: [ADR-0006](docs/adr/0006-insel-welt.md) – handgebaut, Mallorca-Stil.

Prototyp-Game: [ADR-0005](docs/adr/0005-prototyp-game-radsimulator.md) – 3D-Radsimulator auf einer Insel.

Widerstandssteuerung: [ADR-0007](docs/adr/0007-widerstandssteuerung-esp32.md) – Steigung über FTMS, ESP32 als Smart-Bike.

Datenspeicherung: [ADR-0008](docs/adr/0008-datenspeicherung-und-export.md) – CSV + Roh-JSONL pro Bridge-Start, FIT/Strava später.

Repo & Lizenz: [ADR-0009](docs/adr/0009-repo-organisation-und-lizenz.md) – Monorepo, privat, MIT.

Ehrliche Bestzeiten: [ADR-0010](docs/adr/0010-ehrliche-bestzeiten-arcade-getrennt.md) – Arcade-Werte wirken nur im Arcade-Modus.

Bus-Vertrag: [docs/bus-protocol.md](docs/bus-protocol.md).
