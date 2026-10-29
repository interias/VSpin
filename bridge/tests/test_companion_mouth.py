"""Mund des Begleiters (Spec #76, #79): OpenRouter-Anfrage, Satz-für-Satz-Wiedergabe in Reihenfolge, Barge-in bricht
Wiedergabe und offene Synthese ab, Verbrauch und Kostenabruf – nur mit Fakes für HTTP und Audio (kein Netz, kein Ton)."""

import array
import asyncio
import json
import os
import tempfile

import pytest
from vspin_companion.ears import LocalEars
from vspin_companion.fakes import FakeClock, FakeDecoder, FakeHttp, FakeMicrophone, FakePlayer, FakeRecognizer
from vspin_companion.mouth import OpenRouterMouth, scale_pcm
from vspin_companion.openrouter import SPEECH_URL, HttpResponse, OpenRouterClient, OpenRouterError
from vspin_companion.ports import SpeechUsage


def run(coroutine):
    return asyncio.run(asyncio.wait_for(coroutine, 10))


def make(http=None, player=None, key="sk-or-test", **options):
    http = http or FakeHttp()
    player = player or FakePlayer()
    slept: list[float] = []

    async def sleep(seconds: float) -> None:
        slept.append(seconds)

    client = OpenRouterClient(http, lambda: key, "elevenlabs/eleven-v4-turbo", "charlie")
    mouth = OpenRouterMouth(client, FakeDecoder(), player, sleep=sleep, cost_delays=(1.0, 2.0), **options)
    return mouth, http, player, slept


def test_speak_posts_model_voice_and_mp3_to_openrouter_and_plays_the_audio():
    async def scenario():
        mouth, http, player, _ = make()
        started: list[str] = []
        await mouth.speak("Hallo Welt.", lambda: started.append("ton"))
        return mouth, http, player, started

    mouth, http, player, started = run(scenario())
    method, url, headers, body = http.requests[0]
    assert (method, url) == ("POST", SPEECH_URL) and url == "https://openrouter.ai/api/v1/audio/speech"
    assert headers["Authorization"] == "Bearer sk-or-test" and headers["User-Agent"] == "vspin-companion"
    assert json.loads(body) == {
        "model": "elevenlabs/eleven-v4-turbo", "input": "Hallo Welt.", "voice": "charlie", "response_format": "mp3",
    }  # provider.zdr wird bewusst nicht gesetzt (ElevenLabs: nur Enterprise)
    assert player.played == [("Hallo Welt.", 1.0)] and started == ["ton"]  # Lautstärke ohne Meldung des Spiels: 1,0
    assert mouth.take_usage() == SpeechUsage(chars=11, requests=1, generation_ids=("gen-1",))  # aus X-Generation-Id
    assert mouth.take_usage() == SpeechUsage()  # zurückgesetzt


class SlowFirstHttp(FakeHttp):
    async def request(self, method, url, headers, body=None):
        if body and b"eins" in body:
            await asyncio.sleep(0.05)  # Satz 1 ist als Letzter synthetisiert
        return await super().request(method, url, headers, body)


def test_sentences_are_synthesized_at_once_but_played_in_the_order_of_the_calls():
    async def scenario():
        mouth, http, player, _ = make(SlowFirstHttp())
        await asyncio.gather(*(mouth.speak(s) for s in ("eins.", "zwei.", "drei.")))
        return player

    assert [sentence for sentence, _ in run(scenario()).played] == ["eins.", "zwei.", "drei."]


def test_the_next_sentence_is_synthesized_while_the_previous_one_is_still_playing():
    async def scenario():
        mouth, http, player, _ = make(player=FakePlayer(block=True))
        tasks = [asyncio.create_task(mouth.speak(s)) for s in ("eins.", "zwei.")]
        await asyncio.sleep(0.05)
        during = (len(http.requests), [s for s, _ in player.played])  # beide synthetisiert, erst Satz 1 spielt
        player.finish()
        await asyncio.sleep(0.05)
        player.finish()
        await asyncio.gather(*tasks)
        return during, player.finished

    during, finished = run(scenario())
    assert during == (2, ["eins."]) and finished == ["eins.", "zwei."]


