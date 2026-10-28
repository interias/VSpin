"""FIT-Aktivität einer Fahrt (Spec #84; ADR-0008 „csv → .fit“).

Die Bridge exportiert, weil nur sie loggt (ADR-0008); das Spiel kennt die Fahrt. Darum bekommt
`build_ride_fit` vom Spiel Start, Ende, Rundenenden und die Streckenspur, aus der Session-CSV die
Samples (`samples.read_session_samples`).

Inhalt nach dem FIT-Cookbook „Encoding Activity Files“: `file_id`, `device_info`, `event` Timer
Start/Stopp, `record` (Leistung, Kadenz, Puls, Geschwindigkeit, Strecke – keine Position), je Runde ein
`lap`, `session` (Radfahren, virtuell) und `activity`.

- **Hersteller `development`** (255), nie Garmin: kein Hersteller-Spoofing, auch wenn Garmin dann keine
  Trainingsbelastung berechnet (Spec #84, Out of Scope).
- **Geschätzte Watt fehlen** (ADR-0008, ADR-0004): Ein Record bekommt Leistung nur aus einem Sample mit
  `power_estimated = False`. Lap- und Session-Mittel rechnen nur mit diesen Records, sind alle Watt
  geschätzt, hat die Datei gar keine Leistung. Leistung ohne Herkunftsangabe gilt ebenfalls nicht als
  gemessen.
- **Record-Takt 1 s** ab dem Start der Fahrt (Start + k s bis einschließlich Ende): FIT speichert
  Zeitstempel in ganzen Sekunden, Garmin Connect zeigt nicht feiner, und das Spiel liefert die
  Streckenspur etwa mit 1 Hz. Ein dichterer Takt ergäbe doppelte Zeitstempel. Der Record zur Zeit T nimmt
  das letzte Sample aus (T − 1 s, T]; gibt es keins oder fehlt ein Wert darin, fehlt das Feld – kein
  Übertrag, keine Null (Puls-Lücken bleiben leer).
- **Wanduhr**: Der Start der Fahrt wird auf die ganze Sekunde davor gelegt (alle Zeitstempel rücken um
  weniger als 1 s), damit die Records genau auf ganzen Sekunden liegen. Dauern bleiben auf die ms genau.
- **Strecke und Geschwindigkeit aus der Streckenspur des Spiels**: Strecke linear auf die Record-Zeit
  interpoliert und auf 0 am Start bezogen, Geschwindigkeit = Steigung der Spur im Abschnitt, in dem T
  liegt. Vor dem ersten und nach dem letzten Spurpunkt steht die Strecke still (Geschwindigkeit 0).
- **Runden**: Jede volle Runde wird ein Lap, ein Rest nach der letzten vollen Runde ein letzter Lap; ohne
  volle Runde gibt es einen Lap über die ganze Fahrt. Die Laps decken die Fahrt lückenlos ab, ihre Zeiten
  und Strecken (ganze ms bzw. cm) summieren sich exakt zur Session.
- **Eindeutigkeit**: `serial_number` aus der `ride_id`, `time_created` = Start der Fahrt. Gleiche Eingaben
  ergeben dieselbe Datei.

fit-tool ist ein optionales Extra (`pip install -e ".[fit]"`) und wird erst beim Export geladen; ohne es
läuft die Bridge normal, nur der Export wirft `FitToolMissingError`.
"""

import hashlib
from bisect import bisect_right
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from types import SimpleNamespace

from .samples import RideSample

RECORD_INTERVAL_MS = 1000
PRODUCT_ID = 1  # frei wählbar beim Hersteller `development`
PRODUCT_NAME = "VSpin"
_FIT_EPOCH_S = 631065600  # 1989-12-31 00:00:00 UTC in Unix-Sekunden

# Feste lokale Nachrichtennummern je Typ: weniger neue Definitionen im Wechsel der Nachrichten.
_LOCAL_ID = {"file_id": 0, "device_info": 1, "event": 2, "record": 3, "lap": 4, "session": 5, "activity": 6}


