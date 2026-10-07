# VSpin – Anleitung

Installation, Start mit oder ohne Rad, Docker, Tests und Latenzprüfung. Überblick: [README](../README.md).

## Schnellstart (Windows)

Voraussetzungen: Python 3.12, [Godot 4.4](https://godotengine.org/download) (Standard-Version, nicht .NET).

**1. Bridge installieren** (einmalig, PowerShell im Repo-Ordner):

```powershell
cd bridge
py -3.12 -m venv .venv
.venv\Scripts\pip install -e ".[test]"
```

**2. Bridge starten** – eine der Quellen:

```powershell
.venv\Scripts\vspin-bridge --source sim --sim-cadence 80        # Simulator, Kadenz per Pfeiltasten
.venv\Scripts\vspin-bridge --source sim --profile profiles\sprint.toml   # geskriptetes Profil
.venv\Scripts\vspin-bridge --source replay <datei>.raw.jsonl --speed 1   # Aufnahme abspielen
```

Im Bridge-Terminal: Pfeil hoch/runter = Kadenz ±5, `q` = beenden. Profile liegen in
`bridge/profiles/` (Einrollen, Sprint, Stillstand, Abbruch). Jede Session landet als
`sessions/<zeit>.csv` + `.raw.jsonl` im aktuellen Ordner (nicht im Git).
Das echte Rad (`--source ble`) folgt mit #9.

**3. Spiel starten:** Godot öffnen → `games/island-ride/project.godot` importieren → F5,
oder `godot --path games/island-ride`. Tasten: `P`/Leertaste Pause, `F3` Debug-Anzeige, `Esc` oder `F2` Menü
(Kantenglättung, Auflösung, Fenster auf linke/rechte Bildschirmhälfte, Tageszeit, Wetter; Knopf „Beenden“ zum
Beenden), `F11` Vollbild.
Reihenfolge egal – das Spiel verbindet sich, sobald die Bridge läuft.

**4. Protokoll des Rads herausfinden** (sobald das JC312 da ist): siehe [`tools/README.md`](../tools/README.md).

**Tests:**

```powershell
cd bridge; .venv\Scripts\python -m pytest -q          # Bridge (startet echte Bridge-Prozesse)
godot --headless --path games/island-ride --import       # Spiel, einmalig
godot --headless --path games/island-ride -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Details: [`bridge/README.md`](../bridge/README.md), [`games/island-ride/README.md`](../games/island-ride/README.md).

## Mit Docker Desktop starten

Ohne lokale Python- oder Godot-Installation, nur mit [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(im Repo-Ordner):

```powershell
docker compose up --build -d      # erster Build lädt Godot 4.4.1 + Export-Templates, dauert einige Minuten
```

Dann **http://localhost:8080** im Browser öffnen und fahren. Es laufen zwei Container
([`docker-compose.yml`](../docker-compose.yml)):

- **`bridge`** – `vspin-bridge --source sim` mit Start-Kadenz 80 rpm. Der Bus ist nur auf `127.0.0.1:8765` des
  Rechners erreichbar (im Container lauscht die Bridge mit `--host 0.0.0.0`); das Spiel im Browser verbindet sich wie
  gewohnt mit `ws://127.0.0.1:8765`.
- **`game`** – Web-Export der Inselfahrt (Godot 4.4.1, Compatibility-Renderer, ohne Threads) hinter nginx.

**Kadenz ändern:** `docker attach vspin-bridge-1` – dann Pfeil hoch/runter = ±5 rpm wie im Bridge-Terminal.
Abkoppeln mit **Strg+P Strg+Q** (Strg+C oder `q` beenden dagegen die Bridge).

**Profil oder Start-Kadenz** per Umgebungsvariable (Pfad relativ zu `bridge/`):

```powershell
$env:VSPIN_PROFILE="profiles/sprint.toml"; docker compose up -d   # Profil statt manueller Kadenz
$env:VSPIN_CADENCE="60"; docker compose up -d                     # andere Start-Kadenz
```

Gesetzte Variablen gelten bis zum Schließen der PowerShell (`Remove-Item Env:VSPIN_PROFILE` setzt zurück).

**Sessions** landen im Ordner `sessions/` im Repo-Root (nicht im Git). Die Dateinamen tragen UTC-Zeit –
der Container kennt die Zeitzone des Rechners nicht.

**Stoppen:** `docker compose down` – die Bridge schließt die Session dabei sauber ab.

**BLE nur nativ:** Docker Desktop reicht unter Windows kein Bluetooth in Container durch. Für das echte Rad
(`--source ble`, #9) läuft die Bridge weiterhin direkt unter Windows (siehe Schnellstart); das Spiel kann dabei
trotzdem aus dem Container kommen – dann nur `docker compose up -d --no-deps game` starten (ohne `--no-deps`
startet die Container-Bridge mit und belegt Port 8765).

## Latenz prüfen (Abnahme < 200 ms)

Die Debug-Anzeige (`F3`) zeigt Roh-Kadenz, Bridge-Zeitstempel und „Letzte Telemetrie vor … ms“ – die Zeit, seit
die letzte Nachricht im Spiel angekommen ist. Sie zeigt nur, ob Daten vom Bus stocken (Anteil Bus → Spiel), nicht
die Latenz Kurbel → Bild. Die Gesamtlatenz Kurbel → Bild misst man am einfachsten mit einer
Zeitlupen-Aufnahme (Handy, 240 fps): Kurbel und Bildschirm gleichzeitig filmen, aus dem Stand kräftig antreten
und die Frames zwischen erster Kurbelbewegung und erster Reaktion im HUD zählen (1 Frame ≈ 4 ms).
Hinweis: Das Rad selbst sendet typischerweise nur ca. 1–4 Mal pro Sekunde, und die Glättung (0,3 s) verzögert
zusätzlich – das Ergebnis zeigt, ob Glättung oder Senderate angepasst werden müssen.
