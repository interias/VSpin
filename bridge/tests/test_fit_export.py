"""FIT-Export einer Fahrt (Spec #84): Session-CSV + Angaben des Spiels → `.fit`, mit fit-tool zurückdekodiert.

Die Fixture-CSV schreibt der echte Session-Logger (`SessionCsv`) unter `tmp_path`; die FIT-Bytes landen nur dort.
"""

import importlib
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from fit_tool.data_message import DataMessage
from fit_tool.fit_file import FitFile
from fit_tool.profile.profile_type import EventType, FileType, LapTrigger, Manufacturer, Sport, SubSport
from vspin_bridge.export import RideSample, build_ride_fit, read_session_samples
from vspin_bridge.session.csv_log import SessionCsv
from vspin_bridge.sources.base import TelemetrySample

# Wanduhr bei t_ms = 0 mit Bruchteil einer Sekunde – der Start der Fahrt rückt auf die ganze Sekunde davor.
ZERO = datetime(2026, 10, 28, 7, 0, 0, 250_000, tzinfo=timezone(timedelta(hours=1)))


def write_csv(path: Path, samples: list[TelemetrySample]) -> Path:
    with open(path, "x", encoding="utf-8", newline="") as stream:
        log = SessionCsv(path, stream)
        for sample in samples:
            log.write(sample, cadence_raw=sample.cadence, grade=None, status="connected")
        log.close()
    return path


def ride_samples(start: int, end: int, step: int = 250, **values) -> list[TelemetrySample]:
    return [TelemetrySample(t_ms=t, **values) for t in range(start, end + 1, step)]


def track(start: int, end: int, speed_m_s: float = 8.0) -> list[tuple[int, float]]:
    """Streckenspur mit 1 Hz und fester Geschwindigkeit, Strecke 0 am Start."""
    return [(t, (t - start) / 1000 * speed_m_s) for t in range(start, end + 1, 1000)]


def build(samples, start=10_000, end=70_000, **kwargs) -> bytes:
    args = dict(
        ride_id="ride-1",
        start_t_ms=start,
        end_t_ms=end,
        wall_clock_at_zero=ZERO,
        samples=samples,
        distance_track=track(start, end),
    )
    args.update(kwargs)
    return build_ride_fit(**args)


def measured(start=10_000, end=70_000, **values) -> list[RideSample]:
    defaults = dict(cadence=85.0, power_w=180.0, power_estimated=False, hr_bpm=130)
    defaults.update(values)
    return [RideSample(t_ms=t, **defaults) for t in range(start, end + 1, 250)]


def decode(data: bytes, tmp_path: Path) -> list[DataMessage]:
    path = tmp_path / "ride.fit"
    path.write_bytes(data)
    return [r.message for r in FitFile.from_file(str(path)).records if isinstance(r.message, DataMessage)]


def of(messages, name: str) -> list[DataMessage]:
    return [m for m in messages if m.name == name]


def test_required_messages_are_present_in_cookbook_order(tmp_path):
    messages = decode(build(measured(), lap_end_t_ms=[40_000]), tmp_path)
    names = [m.name for m in messages]
    assert names[:3] == ["file_id", "device_info", "event"]
    assert names[-3:] == ["lap", "session", "activity"]
    assert {"record", "lap"} <= set(names)
    start, stop = of(messages, "event")
    assert (start.event_type, stop.event_type) == (EventType.START.value, EventType.STOP_ALL.value)
    assert start.timestamp <= of(messages, "record")[0].timestamp
    assert stop.timestamp >= of(messages, "record")[-1].timestamp
    [activity] = of(messages, "activity")
    assert activity.num_sessions == 1


@pytest.mark.parametrize("hours", [1, 2])  # MEZ, MESZ
def test_activity_local_timestamp_is_local_time(tmp_path, hours):
    zero = ZERO.replace(tzinfo=timezone(timedelta(hours=hours)))
    [activity] = of(decode(build(measured(), wall_clock_at_zero=zero), tmp_path), "activity")
    fit_epoch_s = 631065600  # 1989-12-31 00:00:00 UTC; local_timestamp sind rohe FIT-Sekunden
    assert activity.local_timestamp + fit_epoch_s - activity.timestamp // 1000 == hours * 3600


