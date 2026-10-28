"""Puls in der Session (Spec #64, ADR-0008): `hr_bpm` in der CSV ist der Wert von `telemetry.heart_rate`, jede rohe
Notification der Pulsquelle steht in der Rohdatei. Bridge im Testprozess mit dem BLE-Fake."""

import csv
import errno
import json

from bridge_harness import read_jsonl
from heart_rate_harness import STRAP, BusReader, pulse, pulse_bridge, set_devices  # noqa: F401 – Fixture
from vspin_bridge.parsers import HEART_RATE_MEASUREMENT
from vspin_bridge.session import files as session_files


def strap_connected(bridge, rig, client: BusReader) -> None:
    assert client.reply(set_devices(STRAP))["type"] == "ack"
    bridge.call(rig.adapter.appear, STRAP.address, STRAP.name)
    client.next("status", lambda m: m["heart_rate"]["state"] == "connected")


def test_csv_hr_bpm_matches_the_bus_and_raw_file_has_the_notifications(pulse_bridge, bus_client, tmp_path, isolated_bus):
    out = tmp_path / "out"
    bridge, rig = pulse_bridge(sessions_dir=out)
    client = BusReader(bus_client())
    strap_connected(bridge, rig, client)
    sent = [pulse(70), pulse(71), bytes([0x01]), pulse(72)]  # 0x01: uint16-Puls angekündigt, fehlt – kaputt
    for data in sent:
        bridge.call(rig.adapter.notify, STRAP.address, data)
        client.next("telemetry")
    client.next("telemetry", lambda m: m["heart_rate"] == 72)
    client.drain(0.3)
    assert bridge.stop() is None

    [csv_path] = out.glob("*.csv")
    with open(csv_path, encoding="utf-8", newline="") as stream:
        rows = {int(row["t_ms"]): row["hr_bpm"] for row in csv.DictReader(stream)}
    telemetry = [m for m in client.seen if m["type"] == "telemetry"]
    for message in telemetry:  # dieselbe Zeile, derselbe Wert wie am Bus
        assert rows[message["t_ms"]] == ("" if message["heart_rate"] is None else repr(message["heart_rate"]))
    assert {"", "70", "71", "72"} >= {rows[m["t_ms"]] for m in telemetry} >= {"70", "71", "72"}

    [raw_path] = out.glob("*.raw.jsonl")
    lines = read_jsonl(raw_path)  # Simulator: nur die Notifications der Pulsquelle
    assert [line["hex"] for line in lines] == [data.hex() for data in sent]  # auch die kaputte
    assert {line["char"] for line in lines} == {HEART_RATE_MEASUREMENT}
    first = raw_path.read_text(encoding="utf-8").splitlines()[0]
    assert first == json.dumps({"t_ms": lines[0]["t_ms"], "char": HEART_RATE_MEASUREMENT, "hex": "0046"})


class RawDiskFull:
    """Rohdatei-Stream, der beim ersten Schreiben mit „Platte voll“ scheitert."""

    def __init__(self, stream) -> None:
        self._stream = stream

    def write(self, text: str) -> int:
        raise OSError(errno.ENOSPC, "No space left on device")

    def flush(self) -> None:
        self._stream.flush()

    def close(self) -> None:
        self._stream.close()

    @property
    def closed(self) -> bool:
        return self._stream.closed


def test_write_error_on_pulse_raw_data_ends_logging_but_not_the_bridge(
    pulse_bridge, bus_client, tmp_path, monkeypatch, isolated_bus
):
    real_open = open

    def open_with_full_disk(path, *args, **kwargs):
        stream = real_open(path, *args, **kwargs)
        return RawDiskFull(stream) if str(path).endswith(".raw.jsonl") else stream

    monkeypatch.setattr(session_files, "open", open_with_full_disk, raising=False)
    bridge, rig = pulse_bridge(sessions_dir=tmp_path / "out")
    client = BusReader(bus_client())
    strap_connected(bridge, rig, client)
    for bpm in (90, 91):
        bridge.call(rig.adapter.notify, STRAP.address, pulse(bpm))
        client.next("telemetry", lambda m, bpm=bpm: m["heart_rate"] == bpm)  # Puls und Fahrt laufen weiter

    assert bridge.stop() is None
    log = bridge.log()
    assert log.count("Session-Logging beendet") == 1, log
    assert "No space left on device" in log and "Bridge läuft weiter" in log
