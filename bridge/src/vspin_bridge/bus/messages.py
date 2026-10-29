"""Bus-Nachrichten nach docs/bus-protocol.md (Version 0). Jede hat `v` und `type`.

Bridge → Clients: `status`, `telemetry`; Antworten an einen Client: `ack`, `error`.
Clients → Bridge: `set_grade`. `status` trägt seit Spec #75 den Block `trainer` (Stand der Steuerung).
Puls (Spec #64): Bridge → Clients zusätzlich `heart_rate_found`, `heart_rate_search_ended` (nur an
den Anfrager der Suche); Clients → Bridge `set_heart_rate_devices`, `start_heart_rate_search`,
`stop_heart_rate_search`.
Verbindungsfenster (Spec #75): Rollen `trainer | heart_rate | controller` (`DeviceKind`). Clients → Bridge `set_devices`,
`start_device_search`, `stop_device_search`, `reclaim_trainer_control`; Bridge → Anfrager `device_found`,
`device_search_ended`. Die Pulsbefehle aus #64 sind Aliase für `kind: heart_rate`. `status` trägt dazu `controller`
und `signal` (Signalstärke je Rolle), `trainer` zusätzlich `device`.
ERG (Spec #75): Clients → Bridge `set_target_power` (`watts` 0…2000 oder `null`); `trainer` trägt `mode` und
`target_power`.
"""

import json
import math
from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum

from ..ble import Advertisement
from ..sources.base import Capability, TelemetrySample
from ..sources.controller import ControllerDevice, ControllerState, ControllerStatus, Side, controller_side
from ..sources.heart_rate import HeartRateDevice, HeartRateState, HeartRateStatus, Role
from ..sources.trainer import TrainerDevice
from ..sources.trainer_control import TARGET_POWER_MAX_W

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
    trainer_control: str = "not_supported",
    trainer_device: TrainerDevice | None = None,
    controller: ControllerStatus = ControllerStatus(ControllerState.OFF),
    signal: dict[str, int | None] | None = None,
    trainer_mode: str = "sim",
    target_power: int | None = None,
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
            # Steuerung des Trainers (Spec #75)
            "trainer": trainer_block(trainer_control, trainer_device, trainer_mode, target_power),
            "controller": controller_block(controller),  # Lenkercontroller (Spec #75)
            "signal": signal_block(signal or {}),  # Signalstärke je Rolle (Verbindungsfenster)
        }
    )


def trainer_block(
    control: str, device: TrainerDevice | None = None, mode: str = "sim", target_power: int | None = None
) -> dict:
    """Trainerblock in `status`: Stand der Steuerung (`ControlState`), der verbundene Trainer (`null` ohne
    Verbindung bzw. bei Simulator und Replay), Steuermodus (`sim` | `erg`) und Zielleistung in W (`null` ohne ERG)."""
    return {
        "control": str(control),
        "device": None if device is None else {"address": device.address, "name": device.name},
        "mode": mode,
        "target_power": target_power,
    }


def controller_block(status: ControllerStatus) -> dict:
    """Controllerblock in `status`: Zustand, Gerät (bei `connected`/`locked`, sonst `null`) und Batterie in Prozent."""
    device = status.device
    side = None if device is None or device.side is None else str(device.side)
    return {
        "state": str(status.state),
        "device": None if device is None else {"address": device.address, "name": device.name, "side": side},
        "battery": status.battery,
    }


def signal_block(signal: dict[str, int | None]) -> dict:
    """Signalstärke (dBm) je Rolle: die Ankündigung, nach der das Gerät verbunden wurde; `null` ohne Gerät."""
    return {str(kind): signal.get(str(kind)) for kind in DeviceKind}


def _encode(message: dict) -> str:
    return json.dumps(message, separators=(",", ":"))


# --- Clients → Bridge ------------------------------------------------------

SET_GRADE = "set_grade"
SET_TARGET_POWER = "set_target_power"


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
class SetTargetPower:
    watts: int | None  # Zielleistung in W (ERG); None beendet ERG


def parse_client_message(
    raw: str | bytes,
) -> "SetGrade | SetTargetPower | DeviceCommand | ReclaimTrainerControl":
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
    if kind in DEVICE_COMMANDS:
        return _device_command(kind, message)
    if kind == RECLAIM_TRAINER_CONTROL:
        return ReclaimTrainerControl()
    if kind == SET_TARGET_POWER:
        if "watts" not in message:
            raise ClientMessageError("invalid_watts", "Feld 'watts' fehlt (Zahl oder null)")
        return SetTargetPower(watts=_watts(message["watts"]))
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


def _watts(value: object) -> int | None:
    # Ganze Watt 0…2000 oder null; eine ganzzahlige Kommazahl (250.0) gilt als ganze Zahl.
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ClientMessageError("invalid_watts", f"'watts' muss eine ganze Zahl oder null sein, war {value!r}")
    if isinstance(value, float) and not (math.isfinite(value) and value.is_integer()):
        raise ClientMessageError("invalid_watts", f"'watts' muss eine ganze Zahl sein, war {value!r}")
    watts = int(value)
    if not 0 <= watts <= TARGET_POWER_MAX_W:
        raise ClientMessageError("invalid_watts", f"'watts' muss 0–{TARGET_POWER_MAX_W} sein, war {value!r}")
    return watts


# --- Rollen und Verbindungsfenster (Spec #75) -----------------------------------


class DeviceKind(StrEnum):
    """Rolle eines Geräts im Verbindungsfenster; je Rolle eine Kachel und eine Suche zur Zeit."""

    TRAINER = "trainer"
    HEART_RATE = "heart_rate"
    CONTROLLER = "controller"


