"""Samples einer Fahrt aus der Session-CSV (ADR-0008) lesen.

Braucht kein fit-tool: Der Leser liefert nur die Werte, die der Export braucht (Kadenz, Leistung samt
Herkunft, Puls). Geschwindigkeit und Strecke kommen nicht aus der CSV, sondern vom Spiel (Streckenspur,
siehe `fit.build_ride_fit`) – der JC312 meldet keine Geschwindigkeit (`parsers/csc.py`).
"""

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class RideSample:
    """Eine Zeile der Session-CSV, reduziert auf den Export. Fehlende Werte (leere Felder) sind `None`.

    `t_ms` ist die monotone Bridge-Zeit (`clock.bridge_time_ms`), `cadence` der geglättete Wert wie am
    Bus (ADR-0004). `power_estimated`: `True` = estimated, `False` = measured, `None` = keine Angabe.
    """

    t_ms: int
    cadence: float | None = None
    power_w: float | None = None
    power_estimated: bool | None = None
    hr_bpm: int | None = None


def read_session_samples(csv_path: Path, start_t_ms: int, end_t_ms: int) -> list[RideSample]:
    """Samples der Session-CSV im Zeitfenster der Fahrt, in Dateireihenfolge.

    Das Fenster ist **an beiden Enden inklusiv**: `start_t_ms <= t_ms <= end_t_ms`; alles davor und
    danach fällt weg. Beide Grenzen sind Bridge-Zeit derselben Session.
    """
    if end_t_ms < start_t_ms:
        raise ValueError(f"Fahrt endet vor ihrem Start: {start_t_ms} > {end_t_ms}")
    samples = []
    with open(csv_path, encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream):
            t_ms = int(row["t_ms"])
            if start_t_ms <= t_ms <= end_t_ms:
                samples.append(
                    RideSample(
                        t_ms=t_ms,
                        cadence=_number(row["cadence"]),
                        power_w=_number(row["power_w"]),
                        power_estimated=_flag(row["power_estimated"]),
                        hr_bpm=None if row["hr_bpm"] == "" else int(row["hr_bpm"]),
                    )
                )
    return samples


def _number(value: str) -> float | None:
    return None if value == "" else float(value)


def _flag(value: str) -> bool | None:
    return None if value == "" else value == "true"  # Schreibweise wie am Bus (`csv_log._field`)
