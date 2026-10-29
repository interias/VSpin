"""Seele, Gedächtnis und Anmeldung des Begleiters (Spec #76, #78): Werkzeuge schreiben `soul.md`/`memory.md`, nach
`ride_end` aufgeräumt unter die Grenzen mit `.bak`, Werkzeuge kürzen nie still; Sitzung je Fahrt mit frisch gelesenen
Dateien; Geheimnisse nur aus Umgebung oder Ablage-`.env`, kein Ausweichen auf den API-Schlüssel. Dateien nur unter
`tmp_path`, kein Claude."""

import asyncio
import json

import pytest
from bridge_harness import receive_json, wait_until
from companion_harness import next_status, ptt
from vspin_companion.claude_brain import API_KEY_ENV, AUTH_TOKEN_ENV, OAUTH_TOKEN_ENV, BrainUnavailable, sdk_env
from vspin_companion.env_file import load_secret, read_env_file
from vspin_companion.fakes import FakeBrain, FakeClock, FakeEars, FakeMouth
from vspin_companion.notes import MEMORY, SOUL, Notebook, NoteRefused
from vspin_companion.ports import ToolCall

LOGBOOK = {
    "rides": 42,
    "km_total": 812.4,
    "recent": [{"date": "2026-10-27T17:02:11Z", "mode": "rundfahrt", "distance_km": 18.2, "duration_s": 2700.0,
                "avg_cadence_rpm": 82.0}],
}


def ask(game) -> list[str]:
    ptt(game, "down")
    ptt(game, "up")
    return [next_status(game)["state"] for _ in range(4)]


def ride_event(game, kind: str, **fields) -> None:
    game.send(json.dumps({"v": 0, "type": "ride_event", "kind": kind, **fields}))


def read(path) -> str:
    return path.read_text(encoding="utf-8")


