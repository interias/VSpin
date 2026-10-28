"""Parent-Wächter (#79): endet das Spiel ohne Stoppdatei (Absturz, „Stop“ im Editor, TerminateProcess), beendet sich
der Begleiter selbst sauber. Der Launcher des Spiels setzt dafür `VSPIN_COMPANION_PARENT_PID`; bewusst kein
CLI-Argument, damit ein unbekanntes Argument den Start nie scheitern lässt. Die Prüfung ist die der Bridge
(`vspin_bridge.cli.process_alive`), hier ohne deren schwere Importe (bleak, Quellen) nachgebaut."""

import asyncio
import ctypes
import os
import sys
from collections.abc import Callable

PARENT_PID_ENV = "VSPIN_COMPANION_PARENT_PID"
PARENT_POLL_S = 1.0


def parent_pid(env: dict[str, str] | None = None) -> int | None:
    """Die PID aus der Umgebung; fehlt sie oder ist sie keine positive Zahl: `None` (kein Wächter)."""
    raw = (os.environ if env is None else env).get(PARENT_PID_ENV, "").strip()
    return int(raw) if raw.isdigit() and int(raw) > 0 else None


async def watch_parent(
    pid: int,
    stop: asyncio.Event,
    log: Callable[[str], None],
    alive: Callable[[int], bool] | None = None,
    poll_s: float = PARENT_POLL_S,
) -> None:
    alive = alive or process_alive
    while alive(pid):
        await asyncio.sleep(poll_s)
    log(f"vspin-companion: Elternprozess {pid} läuft nicht mehr – beende")
    stop.set()


def process_alive(pid: int) -> bool:
    """Läuft der Prozess `pid`? Unter Windows über OpenProcess und GetExitCodeProcess (STILL_ACTIVE), sonst Signal 0."""
    if pid <= 0:
        return False
    if sys.platform == "win32":
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = ctypes.c_void_p
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return ctypes.get_last_error() == 5  # ERROR_ACCESS_DENIED: es gibt ihn, nur fremd
        try:
            code = ctypes.c_ulong()
            if not kernel32.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code)):
                return False
            return code.value == 259  # STILL_ACTIVE
        finally:
            kernel32.CloseHandle(ctypes.c_void_p(handle))
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True
