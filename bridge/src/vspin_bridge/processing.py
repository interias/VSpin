"""Datenaufbereitung (ADR-0004) – gilt für alle Quellen gleich (Simulator, Replay, BLE).

Pro Sample der Quelle, auf deren Zeitachse (`t_ms` der Quelle; beim Replay die Zeit der
Aufnahme, daher unabhängig von `--speed`):

- **Plausibilität:** ein neuer Kadenzwert außerhalb 0–200 rpm wird verworfen (nicht
  begrenzt) – als wäre er nicht gekommen.
- **Glättung:** EMA mit Zeitkonstante 0,3 s, zeitbasiert:
  `ema += (1 − exp(−Δt / 0,3 s)) · (wert − ema)`, Δt = Abstand zum vorigen Wert.
  Der erste Wert (und der erste nach ≥ 2,5 s ohne Wert) startet die Glättung neu.
- **Kadenz 0:** kommt 2,5 s lang kein neuer Kadenzwert (CSC: kein neues Kurbel-Event;
  FTMS: Notifications ohne Kadenzfeld), obwohl Samples kommen, ist die Kadenz 0. Kommen gar keine Samples, greift stattdessen
  `stale` (ADR-0004) – die Bridge erfindet keine Samples.
  Meldet die Quelle ausdrücklich 0, ist die Kadenz 0, sobald der geglättete Wert unter
  1 rpm fällt (statt ihm asymptotisch zu folgen; von 80 rpm nach ~1,3 s statt ~2,2 s).

Auf den Bus geht der geglättete Wert (auf 0,1 rpm gerundet), die CSV bekommt zusätzlich
den Rohwert des Samples (`cadence_raw`, auch verworfene Ausreißer; leer ohne neuen Wert).
Geschwindigkeit, Leistung und Puls gehen unverändert durch.
"""

import math
from dataclasses import dataclass, replace

from .sources.base import TelemetrySample

CADENCE_MIN = 0.0
CADENCE_MAX = 200.0  # harte Plausibilitätsgrenze (ADR-0004)
SMOOTHING_TAU_MS = 300.0  # Zeitkonstante des EMA (0,3 s)
ZERO_AFTER_MS = 2500  # so lange kein neuer Kadenzwert → Kadenz 0
ZERO_BELOW_RPM = 1.0  # gemeldete Kadenz 0 und geglättet darunter → Kadenz 0
ROUND_DIGITS = 1


@dataclass(frozen=True, slots=True)
class Processed:
    sample: TelemetrySample  # Kadenz geglättet – so geht es auf den Bus
    cadence_raw: float | None  # Rohwert aus der Quelle (CSV-Spalte `cadence_raw`)
    discarded: bool = False  # Rohwert lag außerhalb 0–200 rpm und wurde verworfen


class CadenceProcessor:
    """`reports_cadence`: die Quelle liefert grundsätzlich Kadenz (Capability CADENCE).
    Nur dann läuft die 2,5-s-Regel ab dem ersten Sample – sonst bleibt die Kadenz `null`."""

    def __init__(self, reports_cadence: bool) -> None:
        self._reports_cadence = reports_cadence
        self._ema: float | None = None
        self._ema_t: int | None = None  # Zeit des letzten Werts im EMA
        self._last_value_t: int | None = None  # Zeit des letzten neuen Werts (oder 1. Sample)

    def process(self, sample: TelemetrySample) -> Processed:
        t, raw = sample.t_ms, sample.cadence
        discarded = raw is not None and not CADENCE_MIN <= raw <= CADENCE_MAX
        if self._last_value_t is None and self._reports_cadence:
            self._last_value_t = t  # ab jetzt zählt die 2,5-s-Regel
        if raw is not None and not discarded:
            self._add(t, raw)
        elif self._last_value_t is not None and t - self._last_value_t >= ZERO_AFTER_MS:
            self._ema, self._ema_t = 0.0, t
        cadence = None if self._ema is None else round(self._ema, ROUND_DIGITS) + 0.0
        return Processed(replace(sample, cadence=cadence), raw, discarded)

    def _add(self, t: int, value: float) -> None:
        restart = (
            self._ema is None
            or self._last_value_t is None
            or t - self._last_value_t >= ZERO_AFTER_MS
        )
        if restart:
            self._ema = float(value)
        else:
            alpha = 1.0 - math.exp(-max(0, t - self._ema_t) / SMOOTHING_TAU_MS)
            self._ema += alpha * (value - self._ema)
            if value == 0 and self._ema < ZERO_BELOW_RPM:
                self._ema = 0.0
        self._ema_t = self._last_value_t = t
