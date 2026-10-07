"""Replay: spielt aufgezeichnete rohe BLE-Notifications erneut ab (ADR-0003).

Eingabe ist das Rohformat aus `tools/ble_discovery.py` bzw. der Session-Rohdatei
(ADR-0008): pro Zeile ein JSON-Objekt `{"t_ms": int, "char": "<128-Bit-UUID>", "hex": "…"}`.
Leere Zeilen werden übersprungen, `t_ms` darf nicht kleiner werden.

Die Notifications kommen im Takt der Aufnahme (`speed` = 1) oder beschleunigt
(`speed` = 10: zehnmal so schnell). Die Quelle liefert sie roh (`RawNotification`); die
Bridge schickt sie durch dieselben Parser wie später beim echten Rad. Am Ende der Datei
endet die Quelle (Status `disconnected`, wie ein Profil ohne `repeat`).
"""

import asyncio
import json
import math
from collections.abc import AsyncIterator
from pathlib import Path

from .. import parsers
from .base import Capability, NotSupportedError, RawNotification


class ReplayError(ValueError):
    """Replay-Datei fehlt, ist leer oder hält sich nicht an das Rohformat."""


class ReplaySource:
    name = "replay"

    def __init__(self, notifications: list[RawNotification], speed: float = 1.0) -> None:
        if not (math.isfinite(speed) and speed > 0):
            raise ReplayError(f"--speed muss > 0 sein, war {speed!r}")
        self.notifications = notifications
        self.speed = speed
        # Capabilities = was die Aufnahme tatsächlich enthält (z. B. CSC nur mit Kurbeldaten → CADENCE).
        self.capabilities: set[Capability] = set().union(*(parsers.capabilities(n) for n in notifications))
        self._played = False

    async def connect(self) -> None:
        pass  # Datei ist schon geladen

    async def samples(self) -> AsyncIterator[RawNotification]:
        if self._played:
            return
        self._played = True
        loop = asyncio.get_running_loop()
        start = loop.time()
        first_ms = self.notifications[0].t_ms
        for notification in self.notifications:
            due = start + (notification.t_ms - first_ms) / 1000.0 / self.speed
            delay = due - loop.time()
            if delay > 0:
                await asyncio.sleep(delay)
            yield notification

    async def set_grade(self, grade: float) -> None:
        raise NotSupportedError("Replay hat keine Capability RESISTANCE_CONTROL")


def load_replay(path: Path, speed: float = 1.0) -> ReplaySource:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReplayError(f"Replay-Datei {path} nicht lesbar: {exc.strerror or exc}") from None
    except UnicodeDecodeError:
        raise ReplayError(f"Replay-Datei {path} ist kein UTF-8-Text") from None
    notifications: list[RawNotification] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            notification = _parse_line(line)
        except ReplayError as exc:
            raise ReplayError(f"Replay-Datei {path}, Zeile {number}: {exc}") from None
        if notifications and notification.t_ms < notifications[-1].t_ms:
            raise ReplayError(
                f"Replay-Datei {path}, Zeile {number}: t_ms {notification.t_ms} kleiner als davor "
                f"({notifications[-1].t_ms})"
            )
        notifications.append(notification)
    if not notifications:
        raise ReplayError(f"Replay-Datei {path} enthält keine Notifications")
    return ReplaySource(notifications, speed)


def _parse_line(line: str) -> RawNotification:
    try:
        entry = json.loads(line)
    except ValueError as exc:
        raise ReplayError(f"kein gültiges JSON: {exc}") from None
    if not isinstance(entry, dict):
        raise ReplayError("erwartet ein JSON-Objekt {\"t_ms\", \"char\", \"hex\"}")
    t_ms, char, hex_ = entry.get("t_ms"), entry.get("char"), entry.get("hex")
    if isinstance(t_ms, bool) or not isinstance(t_ms, int) or t_ms < 0:
        raise ReplayError(f"'t_ms' muss eine ganze Zahl ≥ 0 sein, war {t_ms!r}")
    if not isinstance(char, str) or not char:
        raise ReplayError(f"'char' muss die UUID der Characteristic sein, war {char!r}")
    if not isinstance(hex_, str):
        raise ReplayError(f"'hex' muss ein Hex-Text sein, war {hex_!r}")
    try:
        data = bytes.fromhex(hex_)
    except ValueError:
        raise ReplayError(f"'hex' ist kein gültiger Hex-Text: {hex_!r}") from None
    return RawNotification(t_ms=t_ms, char=char, data=data)
