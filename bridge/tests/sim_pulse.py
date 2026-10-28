"""Erwarteter Puls des Simulators bei konstanter Kadenz, unabhängig von `sim_heart_rate.py` nach der
dokumentierten Formel nachgerechnet (bridge/README.md): Ziel = 60 + 0,9 · Kadenz, Puls läuft ihm je Sample
mit 1 − e^(−0,25 s / 30 s) nach; gemeldet wird der gerundete Wert."""

import math


def simulator_pulse(cadence: float, count: int, interval_s: float = 0.25) -> list[int]:
    """Die ersten `count` Pulswerte eines Simulators, der ab dem ersten Sample konstant `cadence` fährt."""
    alpha = 1 - math.exp(-interval_s / 30)
    target = 60 + 0.9 * cadence
    bpm, out = 60.0, []
    for _ in range(count):
        bpm += (target - bpm) * alpha
        out.append(round(bpm))
    return out


def is_window(values: list, expected: list) -> bool:
    """Ist `values` ein zusammenhängender Ausschnitt von `expected`? (Ein Client verpasst die ersten Samples.)"""
    n = len(values)
    return any(expected[i : i + n] == values for i in range(len(expected) - n + 1))
