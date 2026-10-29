"""Ohren des Begleiters (Spec #76, #79): Aufnahme endet bei `up` oder nach 15 s, Modellwahl CUDA/CPU, Laden im Hintergrund –
nur mit Fake-Mikrofon und Fake-Erkenner (kein Mikrofon, kein Modell, keine GPU, kein `faster_whisper`)."""

import asyncio
import subprocess
import sys
import threading

import pytest
from bridge_harness import bridge_env
from vspin_companion.ears import (
    CPU_MODEL,
    CUDA_MODEL,
    MAX_RECORDING_S,
    LocalEars,
    ModelChoice,
    choose_model,
    load_with_fallback,
)
from vspin_companion.fakes import FakeClock, FakeMicrophone, FakeRecognizer


def run(coroutine):
    return asyncio.run(asyncio.wait_for(coroutine, 10))


def test_cuda_picks_large_v3_turbo_on_the_gpu_and_without_cuda_small_runs_on_the_cpu():
    assert choose_model(True) == ModelChoice("large-v3-turbo", "cuda", "int8_float16")
    assert choose_model(False) == ModelChoice("small", "cpu", "int8")
    assert (CUDA_MODEL, CPU_MODEL) == ("large-v3-turbo", "small")


def test_a_broken_cuda_setup_falls_back_to_small_on_the_cpu_and_says_so():
    loaded: list[ModelChoice] = []
    log: list[str] = []

    def make(choice):
        loaded.append(choice)
        if choice.device == "cuda":
            raise RuntimeError("Library cublas64_12.dll is not found")
        return FakeRecognizer(choice.model)

    recognizer = load_with_fallback(make, True, log.append)
    assert [c.model for c in loaded] == ["large-v3-turbo", "small"] and recognizer.text == "small"
    unusable = next(line for line in log if "CUDA unbrauchbar" in line)
    assert "cublas64_12.dll" in unusable

    loaded.clear()
    load_with_fallback(lambda choice: loaded.append(choice) or FakeRecognizer(), False, log.append)
    assert loaded == [ModelChoice("small", "cpu", "int8")]  # ohne CUDA gar nicht erst CUDA probiert

    def cpu_broken(choice):
        raise OSError("kein Speicher")

    with pytest.raises(OSError):  # auch die CPU scheitert: der Fehler bleibt (Toni wird heiser)
        load_with_fallback(cpu_broken, False, log.append)


def test_recording_ends_with_up_and_the_recognizer_hears_exactly_that_audio():
    async def scenario():
        mic, recognizer, clock = FakeMicrophone(b"frage"), FakeRecognizer("Wie weit noch?"), FakeClock()
        ears = LocalEars(mic, lambda: recognizer, clock)
        await ears.start_listening()
        await asyncio.sleep(0)
        assert mic.recording and clock.pending() == [MAX_RECORDING_S]
        clock.advance(3)
        text = await ears.stop_listening()
        return mic, recognizer, clock, text

    mic, recognizer, clock, text = run(scenario())
    assert text == "Wie weit noch?" and recognizer.heard == [b"frage"]
    assert (mic.started, mic.stopped, mic.recording) == (1, 1, False)
    assert clock.pending() == []  # die 15-s-Grenze ist mit dem Loslassen weg


def test_recording_ends_after_15_seconds_even_if_the_key_is_still_held():
    async def scenario():
        mic, recognizer, clock = FakeMicrophone(b"lange frage"), FakeRecognizer("Langer Satz."), FakeClock()
        log: list[str] = []
        ears = LocalEars(mic, lambda: recognizer, clock, log=log.append)
        await ears.start_listening()
        await asyncio.sleep(0)
        clock.advance(MAX_RECORDING_S - 0.1)
        await asyncio.sleep(0)
        still_recording = mic.recording
        clock.advance(0.1)
        await asyncio.sleep(0.01)
        stopped_by_limit = (not mic.recording, mic.stopped)
        text = await ears.stop_listening()  # Loslassen nach der Grenze: dieselbe Aufnahme, kein zweites Stoppen
        return still_recording, stopped_by_limit, text, mic, recognizer, log

    still, by_limit, text, mic, recognizer, log = run(scenario())
    assert still is True and by_limit == (True, 1)
    assert text == "Langer Satz." and recognizer.heard == [b"lange frage"] and mic.stopped == 1
    assert "nach 15 s beendet" in log[0]


