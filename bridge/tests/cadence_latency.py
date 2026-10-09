"""Erkennungsverzögerung der Kadenzmuster Antritt und Innehalten: geglättet gegen ungeglättet (#45, ADR-0004).

    python tests/cadence_latency.py                     # im Ordner bridge/: Standardmessung als Tabelle
    python tests/cadence_latency.py --profile P.toml --interval 500 --seeds 50
    python tests/cadence_latency.py --replay sessions/AUFNAHME.raw.jsonl   # z. B. ein JC312-Mitschnitt (#1)

Beide Folgen entstehen in `processing.CadenceProcessor` wie in der Bridge: `cadence` (EMA 0,3 s) und `cadence_raw`
(ungeglättet, nach Plausibilität und 2,5-s-Regel – so steht es am Bus, docs/bus-protocol.md).

- **Profil:** Der Fahrer tritt den Verlauf des Profils stetig (Rampen linear). Ein Gerät meldet alle 250 ms (wie
  der Simulator) bzw. alle 1000 ms (FTMS-Räder melden oft 1×/s) die momentane Kadenz – ein Lauf ohne Rauschen,
  dann je Seed mit Rauschen und Jitter wie `--noise` (σ 2 rpm, ±50 ms). Bezug ist die Erkennung am stetigen
  Verlauf selbst; die Verzögerung enthält daher auch den Meldetakt.
- **Replay:** Rohdaten durch die Parser (CSC, FTMS). Ohne bekannten Verlauf ist hier die Erkennung am
  ungeglätteten Wert der Bezug.

Ausgewertet wird wie im Spiel: der zuletzt empfangene Wert gilt bis zum nächsten, die Detektoren laufen auf einem
10-ms-Raster (≈ Bildtakt). Bus und Bildaufbau (wenige ms) fehlen. Vorläufige Detektoren – Schwellen aus der Spec
#27, die endgültigen baut #50:

- **Antritt:** Kadenz − Minimum der letzten 2 s ≥ +25 rpm, Minimum ≥ 30 rpm (Anfahren aus dem Stand zählt nicht).
  Löst einmal aus; wieder scharf, wenn der Anstieg unter +15 rpm fällt (sonst löst Rauschen doppelt aus).
- **Innehalten:** Kadenz < 10 rpm ununterbrochen seit 2 s. Löst einmal je Phase unter der Schwelle aus.

Eine Erkennung gehört zum Bezug, wenn sie höchstens 1 s früher oder 3 s später kommt; sonst gilt der Bezug als
verpasst und die Erkennung als Fehlauslösung.
"""

import argparse
import random
import statistics
import sys
from collections import deque
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path

from vspin_bridge.parsers import Decoder, ParseError
from vspin_bridge.processing import CadenceProcessor
from vspin_bridge.sources.base import Capability, TelemetrySample
from vspin_bridge.sources.profile import Ride, load_profile
from vspin_bridge.sources.replay import load_replay
from vspin_bridge.sources.sim import Noise

BRIDGE_ROOT = Path(__file__).resolve().parents[1]
PROFILES = (BRIDGE_ROOT / "profiles/arcade/antritt.toml", BRIDGE_ROOT / "profiles/arcade/innehalten.toml")
REPLAYS = tuple(Path(__file__).resolve().parent / "fixtures" / name for name in ("csc_step.raw.jsonl", "csc_stop.raw.jsonl"))
INTERVALS_MS = (250, 1000)  # Meldetakt des Geräts: Simulator 250 ms, FTMS-Rad oft 1 s
SEEDS = range(1, 21)

GRID_MS = 10
ANTRITT_RISE_RPM = 25.0
ANTRITT_WINDOW_MS = 2000
ANTRITT_REARM_RPM = 15.0  # erneut scharf erst, wenn der Anstieg im Fenster darunter fällt (Rauschen)
ANTRITT_FROM_RPM = 30.0  # Antritt aus dem Treten: Anfahren nach dem Stillstand zählt nicht
INNEHALTEN_BELOW_RPM = 10.0
INNEHALTEN_HOLD_MS = 2000
MATCH_BEFORE_MS = 1000  # Erkennung zählt zum Bezug, wenn sie höchstens so viel früher …
MATCH_AFTER_MS = 3000  # … oder so viel später kommt; sonst verpasst bzw. Fehlauslösung

ANTRITT = "Antritt"
INNEHALTEN = "Innehalten"
PATTERNS = (ANTRITT, INNEHALTEN)


@dataclass(frozen=True, slots=True)
class Series:
    """Werte am Bus: Zeit der Quelle in ms, geglättet (`cadence`) und ungeglättet (`cadence_raw`)."""

    t_ms: list[int]
    smoothed: list[float | None]
    unsmoothed: list[float | None]


# --- Folgen wie in der Bridge ----------------------------------------------------------------------------------


