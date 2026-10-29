"""Wecker des Begleiters (Spec #76, #78): Abstände im Takt, Ereignis weckt sofort, Mindestabstand 60 s, Schweigen ohne
Ausgabe, `stay_silent`, `set_wake_interval`, harte Phasen – über einen echten Bus, nur mit Fakes und `FakeClock`."""

import json
import random
import time

import pytest
from bridge_harness import receive_json, wait_until
from companion_harness import assert_no_status, next_status, ptt
from vspin_companion.config import CompanionConfig, load_config
from vspin_companion.fakes import FakeBrain, FakeClock, FakeEars, FakeMouth
from vspin_companion.ports import ToolCall
from vspin_companion.wake import RideWatch

SEED = 78
SETTLE_S = 0.3  # so lange darf nichts passieren, wenn nichts passieren soll


def start(bridge_process, bus_client, in_process_companion, brain, ears=None, **kwargs):
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    clock, mouth = FakeClock(), FakeMouth()
    companion = in_process_companion(brain, ears or FakeEars(), mouth, clock, **kwargs)
    assert next_status(game)["state"] == "idle"
    return game, companion, clock, mouth


def send(game, **message) -> None:
    game.send(json.dumps({"v": 0, **message}))


def ride_event(game, kind: str, **fields) -> None:
    send(game, type="ride_event", kind=kind, **fields)


def ride_start(game, clock) -> None:
    ride_event(game, "ride_start", mode="rundfahrt", direction="cw", laps=1, logbook={"rides": 3})
    assert next_status(game)["state"] == "idle"  # Antwort auf ride_start
    wait_until(lambda: clock.pending(), 5.0, "Wecker gestellt")


def spoken(game, mouth, count: int) -> None:
    """Toni spricht ungefragt: `speaking`, dann `idle`; danach liegen `count` Sätze im Mund."""
    assert [next_status(game)["state"] for _ in range(2)] == ["speaking", "idle"]
    assert len(mouth.spoken) == count


def ask(game) -> list[str]:
    ptt(game, "down")
    ptt(game, "up")
    return [next_status(game)["state"] for _ in range(4)]


def nothing_more(game, mouth, count: int) -> None:
    assert_no_status(game, SETTLE_S)
    assert len(mouth.spoken) == count


def test_wake_intervals_follow_the_configured_range_and_only_during_a_ride(
    bridge_process, bus_client, in_process_companion
):
    brain = FakeBrain([["Na, schon warm? Easy peasy, lemon squeezy."], ["Weiter so, Kumpel."]])
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, brain, rng=random.Random(SEED))
    expected = random.Random(SEED)  # gleiche Zufallsfolge wie der Wecker

    ride_event(game, "best_time", time_s=1200, previous_s=1250)  # vor der Fahrt: kein Wecker
    time.sleep(SETTLE_S)
    assert clock.pending() == [] and brain.prompts == []

    ride_start(game, clock)
    first = clock.pending()[0]
    assert 3 * 60 <= first <= 8 * 60  # Start 3–8 min (companion.json-Standard)
    assert first == pytest.approx(expected.uniform(3, 8) * 60)

    companion.advance(first - 1)
    nothing_more(game, mouth, 0)  # eine Sekunde zu früh: nichts
    companion.advance(1)
    spoken(game, mouth, 2)  # zwei Sätze, einzeln an den Mund
    assert brain.prompts[-1].startswith("Wecker: Kein besonderer Anlass.")

    wait_until(lambda: clock.pending(), 5.0, "Wecker neu gestellt")
    second = clock.pending()[0] - clock.now()
    assert 3 * 60 <= second <= 8 * 60
    assert second == pytest.approx(expected.uniform(3, 8) * 60)
    companion.advance(second)
    spoken(game, mouth, 3)
    assert mouth.spoken == ["Na, schon warm?", "Easy peasy, lemon squeezy.", "Weiter so, Kumpel."]

    ride_event(game, "ride_end", finished=True, distance_km=9.1, duration_s=1500)
    wait_until(lambda: clock.pending() == [], 5.0, "Wecker aus nach ride_end")
    companion.advance(30 * 60)
    ride_event(game, "medal", medal="gold", **{"for": "lap"})
    nothing_more(game, mouth, 3)
    assert len(brain.prompts) == 2


