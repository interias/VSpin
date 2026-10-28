"""Pulsquelle an Bus und Session (Spec #64, ADR-0008 Nachtrag „Puls als zweite Quelle“).

Die Bridge hält neben der Radquelle eine `HeartRateSource` (`sources/heart_rate.py`). Dieses Modul
verbindet sie mit dem Bus; die Bridge (`app.py`) reicht nur durch:

- **`telemetry.heart_rate`:** Ist ein Pulsgerät verbunden (`connected`/`stale`) oder hat die
  Pulsquelle einen Wert jünger als `stale_s` (5 s), gilt ihr Wert (`null`, wenn er zu alt ist).
  Sonst gilt der Puls, den das Rad selbst liefert (FTMS). Den Takt gibt weiter die Radquelle vor.
- **Befehle und Suche auf Anfrage** (`set_heart_rate_devices`, `start_heart_rate_search`, `stop_heart_rate_search`)
  laufen seit Spec #75 über die Rollen-Weiche `device_relay.py` (`kind: heart_rate`, die Befehle sind dort Aliase); das
  Verhalten aus #64 – Ergebnisse nur an den Anfrager, `taken_over`, `timeout`, Drosselung – gilt dort für alle Rollen.
"""

from collections.abc import Callable

from .ble.bleak_adapter import BleakAdapter
from .sources.base import RawNotification
from .sources.heart_rate import HeartRateSource, HeartRateState, HeartRateStatus

# Baut die Pulsquelle der Bridge aus ihren beiden Rückrufen (Zustand, Rohdaten). Die Bridge besitzt die
# Rückrufe, deshalb bekommt sie eine Fabrik statt einer fertigen Quelle. Tests und Replay (P4) übergeben
# eine Fabrik mit eigenem `BleAdapter`, z. B. `lambda on_status, on_raw: HeartRateSource(fake, on_status, on_raw)`.
HeartRateFactory = Callable[[Callable[[HeartRateStatus], None], Callable[[RawNotification], None]], HeartRateSource]


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
    ) -> None:
        self.source = factory(on_status, on_raw)

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
        await self.source.stop()
