"""bleak-Umsetzung der BLE-Nahtstelle: nur Import und Aufbau, ohne Gerät und ohne Scan.

Das Verhalten am echten Gerät ist nicht durch Tests belegt (Spec #64: keine Tests gegen Hardware).
"""

from vspin_bridge.ble import BleAdapter
from vspin_bridge.ble.bleak_adapter import BleakAdapter


def test_bleak_adapter_builds_and_fits_the_seam():
    adapter: BleAdapter = BleakAdapter(connect_timeout_s=5.0)
    assert callable(adapter.start_scan)
    assert callable(adapter.connect)
