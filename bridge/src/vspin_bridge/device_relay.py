"""Rollen am Bus (Spec #75, Verbindungsfenster): gemerkte Geräte und Suche auf Anfrage für `trainer`, `heart_rate`
und `controller` – der Mechanismus aus #64 (`heart_rate_relay.py`), auf Rollen verallgemeinert.

- **Befehle** `set_devices {kind, devices}`, `start_device_search {kind, duration_s}`, `stop_device_search {kind}`,
  jeweils mit `ack` an den Absender. Die Pulsbefehle aus #64 (`set_heart_rate_devices`, `start_heart_rate_search`,
  `stop_heart_rate_search`) sind Aliase für `kind: heart_rate`; ihr `ack` trägt den alten Typ, ihre Suche meldet
  `heart_rate_found`/`heart_rate_search_ended` wie bisher. Die gemerkten Geräte setzt jeder Client, zuletzt gesetzt
  gewinnt.
- **Suche auf Anfrage**, je Rolle eine zur Zeit: Ergebnisse (`device_found`) gehen nur an den Client, der sie
  gestartet hat. Startet ein anderer Client eine Suche derselben Rolle, gehört sie ab dann ihm, der vorige bekommt
  `device_search_ended` (bzw. den Alias) mit `taken_over`. Endet sie durch Zeitablauf, bekommt der Anfrager `timeout`;
  auf sein eigenes `stop` folgt nur das `ack`. Trennt er sich, enden seine Suchen.
- **Drosselung:** ein Gerät beim ersten Fund, danach höchstens einmal je `FOUND_INTERVAL_S` mit der dann aktuellen
  Signalstärke – oder sofort, wenn sich sein Name ändert (wie in #64).
- **Ohne Rolle:** Läuft die Bridge mit Simulator oder Replay, gibt es keinen Trainer: `set_devices` für `trainer` wird
  quittiert und bleibt ohne Wirkung, `start_device_search` bekommt `ack` mit `not_supported`.
"""

import asyncio
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import replace
from typing import Protocol

from .ble import Advertisement
from .ble.bleak_adapter import BleakAdapter
from .bus.messages import (
    START_HEART_RATE_SEARCH,
    Device,
    DeviceCommand,
    DeviceKind,
    SetDevices,
    StartDeviceSearch,
    ack_message,
    device_found_message,
    device_search_ended_message,
    heart_rate_found_message,
    heart_rate_search_ended_message,
)
from .clock import bridge_time_ms
from .console import Console
from .sources.controller import ControllerDevice, ControllerSource, ControllerStatus
from .sources.heart_rate import SEARCH_S, HeartRateDevice

FOUND_INTERVAL_S = 1.0  # ein Gerät höchstens so oft als Suchergebnis auf den Bus

Client = object  # undurchsichtiger Verweis auf einen Bus-Client (`BusServer.sender()`)

# Baut die Controller-Quelle der Bridge aus ihrem Rückruf (Zustand); Tests übergeben eine mit dem BLE-Fake.
ControllerFactory = Callable[[Callable[[ControllerStatus], None]], ControllerSource]

LABELS = {DeviceKind.TRAINER: "Trainer", DeviceKind.HEART_RATE: "Puls", DeviceKind.CONTROLLER: "Controller"}
LISTS = {DeviceKind.TRAINER: "Trainer", DeviceKind.HEART_RATE: "Pulsgeräte", DeviceKind.CONTROLLER: "Controller"}
OFF = {
    DeviceKind.TRAINER: "keine – kein Trainer verbindet sich von selbst",
    DeviceKind.HEART_RATE: "keine – Puls aus",
    DeviceKind.CONTROLLER: "keine – Controller aus",
}


def bleak_controller(on_status: Callable[[ControllerStatus], None]) -> ControllerSource:
    """Standard der Bridge: Controller über bleak; fasst BLE erst beim ersten Befehl an (wie der Puls)."""
    return ControllerSource(BleakAdapter(), on_status)


class Role(Protocol):
    """Was eine Rolle für das Verbindungsfenster kann (`HeartRateSource`, `TrainerSource`, `ControllerSource`)."""

    async def set_known_devices(self, devices: Sequence[Device]) -> None: ...

    def start_search(self, on_found: Callable[[Advertisement], None], duration_s: float | None = None) -> None: ...

    def stop_search(self) -> None: ...


class _Search:
    """Laufende Suche auf Anfrage einer Rolle: Anfrager, Form der Antworten (Alias aus #64 oder neu), Zeitgeber."""

    def __init__(self, client: Client | None, alias: bool, timer: asyncio.TimerHandle) -> None:
        self.client = client
        self.alias = alias
        self.timer = timer
        self.forwarded: dict[str, tuple[float, str | None]] = {}  # Adresse → (gesendet um, Name)


