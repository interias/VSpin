"""Fixtures nach dem Bridge-Testmuster (siehe bridge_harness.py)."""

from collections.abc import Iterator
from contextlib import ExitStack

import pytest
from bridge_harness import BUS_URL, HOST, ISOLATED_HOST, PORT, BridgeProcess, InProcessBridge, port_lock
from websockets.sync.client import ClientConnection, connect


@pytest.fixture(scope="session", autouse=True)
def _exclusive_bus_port() -> Iterator[None]:
    """Ein Bridge-Testlauf zur Zeit pro Rechner (fester Port 8765, siehe `port_lock`)."""
    with port_lock():
        yield


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(item, call):
    """Schlägt ein Test fehl, hängt das Log jeder gestarteten Bridge an den Bericht."""
    report = yield
    if report.failed:
        for i, bridge in enumerate(getattr(item, "bridge_processes", [])):
            report.sections.append((f"Bridge-Log {i} ({report.when})", bridge.log()))
    return report


@pytest.fixture
def isolated_bus(request) -> str:
    """Der Test prüft Kadenzwerte oder Startreihenfolgen am Bus und darf dabei keinen fremden Client sehen
    (ein laufendes Spiel am Standard-Bus 127.0.0.1:8765 sendet `set_grade` an jede Bridge dort): `bridge_process`
    und `bus_client` nehmen dann die eigene Loopback-Adresse (`ISOLATED_HOST`)."""
    request.node.bus_host = ISOLATED_HOST
    return ISOLATED_HOST


@pytest.fixture
def bridge_process(request, tmp_path) -> Iterator:
    """Fabrik: `bridge_process("--source", "sim", ...)` startet eine Bridge; Stopp nach dem Test."""
    started: list[BridgeProcess] = []
    request.node.bridge_processes = started

    def start(*args: str) -> BridgeProcess:
        host = getattr(request.node, "bus_host", HOST)
        bridge = BridgeProcess(list(args), tmp_path / f"bridge-{len(started)}.log", host)
        started.append(bridge)
        bridge.start()
        return bridge

    yield start
    for bridge in started:
        bridge.stop()


@pytest.fixture
def in_process_bridge(request, tmp_path) -> Iterator:
    """Fabrik: `in_process_bridge(source)` startet die Bridge im Testprozess (`InProcessBridge`);
    Stopp nach dem Test."""
    started: list[InProcessBridge] = []

    def start(source, sessions_dir=None) -> InProcessBridge:
        bridge = InProcessBridge(source, sessions_dir or tmp_path / "sessions", getattr(request.node, "bus_host", HOST))
        started.append(bridge)
        bridge.start()
        return bridge

    yield start
    for bridge in started:
        bridge.stop()


@pytest.fixture
def bus_client(request) -> Iterator:
    """Fabrik für Test-Clients am Bus; alle werden nach dem Test geschlossen."""
    with ExitStack() as stack:

        def open_client() -> ClientConnection:
            host = getattr(request.node, "bus_host", HOST)
            url = BUS_URL if host == HOST else f"ws://{host}:{PORT}"
            return stack.enter_context(connect(url, open_timeout=5))

        yield open_client