def test_stop_aborts_the_playing_sentence_and_the_pending_ones():
    async def scenario():
        mouth, http, player, _ = make(player=FakePlayer(block=True))
        tasks = [asyncio.create_task(mouth.speak(s)) for s in ("eins.", "zwei.", "drei.")]
        await asyncio.sleep(0.05)
        await mouth.stop()
        await asyncio.gather(*tasks)  # alle kehren zurück, keiner hängt
        return player

    player = run(scenario())
    assert [s for s, _ in player.played] == ["eins."] and player.finished == []  # Satz 2 und 3 nie gespielt
    assert player.stopped == 1


def test_stop_aborts_open_synthesis_and_the_mouth_works_again_afterwards():
    async def scenario():
        mouth, http, player, _ = make(FakeHttp(hold=True))
        tasks = [asyncio.create_task(mouth.speak(s)) for s in ("eins.", "zwei.")]
        await asyncio.sleep(0.05)
        started = http.started  # beide Anfragen sind unterwegs, keine beantwortet
        await mouth.stop()
        await asyncio.gather(*tasks)
        # nichts gespielt, nichts abgerechnet – aber zwei abgebrochene Anfragen, die OpenRouter womöglich berechnet
        assert player.played == [] and mouth.take_usage() == SpeechUsage(aborted=2)
        http.release()
        await mouth.speak("neu.")
        return started, player

    started, player = run(scenario())
    assert started == 2 and [s for s, _ in player.played] == ["neu."]


def test_volume_applies_to_what_is_played_next_and_stays_between_0_and_1():
    async def scenario():
        mouth, _, player, _ = make()
        mouth.set_volume(0.4)
        await mouth.speak("leise.")
        mouth.set_volume(7)
        await mouth.speak("laut.")
        return player.played

    assert run(scenario()) == [("leise.", 0.4), ("laut.", 1.0)]


def test_errors_of_the_service_surface_and_cost_nothing_in_the_protocol():
    async def scenario(respond, key="sk-or-test"):
        mouth, http, _, _ = make(key=key)
        http.respond = respond
        with pytest.raises(Exception) as caught:
            await mouth.speak("Hallo.")
        return caught.value, mouth.take_usage()

    error, usage = run(scenario(lambda *a: HttpResponse(402, {}, b'{"error": "Insufficient credits"}')))
    assert isinstance(error, OpenRouterError) and "HTTP 402" in str(error) and "Insufficient credits" in str(error)
    assert usage == SpeechUsage()
    error, _ = run(scenario(lambda *a: ConnectionError("kein Netz")))
    assert isinstance(error, ConnectionError)
    error, _ = run(scenario(lambda *a: HttpResponse(200, {}, b"")))
    assert isinstance(error, OpenRouterError) and "leer" in str(error)

    def no_key():
        raise OpenRouterError("OPENROUTER_API_KEY fehlt")

    async def without_key():
        http, player = FakeHttp(), FakePlayer()
        mouth = OpenRouterMouth(OpenRouterClient(http, no_key, "m", "v"), FakeDecoder(), player)
        with pytest.raises(OpenRouterError, match="OPENROUTER_API_KEY"):
            await mouth.speak("Hallo.")
        return http.requests

    assert run(without_key()) == []  # ohne Schlüssel geht keine Anfrage raus


def test_a_response_without_generation_id_counts_as_a_request_with_unknown_cost():
    async def scenario():
        mouth, http, _, _ = make()
        http.respond = lambda *a: HttpResponse(200, {}, b"MP3:x") if a[0] == "POST" else None
        await mouth.speak("Satz.")
        return mouth.take_usage()

    assert run(scenario()) == SpeechUsage(chars=5, requests=1, generation_ids=())


def test_cost_of_asks_the_generation_api_again_until_the_record_exists():
    async def scenario():
        mouth, http, _, slept = make(FakeHttp())
        await mouth.speak("Satz.")
        ids = list(mouth.take_usage().generation_ids)
        late: list[float] = []

        def respond(method, url, body):  # die Generation-API kennt den Datensatz erst beim dritten Versuch
            if method == "GET":
                late.append(1)
                if len(late) >= 3:
                    return HttpResponse(200, {}, b'{"data": {"total_cost": 0.00384}}')
                return HttpResponse(404, {}, b"{}")

        http.respond = respond
        return await mouth.cost_of(ids), slept, [r[1] for r in http.requests if r[0] == "GET"]

    costs, slept, urls = run(scenario())
    assert costs == {"gen-1": 0.00384} and slept == [1.0, 2.0]
    assert urls == ["https://openrouter.ai/api/v1/generation?id=gen-1"] * 3


