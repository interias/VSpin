"""Echter Ears-Adapter (ADR-0011, #79): Mikrofon nur zwischen `companion_ptt down` und `up`, Erkennung lokal.

Das Mikrofon läuft höchstens `MAX_RECORDING_S` (15 s); danach hört es von selbst auf, auch wenn die Sprechtaste noch
gedrückt ist. Erkannt wird mit faster-whisper: `large-v3-turbo` auf CUDA (`int8_float16`), ohne CUDA `small` auf der
CPU (`int8`), immer `language="de"` mit VAD-Filter. Das Modell wird beim Start in einem eigenen Thread geladen und
gehalten. Kein Audio auf Platte – die Aufnahme ist ein `bytes`-Puffer (float32, mono, 16 kHz) im Speicher.

Die Logik (`LocalEars`, `choose_model`, `load_with_fallback`) steht hinter den Nahtstellen `Microphone` und
`Recognizer` und läuft in Tests ohne Mikrofon, Modell und GPU. `sounddevice`, `faster_whisper`, `ctranslate2` und
`numpy` (Extra `companion`) werden erst in den echten Teilen unten importiert.
"""

import asyncio
import concurrent.futures
import os
import sys
import threading
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .ports import Clock

MAX_RECORDING_S = 15.0
SAMPLE_RATE = 16_000
LANGUAGE = "de"
CUDA_MODEL = "large-v3-turbo"
CPU_MODEL = "small"
MODEL_DOWNLOAD_GB = {CUDA_MODEL: "1,6", CPU_MODEL: "0,5"}  # aus dem Hugging-Face-Hub, falls nicht im Cache


@dataclass(frozen=True, slots=True)
class ModelChoice:
    model: str
    device: str
    compute_type: str


def choose_model(cuda_available: bool) -> ModelChoice:
    """Mit CUDA `large-v3-turbo` auf der Grafikkarte, sonst `small` auf der CPU. Lädt nichts."""
    if cuda_available:
        return ModelChoice(CUDA_MODEL, "cuda", "int8_float16")
    return ModelChoice(CPU_MODEL, "cpu", "int8")


class Microphone(Protocol):
    def start(self) -> None:
        """Aufnahme beginnen."""
        ...

    def stop(self) -> bytes:
        """Aufnahme beenden und den Puffer liefern (float32, mono, 16 kHz); ohne Aufnahme: leer."""
        ...


class Recognizer(Protocol):
    def transcribe(self, audio: bytes) -> str:
        """Blockierend (läuft in einem Thread): erkannter Text, leer = nichts verstanden."""
        ...

    def warm_up(self) -> None:
        """Blockierend: einmal wirklich rechnen (Encoder auf dem Gerät), damit fehlende CUDA-Bibliotheken schon beim
        Laden auffallen und nicht erst beim ersten Satz des Fahrers; wirft, wenn das Gerät unbrauchbar ist."""
        ...


class LocalEars:
    def __init__(
        self,
        microphone: Microphone,
        load_recognizer: Callable[[], Recognizer],
        clock: Clock,
        *,
        max_seconds: float = MAX_RECORDING_S,
        log: Callable[[str], None] = lambda text: None,
    ) -> None:
        self._mic = microphone
        self._load = load_recognizer
        self._clock = clock
        self._max_seconds = max_seconds
        self._log = log
        self._loaded: concurrent.futures.Future[Recognizer] | None = None
        self._limit: asyncio.Task | None = None
        self._audio: bytes | None = None  # von der 15-s-Grenze bereits beendete Aufnahme

    def preload(self) -> None:
        """Lädt das Modell in einem eigenen Thread (beim Start des Prozesses); mehrfach aufrufbar."""
        if self._loaded is None:
            self._start_load()

    def _start_load(self) -> None:
        self._loaded = concurrent.futures.Future()
        threading.Thread(target=self._load_into, args=(self._loaded,), name="ears-load", daemon=True).start()

    def _load_into(self, future: concurrent.futures.Future) -> None:
        try:
            future.set_result(self._load())
        except BaseException as exc:  # auch SystemExit & Co. des Ladens: Toni wird heiser, der Prozess lebt
            future.set_exception(exc)

    async def start_listening(self) -> None:
        failure = None
        if self._loaded is not None and self._loaded.done() and self._loaded.exception() is not None:
            failure = self._loaded.exception()  # Laden gescheitert (z. B. erster Start ohne Netz)
            self._start_load()  # das nächste Drücken der Sprechtaste findet ein neuer Versuch vor
        else:
            self.preload()
        if failure is not None:
            raise failure  # gleich heiser statt nach dem Sprechen
        self._cancel_limit()
        self._audio = None
        self._mic.start()
        self._limit = asyncio.create_task(self._enforce_limit())

    async def stop_listening(self) -> str:
        self._cancel_limit()
        audio, self._audio = self._audio, None
        if audio is None:
            audio = self._mic.stop()
        if not audio:
            return ""
        self.preload()
        try:
            recognizer = await asyncio.wrap_future(self._loaded)
        except Exception:
            self._loaded = None  # gemeldet (Toni wird heiser): das nächste Drücken lädt von vorn
            raise
        text = await asyncio.to_thread(recognizer.transcribe, audio)
        return text.strip()

    async def _enforce_limit(self) -> None:
        await self._clock.sleep(self._max_seconds)
        self._audio = self._mic.stop()
        self._log(f"Aufnahme nach {self._max_seconds:g} s beendet (Höchstdauer)")

    def _cancel_limit(self) -> None:
        if self._limit is not None:
            self._limit.cancel()
            self._limit = None