def test_event_wakes_at_once_and_unprompted_sentences_keep_a_minute_apart(
    bridge_process, bus_client, in_process_companion
):
    brain = FakeBrain([["Bestzeit! Du Tier!"], ["Klar, noch 4 km."], ["Gold, Kumpel!"]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Wie weit noch?"])
    )
    ride_start(game, clock)

    ride_event(game, "best_time", time_s=1199.6, previous_s=1250, **{"for": "lap"})
    spoken(game, mouth, 2)  # sofort, ohne dass Zeit vergeht (zwei Sätze)
    assert "Anlass: neue Bestzeit für die Runde: 20:00 (vorher 20:50)." in brain.prompts[0]

    ride_event(game, "medal", medal="gold", **{"for": "lap"})
    wait_until(lambda: clock.pending() == [clock.now() + 60], 5.0, "Medaille wartet die Minute ab")
    nothing_more(game, mouth, 2)

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]  # Fragen gehen immer durch
    assert mouth.spoken[-1] == "Klar, noch 4 km."

    companion.advance(59)
    nothing_more(game, mouth, 3)
    companion.advance(1)
    spoken(game, mouth, 4)
    assert "Anlass: Medaille gold für die Runde." in brain.prompts[2]


def test_the_minute_of_silence_starts_when_the_sentence_ends(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Bestzeit! Du Tier!"], ["Gold, Kumpel!"]])
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    clock = FakeClock()

    class SlowMouth(FakeMouth):
        async def speak(self, sentence: str, on_start=None) -> None:
            clock.advance(10)  # der Satz dauert 10 s (läuft im Loop des Begleiters)
            await super().speak(sentence, on_start)

    mouth = SlowMouth()
    in_process_companion(brain, FakeEars(), mouth, clock)
    assert next_status(game)["state"] == "idle"
    ride_start(game, clock)
    ride_event(game, "best_time", time_s=1200, previous_s=1250)
    spoken(game, mouth, 2)
    ride_event(game, "medal", medal="gold", **{"for": "lap"})
    wait_until(lambda: clock.pending() == [clock.now() + 60], 5.0, "Medaille wartet die Minute nach dem Satz ab")


def test_silence_produces_no_output_and_does_not_count_as_a_sentence(
    bridge_process, bus_client, in_process_companion
):
    brain = FakeBrain([["SCHWEIGEN."], [], ["Runde zwei, los!"]])
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, brain)
    ride_start(game, clock)

    ride_event(game, "achievement", id="km100", name="100 km gesamt")
    wait_until(lambda: len(brain.prompts) == 1, 5.0, "Toni geweckt")
    nothing_more(game, mouth, 0)  # kein Status, kein Satz – auch kein `thinking`
    ride_event(game, "lap", lap=1, time_s=1300)
    wait_until(lambda: len(brain.prompts) == 2, 5.0, "Toni sofort wieder geweckt")
    nothing_more(game, mouth, 0)
    ride_event(game, "lap", lap=2, time_s=1290)  # Schweigen zählt nicht für die Minute
    spoken(game, mouth, 1)
    assert "Toni schweigt" in companion.log()


def test_ride_state_occasions_wake_toni(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Fünf Kilometer, easy!"]])
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, brain)
    ride_start(game, clock)
    state = {"type": "ride_state", "km_done": 4.9, "km_left": 4.1, "section": "Hafen", "hr_zone": 2, "cadence": 84}
    send(game, **state)
    nothing_more(game, mouth, 0)
    send(game, **{**state, "km_done": 5.2, "km_left": 3.8})
    spoken(game, mouth, 1)
    assert brain.prompts[0] == (
        "Fahrt: 5.2 km gefahren, noch 3.8 km, Abschnitt Hafen, Kadenz 84\n"
        "Wecker: Anlass: 5 km geschafft. Willst du nichts sagen, antworte mit SCHWEIGEN."
    )


