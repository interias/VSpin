"""`python -m vspin_bridge.garmin login|status` mit gefälschtem `input`/`getpass` und gefälschter Bibliothek:
genau ein Anmeldeversuch, MFA nur bei Bedarf, kein Geheimnis in stdout/stderr.

Kein Netz, kein echtes `~/.garminconnect`: Jeder Test gibt ein `tmp_path` als `--token-dir`.
"""

import os
import subprocess
import sys
from pathlib import Path

import pytest
from fake_garmin import (
    FakeGarminLibrary,
    GarminConnectAuthenticationError,
    GarminConnectTooManyRequestsError,
    missing_library,
)

from vspin_bridge.garmin import GarminConnectUploader, LoginState
from vspin_bridge.garmin.cli import main

EMAIL = "fahrer@example.org"
PASSWORD = "Passw0rt-sehr-geheim"
MFA_CODE = "424242"


class Terminal:
    """Gefälschte Eingaben; merkt sich jede Rückfrage."""

    def __init__(self, email: str = EMAIL, password: str = PASSWORD) -> None:
        self.prompts: list[str] = []
        self._email = email
        self._password = password

    def input(self, prompt: str) -> str:
        self.prompts.append(prompt)
        return self._email

    def getpass(self, prompt: str) -> str:
        self.prompts.append(prompt)
        return MFA_CODE if "MFA" in prompt else self._password


def login(lib, token_dir: Path, terminal: Terminal) -> int:
    return main(
        ["--token-dir", str(token_dir), "login"], library=lib, input_fn=terminal.input, getpass_fn=terminal.getpass
    )


def assert_no_secret(capsys) -> str:
    out, err = capsys.readouterr()
    for secret in (PASSWORD, MFA_CODE, "oauth"):
        assert secret not in out and secret not in err
    return out + err


def test_login_stores_the_token_and_prints_no_secret(capsys, tmp_path):
    lib, terminal, token_dir = FakeGarminLibrary(), Terminal(), tmp_path / "garminconnect"

    assert login(lib, token_dir, terminal) == 0

    assert lib.clients == [{"email": EMAIL, "password": PASSWORD}]
    assert lib.logins == [None]
    assert lib.dumps == [str(token_dir)] and token_dir.is_dir()
    assert terminal.prompts == ["Garmin-E-Mail: ", "Garmin-Passwort: "]  # kein MFA ohne Bedarf
    assert "Angemeldet" in assert_no_secret(capsys)


def test_login_asks_for_mfa_only_when_garmin_wants_it(capsys, tmp_path):
    lib, terminal = FakeGarminLibrary(), Terminal()
    lib.mfa = True

    assert login(lib, tmp_path / "garminconnect", terminal) == 0

    assert terminal.prompts[-1] == "MFA-Code: "
    assert lib.mfa_codes == [MFA_CODE]
    assert_no_secret(capsys)


@pytest.mark.parametrize(
    ("error", "reason"),
    [
        (GarminConnectAuthenticationError(f"401 for {PASSWORD}"), "E-Mail, Passwort oder MFA-Code falsch"),
        (GarminConnectTooManyRequestsError("429"), "zu viele Anmeldeversuche"),
        (RuntimeError(PASSWORD), "unerwarteter Fehler (RuntimeError)"),
    ],
)
def test_failed_login_exits_nonzero_after_exactly_one_attempt(capsys, tmp_path, error, reason):
    lib, terminal, token_dir = FakeGarminLibrary(), Terminal(), tmp_path / "garminconnect"
    lib.login_error = error
    lib.mfa = True

    assert login(lib, token_dir, terminal) == 1

    assert len(lib.clients) == 1 and len(lib.logins) == 1  # kein zweiter Versuch
    assert lib.dumps == [] and not token_dir.exists()
    output = assert_no_secret(capsys)
    assert reason in output and "Nicht sofort wiederholen" in output


@pytest.mark.parametrize("broken", ["no_garth", "dump_error"])
def test_saving_the_token_fails_separately_and_leaves_no_login(capsys, tmp_path, broken):
    """Anmeldung gelingt, nur das Speichern scheitert: eigene Meldung, kein `logged_in`, kein zweiter Versuch."""
    lib, terminal, token_dir = FakeGarminLibrary(), Terminal(), tmp_path / "garminconnect"
    if broken == "no_garth":
        lib.has_garth = False
    else:
        lib.dump_error = PermissionError(f"cannot write {PASSWORD}")

    assert login(lib, token_dir, terminal) == 3

    assert len(lib.clients) == 1 and len(lib.logins) == 1
    assert not token_dir.exists()
    output = assert_no_secret(capsys)
    assert "Bei Garmin angemeldet, aber das Token konnte nicht gespeichert werden" in output
    assert "bitte nicht erneut anmelden" in output and "Anmeldung gescheitert" not in output
    assert GarminConnectUploader(token_dir, lib).login_state() is LoginState.NOT_LOGGED_IN
    assert main(["--token-dir", str(token_dir), "status"], library=lib) == 1


def test_failed_save_keeps_an_existing_token_dir_with_files(capsys, tmp_path):
    lib, token_dir = FakeGarminLibrary(), tmp_path / "garminconnect"
    token_dir.mkdir()
    (token_dir / "old").write_text("x", encoding="utf-8")
    lib.has_garth = False

    assert login(lib, token_dir, Terminal()) == 3

    assert (token_dir / "old").is_file()
    assert_no_secret(capsys)


def test_login_without_library_asks_nothing(capsys, tmp_path):
    terminal = Terminal()

    assert login(missing_library, tmp_path / "garminconnect", terminal) == 1

    assert terminal.prompts == []
    assert 'pip install -e ".[garmin]"' in capsys.readouterr().err


@pytest.mark.parametrize(("email", "password"), [("", PASSWORD), (EMAIL, "")])
def test_login_without_credentials_does_not_try(capsys, tmp_path, email, password):
    lib = FakeGarminLibrary()

    assert login(lib, tmp_path / "garminconnect", Terminal(email, password)) == 2

    assert lib.clients == []
    assert_no_secret(capsys)


def test_status(capsys, tmp_path):
    lib, token_dir = FakeGarminLibrary(), tmp_path / "garminconnect"

    assert main(["--token-dir", str(token_dir), "status"], library=lib) == 1
    assert "Nicht bei Garmin angemeldet" in capsys.readouterr().out

    token_dir.mkdir()
    assert main(["--token-dir", str(token_dir), "status"], library=lib) == 0
    assert "Bei Garmin angemeldet" in capsys.readouterr().out

    assert main(["--token-dir", str(token_dir), "status"], library=missing_library) == 1
    assert 'pip install -e ".[garmin]"' in capsys.readouterr().out
    assert lib.clients == []  # Status ruft Garmin nie auf


def test_module_entry_point_reports_the_missing_library(tmp_path):
    """`python -m vspin_bridge.garmin status` im echten Interpreter: ohne das Extra `garmin` kein Absturz."""
    code = (
        "import runpy, sys; sys.modules['garminconnect'] = None; "  # simuliert das fehlende Extra
        "runpy.run_module('vspin_bridge.garmin', run_name='__main__')"
    )
    result = subprocess.run(
        [sys.executable, "-c", code, "--token-dir", str(tmp_path / "garminconnect"), "status"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
        timeout=30,
    )

    assert result.returncode == 1, result.stderr
    assert "Bibliothek garminconnect fehlt" in result.stdout