def test_virtual_ride_from_development_manufacturer_not_garmin(tmp_path):
    messages = decode(build(measured()), tmp_path)
    [file_id], [device], [session] = of(messages, "file_id"), of(messages, "device_info"), of(messages, "session")
    assert file_id.type == FileType.ACTIVITY.value
    assert file_id.manufacturer == device.manufacturer == Manufacturer.DEVELOPMENT.value == 255
    assert Manufacturer.GARMIN.value not in (file_id.manufacturer, device.manufacturer)  # kein Spoofing
    assert SubSport.VIRTUAL_ACTIVITY.value == 58  # Profilwert von fit-tool (Further Notes der Spec)
    for summary in [session, *of(messages, "lap")]:
        assert (summary.sport, summary.sub_sport) == (Sport.CYCLING.value, SubSport.VIRTUAL_ACTIVITY.value)
    # Kein Ort: Fahrt auf einer virtuellen Insel.
    assert all(r.position_lat is None and r.position_long is None for r in of(messages, "record"))


def test_laps_add_up_to_the_session(tmp_path):
    # Zwei volle Runden, dann Abbruch: der Rest wird ein letzter Lap. Krumme Zeiten und Strecken.
    start, end = 10_123, 75_877
    spur = [(start, 0.0), (30_000, 151.37), (52_345, 333.333), (end, 512.009)]
    messages = decode(build(measured(start, end), start, end, distance_track=spur, lap_end_t_ms=[52_345, 30_000]), tmp_path)
    laps, [session] = of(messages, "lap"), of(messages, "session")
    assert [lap.message_index for lap in laps] == [0, 1, 2]
    assert [lap.lap_trigger for lap in laps] == [LapTrigger.POSITION_LAP.value] * 2 + [LapTrigger.SESSION_END.value]
    assert session.num_laps == 3
    assert [lap.total_elapsed_time for lap in laps] == [19.877, 22.345, 23.532]
    assert sum(lap.total_elapsed_time for lap in laps) == pytest.approx(session.total_elapsed_time, abs=1e-9)
    assert session.total_elapsed_time == session.total_timer_time == (end - start) / 1000
    assert [lap.total_distance for lap in laps] == [151.37, 181.96, 178.68]
    assert round(sum(lap.total_distance for lap in laps) * 100) == round(session.total_distance * 100) == 51201
    # Lückenlos: jeder Lap beginnt, wo der vorige endet; der erste beim Start, der letzte am Ende der Session.
    assert laps[0].start_time == session.start_time
    for previous, lap in zip(laps, laps[1:]):
        assert lap.start_time == previous.timestamp
    assert laps[-1].timestamp == session.timestamp


def test_ride_without_full_lap_has_one_lap_over_the_whole_ride(tmp_path):
    messages = decode(build(measured(), lap_end_t_ms=[]), tmp_path)
    [lap], [session] = of(messages, "lap"), of(messages, "session")
    assert lap.lap_trigger == LapTrigger.SESSION_END.value
    assert (lap.start_time, lap.timestamp) == (session.start_time, session.timestamp)
    assert lap.total_elapsed_time == session.total_elapsed_time == 60.0
    assert lap.total_distance == session.total_distance == 480.0


def test_ride_ending_with_a_full_lap_has_no_rest_lap(tmp_path):
    # Rundenende genau am Ende der Fahrt; Grenzen außerhalb der Fahrt zählen nicht.
    messages = decode(build(measured(), lap_end_t_ms=[5_000, 40_000, 70_000, 90_000]), tmp_path)
    laps = of(messages, "lap")
    assert [lap.lap_trigger for lap in laps] == [LapTrigger.POSITION_LAP.value] * 2
    assert [lap.total_elapsed_time for lap in laps] == [30.0, 30.0]


def test_short_rest_lap_without_record_is_still_a_lap(tmp_path):
    # Abbruch 0,3 s nach dem Rundenende: der Rest-Lap enthält keinen Record (Raster 1 s ab Start).
    spur = track(10_000, 70_000) + [(70_400, 483.2)]  # 8 m/s bis zum Ende
    messages = decode(build(measured(10_000, 70_400), 10_000, 70_400, distance_track=spur, lap_end_t_ms=[70_100]), tmp_path)
    full, rest = of(messages, "lap")
    assert (full.total_elapsed_time, rest.total_elapsed_time) == (60.1, 0.3)
    assert rest.total_distance == pytest.approx(2.4) and rest.max_speed is None
    [session] = of(messages, "session")
    assert session.total_distance == pytest.approx(full.total_distance + rest.total_distance)


