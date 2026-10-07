"""Session-Rohdaten: eine Zeile pro rohe BLE-Notification (ADR-0008), Replay-Format.

Format wie `tools/ble_discovery.py` und Eingabe von `--source replay`::

    {"t_ms": 1234, "char": "00002a5b-0000-1000-8000-00805f9b34fb", "hex": "03..."}

(`json.dumps` mit Standard-Trennzeichen, Schlüssel in dieser Reihenfolge, `hex` klein,
Zeilenende `\\n`). `t_ms` ist der Zeitstempel der Notification aus der Quelle: beim Replay
der aus der Aufnahme – eine Replay-Session schreibt so dieselben Zeilen wie die Eingabe.
Jede Zeile wird sofort geflusht.
"""

import json
from pathlib import Path
from typing import TextIO

from ..sources.base import RawNotification


def raw_line(raw: RawNotification) -> str:
    return json.dumps({"t_ms": raw.t_ms, "char": raw.char, "hex": raw.data.hex()})


class SessionRaw:
    def __init__(self, path: Path, stream: TextIO) -> None:
        self.path = path
        self._stream = stream

    def write(self, raw: RawNotification) -> None:
        self._stream.write(raw_line(raw) + "\n")
        self._stream.flush()

    def close(self) -> None:
        if not self._stream.closed:
            self._stream.close()
