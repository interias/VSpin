"""Test-Harness: parallele Testläufe (mehrere Checkouts) teilen sich Port 8765 nicht."""

import subprocess
import sys

import pytest
from bridge_harness import LOCK_PATH

TRY_LOCK = """
import fcntl, sys
with open(sys.argv[1], "a") as f:
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(3)
"""


@pytest.mark.skipif(sys.platform == "win32", reason="Windows: Harness sperrt nicht (kein fcntl)")
def test_running_suite_holds_the_port_lock():
    # Ein zweiter Testlauf käme nicht an die Sperre und würde warten, statt Bridges zu starten.
    result = subprocess.run([sys.executable, "-c", TRY_LOCK, str(LOCK_PATH)], timeout=10, check=False)
    assert result.returncode == 3
