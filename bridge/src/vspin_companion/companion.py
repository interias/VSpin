"""Toni am Bus: Sprechtaste → Ears → Brain → Mouth, Wecker, Seele und Gedächtnis; Status als `companion_status`.

#77 brachte den Durchstich auf eine Frage, #78 Tonis Kopf: eine Brain-Sitzung je Fahrt (Systemprompt aus Regeln,
Seele, Gedächtnis und Fahrtenbuch), den Wecker, die Werkzeuge und das Aufräumen nach `ride_end`. Satzteilung, Barge-in
und die echten Ears/Mouth kommen mit #79. Toni liest nur: nichts von hier wirkt auf das Spiel (ADR-0010).

Wecker: In der Fahrt klingelt er nach einem zufälligen Abstand aus `companion.json` (`wake_min_minutes` bis
`wake_max_minutes`) und sofort bei einem Anlass (`wake.py`); zwischen zwei ungefragten Sätzen liegen mindestens
`MIN_UNPROMPTED_GAP_S`. Geweckt denkt Toni still (kein `thinking` am Bus) und entscheidet selbst; schweigt er, kommt
gar nichts. Fragen gehen immer durch, auch nach `stay_silent`. In harten Phasen (Intervall, Bosskampf) spricht er
höchstens einen Satz. Vor `ride_start` und nach `ride_end` weckt der Wecker nicht.
"""

import asyncio
import contextlib
import random
from collections.abc import Callable, Coroutine
from pathlib import Path

from . import prompts
from .bus import BusClient
from .config import CompanionConfig, ConfigError, save_wake_interval
from .notes import MEMORY, NOTES, SOUL, Notebook, NoteRefused
from .ports import Brain, Clock, Ears, Mouth, ToolCall, ToolResult
from .wake import RideWatch, describe_event

PROTOCOL_VERSION = 0

# Status des Begleiters (`companion_status.state`). Heiser = Toni schweigt wegen eines Fehlers (Netz, Anmeldung,
# Abo-Limit, Dienst); die Fahrt läuft weiter, das nächste Drücken der Sprechtaste versucht es neu.
IDLE = "idle"
LISTENING = "listening"
THINKING = "thinking"
SPEAKING = "speaking"
HOARSE = "hoarse"
STATES = (IDLE, LISTENING, THINKING, SPEAKING, HOARSE)

