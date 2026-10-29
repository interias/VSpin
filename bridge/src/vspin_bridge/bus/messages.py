"""Bus-Nachrichten nach docs/bus-protocol.md (Version 0). Jede hat `v` und `type`.

Bridge → Clients: `status`, `telemetry`; Antworten an einen Client: `ack`, `error`.
Clients → Bridge: `set_grade`.
Puls (Spec #64): Bridge → Clients zusätzlich `heart_rate_found`, `heart_rate_search_ended` (nur an
den Anfrager der Suche); Clients → Bridge `set_heart_rate_devices`, `start_heart_rate_search`,
`stop_heart_rate_search`.
Fahrt speichern (Spec #84): Clients → Bridge `save_ride`; Antwort `ride_saved` nur an den Absender; Block
`garmin` in `status`.
Clients → alle anderen Clients (die Bridge leitet nur weiter): `ride_state`, `ride_event`,
`companion_ptt`, `companion_status`.
"""

import json
import math
import re
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
            "cadence_raw": sample.cadence_raw,
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
    garmin_login: str | None = None,
) -> str:
    message = {
        "v": PROTOCOL_VERSION,
        "type": "status",
        "t_ms": t_ms,
        "state": state,
        "source": source,
        "capabilities": sorted(str(c) for c in capabilities),
        "heart_rate": heart_rate_block(heart_rate),  # Pulsquelle, hinter dem Radteil
    }
    if garmin_login is not None:
        message["garmin"] = {"login": garmin_login}  # Anmeldezustand für den Upload (Spec #84)
    return _encode(message)


def _encode(message: dict) -> str:
    return json.dumps(message, separators=(",", ":"))


# --- Clients → Bridge ------------------------------------------------------

SET_GRADE = "set_grade"
# Nachrichten zwischen Spiel und Begleiter: Die Bridge prüft nur den Umschlag (`v`, `type`) und leitet den Frame
# unverändert an alle anderen Clients weiter – ihre Felder sind nicht ihr Vertrag (docs/bus-protocol.md).
RELAYED_TYPES = frozenset({"ride_state", "ride_event", "companion_ptt", "companion_status"})


class ClientMessageError(Exception):
    """Client-Nachricht ist kaputt oder unbekannt; wird als Bus-`error` beantwortet."""

    def __init__(self, reason: str, detail: str) -> None:
        super().__init__(f"{reason}: {detail}")
        self.reason = reason
        self.detail = detail


@dataclass(frozen=True, slots=True)
class SetGrade:
    grade: float  # Anteil, 0.07 = 7 % (ADR-0007)


@dataclass(frozen=True, slots=True)
class Relay:
    """Client-Nachricht für alle anderen Clients; `raw` ist der empfangene Textframe, unverändert."""

    type: str
    raw: str


def parse_client_message(raw: str | bytes) -> "SetGrade | HeartRateCommand | SaveRide | Relay":
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
    if isinstance(kind, str) and kind in RELAYED_TYPES:
        return Relay(type=kind, raw=raw)
    if kind in HEART_RATE_COMMANDS:
        return _heart_rate_command(kind, message)
    if kind == SAVE_RIDE:
        return _save_ride(message)
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


# --- Fahrt speichern (Spec #84) --------------------------------------------------------------

SAVE_RIDE = "save_ride"

# Die `ride_id` wird Teil des Dateinamens: nur Buchstaben, Ziffern, `_` und `-` – kein Pfad-Ausbruch.
RIDE_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,64}")


@dataclass(frozen=True, slots=True)
class SaveRide:
    ride_id: str
    start_t_ms: int  # Bridge-Zeit (`telemetry.t_ms`)
    end_t_ms: int
    lap_end_t_ms: tuple[int, ...]  # Ende jeder vollen Runde
    distance: tuple[tuple[int, float], ...]  # Streckenspur des Spiels: (t_ms, Meter)
    upload: bool


def ride_saved_message(
    ride_id: str, fit_path: str | None, fit_error: str | None, upload: tuple[str, str] | None
) -> str:
    """Antwort auf `save_ride`; `upload` ist (Zustand, Meldung) oder `None`, wenn keine FIT-Datei entstand."""
    return _encode(
        {
            "v": PROTOCOL_VERSION,
            "type": "ride_saved",
            "ride_id": ride_id,
            "fit_path": fit_path,
            "fit_error": fit_error,
            "upload": None if upload is None else {"state": upload[0], "message": upload[1]},
        }
    )


def _save_ride(message: dict) -> SaveRide:
    ride_id = message.get("ride_id")
    if not isinstance(ride_id, str) or not RIDE_ID_PATTERN.fullmatch(ride_id):
        _invalid_ride(f"'ride_id' muss 1–64 Zeichen aus A–Z, a–z, 0–9, _ und - sein, war {ride_id!r}")
    start, end = _ride_t_ms(message.get("start_t_ms"), "start_t_ms"), _ride_t_ms(message.get("end_t_ms"), "end_t_ms")
    if end <= start:
        _invalid_ride(f"'end_t_ms' muss nach 'start_t_ms' liegen, war {start} bis {end}")
    laps = message.get("lap_end_t_ms")
    if laps is None:
        laps = []
    if not isinstance(laps, list):
        _invalid_ride(f"'lap_end_t_ms' muss eine Liste sein, war {laps!r}")
    distance = message.get("distance")
    if not isinstance(distance, list):
        _invalid_ride(f"'distance' muss eine Liste von [t_ms, Meter] sein, war {distance!r}")
    track: list[tuple[int, float]] = []
    for i, point in enumerate(distance):
        if not isinstance(point, list) or len(point) != 2:
            _invalid_ride(f"distance[{i}] muss [t_ms, Meter] sein, war {point!r}")
        t_ms, meters = _ride_t_ms(point[0], f"distance[{i}][0]"), _meters(point[1], f"distance[{i}][1]")
        if track and (t_ms <= track[-1][0] or meters < track[-1][1]):
            _invalid_ride(f"distance[{i}]: t_ms muss steigen und die Strecke darf nicht fallen")
        track.append((t_ms, meters))
    upload = message.get("upload")
    if not isinstance(upload, bool):
        _invalid_ride(f"'upload' muss true oder false sein, war {upload!r}")
    return SaveRide(
        ride_id,
        start,
        end,
        tuple(_ride_t_ms(t, f"lap_end_t_ms[{i}]") for i, t in enumerate(laps)),
        tuple(track),
        upload,
    )


def _invalid_ride(detail: str):
    raise ClientMessageError("invalid_ride", detail)


def _ride_t_ms(value: object, name: str) -> int:
    """Bridge-Zeit: ganze Zahl ≥ 0. Auch `123.0` – Godot liest JSON-Zahlen als float."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _invalid_ride(f"'{name}' muss eine ganze Zahl sein, war {value!r}")
    if isinstance(value, float) and not (math.isfinite(value) and value.is_integer()):
        _invalid_ride(f"'{name}' muss eine ganze Zahl sein, war {value!r}")
    if value < 0:
        _invalid_ride(f"'{name}' darf nicht negativ sein, war {value!r}")
    return int(value)


def _meters(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _invalid_ride(f"'{name}' muss eine Zahl sein, war {value!r}")
    try:
        meters = float(value)
    except OverflowError:
        meters = math.inf
    if not (math.isfinite(meters) and meters >= 0):
        _invalid_ride(f"'{name}' muss eine endliche Zahl ≥ 0 sein, war {value!r}")
    return meters
