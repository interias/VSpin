"""Bus-Nachrichten nach docs/bus-protocol.md (Version 0). Jede hat `v` und `type`.

Bridge → Clients: `status`, `telemetry`; Antworten an einen Client: `ack`, `error`.
Clients → Bridge: `set_grade`.
Puls (Spec #64): Bridge → Clients zusätzlich `heart_rate_found`, `heart_rate_search_ended` (nur an
den Anfrager der Suche); Clients → Bridge `set_heart_rate_devices`, `start_heart_rate_search`,
`stop_heart_rate_search`.
"""

import json
import math
from collections.abc import Iterable
from dataclasses import dataclass

from ..ble import Advertisement
from ..sources.base import Capability, TelemetrySample
from ..sources.heart_rate import HeartRateDevice, HeartRateState, HeartRateStatus, Role

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


def status_message(
    t_ms: int,
    state: str,
    source: str,
    capabilities: Iterable[Capability],
    heart_rate: HeartRateStatus = HeartRateStatus(HeartRateState.OFF),
) -> str:
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "status",
            "t_ms": t_ms,
            "state": state,
            "source": source,
            "capabilities": sorted(str(c) for c in capabilities),
            "heart_rate": heart_rate_block(heart_rate),  # Pulsquelle, hinter dem Radteil
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


def parse_client_message(raw: str | bytes) -> "SetGrade | HeartRateCommand":
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
    if kind in HEART_RATE_COMMANDS:
        return _heart_rate_command(kind, message)
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


# --- Puls (Spec #64) ---------------------------------------------------------

SET_HEART_RATE_DEVICES = "set_heart_rate_devices"
START_HEART_RATE_SEARCH = "start_heart_rate_search"
STOP_HEART_RATE_SEARCH = "stop_heart_rate_search"
HEART_RATE_COMMANDS = (SET_HEART_RATE_DEVICES, START_HEART_RATE_SEARCH, STOP_HEART_RATE_SEARCH)

SEARCH_DURATION_MAX_S = 120.0  # Suche auf Anfrage ist immer zeitlich begrenzt


@dataclass(frozen=True, slots=True)
class SetHeartRateDevices:
    devices: tuple[HeartRateDevice, ...]  # höchster Vorrang zuerst; leer = aus


@dataclass(frozen=True, slots=True)
class StartHeartRateSearch:
    duration_s: float | None  # None = Standarddauer der Pulsquelle


@dataclass(frozen=True, slots=True)
class StopHeartRateSearch:
    pass


HeartRateCommand = SetHeartRateDevices | StartHeartRateSearch | StopHeartRateSearch


def heart_rate_block(status: HeartRateStatus) -> dict:
    """Pulsblock in `status`: Zustand und verbundenes Gerät (`null`, wenn keins verbunden ist)."""
    device = status.device
    return {
        "state": str(status.state),
        "device": None
        if device is None
        else {"address": device.address, "name": device.name, "role": str(device.role)},
    }


def heart_rate_found_message(t_ms: int, found: Advertisement) -> str:
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "heart_rate_found",
            "t_ms": t_ms,
            "address": found.address,
            "name": found.name,
            "rssi": found.rssi,
        }
    )


def heart_rate_search_ended_message(t_ms: int, reason: str) -> str:
    return _encode({"v": PROTOCOL_VERSION, "type": "heart_rate_search_ended", "t_ms": t_ms, "reason": reason})


def _heart_rate_command(kind: str, message: dict) -> HeartRateCommand:
    if kind == SET_HEART_RATE_DEVICES:
        return SetHeartRateDevices(_devices(message.get("devices")))
    if kind == START_HEART_RATE_SEARCH:
        return StartHeartRateSearch(_duration(message.get("duration_s")))
    return StopHeartRateSearch()


def _devices(value: object) -> tuple[HeartRateDevice, ...]:
    if not isinstance(value, list):
        raise ClientMessageError("invalid_devices", f"'devices' muss eine Liste sein, war {value!r}")
    devices = []
    for i, entry in enumerate(value):
        if not isinstance(entry, dict):
            raise ClientMessageError("invalid_devices", f"devices[{i}] muss ein Objekt sein, war {entry!r}")
        address, name, role = entry.get("address"), entry.get("name"), entry.get("role")
        if not isinstance(address, str) or not address:
            raise ClientMessageError("invalid_devices", f"devices[{i}].address muss ein nicht leerer Text sein")
        if not isinstance(name, str):
            raise ClientMessageError("invalid_devices", f"devices[{i}].name muss ein Text sein, war {name!r}")
        if role not in tuple(Role):
            raise ClientMessageError(
                "invalid_devices", f"devices[{i}].role muss 'strap' oder 'watch' sein, war {role!r}"
            )
        devices.append(HeartRateDevice(address, name, Role(role)))
    return tuple(devices)


def _duration(value: object) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ClientMessageError("invalid_duration", f"'duration_s' muss eine Zahl sein, war {value!r}")
    try:
        duration = float(value)
    except OverflowError:
        duration = math.inf
    if not (0 < duration <= SEARCH_DURATION_MAX_S):
        raise ClientMessageError(
            "invalid_duration", f"'duration_s' muss > 0 und höchstens {SEARCH_DURATION_MAX_S:g} sein, war {value!r}"
        )
    return duration
