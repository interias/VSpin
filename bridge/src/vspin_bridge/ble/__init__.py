"""BLE-Grundlage der Bridge: Suchen, Verbinden, Notifications, Verbindungsabbruch.

Allgemein, nicht pulsspezifisch: Die `HeartRateSource` (`sources/heart_rate.py`) baut als
Erste darauf auf, die Trainerquelle (`sources/trainer.py`) nutzt dieselbe Nahtstelle.
Quellen kennen nur die Nahtstelle `BleAdapter` (`base.py`); dahinter steckt bleak
(`BleakAdapter`, `bleak_adapter.py`), in Tests ein skriptbarer Fake (`tests/fake_ble.py`).
"""

from .base import Advertisement, BleAdapter, BleConnection, BleError, BleScan, GattCharacteristic

__all__ = ["Advertisement", "BleAdapter", "BleConnection", "BleError", "BleScan", "GattCharacteristic"]