def test_tools_write_soul_and_memory_and_ride_end_tidies_them_with_backup(
    bridge_process, bus_client, in_process_companion, tmp_path
):
    data_dir = tmp_path / "companion"
    data_dir.mkdir()
    (data_dir / "memory.md").write_text("- mag die Serpentinen\n", encoding="utf-8")  # von Hand (Story 19)
    new_soul = "Ich bin Toni, ernster Coach aus Mallorca. Kurz, klar, trotzdem herzlich."
    brain = FakeBrain(
        replies=[
            [ToolCall("remember", {"text": "Ziel: Bergwertung unter 10 Minuten"}), "Notiert, Chef!"],
            [ToolCall("update_soul", {"text": new_soul}), "Gut, ab jetzt ernster."],
        ],
        summaries=["Ich bin Toni, ernst und knapp.", "- mag die Serpentinen\n- Ziel: Bergwertung < 10 min"],
    )
    ears = FakeEars(["Merk dir: Bergwertung unter 10 Minuten", "Sei mal ernster"])
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    in_process_companion(brain, ears, FakeMouth(), FakeClock(), data_dir=data_dir)
    assert next_status(game)["state"] == "idle"

    ride_event(game, "ride_start", mode="rundfahrt", direction="ccw", laps=2, logbook=LOGBOOK)
    assert next_status(game)["state"] == "idle"  # Antwort auf ride_start
    wait_until(lambda: len(brain.sessions) == 1, 5.0, "Sitzung zur Fahrt")
    system = brain.sessions[0]
    assert "Ich bin Toni, frecher Radkumpel aus Mallorca." in system  # Vorgabe-Seele, in die Ablage kopiert
    default_soul = read(data_dir / "soul.md")
    assert default_soul.startswith("Ich bin Toni, frecher Radkumpel")
    assert not (data_dir / "soul.md.bak").exists()  # die Vorgabe zu kopieren sichert nichts
    assert "- mag die Serpentinen" in system
    assert "Fahrt läuft: Modus rundfahrt, gegen den Uhrzeigersinn, 2 Runden geplant." in system
    assert "Fahrtenbuch: 42 Fahrten, 812 km gesamt. Letzte Fahrten: 2026-10-27 rundfahrt 18.2 km 45 min Kadenz 82" in system

    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    assert read(data_dir / "memory.md") == "- mag die Serpentinen\n- Ziel: Bergwertung unter 10 Minuten\n"
    assert ask(game) == ["listening", "thinking", "speaking", "idle"]
    assert read(data_dir / "soul.md") == new_soul + "\n"
    assert [result.is_error for _, result in brain.tool_results] == [False, False]

    ride_event(game, "ride_end", finished=True, distance_km=18.0, duration_s=2600)
    wait_until(lambda: brain.closed == 1, 5.0, "aufgeräumt und Sitzung geschlossen")
    # .bak hält den Stand vor der Fahrt – nicht den nach dem ersten Werkzeug, nicht den vor dem Aufräumen.
    assert read(data_dir / "soul.md.bak") == default_soul
    assert read(data_dir / "memory.md.bak") == "- mag die Serpentinen\n"
    assert read(data_dir / "soul.md") == "Ich bin Toni, ernst und knapp.\n"
    assert read(data_dir / "memory.md") == "- mag die Serpentinen\n- Ziel: Bergwertung < 10 min\n"
    assert len(read(data_dir / "soul.md")) <= SOUL.limit and len(read(data_dir / "memory.md")) <= MEMORY.limit
    assert "höchstens 1350 Zeichen" in brain.summary_prompts[0] and new_soul in brain.summary_prompts[0]
    assert "höchstens 2700 Zeichen" in brain.summary_prompts[1]

    (data_dir / "memory.md").write_text("- von Hand dazu\n", encoding="utf-8")  # zwischen zwei Fahrten bearbeitet
    ride_event(game, "ride_start", mode="training", direction="cw", laps=None, logbook=LOGBOOK)
    wait_until(lambda: len(brain.sessions) == 2, 5.0, "neue Sitzung zur zweiten Fahrt")
    assert "Ich bin Toni, ernst und knapp." in brain.sessions[1]  # frisch gelesen
    assert "- von Hand dazu" in brain.sessions[1] and "Serpentinen" not in brain.sessions[1]
    ride_event(game, "ride_end", finished=False, distance_km=3.0, duration_s=600)
    wait_until(lambda: brain.closed == 2, 5.0, "zweite Fahrt zu Ende")
    assert len(brain.summary_prompts) == 2  # nichts geändert, nichts über der Grenze: kein Aufräumen
    assert read(data_dir / "memory.md") == "- von Hand dazu\n"
    assert read(data_dir / "memory.md.bak") == "- mag die Serpentinen\n"  # nichts geschrieben: keine neue Sicherung


def test_backup_keeps_the_state_before_the_session_once_per_file(tmp_path):
    """Host-Entscheidung 8c: je Datei und Sitzung genau eine Sicherung, vor dem ersten Schreiben – auch unter der
    Grenze und beim Aufräumen –, danach in derselben Sitzung nie überschrieben."""
    book, prompts = notebook(tmp_path, ["Toni, aufgeräumt.", "- aufgeräumt"])
    (tmp_path / "soul.md").write_text("Hand-Seele\n", encoding="utf-8")  # von Hand bearbeitet

    # Außerhalb einer Fahrt (Frage vor ride_start): eigene Sitzung
    asyncio.run(book.remember("mag Mandelblüte"))
    assert not (tmp_path / "memory.md.bak").exists()  # vorher gab es nichts zu sichern
    book.begin()  # ride_start

    asyncio.run(book.update_soul("Seele A"))
    assert read(tmp_path / "soul.md.bak") == "Hand-Seele\n"
    asyncio.run(book.update_soul("Seele B"))
    asyncio.run(book.remember("Ziel: 30 km"))
    asyncio.run(book.remember("Running Gag: Drac"))
    assert asyncio.run(book.tidy(SOUL)) and asyncio.run(book.tidy(MEMORY))  # Aufräumen nach ride_end
    assert read(tmp_path / "soul.md") == "Toni, aufgeräumt.\n"
    assert read(tmp_path / "soul.md.bak") == "Hand-Seele\n"  # nie mit A oder B überschrieben
    assert read(tmp_path / "memory.md.bak") == "- mag Mandelblüte\n"  # Stand vor der Fahrt
    assert len(prompts) == 2
    book.begin()  # nach ride_end: das Schreiben danach ist eine neue Sitzung

    asyncio.run(book.remember("nach der Fahrt"))
    assert read(tmp_path / "memory.md.bak") == "- aufgeräumt\n"
    asyncio.run(book.remember("noch etwas"))
    assert read(tmp_path / "memory.md.bak") == "- aufgeräumt\n"
    assert read(tmp_path / "soul.md.bak") == "Hand-Seele\n"  # Seele in dieser Sitzung nicht geschrieben


