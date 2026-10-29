"""Session-Logging (ADR-0008): pro Bridge-Lauf vier Dateien unter `sessions/` –
`<zeit>.csv` (eine Zeile pro Sample am Bus), `<zeit>.raw.jsonl` (rohe Notifications), `<zeit>.control.jsonl`
(Steuerprotokoll des Trainers, Spec #89) und `<zeit>.controller.jsonl` (Rohprotokoll des Lenkercontrollers, Spec #89).

Bewusst `session` statt des in bridge/README.md geplanten `logging`: ein Unterpaket
`vspin_bridge.logging` wäre zwar technisch möglich, liest sich aber wie die stdlib
und lädt zu Verwechslungen ein (`from . import logging`). „Session“ ist der Begriff
aus CONTEXT.md.
"""

from .control_log import SessionControl, control_line
from .csv_log import CSV_COLUMNS, SessionCsv
from .files import Session, open_session
from .raw_log import SessionRaw, raw_line

__all__ = [
    "CSV_COLUMNS",
    "Session",
    "SessionControl",
    "SessionCsv",
    "SessionRaw",
    "control_line",
    "open_session",
    "raw_line",
]
