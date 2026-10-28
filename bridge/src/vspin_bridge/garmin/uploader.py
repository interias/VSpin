"""Nahtstelle `Uploader` und ihre Umsetzung mit `garminconnect` (Zustände: siehe Paket-Docstring)."""

import importlib
import re
from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from types import ModuleType
from typing import Protocol

DEFAULT_TOKEN_DIR = Path.home() / ".garminconnect"
INSTALL_HINT = 'pip install -e ".[garmin]"'
LOGIN_COMMAND = "python -m vspin_bridge.garmin login"

KEEP_FILE = "Die FIT-Datei bleibt für den manuellen Import liegen."


class LoginState(StrEnum):
    LOGGED_IN = "logged_in"
    NOT_LOGGED_IN = "not_logged_in"
    UNAVAILABLE = "unavailable"


class UploadState(StrEnum):
    UPLOADED = "uploaded"
    DUPLICATE = "duplicate"
    NOT_LOGGED_IN = "not_logged_in"
    AUTH_EXPIRED = "auth_expired"
    REJECTED = "rejected"
    FAILED = "failed"
    UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class UploadResult:
    state: UploadState
    message: str  # deutsch, für den Dialog; enthält nie Zugangsdaten oder Fehlertexte der Bibliothek

    @property
    def ok(self) -> bool:
        """Die Fahrt liegt in Garmin Connect (`uploaded` oder `duplicate`)."""
        return self.state in (UploadState.UPLOADED, UploadState.DUPLICATE)


class Uploader(Protocol):
    def login_state(self) -> LoginState: ...

    def upload(self, fit_path: Path) -> UploadResult: ...


UNAVAILABLE = UploadResult(
    UploadState.UNAVAILABLE, f"Garmin-Upload nicht installiert: {INSTALL_HINT} im Ordner bridge/."
)
NOT_LOGGED_IN = UploadResult(
    UploadState.NOT_LOGGED_IN, f"Nicht bei Garmin angemeldet – im Terminal anmelden: {LOGIN_COMMAND}"
)
AUTH_EXPIRED = UploadResult(
    UploadState.AUTH_EXPIRED, f"Anmeldung abgelaufen – bitte neu anmelden ({LOGIN_COMMAND})."
)
UPLOADED = UploadResult(UploadState.UPLOADED, "Fahrt zu Garmin Connect hochgeladen.")
DUPLICATE = UploadResult(UploadState.DUPLICATE, "Die Fahrt ist schon in Garmin Connect.")
VERSION_MISMATCH = UploadResult(
    UploadState.FAILED,
    "Upload zu Garmin Connect gescheitert: Die Bibliothek garminconnect passt nicht zu VSpin (Version prüfen) – "
    f"neu anmelden hilft nicht. {KEEP_FILE}",
)
RATE_LIMITED = UploadResult(
    UploadState.REJECTED, f"Garmin Connect meldet zu viele Anfragen – später erneut versuchen. {KEEP_FILE}"
)


def import_garminconnect() -> ModuleType:
    """Lädt die Bibliothek erst bei Bedarf; ohne das Extra `garmin` wirft das `ImportError`."""
    return importlib.import_module("garminconnect")


class GarminConnectUploader:
    """`Uploader` mit `garminconnect`: setzt das Token fort (nie mit Passwort) und lädt genau einmal hoch.

    `library` liefert das Modul `garminconnect` (Standard: lazy importiert); Tests geben eine Fälschung.
    Jede Ausnahme wird auf einen Zustand abgebildet, nichts wird wiederholt.
    """

    def __init__(
        self,
        token_dir: Path = DEFAULT_TOKEN_DIR,
        library: Callable[[], ModuleType] = import_garminconnect,
    ) -> None:
        self.token_dir = token_dir
        self._library = library

    def _load(self) -> ModuleType | None:
        try:
            return self._library()
        except ImportError:
            return None

    def login_state(self) -> LoginState:
        if self._load() is None:
            return LoginState.UNAVAILABLE
        # Reine Existenzprüfung: das Token wird hier weder gelesen noch geprüft.
        return LoginState.LOGGED_IN if self.token_dir.is_dir() else LoginState.NOT_LOGGED_IN

    def upload(self, fit_path: Path) -> UploadResult:
        lib = self._load()
        if lib is None:
            return UNAVAILABLE
        if not self.token_dir.is_dir():
            return NOT_LOGGED_IN
        if not fit_path.is_file():
            return UploadResult(UploadState.FAILED, f"FIT-Datei fehlt: {fit_path}")

        # --- Gegen garminconnect 0.3.x ungeprüft (angenommen nach der 0.2.x-API): `Garmin()` ohne
        # Zugangsdaten, `login(tokenstore=…)` lädt nur das gespeicherte Token, `import_activity(pfad)`
        # (Spec #84) lädt hoch und wirft bei HTTP-Fehlern. -------------------------------------------
        try:
            client = lib.Garmin()
            client.login(tokenstore=str(self.token_dir))
        except Exception as exc:
            return _resume_error(lib, exc)
        try:
            response = client.import_activity(str(fit_path))
        except Exception as exc:
            return _upload_error(lib, exc)
        status = _status_of(response)
        if status is not None and status >= 400 or _says_duplicate(response):
            return _upload_error(lib, None, status, response)
        return UPLOADED


