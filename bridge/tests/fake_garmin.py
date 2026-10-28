"""Skriptbare Fälschung des Moduls `garminconnect` für `GarminConnectUploader` und die Garmin-CLI – kein Netz.

Bildet nur die angenommene API nach (gegen garminconnect 0.3.x ungeprüft, siehe `vspin_bridge.garmin.uploader`):
`Garmin(email=…, password=…, prompt_mfa=…)`, `login(tokenstore=None)`, `import_activity(pfad)`,
`garth.dump(pfad)` und die Ausnahmeklassen. Was bei `login` bzw. `import_activity` passiert, gibt der Test
vor (`login_error`, `upload_error`, `upload_response`, `mfa`, `has_garth`, `dump_error`); die Fälschung zählt
jeden Aufruf mit.
"""

from pathlib import Path
from types import ModuleType


class GarminConnectAuthenticationError(Exception):
    pass


class GarminConnectConnectionError(Exception):
    pass


class GarminConnectTooManyRequestsError(Exception):
    pass


class ConnectionError(OSError):  # noqa: A001 – wie requests.exceptions.ConnectionError
    pass


class HTTPError(OSError):
    """Wie requests.HTTPError: trägt die Antwort mit `status_code`."""

    def __init__(self, status: int, text: str = "") -> None:
        super().__init__(f"{status} Client Error")
        self.response = Response(status, text)


class Response:
    def __init__(self, status_code: int, text: str = "") -> None:
        self.status_code = status_code
        self.text = text


class FakeGarth:
    def __init__(self, library: "FakeGarminLibrary") -> None:
        self._library = library

    def dump(self, path: str) -> None:
        self._library.dumps.append(path)
        if self._library.dump_error is not None:
            raise self._library.dump_error
        Path(path, "oauth_token.json").write_text("{}", encoding="utf-8")


class FakeGarminLibrary:
    """`library()` liefert das gefälschte Modul; Attribute steuern und zählen."""

    def __init__(self) -> None:
        self.login_error: BaseException | None = None
        self.upload_error: BaseException | None = None
        self.upload_response: object = Response(201, '{"detailedImportResult": {"failures": []}}')
        self.mfa = False  # verlangt Garmin beim Anmelden einen MFA-Code?
        self.has_garth = True  # False: Client ohne Speicherweg (`garth` fehlt, wie womöglich in 0.3.x)
        self.dump_error: BaseException | None = None
        self.clients: list[dict] = []  # Konstruktorargumente je `Garmin(...)`
        self.logins: list[str | None] = []  # tokenstore je `login(...)`
        self.uploads: list[str] = []
        self.mfa_codes: list[str] = []
        self.dumps: list[str] = []

    def __call__(self) -> ModuleType:
        module = ModuleType("garminconnect")
        module.GarminConnectAuthenticationError = GarminConnectAuthenticationError
        module.GarminConnectConnectionError = GarminConnectConnectionError
        module.GarminConnectTooManyRequestsError = GarminConnectTooManyRequestsError
        library = self

        class Garmin:
            def __init__(self, email=None, password=None, prompt_mfa=None, **kwargs) -> None:
                library.clients.append({"email": email, "password": password, **kwargs})
                self._prompt_mfa = prompt_mfa
                if library.has_garth:
                    self.garth = FakeGarth(library)

            def login(self, tokenstore=None):
                library.logins.append(tokenstore)
                if library.mfa and tokenstore is None:
                    library.mfa_codes.append(self._prompt_mfa())
                if library.login_error is not None:
                    raise library.login_error

            def import_activity(self, activity_path):
                library.uploads.append(activity_path)
                if library.upload_error is not None:
                    raise library.upload_error
                return library.upload_response

        module.Garmin = Garmin
        return module


def missing_library() -> ModuleType:
    raise ModuleNotFoundError("No module named 'garminconnect'")
