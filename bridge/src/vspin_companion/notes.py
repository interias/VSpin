"""Seele (`soul.md`) und Gedächtnis (`memory.md`) des Begleiters in der Ablage (ADR-0008 Nachtrag #76).

Beide sind Textdateien, die der Fahrer auch von Hand bearbeiten darf (Story 19); gelesen wird deshalb bei jedem
Gebrauch frisch. Grenzen: Seele 1 500, Gedächtnis 3 000 Zeichen. Werkzeuge kürzen nie still: Würde ein Eintrag die
Grenze reißen, fasst Haiku die Datei sofort zusammen (Aufräumen vorgezogen); hält auch das die Grenze nicht, wird
nichts gespeichert und das Werkzeug meldet den Fehler. Nach `ride_end` räumt `tidy` auf.

`.bak` hält immer den Stand vor der Sitzung (Fahrt, oder die Zeit außerhalb einer Fahrt): je Datei und Sitzung genau
einmal, vor dem ersten Schreiben – durch ein Werkzeug oder das Aufräumen –, danach in derselben Sitzung nie wieder.
So geht keine Fassung verloren, auch keine von Hand bearbeitete. `begin()` beginnt eine neue Sitzung.
"""

import os
import shutil
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from importlib import resources
from pathlib import Path

from . import prompts

BACKUP_SUFFIX = ".bak"
DEFAULT_SOUL = "soul.md"  # Startcharakter „Toni“, liegt im Paket


@dataclass(frozen=True, slots=True)
class Note:
    file: str
    limit: int  # höchstens so viele Zeichen
    label: str


SOUL = Note("soul.md", 1500, "Seele")
MEMORY = Note("memory.md", 3000, "Gedächtnis")
NOTES = (SOUL, MEMORY)

# Zielgrößen fürs Zusammenfassen als Anteil der Grenze: erst mit Luft, dann knapper (zweiter Versuch).
CONDENSE_TARGETS = (0.9, 0.7)


class NoteRefused(Exception):
    """Ein Eintrag wurde nicht gespeichert (leer, oder auch zusammengefasst über der Grenze) – Meldung an Haiku."""


class Notebook:
    """`summarize(prompt) -> Text` ist ein einmaliger Auftrag an das Brain ohne Werkzeuge (`Brain.summarize`)."""

    def __init__(
        self,
        data_dir: Path,
        summarize: Callable[[str], Awaitable[str]],
        log: Callable[[str], None] = lambda text: None,
    ) -> None:
        self.data_dir = data_dir
        self._summarize = summarize
        self._log = log
        self.changed: set[Note] = set()  # in dieser Fahrt per Werkzeug geschrieben – nach `ride_end` aufräumen
        self._backed_up: set[Note] = set()  # in dieser Sitzung schon gesichert (oder es gab nichts zu sichern)

    def begin(self) -> None:
        """Neue Sitzung (Fahrtbeginn, Fahrtende): das nächste Schreiben je Datei sichert wieder zuerst."""
        self.changed.clear()
        self._backed_up.clear()

    def path(self, note: Note) -> Path:
        return self.data_dir / note.file

    def read(self, note: Note) -> str:
        """Frisch von der Platte. Fehlt `soul.md`, kommt die Vorgabe „Toni“ in die Ablage; fehlt `memory.md`: leer."""
        path = self.path(note)
        try:
            return path.read_text(encoding="utf-8")
        except FileNotFoundError:
            if note is not SOUL:
                return ""
        text = resources.files(__package__).joinpath(DEFAULT_SOUL).read_text(encoding="utf-8")
        self._write(note, text, backup=False)  # die Vorgabe ist der Stand vor der Sitzung, nichts zu sichern
        self._log(f"Seele: Vorgabe „Toni“ nach {path} kopiert")
        return text

    async def remember(self, text: str) -> str:
        entry = " ".join(text.split())
        if not entry:
            raise NoteRefused("nichts zu merken – der Text war leer")
        current = self.read(MEMORY).rstrip()
        updated = (current + "\n" if current else "") + f"- {entry}\n"
        return await self._store(MEMORY, updated, "gemerkt")

    async def update_soul(self, text: str) -> str:
        soul = text.strip()
        if not soul:
            raise NoteRefused("die neue Seele war leer – nichts geändert")
        return await self._store(SOUL, soul + "\n", "Seele geändert")

    async def tidy(self, note: Note) -> bool:
        """Aufräumen nach der Fahrt: Haiku fasst die Datei unter die Grenze zusammen (gesichert wie jedes Schreiben).
        Gelingt das nicht, bleibt die Datei, wie sie war (nie abgeschnitten); das nächste Fahrtende versucht es neu."""
        text = self.read(note)
        condensed = await self._condense(note, text)
        if condensed is None:
            self._log(f"Aufräumen: {note.label} bleibt bei {len(text)} Zeichen – Zusammenfassung über {note.limit}")
            return False
        self._write(note, condensed)
        self._log(f"Aufräumen: {note.label} {len(text)} → {len(condensed)} Zeichen (Sicherung {note.file}.bak)")
        return True

    def needs_tidy(self, note: Note) -> bool:
        return note in self.changed or len(self.read(note)) > note.limit

    def _backup_once(self, note: Note) -> None:
        if note in self._backed_up:
            return  # .bak hält schon den Stand vor dieser Sitzung
        path = self.path(note)
        if path.exists():
            shutil.copyfile(path, path.with_name(path.name + BACKUP_SUFFIX))
        self._backed_up.add(note)

    async def _store(self, note: Note, text: str, done: str) -> str:
        if len(text) > note.limit:
            condensed = await self._condense(note, text)
            if condensed is None:
                raise NoteRefused(
                    f"{note.label} voll: auch zusammengefasst über {note.limit} Zeichen – nichts gespeichert"
                )
            text, done = condensed, f"{done} ({note.label} aufgeräumt, Sicherung {note.file}.bak)"
        self._write(note, text)
        self.changed.add(note)
        return done

    async def _condense(self, note: Note, text: str) -> str | None:
        for share in CONDENSE_TARGETS:
            result = (await self._summarize(prompts.condense_prompt(note.label, text, int(note.limit * share)))).strip()
            if result and len(result) + 1 <= note.limit:  # + Zeilenende
                return result + "\n"
        return None

    def _write(self, note: Note, text: str, backup: bool = True) -> None:
        if backup:
            self._backup_once(note)
        path = self.path(note)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        temp = path.with_name(path.name + ".tmp")
        temp.write_text(text, encoding="utf-8")
        os.replace(temp, path)
