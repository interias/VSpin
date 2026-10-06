"""Tastatur im Bridge-Terminal (Simulator, manueller Modus).

Linux/macOS: termios/tty im cbreak-Modus, nicht-blockierend über den Event-Loop.
Windows: msvcrt, per kurzem Polling. Ist stdin kein TTY (z. B. in Tests), bleibt
die Tastatur aus und die Bridge läuft normal weiter.
"""

import asyncio
import os
import sys
from collections.abc import Callable
from enum import Enum


class Key(Enum):
    UP = "up"
    DOWN = "down"
    QUIT = "quit"


HELP = "Tasten: Pfeil hoch/+ = Kadenz +5, Pfeil runter/- = Kadenz -5, q = beenden"

_CHAR_KEYS = {"+": Key.UP, "=": Key.UP, "-": Key.DOWN, "q": Key.QUIT, "Q": Key.QUIT}


def keyboard_available() -> bool:
    try:
        return sys.stdin is not None and sys.stdin.isatty()
    except (AttributeError, ValueError):
        return False


class Keyboard:
    """Ruft `on_key` für jede erkannte Taste auf. `start`/`stop` sind idempotent."""

    def __init__(self, on_key: Callable[[Key], None]) -> None:
        self._on_key = on_key
        self._stop: Callable[[], None] | None = None

    def start(self) -> None:
        if self._stop is not None:
            return
        if sys.platform == "win32":
            self._stop = self._start_windows()
        else:
            self._stop = self._start_posix()

    def stop(self) -> None:
        if self._stop is not None:
            self._stop()
            self._stop = None

    def _start_posix(self) -> Callable[[], None]:
        import termios
        import tty

        fd = sys.stdin.fileno()
        old_attrs = termios.tcgetattr(fd)
        tty.setcbreak(fd)  # keine Zeilenpufferung/kein Echo; Strg+C bleibt aktiv
        loop = asyncio.get_running_loop()

        def on_readable() -> None:
            for key in parse_posix(os.read(fd, 64)):
                self._on_key(key)

        loop.add_reader(fd, on_readable)

        def stop() -> None:
            loop.remove_reader(fd)
            termios.tcsetattr(fd, termios.TCSADRAIN, old_attrs)

        return stop

    def _start_windows(self) -> Callable[[], None]:
        import msvcrt

        async def poll() -> None:
            while True:
                while msvcrt.kbhit():
                    ch = msvcrt.getwch()
                    if ch in ("\x00", "\xe0"):  # Sondertaste: zweites Zeichen ist der Code
                        code = msvcrt.getwch()
                        key = {"H": Key.UP, "P": Key.DOWN}.get(code)
                    else:
                        key = _CHAR_KEYS.get(ch)
                    if key is not None:
                        self._on_key(key)
                await asyncio.sleep(0.05)

        task = asyncio.get_running_loop().create_task(poll())
        return task.cancel


def parse_posix(data: bytes) -> list[Key]:
    """Übersetzt rohe Terminal-Bytes in Tasten (Pfeiltasten als ESC [ A / ESC [ B)."""
    keys: list[Key] = []
    text = data.decode(errors="ignore")
    i = 0
    while i < len(text):
        if text.startswith(("\x1b[A", "\x1bOA"), i):
            keys.append(Key.UP)
            i += 3
        elif text.startswith(("\x1b[B", "\x1bOB"), i):
            keys.append(Key.DOWN)
            i += 3
        else:
            key = _CHAR_KEYS.get(text[i])
            if key is not None:
                keys.append(key)
            i += 1
    return keys