def test_time_window_cuts_the_session_csv(tmp_path):
    # Session läuft länger als die Fahrt: davor eine Pause mit anderen Werten, danach Auslaufen.
    csv_path = write_csv(
        tmp_path / "session.csv",
        ride_samples(0, 9_750, cadence=40.0, power_w=90.0, power_estimated=False, heart_rate=95)
        + ride_samples(10_000, 70_000, cadence=85.0, power_w=180.0, power_estimated=False, heart_rate=130)
        + ride_samples(70_250, 90_000, cadence=30.0, power_w=60.0, power_estimated=False, heart_rate=110),
    )
    samples = read_session_samples(csv_path, 10_000, 70_000)
    assert (samples[0].t_ms, samples[-1].t_ms) == (10_000, 70_000)  # beide Grenzen inklusiv
    assert len(samples) == 241
    assert {(s.cadence, s.power_w, s.power_estimated, s.hr_bpm) for s in samples} == {(85.0, 180.0, False, 130)}
    assert read_session_samples(csv_path, 10_001, 69_999)[0].t_ms == 10_250  # Gegenprobe: exklusiv fällt weg

    messages = decode(build(samples), tmp_path)
    records = of(messages, "record")
    assert len(records) == 61  # 1 Record je Sekunde, Start bis einschließlich Ende
    assert {(r.cadence, r.power, r.heart_rate) for r in records} == {(85, 180, 130)}
    start_wall_ms = int(ZERO.timestamp() * 1000) + 10_000 - 250  # ganze Sekunde vor dem Start
    assert [r.timestamp for r in records] == [start_wall_ms + k * 1000 for k in range(61)]
    [file_id] = of(messages, "file_id")
    assert file_id.time_created == start_wall_ms


def test_estimated_watts_are_left_out(tmp_path):
    csv_path = write_csv(tmp_path / "session.csv", ride_samples(10_000, 70_000, cadence=85.0, power_w=142.0, power_estimated=True, heart_rate=130))
    messages = decode(build(read_session_samples(csv_path, 10_000, 70_000)), tmp_path)
    assert all(r.power is None for r in of(messages, "record"))
    assert of(messages, "record")[0].cadence == 85  # nur die Leistung fehlt
    for summary in of(messages, "lap") + of(messages, "session"):
        assert summary.avg_power is None and summary.max_power is None


def test_measured_watts_are_exported(tmp_path):
    csv_path = write_csv(tmp_path / "session.csv", ride_samples(10_000, 70_000, cadence=85.0, power_w=142.0, power_estimated=False))
    messages = decode(build(read_session_samples(csv_path, 10_000, 70_000)), tmp_path)
    assert {r.power for r in of(messages, "record")} == {142}
    [session] = of(messages, "session")
    assert (session.avg_power, session.max_power) == (142, 142)


def test_lap_and_session_averages_contain_no_estimated_watts(tmp_path):
    # Erste Hälfte gemessen 200 W, zweite Hälfte geschätzt 400 W (z. B. Leistungsmesser abgerissen).
    samples = measured(10_000, 39_750, power_w=200.0) + measured(40_000, 70_000, power_w=400.0, power_estimated=True)
    messages = decode(build(samples, lap_end_t_ms=[40_000]), tmp_path)
    first, second = of(messages, "lap")
    [session] = of(messages, "session")
    assert (first.avg_power, first.max_power) == (200, 200)
    assert second.avg_power is None and second.max_power is None
    assert (session.avg_power, session.max_power) == (200, 200)


def test_power_without_origin_counts_as_not_measured(tmp_path):
    messages = decode(build(measured(power_estimated=None)), tmp_path)
    assert all(r.power is None for r in of(messages, "record"))


