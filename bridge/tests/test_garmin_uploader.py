"""GarminConnectUploader gegen die gefälschte Bibliothek: Erfolg, Duplikat = Erfolg, Anmeldefehler und 4xx ohne
Wiederholung, Netzfehler, fehlende Bibliothek, fehlendes Token-Verzeichnis ohne Client-Aufruf.

Kein Netz, kein echtes `~/.garminconnect`: Jeder Test bekommt ein `tmp_path` als Token-Verzeichnis.
"""

import sys
from pathlib import Path

import fake_garmin
import pytest
from fake_garmin import (
    FakeGarminLibrary,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
    HTTPError,
    Response,
    missing_library,
)

from vspin_bridge.garmin import (
    DEFAULT_TOKEN_DIR,
    GarminConnectUploader,
    TOKEN_FILE,
    LoginState,
    Uploader,
    UploadState,
)

SECRET = "geheim-token-abc123"  # steht in Fehlertexten der Bibliothek und darf nie in einer Meldung landen


@pytest.fixture
def token_dir(tmp_path) -> Path:
    path = tmp_path / "garminconnect"
    path.mkdir()
    (path / TOKEN_FILE).write_text("{}", encoding="utf-8")
    return path


@pytest.fixture
def fit(tmp_path) -> Path:
    path = tmp_path / "ride.fit"
    path.write_bytes(b"\x0e\x10fake-fit")
    return path


@pytest.fixture
def lib() -> FakeGarminLibrary:
    return FakeGarminLibrary()


def upload(lib, token_dir, fit):
    return GarminConnectUploader(token_dir, lib).upload(fit)


def test_default_token_dir_is_outside_the_repo():
    assert DEFAULT_TOKEN_DIR == Path.home() / ".garminconnect"


def test_is_an_uploader(lib, token_dir):
    uploader: Uploader = GarminConnectUploader(token_dir, lib)
    assert uploader.login_state() == "logged_in"


def test_upload_resumes_the_token_without_password_and_uploads_once(lib, token_dir, fit):
    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.UPLOADED and result.ok
    assert result.message == "Fahrt zu Garmin Connect hochgeladen."
    assert lib.clients == [{"email": None, "password": None}]
    assert lib.logins == [str(token_dir)]
    assert lib.uploads == [str(fit)]


def test_duplicate_conflict_counts_as_success(lib, token_dir, fit):
    error = GarminConnectConnectionError("Upload failed")
    error.__cause__ = HTTPError(409, '{"failures": [{"messages": [{"content": "Duplicate Activity."}]}]}')
    lib.upload_error = error

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.DUPLICATE and result.ok
    assert len(lib.uploads) == 1


def test_duplicate_in_the_response_counts_as_success(lib, token_dir, fit):
    lib.upload_response = Response(202, '{"failures": [{"messages": [{"content": "Duplicate Activity."}]}]}')

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.DUPLICATE and result.ok


def test_auth_error_on_resume_means_auth_expired_and_exactly_one_attempt(lib, token_dir, fit):
    lib.login_error = GarminConnectAuthenticationError(f"token {SECRET} expired")
    uploader = GarminConnectUploader(token_dir, lib)

    result = uploader.upload(fit)

    assert result.state is UploadState.AUTH_EXPIRED and not result.ok
    assert result.message == "Anmeldung abgelaufen – bitte neu anmelden (python -m vspin_bridge.garmin login)."
    assert SECRET not in result.message
    assert lib.logins == [str(token_dir)]  # genau ein Anmeldeversuch …
    assert lib.uploads == []  # … und kein Upload danach
    assert all(client["password"] is None for client in lib.clients)

    uploader.upload(fit)  # Gegenprobe: jeder Aufruf versucht es genau einmal, nie öfter
    assert len(lib.logins) == 2 and len(lib.clients) == 2


@pytest.mark.parametrize("error", [FileNotFoundError("oauth1_token.json"), HTTPError(401), ValueError("bad token")])
def test_broken_or_rejected_token_means_auth_expired(lib, token_dir, fit, error):
    lib.login_error = error

    assert upload(lib, token_dir, fit).state is UploadState.AUTH_EXPIRED
    assert len(lib.logins) == 1 and lib.uploads == []


@pytest.mark.parametrize("on", ["login", "upload"])
@pytest.mark.parametrize(
    "error", [TypeError("login() got an unexpected keyword argument 'tokenstore'"), AttributeError("garth")]
)
def test_api_mismatch_fails_without_asking_to_log_in_again(lib, token_dir, fit, on, error):
    """Eine andere Bibliotheks-API heilt keine neue Anmeldung: `failed` mit Versionshinweis, nie `auth_expired`."""
    setattr(lib, f"{on}_error", error)

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.FAILED
    assert "Version prüfen" in result.message and "neu anmelden hilft nicht" in result.message
    assert "manuellen Import" in result.message and "tokenstore" not in result.message
    assert len(lib.logins) == 1 and len(lib.uploads) == (1 if on == "upload" else 0)


