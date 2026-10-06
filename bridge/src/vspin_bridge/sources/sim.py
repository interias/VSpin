"""Simulator: erzeugt `TelemetrySample`s direkt, Kadenz manuell regelbar (ADR-0003)."""

import asyncio
from collections.abc import AsyncIterator

from ..clock import bridge_time_ms
from .base import Capability, NotSupportedError, TelemetrySample

CADENCE_MIN = 0.0
CADENCE_MAX = 200.0  # Plausibilitätsgrenze aus ADR-0004

# Virtuelle Steigung (ADR-0007): bergauf sinkt die simulierte Kadenz um
# GRADE_CADENCE_DROP × Steigung (7 % → −14 %), höchstens auf GRADE_CADENCE_FLOOR
# der eingestellten Kadenz. Bergab und bei 0 gilt die eingestellte Kadenz.
GRADE_CADENCE_DROP = 2.0
GRADE_CADENCE_FLOOR = 0.5


class SimulatorSource:
    """Manueller Simulator-Modus: liefert die eingestellte Kadenz in festem Takt,
    bergauf (virtuelle Steigung) etwas weniger."""

    name = "sim"

    def __init__(self, cadence: float = 0.0, interval_s: float = 0.25) -> None:
        self.capabilities: set[Capability] = {Capability.CADENCE}
        self._cadence = _clamp(cadence)
        self._grade = 0.0
        self._interval_s = interval_s

    @property
    def cadence(self) -> float:
        """Die eingestellte Kadenz (Tastatur) – Basis vor der Steigung."""
        return self._cadence

    @property
    def grade(self) -> float:
        return self._grade

    def set_grade(self, grade: float) -> None:
        """Virtuelle Steigung auswerten. Keine Widerstandssteuerung – die Capability
        RESISTANCE_CONTROL fehlt weiterhin, `set_resistance` bleibt `NotSupportedError`."""
        self._grade = float(grade)

    def _effective_cadence(self) -> float:
        factor = max(GRADE_CADENCE_FLOOR, 1.0 - GRADE_CADENCE_DROP * max(0.0, self._grade))
        return self._cadence * factor

    def adjust_cadence(self, delta: float) -> float:
        self._cadence = _clamp(self._cadence + delta)
        return self._cadence

    async def connect(self) -> None:
        # Nichts aufzubauen – der Simulator ist sofort verbunden.
        return None

    async def samples(self) -> AsyncIterator[TelemetrySample]:
        loop = asyncio.get_running_loop()
        next_tick = loop.time()
        while True:
            yield TelemetrySample(t_ms=bridge_time_ms(), cadence=self._effective_cadence())
            next_tick += self._interval_s
            await asyncio.sleep(max(0.0, next_tick - loop.time()))

    async def set_resistance(self, level: float) -> None:
        raise NotSupportedError("Simulator hat keine Capability RESISTANCE_CONTROL")


def _clamp(value: float) -> float:
    return max(CADENCE_MIN, min(CADENCE_MAX, float(value)))
