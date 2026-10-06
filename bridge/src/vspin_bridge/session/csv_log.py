"""Session-CSV: eine Zeile pro Sample, das auf den Bus geht (ADR-0008).

Kopfzeile ohne Leerzeichen (übliche CSV-Form; die Schreibweise mit Leerzeichen in
ADR-0008 ist Fließtext). Fehlende Werte sind leere Felder. Zeilenende `\\n` auf
allen Plattformen, UTF-8. Jede Zeile wird sofort geschrieben und geflusht – auch ein
harter Abbruch hinterlässt nur ganze Zeilen.
"""

import csv
from datetime import datetime
from pathlib import Path
from typing import TextIO

from ..sources.base import TelemetrySample

CSV_COLUMNS = (
    "t_ms",
    "cadence_raw",
    "cadence",
    "speed_kmh",
    "power_w",
    "power_estimated",
    "hr_bpm",
    "grade",
    "status",
)

# Dateiname in lokaler Zeit; der Session-Name (ohne Endung) ist für spätere
# Begleitdateien derselben Session gedacht (ADR-0008: `.raw.jsonl`).
NAME_FORMAT = "%Y-%m-%d_%H-%M-%S"


class SessionCsv:
    def __init__(self, path: Path, stream: TextIO) -> None:
        self.path = path
        self._stream = stream
        self._writer = csv.writer(stream, lineterminator="\n")
        self._write(CSV_COLUMNS)

    def write(self, sample: TelemetrySample, grade: float | None, status: str) -> None:
        # Glättung (EMA, ADR-0004) gibt es noch nicht: roh und geglättet sind gleich.
        # Mit der Glättung ändert sich nur die Quelle von `cadence_raw`.
        self._write(
            (
                sample.t_ms,
                _field(sample.cadence),
                _field(sample.cadence),
                _field(sample.speed_kmh),
                _field(sample.power_w),
                _field(sample.power_estimated),
                _field(sample.heart_rate),
                _field(grade),
                status,
            )
        )

    def close(self) -> None:
        if not self._stream.closed:
            self._stream.close()

    def _write(self, row) -> None:
        self._writer.writerow(row)
        self._stream.flush()  # ganze Zeile sofort ins OS – übersteht auch SIGKILL


def open_session_csv(sessions_dir: Path, now: datetime | None = None) -> SessionCsv:
    """Legt `sessions_dir/YYYY-MM-DD_HH-MM-SS.csv` an (Verzeichnis bei Bedarf auch).

    Existiert der Name schon (zwei Starts in derselben Sekunde), bekommt die neue
    Session `_2`, `_3`, … angehängt – eine vorhandene Datei wird nie überschrieben.
    """
    sessions_dir.mkdir(parents=True, exist_ok=True)
    stem = (now or datetime.now()).strftime(NAME_FORMAT)
    suffix = 1
    while True:
        path = sessions_dir / (f"{stem}.csv" if suffix == 1 else f"{stem}_{suffix}.csv")
        try:
            stream = open(path, "x", encoding="utf-8", newline="")
        except FileExistsError:
            suffix += 1
            continue
        return SessionCsv(path, stream)


def _field(value: float | bool | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"  # wie am Bus (JSON)
    return repr(value)  # gleiche Darstellung wie am Bus (json.dumps nutzt repr)
