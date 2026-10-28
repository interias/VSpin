"""Simulator-Profile: geskriptete Abläufe aus einer TOML-Datei (ADR-0003).

Format (Beispiele unter `bridge/profiles/`)::

    name = "Abbruch"     # optional, nur fürs Terminal
    repeat = true        # optional: am Ende von vorn beginnen (Standard: false → Quelle endet)
    heart_rate = false   # optional: false schaltet den Simulator-Puls ab (`heart_rate` bleibt null)

    [[steps]]            # Fahren: konstante Kadenz …
    duration_s = 3
    cadence = 80

    [[steps]]            # … oder linear von `cadence` nach `cadence_to`
    duration_s = 10
    cadence = 60
    cadence_to = 90

    [[steps]]            # Zielpuls statt der Formel des Simulators (`sim_heart_rate.py`): konstant …
    duration_s = 30
    cadence = 110
    heart_rate = 165

    [[steps]]            # … oder linear von `heart_rate` nach `heart_rate_to`
    duration_s = 30
    cadence = 60
    heart_rate = 165
    heart_rate_to = 110

    [[steps]]            # keine Daten, Verbindung bleibt stehen (> 3 s → stale)
    duration_s = 4
    action = "pause"

    [[steps]]            # Verbindung reißt ab; Gerät ist `duration_s` lang nicht erreichbar,
    duration_s = 2       # danach verbindet sich die Bridge selbst neu (alle 3 s, ADR-0004)
    action = "disconnect"

Der Puls ist je Schritt steuerbar, weil sich Belastung und Erholung von Schritt zu Schritt
ändern: `heart_rate` (50–190 bpm) ist der **Zielpuls** des Schritts, `heart_rate_to` lässt ihn
linear wandern wie `cadence_to` die Kadenz. Der gemeldete Puls läuft dem Ziel mit der
Zeitkonstante des Simulators nach, er springt nicht. Ohne `heart_rate` gilt die Formel aus
Kadenz und Steigung. Der Kopfschlüssel `heart_rate = false` schaltet den Puls für das ganze Profil
ab (Rad ohne Puls: `telemetry.heart_rate` bleibt `null`); zusammen mit einem Schritt-Puls ist er ein Fehler.

Die Wiedergabe ist deterministisch: ein Fahr-Schritt liefert genau
`round(duration_s / Takt)` Samples, deren Kadenz nur vom Index im Schritt abhängt –
nie von der Wanduhr.
"""

import math
import tomllib
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

CADENCE_MAX = 200.0  # Plausibilitätsgrenze aus ADR-0004
HEART_RATE_MIN = 50.0  # plausibler Pulsbereich des Simulators (bpm)
HEART_RATE_MAX = 190.0

PAUSE = "pause"
DISCONNECT = "disconnect"
ACTIONS = (PAUSE, DISCONNECT)


class ProfileError(ValueError):
    """Profil-Datei fehlt, ist kein gültiges TOML oder hält sich nicht an das Format."""


@dataclass(frozen=True, slots=True)
class Ride:
    duration_s: float
    cadence: float
    cadence_to: float | None = None
    heart_rate: float | None = None  # Zielpuls des Schritts (None: Formel des Simulators)
    heart_rate_to: float | None = None


@dataclass(frozen=True, slots=True)
class Action:
    duration_s: float
    action: str  # pause | disconnect


Step = Ride | Action


@dataclass(frozen=True, slots=True)
class Profile:
    name: str
    steps: tuple[Step, ...]
    repeat: bool = False
    heart_rate: bool = True  # False: der Simulator liefert keinen Puls


# --- Ereignisse der Wiedergabe ------------------------------------------------


@dataclass(frozen=True, slots=True)
class Tick:
    """Ein Sample mit dieser Kadenz (`None`: die manuell eingestellte, nur im Simulator)
    und ggf. diesem Zielpuls (`None`: Formel des Simulators)."""

    cadence: float | None
    heart_rate: float | None = None


@dataclass(frozen=True, slots=True)
class Pause:
    """`duration_s` lang keine Daten."""

    duration_s: float


@dataclass(frozen=True, slots=True)
class Disconnect:
    """Verbindung reißt ab; das Gerät ist `duration_s` lang nicht erreichbar."""

    duration_s: float


Event = Tick | Pause | Disconnect


def play(profile: Profile, interval_s: float) -> Iterator[Event]:
    """Ereignisfolge eines Profils; bei `repeat` endlos."""
    while True:
        for step in profile.steps:
            if isinstance(step, Ride):
                yield from _ride(step, interval_s)
            elif step.action == PAUSE:
                yield Pause(step.duration_s)
            else:
                yield Disconnect(step.duration_s)
        if not profile.repeat:
            return


def _ride(step: Ride, interval_s: float) -> Iterator[Tick]:
    count = max(1, round(step.duration_s / interval_s))
    end = step.cadence if step.cadence_to is None else step.cadence_to
    for i in range(count):
        fraction = i / (count - 1) if count > 1 else 0.0
        target = None
        if step.heart_rate is not None:
            target_end = step.heart_rate if step.heart_rate_to is None else step.heart_rate_to
            target = round(step.heart_rate + (target_end - step.heart_rate) * fraction, 1)
        yield Tick(round(step.cadence + (end - step.cadence) * fraction, 1), target)


