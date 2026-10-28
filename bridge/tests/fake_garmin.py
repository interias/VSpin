"""Skriptbare Fälschung des Moduls `garminconnect` für `GarminConnectUploader` und die Garmin-CLI – kein Netz.

Bildet nur die angenommene API nach (gegen garminconnect 0.3.x ungeprüft, siehe `vspin_bridge.garmin.uploader`;
so in README und example.py des Projekts): `Garmin(email=…, password=…, prompt_mfa=…)`, `login(tokenstore=None)`
– mit Zugangsdaten meldet es an und speichert das Token selbst als `garmin_tokens.json` im Token-Verzeichnis
(seit 0.3.0 ohne garth), ohne setzt es nur das gespeicherte Token fort –, `import_activity(pfad)` und die
Ausnahmeklassen. Liegt im `tokenstore` schon ein Token, lädt `login` es zuerst und kürzt ab, ohne anzumelden oder
zu schreiben (README: „short-circuits if they load“); ein abgelehntes Token (`tokens_valid = False`) führt zur
Anmeldung mit Zugangsdaten. Was bei `login` bzw. `import_activity` passiert, gibt der Test vor (`login_error`,
`upload_error`, `upload_response`, `mfa`, `saves_token`, `tokens_valid`); die Fälschung zählt jeden Aufruf mit.
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


class FakeGarminLibrary:
    """`library()` liefert das gefälschte Modul; Attribute steuern und zählen."""

    def __init__(self) -> None:
        self.login_error: BaseException | None = None
        self.upload_error: BaseException | None = None
        self.upload_response: object = Response(201, '{"detailedImportResult": {"failures": []}}')
        self.mfa = False  # verlangt Garmin beim Anmelden einen MFA-Code?
        self.saves_token = True  # False: `login(tokenstore)` meldet an, schreibt aber kein Token (andere API)
        self.tokens_valid = True  # False: Garmin lehnt ein gespeichertes Token ab
        self.clients: list[dict] = []  # Konstruktorargumente je `Garmin(...)`
        self.logins: list[str | None] = []  # tokenstore je `login(...)`
        self.uploads: list[str] = []
        self.mfa_codes: list[str] = []
        self.saved: list[str] = []  # Token-Verzeichnis je gespeichertem Token
        self.resumed: list[str] = []  # Token-Verzeichnis je Kurzschluss über ein geladenes Token

    def __call__(self) -> ModuleType:
        module = ModuleType("garminconnect")
        module.GarminConnectAuthenticationError = GarminConnectAuthenticationError
        module.GarminConnectConnectionError = GarminConnectConnectionError
        module.GarminConnectTooManyRequestsError = GarminConnectTooManyRequestsError
        library = self

        class Garmin:
            def __init__(self, email=None, password=None, prompt_mfa=None, **kwargs) -> None:
                library.clients.append({"email": email, "password": password, **kwargs})
                self._email = email
                self._prompt_mfa = prompt_mfa

            def login(self, tokenstore=None):
                library.logins.append(tokenstore)
                stored = tokenstore is not None and Path(tokenstore, "garmin_tokens.json").is_file()
                if stored and library.tokens_valid and library.login_error is None:
                    library.resumed.append(tokenstore)
                    return  # vorhandenes Token geladen: keine Anmeldung, kein Schreiben
                if library.mfa and self._email is not None:
                    library.mfa_codes.append(self._prompt_mfa())
                if library.login_error is not None:
                    raise library.login_error
                if self._email is not None and tokenstore is not None and library.saves_token:
                    library.saved.append(tokenstore)
                    Path(tokenstore, "garmin_tokens.json").write_text("{}", encoding="utf-8")

            def import_activity(self, activity_path):
                library.uploads.append(activity_path)
                if library.upload_error is not None:
                    raise library.upload_error
                return library.upload_response

        module.Garmin = Garmin
        return module


def missing_library() -> ModuleType:
    raise ModuleNotFoundError("No module named 'garminconnect'")