class FitToolMissingError(RuntimeError):
    """fit-tool ist nicht installiert – der FIT-Export ist ein optionales Extra der Bridge."""

    def __init__(self) -> None:
        super().__init__('FIT-Export nicht möglich: fit-tool fehlt (im Ordner bridge/: pip install -e ".[fit]")')


def build_ride_fit(
    *,
    ride_id: str,
    start_t_ms: int,
    end_t_ms: int,
    wall_clock_at_zero: datetime,
    samples: Sequence[RideSample],
    distance_track: Sequence[tuple[int, float]],
    lap_end_t_ms: Sequence[int] = (),
) -> bytes:
    """Baut die FIT-Aktivitätsdatei einer Fahrt und gibt ihre Bytes zurück.

    Alle `t_ms` sind Bridge-Zeit derselben Session (`clock.bridge_time_ms`).

    - `start_t_ms`, `end_t_ms`: Start und Ende der Fahrt.
    - `wall_clock_at_zero`: Wanduhr bei `t_ms = 0` als aware `datetime` in der Ortszeit des Fahrers
      (z. B. `datetime.now().astimezone()`); daraus werden alle Zeitstempel. Ihr UTC-Versatz ergibt
      `activity.local_timestamp` – mit UTC stünde dort UTC statt Ortszeit (MEZ/MESZ).
    - `samples`: Samples der Fahrt, nach `t_ms` aufsteigend (`read_session_samples`); welche außerhalb
      von Start und Ende liegen, zählen nicht.
    - `distance_track`: Streckenspur des Spiels `[(t_ms, distance_m), …]`, `t_ms` streng steigend,
      Strecke nicht fallend. Leer heißt: keine Strecke, keine Geschwindigkeit.
    - `lap_end_t_ms`: Rundenenden (Ende jeder vollen Runde); Werte außerhalb von (Start, Ende] zählen
      nicht.

    Wirft `FitToolMissingError` ohne fit-tool, `ValueError` bei unbrauchbaren Eingaben.
    """
    if end_t_ms <= start_t_ms:
        raise ValueError(f"Fahrt ohne Dauer: Start {start_t_ms}, Ende {end_t_ms}")
    offset = wall_clock_at_zero.utcoffset()
    if offset is None:
        raise ValueError("wall_clock_at_zero braucht eine Zeitzone (aware datetime)")
    track = _Track(distance_track)
    fit = _fit_tool()

    start_wall_ms = round(wall_clock_at_zero.timestamp() * 1000) + start_t_ms
    start_wall_ms -= start_wall_ms % 1000  # ganze Sekunde, siehe Moduldoku „Wanduhr“

    def wall_ms(t_ms: int) -> int:
        return start_wall_ms + t_ms - start_t_ms

    start_cm = track.centimetres(start_t_ms)

    def distance_cm(t_ms: int) -> int | None:
        cm = track.centimetres(t_ms)
        return None if cm is None else cm - start_cm

    points = _points(start_t_ms, end_t_ms, samples, track, distance_cm)
    bounds = [start_t_ms, *sorted({t for t in lap_end_t_ms if start_t_ms < t < end_t_ms}), end_t_ms]
    full_laps = len({t for t in lap_end_t_ms if start_t_ms < t <= end_t_ms})

    types = fit.types
    builder = fit.FitFileBuilder(auto_define=True)

    file_id = fit.FileIdMessage(local_id=_LOCAL_ID["file_id"])
    file_id.type = types.FileType.ACTIVITY
    file_id.manufacturer = types.Manufacturer.DEVELOPMENT.value
    file_id.product = PRODUCT_ID
    file_id.serial_number = serial_number(ride_id)
    file_id.time_created = wall_ms(start_t_ms)
    builder.add(file_id)

    device = fit.DeviceInfoMessage(local_id=_LOCAL_ID["device_info"])
    device.timestamp = wall_ms(start_t_ms)
    device.device_index = 0  # das erzeugende Gerät
    device.manufacturer = types.Manufacturer.DEVELOPMENT.value
    device.product = PRODUCT_ID
    device.product_name = PRODUCT_NAME
    device.serial_number = file_id.serial_number
    builder.add(device)

    builder.add(_event(fit, wall_ms(start_t_ms), types.EventType.START))
    for point in points:
        record = fit.RecordMessage(local_id=_LOCAL_ID["record"])
        record.timestamp = wall_ms(point.t_ms)
        if point.distance_cm is not None:
            record.distance = point.distance_cm / 100
            record.speed = point.speed
        if point.power is not None:
            record.power = point.power
        if point.cadence is not None:
            record.cadence = point.cadence
        if point.hr is not None:
            record.heart_rate = point.hr
        builder.add(record)
    builder.add(_event(fit, wall_ms(end_t_ms), types.EventType.STOP_ALL))

    for index, (lap_start, lap_end) in enumerate(zip(bounds, bounds[1:])):
        last = index == len(bounds) - 2
        lap_points = [p for p in points if lap_start <= p.t_ms < lap_end or (last and p.t_ms == lap_end)]
        lap = fit.LapMessage(local_id=_LOCAL_ID["lap"])
        lap.message_index = index
        lap.event = types.Event.LAP
        lap.event_type = types.EventType.STOP
        lap.lap_trigger = types.LapTrigger.POSITION_LAP if index < full_laps else types.LapTrigger.SESSION_END
        _summary(lap, fit, lap_start, lap_end, lap_points, distance_cm, wall_ms)
        builder.add(lap)

    session = fit.SessionMessage(local_id=_LOCAL_ID["session"])
    session.message_index = 0
    session.event = types.Event.SESSION
    session.event_type = types.EventType.STOP
    session.trigger = types.SessionTrigger.ACTIVITY_END
    session.first_lap_index = 0
    session.num_laps = len(bounds) - 1
    _summary(session, fit, start_t_ms, end_t_ms, points, distance_cm, wall_ms)
    builder.add(session)

    activity = fit.ActivityMessage(local_id=_LOCAL_ID["activity"])
    activity.timestamp = wall_ms(end_t_ms)
    activity.total_timer_time = (end_t_ms - start_t_ms) / 1000
    activity.num_sessions = 1
    activity.type = types.Activity.MANUAL
    activity.event = types.Event.ACTIVITY
    activity.event_type = types.EventType.STOP
    # local_date_time: rohe FIT-Sekunden in Ortszeit (fit-tool rechnet nur date_time-Felder um)
    activity.local_timestamp = round(wall_ms(end_t_ms) / 1000 + offset.total_seconds()) - _FIT_EPOCH_S
    builder.add(activity)

    return builder.build().to_bytes()