# --- Laden ------------------------------------------------------------------


def load_profile(path: Path) -> Profile:
    try:
        with open(path, "rb") as stream:
            data = tomllib.load(stream)
    except OSError as exc:
        raise ProfileError(f"Profil {path} nicht lesbar: {exc.strerror or exc}") from None
    except tomllib.TOMLDecodeError as exc:
        raise ProfileError(f"Profil {path} ist kein gültiges TOML: {exc}") from None
    try:
        return _profile(data, default_name=path.stem)
    except ProfileError as exc:
        raise ProfileError(f"Profil {path}: {exc}") from None


def _profile(data: dict, default_name: str) -> Profile:
    _known_keys(data, {"name", "repeat", "heart_rate", "steps"}, "Profil")
    name = data.get("name", default_name)
    if not isinstance(name, str):
        raise ProfileError("'name' muss ein Text sein")
    repeat = data.get("repeat", False)
    if not isinstance(repeat, bool):
        raise ProfileError("'repeat' muss true oder false sein")
    heart_rate = data.get("heart_rate", True)
    if not isinstance(heart_rate, bool):
        raise ProfileError("'heart_rate' im Profilkopf muss true oder false sein (Zielpulse stehen in den Schritten)")
    raw_steps = data.get("steps")
    if not isinstance(raw_steps, list) or not raw_steps:
        raise ProfileError("mindestens ein [[steps]]-Eintrag nötig")
    steps = tuple(_step(raw, i) for i, raw in enumerate(raw_steps, start=1))
    if not any(isinstance(step, Ride) for step in steps):
        raise ProfileError("mindestens ein Schritt mit 'cadence' nötig")
    if not heart_rate and any(isinstance(step, Ride) and step.heart_rate is not None for step in steps):
        raise ProfileError(
            "'heart_rate = false' schaltet den Puls ab und verträgt sich nicht mit einem Schritt-'heart_rate'"
        )
    return Profile(name=name, steps=steps, repeat=repeat, heart_rate=heart_rate)


def _step(raw: object, index: int) -> Step:
    where = f"Schritt {index}"
    if not isinstance(raw, dict):
        raise ProfileError(f"{where}: muss eine Tabelle sein")
    duration = _number(raw.get("duration_s"), f"{where}: 'duration_s'")
    if duration <= 0:
        raise ProfileError(f"{where}: 'duration_s' muss > 0 sein, war {duration!r}")
    if "action" in raw:
        _known_keys(raw, {"duration_s", "action"}, where)
        if raw["action"] not in ACTIONS:
            raise ProfileError(f"{where}: 'action' muss eins von {', '.join(ACTIONS)} sein, war {raw['action']!r}")
        return Action(duration_s=duration, action=raw["action"])
    _known_keys(raw, {"duration_s", "cadence", "cadence_to", "heart_rate", "heart_rate_to"}, where)
    if "cadence" not in raw:
        raise ProfileError(f"{where}: 'cadence' oder 'action' nötig")
    cadence = _cadence(raw["cadence"], f"{where}: 'cadence'")
    cadence_to = None if "cadence_to" not in raw else _cadence(raw["cadence_to"], f"{where}: 'cadence_to'")
    if "heart_rate_to" in raw and "heart_rate" not in raw:
        raise ProfileError(f"{where}: 'heart_rate_to' braucht 'heart_rate'")
    heart_rate = None if "heart_rate" not in raw else _heart_rate(raw["heart_rate"], f"{where}: 'heart_rate'")
    heart_rate_to = (
        None if "heart_rate_to" not in raw else _heart_rate(raw["heart_rate_to"], f"{where}: 'heart_rate_to'")
    )
    return Ride(
        duration_s=duration, cadence=cadence, cadence_to=cadence_to, heart_rate=heart_rate, heart_rate_to=heart_rate_to
    )


def _cadence(value: object, what: str) -> float:
    cadence = _number(value, what)
    if not 0 <= cadence <= CADENCE_MAX:
        raise ProfileError(f"{what} muss zwischen 0 und {CADENCE_MAX:.0f} rpm liegen, war {value!r}")
    return cadence


def _heart_rate(value: object, what: str) -> float:
    bpm = _number(value, what)
    if not HEART_RATE_MIN <= bpm <= HEART_RATE_MAX:
        raise ProfileError(
            f"{what} muss zwischen {HEART_RATE_MIN:.0f} und {HEART_RATE_MAX:.0f} bpm liegen, war {value!r}"
        )
    return bpm


def _number(value: object, what: str) -> float:
    if not isinstance(value, bool) and isinstance(value, (int, float)):
        try:
            number = float(value)
        except OverflowError:  # riesige TOML-Ganzzahl
            number = math.inf
        if math.isfinite(number):
            return number
    raise ProfileError(f"{what} muss eine endliche Zahl sein, war {value!r}")


def _known_keys(table: dict, allowed: set[str], where: str) -> None:
    unknown = sorted(set(table) - allowed)
    if unknown:
        raise ProfileError(f"{where}: unbekannte Schlüssel {', '.join(unknown)}")
