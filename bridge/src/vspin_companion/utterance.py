"""Eine Antwort Tonis in Rede (#79): Satz für Satz an den Mund, während Haiku noch schreibt.

Jeder fertige Satz geht sofort an `Mouth.speak` (eigene Aufgabe); der Mund synthetisiert gleich los und spielt in
der Reihenfolge der Aufrufe. So ist der erste Satz schon zu hören, bevor der zweite geschrieben ist (Ziel ≤ 2,5 s
vom Loslassen bis zum ersten Ton). Abbruch (Barge-in, Fehler) bricht alle offenen Sätze ab.
"""

import asyncio
from collections.abc import Awaitable, Callable

from . import prompts
from .ports import Mouth
from .sentences import SentenceSplitter, first_sentence


class Utterance:
    """`feed` mit jedem Textstück, am Ende `finish` (wartet, bis alles gespielt ist); `cancel` bricht ab.

    `one_sentence`: wird je Satz gefragt – in harten Phasen spricht Toni nur den ersten, und von dem nur bis zum
    ersten Satzzeichen mit Leerraum (durchgesetzt, nicht nur im Prompt). `gate`: vor dem ersten Satz gefragt; `False` verwirft die ganze Antwort (Wecker: Toni wurde unterdessen
    angesprochen). `on_sound`: läuft, sobald der erste Ton tatsächlich spielt."""

    def __init__(
        self,
        mouth: Mouth,
        *,
        one_sentence: Callable[[], bool] = lambda: False,
        gate: Callable[[], bool] | None = None,
        on_sound: Callable[[], Awaitable[None]] | None = None,
    ) -> None:
        self._mouth = mouth
        self._one_sentence = one_sentence
        self._gate = gate
        self._on_sound = on_sound
        self._splitter = SentenceSplitter()
        self._tasks: list[asyncio.Task] = []
        self._sound_task: asyncio.Task | None = None
        self.sentences: list[str] = []  # was an den Mund ging
        self.discarded = False  # das Tor hat die Antwort verworfen

    def feed(self, text: str) -> None:
        for sentence in self._splitter.feed(text):
            self._say(sentence)

    async def finish(self) -> None:
        """Rest des Textes sprechen und warten, bis alle Sätze zu Ende gespielt sind; ein Fehler des Mundes fliegt
        hier (die übrigen Sätze werden dann abgebrochen)."""
        for sentence in self._splitter.flush():
            self._say(sentence)
        try:
            await asyncio.gather(*self._tasks)
            if self._sound_task is not None:
                await self._sound_task
        except BaseException:
            self.cancel()
            raise

    def cancel(self) -> None:
        for task in [*self._tasks, self._sound_task]:
            if task is not None:
                task.cancel()

    def _say(self, sentence: str) -> None:
        if self.discarded or (self.sentences and self._one_sentence()) or prompts.is_silence(sentence):
            return
        if not self.sentences and self._gate is not None and not self._gate():
            self.discarded = True
            return
        first = not self.sentences
        if self._one_sentence():
            sentence = first_sentence(sentence)  # nicht weicher als #78: „Puls ist 142. Locker bleiben.“ sind zwei
        self.sentences.append(sentence)
        task = asyncio.create_task(self._mouth.speak(sentence, self._started if first else None))
        task.add_done_callback(lambda done: done.cancelled() or done.exception())  # Fehler holt `finish` ab
        self._tasks.append(task)

    def _started(self) -> None:
        if self._on_sound is not None and self._sound_task is None:
            self._sound_task = asyncio.create_task(self._on_sound())
