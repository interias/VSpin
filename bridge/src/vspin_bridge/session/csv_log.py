"""Session-CSV: eine Zeile pro Sample, das auf den Bus geht (ADR-0008).

Kopfzeile ohne Leerzeichen (übliche CSV-Form; die Schreibweise mit Leerzeichen in
ADR-0008 ist Fließtext). Fehlende Werte sind leere Felder. Zeilenende `\\n` auf
allen Plattformen, UTF-8. Jede Zeile wird sofort geschrieben und geflusht – auch ein
harter Abbruch hinterlässt nur ganze Zeilen.
"""

import csv
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


class SessionCsv:
    def __init__(self, path: Path, stream: TextIO) -> None:
        self.path = path
        self._stream = stream
        self._writer = csv.writer(stream, lineterminator="\n")
        self._write(CSV_COLUMNS)

    def write(
        self, sample: TelemetrySample, cadence_raw: float | None, grade: float | None, status: str
    ) -> None:
        """`sample` wie am Bus (Kadenz geglättet), `cadence_raw` der Rohwert der Quelle
        (`processing`, ADR-0004)."""
        self._write(
            (
                sample.t_ms,
                _field(cadence_raw),
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


def _field(value: float | bool | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"  # wie am Bus (JSON)
    return repr(value)  # gleiche Darstellung wie am Bus (json.dumps nutzt repr)
