"""Fakes für alle Ports (Spec #76, Testing Decisions): kein Claude, kein OpenRouter, kein Mikrofon, keine GPU.

Geskriptet wird über Listen, die der Reihe nach verbraucht werden; eine Ausnahme in einer Liste wird an dieser
Stelle geworfen statt geliefert. `fail_*` wirft beim nächsten Aufruf genau einmal.
"""

import asyncio
import json
from collections.abc import AsyncIterator, Callable, Sequence

from .ports import SpeechUsage, ToolCall, ToolHandler, ToolResult


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
    """Zeichnet die Sätze auf, die der Begleiter ihm gibt (`spoken`), die zu Ende gespielten (`played`) und die
    Abbrüche (`stops`); spielt nichts ab. Wie der echte Mund beginnt er sofort (`on_start`), und `speak` darf für
    mehrere Sätze gleichzeitig laufen.

    `hold=True`: `speak` kehrt erst nach `release()` zurück (oder wird abgebrochen) – für Barge-in-Tests.
    Verbrauch: jeder Satz zählt als eine Anfrage mit der ID `gen-<n>` (`generation_ids=False`: ohne ID);
    `costs` sind die Kosten, die „die Generation-API“ schon kennt – der Test füllt sie, wann er will."""

    def __init__(
        self,
        *,
        hold: bool = False,
        costs: dict[str, float] | None = None,
        generation_ids: bool = True,
        patient_blocks: bool = False,
    ) -> None:
        self.spoken: list[str] = []
        self.played: list[str] = []
        self.stops = 0
        self.fail_speak: Exception | None = None
        self.hold = hold
        self.volumes: list[float] = []  # jede Lautstärke, die gesetzt wurde, in der Reihenfolge
        self.costs = dict(costs or {})
        self.cost_calls: list[list[str]] = []
        self.fail_cost: Exception | None = None
        self.fail_usage: Exception | None = None
        self.aborted = 0  # abgebrochene Synthesen, die `take_usage` meldet
        self.patient_blocks = patient_blocks  # geduldiger Kostenabruf hängt (OpenRouter hat den Datensatz nie)
        self.patient_calls: list[bool] = []
        self._ids = generation_ids
        self._chars = 0
        self._requests = 0
        self._generation_ids: list[str] = []
        self._count = 0
        self._loop: asyncio.AbstractEventLoop | None = None
        self._released = False
        self._event: asyncio.Event | None = None

    async def speak(self, sentence: str, on_start: Callable[[], None] | None = None) -> None:
        self._loop = asyncio.get_running_loop()
        if on_start is not None:
            on_start()
        if self.fail_speak is not None:  # Wiedergabe bricht ab: der Satz gilt nicht als gesprochen
            error, self.fail_speak = self.fail_speak, None
            raise error
        self.spoken.append(sentence)
        self._chars += len(sentence)
        self._requests += 1
        if self._ids:
            self._count += 1
            self._generation_ids.append(f"gen-{self._count}")
        if self.hold and not self._released:
            self._event = self._event or asyncio.Event()
            await self._event.wait()
        self.played.append(sentence)

    def release(self) -> None:
        """Lässt alle wartenden (und künftigen) `speak` zu Ende kommen; aus jedem Thread aufrufbar."""
        self._released = True
        if self._loop is not None and self._event is not None:
            self._loop.call_soon_threadsafe(self._event.set)

    async def stop(self) -> None:
        self.stops += 1

    def set_volume(self, volume: float) -> None:
        self.volumes.append(volume)

    def take_usage(self) -> SpeechUsage:
        if self.fail_usage is not None:
            error, self.fail_usage = self.fail_usage, None
            raise error
        usage = SpeechUsage(self._chars, self._requests, tuple(self._generation_ids), self.aborted)
        self._chars, self._requests, self._generation_ids, self.aborted = 0, 0, [], 0
        return usage

    async def cost_of(self, generation_ids: Sequence[str], patient: bool = True) -> dict[str, float]:
        self.cost_calls.append(list(generation_ids))
        self.patient_calls.append(patient)
        if patient and self.patient_blocks:
            await asyncio.Event().wait()
        if self.fail_cost is not None:
            error, self.fail_cost = self.fail_cost, None
            raise error
        return {i: self.costs[i] for i in generation_ids if i in self.costs}


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


