"""Session-Steuerprotokoll (Spec #89): eine Zeile je Ereignis der Trainer-Steuerung, `<zeit>.control.jsonl`.

Diagnose, warum die Bridge den Trainer (nicht) steuert – am Gerät sonst nicht nachweisbar (die Bridge aus dem Spiel läuft
ohne Terminal). Je Zeile ein JSON-Objekt, `t_ms` zuerst (Bridge-Zeit wie CSV und Rohdaten), dann `event`::

    {"t_ms": 812, "event": "state", "state": "requesting", "reason": "fordere die Steuerung an"}
    {"t_ms": 815, "event": "write", "char": "2ad9", "hex": "00"}
    {"t_ms": 871, "event": "indication", "char": "2ad9", "hex": "800001"}
    {"t_ms": 902, "event": "notification", "char": "2ada", "hex": "ff"}
    {"t_ms": 2875, "event": "error", "text": "keine Antwort auf 0x07 (Zeitlimit)"}

`state`: jeder Wechsel von `status.trainer.control` samt Grundtext (und der Stand beim Start der Session); `write`: jedes
Schreiben auf den Control Point `0x2AD9`; `indication`: jede Indication von `0x2AD9`; `notification`: jede Notification
von Machine Status `0x2ADA`; `error`: gescheiterte Anfragen, Schreib- und Abo-Fehler. Keine Zugangsdaten. Jede Zeile wird
sofort geflusht. Ohne Trainer (Simulator, Replay) bleibt die Datei leer.
"""

import json
from pathlib import Path
from typing import TextIO


def control_line(t_ms: int, entry: dict) -> str:
    return json.dumps({"t_ms": t_ms, **entry}, ensure_ascii=False)


class SessionControl:
    def __init__(self, path: Path, stream: TextIO) -> None:
        self.path = path
        self._stream = stream

    def write(self, t_ms: int, entry: dict) -> None:
        self._stream.write(control_line(t_ms, entry) + "\n")
        self._stream.flush()

    def close(self) -> None:
        if not self._stream.closed:
            self._stream.close()