SET_DEVICES = "set_devices"
START_DEVICE_SEARCH = "start_device_search"
STOP_DEVICE_SEARCH = "stop_device_search"
DEVICE_COMMANDS = (SET_DEVICES, START_DEVICE_SEARCH, STOP_DEVICE_SEARCH)
RECLAIM_TRAINER_CONTROL = "reclaim_trainer_control"

# Puls (Spec #64): Aliase für `kind: heart_rate`; Antworten und Suchergebnisse in der alten Form.
SET_HEART_RATE_DEVICES = "set_heart_rate_devices"
START_HEART_RATE_SEARCH = "start_heart_rate_search"
STOP_HEART_RATE_SEARCH = "stop_heart_rate_search"
HEART_RATE_COMMANDS = (SET_HEART_RATE_DEVICES, START_HEART_RATE_SEARCH, STOP_HEART_RATE_SEARCH)

SEARCH_DURATION_MAX_S = 120.0  # Suche auf Anfrage ist immer zeitlich begrenzt

Device = TrainerDevice | HeartRateDevice | ControllerDevice


@dataclass(frozen=True, slots=True)
class SetDevices:
    kind: DeviceKind
    devices: tuple[Device, ...]  # höchster Vorrang zuerst (Trainer: das stärkste gemerkte gewinnt); leer = keins
    for_type: str = SET_DEVICES  # Typ der Anfrage (Alias aus #64: `set_heart_rate_devices`) – für das `ack`


@dataclass(frozen=True, slots=True)
class StartDeviceSearch:
    kind: DeviceKind
    duration_s: float | None  # None = Standarddauer der Rolle
    for_type: str = START_DEVICE_SEARCH  # Alias `start_heart_rate_search`: Ergebnisse als `heart_rate_found`


@dataclass(frozen=True, slots=True)
class StopDeviceSearch:
    kind: DeviceKind | None  # None = alle eigenen Suchen
    for_type: str = STOP_DEVICE_SEARCH


@dataclass(frozen=True, slots=True)
class ReclaimTrainerControl:
    pass


DeviceCommand = SetDevices | StartDeviceSearch | StopDeviceSearch


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


def device_found_message(t_ms: int, kind: DeviceKind, found: Advertisement) -> str:
    """Suchergebnis einer Rolle; beim Controller mit `side` (`left | right | null`) aus den Herstellerdaten."""
    message = {
        "v": PROTOCOL_VERSION,
        "type": "device_found",
        "t_ms": t_ms,
        "kind": str(kind),
        "address": found.address,
        "name": found.name,
        "rssi": found.rssi,
    }
    if kind is DeviceKind.CONTROLLER:
        side = controller_side(found)
        message["side"] = None if side is None else str(side)
    return _encode(message)


def device_search_ended_message(t_ms: int, kind: DeviceKind, reason: str) -> str:
    return _encode(
        {"v": PROTOCOL_VERSION, "type": "device_search_ended", "t_ms": t_ms, "kind": str(kind), "reason": reason}
    )


def _heart_rate_command(kind: str, message: dict) -> DeviceCommand:
    if kind == SET_HEART_RATE_DEVICES:
        return SetDevices(DeviceKind.HEART_RATE, _devices(DeviceKind.HEART_RATE, message.get("devices")), kind)
    if kind == START_HEART_RATE_SEARCH:
        return StartDeviceSearch(DeviceKind.HEART_RATE, _duration(message.get("duration_s")), kind)
    return StopDeviceSearch(DeviceKind.HEART_RATE, kind)


def _device_command(kind: str, message: dict) -> DeviceCommand:
    if kind == STOP_DEVICE_SEARCH:
        return StopDeviceSearch(None if message.get("kind") is None else _kind(message.get("kind")))
    role = _kind(message.get("kind"))
    if kind == SET_DEVICES:
        return SetDevices(role, _devices(role, message.get("devices")))
    return StartDeviceSearch(role, _duration(message.get("duration_s")))


def _kind(value: object) -> DeviceKind:
    if value not in tuple(DeviceKind):
        raise ClientMessageError(
            "invalid_kind", f"'kind' muss 'trainer', 'heart_rate' oder 'controller' sein, war {value!r}"
        )
    return DeviceKind(value)


def _devices(kind: DeviceKind, value: object) -> tuple[Device, ...]:
    if not isinstance(value, list):
        raise ClientMessageError("invalid_devices", f"'devices' muss eine Liste sein, war {value!r}")
    devices = []
    for i, entry in enumerate(value):
        if not isinstance(entry, dict):
            raise ClientMessageError("invalid_devices", f"devices[{i}] muss ein Objekt sein, war {entry!r}")
        address, name = entry.get("address"), entry.get("name")
        if not isinstance(address, str) or not address:
            raise ClientMessageError("invalid_devices", f"devices[{i}].address muss ein nicht leerer Text sein")
        if not isinstance(name, str):
            raise ClientMessageError("invalid_devices", f"devices[{i}].name muss ein Text sein, war {name!r}")
        if kind is DeviceKind.HEART_RATE:
            role = entry.get("role")
            if role not in tuple(Role):
                raise ClientMessageError(
                    "invalid_devices", f"devices[{i}].role muss 'strap' oder 'watch' sein, war {role!r}"
                )
            devices.append(HeartRateDevice(address, name, Role(role)))
        elif kind is DeviceKind.CONTROLLER:
            side = entry.get("side")
            if side is not None and side not in tuple(Side):
                raise ClientMessageError(
                    "invalid_devices", f"devices[{i}].side muss 'left', 'right' oder null sein, war {side!r}"
                )
            devices.append(ControllerDevice(address, name, None if side is None else Side(side)))
        else:
            devices.append(TrainerDevice(address, name))
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
