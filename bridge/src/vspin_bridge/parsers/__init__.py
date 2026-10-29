"""Parser: rohe BLE-Notifications → `TelemetrySample` (ADR-0003).

Werden von allen Byte-Quellen benutzt (Replay, Trainer per BLE). Unterstützt:

- CSC Measurement `0x2A5B` (`csc.py`) – Kadenz aus Kurbel-Events.
- FTMS Indoor Bike Data `0x2AD2` (`ftms.py`) – Geschwindigkeit, Kadenz, Leistung, Puls.
  Ob die Leistung gemessen oder geschätzt ist, bestimmt die Quelle (`Decoder(power_estimated=…)`,
  ADR-0004): das Replay einer Aufnahme ohne Leistungsmessung schätzt, der Trainer misst.
- Cycling Power Measurement `0x2A63` (`cycling_power.py`) – Kadenz aus den Kurbeldaten, wenn ein
  Trainer sie nicht in `0x2AD2` meldet.

Ein `Decoder` gehört zu genau einer Verbindung: er merkt sich den letzten Zählerstand
(CSC) und wird bei jeder neuen Verbindung neu angelegt.
"""

from dataclasses import replace

from ..sources.base import Capability, RawNotification, TelemetrySample
from .csc import CscCadence, parse_csc_measurement
from .cycling_power import parse_cycling_power_measurement
from .errors import ParseError
from .ftms import parse_fitness_machine_features, parse_indoor_bike_data
from .heart_rate import parse_heart_rate_measurement

CSC_MEASUREMENT = "00002a5b-0000-1000-8000-00805f9b34fb"
INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"
HEART_RATE_MEASUREMENT = "00002a37-0000-1000-8000-00805f9b34fb"
CYCLING_POWER_MEASUREMENT = "00002a63-0000-1000-8000-00805f9b34fb"
FITNESS_MACHINE_FEATURE = "00002acc-0000-1000-8000-00805f9b34fb"


class Decoder:
    """`power_estimated`: Herkunft der Leistung aus `0x2AD2` und `0x2A63` – `True` geschätzt (Replay einer
    Aufnahme ohne Leistungsmessung, Standard), `False` gemessen (Trainer)."""

    def __init__(self, power_estimated: bool = True) -> None:
        self._csc = CscCadence()
        self._power_cadence = CscCadence()  # Kurbeldaten aus 0x2A63, getrennt von CSC
        self._power_estimated = power_estimated
        self._bike: TelemetrySample | None = None  # letztes 0x2AD2-Sample, Träger von Tempo, Leistung, Puls

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
            self._bike = TelemetrySample(
                t_ms=raw.t_ms,
                cadence=bike.cadence_rpm,
                speed_kmh=bike.speed_kmh,
                power_w=bike.power_w,
                power_estimated=None if bike.power_w is None else self._power_estimated,
                heart_rate=bike.heart_rate,
            )
            return self._bike
        if char == CYCLING_POWER_MEASUREMENT:
            power = parse_cycling_power_measurement(raw.data)
            cadence = self._power_cadence.update(power.crank, raw.t_ms)
            # Tempo, Leistung und Puls bleiben die aus 0x2AD2 (die Werte zweier Characteristics setzen sich
            # nicht gegenseitig auf `None`); fehlt dort die Leistung (oder es gibt 0x2AD2 gar nicht), gilt die
            # aus 0x2A63. Die Kadenz setzt die Datenaufbereitung bei einem Sample ohne Kadenz nicht zurück.
            bike = self._bike or TelemetrySample(t_ms=raw.t_ms)
            has_power = bike.power_w is not None
            return replace(
                bike,
                t_ms=raw.t_ms,
                cadence=cadence,
                power_w=bike.power_w if has_power else power.power_w,
                power_estimated=bike.power_estimated if has_power else self._power_estimated,
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
        if char == CYCLING_POWER_MEASUREMENT:
            return {Capability.CADENCE} if parse_cycling_power_measurement(raw.data).crank_revs is not None else set()
    except ParseError:
        pass
    return set()


__all__ = [
    "CSC_MEASUREMENT",
    "CYCLING_POWER_MEASUREMENT",
    "FITNESS_MACHINE_FEATURE",
    "HEART_RATE_MEASUREMENT",
    "INDOOR_BIKE_DATA",
    "Decoder",
    "ParseError",
    "capabilities",
    "parse_fitness_machine_features",
    "parse_heart_rate_measurement",
]