def process(samples: Iterable[TelemetrySample], reports_cadence: bool = True) -> Series:
    processor = CadenceProcessor(reports_cadence)
    series = Series([], [], [])
    for sample in samples:
        out = processor.process(sample).sample
        series.t_ms.append(sample.t_ms)
        series.smoothed.append(out.cadence)
        series.unsmoothed.append(out.cadence_raw)
    return series


def truth(profile_path: Path) -> tuple[int, Callable[[float], float | None]]:
    """Kadenz des Fahrers laut Profil, stetig in der Zeit (Rampen linear), `None` in Pausen; dazu die Dauer in ms."""
    segments = []  # (start_ms, end_ms, from, to) – from None = keine Daten
    start = 0.0
    for step in load_profile(profile_path).steps:
        end = start + step.duration_s * 1000
        if isinstance(step, Ride):
            to = step.cadence if step.cadence_to is None else step.cadence_to
            segments.append((start, end, step.cadence, to))
        else:
            segments.append((start, end, None, None))
        start = end

    def at(t_ms: float) -> float | None:
        for begin, end, value_from, value_to in segments:
            if begin <= t_ms < end:
                return None if value_from is None else value_from + (value_to - value_from) * (t_ms - begin) / (end - begin)
        return segments[-1][3]

    return round(start), at


def sample_device(profile_path: Path, interval_ms: int, seed: int | None) -> Iterator[TelemetrySample]:
    """Ein Gerät, das alle `interval_ms` die momentane Kadenz meldet (Simulator: 250 ms; FTMS typisch 250 ms–1 s).
    Mit `seed` Rauschen (σ 2 rpm) und Jitter (±50 ms) wie `--noise` des Simulators."""
    duration_ms, at = truth(profile_path)
    noise = None if seed is None else Noise(random.Random(seed))
    for tick in range(0, duration_ms, interval_ms):
        t = tick + (0.0 if noise is None else noise.jitter() * 1000)
        value = at(max(0.0, t))
        if value is None:
            continue
        cadence = round(value, 1) if noise is None else noise.cadence(value)
        yield TelemetrySample(t_ms=round(t), cadence=cadence)


def replay(path: Path) -> Series:
    source = load_replay(path)
    decoder = Decoder()
    samples = []
    for raw in source.notifications:
        try:
            sample = decoder.decode(raw)
        except ParseError:
            continue
        if sample is not None:
            samples.append(sample)
    return process(samples, Capability.CADENCE in source.capabilities)


# --- Detektoren (vorläufig, siehe oben) ------------------------------------------------------------------------


def hold_on_grid(t_ms: list[int], values: list[float | None]) -> tuple[list[int], list[float | None]]:
    """Letzter empfangener Wert gilt bis zum nächsten – ausgewertet alle GRID_MS (wie das Spiel je Bild)."""
    grid_t, grid_v = [], []
    i, current = 0, None
    for t in range(t_ms[0], t_ms[-1] + 1, GRID_MS):
        while i < len(t_ms) and t_ms[i] <= t:
            current = values[i] if values[i] is not None else current
            i += 1
        grid_t.append(t)
        grid_v.append(current)
    return grid_t, grid_v


def detect_antritt(t_ms: list[int], values: list[float | None]) -> list[int]:
    hits, window, armed = [], deque(), True  # window: (t, v) mit steigenden v – vorn das Minimum
    for t, v in zip(*hold_on_grid(t_ms, values)):
        if v is None:
            continue
        while window and window[-1][1] >= v:
            window.pop()
        window.append((t, v))
        while window[0][0] < t - ANTRITT_WINDOW_MS:
            window.popleft()
        base = window[0][1]
        rise = v - base
        if armed and rise >= ANTRITT_RISE_RPM and base >= ANTRITT_FROM_RPM:
            hits.append(t)
            armed = False
        elif rise < ANTRITT_REARM_RPM:
            armed = True
    return hits


def detect_innehalten(t_ms: list[int], values: list[float | None]) -> list[int]:
    hits, since, fired = [], None, False
    for t, v in zip(*hold_on_grid(t_ms, values)):
        if v is None or v >= INNEHALTEN_BELOW_RPM:
            since, fired = None, False
            continue
        since = t if since is None else since
        if not fired and t - since >= INNEHALTEN_HOLD_MS:
            hits.append(t)
            fired = True
    return hits


DETECTORS = {ANTRITT: detect_antritt, INNEHALTEN: detect_innehalten}


@dataclass(frozen=True, slots=True)
class Match:
    delays_ms: list[int | None]  # je Bezugs-Erkennung: Verzögerung oder None (verpasst)
    false_hits: int  # Erkennungen ohne Bezug


def match(reference: list[int], hits: list[int]) -> Match:
    left, delays = list(hits), []
    for ref in reference:
        found = next((h for h in left if ref - MATCH_BEFORE_MS <= h <= ref + MATCH_AFTER_MS), None)
        if found is None:
            delays.append(None)
        else:
            left.remove(found)
            delays.append(found - ref)
    return Match(delays, len(left))


