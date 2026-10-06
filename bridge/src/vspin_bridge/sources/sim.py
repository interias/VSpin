"""Simulator: erzeugt `TelemetrySample`s direkt, Kadenz manuell regelbar (ADR-0003)."""

import asyncio
from collections.abc import AsyncIterator

from ..clock import bridge_time_ms
from .base import Capability, NotSupportedError, TelemetrySample

CADENCE_MIN = 0.0
CADENCE_MAX = 200.0  # Plausibilitätsgrenze aus ADR-0004


class SimulatorSource:
    """Manueller Simulator-Modus: liefert die eingestellte Kadenz in festem Takt."""

    name = "sim"

    def __init__(self, cadence: float = 0.0, interval_s: float = 0.25) -> None:
        self.capabilities: set[Capability] = {Capability.CADENCE}
        self._cadence = _clamp(cadence)
        self._interval_s = interval_s

    @property
    def cadence(self) -> float:
        return self._cadence

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
            yield TelemetrySample(t_ms=bridge_time_ms(), cadence=self._cadence)
            next_tick += self._interval_s
            await asyncio.sleep(max(0.0, next_tick - loop.time()))

    async def set_resistance(self, level: float) -> None:
        raise NotSupportedError("Simulator hat keine Capability RESISTANCE_CONTROL")


def _clamp(value: float) -> float:
    return max(CADENCE_MIN, min(CADENCE_MAX, float(value)))
