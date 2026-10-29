"""Kommandozeile: `vspin-companion` – Toni als Bus-Client (ADR-0002, Nachtrag #76).

Denken (`ClaudeBrain`, #78), Hören (`LocalEars`: Mikrofon + faster-whisper, lokal) und Sprechen (`OpenRouterMouth`:
Stimme über OpenRouter, Wiedergabe über das Windows-Standardgerät, #79) sind echt. Fehlt ein Paket des Extras
`companion` oder die Hardware (PortAudio), steckt an dieser Stelle ein Platzhalter, der beim Gebrauch scheitert:
Toni verbindet sich, meldet `idle` und wird beim ersten Drücken der Sprechtaste heiser – der Prozess läuft weiter.
Ebenso ohne `claude-agent-sdk`, ohne Anmeldung oder ohne `OPENROUTER_API_KEY`.

Beendet wird er wie die Bridge: Strg+C/SIGTERM, `--stop-file` oder – wenn der Launcher des Spiels
`VSPIN_COMPANION_PARENT_PID` setzt – sobald das Spiel nicht mehr läuft.
"""

import argparse
import asyncio
import contextlib
import signal
import sys
from collections.abc import Callable, Sequence
from pathlib import Path

from .bus import HOST, PORT
from .claude_brain import ClaudeBrain
from .clock import SystemClock
from .companion import Companion
from .config import DATA_DIR_ENV, CompanionConfig, ConfigError, default_data_dir, load_config
from .env_file import ENV_FILE, load_secret
from .openrouter import OpenRouterClient, OpenRouterError, UrllibHttp
from .parent import parent_pid, watch_parent
from .ports import Clock, Ears, Mouth, SpeechUsage

STOP_FILE_POLL_S = 0.1
OPENROUTER_KEY_ENV = "OPENROUTER_API_KEY"


class AdapterMissing(Exception):
    """Für diesen Port gibt es keinen echten Adapter (Paket oder Hardware fehlt)."""


class Unavailable:
    """Platzhalter für Ears bzw. Mouth, deren Paket fehlt: scheitert beim Gebrauch mit dem Grund (Toni wird heiser)."""

    def __init__(self, reason: str) -> None:
        self._reason = reason

    async def start_listening(self) -> None:
        raise AdapterMissing(self._reason)

    async def stop_listening(self) -> str:
        raise AdapterMissing(self._reason)

    async def speak(self, sentence: str, on_start: Callable[[], None] | None = None) -> None:
        raise AdapterMissing(self._reason)

    async def stop(self) -> None:
        pass

    def set_volume(self, volume: float) -> None:
        pass

    def take_usage(self) -> SpeechUsage:
        return SpeechUsage()

    async def cost_of(self, generation_ids: Sequence[str], patient: bool = True) -> dict[str, float]:
        return {}


def build_ears(clock: Clock, log: Callable[[str], None]) -> Ears:
    try:
        from .ears import create_ears

        ears = create_ears(clock, log)
    except (ImportError, OSError) as exc:  # sounddevice oder PortAudio fehlt
        return Unavailable(f"Ears: {exc} (Extra `companion` installieren)")
    ears.preload()  # Modell beim Start laden und halten
    return ears


def build_mouth(config: CompanionConfig, data_dir: Path, log: Callable[[str], None]) -> Mouth:
    def api_key() -> str:
        key = load_secret(OPENROUTER_KEY_ENV, data_dir)
        if not key:
            raise OpenRouterError(f"{OPENROUTER_KEY_ENV} fehlt (Umgebung oder {data_dir / ENV_FILE})")
        return key

    try:
        from .mouth import create_mouth

        client = OpenRouterClient(UrllibHttp(), api_key, config.voice_model, config.voice)
        return create_mouth(client, log)
    except (ImportError, OSError) as exc:  # av oder sounddevice fehlt
        return Unavailable(f"Mouth: {exc} (Extra `companion` installieren)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vspin-companion",
        description="Toni, der sprechende Begleiter – Client am Bus (ws://127.0.0.1:8765)",
    )
    parser.add_argument("--host", default=HOST, metavar="ADRESSE", help="Adresse des Busses (Standard: 127.0.0.1)")
    parser.add_argument(
        "--port",
        type=int,
        default=PORT,
        metavar="PORT",
        help=f"Port des Busses (Standard: {PORT}); ein anderer nur für parallele Testläufe (VSPIN_PORT_BASE)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=None,
        metavar="DIR",
        help=f"Ablage von companion.json, soul.md, memory.md und .env "
        f"(Standard: {DATA_DIR_ENV}, sonst %%APPDATA%%\\VSpin\\companion)",
    )
    parser.add_argument(
        "--stop-file",
        type=Path,
        default=None,
        metavar="DATEI",
        help="sauber beenden, sobald diese Datei existiert (Windows kennt kein SIGTERM)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    data_dir = args.data_dir if args.data_dir is not None else default_data_dir()
    try:
        config = load_config(data_dir)
    except ConfigError as exc:
        _log(f"vspin-companion: Konfiguration ungültig: {exc}")
        return 1
    _log(f"vspin-companion: Ablage {data_dir} (Denken: {config.brain})")
    clock = SystemClock()
    brain = ClaudeBrain(config.brain, data_dir)
    ears = build_ears(clock, _log)
    mouth = build_mouth(config, data_dir, _log)
    url = f"ws://{args.host}:{args.port}"
    companion = Companion(brain, ears, mouth, clock, url, _log, data_dir=data_dir, config=config)
    try:
        return asyncio.run(_run(companion, args.stop_file, parent_pid()))
    except KeyboardInterrupt:  # Strg+C vor dem Anmelden der Signal-Handler
        return 0


async def _run(companion: Companion, stop_file: Path | None, parent: int | None = None) -> int:
    stop = asyncio.Event()
    _stop_on_signals(stop)
    watchers: list[asyncio.Task] = []
    if stop_file is not None:
        stop_file.unlink(missing_ok=True)  # Rest eines früheren Laufs beendet nicht gleich wieder
        watchers.append(asyncio.create_task(_watch_stop_file(stop_file, stop)))
    if parent is not None:
        watchers.append(asyncio.create_task(watch_parent(parent, stop, _log)))
    try:
        await companion.run(stop)
    finally:
        for watcher in watchers:
            watcher.cancel()
        for watcher in watchers:
            with contextlib.suppress(asyncio.CancelledError):
                await watcher
        if stop_file is not None:
            with contextlib.suppress(OSError):
                stop_file.unlink(missing_ok=True)
    _log("vspin-companion: beendet")
    return 0


def _stop_on_signals(stop: asyncio.Event) -> None:
    """Wie die Bridge: Strg+C/SIGTERM bzw. unter Windows Strg+C/Strg+Untbr setzen `stop`."""
    loop = asyncio.get_running_loop()
    if sys.platform == "win32":
        for sig in (signal.SIGINT, signal.SIGBREAK):
            signal.signal(sig, lambda *_: loop.call_soon_threadsafe(stop.set))
        return
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)


async def _watch_stop_file(path: Path, stop: asyncio.Event) -> None:
    while not path.exists():
        await asyncio.sleep(STOP_FILE_POLL_S)
    stop.set()


def _log(text: str) -> None:
    if sys.stdout is not None:  # unter pythonw gibt es kein Terminal
        print(text, flush=True)


if __name__ == "__main__":
    sys.exit(main())
