"""Bridge mit Pulsquelle im Testprozess (Spec #64): `InProcessBridge` mit dem BLE-Fake (`fake_ble.py`) und
kurzen Zeiten, dazu ein Leser für den Bus, der alle Nachrichten mitschreibt.

Alles, was den Fake skriptet (`appear`, `notify`, `drop` …), läuft über `bridge.call` im Event-Loop der Bridge.
"""

import json
import time
from collections.abc import Callable, Iterator

import pytest
from bridge_harness import HOST, InProcessBridge, receive_json
from fake_ble import FakeBleAdapter
from vspin_bridge.sources.heart_rate import HeartRateDevice, HeartRateSource, Role
from vspin_bridge.sources.sim import SimulatorSource
from websockets.sync.client import ClientConnection

STRAP = HeartRateDevice("AA:00:00:00:00:01", "HRM-Pro", Role.STRAP)
WATCH = HeartRateDevice("AA:00:00:00:00:02", "Forerunner 970", Role.WATCH)

WHEEL_PART = {"state": "connected", "source": "sim", "capabilities": ["CADENCE"]}  # Simulator, unverändert
OFF = {"state": "off", "device": None}
DISCONNECTED = {"state": "disconnected", "device": None}


def pulse(bpm: int) -> bytes:
    """Heart Rate Measurement `0x2A37`: Flags 0 (uint8-Puls), dann der Puls."""
    return bytes([0x00, bpm])


def device_json(device: HeartRateDevice) -> dict:
    return {"address": device.address, "name": device.name, "role": str(device.role)}


def block(state: str, device: HeartRateDevice) -> dict:
    return {"state": state, "device": device_json(device)}


def set_devices(*devices: HeartRateDevice) -> dict:
    return {"v": 0, "type": "set_heart_rate_devices", "devices": [device_json(d) for d in devices]}


def ack(for_type: str) -> dict:
    return {"v": 0, "type": "ack", "for": for_type, "ok": True, "reason": None}


class HeartRateRig:
    """Fabrik der Pulsquelle für die Bridge (`HeartRateFactory`) samt BLE-Fake; hält die gebaute Quelle."""

    def __init__(self, stale_s: float = 3.0, retry_s: float = 0.05) -> None:
        self.adapter = FakeBleAdapter()
        self.stale_s = stale_s
        self.retry_s = retry_s
        self.source: HeartRateSource | None = None

    def factory(self, on_status, on_raw) -> HeartRateSource:
        self.source = HeartRateSource(self.adapter, on_status, on_raw, stale_s=self.stale_s, retry_s=self.retry_s)
        return self.source


@pytest.fixture
def pulse_bridge(request, tmp_path) -> Iterator[Callable]:
    """Fabrik: `pulse_bridge(source=None, sessions_dir=None, stale_s=…, retry_s=…)` startet eine Bridge im
    Testprozess (Standard: Simulator mit 80 rpm) mit Pulsquelle auf dem BLE-Fake; liefert `(bridge, rig)`."""
    started: list[InProcessBridge] = []

    def start(source=None, sessions_dir=None, **times: float) -> tuple[InProcessBridge, HeartRateRig]:
        rig = HeartRateRig(**times)
        host = getattr(request.node, "bus_host", HOST)
        bridge = InProcessBridge(
            source or SimulatorSource(cadence=80), sessions_dir or tmp_path / "sessions", host, rig.factory
        )
        started.append(bridge)
        bridge.start()
        return bridge, rig

    yield start
    for bridge in started:
        bridge.stop()


class BusReader:
    """Test-Client, der jede empfangene Nachricht in `seen` mitschreibt."""

    def __init__(self, client: ClientConnection) -> None:
        self.client = client
        self.seen: list[dict] = []
        self.first = self._receive(5.0)
        assert self.first["type"] == "status", self.first

    def _receive(self, timeout_s: float) -> dict:
        message = receive_json(self.client, timeout_s=timeout_s)
        self.seen.append(message)
        return message

    def next(self, kind: str, where: Callable[[dict], bool] = lambda m: True, timeout_s: float = 5.0) -> dict:
        """Nächste Nachricht vom Typ `kind`, die `where` erfüllt; alles dazwischen landet nur in `seen`."""
        deadline = time.monotonic() + timeout_s
        while True:
            remaining = deadline - time.monotonic()
            assert remaining > 0, f"keine {kind}-Nachricht in {timeout_s} s; zuletzt: {self.seen[-5:]}"
            message = self._receive(remaining)
            if message["type"] == kind and where(message):
                return message

    def reply(self, payload) -> dict:
        """Sendet `payload` und liefert die Antwort (`ack`/`error`)."""
        self.client.send(payload if isinstance(payload, (str, bytes)) else json.dumps(payload))
        return self._answer()

    def _answer(self) -> dict:
        deadline = time.monotonic() + 5.0
        while True:
            message = self._receive(max(deadline - time.monotonic(), 0.01))
            if message["type"] in ("ack", "error"):
                return message

    def drain(self, duration_s: float) -> list[dict]:
        """Alles, was in `duration_s` ankommt (auch schon Gepuffertes)."""
        received = []
        deadline = time.monotonic() + duration_s
        while (remaining := deadline - time.monotonic()) > 0:
            try:
                received.append(self._receive(remaining))
            except TimeoutError:
                break
        return received

    def statuses(self) -> list[dict]:
        return [m for m in self.seen if m["type"] == "status"]


def heart_rate_blocks(messages: list[dict]) -> list[dict]:
    return [m["heart_rate"] for m in messages if m["type"] == "status"]