def serial_number(ride_id: str) -> int:
    """Stabile `serial_number` (uint32z, nie 0) einer Fahrt, abgeleitet aus ihrer `ride_id`."""
    value = int.from_bytes(hashlib.sha256(ride_id.encode("utf-8")).digest()[:4], "big")
    return value or 1


@dataclass(frozen=True, slots=True)
class _Point:
    """Werte eines Records. Strecke in ganzen cm (Auflösung von FIT), damit Laps exakt aufgehen."""

    t_ms: int
    distance_cm: int | None
    speed: float | None
    power: int | None
    cadence: int | None
    hr: int | None


def _points(start_t_ms, end_t_ms, samples, track, distance_cm) -> list[_Point]:
    times = range(start_t_ms, end_t_ms + 1, RECORD_INTERVAL_MS)
    inside = [s for s in samples if start_t_ms <= s.t_ms <= end_t_ms]
    sample_times = [s.t_ms for s in inside]
    points = []
    for t_ms in times:
        i = bisect_right(sample_times, t_ms) - 1
        sample = inside[i] if i >= 0 and inside[i].t_ms > t_ms - RECORD_INTERVAL_MS else None
        measured = sample is not None and sample.power_w is not None and sample.power_estimated is False
        points.append(
            _Point(
                t_ms=t_ms,
                distance_cm=distance_cm(t_ms),
                speed=track.speed(t_ms),
                power=round(sample.power_w) if measured else None,
                cadence=None if sample is None or sample.cadence is None else round(sample.cadence),
                hr=None if sample is None else sample.hr_bpm,
            )
        )
    return points


