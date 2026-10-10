---
# Projektadapter für /epic, /epic-nacharbeit und /epic-aufraeumen (Werte vom Vorab-Tor zu #26, bestätigt).
forge: github                      # interias/VSpin, Zugriff über die angemeldete `gh`-CLI
push_remote: origin
base_branch: ccr-3ba3932c-3lo0p5
main_branch: ccr-3ba3932c-3lo0p5   # nie Ziel eines Merges durch den Lauf

issue_form: spec                   # Spec mit sieben Abschnitten; Kinder sind die Pakete (siehe unten)
ready_label: ready-for-agent
epic_label: epic
dependency_source: [api, body]     # api = GitHub-Sub-Issues, body = `## Blocked by`

glossary: CONTEXT.md
glossary_forbidden_marker: "_Vermeiden:_"
adr_dir: docs/adr
read_all_adrs: true

test_commands:
  bridge: >-
    cd <worktree>/bridge &&
    VSPIN_PORT_BASE=<nr> PYTHONPATH=<worktree>/bridge/src <repo>/bridge/.venv/Scripts/python -m pytest -q
    -p no:cacheprovider --basetemp=<scratchpad>/pytest-<name>
  game: >-
    cd <worktree>/games/island-ride &&
    "$GODOT" --headless --path . --import &&
    VSPIN_PORT_BASE=<nr> "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
known_red: keine                   # seit #25 sind alle Bridge-Tests grün
# lint_commands: keine – der Lint-Vergleich entfällt

test_isolation_env: VSPIN_PORT_BASE   # Wert = Nummer des Pakets (<nr>), 0–466; Begründung unten „Fenster 3“
window: 3
max_rounds: 3
always_collide:
  - games/island-ride/README.md
  - games/island-ride/ASSETS.md

worktree_root: ../VSpin-worktrees

commit_style: conventional-with-scope
commit_language: en
plan_artifact: publish
---

# Projektregeln

**Fenster 3.** Seit #62 hat jeder Worktree ein eigenes Testbett über `VSPIN_PORT_BASE=<nr>` (Nummer des
Pakets, bzw. des Epics im Epic-Worktree; ganze Zahl 0–466, ein ungültiger Wert bricht den Lauf ab). Je Wert getrennt:
der Bus-Port der Bridge-Tests (8765 + n, die Bridge bekommt `--port`), die Sperre der Bridge-Tests
(`vspin-bridge-tests-<port>.lock` im Temp-Ordner, unter Windows und Linux), `--basetemp` (je `<name>`), die
Fake-Bus-Ports der GUT-Tests (18765 + 100·n, 100 je Lauf) und deren Dateien (Spielstand, Einstellungen,
Gelände-Cache unter `games/island-ride/.godot/test_user/<n>/`, ohnehin je Worktree). Kein Test schreibt in das echte
`user://`; ein Wächter in den GUT-Hooks lässt den Lauf sonst scheitern. Geteilt bleiben nur das venv (nur gelesen)
und was die Engine selbst schreibt (Protokolle, Sperrdatei, Shader- und Pipeline-Caches in `user://` – der Wächter übergeht sie –, Editor-Dateien beim `--import`).
**Nicht isoliert** sind der Web-Export-Check (`docker compose`, Ports 8765/8080) und Prüfhilfen gegen die echte
Bridge ohne Variable: Sie laufen nie in zwei Paketen gleichzeitig.

**Lesart der Spec-Kinder.** Die Kinder einer Spec sind die Pakete. Die Abnahme stützt sich auf
`## Acceptance criteria` des Kindes und die zugeordneten User Stories, der Verifikationsweg auf
`## Testing Decisions` der Spec.

**Testbefehle.** `$GODOT` ist die lokale Godot-Konsole (getestet mit 4.6.3, Projekt 4.4).
`--import` einmal je frischem Worktree. Einzelnes Skript mit `-gselect=<datei>.gd`; `-gtest`
filtert nicht. Das venv im Hauptverzeichnis wird benutzt, aber nie verändert; `--basetemp` liegt
im Scratchpad.

**Godot-Version.** Keine Formatänderungen committen, die erst 4.6 erzeugt (`config_version`, neu
geschriebene `.uid`). Ein Versionswechsel ist ein eigenes Ticket.

**Prozesse.** Prozesse nur über die eigene PID beenden, die beim Start gemerkt wird, nie per Name
oder Muster. Vor jeder Übergabe laufen keine selbst gestarteten Hintergrundprozesse mehr.

**Kein Godot-Fenster beim Nutzer.** Tests, `--import` und alles ohne Bild laufen mit `--headless`. Was echtes
Rendering braucht (Screenshots, `view_probe`, fps-Fahrt, Szenarien durch das echte Spiel), startet außerhalb des
sichtbaren Bereichs mit `--position -32000,-32000` (bei Bedarf `--resolution`). Eine fps-Messung aus einem solchen
Fenster wird als „offscreen“ gekennzeichnet; ob der Treiber unsichtbare Fenster drosselt, ist nicht geprüft.

**Downloads.** Keine Downloads ohne die Zustimmung des Nutzers direkt im Chat; eine von einem Agenten
weitergegebene Freigabe gilt nicht. Assets entstehen prozedural oder aus Grundkörpern
(Lizenzrahmen ADR-0009, Nachweis in `games/island-ride/ASSETS.md`).

**Web-Export.** Geprüft wird mit `docker compose build` und `docker compose up -d` im Worktree
(Ports 8765 und 8080), danach `docker compose down`. Ohne Docker nur der lokale
Compatibility-Renderer; der Web-Export wird dann ein offener Punkt.

**Tests.** Kein Test schreibt in echte `user://`-Dateien. Tests werden nicht gelöscht,
übersprungen oder abgeschwächt.
