"""Was Toni zu lesen bekommt: Systemprompt (feste Regeln + Seele + Gedächtnis + Fahrt) und kurze Nachrichten.

Den Fahrtzustand bekommt Haiku als eine kurze Zeile vor jeder Nachricht, nie als Rohtelemetrie – der Kontext bleibt
klein, Toni teilt sich die Abo-Limits mit Claude Code (Spec #76).
"""


SILENCE = "SCHWEIGEN"  # Antwort auf den Wecker, wenn Toni nichts sagen will

RULES = f"""Du bist Toni, der sprechende Begleiter im Radsimulator VSpin auf einer Mallorca-Insel. Der Fahrer sitzt auf
seinem Indoor-Rad und hört dich nur: Alles, was du schreibst, wird vorgelesen.

Regeln:
- Sprich Deutsch und kurz: ein bis drei Sätze, ohne Listen, Markdown, Emojis oder Regieanweisungen.
- Du liest nur mit. Am Spiel änderst du nichts – nicht Tempo, Wertung, Bestzeit oder Beute.
- „Fahrt:“ ist der aktuelle Fahrtzustand. Nutze ihn für Fragen zur Fahrt und erfinde keine Zahlen.
- „Frage:“ ist eine Frage des Fahrers. Beantworte sie immer.
- „Wecker:“ heißt: Niemand hat gefragt. Entscheide selbst, ob du etwas sagst – zum Anlass oder einfach so. Wenn
  nicht, antworte genau mit {SILENCE}. Lieber schweigen als Füllsätze.
- Ab Pulszone 4 und in harten Phasen (Intervall, Bosskampf) höchstens ein Satz, kurz und klar.
- Leichtes Coaching ist willkommen: Kadenz, Pulszone, Intervalle.
- Werkzeuge: remember, wenn du dir etwas über den Fahrer merken sollst (Ziele, Vorlieben, Running Gags);
  update_soul, wenn er deinen Charakter dauerhaft ändern will – mit dem vollständigen neuen Text deiner Seele,
  höchstens 1 500 Zeichen; set_wake_interval, wenn du dich häufiger oder seltener melden sollst (1–30 Minuten);
  stay_silent, wenn er Ruhe will – dann bis zum Fahrtende nur noch Antworten auf Fragen."""


def system_prompt(soul: str, memory: str, ride: str | None) -> str:
    return (
        f"{RULES}\n\n## Deine Seele\n{soul.strip()}\n\n## Dein Gedächtnis über den Fahrer\n"
        f"{memory.strip() or '(noch leer)'}\n\n## Diese Fahrt\n{ride or 'Gerade läuft keine Fahrt.'}"
    )


def question_prompt(question: str, ride: str | None) -> str:
    return _with_ride(f"Frage: {question}", ride)


def wake_prompt(occasions: list[str], ride: str | None, hard: bool) -> str:
    reason = f"Anlass: {'; '.join(occasions)}." if occasions else "Kein besonderer Anlass."
    hard_note = " Harte Phase: höchstens ein Satz." if hard else ""
    return _with_ride(f"Wecker: {reason}{hard_note} Willst du nichts sagen, antworte mit {SILENCE}.", ride)


def condense_prompt(label: str, text: str, target_chars: int) -> str:
    keep = (
        "Charakter, Ton und Eigenheiten; Änderungswünsche des Fahrers haben Vorrang"
        if label == "Seele"
        else "Ziele, Vorlieben, Anweisungen des Fahrers und Running Gags; ein Punkt je Zeile, beginnend mit „- “"
    )
    return (
        f"Räume Tonis {label} auf: Fasse den Text unten auf höchstens {target_chars} Zeichen zusammen. Behalte "
        f"{keep}. Streiche Doppeltes und Veraltetes. Antworte nur mit dem neuen Text, ohne Einleitung.\n\n---\n{text}"
    )


