"""Tonis Mund im Gespräch (Spec #76, #79): Satz für Satz sprechen, während Haiku noch schreibt, Barge-in per Sprechtaste,
Antwortzeit ab dem Loslassen, Lautstärke des Spiels, Kosten- und Latenzprotokoll je Fahrt – über einen echten Bus, nur mit
Fakes (kein Claude, kein OpenRouter, kein Mikrofon, kein Ton)."""

import asyncio
import json
import threading
import time

import pytest
from bridge_harness import receive_json, wait_until
from companion_harness import assert_no_status, next_status, ptt
from vspin_companion.fakes import FakeBrain, FakeClock, FakeEars, FakeMouth

SETTLE_S = 0.3


class GatedBrain(FakeBrain):
    """Liefert je Anfrage die Stücke aus `scripts` (`(stücke, warte_vor)`); vor dem Stück `warte_vor` wartet er auf
    `gate` – Haiku „schreibt noch“. Merkt sich, ob eine Antwort zu Ende kam (`finished`) oder abgebrochen wurde."""

    def __init__(self, *scripts):
        super().__init__()
        self.scripts = list(scripts)
        self.gate = threading.Event()
        self.finished = 0
        self.cancelled = 0

    async def respond(self, prompt):
        self.prompts.append(prompt)
        pieces, wait_before = self.scripts.pop(0)
        try:
            for index, piece in enumerate(pieces):
                while index == wait_before and not self.gate.is_set():
                    await asyncio.sleep(0.01)
                yield piece
            self.finished += 1
        except asyncio.CancelledError:
            self.cancelled += 1
            raise


def start(bridge_process, bus_client, in_process_companion, brain, ears=None, mouth=None, clock=None, **kwargs):
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    mouth, clock = mouth or FakeMouth(), clock or FakeClock()
    companion = in_process_companion(brain, ears or FakeEars(), mouth, clock, **kwargs)
    assert next_status(game)["state"] == "idle"
    return game, companion, clock, mouth


def states(game, count: int) -> list[str]:
    return [next_status(game)["state"] for _ in range(count)]


def ask(game) -> None:
    ptt(game, "down")
    ptt(game, "up")


def send(game, **message) -> None:
    game.send(json.dumps({"v": 0, **message}))


def ride_start(game, **fields) -> None:
    send(game, type="ride_event", kind="ride_start", mode="rundfahrt", direction="cw", laps=1, **fields)
    assert next_status(game)["state"] == "idle"


def records(companion) -> list[dict]:
    path = companion.data_dir / "protocol.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


# --- Satz für Satz ------------------------------------------------------------------------------------------------


def test_the_first_sentence_is_spoken_while_haiku_is_still_writing(bridge_process, bus_client, in_process_companion):
    brain = GatedBrain((["Das ist der erste ", "Satz. Und der ", "zweite Satz."], 2))
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Erzähl was"])
    )
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "speaking"]  # `speaking` mit dem ersten Ton
    wait_until(lambda: mouth.spoken == ["Das ist der erste Satz."], 5.0, "erster Satz im Mund")
    assert brain.finished == 0  # Haiku schreibt noch
    brain.gate.set()
    assert next_status(game)["state"] == "idle"
    assert mouth.spoken == ["Das ist der erste Satz.", "Und der zweite Satz."]
    assert mouth.played == mouth.spoken and mouth.stops == 0


# --- Barge-in -----------------------------------------------------------------------------------------------------


def test_ptt_down_while_toni_speaks_stops_playback_and_the_pending_sentences(
    bridge_process, bus_client, in_process_companion
):
    brain = GatedBrain((["Erster Satz. ", "Zweiter Satz. ", "Dritter Satz."], 1), (["Antwort auf die zweite Frage."], None))
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain,
        ears=FakeEars(["Frage eins", "Frage zwei"]), mouth=FakeMouth(hold=True),
    )
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "speaking"]
    wait_until(lambda: mouth.spoken == ["Erster Satz."], 5.0, "erster Satz spielt")

    ptt(game, "down")  # Barge-in
    assert next_status(game)["state"] == "listening"
    wait_until(lambda: brain.cancelled == 1, 5.0, "Antwort abgebrochen")
    assert mouth.stops == 1 and mouth.played == []  # Wiedergabe abgebrochen, nichts mehr ausgegeben
    brain.gate.set()  # Haiku „schriebe“ weiter – die abgebrochenen Sätze kommen nie im Mund an
    assert_no_status(game, SETTLE_S)
    assert mouth.spoken == ["Erster Satz."] and brain.finished == 0
    assert "Barge-in" in companion.log() and companion.alive and companion.error is None

    mouth.release()
    ptt(game, "up")  # die neue Frage wird ganz normal beantwortet
    assert states(game, 3) == ["thinking", "speaking", "idle"]
    assert mouth.spoken[-1] == "Antwort auf die zweite Frage." and brain.prompts[-1] == "Frage: Frage zwei"
    assert len(brain.sessions) == 1  # dieselbe Sitzung, nichts ging verloren