class FakeHttp:
    """Fake für `openrouter.Http`: zeichnet Anfragen auf (`requests`: Methode, URL, Header, Körper als Text) und
    antwortet nach `respond(method, url, body)` – Standard: Synthese mit MP3-Bytes und `X-Generation-Id: gen-<n>`,
    Generation-Abfrage mit `costs`. `hold`: Synthese-Anfragen warten auf `release()` (offene Synthese beim Abbruch).
    Eine Ausnahme aus `respond` wird geworfen (Netzfehler)."""

    def __init__(self, costs: dict[str, float] | None = None, hold: bool = False) -> None:
        self.requests: list[tuple[str, str, dict[str, str], str]] = []
        self.costs = dict(costs or {})
        self.respond: Callable | None = None
        self.hold = hold
        self.started = 0  # Synthese-Anfragen, die angekommen sind
        self.finished = 0  # davon beantwortet
        self._loop: asyncio.AbstractEventLoop | None = None
        self._event: asyncio.Event | None = None
        self._speech_count = 0

    async def request(self, method: str, url: str, headers: dict[str, str], body: bytes | None = None):
        from .openrouter import HttpResponse

        text = body.decode("utf-8") if body else ""
        self.requests.append((method, url, dict(headers), text))
        if self.respond is not None:
            outcome = self.respond(method, url, text)
            if isinstance(outcome, Exception):
                raise outcome
            if outcome is not None:
                return outcome
        if method == "POST":
            self.started += 1
            if self.hold:
                self._loop = asyncio.get_running_loop()
                self._event = self._event or asyncio.Event()
                await self._event.wait()
            self._speech_count += 1
            self.finished += 1
            return HttpResponse(200, {"x-generation-id": f"gen-{self._speech_count}"}, b"MP3:" + json.loads(text)["input"].encode("utf-8"))
        generation_id = url.rsplit("id=", 1)[-1]
        if generation_id in self.costs:
            return HttpResponse(200, {}, f'{{"data": {{"total_cost": {self.costs[generation_id]}}}}}'.encode())
        return HttpResponse(404, {}, b'{"error": {"code": 404, "message": "not found"}}')

    def release(self) -> None:
        self.hold = False
        if self._loop is not None and self._event is not None:
            self._loop.call_soon_threadsafe(self._event.set)


class FakeDecoder:
    """Fake für `mouth.Decoder`: macht aus „MP3:<Satz>“ einen PCM-Puffer, der den Satz in `samples` trägt."""

    def decode(self, mp3: bytes):
        from .mouth import Pcm

        return Pcm(mp3.removeprefix(b"MP3:"), 24_000)


class FakePlayer:
    """Fake für `mouth.Player`: `played` (Satz, Lautstärke beim Start), `stopped` (Aufrufe von `stop`). Ein Satz
    „dauert“ bis `finish()` (`block=True`) oder ist sofort zu Ende; `stop` beendet die laufende Wiedergabe."""

    def __init__(self, block: bool = False) -> None:
        self.played: list[tuple[str, float]] = []
        self.finished: list[str] = []
        self.stopped = 0
        self.block = block
        self._loop: asyncio.AbstractEventLoop | None = None
        self._event: asyncio.Event | None = None
        self._aborted = False

    async def play(self, pcm, volume: Callable[[], float], on_start: Callable[[], None] | None) -> None:
        sentence = pcm.samples.decode("utf-8")
        self._aborted = False
        self.played.append((sentence, volume()))
        if on_start is not None:
            on_start()
        if self.block:
            self._loop = asyncio.get_running_loop()
            self._event = asyncio.Event()
            try:
                await self._event.wait()
            except asyncio.CancelledError:
                return
        if not self._aborted:
            self.finished.append(sentence)

    def finish(self) -> None:
        """Die laufende Wiedergabe ist zu Ende (aus jedem Thread aufrufbar)."""
        if self._loop is not None and self._event is not None:
            self._loop.call_soon_threadsafe(self._event.set)

    def stop(self) -> None:
        self.stopped += 1
        self._aborted = True
        self.finish()


class FakeMicrophone:
    """Fake für `ears.Microphone`: `started`/`stopped` zählen, `audio` ist, was `stop` liefert."""

    def __init__(self, audio: bytes = b"audio") -> None:
        self.audio = audio
        self.started = 0
        self.stopped = 0
        self.recording = False

    def start(self) -> None:
        self.started += 1
        self.recording = True

    def stop(self) -> bytes:
        self.stopped += 1
        audio, self.recording = (self.audio if self.recording else b""), False
        return audio


class FakeRecognizer:
    """Fake für `ears.Recognizer`: liefert `text` und merkt sich, was es hören sollte."""

    def __init__(self, text: str = "Wie weit noch?", warm_up_error: Exception | None = None) -> None:
        self.text = text
        self.heard: list[bytes] = []
        self.warm_up_error = warm_up_error
        self.warmed_up = 0

    def warm_up(self) -> None:
        self.warmed_up += 1
        if self.warm_up_error is not None:
            raise self.warm_up_error

    def transcribe(self, audio: bytes) -> str:
        self.heard.append(audio)
        return self.text
