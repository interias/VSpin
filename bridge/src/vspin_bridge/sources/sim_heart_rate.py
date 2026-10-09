"""Puls des Simulators: folgt träge der Belastung (Spec #64).

Ein Rad mit FTMS liefert seinen Puls im Sample mit; der Simulator tut dasselbe. Die
Bridge nimmt ihn nur, solange kein Pulsgerät verbunden ist (`heart_rate_relay.py`).

Formel, einfach gehalten:

    Ziel   = 60 + 0,9 · Kadenz + 3 · max(0, Steigung in %)      (begrenzt auf 50–190 bpm)
    Puls  += (Ziel − Puls) · (1 − e^(−Takt / 30 s))              (je Sample)

Ruhepuls 60 bpm; 80 rpm eben ergibt ein Ziel von 132, 130 rpm 177, 7 % Steigung bringen
21 bpm obendrauf. Die Zeitkonstante von 30 s lässt den Puls im Intervall langsam steigen und
in der Pause langsam fallen (nach 30 s sind 63 % des Weges geschafft). Gemeldet wird der auf
ganze bpm gerundete Wert. Ein Profilschritt kann das Ziel mit `heart_rate` selbst vorgeben
(`profile.py`); der Puls läuft ihm dann ebenso nach.

Gerechnet wird je Sample mit dem festen Takt der Quelle, nie mit der Wanduhr: der Puls hängt
nur von der Folge der Samples ab (Kadenz, Steigung, Zielpuls), ohne `--noise` also bei jedem
Lauf gleich. Mit `--noise` geht die verrauschte Kadenz ein, bei gleichem Seed wieder gleich.
Eine Datenlücke (Profil-`pause`, `disconnect`) lässt die Zeit des Pulses stehen.
"""

import math

from .profile import HEART_RATE_MAX, HEART_RATE_MIN

REST_BPM = 60.0
BPM_PER_RPM = 0.9
BPM_PER_GRADE_PERCENT = 3.0
TAU_S = 30.0


class HeartRateModel:
    def __init__(self, interval_s: float, tau_s: float = TAU_S) -> None:
        self._alpha = 1.0 - math.exp(-interval_s / tau_s)
        self._bpm = REST_BPM

    @staticmethod
    def target(cadence: float, grade: float = 0.0) -> float:
        """Zielpuls aus Kadenz (rpm) und virtueller Steigung (Anteil, 0,07 = 7 %)."""
        bpm = REST_BPM + BPM_PER_RPM * cadence + BPM_PER_GRADE_PERCENT * max(0.0, grade) * 100.0
        return max(HEART_RATE_MIN, min(HEART_RATE_MAX, bpm))

    def step(self, cadence: float, grade: float = 0.0, target: float | None = None) -> int:
        """Ein Takt weiter; liefert den Puls in ganzen bpm. `target`: Zielpuls statt der Formel."""
        goal = self.target(cadence, grade) if target is None else target
        self._bpm += (goal - self._bpm) * self._alpha
        return round(self._bpm)
