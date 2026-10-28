"""Kommandozeile: `vspin-companion` – Toni als Bus-Client (ADR-0002, Nachtrag #76).

Das Denken ist echt (`ClaudeBrain`, #78, nach `brain` in `companion.json`); bis #79 die echten Ears und Mouth
bringt, steckt dort ein Platzhalter, der sofort scheitert: Toni verbindet sich, meldet `idle` und wird beim ersten
Drücken der Sprechtaste heiser – der Prozess läuft weiter. Ebenso ohne `claude-agent-sdk` oder ohne Anmeldung: Toni
wird zu Fahrtbeginn heiser.
"""

import argparse
import asyncio
import contextlib
import signal
import sys
from pathlib import Path

from .bus import HOST, PORT
from .claude_brain import ClaudeBrain
from .clock import SystemClock
from .companion import Companion
from .config import DATA_DIR_ENV, ConfigError, default_data_dir, load_config

STOP_FILE_POLL_S = 0.1


class AdapterMissing(Exception):
    """Für diesen Port gibt es noch keinen echten Adapter."""


class MissingAdapters:
    """Platzhalter für Ears und Mouth bis #79."""

    async def start_listening(self) -> None:
        raise AdapterMissing("Ears: kein Adapter (kommt mit #79)")

    async def stop_listening(self) -> str:
        raise AdapterMissing("Ears: kein Adapter (kommt mit #79)")

    async def speak(self, sentence: str) -> None:
        raise AdapterMissing("Mouth: kein Adapter (kommt mit #79)")

    async def stop(self) -> None:
        pass


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
    adapters = MissingAdapters()
    brain = ClaudeBrain(config.brain, data_dir)
    url = f"ws://{args.host}:{args.port}"
    companion = Companion(brain, adapters, adapters, SystemClock(), url, _log, data_dir=data_dir, config=config)
    try:
        return asyncio.run(_run(companion, args.stop_file))
    except KeyboardInterrupt:  # Strg+C vor dem Anmelden der Signal-Handler
        return 0


async def _run(companion: Companion, stop_file: Path | None) -> int:
    stop = asyncio.Event()
    _stop_on_signals(stop)
    watcher = None
    if stop_file is not None:
        stop_file.unlink(missing_ok=True)  # Rest eines früheren Laufs beendet nicht gleich wieder
        watcher = asyncio.create_task(_watch_stop_file(stop_file, stop))
    try:
        await companion.run(stop)
    finally:
        if watcher is not None:
            watcher.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await watcher
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
