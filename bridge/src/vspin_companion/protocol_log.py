"""Protokoll des Begleiters (#79, ADR-0008 Nachtrag #76): Antwortzeiten und Sprachkosten, eine JSON-Zeile je Eintrag
in `<Ablage>/protocol.jsonl` (Ablage unter `%APPDATA%/VSpin/companion/`). Kein Audio, kein Text der Gespräche.

Einträge (`type`):
- `answer`: je Antwort auf eine Frage – `latency_s` vom Loslassen der Sprechtaste bis zum ersten Ton,
  `within_target` (Ziel `TARGET_LATENCY_S`).
- `ride`: je Fahrt, bei `ride_end` – `answers`, `latency_avg_s`/`latency_max_s`/`over_target`, gesprochene `chars`,
  `requests` an die Stimme, `generations` (IDs mit `X-Generation-Id`), `total_cost_usd` und `unknown_generations`.
  Die Kosten liefert OpenRouter erst kurz nach der Synthese: Sind sie noch nicht da, steht `cost: "pending"` und
  `total_cost_usd: null`; `ride_cost` folgt, sobald sie abgeholt sind. Was OpenRouter nie liefert, bleibt
  „unbekannt“ (`unknown_generations`) – es wird nie geschätzt.
- `ride_cost`: Nachtrag zu `ride` (`ride_end_at`), mit `total_cost_usd` (Summe der bekannten) und
  `unknown_generations`. Endet der Prozess vor dem Abruf, fragt er ein letztes Mal ohne Wartezeit und schreibt, was
  dann bekannt ist.
- `aborted_requests` (in `ride` und `ride_cost`): abgebrochene Synthesen (Barge-in). OpenRouter berechnet sie womöglich,
  ihre Generation-ID kennen wir nicht – bei `lower_bound: true` ist `total_cost_usd` nur eine Untergrenze.
"""

import json
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

PROTOCOL_FILE = "protocol.jsonl"
TARGET_LATENCY_S = 2.5  # Story 4: Antwort nach höchstens etwa 2,5 s zu hören


class ProtocolLog:
    def __init__(self, data_dir: Path, log: Callable[[str], None] = lambda text: None) -> None:
        self._path = data_dir / PROTOCOL_FILE
        self._log = log

    def write(self, record: dict) -> str:
        """Hängt `record` mit Zeitstempel (UTC) an; liefert den Zeitstempel. Ein Schreibfehler bricht nichts ab."""
        at = datetime.now(timezone.utc).isoformat(timespec="seconds")
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            with self._path.open("a", encoding="utf-8") as file:
                file.write(json.dumps({"at": at, **record}, ensure_ascii=False) + "\n")
        except OSError as exc:
            self._log(f"Protokoll nicht geschrieben – {type(exc).__name__}: {exc}")
        return at
