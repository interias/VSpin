"""Gemeinsame Schnittstelle aller Datenquellen (ADR-0003)."""

from collections.abc import AsyncIterator
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol


class Capability(StrEnum):
    """Fähigkeit einer Quelle; wird im Bus-`status` als Name gemeldet."""

    CADENCE = "CADENCE"
    SPEED = "SPEED"
    POWER = "POWER"
    RESISTANCE_CONTROL = "RESISTANCE_CONTROL"


@dataclass(frozen=True, slots=True)
class TelemetrySample:
    """Protokollneutraler Messpunkt. Fehlende Werte sind `None` (auf dem Bus `null`).

    Am Bus und in der CSV ist `t_ms` der monotone Bridge-Zeitstempel (siehe
    `clock.bridge_time_ms`); von einer Quelle kommend die Zeitachse der Quelle
    (siehe `DeviceSource.samples`).
    `power_estimated` trägt die Herkunft der Leistung: `True` = estimated,
    `False` = measured (ADR-0004).
    """

    t_ms: int
    cadence: float | None = None
    speed_kmh: float | None = None
    power_w: float | None = None
    power_estimated: bool | None = None
    heart_rate: int | None = None


@dataclass(frozen=True, slots=True)
class RawNotification:
    """Rohe BLE-Notification, wie sie im Replay-Format steht (ADR-0003, ADR-0008):
    `t_ms` Zeitstempel der Aufnahme, `char` volle 128-Bit-UUID der Characteristic,
    `data` die Nutzdaten. Byte-Quellen (Replay, später BLE) liefern diese statt fertiger
    Samples; die Bridge schreibt sie in die Session-Rohdatei und schickt sie durch die Parser."""

    t_ms: int
    char: str
    data: bytes


class NotSupportedError(Exception):
    """Die Quelle hat die nötige Capability nicht (z. B. `RESISTANCE_CONTROL`)."""


class SourceDisconnectedError(Exception):
    """Verbindung zur Quelle ist weg: `connect` erreicht das Gerät nicht oder `samples`
    bricht ab. Die Bridge meldet `disconnected` und versucht alle 3 s neu zu verbinden
    (ADR-0004)."""


class DeviceSource(Protocol):
    """Schnittstelle für BLE, Replay und Simulator – Clients sehen keinen Unterschied."""

    name: str  # Bus-`source`: ble | sim | replay
    capabilities: set[Capability]

    async def connect(self) -> None:
        """Wirft `SourceDisconnectedError`, wenn das Gerät gerade nicht erreichbar ist."""
        ...

    def samples(self) -> AsyncIterator[TelemetrySample | RawNotification]:
        """Samples bis zum Ende der Quelle; wirft `SourceDisconnectedError` bei Abbruch.
        Nach erneutem `connect` liefert ein neuer Aufruf die weiteren Samples.

        Der Simulator liefert fertige `TelemetrySample`s, Byte-Quellen (Replay, BLE) rohe
        `RawNotification`s – die parst die Bridge (`parsers`). Beides geht danach durch
        dieselbe Datenaufbereitung (`processing`, ADR-0004). `t_ms` ist dabei die Zeitachse
        der Quelle (Simulator: Bridge-Zeit, Replay: Zeit der Aufnahme)."""
        ...

    async def set_resistance(self, level: float) -> None:
        """Wirft `NotSupportedError` ohne Capability `RESISTANCE_CONTROL`."""
        ...
