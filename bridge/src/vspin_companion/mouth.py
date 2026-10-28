"""Echter Mouth-Adapter (ADR-0011, #79): Sätze über OpenRouter synthesieren und über das Windows-Standardgerät spielen.

Die Logik (Reihenfolge, Abbruch, Verbrauch, Kostenabruf) steht hinter drei Nahtstellen und läuft in Tests mit Fakes:
`OpenRouterClient` (HTTP, `openrouter.py`), `Decoder` (MP3 → PCM) und `Player` (PCM → Lautsprecher). Die echten
`AvDecoder` und `SoundDevicePlayer` importieren `av` und `sounddevice` (Extra `companion`) erst beim Erzeugen; ohne
die Pakete wird Toni heiser, der Prozess läuft weiter. Kein Audio wird gespeichert – MP3 und PCM leben im Speicher.

`speak` darf für mehrere Sätze gleichzeitig laufen: Jeder Satz wird sofort synthetisiert (so ist Satz 2 fertig,
während Satz 1 noch spielt), gespielt wird strikt in der Reihenfolge der Aufrufe.
"""

import asyncio
import io
import threading
from array import array
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from typing import Protocol

from .openrouter import OpenRouterClient
from .ports import SpeechUsage

# Abstände (Sekunden), in denen nach den Kosten gefragt wird: OpenRouters Generation-API hat den Datensatz erst
# kurz nach der Synthese.
COST_DELAYS_S = (5.0, 15.0, 45.0)
CHUNK_S = 0.05  # Wiedergabe in Stücken von 50 ms: Abbruch und Lautstärkewechsel wirken fast sofort


@dataclass(frozen=True, slots=True)
class Pcm:
    samples: bytes  # 16 Bit, mono, native Byte-Reihenfolge
    rate: int


class Decoder(Protocol):
    def decode(self, mp3: bytes) -> Pcm:
        """Blockierend; läuft in einem Thread."""
        ...


class Player(Protocol):
    async def play(self, pcm: Pcm, volume: Callable[[], float], on_start: Callable[[], None] | None) -> None:
        """Spielt `pcm`; `on_start` genau dann, wenn der erste Ton ausgegeben wird (aus dem Loop-Thread gerufen).
        Kehrt zurück, wenn zu Ende gespielt oder per `stop` abgebrochen."""
        ...

    def stop(self) -> None:
        """Bricht die laufende Wiedergabe sofort ab."""
        ...


class OpenRouterMouth:
    def __init__(
        self,
        client: OpenRouterClient,
        decoder: Decoder,
        player: Player,
        *,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        cost_delays: Sequence[float] = COST_DELAYS_S,
        log: Callable[[str], None] = lambda text: None,
    ) -> None:
        self._client = client
        self._decoder = decoder
        self._player = player
        self._sleep = sleep
        self._cost_delays = tuple(cost_delays)
        self._log = log
        self._volume = 1.0  # bis das Spiel `companion_volume` meldet
        self._tail: asyncio.Event | None = None  # „vorheriger Satz ist durch“
        self._epoch = 0  # `stop` zählt hoch: Sätze davor werden nicht mehr gespielt
        self._synths: set[asyncio.Task] = set()
        self._chars = 0
        self._requests = 0
        self._ids: list[str] = []
        self._aborted = 0

    async def speak(self, sentence: str, on_start: Callable[[], None] | None = None) -> None:
        epoch = self._epoch
        previous, mine = self._tail, asyncio.Event()
        self._tail = mine
        synth = asyncio.ensure_future(self._synthesize(sentence))
        self._synths.add(synth)
        try:
            try:
                pcm = await synth
            except asyncio.CancelledError:
                if epoch != self._epoch:
                    return  # `stop` hat die Synthese abgebrochen – der Satz wird nicht mehr gesprochen
                raise
            if previous is not None:
                await previous.wait()
            if epoch != self._epoch:
                return  # unterbrochen, während dieser Satz wartete
            await self._player.play(pcm, lambda: self._volume, on_start)
        finally:
            synth.cancel()
            self._synths.discard(synth)
            mine.set()

    async def stop(self) -> None:
        """Barge-in: Wiedergabe und offene Synthese abbrechen, auch die noch ausstehenden Sätze."""
        self._epoch += 1
        self._tail = None
        for synth in list(self._synths):
            synth.cancel()
        self._player.stop()

    def set_volume(self, volume: float) -> None:
        self._volume = min(1.0, max(0.0, volume))

    def take_usage(self) -> SpeechUsage:
        usage = SpeechUsage(self._chars, self._requests, tuple(self._ids), self._aborted)
        self._chars, self._requests, self._ids, self._aborted = 0, 0, [], 0
        return usage

    async def cost_of(self, generation_ids: Sequence[str], patient: bool = True) -> dict[str, float]:
        costs: dict[str, float] = {}
        for delay in (0.0, *(self._cost_delays if patient else ())):
            if delay:
                await self._sleep(delay)
            for generation_id in generation_ids:
                if generation_id in costs:
                    continue
                try:
                    cost = await self._client.generation_cost(generation_id)
                except Exception as exc:  # Netz oder Dienst: später nochmal, am Ende bleibt es „unbekannt“
                    self._log(f"Kosten von {generation_id} nicht abgeholt – {type(exc).__name__}: {exc}")
                    continue
                if cost is not None:
                    costs[generation_id] = cost
            if len(costs) == len(set(generation_ids)):
                break
        return costs

    async def _synthesize(self, sentence: str) -> Pcm:
        try:
            speech = await self._client.speech(sentence)
        except asyncio.CancelledError:
            self._aborted += 1  # unterwegs abgebrochen: berechnet wird sie womöglich trotzdem
            raise
        # Verbrauch zählt, sobald OpenRouter geantwortet hat (dann ist es berechnet); eine abgebrochene Anfrage
        # ohne Antwort bleibt unsichtbar – ihre Kosten stehen nirgends im Protokoll.
        self._chars += len(sentence)
        self._requests += 1
        if speech.generation_id:
            self._ids.append(speech.generation_id)
        return await asyncio.to_thread(self._decoder.decode, speech.audio)


