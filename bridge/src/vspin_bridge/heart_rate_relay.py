"""Pulsquelle an Bus und Session (Spec #64, ADR-0008 Nachtrag „Puls als zweite Quelle“).

Die Bridge hält neben der Radquelle eine `HeartRateSource` (`sources/heart_rate.py`). Dieses Modul
verbindet sie mit dem Bus; die Bridge (`app.py`) reicht nur durch:

- **`telemetry.heart_rate`:** Ist ein Pulsgerät verbunden (`connected`/`stale`) oder hat die
  Pulsquelle einen Wert jünger als `stale_s` (5 s), gilt ihr Wert (`null`, wenn er zu alt ist).
  Sonst gilt der Puls, den das Rad selbst liefert (FTMS). Den Takt gibt weiter die Radquelle vor.
- **Befehle** `set_heart_rate_devices`, `start_heart_rate_search`, `stop_heart_rate_search`, jeweils
  mit `ack` an den Absender. Die gemerkten Geräte setzt jeder Client, zuletzt gesetzt gewinnt.
- **Suche auf Anfrage:** Ergebnisse (`heart_rate_found`) gehen nur an den Client, der sie gestartet
  hat. Es gibt eine Suche zur Zeit; startet ein anderer Client eine, gehört sie ab dann ihm, der
  vorige bekommt `heart_rate_search_ended` mit `taken_over`. Endet die Suche durch Zeitablauf,
  bekommt der Anfrager `heart_rate_search_ended` mit `timeout`; auf sein eigenes `stop` folgt nur
  das `ack`. Trennt er sich, endet seine Suche.
- **Drosselung:** Die Quelle meldet jede Ankündigung (oft mehrmals je Sekunde). Auf den Bus geht ein
  Gerät beim ersten Fund, danach höchstens einmal je `FOUND_INTERVAL_S` mit der dann aktuellen
  Signalstärke – oder sofort, wenn sich sein Name ändert. Die Signalstärke allein zählt nicht als
  Änderung: sie schwankt bei jeder Ankündigung und würde die Drosselung aushebeln.
"""

import asyncio
import time
from collections.abc import Callable

from .ble import Advertisement
from .ble.bleak_adapter import BleakAdapter
from .bus.messages import (
    SET_HEART_RATE_DEVICES,
    START_HEART_RATE_SEARCH,
    STOP_HEART_RATE_SEARCH,
    HeartRateCommand,
    SetHeartRateDevices,
    StartHeartRateSearch,
    ack_message,
    heart_rate_found_message,
    heart_rate_search_ended_message,
)
from .clock import bridge_time_ms
from .console import Console
from .sources.base import RawNotification
from .sources.heart_rate import SEARCH_S, HeartRateSource, HeartRateState, HeartRateStatus

FOUND_INTERVAL_S = 1.0  # ein Gerät höchstens so oft als `heart_rate_found` auf den Bus

# Baut die Pulsquelle der Bridge aus ihren beiden Rückrufen (Zustand, Rohdaten). Die Bridge besitzt die
# Rückrufe, deshalb bekommt sie eine Fabrik statt einer fertigen Quelle. Tests und Replay (P4) übergeben
# eine Fabrik mit eigenem `BleAdapter`, z. B. `lambda on_status, on_raw: HeartRateSource(fake, on_status, on_raw)`.
HeartRateFactory = Callable[[Callable[[HeartRateStatus], None], Callable[[RawNotification], None]], HeartRateSource]

Client = object  # undurchsichtiger Verweis auf einen Bus-Client (`BusServer.sender()`)


def bleak_heart_rate(
    on_status: Callable[[HeartRateStatus], None], on_raw: Callable[[RawNotification], None]
) -> HeartRateSource:
    """Standard der Bridge: Pulsquelle über bleak. Startet auch ohne Bluetooth-Adapter (Docker, CI): bis
    zum ersten Befehl fasst sie BLE nicht an; scheitert dann die Suche, versucht sie es alle 3 s erneut."""
    return HeartRateSource(BleakAdapter(), on_status, on_raw)


