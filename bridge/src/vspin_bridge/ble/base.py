"""Nahtstelle zum BLE-Stack: suchen, verbinden, Notifications, Abbruch, trennen.

Allgemein gehalten, nicht pulsspezifisch: Die `HeartRateSource` nutzt sie als Erste, die
`BleSource` fürs Rad (#9) soll sie wiederverwenden. Was ein Gerät bedeutet (Rolle, Vorrang,
Parser), gehört der Quelle, nicht hierher.

Alle Rückrufe kommen im Event-Loop der Bridge an (bleak ruft sie dort auf, der Fake auch).
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol


class BleError(Exception):
    """BLE-Vorgang gescheitert: Suche lässt sich nicht starten (z. B. kein Bluetooth-Adapter),
    Gerät nicht erreichbar, Abonnieren oder Trennen gescheitert."""


@dataclass(frozen=True, slots=True)
class Advertisement:
    """Ein gefundenes Gerät, so wie es gerade sendet. `name` fehlt, wenn das Gerät keinen
    mitschickt; `rssi` ist die Signalstärke in dBm."""

    address: str
    name: str | None
    rssi: int


class BleScan(Protocol):
    """Eine laufende Suche."""

    async def stop(self) -> None: ...


class BleConnection(Protocol):
    """Eine bestehende Verbindung zu einem Gerät."""

    address: str

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        """Notifications der Characteristic `char` (volle 128-Bit-UUID) abonnieren.
        Wirft `BleError`."""
        ...

    async def disconnect(self) -> None:
        """Trennen. Ein schon getrenntes Gerät ist kein Fehler."""
        ...


class BleAdapter(Protocol):
    """Zugang zum BLE-Stack (bleak oder der Fake der Tests)."""

    async def start_scan(self, service: str, on_found: Callable[[Advertisement], None]) -> BleScan:
        """Sucht nach Geräten, die den Service `service` (volle 128-Bit-UUID) ankündigen.
        `on_found` bekommt laufend jede Ankündigung, also dasselbe Gerät wiederholt mit
        aktueller Signalstärke. Wirft `BleError`, wenn die Suche nicht startet."""
        ...

    async def connect(self, address: str, on_disconnect: Callable[[], None]) -> BleConnection:
        """Verbindet mit dem Gerät an `address`. `on_disconnect` meldet, dass die Verbindung
        weg ist, auch nach eigenem `disconnect`. Wirft `BleError`, wenn das Gerät nicht
        erreichbar ist."""
        ...