def test_cost_of_leaves_out_what_openrouter_never_delivers():
    async def scenario():
        mouth, http, _, slept = make(FakeHttp(costs={"gen-1": 0.002}))
        http.respond = lambda m, u, b: ConnectionError("kein Netz") if "gen-3" in u else None
        return await mouth.cost_of(["gen-1", "gen-2", "gen-3"]), slept

    costs, slept = run(scenario())
    assert costs == {"gen-1": 0.002}  # gen-2: 404, gen-3: Netzfehler – beides fehlt, nichts wird geschätzt
    assert slept == [1.0, 2.0]


def test_a_broken_generation_record_is_an_error_not_a_guess():
    async def cost(response):
        _, http, _, _ = make()
        http.respond = lambda *a: response
        client = OpenRouterClient(http, lambda: "k", "m", "v")
        return await client.generation_cost("gen-9")

    assert run(cost(HttpResponse(200, {}, b'{"data": {"total_cost": 0}}'))) == 0.0
    assert run(cost(HttpResponse(404, {}, b"{}"))) is None
    for bad in (HttpResponse(500, {}, b"boom"), HttpResponse(200, {}, b"{}"), HttpResponse(200, {}, b'{"data": {"total_cost": "viel"}}')):
        with pytest.raises(OpenRouterError):
            run(cost(bad))


def test_scale_pcm_multiplies_16_bit_samples():
    samples = array.array("h", [1000, -1000, 32767]).tobytes()
    assert array.array("h", scale_pcm(samples, 0.5)).tolist() == [500, -500, 16383]
    assert scale_pcm(samples, 1.0) is samples
    assert scale_pcm(samples, 0.0) == bytes(len(samples))


def test_cost_of_impatient_asks_once_without_waiting():
    async def scenario():
        mouth, http, _, slept = make(FakeHttp(costs={"gen-1": 0.002}))
        return await mouth.cost_of(["gen-1", "gen-2"], patient=False), slept, len(http.requests)

    costs, slept, asked = run(scenario())
    assert costs == {"gen-1": 0.002} and slept == [] and asked == 2


def test_the_cost_request_also_carries_the_user_agent():
    async def scenario():
        mouth, http, _, _ = make(FakeHttp(costs={"gen-1": 0.002}))
        await mouth.cost_of(["gen-1"])
        return http.requests[0][2]

    assert run(scenario())["User-Agent"] == "vspin-companion"


# --- Wächter: kein Audio auf Platte (ADR-0008 Nachtrag #76) -------------------------------------------------------


def files_left(tmp_path, monkeypatch):
    """Richtet Arbeitsverzeichnis und Temp-Ordner unter `tmp_path` ein; liefert eine Funktion, die alle Dateien dort
    zählt (relative Pfade)."""
    work, temp = tmp_path / "cwd", tmp_path / "tmp"
    work.mkdir()
    temp.mkdir()
    monkeypatch.chdir(work)
    monkeypatch.setattr(tempfile, "tempdir", str(temp))
    for name in ("TMP", "TEMP", "TMPDIR"):
        monkeypatch.setenv(name, str(temp))
    return lambda: sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob("*") if p.is_file())


def test_speaking_and_listening_leave_no_audio_file_behind(tmp_path, monkeypatch):
    left = files_left(tmp_path, monkeypatch)

    async def scenario():
        mouth, _, _, _ = make()
        await asyncio.gather(mouth.speak("Eins."), mouth.speak("Zwei."))
        await mouth.stop()
        ears = LocalEars(FakeMicrophone(b"frage"), lambda: FakeRecognizer(), FakeClock())
        await ears.start_listening()
        await ears.stop_listening()

    run(scenario())
    assert left() == []


def test_the_disk_guard_notices_a_mouth_that_writes_a_temp_mp3(tmp_path, monkeypatch):
    """Gegenprobe: ein Mund, der den MP3-Puffer in eine Temp-Datei schreibt, macht den Wächter rot."""
    left = files_left(tmp_path, monkeypatch)

    class DiskDecoder(FakeDecoder):
        def decode(self, mp3):
            handle, _ = tempfile.mkstemp(suffix=".mp3")
            os.write(handle, mp3)
            os.close(handle)
            return super().decode(mp3)

    async def scenario():
        client = OpenRouterClient(FakeHttp(), lambda: "k", "m", "v")
        await OpenRouterMouth(client, DiskDecoder(), FakePlayer()).speak("Eins.")

    run(scenario())
    assert len(left()) == 1 and left()[0].endswith(".mp3")