def scale_pcm(samples: bytes, volume: float) -> bytes:
    """16-Bit-PCM mit `volume` (0..1) multiplizieren."""
    if volume >= 1.0:
        return samples
    if volume <= 0.0:
        return bytes(len(samples))
    data = array("h")
    data.frombytes(samples)
    return array("h", (int(value * volume) for value in data)).tobytes()


class AvDecoder:
    """MP3 → 16-Bit-PCM mit PyAV (`av`, kommt mit faster-whisper)."""

    def __init__(self) -> None:
        import av

        self._av = av

    def decode(self, mp3: bytes) -> Pcm:
        av = self._av
        with av.open(io.BytesIO(mp3)) as container:
            stream = container.streams.audio[0]
            rate = stream.rate
            resampler = av.AudioResampler(format="s16", layout="mono", rate=rate)
            chunks: list[bytes] = []
            for frame in container.decode(stream):
                chunks.extend(out.to_ndarray().tobytes() for out in resampler.resample(frame))
            chunks.extend(out.to_ndarray().tobytes() for out in resampler.resample(None))
        return Pcm(b"".join(chunks), rate)


class SoundDevicePlayer:
    """Wiedergabe über das Standardgerät von Windows (`sounddevice`/PortAudio, `device=None`)."""

    def __init__(self) -> None:
        import sounddevice

        self._sd = sounddevice
        self._abort = threading.Event()
        self._stream = None

    async def play(self, pcm: Pcm, volume: Callable[[], float], on_start: Callable[[], None] | None) -> None:
        loop = asyncio.get_running_loop()
        self._abort.clear()
        await asyncio.to_thread(self._play, pcm, volume, on_start, loop)

    def stop(self) -> None:
        self._abort.set()
        stream = self._stream
        if stream is not None:
            try:
                stream.abort()
            except Exception:  # der Wiedergabe-Thread räumt selbst auf
                pass

    def _play(self, pcm: Pcm, volume, on_start, loop: asyncio.AbstractEventLoop) -> None:
        step = int(pcm.rate * CHUNK_S) * 2  # Bytes je Stück (16 Bit)
        stream = self._sd.RawOutputStream(samplerate=pcm.rate, channels=1, dtype="int16")
        self._stream = stream
        try:
            stream.start()
            if on_start is not None:
                loop.call_soon_threadsafe(on_start)
            for offset in range(0, len(pcm.samples), step):
                if self._abort.is_set():
                    return
                stream.write(scale_pcm(pcm.samples[offset : offset + step], volume()))
            if not self._abort.is_set():
                stream.stop()  # wartet, bis alles gespielt ist
        except Exception:
            if not self._abort.is_set():  # ein Abbruch per `stop` ist kein Fehler
                raise
        finally:
            self._stream = None
            stream.close()


def create_mouth(client: OpenRouterClient, log: Callable[[str], None]) -> OpenRouterMouth:
    """Der echte Mund; wirft `ImportError`/`OSError`, wenn `av` oder `sounddevice` (PortAudio) fehlen."""
    return OpenRouterMouth(client, AvDecoder(), SoundDevicePlayer(), log=log)