def _summary(message, fit, start_t_ms, end_t_ms, points, distance_cm, wall_ms) -> None:
    """Gemeinsame Felder von Lap und Session; Mittel und Maxima nur aus vorhandenen Record-Werten."""
    message.timestamp = wall_ms(end_t_ms)
    message.start_time = wall_ms(start_t_ms)
    message.sport = fit.types.Sport.CYCLING
    message.sub_sport = fit.types.SubSport.VIRTUAL_ACTIVITY
    elapsed_s = (end_t_ms - start_t_ms) / 1000
    message.total_elapsed_time = elapsed_s
    message.total_timer_time = elapsed_s
    start_cm, end_cm = distance_cm(start_t_ms), distance_cm(end_t_ms)
    if start_cm is not None:
        message.total_distance = (end_cm - start_cm) / 100
        message.avg_speed = (end_cm - start_cm) / 100 / elapsed_s
        if points:  # ein Rest-Lap unter 1 s kann ohne Record sein
            message.max_speed = max(p.speed for p in points)
    for name in ("power", "cadence", "hr"):
        values = [getattr(p, name) for p in points if getattr(p, name) is not None]
        if values:
            field = "heart_rate" if name == "hr" else name
            setattr(message, f"avg_{field}", round(sum(values) / len(values)))
            setattr(message, f"max_{field}", max(values))


def _event(fit, timestamp_ms: int, event_type):
    event = fit.EventMessage(local_id=_LOCAL_ID["event"])
    event.timestamp = timestamp_ms
    event.event = fit.types.Event.TIMER
    event.event_type = event_type
    return event


class _Track:
    """Streckenspur des Spiels: stückweise linear zwischen den Punkten, davor und danach konstant."""

    def __init__(self, points: Sequence[tuple[int, float]]) -> None:
        self._t = [int(t) for t, _ in points]
        self._d = [float(d) for _, d in points]
        for i in range(1, len(self._t)):
            if self._t[i] <= self._t[i - 1]:
                raise ValueError(f"Streckenspur: t_ms nicht streng steigend bei Punkt {i}")
            if self._d[i] < self._d[i - 1]:
                raise ValueError(f"Streckenspur: Strecke fällt bei Punkt {i}")

    def centimetres(self, t_ms: int) -> int | None:
        if not self._t:
            return None
        i = bisect_right(self._t, t_ms) - 1
        if i < 0:
            metres = self._d[0]
        elif i == len(self._t) - 1:
            metres = self._d[-1]
        else:
            share = (t_ms - self._t[i]) / (self._t[i + 1] - self._t[i])
            metres = self._d[i] + share * (self._d[i + 1] - self._d[i])
        return round(metres * 100)

    def speed(self, t_ms: int) -> float | None:
        """m/s im Abschnitt [t_i, t_i+1), in dem `t_ms` liegt; außerhalb der Spur 0."""
        if not self._t:
            return None
        i = bisect_right(self._t, t_ms) - 1
        if i < 0 or i == len(self._t) - 1:
            return 0.0
        return (self._d[i + 1] - self._d[i]) / ((self._t[i + 1] - self._t[i]) / 1000)


def _fit_tool() -> SimpleNamespace:
    """Lädt fit-tool erst beim Export (optionales Extra `fit`)."""
    try:
        from fit_tool.fit_file_builder import FitFileBuilder
        from fit_tool.profile import profile_type
        from fit_tool.profile.messages.activity_message import ActivityMessage
        from fit_tool.profile.messages.device_info_message import DeviceInfoMessage
        from fit_tool.profile.messages.event_message import EventMessage
        from fit_tool.profile.messages.file_id_message import FileIdMessage
        from fit_tool.profile.messages.lap_message import LapMessage
        from fit_tool.profile.messages.record_message import RecordMessage
        from fit_tool.profile.messages.session_message import SessionMessage
    except ImportError as error:
        raise FitToolMissingError() from error
    return SimpleNamespace(
        FitFileBuilder=FitFileBuilder,
        types=profile_type,
        ActivityMessage=ActivityMessage,
        DeviceInfoMessage=DeviceInfoMessage,
        EventMessage=EventMessage,
        FileIdMessage=FileIdMessage,
        LapMessage=LapMessage,
        RecordMessage=RecordMessage,
        SessionMessage=SessionMessage,
    )
