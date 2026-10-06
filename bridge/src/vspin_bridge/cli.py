"""Kommandozeile: `vspin-bridge --source sim` (ADR-0003: --source ble|sim|replay)."""

import argparse
import asyncio
import signal
import sys
from collections.abc import Callable
from pathlib import Path

from .app import DEFAULT_SESSIONS_DIR, Bridge
from .bus import BusStartError
from .console import Console
from .sources.base import DeviceSource
from .sources.sim import SimulatorSource

# Quellenwahl: ble und replay docken in Folgetickets hier an.
SOURCES: dict[str, Callable[[argparse.Namespace], DeviceSource]] = {
    "sim": lambda args: SimulatorSource(cadence=args.sim_cadence),
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vspin-bridge",
        description="Telemetrie-Bridge: DeviceSource → Bus (ws://127.0.0.1:8765)",
    )
    parser.add_argument("--source", required=True, choices=sorted(SOURCES), help="Datenquelle")
    parser.add_argument(
        "--sim-cadence",
        type=float,
        default=0.0,
        metavar="RPM",
        help="Start-Kadenz des Simulators in rpm (Standard: 0)",
    )
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=DEFAULT_SESSIONS_DIR,
        metavar="DIR",
        help="Ablage der Session-CSV (Standard: ./sessions im Arbeitsverzeichnis)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    source = SOURCES[args.source](args)
    console = Console()
    try:
        return asyncio.run(_run(source, console, args.sessions_dir))
    except KeyboardInterrupt:  # Windows: kein add_signal_handler, Strg+C kommt so an
        console.close()
        return 0


async def _run(source: DeviceSource, console: Console, sessions_dir: Path) -> int:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except (NotImplementedError, RuntimeError):
            pass  # Windows
    try:
        await Bridge(source, console, sessions_dir).run(stop)
    except BusStartError as exc:
        console.info(f"vspin-bridge: Bus konnte nicht starten: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
