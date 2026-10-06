"""Kommandozeile: `vspin-bridge --source sim` (ADR-0003: --source ble|sim|replay)."""

import argparse
import asyncio
import random
import signal
import sys
from collections.abc import Callable
from pathlib import Path

from .app import DEFAULT_SESSIONS_DIR, Bridge, SessionStartError
from .bus import BusStartError
from .console import Console
from .sources.base import DeviceSource
from .sources.profile import ProfileError, load_profile
from .sources.sim import Noise, SimulatorSource


def _simulator(args: argparse.Namespace) -> SimulatorSource:
    profile = None if args.profile is None else load_profile(args.profile)
    noise = Noise(random.Random(args.seed)) if args.noise else None
    cadence = 0.0 if args.sim_cadence is None else args.sim_cadence
    return SimulatorSource(cadence=cadence, profile=profile, noise=noise)


# Quellenwahl: ble und replay docken in Folgetickets hier an.
SOURCES: dict[str, Callable[[argparse.Namespace], DeviceSource]] = {
    "sim": _simulator,
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
        default=None,
        metavar="RPM",
        help="Start-Kadenz des Simulators in rpm (Standard: 0)",
    )
    parser.add_argument(
        "--profile",
        type=Path,
        default=None,
        metavar="DATEI",
        help="Simulator spielt dieses Profil (TOML) ab statt manueller Kadenz, z. B. profiles/abbruch.toml",
    )
    parser.add_argument(
        "--noise",
        action="store_true",
        help="Simulator: Rauschen auf der Kadenz und Jitter im Sample-Takt",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        metavar="N",
        help="Seed für --noise: gleicher Seed, gleiche Folge (Standard: zufällig)",
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
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.source != "sim" and (args.profile is not None or args.noise or args.sim_cadence is not None):
        parser.error("--profile, --noise und --sim-cadence gibt es nur mit --source sim")
    if args.profile is not None and args.sim_cadence is not None:
        parser.error("--profile und --sim-cadence schließen sich aus (das Profil gibt die Kadenz vor)")
    if args.seed is not None and not args.noise:
        parser.error("--seed wirkt nur zusammen mit --noise")
    try:
        source = SOURCES[args.source](args)
    except ProfileError as exc:
        parser.error(str(exc))
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
    except SessionStartError as exc:
        console.info(f"vspin-bridge: Session-Datei konnte nicht angelegt werden: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