def test_ptt_down_while_toni_is_still_thinking_cancels_the_answer_too(bridge_process, bus_client, in_process_companion):
    brain = GatedBrain((["Das kommt nie."], 0), (["Danach geht es."], None))
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Eins", "Zwei"])
    )
    ask(game)
    assert states(game, 2) == ["listening", "thinking"]
    ptt(game, "down")
    assert next_status(game)["state"] == "listening"
    wait_until(lambda: brain.cancelled == 1, 5.0, "Antwort abgebrochen")
    assert mouth.spoken == []
    ptt(game, "up")
    assert states(game, 3) == ["thinking", "speaking", "idle"]
    assert mouth.spoken == ["Danach geht es."]


def test_ptt_down_interrupts_an_unprompted_remark_too(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Bestzeit! Du Tier!"]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, mouth=FakeMouth(hold=True)
    )
    ride_start(game)
    send(game, type="ride_event", kind="best_time", time_s=1200, previous_s=1250)
    assert next_status(game)["state"] == "speaking"
    ptt(game, "down")
    assert next_status(game)["state"] == "listening"
    assert mouth.stops == 1 and mouth.played == []
    assert companion.alive and companion.error is None


def test_a_failing_mouth_mid_answer_stops_the_rest_and_makes_toni_hoarse(
    bridge_process, bus_client, in_process_companion
):
    class FailsOnSecond(FakeMouth):
        async def speak(self, sentence, on_start=None):
            if sentence == "Zweiter Satz.":
                raise ConnectionError("kein Netz")
            await super().speak(sentence, on_start)

    brain = FakeBrain([["Erster Satz. Zweiter Satz. Dritter Satz."]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Hallo"]),
        mouth=FailsOnSecond(hold=True),
    )
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "hoarse"]
    assert mouth.stops == 1 and mouth.played == []  # der laufende Satz wird mit abgebrochen
    assert "Toni ist heiser – Mouth: ConnectionError: kein Netz" in companion.log()
    assert companion.alive and companion.error is None


# --- Antwortzeit ----------------------------------------------------------------------------------------------------


def test_latency_counts_from_the_release_including_recognition_until_the_first_sound(
    bridge_process, bus_client, in_process_companion
):
    clock = FakeClock()

    class SlowEars(FakeEars):
        async def stop_listening(self):
            clock.advance(self.delays.pop(0))  # die Erkennung dauert (läuft im Loop des Begleiters)
            return await super().stop_listening()

    class SlowBrain(FakeBrain):
        async def respond(self, prompt):
            clock.advance(0.5)  # Haiku braucht bis zum ersten Stück
            async for item in super().respond(prompt):
                yield item

    ears = SlowEars(["Eins", "Zwei"])
    ears.delays = [1.0, 4.0]
    brain = SlowBrain([["Erster Satz. Zweiter Satz."], ["Noch ein Satz."]])
    game, companion, _, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=ears, clock=clock
    )
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    wait_until(lambda: len(records(companion)) == 1, 5.0, "erste Antwortzeit protokolliert")
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    wait_until(lambda: len(records(companion)) == 2, 5.0, "zweite Antwortzeit protokolliert")
    first, second = records(companion)
    assert (first["type"], first["latency_s"], first["within_target"]) == ("answer", 1.5, True)  # 1,0 + 0,5
    assert (second["latency_s"], second["within_target"]) == (4.5, False)  # über dem Ziel von 2,5 s
    assert "Antwort nach 1.50 s: Erster Satz." in companion.log()  # bis zum ersten Ton, nicht bis zum letzten Satz


# --- Lautstärke -----------------------------------------------------------------------------------------------------