def load_with_fallback(
    make_model: Callable[[ModelChoice], Recognizer], cuda_available: bool, log: Callable[[str], None]
) -> Recognizer:
    """Lädt das gewählte Modell und wärmt es auf; scheitert beides auf CUDA (fehlende cuBLAS/cuDNN-Bibliotheken,
    zu wenig Speicher), fällt Toni auf `small` auf der CPU zurück – wie ohne CUDA. `make_model` lädt nur."""

    def attempt(choice: ModelChoice) -> Recognizer:
        size = MODEL_DOWNLOAD_GB.get(choice.model, "?")
        log(
            f"Lade Erkennung {choice.model} ({choice.device}, {choice.compute_type}); beim ersten Mal rund {size} GB "
            "aus dem Hugging-Face-Hub, falls nicht im Cache – das dauert …"
        )
        recognizer = make_model(choice)
        recognizer.warm_up()
        return recognizer

    choice = choose_model(cuda_available)
    try:
        return attempt(choice)
    except Exception as exc:
        if choice.device != "cuda":
            raise
        log(f"CUDA unbrauchbar ({type(exc).__name__}: {exc}) – Erkennung mit {CPU_MODEL} auf der CPU")
        return attempt(choose_model(False))


# --- Echte Teile (Extra `companion`; nicht automatisch getestet) -----------------------------------------------


class SoundDeviceMicrophone:
    """Aufnahme vom Windows-Standardmikrofon, nur im Speicher; über `max_seconds` hinaus wird nichts mehr gepuffert."""

    def __init__(self, max_seconds: float = MAX_RECORDING_S) -> None:
        import sounddevice

        self._sd = sounddevice
        self._max_bytes = int(max_seconds * SAMPLE_RATE) * 4  # float32
        self._frames: list[bytes] = []
        self._size = 0
        self._stream = None

    def start(self) -> None:
        self.stop()
        self._frames, self._size = [], 0
        self._stream = self._sd.RawInputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="float32", callback=self._on_audio
        )
        self._stream.start()

    def stop(self) -> bytes:
        stream, self._stream = self._stream, None
        if stream is not None:
            stream.stop()
            stream.close()
        audio, self._frames, self._size = b"".join(self._frames), [], 0
        return audio

    def _on_audio(self, indata, frames, time, status) -> None:
        if self._size < self._max_bytes:
            chunk = bytes(indata)
            self._frames.append(chunk)
            self._size += len(chunk)


class FasterWhisperRecognizer:
    def __init__(self, model, numpy) -> None:
        self._model = model
        self._numpy = numpy

    def transcribe(self, audio: bytes) -> str:
        samples = self._numpy.frombuffer(audio, dtype=self._numpy.float32)
        segments, _ = self._model.transcribe(samples, language=LANGUAGE, vad_filter=True)
        return " ".join(segment.text.strip() for segment in segments).strip()

    def warm_up(self) -> None:
        """Rauschen statt Stille, ohne VAD-Filter (der würde alles verwerfen und das Gerät nie anfassen); der
        Segment-Generator wird ganz durchlaufen, denn erst dabei rechnet der Encoder."""
        numpy = self._numpy
        noise = (numpy.random.default_rng(0).standard_normal(2 * SAMPLE_RATE) * 0.1).astype(numpy.float32)
        segments, _ = self._model.transcribe(noise, language=LANGUAGE, vad_filter=False)
        for _segment in segments:
            pass


def load_faster_whisper(log: Callable[[str], None]) -> Recognizer:
    """Lädt faster-whisper (langsam, im Lade-Thread): CUDA erkennen, Modell laden, aufwärmen (`warm_up`) – so zeigt
    sich ein kaputtes CUDA hier und nicht erst beim ersten Satz des Fahrers."""
    import ctranslate2
    import numpy
    from faster_whisper import WhisperModel

    _add_nvidia_dll_directories()
    try:
        cuda = ctranslate2.get_cuda_device_count() > 0
    except Exception:
        cuda = False

    def make(choice: ModelChoice) -> Recognizer:
        return FasterWhisperRecognizer(
            WhisperModel(choice.model, device=choice.device, compute_type=choice.compute_type), numpy
        )

    recognizer = load_with_fallback(make, cuda, log)
    log("Erkennung bereit")
    return recognizer


def _add_nvidia_dll_directories() -> None:
    """Unter Windows: cuBLAS/cuDNN aus den pip-Paketen `nvidia-cublas-cu12` und `nvidia-cudnn-cu12` auffindbar machen
    (deren `bin`-Ordner liegen in site-packages/nvidia/<paket>/bin). Ungeprüft; ohne die Pakete wirkungslos."""
    if sys.platform != "win32":
        return
    import importlib.util

    for package in ("nvidia.cublas", "nvidia.cudnn"):
        try:
            spec = importlib.util.find_spec(package)
        except (ImportError, ValueError):
            continue
        for location in (spec.submodule_search_locations or []) if spec else []:
            bin_dir = Path(location) / "bin"
            if bin_dir.is_dir():
                os.add_dll_directory(str(bin_dir))
                os.environ["PATH"] = f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}"


def create_ears(clock: Clock, log: Callable[[str], None]) -> LocalEars:
    """Die echten Ohren; wirft `ImportError`/`OSError`, wenn `sounddevice` (PortAudio) fehlt. `faster_whisper` wird
    erst im Lade-Thread importiert: fehlt es, wird Toni beim ersten Drücken der Sprechtaste heiser."""
    return LocalEars(SoundDeviceMicrophone(), lambda: load_faster_whisper(log), clock, log=log)
