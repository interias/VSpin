"""Test-Harness: parallele Testläufe teilen sich keinen Bus-Port (#62).

Läufe auf derselben Port-Basis sperren einander aus; Läufe mit anderer Basis (`VSPIN_PORT_BASE`) bekommen
einen eigenen Port und eine eigene Sperre und laufen gleichzeitig.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from bridge_harness import DEFAULT_PORT, LOCK_PATH, MAX_PORT_BASE, PORT, PORT_BASE_ENV, port_base

TESTS_DIR = Path(__file__).resolve().parent

# Zweiter „Testlauf“: holt sich mit seiner eigenen Umgebung die Sperre seiner Port-Basis, ohne zu warten.
TRY_LOCK = """
import sys
sys.path.insert(0, sys.argv[1])
from bridge_harness import LOCK_PATH, try_lock
print(LOCK_PATH)
with open(LOCK_PATH, "a+") as f:
    sys.exit(0 if try_lock(f) else 3)
"""


def _second_run(base: int) -> subprocess.CompletedProcess:
    env = {**os.environ, PORT_BASE_ENV: str(base)}
    return subprocess.run(
        [sys.executable, "-c", TRY_LOCK, str(TESTS_DIR)], env=env, capture_output=True, text=True, timeout=10
    )


def test_running_suite_holds_the_port_lock():
    # Ein zweiter Testlauf auf derselben Basis käme nicht an die Sperre und würde warten, statt Bridges zu starten.
    result = _second_run(port_base())
    assert result.stdout.strip() == str(LOCK_PATH)
    assert result.returncode == 3


def test_run_with_other_port_base_gets_its_own_lock():
    # Höchster Wert: von parallelen Läufen (Wert = Paketnummer) praktisch nie belegt.
    other = MAX_PORT_BASE if port_base() != MAX_PORT_BASE else MAX_PORT_BASE - 1
    result = _second_run(other)
    assert result.stdout.strip() != str(LOCK_PATH)
    assert str(DEFAULT_PORT + other) in result.stdout
    assert result.returncode == 0, "andere Port-Basis wartet nicht auf diesen Lauf"


def test_port_base_moves_the_bus_port():
    assert port_base({}) == 0, "ohne Variable bleibt es bei 8765"
    assert port_base({PORT_BASE_ENV: ""}) == 0
    assert port_base({PORT_BASE_ENV: "3"}) == 3
    assert PORT == DEFAULT_PORT + port_base()
    assert str(PORT) in LOCK_PATH.name


@pytest.mark.parametrize("raw", ["x", "-1", str(MAX_PORT_BASE + 1), "1.5"])
def test_invalid_port_base_stops_the_run(raw):
    # Still auf 8765 zurückzufallen hieße, einem parallelen Lauf in die Quere zu kommen.
    with pytest.raises(ValueError, match=PORT_BASE_ENV):
        port_base({PORT_BASE_ENV: raw})
