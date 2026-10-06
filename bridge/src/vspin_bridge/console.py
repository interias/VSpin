"""Statuszeile im Bridge-Terminal: Quelle, Verbindungsstatus, Kadenz, Clients."""

import sys
from typing import TextIO


class Console:
    """Im TTY wird eine Zeile überschrieben; sonst (Pipe/Datei) eine Zeile pro Änderung."""

    def __init__(self, stream: TextIO | None = None) -> None:
        self._stream = stream if stream is not None else sys.stdout
        self._tty = _isatty(self._stream)
        self._last = ""

    def info(self, text: str) -> None:
        self._finish_line()
        self._write(text + "\n")

    def show(self, source: str, state: str, cadence: float | None, clients: int) -> None:
        cadence_text = "--" if cadence is None else f"{cadence:.0f} rpm"
        line = f"Quelle: {source} | Status: {state} | Kadenz: {cadence_text} | Clients: {clients}"
        if line == self._last:
            return
        if self._tty:
            pad = max(0, len(self._last) - len(line))
            self._write("\r" + line + " " * pad)
        else:
            self._write(line + "\n")
        self._last = line

    def close(self) -> None:
        self._finish_line()

    def _finish_line(self) -> None:
        if self._tty and self._last:
            self._write("\n")
            self._last = ""

    def _write(self, text: str) -> None:
        self._stream.write(text)
        self._stream.flush()


def _isatty(stream: TextIO) -> bool:
    try:
        return stream.isatty()
    except (AttributeError, ValueError):
        return False
