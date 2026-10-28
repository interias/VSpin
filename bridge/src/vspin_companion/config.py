"""Ablage und Konfiguration des Begleiters (ADR-0008, Nachtrag #76): `%APPDATA%\\VSpin\\companion\\`, nie im Repo.

Die Ablage hält `companion.json` (hier), später `soul.md`, `memory.md`, `.bak`-Sicherungen und das Protokoll
(#78/#79). Tests lenken sie mit `--data-dir` oder `VSPIN_COMPANION_DIR` um, nie in das echte `%APPDATA%`.
"""

import json
import os
from dataclasses import dataclass, fields
from pathlib import Path

DATA_DIR_ENV = "VSPIN_COMPANION_DIR"
CONFIG_FILE = "companion.json"

BRAINS = ("oauth", "api_key")  # ADR-0011: Standard Abo-OAuth, API-Schlüssel nur per Einstellung
WAKE_MINUTES_MIN = 1
WAKE_MINUTES_MAX = 30


class ConfigError(Exception):
    """`companion.json` ist kaputt oder hat einen ungültigen Wert."""


@dataclass(frozen=True, slots=True)
class CompanionConfig:
    brain: str = "oauth"
    wake_min_minutes: float = 3  # Wecker: zufälliger Abstand zwischen min und max (Spec #76, #78)
    wake_max_minutes: float = 8
    voice_model: str = "elevenlabs/eleven-v4-turbo"  # Mouth über OpenRouter (#79)
    voice: str = "charlie"


def default_data_dir(env: dict[str, str] | None = None) -> Path:
    """`VSPIN_COMPANION_DIR`, sonst `%APPDATA%\\VSpin\\companion` (ohne `APPDATA`: `~/.config/VSpin/companion`)."""
    env = os.environ if env is None else env
    if env.get(DATA_DIR_ENV):
        return Path(env[DATA_DIR_ENV])
    base = Path(env["APPDATA"]) if env.get("APPDATA") else Path.home() / ".config"
    return base / "VSpin" / "companion"


def load_config(data_dir: Path) -> CompanionConfig:
    """Liest `companion.json` aus `data_dir`; fehlt die Datei, gelten die Standardwerte. Unbekannte Schlüssel
    werden ignoriert (spätere Pakete ergänzen sie). Schreibt nichts."""
    path = data_dir / CONFIG_FILE
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return CompanionConfig()
    except OSError as exc:
        raise ConfigError(f"{path}: {exc.strerror or exc}") from exc
    try:
        raw = json.loads(text)
    except ValueError as exc:
        raise ConfigError(f"{path}: kein gültiges JSON: {exc}") from None
    if not isinstance(raw, dict):
        raise ConfigError(f"{path}: erwartet ein JSON-Objekt")
    config = CompanionConfig(**{f.name: raw[f.name] for f in fields(CompanionConfig) if f.name in raw})
    _check(config, path)
    return config


def _check(config: CompanionConfig, path: Path) -> None:
    if config.brain not in BRAINS:
        raise ConfigError(f"{path}: 'brain' muss {' oder '.join(BRAINS)} sein, war {config.brain!r}")
    for name in ("wake_min_minutes", "wake_max_minutes"):
        value = getattr(config, name)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not (
            WAKE_MINUTES_MIN <= value <= WAKE_MINUTES_MAX
        ):
            raise ConfigError(f"{path}: {name!r} muss {WAKE_MINUTES_MIN}–{WAKE_MINUTES_MAX} sein, war {value!r}")
    if config.wake_min_minutes > config.wake_max_minutes:
        raise ConfigError(f"{path}: 'wake_min_minutes' ist größer als 'wake_max_minutes'")
    for name in ("voice_model", "voice"):
        value = getattr(config, name)
        if not isinstance(value, str) or not value:
            raise ConfigError(f"{path}: {name!r} muss ein nicht leerer Text sein, war {value!r}")
