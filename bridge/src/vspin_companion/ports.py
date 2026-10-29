"""Nahtstellen des Begleiters (Spec #76): Die Logik kennt nur diese Ports, nie die echten Dienste.

Jeder Port hat einen Fake (`fakes.py`) und – ab #78/#79 – einen echten Adapter, der seine schweren Abhängigkeiten
(Extra `companion`) erst beim Erzeugen importiert. Jede Ausnahme eines Ports macht Toni **heiser**
(`companion_status: hoarse`); der Prozess läuft weiter.
"""

from collections.abc import AsyncIterator, Awaitable, Callable, Sequence
from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True, slots=True)
class ToolCall:
    """Werkzeugaufruf des Brain mitten in seiner Antwort: `remember(text)`, `update_soul(text)`,
    `set_wake_interval(min_minutes, max_minutes)`, `stay_silent(until_ride_end)` (#78)."""

    name: str
    arguments: dict = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class ToolResult:
    """Ergebnis eines Werkzeugs für das Brain; `is_error` meldet einen Fehlschlag (Haiku liest den Text)."""

    text: str
    is_error: bool = False


# Führt einen Werkzeugaufruf aus (Logik des Begleiters: Gedächtnis, Seele, Wecker) – das Brain ruft ihn mitten in
# seiner Antwort und gibt das Ergebnis an das Modell weiter.
ToolHandler = Callable[[ToolCall], Awaitable[ToolResult]]


class Brain(Protocol):
    """Das Denken (LLM, ADR-0011): eine Sitzung je Fahrt mit festem Systemprompt und Werkzeugen."""

    async def open_session(self, system_prompt: str, tools: ToolHandler) -> None:
        """Neue Sitzung (Gesprächsverlauf leer) mit `system_prompt`; Werkzeugaufrufe gehen an `tools`."""
        ...

    async def close_session(self) -> None:
        """Sitzung beenden, der Verlauf ist weg (lebt nur im Speicher, ADR-0008); ohne Sitzung wirkungslos."""
        ...

    def respond(self, prompt: str) -> AsyncIterator[str | ToolCall]:
        """Antwort auf `prompt` in der offenen Sitzung als Strom: Textstücke in der Reihenfolge, in der sie
        entstehen (noch nicht an Satzgrenzen geteilt), dazwischen die Werkzeugaufrufe – zur Kenntnis, ausgeführt hat
        sie `tools` schon. Ein leerer Strom heißt: Toni schweigt."""
        ...

    async def summarize(self, prompt: str) -> str:
        """Einmaliger Auftrag außerhalb der Sitzung, ohne Werkzeuge und ohne Seele (Aufräumen von Seele und
        Gedächtnis); liefert den ganzen Text."""
        ...


class Ears(Protocol):
    """Das Hören: Aufnahme nur zwischen Drücken und Loslassen der Sprechtaste, Erkennung lokal (ADR-0011)."""

    async def start_listening(self) -> None:
        """Sprechtaste gedrückt: Aufnahme beginnen."""
        ...

    async def stop_listening(self) -> str:
        """Sprechtaste losgelassen: Aufnahme beenden und erkannten Text liefern (leer = nichts verstanden)."""
        ...


@dataclass(frozen=True, slots=True)
class SpeechUsage:
    """Was die Stimme seit dem letzten `take_usage` verbraucht hat: gesprochene Zeichen, Anfragen an den Dienst und
    deren Generation-IDs (OpenRouter `X-Generation-Id`); eine Anfrage ohne ID zählt in `requests`, nicht in `ids`."""

    chars: int = 0
    requests: int = 0
    generation_ids: tuple[str, ...] = ()
    aborted: int = 0  # abgebrochene Synthesen (Barge-in): OpenRouter berechnet sie womöglich, wir sehen keine ID


class Mouth(Protocol):
    """Das Sprechen: Stimme und Wiedergabe (ADR-0011).

    `speak` darf für mehrere Sätze **gleichzeitig** laufen (der Begleiter gibt jeden Satz sofort weiter, während Haiku
    noch schreibt): Der Mund synthetisiert sofort, spielt aber strikt in der Reihenfolge der Aufrufe."""

    async def speak(self, sentence: str, on_start: Callable[[], None] | None = None) -> None:
        """Einen Satz sprechen; kehrt zurück, wenn er zu Ende gespielt (oder abgebrochen) ist. `on_start` wird
        gerufen, sobald tatsächlich Ton zu hören ist (Antwortzeit, Status `speaking`)."""
        ...

    async def stop(self) -> None:
        """Laufende Wiedergabe **und** offene Synthese sofort abbrechen (Barge-in, #79); sonst wirkungslos."""
        ...

    def set_volume(self, volume: float) -> None:
        """Lautstärke 0..1 für alles, was ab jetzt gespielt wird (`companion_volume` des Spiels)."""
        ...

    def take_usage(self) -> SpeechUsage:
        """Verbrauch seit dem letzten Aufruf liefern und zurücksetzen."""
        ...

    async def cost_of(self, generation_ids: Sequence[str], patient: bool = True) -> dict[str, float]:
        """Kosten in Dollar je Generation-ID laut Dienst. Der Dienst liefert den Datensatz erst kurz nach der Synthese:
        der Mund wartet und fragt bei Bedarf mehrmals nach; was er danach nicht kennt, fehlt im Ergebnis.
        `patient=False`: nur eine Abfrage, ohne Wartezeit (letzter Versuch beim Beenden)."""
        ...


class Clock(Protocol):
    """Die Zeit des Begleiters: monotone Sekunden und Warten (Wecker, Antwortzeiten)."""

    def now(self) -> float:
        ...

    async def sleep(self, seconds: float) -> None:
        ...