def test_ride_watch_counts_each_occasion_once_without_flapping():
    watch = RideWatch()
    seen = []
    for km, left, zone, section, gap in [
        (0.0, 9.0, 2, "Hafen", 2.0),  # Ausgangslage: nichts
        (4.9, 5.1, 3, "Hafen", 0.5),  # Zone 3 erst einmal gesehen
        (5.0, 5.0, 2, "Küste", -0.5),  # 5. km; Zone flattert zurück; Abschnitt neu; Ghost innerhalb der Marge
        (5.4, 4.6, 3, "Küste", -1.5),  # noch 5 km; Ghost überholt
        (5.8, 4.2, 3, "Küste", -0.2),  # Zone 3 bestätigt
        (6.2, 3.8, 3, "Küste", 0.4),  # nichts
        (6.5, 5.5, 3, "Küste", 1.2),  # km_left springt zurück: „noch 5 km“ nicht noch einmal; Ghost vorbei
        (7.0, 4.9, 3, "Küste", 1.5),
        (10.1, 1.0, 3, "Hafen", 1.5),  # 10. km
    ]:
        seen.append([key for key, _ in watch.update(
            {"km_done": km, "km_left": left, "hr_zone": zone, "section": section, "ghost_gap_s": gap}
        )])
    assert seen == [[], [], ["km", "section"], ["km_left", "ghost"], ["hr_zone"], [], ["ghost"], [], ["km", "section"]]
    assert watch.update({"hr_zone": None, "km_done": None}) == []  # fehlende Werte: nichts


def test_hard_phase_allows_one_sentence_until_the_interval_is_over(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([
        ["Jetzt 95! Zieh durch, Kumpel. Ich zähl mit."],
        ["Runde geschafft. Das Bergdorf hat applaudiert."],
        ["Der Drac! Tritt rein. Ich glaub an dich."],
        ["Noch 2 km. Danach rollen wir."],
    ])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Wie weit noch?"])
    )
    ride_start(game, clock)

    ride_event(game, "interval_start", target_cadence=95, duration_s=30)
    spoken(game, mouth, 1)
    assert mouth.spoken[-1] == "Jetzt 95!"
    assert "Harte Phase: höchstens ein Satz." in brain.prompts[-1]

    ride_event(game, "lap", lap=1, time_s=1300)
    wait_until(lambda: clock.pending() == [clock.now() + 60], 5.0, "Runde wartet die Minute ab")
    companion.advance(60)  # Intervall längst vorbei
    spoken(game, mouth, 3)  # außerhalb harter Phasen beide Sätze
    assert mouth.spoken[-2:] == ["Runde geschafft.", "Das Bergdorf hat applaudiert."]

    ride_event(game, "boss_start", boss="Drac de na Coca")
    wait_until(lambda: clock.pending() == [clock.now() + 60], 5.0, "Boss wartet die Minute ab")
    companion.advance(60)
    spoken(game, mouth, 4)
    assert mouth.spoken[-1] == "Der Drac!"
    assert ask(game) == ["listening", "thinking", "speaking", "idle"]  # auch Antworten: ein Satz im Bosskampf
    assert mouth.spoken[-1] == "Noch 2 km."


def test_stay_silent_suppresses_unprompted_remarks_until_ride_end_but_questions_get_answers(
    bridge_process, bus_client, in_process_companion
):
    brain = FakeBrain([
        [ToolCall("stay_silent", {"until_ride_end": True}), "Na gut, ich halt die Klappe."],
        ["Noch 3 km, Ruhe bewahren."],
        ["Neue Fahrt, neues Glück!"],
    ])
    ears = FakeEars(["Sei mal still", "Wie weit noch?"])
    game, companion, clock, mouth = start(bridge_process, bus_client, in_process_companion, brain, ears=ears)
    ride_start(game, clock)

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    assert brain.tool_results[0][1].is_error is False
    wait_until(lambda: clock.pending() == [], 5.0, "kein Zufallsabstand mehr")
    ride_event(game, "best_time", time_s=1200, previous_s=None)
    nothing_more(game, mouth, 1)
    assert len(brain.prompts) == 1

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    assert mouth.spoken[-1] == "Noch 3 km, Ruhe bewahren."

    ride_event(game, "ride_end", finished=True, distance_km=9.0, duration_s=1500)
    wait_until(lambda: brain.closed == 1, 5.0, "Sitzung nach ride_end geschlossen")
    ride_start(game, clock)  # neue Fahrt: Toni meldet sich wieder
    ride_event(game, "medal", medal="bronze", **{"for": "lap"})
    spoken(game, mouth, 3)
    assert mouth.spoken[-1] == "Neue Fahrt, neues Glück!"


