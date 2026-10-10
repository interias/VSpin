"""Bridge-Ablauf: DeviceSource → (Parser) → Datenaufbereitung → Bus + Session,
Statuszeile im Terminal, Tastatur für den Simulator."""

import asyncio
import contextlib
import time
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path

from .bus import HOST, PORT, BusServer
from .bus.messages import (
    SET_GRADE,
    ClientMessageError,
    SetGrade,
    ack_message,
    error_message,
    parse_client_message,
    status_message,
    telemetry_message,
)
from .clock import bridge_time_ms
from .console import Console
from .keyboard import HELP, Key, Keyboard, keyboard_available
from .parsers import Decoder, ParseError
from .processing import CADENCE_MAX, CADENCE_MIN, CadenceProcessor
from .session import Session, open_session
from .sources.base import (
    Capability,
    DeviceSource,
    NotSupportedError,
    RawNotification,
    SourceDisconnectedError,
    TelemetrySample,
)
from .sources.sim import SimulatorSource

# Verbindungsstatus (ADR-0004). Jede Änderung geht genau einmal als `status` auf den Bus.
CONNECTED = "connected"
STALE = "stale"
DISCONNECTED = "disconnected"

STALE_AFTER_S = 3.0  # verbunden, aber so lange keine Daten → stale (ADR-0004)
CLOCK_RESOLUTION_S = time.get_clock_info("monotonic").resolution  # Takt von Bridge-Zeit und Event-Loop
RECONNECT_INTERVAL_S = 3.0  # nach einem Abbruch alle 3 s neu verbinden (ADR-0004)

CADENCE_STEP = 5.0

DEFAULT_SESSIONS_DIR = Path("sessions")  # relativ zum Arbeitsverzeichnis der Bridge


class SessionStartError(Exception):
    """Die Session-Dateien konnten nicht angelegt werden (z. B. Verzeichnis nicht beschreibbar)."""


