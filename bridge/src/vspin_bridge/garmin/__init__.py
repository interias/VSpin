"""Garmin-Connect-Upload einer FIT-Datei hinter der Nahtstelle `Uploader` (Spec #84).

Die Bridge kennt nur `Uploader` (`login_state()`, `upload(fit_path)`); dahinter steckt
`GarminConnectUploader` mit der Bibliothek `garminconnect` (optionales Extra `garmin`, lazy importiert),
in Tests eine gefälschte Bibliothek. Angemeldet wird nur von Hand im Terminal
(`python -m vspin_bridge.garmin login`); die Bridge selbst meldet sich nie mit Passwort an, sie setzt
nur das Token im Token-Verzeichnis (Standard `~/.garminconnect`, außerhalb des Repos) über die
Bibliothek fort. Kein Code gibt Passwort, MFA-Code oder Token aus.

Anmeldezustand (`LoginState`, Ergebnis von `login_state()`; reine Existenzprüfung der Token-Datei
`garmin_tokens.json` im Token-Verzeichnis, nie gelesen):

- `logged_in` – Token-Datei vorhanden (ob das Token noch gilt, zeigt erst ein Upload)
- `not_logged_in` – keine Token-Datei (auch wenn das Verzeichnis selbst noch existiert)
- `unavailable` – Bibliothek nicht installiert (`pip install -e ".[garmin]"`)

Upload-Zustand (`UploadState`, in `UploadResult.state`, dazu eine deutsche `message` für den Dialog):

- `uploaded` – hochgeladen
- `duplicate` – Garmin kennt die Fahrt schon (HTTP 409 / „Duplicate Activity“); zählt als Erfolg
- `not_logged_in` – keine Token-Datei; kein Aufruf bei Garmin
- `auth_expired` – „Anmeldung abgelaufen – bitte neu anmelden“ (Anmeldefehler, HTTP 401/403)
- `rejected` – sonstiger 4xx-Fehler, auch 429 (zu viele Anfragen)
- `failed` – Netzfehler, 5xx oder Unbekanntes; die FIT-Datei bleibt für den manuellen Import liegen
- `unavailable` – Bibliothek nicht installiert

Schonung des Kontos: höchstens ein Upload-Versuch je `upload()`-Aufruf, nichts wird wiederholt –
nach Fehlversuchen sperrt Garmin Konten für mehr als 48 h.
"""

from .uploader import (
    DEFAULT_TOKEN_DIR,
    INSTALL_HINT,
    TOKEN_FILE,
    GarminConnectUploader,
    LoginState,
    Uploader,
    UploadResult,
    UploadState,
)

__all__ = [
    "DEFAULT_TOKEN_DIR",
    "INSTALL_HINT",
    "TOKEN_FILE",
    "GarminConnectUploader",
    "LoginState",
    "UploadResult",
    "UploadState",
    "Uploader",
]
