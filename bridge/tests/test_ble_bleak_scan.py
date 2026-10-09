"""bleak-Umsetzung: scheitert schon das Bauen des Scanners (z. B. kein Backend für die Plattform), kommt das als
`BleError` an und beendet die Hintergrundaufgabe der Pulsquelle nicht. `BleakScanner` ist durch eine werfende
Attrappe ersetzt; es gibt keinen echten Scan."""

import asyncio

import pytest
from bleak.exc import BleakError
from vspin_bridge.ble import BleError
from vspin_bridge.ble import bleak_adapter
from vspin_bridge.ble.bleak_adapter import BleakAdapter
from vspin_bridge.sources.heart_rate import HEART_RATE_SERVICE, HeartRateDevice, HeartRateSource, HeartRateState, Role


def failing_scanner(error: Exception, built: list):
    class Scanner:
        def __init__(self, *args, **kwargs) -> None:
            built.append(kwargs)
            raise error

    return Scanner


@pytest.mark.parametrize("error", [BleakError("kein Backend"), OSError("kein Adapter")])
def test_scanner_that_cannot_be_built_is_a_ble_error(monkeypatch, error):
    built: list = []
    monkeypatch.setattr(bleak_adapter, "BleakScanner", failing_scanner(error, built))
    with pytest.raises(BleError, match="Suche startet nicht"):
        asyncio.run(BleakAdapter().start_scan(HEART_RATE_SERVICE, lambda advertisement: None))
    assert built[0]["service_uuids"] == [HEART_RATE_SERVICE]


def test_heart_rate_source_survives_a_scanner_that_cannot_be_built(monkeypatch):
    built: list = []
    monkeypatch.setattr(bleak_adapter, "BleakScanner", failing_scanner(BleakError("kein Backend"), built))

    async def scenario() -> HeartRateState:
        source = HeartRateSource(BleakAdapter(), lambda status: None, retry_s=0.05)
        await source.start()
        await source.set_known_devices([HeartRateDevice("AA:00:00:00:00:01", "HRM-Pro", Role.STRAP)])
        await asyncio.sleep(0.4)
        state = source.status.state
        await source.stop()  # würde die Ausnahme einer abgebrochenen Hintergrundaufgabe auslösen
        return state

    assert asyncio.run(scenario()) is HeartRateState.DISCONNECTED
    assert len(built) >= 2  # die Quelle versucht es nach der Pause erneut
