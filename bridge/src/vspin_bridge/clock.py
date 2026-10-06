"""Monotone Bridge-Zeit (ADR-0004: jedes Sample bekommt einen monotonen Bridge-Zeitstempel)."""

import time

_START_NS = time.monotonic_ns()


def bridge_time_ms() -> int:
    """Millisekunden seit Start der Bridge, monoton (unabhängig von der Wanduhr)."""
    return (time.monotonic_ns() - _START_NS) // 1_000_000