class DeviceRelay:
    def __init__(self, roles: Mapping[DeviceKind, Role], send_to: Callable[[Client, str], None], console: Console) -> None:
        self._roles = dict(roles)
        self._send_to = send_to
        self._console = console
        self._searches: dict[DeviceKind, _Search] = {}

    async def handle(self, command: DeviceCommand, sender: Client | None) -> str:
        """Antwort (`ack`) für den Absender eines Gerätebefehls."""
        if isinstance(command, SetDevices):
            names = ", ".join(_describe(device) for device in command.devices)
            role = self._roles.get(command.kind)
            effect = "" if role is not None else " (ohne Trainerquelle ohne Wirkung)"
            self._console.info(f"{LISTS[command.kind]}: {names or OFF[command.kind]}{effect}")
            if role is not None:
                await role.set_known_devices(command.devices)
            return ack_message(command.for_type, True)
        if isinstance(command, StartDeviceSearch):
            if command.kind not in self._roles:
                return ack_message(command.for_type, False, "not_supported")
            duration_s = SEARCH_S if command.duration_s is None else command.duration_s
            self._start_search(command.kind, sender, command.for_type == START_HEART_RATE_SEARCH, duration_s)
            return ack_message(command.for_type, True)
        kinds = list(self._searches) if command.kind is None else [command.kind]
        for kind in kinds:  # nur die eigene Suche; sonst ohne Wirkung
            search = self._searches.get(kind)
            if search is not None and sender is not None and search.client is sender:
                self._stop_search(kind, "gestoppt")
        return ack_message(command.for_type, True)

    def client_left(self, client: Client) -> None:
        for kind, search in list(self._searches.items()):
            if search.client is client:
                self._stop_search(kind, "Client getrennt")

    def stop(self) -> None:
        """Bridge endet: alle Suchen auf Anfrage beenden (ohne Meldung an die Anfrager)."""
        for kind in list(self._searches):
            self._stop_search(kind, "Bridge endet")

    # --- Suche auf Anfrage ---------------------------------------------------------------

    def _start_search(self, kind: DeviceKind, client: Client | None, alias: bool, duration_s: float) -> None:
        previous = self._searches.pop(kind, None)
        if previous is not None:
            previous.timer.cancel()
            if previous.client is not None and previous.client is not client:
                self._send_to(previous.client, _ended(kind, previous.alias, "taken_over"))
        timer = asyncio.get_running_loop().call_later(duration_s, self._on_timeout, kind)
        search = _Search(client, alias, timer)
        self._searches[kind] = search

        def found(advertisement: Advertisement) -> None:
            if client is not None and self._searches.get(kind) is search:
                self._forward(kind, search, advertisement)

        self._roles[kind].start_search(found, duration_s)
        self._console.info(f"{LABELS[kind]}suche gestartet ({duration_s:g} s)")

    def _on_timeout(self, kind: DeviceKind) -> None:
        search = self._searches.get(kind)
        if search is None:
            return
        self._stop_search(kind, "Zeit abgelaufen")
        if search.client is not None:
            self._send_to(search.client, _ended(kind, search.alias, "timeout"))

    def _stop_search(self, kind: DeviceKind, why: str) -> None:
        search = self._searches.pop(kind, None)
        if search is not None:
            search.timer.cancel()
        self._roles[kind].stop_search()
        self._console.info(f"{LABELS[kind]}suche beendet ({why})")

    def _forward(self, kind: DeviceKind, search: _Search, advertisement: Advertisement) -> None:
        now = time.monotonic()
        last = search.forwarded.get(advertisement.address)
        # Ankündigungen ohne Namen (z. B. ohne Scan-Antwort) behalten den zuletzt gesehenen Namen.
        name = advertisement.name or (None if last is None else last[1])
        if last is not None and last[1] == name and now - last[0] < FOUND_INTERVAL_S:
            return
        search.forwarded[advertisement.address] = (now, name)
        found = replace(advertisement, name=name)
        if search.alias:
            message = heart_rate_found_message(bridge_time_ms(), Advertisement(found.address, name, found.rssi))
        else:
            message = device_found_message(bridge_time_ms(), kind, found)
        self._send_to(search.client, message)


def _ended(kind: DeviceKind, alias: bool, reason: str) -> str:
    if alias:
        return heart_rate_search_ended_message(bridge_time_ms(), reason)
    return device_search_ended_message(bridge_time_ms(), kind, reason)


def _describe(device: Device) -> str:
    if isinstance(device, HeartRateDevice):
        return f"{device.name or device.address} ({device.role})"
    if isinstance(device, ControllerDevice):
        return f"{device.name or device.address} ({device.side or 'Seite unbekannt'})"
    return device.name or device.address