def test_the_mouth_follows_the_last_companion_volume_from_the_game(bridge_process, bus_client, in_process_companion):
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, FakeBrain())
    send(game, type="ride_state", companion_volume=0.3)  # auch ohne Fahrt
    wait_until(lambda: mouth.volumes == [0.3], 5.0, "Lautstärke 0,3")
    ride_start(game, companion_volume=0.8)
    wait_until(lambda: mouth.volumes == [0.3, 0.8], 5.0, "Lautstärke aus ride_start")
    for value in (0.8, "laut", True, None, [0.1]):  # gleich geblieben oder unbrauchbar: bleibt, wie es war
        send(game, type="ride_state", companion_volume=value)
    send(game, type="ride_state", km_done=1.0)  # fehlt: bleibt
    send(game, type="ride_state", companion_volume=7)
    wait_until(lambda: mouth.volumes == [0.3, 0.8, 1.0], 5.0, "Werte außerhalb 0..1 werden begrenzt")
    time.sleep(SETTLE_S)
    assert mouth.volumes == [0.3, 0.8, 1.0]


# --- Protokoll je Fahrt -----------------------------------------------------------------------------------------------

COST_CASES = [
    # gen-1 gehört zur Antwort vor der Fahrt; die Fahrt sind gen-2 und gen-3
    pytest.param({"costs": {"gen-1": 9.0, "gen-2": 0.003, "gen-3": 0.001}}, None, 0.004, 0, id="alles-bekannt"),
    pytest.param({"costs": {"gen-2": 0.003}}, None, 0.003, 1, id="eine-fehlt"),
    pytest.param({"generation_ids": False}, None, None, 2, id="ohne-generation-id"),
    pytest.param({"costs": {"gen-2": 0.003, "gen-3": 0.001}}, ConnectionError("kein Netz"), None, 2, id="abruf-scheitert"),
]


@pytest.mark.parametrize(("mouth_options", "cost_error", "total", "unknown"), COST_CASES)
def test_the_ride_protocol_has_chars_latencies_and_the_cost_from_the_generation_api(
    bridge_process, bus_client, in_process_companion, mouth_options, cost_error, total, unknown
):
    brain = FakeBrain([["Vorab."], ["Noch 5 km."], ["Gleich da."]])
    mouth = FakeMouth(**mouth_options)
    mouth.fail_cost = cost_error
    game, companion, clock, _ = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["a", "b", "c"]), mouth=mouth
    )
    ask(game)  # vor der Fahrt gesprochen: zählt nicht zur Fahrt
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    ride_start(game)
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    send(game, type="ride_event", kind="ride_end", finished=True, distance_km=9.0, duration_s=1500)
    wait_until(lambda: any(r["type"] == "ride_cost" for r in records(companion)), 5.0, "Kosten protokolliert")

    ride = next(r for r in records(companion) if r["type"] == "ride")
    cost = next(r for r in records(companion) if r["type"] == "ride_cost")
    assert (ride["answers"], ride["chars"], ride["requests"]) == (2, len("Noch 5 km.") + len("Gleich da."), 2)
    assert (ride["latency_avg_s"], ride["latency_max_s"], ride["over_target"]) == (0.0, 0.0, 0)
    assert (ride["total_cost_usd"], ride["cost"]) == (None, "pending")  # zum Fahrtende noch nicht abgeholt
    assert ride["generations"] == ([] if "generation_ids" in mouth_options else ["gen-2", "gen-3"])
    assert (cost["total_cost_usd"], cost["unknown_generations"], cost["ride_end_at"]) == (total, unknown, ride["at"])
    assert ride["at"]


def test_a_ride_without_speech_costs_nothing_and_the_protocol_says_so(bridge_process, bus_client, in_process_companion):
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, FakeBrain())
    ride_start(game)
    send(game, type="ride_event", kind="ride_end", finished=True, distance_km=1.0, duration_s=60)
    wait_until(lambda: records(companion), 5.0, "Fahrt protokolliert")
    (ride,) = records(companion)
    assert (ride["answers"], ride["chars"], ride["requests"], ride["total_cost_usd"]) == (0, 0, 0, 0.0)
    assert ride["latency_avg_s"] is None and mouth.cost_calls == []  # nichts zu fragen, nichts zu schätzen


# --- Runde 2 (Review): Barge-in ohne Verzögerung, Wecker neben einer Antwort, Beenden ------------------------------


class SlowAbandon(GatedBrain):
    """Räumt nach dem Abbruch 1 s auf – wie `ClaudeBrain._abandon` (interrupt + Rest wegleesen, bis 3 s)."""

    async def respond(self, prompt):
        try:
            async for piece in super().respond(prompt):
                yield piece
        except asyncio.CancelledError:
            await asyncio.sleep(1.0)
            raise