def test_a_new_press_starts_a_fresh_recording_and_silence_is_not_recognized():
    async def scenario():
        mic, recognizer, clock = FakeMicrophone(b""), FakeRecognizer("sollte nie kommen"), FakeClock()
        ears = LocalEars(mic, lambda: recognizer, clock)
        await ears.start_listening()
        assert await ears.stop_listening() == ""  # leere Aufnahme: nichts verstanden, der Erkenner läuft nicht
        mic.audio = b"zweite"
        await ears.start_listening()
        return await ears.stop_listening(), recognizer.heard, mic.started

    text, heard, started = run(scenario())
    assert (text, heard, started) == ("sollte nie kommen", [b"zweite"], 2)


def test_the_model_loads_once_in_the_background_and_a_failed_load_makes_the_next_press_fail_at_once():
    loads: list[str] = []
    gate = threading.Event()

    def load():
        loads.append(threading.current_thread().name)
        gate.wait(5)
        return FakeRecognizer("geladen")

    async def scenario():
        ears = LocalEars(FakeMicrophone(b"x"), load, FakeClock())
        ears.preload()
        ears.preload()  # zweimal: nur ein Ladevorgang
        await ears.start_listening()  # Modell lädt noch – Aufnahme beginnt trotzdem
        gate.set()
        return await ears.stop_listening()

    assert run(scenario()) == "geladen" and loads == ["ears-load"]

    attempts = []

    def flaky():
        attempts.append(1)
        if len(attempts) == 1:
            raise ConnectionError("kein Netz (Hugging-Face-Hub)")
        return FakeRecognizer("zweiter Versuch")

    async def failing():
        mic = FakeMicrophone(b"x")
        ears = LocalEars(mic, flaky, FakeClock())
        ears.preload()
        await asyncio.sleep(0.1)  # der erste Ladeversuch ist gescheitert (Start ohne Netz)
        with pytest.raises(ConnectionError, match="Hugging-Face"):
            await ears.start_listening()  # Toni wird heiser, kein Aufnehmen ...
        assert mic.started == 0
        await ears.start_listening()  # ... und das nächste Drücken hat einen neuen Ladeversuch vor sich
        return await ears.stop_listening()

    assert run(failing()) == "zweiter Versuch" and len(attempts) == 2


def test_importing_the_companion_loads_no_heavy_package():
    """Die schweren Pakete des Extras `companion` werden erst im echten Adapter gebraucht, nie beim Import."""
    code = (
        "import sys, vspin_companion.cli, vspin_companion.ears, vspin_companion.mouth, vspin_companion.openrouter, "
        "vspin_companion.claude_brain, vspin_companion.companion\n"
        "heavy = ('faster_whisper', 'ctranslate2', 'sounddevice', 'av', 'numpy', 'claude_agent_sdk', 'onnxruntime')\n"
        "print([m for m in heavy if m in sys.modules])\n"
    )
    result = subprocess.run([sys.executable, "-c", code], env=bridge_env(), capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "[]"


def test_warm_up_failing_on_cuda_switches_to_small_on_the_cpu_through_the_seam():
    """Fehlende cuBLAS-DLLs zeigen sich erst beim Rechnen: das Aufwärmen wirft, also weicht Toni schon beim Start aus."""
    made: list[FakeRecognizer] = []
    log: list[str] = []

    def make(choice):
        error = RuntimeError("Library cublas64_12.dll is not found") if choice.device == "cuda" else None
        made.append(FakeRecognizer(choice.model, warm_up_error=error))
        return made[-1]

    recognizer = load_with_fallback(make, True, log.append)
    assert [r.text for r in made] == ["large-v3-turbo", "small"]  # beide geladen, nur das zweite taugt
    assert recognizer is made[1] and made[0].warmed_up == 1 and made[1].warmed_up == 1
    assert any("CUDA unbrauchbar" in line and "cublas64_12.dll" in line for line in log)
    assert any("small" in line and "CPU" in line for line in log)


def test_the_log_says_before_loading_that_the_model_comes_from_the_hub():
    log: list[str] = []
    load_with_fallback(lambda choice: FakeRecognizer(choice.model), True, log.append)
    assert "large-v3-turbo" in log[0] and "1,6 GB" in log[0] and "Hugging-Face-Hub" in log[0] and "Cache" in log[0]
    log.clear()
    load_with_fallback(lambda choice: FakeRecognizer(choice.model), False, log.append)
    assert "small" in log[0] and "0,5 GB" in log[0]