MIN_UNPROMPTED_GAP_S = 60.0  # Story 10: mindestens eine Minute Schweigen zwischen zwei ungefragten Sätzen


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
        *,
        data_dir: Path,
        config: CompanionConfig = CompanionConfig(),
        rng: random.Random | None = None,
    ) -> None:
        self._brain = brain
        self._ears = ears
        self._mouth = mouth
        self._clock = clock
        self._log = log
        extra = {} if reconnect_interval_s is None else {"reconnect_interval_s": reconnect_interval_s}
        self._bus = BusClient(url, self._on_message, self._send_status, log, **extra)
        self._state = IDLE
        self._data_dir = data_dir
        self._config = config
        self._rng = rng or random.Random()  # Tests geben einen mit festem Seed
        self._notes = Notebook(data_dir, brain.summarize, log)
        self._tasks: set[asyncio.Task] = set()
        # Das Brain macht eins nach dem anderen: Sitzung öffnen/schließen, Antwort, Wecker, Aufräumen.
        self._brain_lock = asyncio.Lock()
        self._session_open = False
        self._session_broken = False  # nach einem Fehler des Brain: nächste Anfrage in frischer Sitzung
        # Fahrt
        self._riding = False
        self._paused = False
        self._silenced = False  # stay_silent: bis `ride_end` nichts Ungefragtes
        self._ride: str | None = None  # Kurzfassung aus `ride_start` für den Systemprompt
        self._watch = RideWatch()
        self._boss = False
        self._hard_until: float | None = None
        # Wecker
        self._next_timer_at: float | None = None
        self._pending: dict[object, str] = {}  # Anlässe, die auf den Wecker warten (Schlüssel gegen Doppeltes)
        self._last_unprompted_at: float | None = None
        self._alarm: asyncio.Task | None = None
        self._waking: asyncio.Task | None = None

    @property
    def state(self) -> str:
        return self._state

    async def run(self, stop: asyncio.Event) -> None:
        """Läuft, bis `stop` gesetzt wird; Fehler der Ports beenden ihn nie."""
        self._log("vspin-companion: Toni ist da")
        try:
            await self._bus.run(stop)
        finally:
            tasks = list(self._tasks)
            for task in tasks:
                task.cancel()
            for task in tasks:
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await task
            with contextlib.suppress(Exception):
                await self._close_session()

    async def _on_message(self, message: dict) -> None:
        try:
            await self._handle(message)
        except Exception as exc:  # eine kaputte Nachricht darf den Bus-Client nicht beenden
            self._log(f"Nachricht verworfen – {type(exc).__name__}: {exc}")

    async def _handle(self, message: dict) -> None:
        if not _is_version(message.get("v")):
            return
        kind = message.get("type")
        if kind == "companion_ptt":
            action = message.get("action")
            if action == "down":
                await self._ptt_down()
            elif action == "up":
                await self._ptt_up()
        elif kind == "ride_event":
            await self._ride_event(message)
        elif kind == "ride_state":
            self._ride_state(message)
        # alles andere ignorieren

    # --- Fahrt ------------------------------------------------------------------------------------------------

    async def _ride_event(self, event: dict) -> None:
        kind = event.get("kind")
        if kind == "ride_start":
            await self._send_status()  # das Spiel kennt Tonis Stand ab Fahrtbeginn, auch wenn es später kam
            self._ride_started(event)
            return
        if not self._riding:
            return
        if kind == "ride_end":
            self._ride_ended()
            return
        if kind == "pause":
            self._paused = bool(event.get("paused"))
            if not self._paused:
                self._schedule_timer()  # nach der Pause beginnt der Abstand neu
            self._rearm()
            return
        if kind == "boss_start":
            self._boss = True
        elif kind == "boss_end":
            self._boss = False
        elif kind == "interval_start":
            duration = event.get("duration_s")
            if isinstance(duration, (int, float)) and not isinstance(duration, bool) and duration > 0:
                self._hard_until = self._clock.now() + duration
        text = describe_event(event)
        if text is not None:
            self._occasion(object(), text)  # jedes `ride_event` zählt für sich

    def _ride_started(self, event: dict) -> None:
        self._riding, self._paused, self._silenced = True, False, False
        self._ride = prompts.ride_start_text(event)
        self._watch = RideWatch()
        self._boss, self._hard_until = False, None
        self._pending.clear()
        self._last_unprompted_at = None
        self._log(f"Fahrt beginnt – {self._ride.splitlines()[0]}")
        self._spawn(self._new_session())  # warme Sitzung je Fahrt, Seele und Gedächtnis frisch gelesen
        self._schedule_timer()
        self._rearm()

    def _ride_ended(self) -> None:
        self._riding, self._silenced = False, False
        self._boss, self._hard_until = False, None
        self._pending.clear()
        self._rearm()
        self._log("Fahrt zu Ende")
        self._spawn(self._finish_ride())

    def _ride_state(self, state: dict) -> None:
        if not self._riding:
            return
        for key, text in self._watch.update(state):
            self._occasion(key, text)

    async def _new_session(self) -> None:
        try:
            async with self._brain_lock:
                await self._close_session()
                self._notes.begin()  # neue Sitzung: `.bak` sichert den Stand vor dieser Fahrt
                await self._open_session()
        except Exception as exc:
            await self._hoarse("Brain", exc)

    async def _finish_ride(self) -> None:
        """Nach `ride_end`: Seele und Gedächtnis aufräumen (was sich in der Fahrt geändert hat oder über der Grenze
        liegt; `.bak` sichert den Stand vor der Fahrt, falls noch nicht geschehen), dann die Sitzung schließen."""
        try:
            async with self._brain_lock:
                try:
                    for note in NOTES:
                        if self._notes.needs_tidy(note):
                            await self._notes.tidy(note)
                    self._notes.begin()  # was nach der Fahrt geschrieben wird, sichert für sich
                finally:
                    await self._close_session()
        except Exception as exc:
            await self._hoarse("Brain", exc)

    async def _open_session(self) -> None:
        ride = self._ride if self._riding else None
        system = prompts.system_prompt(self._notes.read(SOUL), self._notes.read(MEMORY), ride)
        await self._brain.open_session(system, self._run_tool)
        self._session_open, self._session_broken = True, False

    async def _close_session(self) -> None:
        if self._session_open:
            self._session_open = False
            await self._brain.close_session()

    async def _ensure_session(self) -> None:
        """Nur unter `_brain_lock`."""
        if self._session_broken:
            with contextlib.suppress(Exception):
                await self._close_session()
            self._session_open = False
        if not self._session_open:
            await self._open_session()

    def _hard_phase(self) -> bool:
        return self._boss or (self._hard_until is not None and self._clock.now() < self._hard_until)

    # --- Wecker -----------------------------------------------------------------------------------------------

    def _occasion(self, key: object, text: str) -> None:
        if not self._wake_allowed():
            return
        self._log(f"Wecker: {text}")
        self._pending[key] = text
        self._rearm()

    def _wake_allowed(self) -> bool:
        return self._riding and not self._paused and not self._silenced

    def _schedule_timer(self) -> None:
        minutes = self._rng.uniform(self._config.wake_min_minutes, self._config.wake_max_minutes)
        self._next_timer_at = self._clock.now() + minutes * 60

    def _rearm(self) -> None:
        """Stellt den Wecker neu: Anlass sofort, sonst zum Zufallsabstand – beides frühestens
        `MIN_UNPROMPTED_GAP_S` nach dem letzten ungefragten Satz. Anlässe warten, solange Toni nicht `idle` ist."""
        if self._alarm is not None:
            self._alarm.cancel()
            self._alarm = None
        if not self._wake_allowed() or self._next_timer_at is None or self._waking is not None:
            return  # ein laufender Wecker stellt am Ende selbst neu
        if self._pending and self._state != IDLE:
            return  # die Rückkehr nach `idle` stellt neu (`_set_state`)
        now = self._clock.now()
        due = now if self._pending else self._next_timer_at
        if self._last_unprompted_at is not None:
            due = max(due, self._last_unprompted_at + MIN_UNPROMPTED_GAP_S)
        self._alarm = self._spawn(self._ring(max(0.0, due - now)))

    async def _ring(self, delay: float) -> None:
        await self._clock.sleep(delay)
        self._alarm = None
        self._waking = self._spawn(self._wake())

    async def _wake(self) -> None:
        port = "Brain"
        try:
            if not self._wake_allowed():
                self._pending.clear()
                return
            if self._state != IDLE:  # Toni hört zu, denkt, spricht oder ist heiser
                if not self._pending:
                    self._schedule_timer()  # der Zufallsabstand beginnt neu; Anlässe warten auf `idle`
                return
            occasions = list(self._pending.values())
            self._pending.clear()
            self._schedule_timer()
            parts: list[str] = []
            async with self._brain_lock:
                if not self._wake_allowed():  # Fahrt endete oder `stay_silent`, während Toni wartete
                    return
                hard = self._hard_phase()
                await self._ensure_session()
                prompt = prompts.wake_prompt(occasions, prompts.ride_line(self._watch.last), hard)
                async for item in self._brain.respond(prompt):
                    if isinstance(item, ToolCall):
                        self._log(f"Werkzeug {item.name} {item.arguments}")
                    else:
                        parts.append(item)
            text = prompts.spoken_text(parts, hard or self._hard_phase())
            if not text or self._state != IDLE or not self._wake_allowed():
                self._log("Wecker: Toni schweigt")
                return
            port = "Clock"
            self._last_unprompted_at = self._clock.now()
            await self._set_state(SPEAKING)
            self._log(f"Ungefragt: {text}")
            port = "Mouth"
            await self._mouth.speak(text)
            self._last_unprompted_at = self._clock.now()  # die Minute Schweigen zählt ab dem Ende des Satzes
            await self._set_state(IDLE)
        except Exception as exc:
            await self._hoarse(port, exc)
        finally:
            self._waking = None
            self._rearm()

    # --- Werkzeuge --------------------------------------------------------------------------------------------

    async def _run_tool(self, call: ToolCall) -> ToolResult:
        """Werkzeuge für das Brain. Ein Fehlschlag geht als `is_error` an Haiku zurück, Toni wird davon nicht heiser."""
        args = call.arguments if isinstance(call.arguments, dict) else {}
        try:
            if call.name == "remember":
                result = ToolResult(await self._notes.remember(_text_arg(args, "text")))
            elif call.name == "update_soul":
                result = ToolResult(await self._notes.update_soul(_text_arg(args, "text")))
            elif call.name == "set_wake_interval":
                result = ToolResult(self._set_wake_interval(args.get("min_minutes"), args.get("max_minutes")))
            elif call.name == "stay_silent":
                result = ToolResult(self._stay_silent(args.get("until_ride_end", True)))
            else:
                result = ToolResult(f"unbekanntes Werkzeug {call.name!r}", is_error=True)
        except (NoteRefused, ConfigError, ValueError) as exc:
            result = ToolResult(str(exc), is_error=True)
        except Exception as exc:  # z. B. Zusammenfassen gescheitert (Netz) – Haiku erfährt es
            result = ToolResult(f"{type(exc).__name__}: {exc}", is_error=True)
        self._log(f"Werkzeug {call.name}: {'Fehler – ' if result.is_error else ''}{result.text}")
        return result

    def _set_wake_interval(self, min_minutes: object, max_minutes: object) -> str:
        self._config = save_wake_interval(self._data_dir, min_minutes, max_minutes)  # prüft 1–30, min ≤ max
        self._schedule_timer()  # wirkt sofort auf den nächsten Wecker
        self._rearm()
        low, high = self._config.wake_min_minutes, self._config.wake_max_minutes
        return f"Wecker alle {low:g} min" if low == high else f"Wecker alle {low:g}–{high:g} min"

    def _stay_silent(self, until_ride_end: object) -> str:
        if until_ride_end is False:
            self._silenced = False
            self._schedule_timer()
            self._rearm()
            return "Toni meldet sich wieder von selbst"
        self._silenced = True
        self._pending.clear()
        self._rearm()
        return "Toni schweigt bis zum Fahrtende ungefragt; Fragen beantwortet er weiter"

    # --- Sprechtaste ------------------------------------------------------------------------------------------

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
        self._spawn(self._reply())

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
            async with self._brain_lock:
                await self._ensure_session()
                ride = prompts.ride_line(self._watch.last) if self._riding else None
                async for item in self._brain.respond(prompts.question_prompt(question, ride)):
                    if isinstance(item, ToolCall):
                        self._log(f"Werkzeug {item.name} {item.arguments}")
                    else:
                        parts.append(item)
            answer = prompts.spoken_text(parts, self._riding and self._hard_phase())
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

    # --- Status -----------------------------------------------------------------------------------------------

    async def _hoarse(self, port: str, exc: Exception) -> None:
        self._log(f"Toni ist heiser – {port}: {type(exc).__name__}: {exc}")
        if port == "Brain":
            self._session_broken = True
        await self._set_state(HOARSE)

    async def _set_state(self, state: str) -> None:
        if state == self._state:
            return
        self._state = state
        await self._send_status()
        if state == IDLE:
            self._rearm()  # Anlässe, die während Frage oder Antwort kamen, kommen jetzt dran

    async def _send_status(self) -> None:
        await self._bus.send(status_message(self._state))

    def _spawn(self, coroutine: Coroutine) -> asyncio.Task:
        task = asyncio.create_task(coroutine)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        return task


def _text_arg(args: dict, name: str) -> str:
    value = args.get(name)
    if not isinstance(value, str):
        raise ValueError(f"{name!r} muss ein Text sein, war {value!r}")
    return value


def _is_version(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == PROTOCOL_VERSION
