"""Toni am Bus: Sprechtaste → Ears → Brain → Mouth, Status als `companion_status` (docs/bus-protocol.md).

Gerüst aus #77 – der Durchstich auf eine Frage. Wecker, Gedächtnis und Werkzeuge kommen mit #78, Satzteilung,
Barge-in und die echten Ears/Mouth mit #79. Toni liest nur: nichts von hier wirkt auf das Spiel (ADR-0010).
"""

import asyncio
import contextlib
from collections.abc import Callable

from .bus import BusClient
from .ports import Brain, Clock, Ears, Mouth, ToolCall

PROTOCOL_VERSION = 0

# Status des Begleiters (`companion_status.state`). Heiser = Toni schweigt wegen eines Fehlers (Netz, Anmeldung,
# Abo-Limit, Dienst); die Fahrt läuft weiter, das nächste Drücken der Sprechtaste versucht es neu.
IDLE = "idle"
LISTENING = "listening"
THINKING = "thinking"
SPEAKING = "speaking"
HOARSE = "hoarse"
STATES = (IDLE, LISTENING, THINKING, SPEAKING, HOARSE)


def status_message(state: str) -> dict:
    return {"v": PROTOCOL_VERSION, "type": "companion_status", "state": state, "speaking": state == SPEAKING}


class Companion:
    def __init__(
        self,
        brain: Brain,
        ears: Ears,
        mouth: Mouth,
        clock: Clock,
        url: str,
        log: Callable[[str], None] = lambda text: None,
        reconnect_interval_s: float | None = None,
    ) -> None:
        self._brain = brain
        self._ears = ears
        self._mouth = mouth
        self._clock = clock
        self._log = log
        extra = {} if reconnect_interval_s is None else {"reconnect_interval_s": reconnect_interval_s}
        self._bus = BusClient(url, self._on_message, self._send_status, log, **extra)
        self._state = IDLE
        self._answer: asyncio.Task | None = None

    @property
    def state(self) -> str:
        return self._state

    async def run(self, stop: asyncio.Event) -> None:
        """Läuft, bis `stop` gesetzt wird; Fehler der Ports beenden ihn nie."""
        self._log("vspin-companion: Toni ist da")
        try:
            await self._bus.run(stop)
        finally:
            if self._answer is not None:
                self._answer.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await self._answer

    async def _on_message(self, message: dict) -> None:
        if not _is_version(message.get("v")):
            return
        kind = message.get("type")
        if kind == "companion_ptt":
            action = message.get("action")
            if action == "down":
                await self._ptt_down()
            elif action == "up":
                await self._ptt_up()
        elif kind == "ride_event" and message.get("kind") == "ride_start":
            await self._send_status()  # das Spiel kennt Tonis Stand ab Fahrtbeginn, auch wenn es später kam
        # ride_state und die übrigen ride_event: Wecker und Fahrtwissen (#78); alles andere ignorieren.

    async def _ptt_down(self) -> None:
        if self._state not in (IDLE, HOARSE):
            return  # Toni denkt oder spricht noch – Barge-in kommt mit #79
        try:
            await self._ears.start_listening()
        except Exception as exc:
            await self._hoarse("Ears", exc)
            return
        await self._set_state(LISTENING)

    async def _ptt_up(self) -> None:
        if self._state != LISTENING:
            return
        await self._set_state(THINKING)
        # Eigene Aufgabe: Der Bus liest weiter, während Toni denkt und spricht.
        self._answer = asyncio.create_task(self._reply())

    async def _reply(self) -> None:
        port = "Ears"
        try:
            question = await self._ears.stop_listening()
            port = "Clock"
            released = self._clock.now()
            if not question.strip():
                self._log("Sprechtaste: nichts verstanden")
                await self._set_state(IDLE)
                return
            self._log(f"Frage: {question}")
            port = "Brain"
            parts: list[str] = []
            async for item in self._brain.respond(question):
                if isinstance(item, ToolCall):
                    self._log(f"Werkzeug {item.name} ignoriert (kommt mit #78)")
                else:
                    parts.append(item)
            answer = "".join(parts).strip()
            if answer:
                port = "Clock"
                latency_s = self._clock.now() - released
                await self._set_state(SPEAKING)
                self._log(f"Antwort nach {latency_s:.2f} s: {answer}")
                port = "Mouth"
                await self._mouth.speak(answer)
        except Exception as exc:
            await self._hoarse(port, exc)
            return
        await self._set_state(IDLE)

    async def _hoarse(self, port: str, exc: Exception) -> None:
        self._log(f"Toni ist heiser – {port}: {type(exc).__name__}: {exc}")
        await self._set_state(HOARSE)

    async def _set_state(self, state: str) -> None:
        if state == self._state:
            return
        self._state = state
        await self._send_status()

    async def _send_status(self) -> None:
        await self._bus.send(status_message(self._state))


def _is_version(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == PROTOCOL_VERSION
