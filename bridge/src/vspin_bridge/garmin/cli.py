"""`python -m vspin_bridge.garmin login|status`: einmalige Anmeldung von Hand und Anmeldezustand.

Nur hier wird je ein Passwort benutzt: E-Mail per `input`, Passwort und MFA-Code (nur wenn Garmin ihn
verlangt) per `getpass`. Genau ein Anmeldeversuch; ein Fehlversuch endet mit Meldung und Exit 1, ohne
zweiten Versuch; liegt nach gelungener Anmeldung kein frisch geschriebenes Token im Token-Verzeichnis, Exit 3 –
außer es lag schon eines da und `login()` hat es geladen, ohne neu zu schreiben: „schon angemeldet“, Exit 0.
Ausgegeben werden nie Passwort, MFA-Code, Token oder Fehlertexte der Bibliothek.
"""

import argparse
import contextlib
import getpass
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from types import ModuleType

from .uploader import (
    AUTH_ERROR,
    DEFAULT_TOKEN_DIR,
    INSTALL_HINT,
    TOKEN_FILE,
    TOO_MANY_REQUESTS,
    GarminConnectUploader,
    LoginState,
    import_garminconnect,
    is_error,
    is_network_error,
)

SAVE_FAILED = (
    "Bei Garmin angemeldet, aber das Token konnte nicht gespeichert werden – bitte nicht erneut anmelden; "
    "das ist ein Fehler in VSpin (Bibliotheksversion prüfen)."
)
NO_RETRY = "Nicht sofort wiederholen – nach Fehlversuchen sperrt Garmin das Konto für mehr als 48 h."

STATUS_TEXT = {
    LoginState.LOGGED_IN: "Bei Garmin angemeldet (Token vorhanden: {file}).",
    LoginState.NOT_LOGGED_IN: "Nicht bei Garmin angemeldet. Anmelden: python -m vspin_bridge.garmin login",
    LoginState.UNAVAILABLE: f"Bibliothek garminconnect fehlt. Installieren im Ordner bridge/: {INSTALL_HINT}",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m vspin_bridge.garmin", description="Garmin-Connect-Anmeldung für den Upload der Fahrten"
    )
    parser.add_argument(
        "--token-dir", type=Path, default=DEFAULT_TOKEN_DIR, help=f"Token-Verzeichnis (Standard {DEFAULT_TOKEN_DIR})"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("login", help="einmal im Terminal anmelden; das Token landet im Token-Verzeichnis")
    commands.add_parser("status", help="angemeldet / nicht angemeldet / Bibliothek fehlt")
    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    library: Callable[[], ModuleType] = import_garminconnect,
    input_fn: Callable[[str], str] = input,
    getpass_fn: Callable[[str], str] = getpass.getpass,
) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "status":
        state = GarminConnectUploader(args.token_dir, library).login_state()
        print(STATUS_TEXT[state].format(file=args.token_dir / TOKEN_FILE))
        return 0 if state is LoginState.LOGGED_IN else 1
    return _login(args.token_dir, library, input_fn, getpass_fn)


def _login(
    token_dir: Path,
    library: Callable[[], ModuleType],
    input_fn: Callable[[str], str],
    getpass_fn: Callable[[str], str],
) -> int:
    try:
        lib = library()
    except ImportError:
        print(STATUS_TEXT[LoginState.UNAVAILABLE], file=sys.stderr)
        return 1
    try:
        email = input_fn("Garmin-E-Mail: ").strip()
        password = getpass_fn("Garmin-Passwort: ")
    except (EOFError, KeyboardInterrupt):
        print("\nAnmeldung abgebrochen.", file=sys.stderr)
        return 2
    if not email or not password:
        print("E-Mail und Passwort sind nötig – keine Anmeldung versucht.", file=sys.stderr)
        return 2

    try:
        token_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    except OSError:
        print(f"Token-Verzeichnis {token_dir} lässt sich nicht anlegen – keine Anmeldung versucht.", file=sys.stderr)
        return 1
    before = _token_stamp(token_dir)
    # --- Gegen garminconnect 0.3.x ungeprüft (Bibliothek nicht installiert), aber so in README und example.py
    # des Projekts: `Garmin(email=…, password=…, prompt_mfa=…)` fragt den MFA-Code nur bei Bedarf über
    # `prompt_mfa`; `login(tokenstore)` meldet einmal an und speichert das Token selbst als `garmin_tokens.json`
    # im Token-Verzeichnis (seit 0.3.0 ohne garth). ---
    try:
        client = lib.Garmin(email=email, password=password, prompt_mfa=lambda: getpass_fn("MFA-Code: "))
        client.login(str(token_dir))
    except (EOFError, KeyboardInterrupt):  # an der MFA-Abfrage: das vorab angelegte Verzeichnis darf nicht bleiben
        _remove_if_empty(token_dir)
        print("\nAnmeldung abgebrochen.", file=sys.stderr)
        return 2
    except Exception as exc:
        _remove_if_empty(token_dir)
        print(f"Anmeldung gescheitert: {_reason(lib, exc)} {NO_RETRY}", file=sys.stderr)
        return 1
    after = _token_stamp(token_dir)
    if after is not None and after == before:
        # `login(tokenstore)` lädt ein vorhandenes Token zuerst und kürzt ab, wenn es gilt (README von
        # garminconnect): kein neues Schreiben, aber auch kein Fehler.
        print(f"Schon bei Garmin angemeldet – das vorhandene Token in {token_dir} gilt noch; nichts neu gespeichert.")
        return 0
    # Eigener Schritt: Die Anmeldung bei Garmin ist gelungen; fehlt nur das gespeicherte Token, darf der Nutzer
    # sich nicht erneut anmelden (das wäre die Kette von Fehlversuchen, die das Konto sperrt). Ein Fehler beim
    # Speichern innerhalb von `login()` lässt sich von einer gescheiterten Anmeldung nicht trennen (Exit 1).
    if after is None:
        _remove_if_empty(token_dir)
        print(SAVE_FAILED, file=sys.stderr)
        return 3
    print(f"Angemeldet. Token gespeichert in {token_dir}; die Bridge lädt jede Fahrt ab jetzt selbst hoch.")
    return 0


def _token_stamp(token_dir: Path) -> int | None:
    """Änderungszeit der Token-Datei (`None`, wenn es keine gibt): Ein altes Token aus einer früheren Anmeldung
    zählt nicht als gespeichert."""
    try:
        return (token_dir / TOKEN_FILE).stat().st_mtime_ns
    except OSError:
        return None


def _remove_if_empty(token_dir: Path) -> None:
    """Ein leer gebliebenes Token-Verzeichnis wird wieder entfernt, damit `login_state()` danach nicht `logged_in`
    meldet; vorhandene Token-Dateien bleiben unangetastet."""
    with contextlib.suppress(OSError):
        token_dir.rmdir()


def _reason(lib: ModuleType, exc: BaseException) -> str:
    """Grund ohne den Fehlertext der Bibliothek (er könnte Anfragedaten enthalten)."""
    if is_error(lib, exc, TOO_MANY_REQUESTS):
        return "Garmin meldet zu viele Anmeldeversuche."
    if is_error(lib, exc, AUTH_ERROR):
        return "E-Mail, Passwort oder MFA-Code falsch."
    if is_network_error(lib, exc):
        return "keine Verbindung zu Garmin."
    return f"unerwarteter Fehler ({type(exc).__name__})."
