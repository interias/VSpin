"""Export einer Fahrt als FIT-Aktivität (Spec #84, ADR-0008).

`read_session_samples` liest die Samples einer Fahrt aus der Session-CSV, `build_ride_fit` baut daraus
und aus den Angaben des Spiels (Rundenenden, Streckenspur) die `.fit`-Datei. Das Paket importiert
fit-tool nicht beim Laden; erst `build_ride_fit` braucht es und wirft sonst `FitToolMissingError`.
"""

from .fit import FitToolMissingError, build_ride_fit, serial_number
from .samples import RideSample, read_session_samples

__all__ = ["FitToolMissingError", "RideSample", "build_ride_fit", "read_session_samples", "serial_number"]
