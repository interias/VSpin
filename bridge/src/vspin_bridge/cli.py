"""Kommandozeile: `vspin-bridge --source sim` bzw. `--source replay DATEI` (ADR-0003)."""

import argparse
import asyncio
import contextlib
import random
import signal
import sys
from collections.abc import Callable
from pathlib import Path

from .app import DEFAULT_SESSIONS_DIR, Bridge, SessionStartError
from .bus import HOST, BusStartError
from .console import Console
from .sources.base import DeviceSource
from .sources.profile import ProfileError, load_profile
from .sources.replay import ReplayError, load_replay
from .sources.sim import Noise, SimulatorSource


def _simulator(args: argparse.Namespace) -> SimulatorSource:
    profile = None if args.profile is None else load_profile(args.profile)
    noise = Noise(random.Random(args.seed)) if args.noise else None
    cadence = 0.0 if args.sim_cadence is None else args.sim_cadence
    return SimulatorSource(cadence=cadence, profile=profile, noise=noise)


def _replay(args: argparse.Namespace) -> DeviceSource:
    return load_replay(args.file, 1.0 if args.speed is None else args.speed)


# Quellenwahl: ble dockt in einem Folgeticket hier an.
SOURCES: dict[str, Callable[[argparse.Namespace], DeviceSource]] = {
    "replay": _replay,
    "sim": _simulator,
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vspin-bridge",
        description="Telemetrie-Bridge: DeviceSource → Bus (ws://127.0.0.1:8765)",
    )
    parser.add_argument("--source", required=True, choices=sorted(SOURCES), help="Datenquelle")
    parser.add_argument(
        "file",
        nargs="?",
        type=Path,
        default=None,
        metavar="DATEI",
        help="nur --source replay: aufgezeichnete Roh-Notifications (.raw.jsonl)",
    )
    parser.add_argument(
        "--speed",
        type=float,
        default=None,
        metavar="FAKTOR",
        help="Replay: Abspielgeschwindigkeit, 1 = Echtzeit (Standard), 10 = zehnmal so schnell",
    )
    parser.add_argument(
        "--wait-client",
        action="store_true",
        help="Replay: erst abspielen, wenn sich der erste Client mit dem Bus verbunden hat",
    )
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
        help="Ablage der Session-Dateien (Standard: ./sessions im Arbeitsverzeichnis)",
    )
    parser.add_argument(
        "--host",
        default=HOST,
        metavar="ADRESSE",
        help="Adresse, auf der der Bus lauscht (Standard: 127.0.0.1); 0.0.0.0 nur im Container, "
        "dessen Port nur auf 127.0.0.1 des Hosts veröffentlicht ist (docker-compose.yml)",
    )
    parser.add_argument(
        "--stop-file",
        type=Path,
        default=None,
        metavar="DATEI",
        help="sauber beenden, sobald diese Datei existiert (Start aus dem Spiel; Windows kennt kein SIGTERM)",
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
    if args.source == "replay" and args.file is None:
        parser.error("--source replay braucht eine Datei: vspin-bridge --source replay DATEI.raw.jsonl")
    if args.source != "replay" and (args.file is not None or args.speed is not None or args.wait_client):
        parser.error("DATEI, --speed und --wait-client gibt es nur mit --source replay")
    try:
        source = SOURCES[args.source](args)
    except (ProfileError, ReplayError) as exc:
        parser.error(str(exc))
    console = Console()
    try:
        return asyncio.run(
            _run(source, console, args.sessions_dir, args.wait_client, args.host, args.stop_file)
        )
    except KeyboardInterrupt:  # Strg+C vor dem Anmelden der Signal-Handler
        console.close()
        return 0


STOP_FILE_POLL_S = 0.1


async def _run(
    source: DeviceSource,
    console: Console,
    sessions_dir: Path,
    wait_for_client: bool,
    host: str,
    stop_file: Path | None = None,
) -> int:
    stop = asyncio.Event()
    _stop_on_signals(stop)
    watcher = None
    if stop_file is not None:
        stop_file.unlink(missing_ok=True)  # Rest eines früheren Laufs beendet nicht gleich wieder
        watcher = asyncio.create_task(_watch_stop_file(stop_file, stop))
    try:
        await Bridge(source, console, sessions_dir, wait_for_client, host).run(stop)
    except BusStartError as exc:
        console.info(f"vspin-bridge: Bus konnte nicht starten: {exc}")
        return 1
    except SessionStartError as exc:
        console.info(f"vspin-bridge: Session-Datei konnte nicht angelegt werden: {exc}")
        return 1
    finally:
        if watcher is not None:
            watcher.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await watcher
            with contextlib.suppress(OSError):
                stop_file.unlink(missing_ok=True)
    return 0


def _stop_on_signals(stop: asyncio.Event) -> None:
    """Strg+C/SIGTERM (Linux/macOS) bzw. Strg+C/Strg+Untbr (Windows) beenden sauber: `stop` wird gesetzt,
    die Bridge schließt Bus und Session ab. Unter Windows gibt es kein `add_signal_handler`; der Handler
    läuft dort im Hauptthread und weckt den Event-Loop. TerminateProcess (kill) lässt sich nicht abfangen."""
    loop = asyncio.get_running_loop()
    if sys.platform == "win32":
        for sig in (signal.SIGINT, signal.SIGBREAK):
            signal.signal(sig, lambda *_: loop.call_soon_threadsafe(stop.set))
        return
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)


async def _watch_stop_file(path: Path, stop: asyncio.Event) -> None:
    """Stoppweg ohne Signal (Spiel unter Windows): die Bridge endet sauber, sobald `path` existiert."""
    while not path.exists():
        await asyncio.sleep(STOP_FILE_POLL_S)
    stop.set()


if __name__ == "__main__":
    sys.exit(main())
