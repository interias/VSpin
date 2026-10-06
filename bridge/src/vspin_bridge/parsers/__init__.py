"""Parser: rohe BLE-Notifications → `TelemetrySample` (ADR-0003).

Werden von allen Byte-Quellen benutzt (Replay, später BLE). Unterstützt:

- CSC Measurement `0x2A5B` (`csc.py`) – Kadenz aus Kurbel-Events.

Ein `Decoder` gehört zu genau einer Verbindung: er merkt sich den letzten Zählerstand
(CSC) und wird bei jeder neuen Verbindung neu angelegt.
"""

from ..sources.base import Capability, RawNotification, TelemetrySample
from .csc import CscCadence, parse_csc_measurement
from .errors import ParseError

CSC_MEASUREMENT = "00002a5b-0000-1000-8000-00805f9b34fb"


class Decoder:
    def __init__(self) -> None:
        self._csc = CscCadence()

    def decode(self, raw: RawNotification) -> TelemetrySample | None:
        """Sample zur Notification; `None` für Characteristics ohne Parser.
        Wirft `ParseError` bei kaputten Daten."""
        char = raw.char.lower()
        if char == CSC_MEASUREMENT:
            measurement = parse_csc_measurement(raw.data)
            # CSC liefert keine Geschwindigkeit (Radumfang unbekannt) und keine Leistung.
            return TelemetrySample(t_ms=raw.t_ms, cadence=self._csc.update(measurement, raw.t_ms))
        return None


def capabilities(raw: RawNotification) -> set[Capability]:
    """Was diese eine Notification an Werten mitbringt (ohne Zustand, für die Capabilities
    einer Aufnahme). Kaputte oder unbekannte Notifications bringen nichts."""
    try:
        if raw.char.lower() == CSC_MEASUREMENT:
            return {Capability.CADENCE} if parse_csc_measurement(raw.data).has_crank else set()
    except ParseError:
        pass
    return set()


__all__ = ["CSC_MEASUREMENT", "Decoder", "ParseError", "capabilities"]