class HeartRateRelay:
    def __init__(
        self,
        factory: HeartRateFactory,
        on_status: Callable[[HeartRateStatus], None],
        on_raw: Callable[[RawNotification], None],
        send_to: Callable[[Client, str], None],
        console: Console,
    ) -> None:
        self.source = factory(on_status, on_raw)
        self._send_to = send_to
        self._console = console
        self._requester: Client | None = None  # Client der laufenden Suche auf Anfrage
        self._timer: asyncio.TimerHandle | None = None
        self._forwarded: dict[str, tuple[float, str | None]] = {}  # Adresse → (gesendet um, Name)

    @property
    def status(self) -> HeartRateStatus:
        return self.source.status

    def heart_rate(self, wheel: int | None) -> int | None:
        """Wert für `telemetry.heart_rate`; `wheel` ist der Puls, den das Rad selbst liefert (FTMS)."""
        bpm = self.source.heart_rate
        if self.source.status.state in (HeartRateState.CONNECTED, HeartRateState.STALE) or bpm is not None:
            return bpm
        return wheel

    async def start(self) -> None:
        await self.source.start()

    async def stop(self) -> None:
        self._end_search()
        await self.source.stop()

    async def handle(self, command: HeartRateCommand, sender: Client | None) -> str:
        """Antwort (`ack`) für den Absender eines Pulsbefehls."""
        if isinstance(command, SetHeartRateDevices):
            names = ", ".join(f"{d.name or d.address} ({d.role})" for d in command.devices)
            self._console.info(f"Pulsgeräte: {names or 'keine – Puls aus'}")
            await self.source.set_known_devices(command.devices)
            return ack_message(SET_HEART_RATE_DEVICES, True)
        if isinstance(command, StartHeartRateSearch):
            self._start_search(sender, SEARCH_S if command.duration_s is None else command.duration_s)
            return ack_message(START_HEART_RATE_SEARCH, True)
        if sender is not None and sender is self._requester:  # nur die eigene Suche; sonst ohne Wirkung
            self._stop_search("gestoppt")
        return ack_message(STOP_HEART_RATE_SEARCH, True)

    def client_left(self, client: Client) -> None:
        if client is self._requester:
            self._stop_search("Client getrennt")

    # --- Suche auf Anfrage ---------------------------------------------------------------

    def _start_search(self, client: Client | None, duration_s: float) -> None:
        previous = self._requester
        self._end_search()
        if previous is not None and previous is not client:
            self._send_to(previous, heart_rate_search_ended_message(bridge_time_ms(), "taken_over"))

        def found(advertisement: Advertisement) -> None:
            if client is not None and client is self._requester:
                self._forward(client, advertisement)

        self._requester = client
        self.source.start_search(found, duration_s)
        self._timer = asyncio.get_running_loop().call_later(duration_s, self._on_timeout)
        self._console.info(f"Pulssuche gestartet ({duration_s:g} s)")

    def _on_timeout(self) -> None:
        self._timer = None
        client = self._requester
        self._stop_search("Zeit abgelaufen")
        if client is not None:
            self._send_to(client, heart_rate_search_ended_message(bridge_time_ms(), "timeout"))

    def _stop_search(self, why: str) -> None:
        self._end_search()
        self.source.stop_search()
        self._console.info(f"Pulssuche beendet ({why})")

    def _end_search(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None
        self._requester = None
        self._forwarded.clear()

    def _forward(self, client: Client, advertisement: Advertisement) -> None:
        now = time.monotonic()
        last = self._forwarded.get(advertisement.address)
        # Ankündigungen ohne Namen (z. B. ohne Scan-Antwort) behalten den zuletzt gesehenen Namen.
        name = advertisement.name or (None if last is None else last[1])
        if last is not None and last[1] == name and now - last[0] < FOUND_INTERVAL_S:
            return
        self._forwarded[advertisement.address] = (now, name)
        found = Advertisement(advertisement.address, name, advertisement.rssi)
        self._send_to(client, heart_rate_found_message(bridge_time_ms(), found))