# --- Abbildung der Fehler: Klassennamen und Statusfundorte gegen garminconnect 0.3.x ungeprüft -----

AUTH_ERROR = "GarminConnectAuthenticationError"
TOO_MANY_REQUESTS = "GarminConnectTooManyRequestsError"
CONNECTION_ERROR = "GarminConnectConnectionError"
NETWORK_CLASS_NAMES = {"ConnectionError", "Timeout", "TimeoutError"}  # builtins und requests


def is_error(lib: ModuleType, exc: BaseException, name: str) -> bool:
    cls = getattr(lib, name, None)
    return isinstance(cls, type) and isinstance(exc, cls)


def is_network_error(lib: ModuleType, exc: BaseException) -> bool:
    names = {cls.__name__ for cls in type(exc).__mro__}
    return is_error(lib, exc, CONNECTION_ERROR) or bool(names & NETWORK_CLASS_NAMES)


def is_api_mismatch(exc: BaseException) -> bool:
    """`TypeError`/`AttributeError`: die Bibliothek hat eine andere API als angenommen – ein Fehler in VSpin,
    den keine neue Anmeldung heilt."""
    return isinstance(exc, (TypeError, AttributeError))


def _status_of(obj: object) -> int | None:
    """HTTP-Status an Antwort oder Ausnahme: `status_code`, `.response.status_code`, `.error`, Ursachenkette;
    zuletzt eine 4xx/5xx-Zahl im Fehlertext."""
    seen: set[int] = set()
    stack = [obj]
    while stack:
        item = stack.pop()
        if item is None or id(item) in seen:
            continue
        seen.add(id(item))
        for holder in (item, getattr(item, "response", None)):
            code = getattr(holder, "status_code", None)
            if isinstance(code, int):
                return code
        if isinstance(item, BaseException):
            stack += [getattr(item, "error", None), item.__cause__, item.__context__]
    if isinstance(obj, BaseException):
        match = re.search(r"\b([45]\d\d)\b", str(obj))
        if match:
            return int(match.group(1))
    return None


def _says_duplicate(obj: object) -> bool:
    text = getattr(obj, "text", obj)
    return "duplicate" in str(text).lower()


def _resume_error(lib: ModuleType, exc: BaseException) -> UploadResult:
    """Fehler beim Fortsetzen des Tokens. Alles außer Netz/5xx, 429 und API-Abweichung heißt: neu anmelden."""
    if is_api_mismatch(exc):
        return VERSION_MISMATCH
    status = _status_of(exc)
    if is_error(lib, exc, TOO_MANY_REQUESTS) or status == 429:
        return RATE_LIMITED
    if status is not None and status < 500:
        return AUTH_EXPIRED
    if status is not None or is_network_error(lib, exc):
        return _failed(status)
    return AUTH_EXPIRED


def _upload_error(
    lib: ModuleType, exc: BaseException | None, status: int | None = None, response: object = None
) -> UploadResult:
    if exc is not None:
        if is_api_mismatch(exc):
            return VERSION_MISMATCH
        status = _status_of(exc)
    if status == 409 or _says_duplicate(exc if exc is not None else response):
        return DUPLICATE
    if exc is not None and is_error(lib, exc, AUTH_ERROR) or status in (401, 403):
        return AUTH_EXPIRED
    if exc is not None and is_error(lib, exc, TOO_MANY_REQUESTS) or status == 429:
        return RATE_LIMITED
    if status is not None and 400 <= status < 500:
        return UploadResult(
            UploadState.REJECTED, f"Garmin Connect hat die Fahrt abgelehnt (HTTP {status}). {KEEP_FILE}"
        )
    return _failed(status if status is not None and status >= 500 else None)


def _failed(status: int | None) -> UploadResult:
    reason = f"HTTP {status}" if status is not None else "keine Verbindung oder unbekannter Fehler"
    return UploadResult(UploadState.FAILED, f"Upload zu Garmin Connect gescheitert ({reason}). {KEEP_FILE}")