class Bridge:
    def __init__(
        self,
        source: DeviceSource,
        console: Console,
        sessions_dir: Path = DEFAULT_SESSIONS_DIR,
        wait_for_client: bool = False,
        host: str = HOST,
        port: int = PORT,
    ) -> None:
        self._source = source
        self._sessions_dir = sessions_dir
        self._wait_for_client = wait_for_client
        self._session: Session | None = None
        # Datenaufbereitung (ADR-0004) für alle Quellen; Parser-Zustand je Verbindung.
        self._processor = CadenceProcessor(reports_cadence=Capability.CADENCE in source.capabilities)
        self._decoder = Decoder()
        self._reported: set[str] = set()  # schon im Terminal gemeldete Parser-Probleme
        self._console = console
        self._state = DISCONNECTED
        self._cadence: float | None = None
        self._grade: float | None = None
        self._bus = BusServer(
            self._status_message,
            on_clients_changed=self._on_clients_changed,
            on_message=self._on_client_message,
            host=host,
            port=port,
        )
        self._stop: asyncio.Event | None = None
        self._stale_timer: asyncio.TimerHandle | None = None
        self._stale_since_ms = 0  # Bridge-Zeit des letzten Samples (bzw. der Verbindung)
        self._first_client = asyncio.Event()

    async def run(self, stop: asyncio.Event) -> None:
        """Läuft, bis `stop` gesetzt wird. Wirft `BusStartError`, wenn der Bus-Port belegt ist,
        und `SessionStartError`, wenn die Session-Dateien nicht angelegt werden können."""
        self._stop = stop
        await self._bus.start()
        keyboard: Keyboard | None = None
        try:
            self._console.info(f"vspin-bridge: Bus auf ws://{self._bus.host}:{self._bus.port}")
            # Session = ein Bridge-Lauf (ADR-0008); erst nach erfolgreichem Bus-Start.
            try:
                self._session = open_session(self._sessions_dir)
            except OSError as exc:
                raise SessionStartError(f"{self._sessions_dir}: {exc.strerror or exc}") from exc
            self._console.info(f"Session: {self._session.csv.path}")
            self._console.info(f"Rohdaten: {self._session.raw.path}")
            if isinstance(self._source, SimulatorSource) and keyboard_available():
                keyboard = Keyboard(self._on_key)
                keyboard.start()
                self._console.info(HELP)
            if isinstance(self._source, SimulatorSource) and self._source.profile is not None:
                profile = self._source.profile
                repeat = ", wiederholt" if profile.repeat else ""
                self._console.info(
                    f"Profil: {profile.name} ({len(profile.steps)} Schritte{repeat}) – gibt die Kadenz vor"
                )
            self._render()

            if self._wait_for_client:
                self._console.info("Warte auf den ersten Client am Bus …")
            pump = asyncio.create_task(self._pump())
            stopped = asyncio.create_task(stop.wait())
            await asyncio.wait({pump, stopped}, return_when=asyncio.FIRST_COMPLETED)
            if pump.done() and pump.exception() is not None:
                raise pump.exception()
            await stop.wait()  # Quelle beendet → Bus bleibt bis zum Stopp erreichbar
            for task in (pump, stopped):
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
        finally:
            self._cancel_stale_timer()
            if keyboard is not None:
                keyboard.stop()
            await self._bus.stop()
            if self._session is not None:
                self._session.close()  # alle Zeilen sind schon geflusht
            self._console.close()

    async def _pump(self) -> None:
        """Verbinden, Samples weiterreichen; nach einem Abbruch alle 3 s neu verbinden."""
        if self._wait_for_client:
            await self._first_client.wait()
        while True:
            try:
                await self._source.connect()
                self._decoder = Decoder()  # neue Verbindung: Zählerstände (CSC) neu
                self._set_state(CONNECTED, "Quelle verbunden")
                self._arm_stale_timer()
                async for item in self._source.samples():
                    if isinstance(item, RawNotification):
                        self._on_raw(item)
                    else:
                        self._on_sample(item)
            except SourceDisconnectedError as exc:
                if self._state == DISCONNECTED:
                    retry = f"neuer Versuch in {RECONNECT_INTERVAL_S:g} s"
                    self._console.info(f"Verbindung gescheitert: {exc} – {retry}")
                self._set_state(DISCONNECTED, str(exc))
                await asyncio.sleep(RECONNECT_INTERVAL_S)
                continue
            self._set_state(DISCONNECTED, "Quelle beendet")
            return

    def _on_raw(self, raw: RawNotification) -> None:
        """Rohe Notification: in die Session-Rohdatei, dann durch die Parser."""
        self._log_session(lambda session: session.raw.write(raw))
        char = raw.char.lower()
        try:
            sample = self._decoder.decode(raw)
        except ParseError as exc:
            self._report_once(f"parse:{char}", f"Notification verworfen ({char}): {exc}")
            return
        if sample is None:
            self._report_once(f"unknown:{char}", f"Characteristic {char} wird nicht ausgewertet")
            return
        self._on_sample(sample)

    def _report_once(self, key: str, text: str) -> None:
        if key not in self._reported:
            self._reported.add(key)
            self._console.info(text + " (weitere gleiche Meldungen unterdrückt)")

    def _on_sample(self, sample: TelemetrySample) -> None:
        # Daten nach einer Lücke: erst `status: connected`, dann die Telemetrie.
        self._set_state(CONNECTED, "wieder Daten")
        # Aufbereitung auf der Zeitachse der Quelle, am Bus dann die Bridge-Zeit (ADR-0004).
        processed = self._processor.process(sample)
        if processed.discarded:
            self._console.info(
                f"Kadenz {processed.cadence_raw:.1f} rpm verworfen "
                f"(außerhalb {CADENCE_MIN:.0f}–{CADENCE_MAX:.0f} rpm)"
            )
        published = replace(processed.sample, t_ms=bridge_time_ms())
        self._arm_stale_timer(published.t_ms)
        self._cadence = published.cadence
        self._bus.publish(telemetry_message(published))
        # Eine CSV-Zeile pro Sample am Bus – ohne `await` dazwischen, also nie nur eins von beiden.
        self._log_session(
            lambda session: session.csv.write(published, processed.cadence_raw, self._grade, self._state)
        )
        self._render()

    def _log_session(self, write: Callable[[Session], None]) -> None:
        """Schreibt in die Session-Dateien. Scheitert das (z. B. Platte voll), endet das Logging
        dieser Session mit einer Meldung; Bridge und Bus laufen weiter. Was bis dahin
        geschrieben war, bleibt lesbar (jede Zeile ist geflusht)."""
        if self._session is None:
            return
        try:
            write(self._session)
        except OSError as exc:
            session, self._session = self._session, None
            with contextlib.suppress(OSError):
                session.close()
            self._console.info(
                f"Session-Logging beendet – Schreibfehler: {exc.strerror or exc} "
                f"({session.csv.path}). Bridge läuft weiter, ohne Session-Dateien."
            )

    def _arm_stale_timer(self, since_ms: int | None = None) -> None:
        """(Neu) starten: kommt STALE_AFTER_S lang kein Sample, wird der Status `stale`.
        Kadenz 0 ist ein normales Sample – nur ausbleibende Daten zählen. `since_ms`: Bridge-Zeit
        des letzten Samples (Standard: jetzt)."""
        self._stale_since_ms = bridge_time_ms() if since_ms is None else since_ms
        self._schedule_stale(STALE_AFTER_S)

    def _schedule_stale(self, delay_s: float) -> None:
        self._cancel_stale_timer()
        loop = asyncio.get_running_loop()
        self._stale_timer = loop.call_later(delay_s, self._on_stale)

    def _cancel_stale_timer(self) -> None:
        if self._stale_timer is not None:
            self._stale_timer.cancel()
            self._stale_timer = None

    def _on_stale(self) -> None:
        self._stale_timer = None
        # Der Event-Loop löst Timer bis zu einer Uhr-Auflösung zu früh aus (Windows: 15,6 ms) –
        # `stale` erst, wenn auf der Bridge-Zeit wirklich STALE_AFTER_S vergangen sind.
        remaining_ms = STALE_AFTER_S * 1000 - (bridge_time_ms() - self._stale_since_ms)
        if remaining_ms > 0:
            self._schedule_stale(remaining_ms / 1000 + CLOCK_RESOLUTION_S)
            return
        if self._state == CONNECTED:
            self._set_state(STALE, f"seit {STALE_AFTER_S:g} s keine Daten")

    @property
    def grade(self) -> float | None:
        """Zuletzt per `set_grade` gesetzte virtuelle Steigung (Anteil) – für das Session-Logging."""
        return self._grade

    async def _on_client_message(self, raw: str | bytes) -> str:
        """Antwort (`ack`/`error`) für genau den Client, der `raw` gesendet hat."""
        try:
            message = parse_client_message(raw)
        except ClientMessageError as exc:
            return error_message(exc.reason, exc.detail)
        return await self._set_grade(message)

    async def _set_grade(self, message: SetGrade) -> str:
        self._grade = message.grade
        # Andockpunkt Widerstandssteuerung: eine Quelle mit RESISTANCE_CONTROL setzt die
        # Steigung um, alle anderen werfen NotSupportedError (ADR-0003, ADR-0007) – der
        # Simulator wertet sie vorher trotzdem aus.
        detail = ""
        try:
            await self._source.set_grade(message.grade)
        except NotSupportedError:
            ok, reason = False, "not_supported"
        except Exception as exc:  # Quelle scheitert anders: Absender bekommt ack, Verbindung bleibt
            ok, reason, detail = False, "source_error", f" ({exc})"
        else:
            ok, reason = True, None
        result = ("ok" if ok else reason) + detail
        self._console.info(f"set_grade {message.grade:+.3f} ({message.grade * 100:+.1f} %) -> {result}")
        self._render()
        return ack_message(SET_GRADE, ok, reason)

    def _status_message(self) -> str:
        return status_message(
            bridge_time_ms(), self._state, self._source.name, self._source.capabilities
        )

    def _set_state(self, state: str, reason: str) -> None:
        if state == self._state:
            return
        self._state = state
        if state != CONNECTED:
            self._cancel_stale_timer()
        self._bus.publish(self._status_message())  # genau ein `status` je Änderung
        self._console.info(f"Status: {state} ({reason})")
        self._render()

    def _on_clients_changed(self, count: int) -> None:
        if count > 0:
            self._first_client.set()
        self._render()

    def _on_key(self, key: Key) -> None:
        if key is Key.QUIT:
            if self._stop is not None:
                self._stop.set()
        elif isinstance(self._source, SimulatorSource):
            self._source.adjust_cadence(CADENCE_STEP if key is Key.UP else -CADENCE_STEP)

    def _render(self) -> None:
        self._console.show(self._source.name, self._state, self._cadence, self._bus.client_count)
