"""Tastatur im Bridge-Terminal, Windows-Pfad (`msvcrt`). Ohne echtes Terminal nicht über die
Bridge erreichbar (stdin der Test-Bridge ist kein TTY) – daher mit nachgebautem `msvcrt`
direkt an `Keyboard` geprüft; läuft so auf jedem System."""

import asyncio
import sys
import types

from vspin_bridge.keyboard import Key, Keyboard


def fake_msvcrt(pending: list[str]) -> types.ModuleType:
    """`kbhit`/`getwch` wie unter Windows, gespeist aus `pending`."""
    module = types.ModuleType("msvcrt")
    module.kbhit = lambda: bool(pending)
    module.getwch = lambda: pending.pop(0)
    return module


async def wait_until_read(pending: list[str]) -> None:
    for _ in range(100):
        if not pending:
            return
        await asyncio.sleep(0.01)
    raise AssertionError(f"Tasten nicht gelesen: {pending}")


def test_windows_keys_are_translated_and_polling_stops(monkeypatch):
    # Pfeiltasten kommen als Sondertaste: Präfix "\xe0" (oder "\x00") plus Code H/P.
    # Pfeil links ("\xe0K") und unbekannte Zeichen ("x") werden ignoriert.
    pending = ["+", "\xe0", "H", "x", "\x00", "P", "-", "\xe0", "K", "=", "q"]
    monkeypatch.setitem(sys.modules, "msvcrt", fake_msvcrt(pending))
    keys: list[Key] = []

    async def run() -> None:
        keyboard = Keyboard(keys.append)
        with monkeypatch.context() as patch:
            patch.setattr(sys, "platform", "win32")
            keyboard.start()
        await wait_until_read(pending)
        keyboard.stop()
        pending.append("+")  # nach `stop` liest niemand mehr
        await asyncio.sleep(0.2)
        assert pending == ["+"]

    asyncio.run(run())
    assert keys == [Key.UP, Key.UP, Key.DOWN, Key.DOWN, Key.UP, Key.QUIT]
