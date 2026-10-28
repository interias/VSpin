"""Test-Harness: parallele Testläufe teilen sich keinen Bus-Port (#62).

Läufe auf demselben Platz (`port_slot(VSPIN_PORT_BASE)`, #72) sperren einander aus; Läufe auf anderem Platz
bekommen einen eigenen Port und eine eigene Sperre und laufen gleichzeitig.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from bridge_harness import DEFAULT_PORT, LOCK_PATH, PORT, PORT_BASE_ENV, PORT_SLOTS, lock_path, port_base, port_slot

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
    # Höchster Platz: von parallelen Läufen (Wert = Paketnummer) praktisch nie belegt.
    other = PORT_SLOTS if port_slot(port_base()) != PORT_SLOTS else PORT_SLOTS - 1
    result = _second_run(other)
    assert result.stdout.strip() != str(LOCK_PATH)
    assert str(DEFAULT_PORT + port_slot(other)) in result.stdout
    assert result.returncode == 0, "andere Port-Basis wartet nicht auf diesen Lauf"


def test_port_base_moves_the_bus_port():
    assert port_base({}) == 0, "ohne Variable bleibt es bei 8765"
    assert port_base({PORT_BASE_ENV: ""}) == 0
    assert port_base({PORT_BASE_ENV: "3"}) == 3
    assert PORT == DEFAULT_PORT + port_slot(port_base())
    assert str(PORT) in LOCK_PATH.name


# Fixpunkte der Ableitung (#72), gleich in `games/island-ride/tests/test_test_isolation.gd`: Wert → Bus-Port.
PORT_FIXPOINTS = {0: 8765, 1: 8766, 3: 8768, 300: 9065, 301: 8766, 466: 8931, 467: 8932, 999: 8864, 1234: 8799}
# Sicherer Bereich: oberhalb der Systemports, unterhalb des dynamischen Bereichs (49152–65535), aus dem Windows
# (Hyper-V, WinNAT) wechselnde Bereiche ausschließt (`netsh interface ipv4 show excludedportrange protocol=tcp`).
SAFE_LOW = 1024
DYNAMIC_FIRST = 49152


@pytest.mark.parametrize("value", sorted(PORT_FIXPOINTS))
def test_every_value_maps_to_its_fixed_bus_port(value):
    assert port_base({PORT_BASE_ENV: str(value)}) == value, "jede ganze Zahl ≥ 0 ist gültig"
    assert DEFAULT_PORT + port_slot(value) == PORT_FIXPOINTS[value]


def test_bus_ports_stay_in_the_safe_range_and_apart():
    # Jeder Platz hat seinen eigenen Bus-Port; alle liegen unter dem dynamischen Bereich (dort darüber, ab 18765,
    # die Fake-Bus-Ports des Spiels: 18765 + 100·Platz … + 99, höchstens 48864).
    ports = {DEFAULT_PORT + slot for slot in range(PORT_SLOTS + 1)}
    assert len(ports) == PORT_SLOTS + 1
    assert (min(ports), max(ports)) == (8765, 9065)
    assert SAFE_LOW <= min(ports) and max(ports) < 18765
    assert 18765 + 100 * PORT_SLOTS + 99 < DYNAMIC_FIRST


def test_values_share_a_port_only_a_multiple_of_300_apart():
    for value in range(2001):
        slot = port_slot(value)
        assert (slot == 0) == (value == 0)
        assert 0 <= slot <= PORT_SLOTS
        if 1 <= value <= PORT_SLOTS:
            assert slot == value, "bis 300 wie bisher: Bus-Port 8765 + n"
        if value > PORT_SLOTS:
            assert slot == port_slot(value - PORT_SLOTS)
    # Teilen zwei Werte den Port, teilen sie auch die Sperre: Die Läufe warten aufeinander, statt sich zu stören.
    assert lock_path(DEFAULT_PORT + port_slot(72)) == lock_path(DEFAULT_PORT + port_slot(372))
    assert lock_path(DEFAULT_PORT + port_slot(72)) != lock_path(DEFAULT_PORT + port_slot(73))


@pytest.mark.parametrize("raw", ["x", "-1", "1.5", "4 6"])
def test_invalid_port_base_stops_the_run(raw):
    # Still auf 8765 zurückzufallen hieße, einem parallelen Lauf in die Quere zu kommen.
    with pytest.raises(ValueError, match=PORT_BASE_ENV):
        port_base({PORT_BASE_ENV: raw})