def test_set_wake_interval_changes_and_stores_the_interval_within_1_to_30_minutes(
    bridge_process, bus_client, in_process_companion, tmp_path
):
    data_dir = tmp_path / "companion"
    data_dir.mkdir()
    original = {"brain": "oauth", "wake_min_minutes": 3, "wake_max_minutes": 8, "kommt_spaeter": {"x": 1}}
    (data_dir / "companion.json").write_text(json.dumps(original), encoding="utf-8")
    brain = FakeBrain([
        [ToolCall("set_wake_interval", {"min_minutes": 10, "max_minutes": 10}), "Alle zehn Minuten, versprochen."],
        [
            ToolCall("set_wake_interval", {"min_minutes": 0, "max_minutes": 5}),
            ToolCall("set_wake_interval", {"min_minutes": 5, "max_minutes": 31}),
            ToolCall("set_wake_interval", {"min_minutes": 12, "max_minutes": 10}),
            ToolCall("set_wake_interval", {"min_minutes": "5", "max_minutes": 10}),
            ToolCall("set_wake_interval", {"min_minutes": True, "max_minutes": 10}),
            ToolCall("set_wake_interval", {"max_minutes": 10}),
            "So nicht, Kumpel.",
        ],
        [ToolCall("set_wake_interval", {"min_minutes": 1, "max_minutes": 30}), "Mal so, mal so."],
    ])
    ears = FakeEars(["Nur noch alle 10 Minuten", "Melde dich nie", "Mal oft, mal selten"])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=ears,
        data_dir=data_dir, config=load_config(data_dir), rng=random.Random(SEED),
    )
    ride_start(game, clock)

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    stored = json.loads((data_dir / "companion.json").read_text(encoding="utf-8"))
    assert stored == {**original, "wake_min_minutes": 10, "wake_max_minutes": 10}  # unbekannte Schlüssel bleiben
    assert load_config(data_dir) == CompanionConfig(wake_min_minutes=10, wake_max_minutes=10)
    wait_until(lambda: clock.pending() == [clock.now() + 600], 5.0, "neuer Takt wirkt sofort")

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    refused = [result for _, result in brain.tool_results[1:]]
    assert len(refused) == 6 and all(result.is_error for result in refused)
    assert "1–30" in refused[0].text and "1–30" in refused[1].text and "größer" in refused[2].text
    assert json.loads((data_dir / "companion.json").read_text(encoding="utf-8")) == stored  # unverändert
    wait_until(lambda: clock.pending() == [clock.now() + 600], 5.0, "Takt unverändert")

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]  # die Ränder 1 und 30 gelten
    assert load_config(data_dir) == CompanionConfig(wake_min_minutes=1, wake_max_minutes=30)
    wait_until(lambda: [t for t in clock.pending() if 60 <= t - clock.now() <= 1800], 5.0, "Takt 1–30 min")


def test_brain_failure_on_waking_makes_toni_hoarse_until_the_next_ptt(
    bridge_process, bus_client, in_process_companion
):
    brain = FakeBrain([ConnectionError("kein Netz"), ["Bin wieder da."], ["Und Medaille!"]])
    game, companion, clock, mouth = start(
        bridge_process, bus_client, in_process_companion, brain, ears=FakeEars(["Toni?"])
    )
    ride_start(game, clock)
    ride_event(game, "lap", lap=1, time_s=1300)
    assert next_status(game)["state"] == "hoarse"
    assert "Toni ist heiser – Brain: ConnectionError: kein Netz" in companion.log()

    ride_event(game, "medal", medal="silver", **{"for": "lap"})  # heiser: der Wecker wartet
    nothing_more(game, mouth, 0)
    assert len(brain.prompts) == 1

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]  # die Sprechtaste versucht es neu
    spoken(game, mouth, 2)  # danach kommt die wartende Medaille dran
    assert "Medaille silver" in brain.prompts[2]
    assert len(brain.sessions) == 2  # nach dem Fehler eine frische Sitzung
    assert companion.alive and companion.error is None
