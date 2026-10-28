"""Satzteilung und Textstrom des Brain (Spec #76, #79): Sätze an Satzgrenzen, Teilstücke ohne Doppeltes, Abbruch räumt
die Anfrage weg – ohne Claude (ein Fake-SDK ersetzt `claude_agent_sdk`)."""

import asyncio
from collections import deque
from types import SimpleNamespace

import pytest
from vspin_companion import claude_brain
from vspin_companion.claude_brain import BrainUnavailable, ClaudeBrain
from vspin_companion.ports import ToolCall
from vspin_companion.sentences import SentenceSplitter, split_sentences


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Noch 5 km. Das schaffst du!", ["Noch 5 km.", "Das schaffst du!"]),
        ("Läuft's? Ja! Dann weiter …", ["Läuft's?", "Ja!", "Dann weiter …"]),
        ("Ein Satz ohne Ende", ["Ein Satz ohne Ende"]),
        ("  ", []),
        ("Tempo 3.5 km/h sind zu langsam. Tritt rein.", ["Tempo 3.5 km/h sind zu langsam.", "Tritt rein."]),
        ("Das sind z. B. 5 km, d. h. bald da. Weiter.", ["Das sind z. B. 5 km, d. h. bald da.", "Weiter."]),
        ("Am 3. Mai war ich schneller. Heute nicht.", ["Am 3. Mai war ich schneller.", "Heute nicht."]),
        ('Er sagte "Los!" Dann fuhr er.', ['Er sagte "Los!"', "Dann fuhr er."]),
        ("Was?!  Wirklich.\nJa.", ["Was?!", "Wirklich.", "Ja."]),
    ],
)
def test_text_is_split_at_sentence_ends(text, expected):
    assert split_sentences(text) == expected


def test_the_splitter_gives_a_sentence_as_soon_as_its_end_is_certain():
    splitter = SentenceSplitter()
    assert splitter.feed("Noch 5") == [] and splitter.feed(" km.") == []  # ein Punkt am Ende: Zahl oder Satzende?
    assert splitter.feed(" Das") == ["Noch 5 km."]
    assert splitter.feed(" schaffst du! Und") == ["Das schaffst du!"]
    assert splitter.flush() == ["Und"] and splitter.flush() == []


# --- Textstrom des Brain mit Fake-SDK -----------------------------------------------------------------------------


class StreamEvent:
    def __init__(self, event):
        self.event = event


class AssistantMessage:
    def __init__(self, *content, error=None):
        self.content, self.error = list(content), error


class TextBlock:
    def __init__(self, text):
        self.text = text


class ToolUseBlock:
    def __init__(self, name, input):
        self.name, self.input = name, input


class ResultMessage:
    is_error = False


def delta(text):
    return StreamEvent({"type": "content_block_delta", "delta": {"type": "text_delta", "text": text}})


SDK = SimpleNamespace(
    types=SimpleNamespace(StreamEvent=StreamEvent),
    AssistantMessage=AssistantMessage,
    TextBlock=TextBlock,
    ToolUseBlock=ToolUseBlock,
    ResultMessage=ResultMessage,
)


class FakeClient:
    def __init__(self, *messages, fail_interrupt=False):
        self.messages = deque(messages)
        self.interrupts = 0
        self.fail_interrupt = fail_interrupt

    async def query(self, prompt):
        pass

    async def receive_response(self):
        while self.messages:
            message = self.messages.popleft()
            yield message
            if isinstance(message, ResultMessage):
                return

    async def interrupt(self):
        self.interrupts += 1
        if self.fail_interrupt:
            raise ConnectionError("CLI tot")


@pytest.fixture
def brain(monkeypatch, tmp_path):
    monkeypatch.setattr(claude_brain, "_import_sdk", lambda: SDK)

    def make(*messages, **options) -> ClaudeBrain:
        brain = ClaudeBrain("oauth", tmp_path)
        brain._client = FakeClient(*messages, **options)
        return brain

    return make


def collect(brain):
    async def scenario():
        return [item async for item in brain.respond("Frage")]

    return asyncio.run(scenario())


def test_text_arrives_piece_by_piece_and_the_finished_block_adds_nothing_twice(brain):
    items = collect(brain(
        delta("Noch 5"), delta(" km. "), AssistantMessage(TextBlock("Noch 5 km. ")),
        AssistantMessage(ToolUseBlock("mcp__toni__remember", {"text": "x"})),
        delta("Weiter."), AssistantMessage(TextBlock("Weiter.")),
        ResultMessage(),
    ))
    assert items == ["Noch 5", " km. ", ToolCall("remember", {"text": "x"}), "Weiter."]


def test_without_partial_messages_the_finished_block_still_delivers_the_text(brain):
    assert collect(brain(AssistantMessage(TextBlock("Ganzer Text.")), ResultMessage())) == ["Ganzer Text."]
    # Teilstücke und Block, der mehr enthält: nur der Rest kommt nach
    assert collect(brain(delta("Ganzer"), AssistantMessage(TextBlock("Ganzer Text.")), ResultMessage())) == [
        "Ganzer", " Text."
    ]


def test_ending_the_stream_early_interrupts_the_request_and_reads_the_rest_away(brain):
    b = brain(delta("Erster Satz. "), delta("Zweiter."), AssistantMessage(TextBlock("Erster Satz. Zweiter.")), ResultMessage())

    async def scenario():
        stream = b.respond("Frage")
        first = await stream.__anext__()
        await stream.aclose()  # Barge-in: der Begleiter hört auf zu lesen
        return first

    assert asyncio.run(scenario()) == "Erster Satz. "
    assert b._client.interrupts == 1 and not b._client.messages  # Rest bis zum Ergebnis weggelesen
    assert collect(b) == []  # und die Sitzung ist für die nächste Anfrage sauber


def test_a_session_that_cannot_be_cleaned_up_after_an_abort_is_reported_not_reused(brain):
    b = brain(delta("Erster Satz. "), delta("Rest"), ResultMessage(), fail_interrupt=True)

    async def scenario():
        stream = b.respond("Frage")
        await stream.__anext__()
        await stream.aclose()

    asyncio.run(scenario())
    with pytest.raises(BrainUnavailable, match="unbrauchbar"):
        collect(b)  # Toni wird heiser und öffnet beim nächsten Mal eine frische Sitzung


def test_one_sentence_mode_cuts_like_the_old_spoken_text_even_after_a_number():
    """#78: In harten Phasen spricht Toni höchstens einen Satz. „Puls ist 142.“ ist für die Teilung kein Satzende
    (Ordnungszahl), für die Ein-Satz-Grenze aber schon."""
    from vspin_companion.fakes import FakeMouth
    from vspin_companion.utterance import Utterance

    async def spoken(one_sentence):
        mouth = FakeMouth()
        utterance = Utterance(mouth, one_sentence=lambda: one_sentence)
        utterance.feed("Dein Puls ist 142. Locker bleiben. Noch ein Satz.")
        await utterance.finish()
        return mouth.spoken

    assert asyncio.run(spoken(True)) == ["Dein Puls ist 142."]
    assert asyncio.run(spoken(False)) == ["Dein Puls ist 142. Locker bleiben.", "Noch ein Satz."]
