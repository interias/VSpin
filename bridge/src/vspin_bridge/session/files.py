"""Anlegen der Session-Dateien: `YYYY-MM-DD_HH-MM-SS.csv` und `.raw.jsonl` (ADR-0008)."""

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .csv_log import SessionCsv
from .raw_log import SessionRaw

# Dateiname in lokaler Zeit; beide Dateien einer Session haben denselben Namen.
NAME_FORMAT = "%Y-%m-%d_%H-%M-%S"
CSV_SUFFIX = ".csv"
RAW_SUFFIX = ".raw.jsonl"


@dataclass
class Session:
    csv: SessionCsv
    raw: SessionRaw

    def close(self) -> None:
        self.csv.close()
        self.raw.close()


def open_session(sessions_dir: Path, now: datetime | None = None) -> Session:
    """Legt `sessions_dir/<zeit>.csv` und `<zeit>.raw.jsonl` an (Verzeichnis bei Bedarf auch).

    Die Roh-Datei gibt es immer – beim Simulator bleibt sie leer (er hat keine rohen
    Notifications). Ist einer der beiden Namen schon belegt (zwei Starts in derselben
    Sekunde), bekommt die neue Session `_2`, `_3`, … angehängt – eine vorhandene Datei wird
    nie überschrieben.
    """
    sessions_dir.mkdir(parents=True, exist_ok=True)
    stem = (now or datetime.now()).strftime(NAME_FORMAT)
    suffix = 1
    while True:
        name = stem if suffix == 1 else f"{stem}_{suffix}"
        suffix += 1
        csv_path, raw_path = sessions_dir / (name + CSV_SUFFIX), sessions_dir / (name + RAW_SUFFIX)
        try:
            csv_stream = open(csv_path, "x", encoding="utf-8", newline="")
        except FileExistsError:
            continue
        try:
            raw_stream = open(raw_path, "x", encoding="utf-8", newline="\n")
        except FileExistsError:
            csv_stream.close()
            csv_path.unlink()
            continue
        except BaseException:
            csv_stream.close()
            raise
        return Session(SessionCsv(csv_path, csv_stream), SessionRaw(raw_path, raw_stream))