def test_barge_in_starts_listening_at_once_while_the_old_answer_cleans_up_in_the_background(
    bridge_process, bus_client, in_process_companion
):
    brain = SlowAbandon((["Erster Satz. ", "Zweiter."], 1), (["Neue Antwort."], None))
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain,
        ears=FakeEars(["Eins", "Zwei"]), mouth=FakeMouth(hold=True),
    )
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "speaking"]
    pressed = time.monotonic()
    ptt(game, "down")
    assert next_status(game)["state"] == "listening"
    assert time.monotonic() - pressed < 0.5  # die ersten Wörter des Fahrers gehen nicht verloren
    assert companion.ears.listening and mouth.stops == 1

    mouth.release()
    ptt(game, "up")  # das Brain bleibt trotzdem eins nach dem anderen: die neue Frage wartet auf das Aufräumen
    assert states(game, 3) == ["thinking", "speaking", "idle"]
    assert mouth.spoken[-1] == "Neue Antwort." and brain.cancelled == 1 and brain.prompts[-1] == "Frage: Zwei"


def test_a_wake_ringing_during_an_answer_keeps_the_answers_utterance(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Antwort eins. Antwort zwei."]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Frage"]), mouth=FakeMouth(hold=True)
    )
    ride_start(game)
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "speaking"]
    wait_until(lambda: companion.companion._utterance is not None, 5.0, "Antwort in Rede")
    before = companion.companion._utterance
    clock.advance(9 * 60)  # der Wecker klingelt, während Toni noch spricht
    wait_until(lambda: companion.companion._waking is None, 5.0, "Wecker durch")
    time.sleep(SETTLE_S)
    assert companion.companion._utterance is before  # Barge-in findet die Antwort noch
    ptt(game, "down")
    assert next_status(game)["state"] == "listening" and mouth.stops == 1


def test_shutdown_stops_playback_and_synthesis(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Ein Satz, der noch spielt."]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Hallo"]), mouth=FakeMouth(hold=True)
    )
    ask(game)
    assert states(game, 3) == ["listening", "thinking", "speaking"]
    assert mouth.stops == 0
    assert companion.stop() is None
    assert mouth.stops == 1  # kein Thread soll das Prozessende verzögern


def test_shutdown_before_the_costs_arrived_asks_one_last_time_without_waiting(
    bridge_process, bus_client, in_process_companion
):
    mouth = FakeMouth(costs={"gen-1": 0.003, "gen-2": 0.001}, patient_blocks=True)
    brain = FakeBrain([["Erster Satz. Zweiter Satz."]])
    game, companion, clock, _ = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Hallo"]), mouth=mouth
    )
    ride_start(game)
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    mouth.aborted = 2  # zwei Synthesen der Fahrt wurden abgebrochen: ihre Kosten stehen nirgends
    send(game, type="ride_event", kind="ride_end", finished=True, distance_km=1.0, duration_s=60)
    wait_until(lambda: any(r["type"] == "ride" for r in records(companion)), 5.0, "Fahrt protokolliert")
    wait_until(lambda: mouth.cost_calls, 5.0, "Kostenabruf läuft (wartet auf OpenRouter)")
    assert not any(r["type"] == "ride_cost" for r in records(companion))
    assert companion.stop() is None  # Prozess endet vor dem Abruf
    ride = next(r for r in records(companion) if r["type"] == "ride")
    cost = next(r for r in records(companion) if r["type"] == "ride_cost")
    assert mouth.patient_calls == [True, False]  # zuletzt eine Abfrage ohne Wartezeit
    assert (cost["total_cost_usd"], cost["unknown_generations"], cost["ride_end_at"]) == (0.004, 0, ride["at"])
    assert ride["aborted_requests"] == 2 and cost["aborted_requests"] == 2 and cost["lower_bound"] is True


def test_shutdown_right_after_ride_end_still_leaves_the_ride_record(bridge_process, bus_client, in_process_companion):
    mouth = FakeMouth(costs={"gen-1": 0.002})
    brain = FakeBrain([["Satz."]])
    game, companion, clock, _ = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Hallo"]), mouth=mouth
    )
    ride_start(game)
    ask(game)
    assert states(game, 4) == ["listening", "thinking", "speaking", "idle"]
    send(game, type="ride_event", kind="ride_end", finished=True, distance_km=1.0, duration_s=60)
    wait_until(lambda: any(r["type"] == "ride" for r in records(companion)), 5.0, "Fahrt protokolliert")
    assert companion.stop() is None
    kinds = [r["type"] for r in records(companion)]
    assert kinds.count("ride") == 1 and kinds.count("ride_cost") == 1  # nichts doppelt, nichts verloren
