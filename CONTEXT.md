# VSPIN – Kontext & Glossar

Lebendes Dokument. Begriffe, die im Projekt eine feste Bedeutung haben.
Entscheidungen stehen als ADRs unter [`docs/adr/`](docs/adr/).

## Ausgangslage

- **Gerät:** Trainer (FTMS), Bluetooth LE; erstes Gerät ist der Wahoo KICKR CORE 2.
- **Widerstand:** vom Trainer elektronisch gesteuert (Indoor Bike Simulation, ERG).
- **Host:** Windows-PC mit USB-Bluetooth-Dongle.
- **Protokoll:** FTMS (Fitness Machine Service); Verifikation per nRF-Connect-Dump.

## Glossar

| Begriff | Bedeutung |
|---|---|
| **Trainer (FTMS)** | Rad-Trainer (z. B. Wahoo KICKR CORE 2) als Gerät der Bridge: liest Leistung, Kadenz und Tempo per BLE Fitness Machine Service `0x1826` (Indoor Bike Data `0x2AD2`, Features `0x2ACC`); fehlt die Kadenz dort, kommt sie aus Cycling Power `0x2A63`. Bus-`source` ist `ble` (`vspin-bridge --source ble`), die Watt sind **measured**. Kann er Indoor Bike Simulation, steuert die Bridge ihn: die virtuelle Steigung wird zum Widerstand (**Steuerung**). |
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
| **virtuelle Steigung** | Steigung der Strecke an der Fahrerposition. Sie wirkt auf die Spielgeschwindigkeit und – per `set_grade` – am Trainer als Widerstand (Spec #75); ohne Trainer mit Steuerung (Simulator, Replay, Nur-lesen-Modus) nur im Spiel. |
| **Bridge** (`vspin-bridge`) | Python-Prozess, der als einziger BLE spricht und Telemetrie auf den Bus publiziert. |
| **Bus** | Lokaler WebSocket (`ws://127.0.0.1:8765`, JSON), über den Bridge und Clients kommunizieren. |
| **Client** | Alles, was am Bus hängt: Games, Begleiter, Logger, Dashboard. |
| **measured / estimated** | Herkunft eines Werts: gemessen vom Gerät bzw. hochgerechnet. Geschätzte Watt werden als „~142 W“ angezeigt. Die Herkunft hängt am Gerät: der Trainer (FTMS) misst, Replay und Simulator schätzen. |
| **stale** | Verbindungsstatus: verbunden, aber > 3 s keine Daten. Games pausieren. |
| **set_grade** | Bus-Nachricht vom Game an die Bridge mit der aktuellen virtuellen Steigung (Anteil, 0.07 = 7 %). Die Bridge antwortet dem Absender mit einem **ack**: `ok: true`, wenn die Steigung angenommen ist (am Trainer gedrosselt umgesetzt), sonst mit Grund – `not_supported` (Quelle ohne `RESISTANCE_CONTROL`), `read_only`, `control_lost`, `source_error`. |
| **Steuerung** | Die Bridge steuert den Trainer über den FTMS Control Point; es gibt immer nur einen Steuerer. Stand auf dem Bus in `status.trainer.control` (`none`, `requesting`, `active`, `lost`, `read_only`, `not_supported`, `error`). `lost` = eine andere App (z. B. Zwift) steuert; die Bridge schreibt dann bis zum Neuverbinden nichts und das Spiel zeigt einen Hinweis. |
| **Nur-lesen-Modus** | Bridge mit `--read-only` (Spiel: `config.cfg [bridge] trainer_read_only`): liest den Trainer, fordert keine Steuerung an und schreibt nichts auf ihn – damit sich zwei Apps nicht um die Steuerung streiten. |
| **Gang (virtuell)** / **effektive Steigung** | Gang = Stufe der Gangtabelle in VSpin (`Gears`, `config.cfg [gears]`: Anzahl, neutraler Gang, Schritt in Prozentpunkten; Standard 24 / 12 / 0,5). Schalten per Tastatur (Pfeil ↑ schwerer, Pfeil ↓ leichter, Ziffernblock +/−), nur bei steuerbarem Trainer (`status.trainer.control == active`), nicht im ERG-Modus. Effektive Steigung = Steigung der Strecke + (Gang − neutral) × Schritt; sie geht per `set_grade` an den Trainer und ist der einzige Weg des Gangs – das Fahrmodell und die Grundlast (0) kennen ihn nicht, das Zwift-Protokoll wird nicht benutzt (Spec #75). |
| **Grundlast** | Sichere Last am Trainer: Steigung 0. Das Spiel sendet sie beim Verlassen der Fahrt (Pause, Verbindungspause, Ziel, Menü), die Bridge setzt sie, wenn alle Clients weg sind oder der Client der letzten Steigung geht, und beim Beenden (dann zusätzlich Reset). Nie gedrosselt. |
| **Control Point** | FTMS-Characteristic `0x2AD9` zum Steuern des Geräts (Write + Indicate); wir nutzen `0x00` Request Control, `0x07` Start, `0x11` Indoor Bike Simulation, `0x05` Set Target Power (ERG) und beim Beenden `0x01` Reset. Machine Status `0x2ADA` meldet u. a. den Verlust der Steuerung (`0xFF`). |
| **Session** | Ein Bridge-Lauf; erzeugt `sessions/<zeit>.csv`, `sessions/<zeit>.raw.jsonl` und das **Steuerprotokoll** `sessions/<zeit>.control.jsonl`. |
| **Steuerprotokoll** | Session-Datei `<zeit>.control.jsonl` (Spec #89): jeder Wechsel der **Steuerung** samt Grund, jedes Schreiben und jede Indication auf dem **Control Point**, jede Notification von `0x2ADA`, jeder Fehler – zur Diagnose, warum VSpin den Trainer (nicht) steuert. |
| **FIT-Datei** | Eine **Fahrt** als FIT-Aktivität (Garmins Dateiformat) in der **Fahrtablage** `sessions/rides/<zeit>_<ride_id>.fit`; die Bridge schreibt sie aus der Session-CSV, ohne geschätzte Watt (ADR-0008, Nachtrag #84). Lässt sich von Hand in Garmin Connect importieren. |
| **Fahrtablage** | Ordner `sessions/rides/` der Bridge: die **FIT-Datei** jeder gespeicherten **Fahrt** und `rides.json` mit Wanduhr-Anker, Session-CSV und Upload-Marke je `ride_id` – die Merkliste, damit keine Fahrt zweimal hochgeladen wird. Eine Fahrt aus einer früheren **Session** wird nie neu geschrieben (#84). |
| **HeartRateSource** | Zweite Quelle der Bridge neben der Radquelle: Puls per BLE Heart Rate Service `0x180D`. Gemerkte Geräte haben die Rolle Gurt (Brustgurt) oder Uhr (Garmin-Uhr mit „Herzfrequenz übertragen“); ihre Reihenfolge ist der Vorrang, ein verbundenes Gerät mit geringerem Vorrang wird gegen eines mit höherem getauscht. |
| **Rolle** | Wofür ein BLE-Gerät im Verbindungsfenster steht: `trainer`, `heart_rate` (Puls) oder `controller` (Bus-Feld `kind`). Je Rolle gemerkte Geräte (`set_devices`) und eine Suche auf Anfrage zur Zeit. Nicht zu verwechseln mit der Pulsrolle Gurt/Uhr eines Pulsgeräts. |
| **Verbindungsfenster** | Fenster im Spiel mit einer **Kachel** je Rolle (Zustand, Gerätename, Live-Wert, Signalstärke) und darunter der Einrichtung (suchen, merken, vergessen). Öffnet beim Start von selbst nur bei `config.cfg [bridge] source="ble"` ohne gemerkten Trainer, sonst über „Verbindungen“ im Startmenü, den Knopf im HUD oder die Taste V. Vorgänger ist die Geräteseite aus #64. |
| **Kachel** | Teil des Verbindungsfensters für eine Rolle: oben der Stand, unten die Einrichtung. Die Trainerkachel zeigt auch die Steuerung, „Nur lesen“ und den Knopf „Steuerung zurückholen“. |
| **Background Pairing** | Start ohne Dialog: Das Spiel schickt seine gemerkten Geräte nach jedem Verbinden mit dem Bus, die Bridge verbindet im Hintergrund das beste gemerkte Gerät, das sendet (Trainer: das stärkste). |
| **Steuerung zurückholen** | Knopf im Verbindungsfenster bei `lost` oder `error` (`reclaim_trainer_control`): Nur auf diesen Klick fordert die Bridge die Steuerung neu an; von selbst nie, damit VSpin nie im Streit mit einer anderen App steuert. |
| **Controller** | Lenkercontroller des Zwift Ride (links/rechts, Name „Zwift SF2“). VSpin verbindet ihn nur und zeigt Zustand und Akku; die Tasten nutzt es noch nicht, und es schreibt nie auf ihn. **Gesperrt** (`locked`): Ab Firmware 1.3 versteckt er seinen Service, bis er einmal in Zwift verbunden war (gilt etwa 24 h) – kein Fehler, sondern ein Hinweis. |

### Spiel

| Begriff | Bedeutung |
|---|---|
| **Runde** | Einmal den Rundkurs abfahren, in einer **Richtung** (im oder gegen den Uhrzeigersinn). |
| **Fahrt** | Alles von Start bis Ende im Spiel: eine oder mehrere Runden, oder endlos. Nicht zu verwechseln mit der **Session** (ein Bridge-Lauf). |
| **Fahrt speichern** | Am Ende einer **Fahrt**: das Spiel schickt `save_ride`, die Bridge schreibt die **FIT-Datei** und lädt sie auf Wunsch einmal zu Garmin Connect hoch (#84). Erneutes Speichern schreibt dieselbe Datei (in einer späteren **Session** bleibt sie unverändert) und lädt nicht noch einmal hoch. |
| **Bestzeit** | Schnellste Runde je Strecke und Richtung. |
| **Ghost** | Halbtransparenter Mitfahrer, der eine frühere Runde nachfährt – standardmäßig die Bestzeit, wahlweise die letzte Fahrt. |
| **Segment** | Fester Abschnitt des Rundkurses mit eigener Zeit, z. B. die Bergwertung in den Serpentinen. |
| **Medaille** | Bronze/Silber/Gold für eine Runden- oder Segmentzeit nach festen Schwellen. _Vermeiden:_ Medaille für Meilensteine. |
| **Geräteart** | Womit eine Fahrt gewertet wird: `power` (Trainer mit gemessener Leistung → **Leistungsmodell**) oder `cadence` (Simulator, Rad ohne gemessene Watt → Kadenzmodell). Steht mit der ersten Telemetrie der Fahrt fest; Bestzeit, Segmentzeiten, Medaillen und Ghosts gibt es je Geräteart getrennt (ADR-0010 Nachtrag). |
| **Leistungsmodell** | Fahrmodell bei gemessener Leistung: Tempo aus Watt und Streckensteigung mit Masse, Roll- und Luftwiderstand (`config.cfg [power]`), Trägheit wie im Kadenzmodell; die Gänge wirken nur am Trainer. Arcade-Herausforderungen hängen trotzdem an der Kadenz. |
| **3-s-Mittel** | Mittel der gemessenen Leistung über die letzten drei Sekunden; steht im HUD klein hinter dem Wattwert („212 W · Ø3s 205 W“). |
| **Erfolg** | Einmaliger Meilenstein, z. B. „100 km gesamt“, „Nachtfahrt“, „im Regen gefahren“. _Vermeiden:_ Achievement, Abzeichen. |
| **Fahrerprofil** | Der eine lokale Spieler mit Fahrtenbuch, Bestzeiten, Erfolgen und Fahrerlevel. |
| **Fahrerlevel** | Wächst mit jedem gefahrenen Kilometer in jedem Modus; schaltet nur Kosmetik frei (Trikots, Radfarben, Helme). |
| **Jahreszeit** | Folgt wie die Tageszeit dem echten Datum auf Mallorca (Mandelblüte im Februar, trockener Sommer …), im Menü umstellbar. |
| **Rundfahrt** | Spielmodus: Runden auf dem Rundkurs in gewählter Richtung, 1–n oder endlos; jede Runde zählt für Bestzeit und Medaille, Ghost zuschaltbar. |
| **Training** | Spielmodus: angeleitete Einheit (z. B. Intervalle, Pyramide, Tempo-Blöcke) mit Zielkadenz und Ansagen zum Widerstandsknopf; bewertet wird, wie gut die Zielkadenz getroffen wurde. Steuert VSpin den Trainer (`status.trainer.control == active`), entfällt die Ansage zum Knopf. |
| **ERG** | Zweiter Steuermodus des Trainers (Spec #75): Der Trainer hält eine **Zielleistung** (FTMS `0x05` Target Power, Bus `set_target_power`), unabhängig von der Kadenz; Gegenstück ist SIM (Steigung, `set_grade`). Stand in `status.trainer.mode` (`sim` / `erg`) und `target_power`. In ERG wird nicht geschaltet und keine Steigung gesendet; die Grundlast verlässt ERG und setzt Steigung 0. |
| **ERG-Einheit** / **Zielleistung** | Trainingseinheit mit Watt-Zielen je Phase, absolut (`power_w`) oder als Anteil der FTP (`power_ftp`). Das Spiel sendet je Phase die Zielleistung und sagt sie an („In 8 s: 250 W“); bewertet wird der Anteil der Zeit, in der die gemessene Leistung im Zielband lag (± 5 %, mindestens ± 10 W). Ohne steuerbaren Trainer läuft sie ohne ERG weiter (der Fahrer hält die Leistung selbst). |
| **FTP** | Functional Threshold Power des Fahrers in W (50–600), im Profil neben LTHR und Maximalpuls (Verbindungsfenster). Einheiten in % FTP lassen sich ohne FTP nicht starten. |
| **Arcade** | Spielmodus nach dem Diablo-Kreislauf: Herausforderungen und Bosse → Beute → stärker → höhere Stufe. Seine Werte wirken nur hier (ADR-0010). |
| **Panorama-Moment** | Kurzer Kameraschwenk mit Namenseinblendung an Sehenswürdigkeiten; nicht bei Ghost oder Training. |
| **Herausforderung** | Arcade: Aufgabe auf der Strecke, die nur über die Kadenz gelöst wird: Zone halten, Durchbruch (Balken über einer Schwelle füllen), Takt-Tore, Jagd, Sammeln. Scheitern ist weich: weniger oder keine Beute, die Fahrt geht weiter. |
| **Boss** | Arcade: Sagengestalt der Insel (z. B. Drac de na Coca, Tramuntana, Dimonis) an festem Ort; sein Lebensbalken sinkt, solange die Kadenz in der Zielzone liegt. |
| **Beute** | Arcade: Ausrüstung mit Seltenheit; macht nachsichtiger, wirkungsvoller und lohnender, ersetzt aber nie das Treten. |
| **Stufe** | Arcade: gewählter Schwierigkeitsgrad (wie Diablos Qualstufen); bestimmt Zielzonen, Dauer und Beute-Qualität. Höhere Stufen werden freigeschaltet. |
| **Elite-Gruppe** | Arcade: zufällig auftauchende Gegnergruppe mit 1–3 **Eigenschaften** (Affixen: Windschnell, Wankelmütig, Gegenwind, Zäh, Taktwechsel, Rudelführer); blau = Champions, gelb = Seltene mit **Gefolge** (kleine Herausforderung im Anschluss an den Anführer). Bessere Beute. |
| **Kadenzmuster** | Aus dem Kadenzverlauf erkannte Geste: **Antritt** (schnell hochziehen), **Gleichmaß** (Kadenz ruhig halten), **Innehalten** (kurz nicht treten), **Rhythmus** (Takt treffen). _Vermeiden:_ „Antritt“ für die Herausforderung – die heißt **Durchbruch**. |
| **Fähigkeit** | Arcade: Wirkung, die ein Kadenzmuster auslöst (Windböe, Fokus, Schild, Kombo); Talente und legendäre Beute verändern sie. |
| **Charakterblatt** | Arcade: Ansicht in der Ausrüstung mit dem Fahrer in der Mitte und den sechs Plätzen (Rahmen, Laufräder, Trikot, Helm, Schuhe, Talisman) drumherum; zeigt die angelegten Teile, die Summe der Werte und die eigene Stärke neben der **Empfohlenen Stärke** der gewählten Stufe. Nur Darstellung (#68, ADR-0010). |
| **Ausrüstungssymbol** | Arcade: kleines Bild eines Teils der **Beute** – je Platz eine eigene Low-Poly-Form (aus Grundkörpern gerendert), Rahmen und Hintergrund in der Farbe der Seltenheit, legendäre Teile leuchten (im Grafikmenü abschaltbar); Farbe, Muster und Detail folgen dem Inhalt des Teils, sodass es immer gleich aussieht. Ein leerer Platz zeigt die graue Silhouette seiner Form. Nur Darstellung (#83, ADR-0010). |
| **Empfohlene Stärke** | Arcade: Wert aus Ausrüstung und Talenten, den eine Stufe voraussetzt; höhere Stufen brauchen Fitness und Build. |
| **Arcade-Level** | Arcade: eigenes Level aus den Punkten aller Arcade-Läufe; gibt Talentpunkte. Getrennt vom **Fahrerlevel**, das nur Kosmetik freischaltet (ADR-0010). |
| **Talent** | Arcade: Knoten im Talentbaum (Äste Sprinter, Kletterer, Ausdauer), gelernt mit Talentpunkten aus dem Arcade-Level; verändert Fähigkeiten und Ausrüstungswerte nur im Arcade. |

### Begleiter

| Begriff | Bedeutung |
|---|---|
| **Begleiter** (Toni, `vspin-companion`) | Sprechender Radkumpel: eigener Python-Prozess am Bus, hört über die Sprechtaste zu, antwortet mit Stimme und meldet sich von selbst. Liest nur, wirkt nie auf Tempo, Wertung oder Beute (ADR-0010, ADR-0011). _Vermeiden:_ Bot, Assistent, Sprachassistent. |
| **Wecker** | Weckt den Begleiter in zufälligen Abständen (Start 3–8 min, per Stimme einstellbar) und sofort bei Ereignissen; Toni entscheidet dann selbst, ob er etwas sagt. _Vermeiden:_ Wake-Word – Toni hört nie dauernd mit. |
| **Seele** (`soul.md`) | Tonis Charakter als Textdatei, höchstens 1 500 Zeichen; per Stimme änderbar („sei mal ernster“). |
| **Gedächtnis** (`memory.md`) | Was Toni über den Fahrer weiß (Ziele, Vorlieben, Running Gags), höchstens 3 000 Zeichen; nach jeder Fahrt aufgeräumt. Nicht der Gesprächsverlauf – der lebt nur im Speicher, eine Sitzung je Fahrt. |
| **Sprechtaste** | Leertaste in der Fahrt halten: Toni hört nur, solange sie gedrückt ist (`companion_ptt`). Pause bleibt `P`, im Startmenü startet die Leertaste wie bisher. _Vermeiden:_ Wake-Word, Dauer-Mithören. |
| **heiser** | Status des Begleiters (`companion_status: hoarse`): Toni schweigt wegen eines Fehlers, ohne Netz oder bei erreichtem Abo-Limit; die Fahrt läuft weiter, kein stilles Ausweichen auf etwas Kostenpflichtiges. |

## Scope v1

Siehe [ADR-0001](docs/adr/0001-scope-v1.md). Telemetrie + Simulator + genau ein Prototyp-Game.

## Architektur

Siehe [ADR-0002](docs/adr/0002-tech-stack-und-bus.md): Python-Bridge (bleak) → WebSocket-Bus → Godot-Games.

Geräte-Abstraktion: [ADR-0003](docs/adr/0003-geraete-abstraktion-und-simulator.md).

Datenqualität: [ADR-0004](docs/adr/0004-datenqualitaet.md) – Kadenz ist einziger Game-Input, Watt je Gerät gemessen oder geschätzt.

Insel-Welt: [ADR-0006](docs/adr/0006-insel-welt.md) – handgebaut, Mallorca-Stil.

Prototyp-Game: [ADR-0005](docs/adr/0005-prototyp-game-radsimulator.md) – 3D-Radsimulator auf einer Insel.

Widerstandssteuerung: [ADR-0007](docs/adr/0007-widerstandssteuerung-esp32.md) – Steigung über FTMS am Trainer.

Datenspeicherung: [ADR-0008](docs/adr/0008-datenspeicherung-und-export.md) – CSV + Roh-JSONL pro Bridge-Start, FIT-Datei je Fahrt, optional Garmin-Upload (#84).

Repo & Lizenz: [ADR-0009](docs/adr/0009-repo-organisation-und-lizenz.md) – Monorepo, privat, MIT.

Ehrliche Bestzeiten: [ADR-0010](docs/adr/0010-ehrliche-bestzeiten-arcade-getrennt.md) – Arcade-Werte wirken nur im Arcade-Modus.

Begleiter: [ADR-0011](docs/adr/0011-begleiter-claude-abo-oauth-stimme-openrouter.md) – Claude über Abo-OAuth, Stimme über OpenRouter, Erkennung lokal.

Bus-Vertrag: [docs/bus-protocol.md](docs/bus-protocol.md).
