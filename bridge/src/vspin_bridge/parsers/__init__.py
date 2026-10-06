"""Parser: rohe BLE-Notifications → `TelemetrySample` (ADR-0003).

Werden von allen Byte-Quellen benutzt (Replay, später BLE). Unterstützt:

- CSC Measurement `0x2A5B` (`csc.py`) – Kadenz aus Kurbel-Events.
- FTMS Indoor Bike Data `0x2AD2` (`ftms.py`) – Geschwindigkeit, Kadenz, Leistung, Puls.
  Die Leistung gilt als geschätzt (`power_estimated`, ADR-0004): das JC312 kennt die
  Stellung des Widerstandsknopfs nicht.

Ein `Decoder` gehört zu genau einer Verbindung: er merkt sich den letzten Zählerstand
(CSC) und wird bei jeder neuen Verbindung neu angelegt.
"""

from ..sources.base import Capability, RawNotification, TelemetrySample
from .csc import CscCadence, parse_csc_measurement
from .errors import ParseError
from .ftms import parse_indoor_bike_data

CSC_MEASUREMENT = "00002a5b-0000-1000-8000-00805f9b34fb"
INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"


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
        if char == INDOOR_BIKE_DATA:
            bike = parse_indoor_bike_data(raw.data)
            # Momentanwerte: jede Notification mit Kadenz ist ein neuer Wert.
            return TelemetrySample(
                t_ms=raw.t_ms,
                cadence=bike.cadence_rpm,
                speed_kmh=bike.speed_kmh,
                power_w=bike.power_w,
                power_estimated=None if bike.power_w is None else True,
                heart_rate=bike.heart_rate,
            )
        return None


def capabilities(raw: RawNotification) -> set[Capability]:
    """Was diese eine Notification an Werten mitbringt (ohne Zustand, für die Capabilities
    einer Aufnahme). Kaputte oder unbekannte Notifications bringen nichts."""
    try:
        char = raw.char.lower()
        if char == CSC_MEASUREMENT:
            return {Capability.CADENCE} if parse_csc_measurement(raw.data).has_crank else set()
        if char == INDOOR_BIKE_DATA:
            bike = parse_indoor_bike_data(raw.data)
            found = {
                Capability.SPEED: bike.speed_kmh,
                Capability.CADENCE: bike.cadence_rpm,
                Capability.POWER: bike.power_w,
            }
            return {capability for capability, value in found.items() if value is not None}
    except ParseError:
        pass
    return set()


__all__ = ["CSC_MEASUREMENT", "INDOOR_BIKE_DATA", "Decoder", "ParseError", "capabilities"]
