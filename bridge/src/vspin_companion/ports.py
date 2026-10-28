"""Nahtstellen des Begleiters (Spec #76): Die Logik kennt nur diese Ports, nie die echten Dienste.

Jeder Port hat einen Fake (`fakes.py`) und – ab #78/#79 – einen echten Adapter, der seine schweren Abhängigkeiten
(Extra `companion`) erst beim Erzeugen importiert. Jede Ausnahme eines Ports macht Toni **heiser**
(`companion_status: hoarse`); der Prozess läuft weiter.
"""

from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True, slots=True)
class ToolCall:
    """Werkzeugaufruf des Brain mitten in seiner Antwort, z. B. `remember(text)` (#78)."""

    name: str
    arguments: dict = field(default_factory=dict)


class Brain(Protocol):
    """Das Denken (LLM, ADR-0011)."""

    def respond(self, prompt: str) -> AsyncIterator[str | ToolCall]:
        """Antwort auf `prompt` als Strom: Textstücke in der Reihenfolge, in der sie entstehen (noch nicht an
        Satzgrenzen geteilt), dazwischen Werkzeugaufrufe. Ein leerer Strom heißt: Toni schweigt."""
        ...


class Ears(Protocol):
    """Das Hören: Aufnahme nur zwischen Drücken und Loslassen der Sprechtaste, Erkennung lokal (ADR-0011)."""

    async def start_listening(self) -> None:
        """Sprechtaste gedrückt: Aufnahme beginnen."""
        ...

    async def stop_listening(self) -> str:
        """Sprechtaste losgelassen: Aufnahme beenden und erkannten Text liefern (leer = nichts verstanden)."""
        ...


class Mouth(Protocol):
    """Das Sprechen: Stimme und Wiedergabe (ADR-0011)."""

    async def speak(self, sentence: str) -> None:
        """Einen Satz sprechen; kehrt zurück, wenn er zu Ende gespielt (oder per `stop` abgebrochen) ist."""
        ...

    async def stop(self) -> None:
        """Laufende Wiedergabe sofort abbrechen (Barge-in, #79); ohne Wiedergabe wirkungslos."""
        ...


class Clock(Protocol):
    """Die Zeit des Begleiters: monotone Sekunden und Warten (Wecker, Antwortzeiten)."""

    def now(self) -> float:
        ...

    async def sleep(self, seconds: float) -> None:
        ...