# --- Messung ---------------------------------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Row:
    source: str
    pattern: str
    episode: int  # 1, 2, … in der Reihenfolge des Bezugs
    reference_ms: int  # Zeit der Bezugs-Erkennung (Quelle)
    unsmoothed: list[int | None]  # Verzögerung je Lauf: ohne Rauschen zuerst, dann je Seed
    smoothed: list[int | None]
    false_unsmoothed: int = 0  # Fehlauslösungen über alle Läufe (beim ersten Episoden-Eintrag eines Musters)
    false_smoothed: int = 0


def measure_profile(path: Path, interval_ms: int, seeds: Iterable[int | None]) -> list[Row]:
    duration_ms, at = truth(path)
    grid = list(range(0, duration_ms, GRID_MS))
    reference_values = [at(t) for t in grid]
    runs = [process(sample_device(path, interval_ms, seed)) for seed in seeds]
    rows = []
    for pattern, detect in DETECTORS.items():
        ref = detect(grid, reference_values)
        per_run = [
            (match(ref, detect(run.t_ms, run.unsmoothed)), match(ref, detect(run.t_ms, run.smoothed))) for run in runs
        ]
        for k, ref_ms in enumerate(ref):
            rows.append(
                Row(
                    f"{path.stem} ({interval_ms} ms)",
                    pattern,
                    k + 1,
                    ref_ms,
                    [u.delays_ms[k] for u, _ in per_run],
                    [s.delays_ms[k] for _, s in per_run],
                    sum(u.false_hits for u, _ in per_run) if k == 0 else 0,
                    sum(s.false_hits for _, s in per_run) if k == 0 else 0,
                )
            )
    return rows


def measure_replay(path: Path) -> list[Row]:
    series = replay(path)
    rows = []
    for pattern, detect in DETECTORS.items():
        ref = detect(series.t_ms, series.unsmoothed)
        smoothed = match(ref, detect(series.t_ms, series.smoothed))
        for k, ref_ms in enumerate(ref):
            rows.append(
                Row(path.name, pattern, k + 1, ref_ms, [0], [smoothed.delays_ms[k]], 0, smoothed.false_hits if k == 0 else 0)
            )
    return rows


def _spread(values: list[int | None]) -> str:
    found = [v for v in values if v is not None]
    missed = len(values) - len(found)
    text = "–" if not found else f"{statistics.median(found):.0f} / {max(found)}"
    return text + (f", verpasst {missed}/{len(values)}" if missed else "")


def _one(value: int | None) -> str:
    return "verpasst" if value is None else str(value)


def table(rows: list[Row]) -> str:
    """Je Lauf ohne Rauschen der Wert, mit Rauschen „Median / Max“ über die Seeds (ms nach dem Bezug)."""
    lines = [
        "| Quelle (Meldetakt) | Muster | # | ungeglättet | geglättet | EMA kostet | ungegl. Rauschen | gegl. Rauschen "
        "| EMA kostet Rauschen | Fehlauslösungen u./g. |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        extra = [s - u if u is not None and s is not None else None for u, s in zip(row.unsmoothed, row.smoothed)]
        noisy = len(row.unsmoothed) > 1
        lines.append(
            f"| {row.source} | {row.pattern} | {row.episode} | {_one(row.unsmoothed[0])} | {_one(row.smoothed[0])} "
            f"| {_one(extra[0])} | {_spread(row.unsmoothed[1:]) if noisy else '–'} "
            f"| {_spread(row.smoothed[1:]) if noisy else '–'} "
            f"| {_spread([e for e in extra[1:] if e is not None]) if noisy else '–'} "
            f"| {row.false_unsmoothed}/{row.false_smoothed} |"
        )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Erkennungsverzögerung Antritt/Innehalten, geglättet gegen ungeglättet")
    parser.add_argument("--profile", type=Path, action="append", default=[], help="Simulator-Profil (TOML)")
    parser.add_argument("--replay", type=Path, action="append", default=[], help="Rohdaten (.raw.jsonl)")
    parser.add_argument(
        "--interval", type=int, action="append", default=[], help="Meldetakt des Geräts in ms (Standard 250 und 1000)"
    )
    parser.add_argument("--seeds", type=int, default=len(SEEDS), help="Läufe mit Rauschen je Profil (Seeds 1…N)")
    args = parser.parse_args(argv)
    profiles, replays = args.profile, args.replay
    if not profiles and not replays:
        profiles, replays = list(PROFILES), list(REPLAYS)
    seeds = [None, *range(1, args.seeds + 1)]
    intervals = args.interval or list(INTERVALS_MS)
    rows = [row for interval in intervals for path in profiles for row in measure_profile(path, interval, seeds)]
    rows += [row for path in replays for row in measure_replay(path)]
    print(f"Profile: 1 Lauf ohne Rauschen + {args.seeds} Seeds mit Rauschen („Median / Max“); ms nach dem Bezug.")
    print(table(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
