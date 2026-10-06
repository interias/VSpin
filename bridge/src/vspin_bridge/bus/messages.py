"""Bus-Nachrichten nach docs/bus-protocol.md (Version 0). Jede hat `v` und `type`."""

import json
from collections.abc import Iterable

from ..sources.base import Capability, TelemetrySample

PROTOCOL_VERSION = 0


def telemetry_message(sample: TelemetrySample) -> str:
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "telemetry",
            "t_ms": sample.t_ms,
            "cadence": sample.cadence,
            "speed_kmh": sample.speed_kmh,
            "power_w": sample.power_w,
            "power_estimated": sample.power_estimated,
            "heart_rate": sample.heart_rate,
        }
    )


def status_message(t_ms: int, state: str, source: str, capabilities: Iterable[Capability]) -> str:
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "status",
            "t_ms": t_ms,
            "state": state,
            "source": source,
            "capabilities": sorted(str(c) for c in capabilities),
        }
    )


def _encode(message: dict) -> str:
    return json.dumps(message, separators=(",", ":"))
