"""Session-Logging (ADR-0008): pro Bridge-Lauf zwei Dateien unter `sessions/` –
`<zeit>.csv` (eine Zeile pro Sample am Bus) und `<zeit>.raw.jsonl` (rohe Notifications).

Bewusst `session` statt des in bridge/README.md geplanten `logging`: ein Unterpaket
`vspin_bridge.logging` wäre zwar technisch möglich, liest sich aber wie die stdlib
und lädt zu Verwechslungen ein (`from . import logging`). „Session“ ist der Begriff
aus CONTEXT.md.
"""

from .csv_log import CSV_COLUMNS, SessionCsv
from .files import Session, open_session
from .raw_log import SessionRaw, raw_line

__all__ = ["CSV_COLUMNS", "Session", "SessionCsv", "SessionRaw", "open_session", "raw_line"]
