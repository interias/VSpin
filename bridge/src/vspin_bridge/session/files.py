"""Anlegen der Session-Dateien: `YYYY-MM-DD_HH-MM-SS.csv`, `.raw.jsonl` (ADR-0008), `.control.jsonl` und
`.controller.jsonl` (Spec #89)."""

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .control_log import SessionControl
from .csv_log import SessionCsv
from .raw_log import SessionRaw

# Dateiname in lokaler Zeit; alle Dateien einer Session haben denselben Namen.
NAME_FORMAT = "%Y-%m-%d_%H-%M-%S"
CSV_SUFFIX = ".csv"
RAW_SUFFIX = ".raw.jsonl"
CONTROL_SUFFIX = ".control.jsonl"
CONTROLLER_SUFFIX = ".controller.jsonl"


@dataclass
class Session:
    csv: SessionCsv
    raw: SessionRaw
    control: SessionControl
    controller: SessionControl  # Controller-Rohprotokoll: derselbe JSONL-Schreiber wie das Steuerprotokoll

    def close(self) -> None:
        self.csv.close()
        self.raw.close()
        self.control.close()
        self.controller.close()


def open_session(sessions_dir: Path, now: datetime | None = None) -> Session:
    """Legt `sessions_dir/<zeit>.csv`, `<zeit>.raw.jsonl`, `<zeit>.control.jsonl` und `<zeit>.controller.jsonl` an
    (Verzeichnis bei Bedarf auch).

    Die Roh-Datei gibt es immer – beim Simulator bleibt sie leer (er hat keine rohen
    Notifications), ebenso das Steuerprotokoll ohne Trainer und das Controller-Rohprotokoll ohne Controller. Ist einer
    der Namen schon belegt (zwei Starts in derselben Sekunde), bekommt die neue Session `_2`, `_3`, … angehängt – eine
    vorhandene Datei wird nie überschrieben.
    """
    sessions_dir.mkdir(parents=True, exist_ok=True)
    stem = (now or datetime.now()).strftime(NAME_FORMAT)
    suffix = 1
    while True:
        name = stem if suffix == 1 else f"{stem}_{suffix}"
        suffix += 1
        csv_path, raw_path = sessions_dir / (name + CSV_SUFFIX), sessions_dir / (name + RAW_SUFFIX)
        control_path = sessions_dir / (name + CONTROL_SUFFIX)
        controller_path = sessions_dir / (name + CONTROLLER_SUFFIX)
        opened = []  # (Pfad, Stream) dieser Session, für das Aufräumen bei einem belegten Namen
        try:
            for path, newline in ((csv_path, ""), (raw_path, "\n"), (control_path, "\n"), (controller_path, "\n")):
                opened.append((path, open(path, "x", encoding="utf-8", newline=newline)))
        except FileExistsError:
            for path, stream in opened:
                stream.close()
                path.unlink()
            continue
        except BaseException:
            for _path, stream in opened:
                stream.close()
            raise
        (_, csv_stream), (_, raw_stream), (_, control_stream), (_, controller_stream) = opened
        return Session(
            SessionCsv(csv_path, csv_stream),
            SessionRaw(raw_path, raw_stream),
            SessionControl(control_path, control_stream),
            SessionControl(controller_path, controller_stream),
        )
