"""Fixtures nach dem Bridge-Testmuster (siehe bridge_harness.py)."""

from collections.abc import Iterator
from contextlib import ExitStack

import pytest
from bridge_harness import BUS_URL, BridgeProcess, port_lock
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
def bridge_process(request, tmp_path) -> Iterator:
    """Fabrik: `bridge_process("--source", "sim", ...)` startet eine Bridge; Stopp nach dem Test."""
    started: list[BridgeProcess] = []
    request.node.bridge_processes = started

    def start(*args: str) -> BridgeProcess:
        bridge = BridgeProcess(list(args), tmp_path / f"bridge-{len(started)}.log")
        started.append(bridge)
        bridge.start()
        return bridge

    yield start
    for bridge in started:
        bridge.stop()


@pytest.fixture
def bus_client() -> Iterator:
    """Fabrik für Test-Clients am Bus; alle werden nach dem Test geschlossen."""
    with ExitStack() as stack:

        def open_client() -> ClientConnection:
            return stack.enter_context(connect(BUS_URL, open_timeout=5))

        yield open_client