@pytest.mark.parametrize("error", [GarminConnectAuthenticationError(SECRET), HTTPError(401), HTTPError(403)])
def test_auth_error_on_upload_means_auth_expired_without_retry(lib, token_dir, fit, error):
    lib.upload_error = error

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.AUTH_EXPIRED
    assert len(lib.logins) == 1 and len(lib.uploads) == 1


@pytest.mark.parametrize("status", [400, 413, 422])
def test_client_error_is_rejected_without_retry(lib, token_dir, fit, status):
    lib.upload_error = GarminConnectConnectionError(f"Error: {status} Client Error {SECRET}")

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.REJECTED and not result.ok
    assert f"HTTP {status}" in result.message and "manuellen Import" in result.message
    assert SECRET not in result.message
    assert len(lib.uploads) == 1


def test_client_error_in_the_response_is_rejected(lib, token_dir, fit):
    lib.upload_response = Response(400, "bad request")

    assert upload(lib, token_dir, fit).state is UploadState.REJECTED


@pytest.mark.parametrize("on", ["login", "upload"])
def test_too_many_requests_is_rejected_without_retry(lib, token_dir, fit, on):
    setattr(lib, f"{on}_error", GarminConnectTooManyRequestsError("429"))

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.REJECTED
    assert "zu viele Anfragen" in result.message
    assert len(lib.logins) == 1 and len(lib.uploads) == (1 if on == "upload" else 0)


@pytest.mark.parametrize(
    "error",
    [
        fake_garmin.ConnectionError("Max retries exceeded"),
        TimeoutError("timed out"),
        GarminConnectConnectionError("Connection reset"),
        HTTPError(503),
        RuntimeError(SECRET),
    ],
)
def test_network_server_and_unknown_errors_fail_and_keep_the_file(lib, token_dir, fit, error):
    lib.upload_error = error

    result = upload(lib, token_dir, fit)

    assert result.state is UploadState.FAILED and not result.ok
    assert "manuellen Import" in result.message and SECRET not in result.message
    assert len(lib.uploads) == 1
    assert fit.is_file()


@pytest.mark.parametrize("error", [fake_garmin.ConnectionError("no route"), HTTPError(502)])
def test_network_error_on_resume_fails_instead_of_auth_expired(lib, token_dir, fit, error):
    lib.login_error = error

    assert upload(lib, token_dir, fit).state is UploadState.FAILED
    assert lib.uploads == []


def test_missing_library_is_unavailable(token_dir, fit):
    uploader = GarminConnectUploader(token_dir, missing_library)

    assert uploader.login_state() is LoginState.UNAVAILABLE
    result = uploader.upload(fit)
    assert result.state is UploadState.UNAVAILABLE
    assert 'pip install -e ".[garmin]"' in result.message


def test_missing_library_through_the_real_lazy_import_is_unavailable(monkeypatch, token_dir, fit):
    """Ohne das Extra `garmin`: der Standard-Import scheitert, die Bridge stürzt nicht ab."""
    monkeypatch.setitem(sys.modules, "garminconnect", None)  # simuliert das Fehlen, auch wenn es installiert ist
    uploader = GarminConnectUploader(token_dir)

    assert uploader.login_state() is LoginState.UNAVAILABLE
    assert uploader.upload(fit).state is UploadState.UNAVAILABLE


def test_missing_token_dir_is_not_logged_in_without_any_client_call(lib, tmp_path, fit):
    uploader = GarminConnectUploader(tmp_path / "missing", lib)

    assert uploader.login_state() is LoginState.NOT_LOGGED_IN
    result = uploader.upload(fit)

    assert result.state is UploadState.NOT_LOGGED_IN and not result.ok
    assert "python -m vspin_bridge.garmin login" in result.message
    assert lib.clients == [] and lib.logins == [] and lib.uploads == []


def test_token_dir_without_the_token_file_is_not_logged_in_without_any_client_call(lib, token_dir, fit):
    """Nach `logout()` der Bibliothek (sie entfernt nur `garmin_tokens.json`) oder während `login` läuft: Das
    Verzeichnis allein heißt nicht angemeldet."""
    (token_dir / TOKEN_FILE).unlink()
    (token_dir / "unrelated.txt").write_text("x", encoding="utf-8")
    uploader = GarminConnectUploader(token_dir, lib)

    assert uploader.login_state() is LoginState.NOT_LOGGED_IN
    assert uploader.upload(fit).state is UploadState.NOT_LOGGED_IN
    assert lib.clients == [] and lib.logins == [] and lib.uploads == []


def test_login_state_only_checks_the_token_file_exists(lib, token_dir):
    (token_dir / TOKEN_FILE).write_bytes(b"\xff kein JSON")  # nie gelesen: auch ein kaputtes Token zählt
    assert GarminConnectUploader(token_dir, lib).login_state() is LoginState.LOGGED_IN
    assert lib.clients == [] and lib.logins == []


def test_missing_fit_file_fails_without_any_client_call(lib, token_dir, tmp_path):
    result = upload(lib, token_dir, tmp_path / "gone.fit")

    assert result.state is UploadState.FAILED
    assert lib.clients == []