def test_session_failure_at_ride_start_makes_toni_hoarse(bridge_process, bus_client, in_process_companion):
    brain = FakeBrain([["Jetzt geht's."]])
    brain.fail_open = ConnectionError("kein Netz")
    bridge_process("--source", "sim", "--sim-cadence", "80")
    game = bus_client()
    assert receive_json(game)["type"] == "status"
    companion = in_process_companion(brain, FakeEars(["Toni?"]), FakeMouth(), FakeClock())
    assert next_status(game)["state"] == "idle"
    ride_event(game, "ride_start", mode="rundfahrt", logbook=LOGBOOK)
    assert next_status(game)["state"] == "idle"
    assert next_status(game)["state"] == "hoarse"
    assert "Toni ist heiser – Brain: ConnectionError: kein Netz" in companion.log()
    assert ask(game) == ["listening", "thinking", "speaking", "idle"]  # Sprechtaste: neue Sitzung, Antwort
    assert len(brain.sessions) == 1


def notebook(tmp_path, summaries: list[str]) -> tuple[Notebook, list[str]]:
    prompts: list[str] = []

    async def summarize(prompt: str) -> str:
        prompts.append(prompt)
        return summaries.pop(0)

    return Notebook(tmp_path, summarize), prompts


def test_remember_over_the_limit_condenses_first_and_keeps_a_backup(tmp_path):
    book, prompts = notebook(tmp_path, ["- alles Wichtige, kurz"])
    full = "".join(f"- Eintrag {i:03d} " + "x" * 40 + "\n" for i in range(54))  # knapp unter 3 000 Zeichen
    assert len(full) <= MEMORY.limit
    (tmp_path / "memory.md").write_text(full, encoding="utf-8")
    result = asyncio.run(book.remember("Running Gag: der Drac schuldet ihm ein Bier"))
    assert "aufgeräumt" in result and len(prompts) == 1
    assert "Running Gag: der Drac schuldet ihm ein Bier" in prompts[0]  # der neue Eintrag geht nicht verloren
    assert read(tmp_path / "memory.md") == "- alles Wichtige, kurz\n"
    assert read(tmp_path / "memory.md.bak") == full


def test_tools_never_cut_silently_when_condensing_does_not_fit(tmp_path):
    too_long = "y" * (SOUL.limit + 1)
    book, prompts = notebook(tmp_path, [too_long, too_long])
    (tmp_path / "soul.md").write_text("Ich bin Toni.\n", encoding="utf-8")
    with pytest.raises(NoteRefused, match="Seele voll"):
        asyncio.run(book.update_soul("z" * 2000))
    assert len(prompts) == 2  # zweiter, knapperer Versuch
    assert "höchstens 1050 Zeichen" in prompts[1]
    assert read(tmp_path / "soul.md") == "Ich bin Toni.\n"  # nichts gespeichert, nichts abgeschnitten
    with pytest.raises(NoteRefused):
        asyncio.run(book.remember("   "))
    assert not (tmp_path / "memory.md").exists()


