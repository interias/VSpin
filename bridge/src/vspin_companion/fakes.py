"""Fakes für alle Ports (Spec #76, Testing Decisions): kein Claude, kein OpenRouter, kein Mikrofon, keine GPU.

Geskriptet wird über Listen, die der Reihe nach verbraucht werden; eine Ausnahme in einer Liste wird an dieser
Stelle geworfen statt geliefert. `fail_*` wirft beim nächsten Aufruf genau einmal.
"""

import asyncio
from collections.abc import AsyncIterator

from .ports import ToolCall, ToolHandler, ToolResult


class FakeBrain:
    """`replies`: je `respond` eine Antwort – Liste aus Textstücken und `ToolCall`s (eine Ausnahme darin bricht
    die Antwort an dieser Stelle ab) oder eine Ausnahme, die sofort fliegt. Ein `ToolCall` wird wie beim echten
    Brain über die Werkzeuge der Sitzung ausgeführt, dann geliefert; Ergebnis in `tool_results`. `prompts` zeichnet
    jede Anfrage auf, `sessions` den Systemprompt jeder geöffneten Sitzung. `summaries`: je `summarize` der Text
    (oder eine Ausnahme), ohne weiteren Eintrag leer; Aufträge in `summary_prompts`."""

    def __init__(
        self,
        replies: list[list[str | ToolCall | Exception] | Exception] | None = None,
        summaries: list[str | Exception] | None = None,
    ) -> None:
        self.replies = list(replies or [])
        self.prompts: list[str] = []
        self.summaries = list(summaries or [])
        self.summary_prompts: list[str] = []
        self.sessions: list[str] = []
        self.closed = 0
        self.fail_open: Exception | None = None
        self.tool_results: list[tuple[ToolCall, ToolResult]] = []
        self._tools: ToolHandler | None = None

    async def open_session(self, system_prompt: str, tools: ToolHandler) -> None:
        if self.fail_open is not None:
            error, self.fail_open = self.fail_open, None
            raise error
        self.sessions.append(system_prompt)
        self._tools = tools

    async def close_session(self) -> None:
        self.closed += 1
        self._tools = None

    async def respond(self, prompt: str) -> AsyncIterator[str | ToolCall]:
        self.prompts.append(prompt)
        reply = self.replies.pop(0) if self.replies else []
        if isinstance(reply, Exception):
            raise reply
        for item in reply:
            if isinstance(item, Exception):
                raise item
            await asyncio.sleep(0)  # Stück für Stück, wie ein Strom
            if isinstance(item, ToolCall) and self._tools is not None:
                self.tool_results.append((item, await self._tools(item)))
            yield item

    async def summarize(self, prompt: str) -> str:
        self.summary_prompts.append(prompt)
        summary = self.summaries.pop(0) if self.summaries else ""
        if isinstance(summary, Exception):
            raise summary
        return summary


class FakeEars:
    """`transcripts`: je `stop_listening` der erkannte Text (oder eine Ausnahme). Text statt Audio."""

    def __init__(self, transcripts: list[str | Exception] | None = None) -> None:
        self.transcripts = list(transcripts or [])
        self.fail_start: Exception | None = None
        self.listening = False
        self.sessions = 0  # wie oft die Aufnahme begonnen hat

    async def start_listening(self) -> None:
        if self.fail_start is not None:
            error, self.fail_start = self.fail_start, None
            raise error
        self.listening = True
        self.sessions += 1

    async def stop_listening(self) -> str:
        self.listening = False
        text = self.transcripts.pop(0) if self.transcripts else ""
        if isinstance(text, Exception):
            raise text
        return text


class FakeMouth:
    """Zeichnet gesprochene Sätze (`spoken`) und Abbrüche (`stops`) auf; spielt nichts ab."""

    def __init__(self) -> None:
        self.spoken: list[str] = []
        self.stops = 0
        self.fail_speak: Exception | None = None

    async def speak(self, sentence: str) -> None:
        if self.fail_speak is not None:
            error, self.fail_speak = self.fail_speak, None
            raise error
        self.spoken.append(sentence)

    async def stop(self) -> None:
        self.stops += 1


class FakeClock:
    """Zeit nur auf Befehl: `advance(s)` rückt vor und weckt alle, deren `sleep` damit abgelaufen ist."""

    def __init__(self, start: float = 0.0) -> None:
        self._now = start
        self._sleepers: list[tuple[float, asyncio.Future]] = []
        self.fail_now: Exception | None = None

    def now(self) -> float:
        if self.fail_now is not None:
            error, self.fail_now = self.fail_now, None
            raise error
        return self._now

    async def sleep(self, seconds: float) -> None:
        if seconds <= 0:
            await asyncio.sleep(0)
            return
        future = asyncio.get_running_loop().create_future()
        self._sleepers.append((self._now + seconds, future))
        await future

    def pending(self) -> list[float]:
        """Zeitpunkte, zu denen gerade jemand schläft (aufsteigend) – Tests sehen so, wann der Wecker klingelt."""
        return sorted(t for t, f in list(self._sleepers) if not f.done())

    def advance(self, seconds: float) -> None:
        """Nur im Event-Loop der Schläfer aufrufen (Tests im Thread: `loop.call_soon_threadsafe`)."""
        self._now += seconds
        due = [(t, f) for t, f in self._sleepers if t <= self._now]
        self._sleepers = [(t, f) for t, f in self._sleepers if t > self._now]
        for _, future in due:
            if not future.done():
                future.set_result(None)
