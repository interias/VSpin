"""Session-Logging (ADR-0008): pro Bridge-Lauf eine Datei unter `sessions/`.

Bewusst `session` statt des in bridge/README.md geplanten `logging`: ein Unterpaket
`vspin_bridge.logging` wäre zwar technisch möglich, liest sich aber wie die stdlib
und lädt zu Verwechslungen ein (`from . import logging`). „Session“ ist der Begriff
aus CONTEXT.md.
"""

from .csv_log import CSV_COLUMNS, SessionCsv, open_session_csv

__all__ = ["CSV_COLUMNS", "SessionCsv", "open_session_csv"]
