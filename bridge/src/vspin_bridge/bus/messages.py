"""Bus-Nachrichten nach docs/bus-protocol.md (Version 0). Jede hat `v` und `type`.

Bridge → Clients: `status`, `telemetry`; Antworten an einen Client: `ack`, `error`.
Clients → Bridge: `set_grade`.
"""

import json
import math
from collections.abc import Iterable
from dataclasses import dataclass

from ..sources.base import Capability, TelemetrySample

PROTOCOL_VERSION = 0


def telemetry_message(sample: TelemetrySample) -> str:
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "telemetry",
            "t_ms": sample.t_ms,
            "cadence": sample.cadence,
            "cadence_raw": sample.cadence_raw,
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


# --- Clients → Bridge ------------------------------------------------------

SET_GRADE = "set_grade"


class ClientMessageError(Exception):
    """Client-Nachricht ist kaputt oder unbekannt; wird als Bus-`error` beantwortet."""

    def __init__(self, reason: str, detail: str) -> None:
        super().__init__(f"{reason}: {detail}")
        self.reason = reason
        self.detail = detail


@dataclass(frozen=True, slots=True)
class SetGrade:
    grade: float  # Anteil, 0.07 = 7 % (ADR-0007)


def parse_client_message(raw: str | bytes) -> SetGrade:
    """Prüft eine Client-Nachricht. Wirft `ClientMessageError` mit `reason` aus docs/bus-protocol.md."""
    if not isinstance(raw, str):
        raise ClientMessageError("invalid_json", "Binärframe – erwartet UTF-8-JSON als Textframe")
    try:
        message = json.loads(raw)
    except ValueError as exc:
        raise ClientMessageError("invalid_json", f"kein gültiges JSON: {exc}") from None
    except RecursionError:
        raise ClientMessageError("invalid_json", "JSON zu tief verschachtelt") from None
    if not isinstance(message, dict):
        raise ClientMessageError("invalid_message", "erwartet ein JSON-Objekt")
    if "type" not in message:
        raise ClientMessageError("invalid_message", "Feld 'type' fehlt")
    if not _is_version(message.get("v")):
        raise ClientMessageError(
            "unsupported_version", f"'v' muss {PROTOCOL_VERSION} sein, war {message.get('v')!r}"
        )
    kind = message["type"]
    if kind != SET_GRADE:
        raise ClientMessageError("unknown_type", f"unbekannter type {kind!r}")
    return SetGrade(grade=_grade(message.get("grade")))


def ack_message(for_type: str, ok: bool, reason: str | None = None) -> str:
    return _encode({"v": PROTOCOL_VERSION, "type": "ack", "for": for_type, "ok": ok, "reason": reason})


def error_message(reason: str, detail: str) -> str:
    return _encode({"v": PROTOCOL_VERSION, "type": "error", "reason": reason, "detail": detail})


def _is_version(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == PROTOCOL_VERSION


def _grade(value: object) -> float:
    # Kein Plausibilitätsbereich: die Sicherheitsgrenzen liegen im Gerät (ADR-0007),
    # die Bridge prüft nur, dass es eine endliche Zahl ist (ADR-0004: so einfach wie möglich).
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ClientMessageError("invalid_grade", f"'grade' muss eine Zahl sein, war {value!r}")
    try:
        grade = float(value)
    except OverflowError:
        grade = math.inf
    if not math.isfinite(grade):
        raise ClientMessageError("invalid_grade", f"'grade' muss endlich sein, war {value!r}")
    return grade