def test_tidy_brings_a_hand_edited_file_under_the_limit_or_leaves_it_alone(tmp_path):
    book, prompts = notebook(tmp_path, ["- kurz gefasst", "m" * 3500, "m" * 3500])
    hand = "- " + "h" * 3200 + "\n"
    (tmp_path / "memory.md").write_text(hand, encoding="utf-8")
    assert book.needs_tidy(MEMORY) and not book.needs_tidy(SOUL)
    assert asyncio.run(book.tidy(MEMORY)) is True
    assert read(tmp_path / "memory.md") == "- kurz gefasst\n" and read(tmp_path / "memory.md.bak") == hand

    (tmp_path / "memory.md").write_text(hand, encoding="utf-8")
    assert asyncio.run(book.tidy(MEMORY)) is False  # Zusammenfassung zweimal zu lang
    assert read(tmp_path / "memory.md") == hand  # bleibt, wie es war – das nächste Fahrtende versucht es neu
    assert len(prompts) == 3


def test_secrets_come_from_the_environment_or_the_data_dir_env_file_only(tmp_path, monkeypatch):
    data_dir, cwd = tmp_path / "companion", tmp_path / "repo"
    data_dir.mkdir()
    cwd.mkdir()
    (cwd / ".env").write_text("OPENROUTER_API_KEY=aus-dem-repo\n", encoding="utf-8")
    monkeypatch.chdir(cwd)
    assert load_secret("OPENROUTER_API_KEY", data_dir, env={}) is None  # nie die .env im Arbeitsverzeichnis

    (data_dir / ".env").write_text(
        "# Begleiter\n\nexport OPENROUTER_API_KEY = 'or-test'\nCLAUDE_CODE_OAUTH_TOKEN=\"tok=en\"\nLEER=\nkaputt\n",
        encoding="utf-8",
    )
    assert read_env_file(data_dir / ".env") == {
        "OPENROUTER_API_KEY": "or-test", "CLAUDE_CODE_OAUTH_TOKEN": "tok=en", "LEER": ""
    }
    assert load_secret("OPENROUTER_API_KEY", data_dir, env={}) == "or-test"
    assert load_secret("OPENROUTER_API_KEY", data_dir, env={"OPENROUTER_API_KEY": "aus-env"}) == "aus-env"
    assert load_secret("LEER", data_dir, env={}) is None


def test_oauth_never_falls_back_to_the_api_key_without_the_setting(tmp_path):
    with_key = {API_KEY_ENV: "sk-ant-test"}
    with pytest.raises(BrainUnavailable, match=f"{OAUTH_TOKEN_ENV} fehlt.*kein Ausweichen"):
        sdk_env("oauth", tmp_path, env=with_key)

    env = sdk_env("oauth", tmp_path, env={**with_key, OAUTH_TOKEN_ENV: "oauth-test", AUTH_TOKEN_ENV: "bearer-test"})
    assert env[OAUTH_TOKEN_ENV] == "oauth-test" and env[API_KEY_ENV] == ""  # Schlüssel für den CLI-Prozess geleert
    assert env[AUTH_TOKEN_ENV] == ""  # auch ein geerbtes Bearer-Token, das in der CLI vor dem OAuth-Token gälte

    (tmp_path / ".env").write_text(f"{OAUTH_TOKEN_ENV}=aus-der-ablage\n", encoding="utf-8")
    assert sdk_env("oauth", tmp_path, env=with_key)[OAUTH_TOKEN_ENV] == "aus-der-ablage"

    env = sdk_env("api_key", tmp_path, env=with_key)  # nur per Einstellung
    assert env[API_KEY_ENV] == "sk-ant-test" and env[OAUTH_TOKEN_ENV] == "" and env[AUTH_TOKEN_ENV] == ""
    with pytest.raises(BrainUnavailable, match=f"{API_KEY_ENV} fehlt"):
        sdk_env("api_key", tmp_path, env={})
