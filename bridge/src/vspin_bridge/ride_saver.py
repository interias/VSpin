"""Fahrt speichern am Bus (Spec #84, ADR-0008 Nachtrag „Fahrt speichern“).

Das Spiel kennt die Fahrt (Start, Ende, Runden, Streckenspur), nur die Bridge die Telemetrie (ADR-0008: nur die
Bridge loggt). Auf `save_ride` schreibt die Bridge deshalb die FIT-Datei der Fahrt aus der laufenden Session-CSV
und lädt sie auf Wunsch einmal zu Garmin Connect hoch; die Bridge (`app.py`) reicht nur durch:

- **Fahrtablage** `<sessions_dir>/rides/`: je Fahrt `<zeit>_<ride_id>.fit` (`<zeit>` = Start der Fahrt in
  Ortszeit), dazu `rides.json` mit dem Wanduhr-Anker, dem Namen der Session-CSV und der Upload-Marke je
  `ride_id`. Erneutes Speichern derselben `ride_id` im selben Bridge-Lauf schreibt dieselbe Datei neu – bei
  gleichen Angaben Byte für Byte gleich, weil der Anker des ersten Speicherns gilt. Ein **anderer** Bridge-Lauf
  baut sie nie neu: Seine Session-CSV hat andere Samples unter denselben Bridge-Zeiten (die Bridge-Zeit beginnt
  je Lauf bei 0). Er nimmt die vorhandene Datei, auch für den Upload; fehlt sie, gibt es keine.
- **Antwort** `ride_saved` nur an den Absender, erst wenn Datei und Upload fertig sind. Es gibt kein `ack`;
  ungültige Befehle beantwortet die Bridge sofort mit `error` (`bus/messages.py`).
- **Nichts blockiert:** FIT-Bau, Schreiben und Upload laufen in einem Thread (`asyncio.to_thread`); Telemetrie
  und Bus laufen weiter, auch die weiteren Nachrichten des Absenders. Nur das Lesen der Session-CSV läuft im
  Event-Loop, weil dort auch geschrieben wird (sonst könnte eine halbe Zeile gelesen werden). Ein Speichern zur
  Zeit; weitere warten, damit dieselbe Fahrt nie zweimal gleichzeitig hochgeladen wird.
- **Schonung des Kontos:** höchstens ein Upload-Versuch je `save_ride`, nichts wird wiederholt. Erfolg
  (`uploaded`, `duplicate`) setzt die Upload-Marke; danach lädt erneutes Speichern nicht mehr hoch
  (`already_uploaded`). Ein gescheiterter Upload setzt sie nicht: Erneutes Speichern ist eine bewusste Handlung
  und darf es noch einmal versuchen.
- **Anmeldezustand** (`status.garmin.login`): `Uploader.login_state()`, geprüft beim Start, nach jedem
  `save_ride` und alle `LOGIN_CHECK_S` (Anmeldung im Terminal, während die Bridge läuft); eine Änderung geht
  genau einmal als `status` an alle.
"""

import asyncio
import contextlib
import json
import os
from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path

from .bus.messages import SaveRide, error_message, ride_saved_message
from .clock import bridge_time_ms
from .console import Console
from .export import FitToolMissingError, build_ride_fit, read_session_samples
from .garmin import LoginState, Uploader
from .session.files import NAME_FORMAT

RIDES_DIR = "rides"
INDEX_FILE = "rides.json"
LOGIN_CHECK_S = 5.0

SKIPPED = ("skipped", "Nicht hochgeladen – der Upload ist für diese Fahrt abgeschaltet.")
ALREADY_UPLOADED = ("already_uploaded", "Die Fahrt ist schon in Garmin Connect – nicht erneut hochgeladen.")

Client = object  # undurchsichtiger Verweis auf einen Bus-Client (`BusServer.sender()`)


