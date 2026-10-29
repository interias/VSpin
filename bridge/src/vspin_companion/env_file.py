"""Geheimnisse des Begleiters (ADR-0011): aus der Umgebung, sonst aus `<Ablage>/.env`.

Die `.env` liegt nur in der Ablage (`%APPDATA%\\VSpin\\companion\\.env`, ADR-0008 Nachtrag #76) – nie im Repo und
nie im Arbeitsverzeichnis; eine `.env` dort wird nie gelesen. Kleiner eigener Parser, keine Abhängigkeit.
"""

import os
from pathlib import Path

ENV_FILE = ".env"


def load_secret(name: str, data_dir: Path, env: dict[str, str] | None = None) -> str | None:
    """Wert von `name` aus der Umgebung, sonst aus `<data_dir>/.env`; fehlt er überall (oder ist leer): `None`."""
    env = os.environ if env is None else env
    if env.get(name):
        return env[name]
    return read_env_file(data_dir / ENV_FILE).get(name) or None


def read_env_file(path: Path) -> dict[str, str]:
    """`NAME=Wert` je Zeile; leere Zeilen und `#`-Kommentare zählen nicht, `export ` davor und Anführungszeichen um
    den Wert fallen weg. Fehlt die Datei: leer."""
    try:
        text = path.read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        return {}
    values: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        name = name.removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if name:
            values[name] = value
    return values