def test_heart_rate_gaps_stay_empty(tmp_path):
    # Puls fällt von 20 s bis einschließlich 35 s weg (Gurt verloren) – kein Übertrag, keine Null.
    samples = [
        TelemetrySample(t_ms=t, cadence=85.0, heart_rate=None if 20_000 <= t <= 35_000 else 140)
        for t in range(10_000, 70_001, 250)
    ]
    csv_path = write_csv(tmp_path / "session.csv", samples)
    messages = decode(build(read_session_samples(csv_path, 10_000, 70_000)), tmp_path)
    by_second = {(r.timestamp - of(messages, "record")[0].timestamp) // 1000: r for r in of(messages, "record")}
    gap = [k for k, r in by_second.items() if r.heart_rate is None]
    assert gap == list(range(10, 26))  # Records 20 s … 35 s nach t_ms = 0, also Sekunde 10 … 25 der Fahrt
    assert {r.heart_rate for k, r in by_second.items() if k not in gap} == {140}
    assert all(r.cadence == 85 for r in by_second.values())  # nur der Puls fehlt
    [session] = of(messages, "session")
    assert (session.avg_heart_rate, session.max_heart_rate) == (140, 140)


def test_record_without_a_sample_in_its_second_has_no_values(tmp_path):
    # Session-CSV setzt 5 s aus (z. B. Bridge hing): die Records dort tragen nur Zeit und Strecke.
    samples = measured(10_000, 30_000) + measured(35_250, 70_000)
    records = of(decode(build(samples), tmp_path), "record")
    empty = [i for i, r in enumerate(records) if r.cadence is None]
    assert empty == [21, 22, 23, 24, 25]  # 31 s … 35 s: kein Sample in (T − 1 s, T]
    assert all(records[i].power is None and records[i].heart_rate is None for i in empty)
    assert all(records[i].distance is not None for i in empty)


def test_distance_follows_the_track(tmp_path):
    # Spur mit wechselnder Geschwindigkeit, nicht auf dem Record-Raster, beginnt nicht bei 0.
    spur = [(9_500, 1000.0), (12_500, 1015.0), (14_000, 1030.0), (20_000, 1030.0), (24_000, 1070.0)]
    messages = decode(build(measured(10_000, 26_000), 10_000, 26_000, distance_track=spur), tmp_path)
    records = of(messages, "record")
    # Am Start (10 s) steht die Spur bei 1002,5 m – das ist Strecke 0 der Fahrt.
    assert [r.distance for r in records] == [
        0.0, 5.0, 10.0, 17.5, 27.5, 27.5, 27.5, 27.5, 27.5, 27.5, 27.5, 37.5, 47.5, 57.5, 67.5, 67.5, 67.5
    ]  # fmt: skip
    # Geschwindigkeit = Steigung des Spurabschnitts, nach dem letzten Spurpunkt 0.
    assert [r.speed for r in records] == [
        5.0, 5.0, 5.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 10.0, 0.0, 0.0, 0.0
    ]  # fmt: skip
    [session] = of(messages, "session")
    assert session.total_distance == 67.5
    assert session.max_speed == 10.0
    assert session.avg_speed == pytest.approx(67.5 / 16, abs=1e-3)  # FIT: mm/s


def test_same_ride_gives_the_same_file_and_rides_differ(tmp_path):
    first = build(measured(), lap_end_t_ms=[40_000])
    assert build(measured(), lap_end_t_ms=[40_000]) == first  # erneutes Speichern: dieselbe Datei
    other = decode(build(measured(), ride_id="ride-2"), tmp_path)
    [file_id] = of(decode(first, tmp_path), "file_id")
    [other_id] = of(other, "file_id")
    assert file_id.serial_number != other_id.serial_number
    assert file_id.serial_number not in (None, 0)


def test_invalid_inputs_are_rejected():
    with pytest.raises(ValueError, match="Zeitzone"):
        build(measured(), wall_clock_at_zero=ZERO.replace(tzinfo=None))
    with pytest.raises(ValueError, match="Dauer"):
        build(measured(), start=70_000, end=70_000)
    with pytest.raises(ValueError, match="Streckenspur"):
        build(measured(), distance_track=[(10_000, 5.0), (11_000, 4.0)])


def test_missing_fit_tool_gives_a_clear_error(monkeypatch):
    # fit-tool ausblenden, als wäre das Extra nicht installiert: Import der Bridge-Module geht trotzdem.
    for name in [n for n in sys.modules if n == "fit_tool" or n.startswith("fit_tool.")]:
        monkeypatch.setitem(sys.modules, name, None)
    monkeypatch.setitem(sys.modules, "fit_tool", None)
    for name in [n for n in sys.modules if n.startswith("vspin_bridge.export")]:
        monkeypatch.delitem(sys.modules, name)
    export = importlib.import_module("vspin_bridge.export")  # lazy: kein Absturz beim Import

    samples = [export.RideSample(t_ms=t, cadence=85.0) for t in range(0, 5_001, 1000)]
    with pytest.raises(export.FitToolMissingError) as error:
        export.build_ride_fit(
            ride_id="ride-1", start_t_ms=0, end_t_ms=5_000, wall_clock_at_zero=ZERO, samples=samples, distance_track=[]
        )
    assert "fit-tool fehlt" in str(error.value) and ".[fit]" in str(error.value)
    assert isinstance(error.value, RuntimeError) and isinstance(error.value.__cause__, ImportError)
