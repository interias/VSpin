"""Anlässe des Weckers (Story 9, Host-Festlegung #78): `ride_event`s und aus `ride_state` abgeleitete Ereignisse.

Abgeleitet: jeder volle 5. km, „noch 5 km“, Wechsel der Pulszone, neuer Abschnitt, Ghost überholt oder überholt
worden. Jeder Anlass zählt einmal, nichts flattert: Die Pulszone gilt erst als gewechselt, wenn zwei `ride_state` in
Folge sie zeigen; der Ghost erst, wenn der Abstand auf der anderen Seite mindestens `GHOST_MARGIN_S` beträgt.
"""

from .prompts import clock_text

FIVE_KM = 5.0
KM_LEFT_NOTICE = 5.0
GHOST_MARGIN_S = 1.0
ZONE_CONFIRMATIONS = 2  # so viele `ride_state` in Folge, bis eine neue Pulszone zählt


class RideWatch:
    """Je Fahrt neu. `update(ride_state)` liefert die neuen Anlässe als (Schlüssel, Text)."""

    def __init__(self) -> None:
        self.last: dict | None = None
        self._fives: int | None = None
        self._km_left_above = False
        self._km_left_done = False
        self._zone: int | None = None
        self._zone_candidate: int | None = None
        self._zone_seen = 0
        self._section: str | None = None
        self._ghost_ahead: bool | None = None

    def update(self, state: dict) -> list[tuple[str, str]]:
        self.last = state
        found: list[tuple[str, str]] = []
        if (km := _number(state.get("km_done"))) is not None:
            fives = int(km // FIVE_KM)
            if self._fives is not None and fives > self._fives:
                found.append(("km", f"{fives * FIVE_KM:g} km geschafft"))
            if self._fives is None or fives > self._fives:
                self._fives = fives
        if (left := _number(state.get("km_left"))) is not None and not self._km_left_done:
            if left >= KM_LEFT_NOTICE:
                self._km_left_above = True
            elif self._km_left_above:
                self._km_left_done = True
                found.append(("km_left", f"noch {KM_LEFT_NOTICE:g} km bis zum Ziel"))
        if (zone := _number(state.get("hr_zone"))) is not None:
            found.extend(self._zone_update(int(zone)))
        section = state.get("section")
        if isinstance(section, str) and section and section != self._section:
            if self._section is not None:
                found.append(("section", f"neuer Abschnitt: {section}"))
            self._section = section
        if (gap := _number(state.get("ghost_gap_s"))) is not None and abs(gap) >= GHOST_MARGIN_S:
            ahead = gap < 0
            if self._ghost_ahead is not None and ahead != self._ghost_ahead:
                found.append(("ghost", "Ghost überholt" if ahead else "vom Ghost überholt worden"))
            self._ghost_ahead = ahead
        return found

    def _zone_update(self, zone: int) -> list[tuple[str, str]]:
        if self._zone is None:
            self._zone = zone  # erster Wert: Ausgangslage, kein Anlass
            return []
        if zone == self._zone:
            self._zone_candidate, self._zone_seen = None, 0
            return []
        if zone != self._zone_candidate:
            self._zone_candidate, self._zone_seen = zone, 0
        self._zone_seen += 1
        if self._zone_seen < ZONE_CONFIRMATIONS:
            return []
        previous, self._zone = self._zone, zone
        self._zone_candidate, self._zone_seen = None, 0
        return [("hr_zone", f"Pulszone {previous} → {zone}")]


def describe_event(event: dict) -> str | None:
    """Text eines weckenden `ride_event`; `None` für Arten, die nicht wecken (oder unbekannt sind)."""
    kind = event.get("kind")
    if kind == "lap":
        time_s = _number(event.get("time_s"))
        return f"Runde {event.get('lap')} geschafft" + (f" in {clock_text(time_s)}" if time_s is not None else "")
    if kind == "medal":
        return f"Medaille {event.get('medal')} für {_target(event.get('for'))}"
    if kind == "best_time":
        time_s, previous = _number(event.get("time_s")), _number(event.get("previous_s"))
        text = f"neue Bestzeit für {_target(event.get('for'))}"
        if time_s is not None:
            text += f": {clock_text(time_s)}"
        return text + (f" (vorher {clock_text(previous)})" if previous is not None else " (die erste)")
    if kind == "achievement":
        return f"Erfolg „{event.get('name') or event.get('id')}“"
    if kind == "boss_start":
        return f"Bosskampf beginnt: {event.get('boss')}"
    if kind == "boss_end":
        return f"Boss {event.get('boss')} {'besiegt' if event.get('defeated') else 'nicht besiegt'}"
    if kind == "interval_start":
        target, duration = _number(event.get("target_cadence")), _number(event.get("duration_s"))
        text = "Intervall beginnt"
        if target is not None:
            text += f": Zielkadenz {target:.0f}"
        return text + (f" für {duration:.0f} s" if duration is not None else "")
    return None


def _target(value: object) -> str:
    return "die Runde" if value in (None, "lap") else f"Segment {value}"


def _number(value: object) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)
