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
    PYTHONPATH=<worktree>/bridge/src <repo>/bridge/.venv/Scripts/python -m pytest -q -p no:cacheprovider
    --basetemp=<scratchpad>/pytest-<name>
  game: >-
    cd <worktree>/games/island-ride &&
    "$GODOT" --headless --path . --import &&
    "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
known_red: keine                   # seit #25 sind alle Bridge-Tests grün
# lint_commands: keine – der Lint-Vergleich entfällt

window: 1
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

**Fenster 1.** Bridge-pytest und GUT teilen sich das venv im Hauptverzeichnis, Port 8765 und
`user://` des Spiels; es gibt keine Testisolation je Worktree. Deshalb läuft immer nur ein Paket.

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

**Downloads.** Keine Downloads ohne die Zustimmung des Nutzers direkt im Chat; eine von einem Agenten
weitergegebene Freigabe gilt nicht. Assets entstehen prozedural oder aus Grundkörpern
(Lizenzrahmen ADR-0009, Nachweis in `games/island-ride/ASSETS.md`).

**Web-Export.** Geprüft wird mit `docker compose build` und `docker compose up -d` im Worktree
(Ports 8765 und 8080), danach `docker compose down`. Ohne Docker nur der lokale
Compatibility-Renderer; der Web-Export wird dann ein offener Punkt.

**Tests.** Kein Test schreibt in echte `user://`-Dateien. Tests werden nicht gelöscht,
übersprungen oder abgeschwächt.