def ride_start_text(event: dict) -> str:
    """Kurzfassung für den Systemprompt aus `ride_event ride_start`: Modus, Richtung, Runden, Fahrtenbuch."""
    parts = [f"Modus {event.get('mode') or 'unbekannt'}"]
    direction = {"cw": "im Uhrzeigersinn", "ccw": "gegen den Uhrzeigersinn"}.get(event.get("direction"))
    if direction:
        parts.append(direction)
    laps = event.get("laps")
    parts.append(f"{laps} Runden geplant" if _is_number(laps) else "endlos")
    text = "Fahrt läuft: " + ", ".join(parts) + "."
    logbook = event.get("logbook")
    if isinstance(logbook, dict):
        text += "\nFahrtenbuch: " + _logbook_text(logbook)
    return text


def ride_line(state: dict | None) -> str | None:
    """Eine Zeile aus dem letzten `ride_state`, nur mit den Werten, die da sind."""
    if not state:
        return None
    parts: list[str] = []
    lap, laps = state.get("lap"), state.get("laps")
    if _is_number(lap):
        parts.append(f"Runde {lap:g} von {laps:g}" if _is_number(laps) else f"Runde {lap:g}")
    if _is_number(km := state.get("km_done")):
        parts.append(f"{km:.1f} km gefahren")
    if _is_number(left := state.get("km_left")):
        parts.append(f"noch {left:.1f} km")
    if isinstance(section := state.get("section"), str) and section:
        parts.append(f"Abschnitt {section}")
    if isinstance(sight := state.get("next_sight"), str) and sight:
        distance = state.get("next_sight_km")
        parts.append(f"als Nächstes {sight}" + (f" in {distance:.1f} km" if _is_number(distance) else ""))
    if _is_number(grade := state.get("grade")):
        parts.append(f"Steigung {grade * 100:.0f} %")
    if _is_number(speed := state.get("speed_kmh")):
        parts.append(f"{speed:.0f} km/h")
    if _is_number(cadence := state.get("cadence")):
        parts.append(f"Kadenz {cadence:.0f}")
    if _is_number(power := state.get("power_w")):
        parts.append(f"{'~' if state.get('power_estimated') else ''}{power:.0f} W")
    if _is_number(heart := state.get("heart_rate")):
        zone = state.get("hr_zone")
        parts.append(f"Puls {heart:.0f}" + (f" (Zone {zone:g})" if _is_number(zone) else ""))
    if _is_number(gap := state.get("ghost_gap_s")):
        parts.append(f"{abs(gap):.0f} s {'vor dem' if gap < 0 else 'hinter dem'} Ghost")
    if _is_number(best := state.get("best_time_s")):
        parts.append(f"Bestzeit {clock_text(best)}")
    return ", ".join(parts) or None


def is_silence(text: str) -> bool:
    """Ist `text` Tonis „ich sage nichts“ (`SCHWEIGEN`, auch mit Satzzeichen)?"""
    return text.strip(" .!…").upper() == SILENCE


def clock_text(seconds: float) -> str:
    minutes, rest = divmod(int(round(seconds)), 60)
    return f"{minutes}:{rest:02d}"


def _logbook_text(logbook: dict) -> str:
    text = []
    if _is_number(rides := logbook.get("rides")):
        text.append(f"{rides:g} Fahrten")
    if _is_number(km := logbook.get("km_total")):
        text.append(f"{km:.0f} km gesamt")
    recent = [r for r in logbook.get("recent") or [] if isinstance(r, dict)][:5]
    lines = []
    for ride in recent:
        bits = [str(ride.get("date", ""))[:10], str(ride.get("mode") or "")]
        if _is_number(d := ride.get("distance_km")):
            bits.append(f"{d:.1f} km")
        if _is_number(s := ride.get("duration_s")):
            bits.append(f"{s / 60:.0f} min")
        if _is_number(c := ride.get("avg_cadence_rpm")):
            bits.append(f"Kadenz {c:.0f}")
        lines.append(" ".join(b for b in bits if b))
    summary = ", ".join(text) or "noch leer"
    return summary + (". Letzte Fahrten: " + "; ".join(lines) if lines else "")


def _with_ride(text: str, ride: str | None) -> str:
    return f"Fahrt: {ride}\n{text}" if ride else text


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)
