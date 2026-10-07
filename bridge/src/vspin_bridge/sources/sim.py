"""Simulator: erzeugt `TelemetrySample`s direkt (ADR-0003).

Modi: manuell (Kadenz per Tastatur) oder Profil (`profile.py`); Rauschen/Jitter
zuschaltbar (`Noise`). Mit festem Seed ist auch das Rauschen reproduzierbar.
"""

import asyncio
import random
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass, field

from ..clock import bridge_time_ms
from .base import (
    Capability,
    NotSupportedError,
    SourceDisconnectedError,
    TelemetrySample,
)
from .profile import Disconnect, Event, Pause, Profile, Tick, play

CADENCE_MIN = 0.0
CADENCE_MAX = 200.0  # Plausibilitätsgrenze aus ADR-0004

# Virtuelle Steigung (ADR-0007): bergauf sinkt die simulierte Kadenz um
# GRADE_CADENCE_DROP × Steigung (7 % → −14 %), höchstens auf GRADE_CADENCE_FLOOR
# der eingestellten Kadenz. Bergab und bei 0 gilt die eingestellte Kadenz.
GRADE_CADENCE_DROP = 2.0
GRADE_CADENCE_FLOOR = 0.5


@dataclass
class Noise:
    """Rauschen auf der Kadenz (Normalverteilung, `cadence_sd` rpm) und Jitter im
    Sample-Takt (gleichverteilt ±`jitter_s`). Kadenz 0 bleibt 0 – wer nicht tritt,
    erzeugt kein Kurbel-Rauschen. Alle Zufallswerte kommen aus `rng`: gleicher Seed,
    gleiche Folge."""

    rng: random.Random = field(default_factory=random.Random)
    cadence_sd: float = 2.0
    jitter_s: float = 0.05

    def cadence(self, value: float) -> float:
        if value <= 0:
            return value
        return _clamp(round(value + self.rng.gauss(0.0, self.cadence_sd), 1))

    def jitter(self) -> float:
        return self.rng.uniform(-self.jitter_s, self.jitter_s)


class SimulatorSource:
    """Liefert in festem Takt die eingestellte Kadenz (manuell) bzw. die des Profils,
    bergauf (virtuelle Steigung) etwas weniger. Profil-Schritte `pause`/`disconnect`
    erzeugen Datenlücken bzw. Verbindungsabbrüche."""

    name = "sim"

    def __init__(
        self,
        cadence: float = 0.0,
        interval_s: float = 0.25,
        profile: Profile | None = None,
        noise: Noise | None = None,
    ) -> None:
        self.capabilities: set[Capability] = {Capability.CADENCE}
        self._cadence = _clamp(cadence)
        self._grade = 0.0
        self._interval_s = interval_s
        self.profile = profile
        self._noise = noise
        # Ein Ereignisstrom für den ganzen Lauf: nach einem Abbruch geht es dort weiter.
        self._events: Iterator[Event] = _manual() if profile is None else play(profile, interval_s)
        self._offline_until = 0.0  # loop.time(), bis zu der `connect` scheitert

    @property
    def cadence(self) -> float:
        """Die eingestellte Kadenz (Tastatur) – Basis vor der Steigung."""
        return self._cadence

    @property
    def grade(self) -> float:
        return self._grade

    async def set_grade(self, grade: float) -> None:
        """Virtuelle Steigung auswerten (bergauf sinkt die Kadenz). Keine Widerstandssteuerung –
        die Capability RESISTANCE_CONTROL fehlt, daher danach trotzdem `NotSupportedError`."""
        self._grade = float(grade)
        raise NotSupportedError("Simulator hat keine Capability RESISTANCE_CONTROL")

    def _effective_cadence(self, base: float) -> float:
        factor = max(GRADE_CADENCE_FLOOR, 1.0 - GRADE_CADENCE_DROP * max(0.0, self._grade))
        cadence = base * factor
        return cadence if self._noise is None else self._noise.cadence(cadence)

    def adjust_cadence(self, delta: float) -> float:
        self._cadence = _clamp(self._cadence + delta)
        return self._cadence

    async def connect(self) -> None:
        # Nichts aufzubauen – nur nach einem Profil-`disconnect` ist das „Gerät“ eine Weile weg.
        remaining = self._offline_until - asyncio.get_running_loop().time()
        if remaining > 0:
            raise SourceDisconnectedError(f"Simulator laut Profil noch {remaining:.1f} s weg")

    async def samples(self) -> AsyncIterator[TelemetrySample]:
        loop = asyncio.get_running_loop()
        next_tick = loop.time()
        for event in self._events:
            if isinstance(event, Pause):
                next_tick += event.duration_s
                await asyncio.sleep(max(0.0, next_tick - loop.time()))
            elif isinstance(event, Disconnect):
                self._offline_until = loop.time() + event.duration_s
                raise SourceDisconnectedError(f"Abbruch laut Profil, Gerät {event.duration_s:g} s weg")
            else:
                jitter = 0.0 if self._noise is None else self._noise.jitter()
                await asyncio.sleep(max(0.0, next_tick + jitter - loop.time()))
                base = self._cadence if event.cadence is None else event.cadence
                yield TelemetrySample(t_ms=bridge_time_ms(), cadence=self._effective_cadence(base))
                next_tick += self._interval_s
        await asyncio.sleep(max(0.0, next_tick - loop.time()))  # auch der letzte Takt dauert voll


def _manual() -> Iterator[Tick]:
    """Manueller Modus: endlos Samples mit der per Tastatur eingestellten Kadenz."""
    while True:
        yield Tick(None)


def _clamp(value: float) -> float:
    return max(CADENCE_MIN, min(CADENCE_MAX, float(value)))