class RideSaver:
    def __init__(
        self,
        sessions_dir: Path,
        uploader: Uploader,
        send_to: Callable[[Client, str], None],
        on_login_changed: Callable[[LoginState], None],
        console: Console,
    ) -> None:
        self.rides_dir = sessions_dir / RIDES_DIR
        self.session_csv: Path | None = None  # Session-CSV dieses Bridge-Laufs; setzt die Bridge
        self._uploader = uploader
        self._send_to = send_to
        self._on_login_changed = on_login_changed
        self._console = console
        self.login = uploader.login_state()
        self._lock = asyncio.Lock()
        self._tasks: set[asyncio.Task] = set()
        self._timer: asyncio.TimerHandle | None = None
        self._index: dict[str, dict] | None = None  # `rides.json`, beim ersten Speichern geladen

    def start(self) -> None:
        self._timer = asyncio.get_running_loop().call_later(LOGIN_CHECK_S, self._poll_login)

    async def stop(self) -> None:
        """Wartet laufende Speichervorgänge ab: ein Upload im Thread lässt sich nicht abbrechen, und seine
        Upload-Marke muss noch in die Fahrtablage."""
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None
        if self._tasks:
            self._console.info("Warte auf das laufende Speichern der Fahrt …")
            await asyncio.gather(*self._tasks, return_exceptions=True)

    def handle(self, command: SaveRide, sender: Client | None) -> str | None:
        """Startet das Speichern; `ride_saved` geht später nur an `sender`. Liegt das Ende einer unbekannten Fahrt
        nach der Bridge-Zeit, stammt sie aus einem früheren Bridge-Lauf (die Bridge-Zeit beginnt je Lauf bei 0):
        sofort `error`, denn ihre Samples stehen nicht in dieser Session-CSV. Kennt die Fahrtablage die Fahrt aus
        einem früheren Lauf, gilt deren Datei, die Bridge-Zeit spielt dann keine Rolle."""
        now = bridge_time_ms()
        if command.end_t_ms > now and not self._from_other_run(self._load_index().get(command.ride_id)):
            detail = f"'end_t_ms' {command.end_t_ms} nach der Bridge-Zeit {now} – Fahrt aus einem früheren Lauf?"
            return error_message("invalid_ride", detail)
        task = asyncio.create_task(self._save(command, sender))
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return None

    def check_login(self) -> None:
        state = self._uploader.login_state()
        if state != self.login:
            self.login = state
            self._on_login_changed(state)

    def _poll_login(self) -> None:
        self.check_login()
        self._timer = asyncio.get_running_loop().call_later(LOGIN_CHECK_S, self._poll_login)

    async def _save(self, command: SaveRide, sender: Client | None) -> None:
        async with self._lock:
            try:
                reply = await self._save_ride(command)
            except Exception as exc:  # unerwartet: Meldung an den Absender, die Bridge läuft weiter
                self._console.info(f"Fahrt {command.ride_id}: Speichern gescheitert ({type(exc).__name__}: {exc})")
                detail = f"FIT-Datei nicht geschrieben: unerwarteter Fehler ({type(exc).__name__})."
                reply = ride_saved_message(command.ride_id, None, detail, None)
        if sender is not None:
            self._send_to(sender, reply)
        self.check_login()  # der Upload kann gezeigt haben, dass sich etwas geändert hat

    async def _save_ride(self, command: SaveRide) -> str:
        if self.session_csv is None:
            return ride_saved_message(command.ride_id, None, "FIT-Datei nicht geschrieben: keine Session-CSV.", None)
        entry = self._entry(command)
        path = self.rides_dir / entry["fit"]
        if self._from_other_run(entry):
            if not path.is_file():
                self._console.info(f"Fahrt {command.ride_id}: FIT-Datei {path} aus einem früheren Bridge-Lauf fehlt")
                return ride_saved_message(command.ride_id, None, missing_file(entry["fit"]), None)
            self._console.info(f"Fahrt {command.ride_id}: FIT-Datei aus einem früheren Bridge-Lauf, nicht neu gebaut")
        else:
            reply = await self._write_fit(command, entry, path)
            if reply is not None:
                return reply
        fit_path = str(path.absolute())
        self._console.info(f"Fahrt {command.ride_id} gespeichert: {fit_path}")

        if not command.upload:
            upload = SKIPPED
        elif entry.get("uploaded"):
            upload = ALREADY_UPLOADED
        else:
            result = await asyncio.to_thread(self._uploader.upload, path)  # genau ein Versuch, blockierend
            if result.ok:
                entry["uploaded"] = True
                self._write_index()
            upload = (str(result.state), result.message)
        self._console.info(f"Fahrt {command.ride_id}: Garmin {upload[0]}")
        return ride_saved_message(command.ride_id, fit_path, None, upload)

    async def _write_fit(self, command: SaveRide, entry: dict, path: Path) -> str | None:
        """Baut die FIT-Datei aus der Session-CSV dieses Laufs; `ride_saved` ohne Datei, wenn das scheitert."""
        try:
            samples = read_session_samples(self.session_csv, command.start_t_ms, command.end_t_ms)
            data = await asyncio.to_thread(
                build_ride_fit,
                ride_id=command.ride_id,
                start_t_ms=command.start_t_ms,
                end_t_ms=command.end_t_ms,
                wall_clock_at_zero=datetime.fromisoformat(entry["wall_clock_at_zero"]),
                samples=samples,
                distance_track=command.distance,
                lap_end_t_ms=command.lap_end_t_ms,
            )
            await asyncio.to_thread(_write_file, path, data)
        except FitToolMissingError as exc:
            self._console.info(f"Fahrt {command.ride_id}: {exc}")
            return ride_saved_message(command.ride_id, None, str(exc), None)
        except OSError as exc:
            detail = exc.strerror or str(exc)
            self._console.info(f"Fahrt {command.ride_id}: FIT-Datei nicht geschrieben ({detail})")
            return ride_saved_message(command.ride_id, None, f"FIT-Datei nicht geschrieben: {detail}.", None)
        return None

    def _from_other_run(self, entry: dict | None) -> bool:
        """Stammt der Eintrag aus einem anderen Bridge-Lauf (andere Session-CSV)? Dann darf diese Session-CSV
        die Datei nicht neu bauen."""
        current = None if self.session_csv is None else self.session_csv.name
        return entry is not None and entry["session_csv"] != current

    def _entry(self, command: SaveRide) -> dict:
        """Eintrag der Fahrt in `rides.json`; beim ersten Speichern mit Wanduhr-Anker, Dateinamen und der
        Session-CSV dieses Laufs."""
        index = self._load_index()
        entry = index.get(command.ride_id)
        if entry is None:
            anchor = datetime.now().astimezone() - timedelta(milliseconds=bridge_time_ms())
            start = anchor + timedelta(milliseconds=command.start_t_ms)
            entry = {
                "fit": f"{start.strftime(NAME_FORMAT)}_{command.ride_id}.fit",
                "wall_clock_at_zero": anchor.isoformat(),
                "session_csv": self.session_csv.name,
                "uploaded": False,
            }
            index[command.ride_id] = entry
            self._write_index()
        return entry

    def _load_index(self) -> dict[str, dict]:
        if self._index is None:
            self._index = {}
            path = self.rides_dir / INDEX_FILE
            try:
                loaded = json.loads(path.read_text(encoding="utf-8"))
            except FileNotFoundError:
                return self._index
            except (OSError, ValueError) as exc:
                self._console.info(f"{path} nicht lesbar ({exc}) – Fahrtablage beginnt neu")
                return self._index
            if isinstance(loaded, dict):
                self._index = {
                    ride_id: entry
                    for ride_id, entry in loaded.items()
                    if isinstance(entry, dict) and _valid_entry(entry)
                }
        return self._index

    def _write_index(self) -> None:
        """Schreibt `rides.json` (über eine Zwischendatei, nie halb). Scheitert das, gilt der Stand im Speicher
        für diesen Bridge-Lauf weiter; die Meldung steht im Terminal."""
        try:
            data = json.dumps(self._index, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
            _write_file(self.rides_dir / INDEX_FILE, data.encode("utf-8"))
        except OSError as exc:
            self._console.info(f"Fahrtablage {self.rides_dir / INDEX_FILE} nicht geschrieben ({exc.strerror or exc})")


def missing_file(name: str) -> str:
    return (
        f"FIT-Datei {name} fehlt in der Fahrtablage. Die Fahrt stammt aus einem früheren Bridge-Lauf und lässt "
        "sich nicht neu schreiben – ihre Samples stehen nicht in dieser Session."
    )


def _valid_entry(entry: dict) -> bool:
    if not isinstance(entry.get("fit"), str) or not isinstance(entry.get("uploaded"), bool):
        return False
    if not isinstance(entry.get("session_csv"), str):
        return False
    if Path(entry["fit"]).name != entry["fit"]:
        return False  # nur ein Dateiname in der Fahrtablage, kein Pfad
    try:
        anchor = datetime.fromisoformat(entry["wall_clock_at_zero"])
    except (TypeError, ValueError):
        return False
    return anchor.utcoffset() is not None


def _write_file(path: Path, data: bytes) -> None:
    """Schreibt über eine Zwischendatei: Eine vorhandene Datei wird erst ersetzt, wenn die neue ganz da ist."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_bytes(data)
        os.replace(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            tmp.unlink()
        raise
