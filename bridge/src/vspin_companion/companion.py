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
from dataclasses import dataclass
from pathlib import Path

from . import prompts
from .bus import BusClient
from .config import CompanionConfig, ConfigError, save_wake_interval
from .notes import MEMORY, NOTES, SOUL, Notebook, NoteRefused
from .ports import Brain, Clock, Ears, Mouth, ToolCall, ToolResult
from .protocol_log import TARGET_LATENCY_S, ProtocolLog
from .utterance import Utterance
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

FINAL_COST_TIMEOUT_S = 3.0  # letzte Kostenabfrage beim Beenden darf das Prozessende kaum verzögern
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
        self._protocol = ProtocolLog(data_dir, log)
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
        # Antwort in Rede (Barge-in bricht sie ab)
        self._replying: asyncio.Task | None = None
        self._utterance: Utterance | None = None
        self._volume: float | None = None  # zuletzt gemeldetes `companion_volume` (0..1)
        self._latencies: list[float] = []  # Antwortzeiten der laufenden Fahrt
        self._cost_jobs: list[_CostJob] = []  # Fahrten, deren Kosten OpenRouter noch nicht geliefert hat

    @property
    def state(self) -> str:
        return self._state

    async def run(self, stop: asyncio.Event) -> None:
        """Läuft, bis `stop` gesetzt wird; Fehler der Ports beenden ihn nie."""
        self._log("vspin-companion: Toni ist da")
        try:
            await self._bus.run(stop)
        finally:
            with contextlib.suppress(Exception):
                await self._mouth.stop()  # Wiedergabe und Synthese enden, kein Thread verzögert das Prozessende
            tasks = list(self._tasks)
            for task in tasks:
                task.cancel()
            for task in tasks:
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await task
            await self._settle_costs()
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
            self._apply_volume(event)
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
        self._latencies = []
        self._discard_usage()  # was vor der Fahrt gesprochen wurde, gehört nicht in ihr Protokoll
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
        self._protocol_ride(self._take_usage(), self._latencies)
        self._latencies = []

    def _ride_state(self, state: dict) -> None:
        self._apply_volume(state)
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
        speech: Utterance | None = None
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
            async with self._brain_lock:
                if not self._wake_allowed():  # Fahrt endete oder `stay_silent`, während Toni wartete
                    return
                hard = self._hard_phase()
                await self._ensure_session()
                prompt = prompts.wake_prompt(occasions, prompts.ride_line(self._watch.last), hard)
                speech = self._utterance = Utterance(
                    self._mouth,
                    one_sentence=lambda: hard or self._hard_phase(),
                    gate=self._wake_gate,
                    on_sound=self._wake_sound,
                )
                async for item in self._brain.respond(prompt):
                    if isinstance(item, ToolCall):
                        self._log(f"Werkzeug {item.name} {item.arguments}")
                    else:
                        speech.feed(item)
            port = "Mouth"
            await speech.finish()
            if not speech.sentences:
                self._log("Wecker: Toni schweigt")
                return
            port = "Clock"
            self._last_unprompted_at = self._clock.now()  # die Minute Schweigen zählt ab dem Ende des Satzes
            await self._set_state(IDLE)
        except Exception as exc:
            if speech is not None and speech.sentences:
                speech.cancel()
                with contextlib.suppress(Exception):
                    await self._mouth.stop()
            await self._hoarse(port, exc)
        finally:
            if speech is not None and self._utterance is speech:  # die Antwort auf eine Frage bleibt stehen
                self._utterance = None
            self._waking = None
            self._rearm()

    def _wake_gate(self) -> bool:
        """Vor dem ersten Satz des Weckers: Toni darf nur sprechen, wenn er noch `idle` ist (nicht angesprochen
        wurde) und der Wecker noch gilt; die Minute Schweigen beginnt mit dem Satz."""
        if self._state != IDLE or not self._wake_allowed():
            return False
        self._last_unprompted_at = self._clock.now()
        return True

    async def _wake_sound(self) -> None:
        if self._state == IDLE:
            await self._set_state(SPEAKING)

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
        if self._state in (THINKING, SPEAKING) or self._speech_in_flight():
            await self._barge_in()
        elif self._state not in (IDLE, HOARSE):
            return  # Toni hört schon zu
        try:
            await self._ears.start_listening()
        except Exception as exc:
            await self._hoarse("Ears", exc)
            return
        await self._set_state(LISTENING)

    def _speech_in_flight(self) -> bool:
        return self._utterance is not None and bool(self._utterance.sentences)

    async def _barge_in(self) -> None:
        """Der Fahrer unterbricht Toni (Story 5): Antwort-Aufgabe und offene Sätze abbrechen, Wiedergabe und
        Synthese des Mundes stoppen. Danach hört Toni zu."""
        self._log("Barge-in: Toni wird unterbrochen")
        current = asyncio.current_task()
        tasks = [t for t in (self._replying, self._waking) if t is not None and t is not current and not t.done()]
        for task in tasks:
            task.cancel()
        if self._utterance is not None:
            self._utterance.cancel()
        self._replying = None
        try:
            await self._mouth.stop()
        except Exception as exc:
            await self._hoarse("Mouth", exc)
        # Die abgebrochenen Aufgaben räumen im Hintergrund auf (das Brain braucht dafür bis zu 3 s); die ersten
        # Wörter des Fahrers warten nicht darauf. Brain-Zugriffe bleiben nacheinander (`_brain_lock`).

    async def _ptt_up(self) -> None:
        if self._state != LISTENING:
            return
        await self._set_state(THINKING)
        # Eigene Aufgabe: Der Bus liest weiter, während Toni denkt und spricht.
        self._replying = self._spawn(self._reply())

    async def _reply(self) -> None:
        port = "Clock"
        speech: Utterance | None = None
        try:
            released = self._clock.now()  # Antwortzeit zählt ab dem Loslassen, inklusive Erkennung
            port = "Ears"
            question = await self._ears.stop_listening()
            if not question.strip():
                self._log("Sprechtaste: nichts verstanden")
                await self._set_state(IDLE)
                return
            self._log(f"Frage: {question}")
            port = "Brain"

            async def on_sound() -> None:
                await self._question_sound(released, speech)

            speech = self._utterance = Utterance(
                self._mouth, one_sentence=lambda: self._riding and self._hard_phase(), on_sound=on_sound
            )
            async with self._brain_lock:
                await self._ensure_session()
                ride = prompts.ride_line(self._watch.last) if self._riding else None
                async for item in self._brain.respond(prompts.question_prompt(question, ride)):
                    if isinstance(item, ToolCall):
                        self._log(f"Werkzeug {item.name} {item.arguments}")
                    else:
                        speech.feed(item)
            port = "Mouth"
            await speech.finish()
        except Exception as exc:
            if speech is not None and speech.sentences:
                speech.cancel()
                with contextlib.suppress(Exception):
                    await self._mouth.stop()
            await self._hoarse(port, exc)
            return
        finally:
            if self._utterance is speech:
                self._utterance = None
        await self._set_state(IDLE)

    async def _question_sound(self, released: float, speech: Utterance | None) -> None:
        """Der erste Ton der Antwort spielt: Antwortzeit ins Protokoll (Ziel ≤ 2,5 s), Status `speaking`."""
        latency_s = self._clock.now() - released
        self._latencies.append(latency_s)
        first = speech.sentences[0] if speech is not None and speech.sentences else ""
        self._log(f"Antwort nach {latency_s:.2f} s: {first}")
        self._protocol.write(
            {"type": "answer", "latency_s": round(latency_s, 2), "within_target": latency_s <= TARGET_LATENCY_S}
        )
        if self._state == THINKING:
            await self._set_state(SPEAKING)

    # --- Lautstärke, Kosten und Protokoll ----------------------------------------------------------------------

    def _apply_volume(self, message: dict) -> None:
        """`companion_volume` (0..1) aus `ride_state` und `ride_start`: der zuletzt empfangene Wert gilt; fehlt er
        oder ist er keine Zahl, bleibt es, wie es war (Standard des Mundes: 1,0)."""
        volume = message.get("companion_volume")
        if isinstance(volume, bool) or not isinstance(volume, (int, float)) or volume != volume:
            return
        volume = min(1.0, max(0.0, float(volume)))
        if volume != self._volume:
            self._volume = volume
            self._mouth.set_volume(volume)

    def _take_usage(self):
        try:
            return self._mouth.take_usage()
        except Exception as exc:
            self._log(f"Sprachverbrauch nicht lesbar – {type(exc).__name__}: {exc}")
            return None

    def _discard_usage(self) -> None:
        usage = self._take_usage()
        if usage is not None and usage.requests:
            self._log(f"Sprachverbrauch vor der Fahrt ({usage.chars} Zeichen) zählt nicht zur Fahrt")

    def _protocol_ride(self, usage, latencies: list[float]) -> None:
        """Protokoll der Fahrt bei `ride_end`: Zeichen und Antwortzeiten sofort, die Kosten aus OpenRouters
        Generation-API als Nachtrag (`ride_cost`) – die gibt den Datensatz erst kurz nach der Synthese her."""
        record: dict = {
            "type": "ride",
            "answers": len(latencies),
            "latency_avg_s": round(sum(latencies) / len(latencies), 2) if latencies else None,
            "latency_max_s": round(max(latencies), 2) if latencies else None,
            "over_target": sum(1 for value in latencies if value > TARGET_LATENCY_S),
        }
        if usage is None:
            self._protocol.write({**record, "chars": None, "requests": None, "total_cost_usd": None, "cost": "unknown"})
            return
        ids = list(usage.generation_ids)
        record.update(chars=usage.chars, requests=usage.requests, generations=ids, aborted_requests=usage.aborted)
        if not usage.requests:
            self._protocol.write({**record, "total_cost_usd": 0.0, "unknown_generations": 0, "lower_bound": usage.aborted > 0})
            return
        ride_end_at = self._protocol.write({**record, "total_cost_usd": None, "cost": "pending"})
        # Anfragen ohne `X-Generation-Id`: ihre Kosten sind nicht abholbar
        job = _CostJob(ride_end_at, ids, usage.requests - len(ids), usage.aborted)
        self._cost_jobs.append(job)
        self._spawn(self._collect_cost(job))

    async def _collect_cost(self, job: "_CostJob") -> None:
        """Eigene Aufgabe: wartet auf OpenRouter, ohne Fahrt oder Antwortzeit zu stören."""
        costs: dict[str, float] = {}
        try:
            costs = await self._mouth.cost_of(job.ids)
        except Exception as exc:
            self._log(f"Sprachkosten nicht abgeholt – {type(exc).__name__}: {exc}")
        self._write_cost(job, costs)

    async def _settle_costs(self) -> None:
        """Beim Beenden: jede Fahrt, deren Kosten noch ausstehen, bekommt eine letzte Abfrage ohne Wartezeit; was
        dann bekannt ist, steht im Protokoll, der Rest bleibt unbekannt."""
        for job in list(self._cost_jobs):
            costs: dict[str, float] = {}
            try:
                costs = await asyncio.wait_for(self._mouth.cost_of(job.ids, patient=False), FINAL_COST_TIMEOUT_S)
            except Exception as exc:
                self._log(f"Sprachkosten beim Beenden nicht abgeholt – {type(exc).__name__}: {exc}")
            self._write_cost(job, costs)

    def _write_cost(self, job: "_CostJob", costs: dict[str, float]) -> None:
        if job not in self._cost_jobs:
            return
        self._cost_jobs.remove(job)
        unknown = job.unidentified + len([i for i in job.ids if i not in costs])
        total = round(sum(costs.values()), 6) if costs or not unknown else None
        self._protocol.write(
            {
                "type": "ride_cost",
                "ride_end_at": job.ride_end_at,
                "total_cost_usd": total,
                "unknown_generations": unknown,
                "aborted_requests": job.aborted,
                # abgebrochene Synthesen sind womöglich berechnet, aber nirgends zu sehen: dann nur eine Untergrenze
                "lower_bound": unknown > 0 or job.aborted > 0,
            }
        )
        self._log(f"Sprachkosten der Fahrt: {total if total is not None else 'unbekannt'} $ ({unknown} unbekannt)")

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


@dataclass
class _CostJob:
    ride_end_at: str
    ids: list[str]
    unidentified: int
    aborted: int


def _text_arg(args: dict, name: str) -> str:
    value = args.get(name)
    if not isinstance(value, str):
        raise ValueError(f"{name!r} muss ein Text sein, war {value!r}")
    return value


def _is_version(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == PROTOCOL_VERSION
