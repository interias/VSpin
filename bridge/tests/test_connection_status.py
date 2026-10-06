"""Verbindungsstatus (ADR-0004): connected → stale (> 3 s keine Daten) → disconnected → connected.

Die Bridge läuft als echter Prozess mit dem Beispielprofil `profiles/abbruch.toml`;
geprüft wird nur, was Test-Clients am Bus sehen (und das Terminal-Log).
"""

import csv
import time

from bridge_harness import PROFILES_DIR, receive_json

STALE_AFTER_MS = 3000
# Längste Stille am Bus im Abbruch-Profil: 4 s Pause + 3 s bis zur Neuverbindung.
QUIET_TIMEOUT_S = 8.0


def collect_until(client, done, timeout_s: float = 30.0) -> list[dict]:
    """Nachrichten sammeln, bis `done(messages)` gilt."""
    messages: list[dict] = []
    deadline = time.monotonic() + timeout_s
    while not done(messages):
        assert time.monotonic() < deadline, f"Zeitüberschreitung, bisher: {summary(messages)}"
        messages.append(receive_json(client, timeout_s=QUIET_TIMEOUT_S))
    return messages


def states(messages: list[dict]) -> list[str]:
    return [m["state"] for m in messages if m["type"] == "status"]


def summary(messages: list[dict]) -> list[str]:
    """Kompakte Folge für Fehlermeldungen: Status-Namen, Telemetrie als `T`."""
    return [m["state"] if m["type"] == "status" else "T" for m in messages]


def telemetry_after(count: int, already: list[dict]):
    """Abbruch-Kriterium: (mit `already`) vier Statusnachrichten gesehen, danach `count`
    Telemetrie – oder ein weiterer Status, den der Test dann bemängelt."""

    def done(messages: list[dict]) -> bool:
        both = already + messages
        status_at = [i for i, m in enumerate(both) if m["type"] == "status"]
        return len(status_at) > 4 or (len(status_at) == 4 and len(both) - 1 - status_at[3] >= count)

    return done


def test_drop_profile_status_sequence(bridge_process, bus_client):
    bridge = bridge_process("--source", "sim", "--profile", str(PROFILES_DIR / "abbruch.toml"))
    first, second = bus_client(), bus_client()

    seen = collect_until(first, lambda ms: states(ms)[-1:] == ["disconnected"])
    # Wer während des Abbruchs dazukommt, bekommt sofort den aktuellen Status – kein Broadcast.
    late = bus_client()
    assert receive_json(late)["state"] == "disconnected"
    seen += collect_until(first, telemetry_after(4, already=seen))
    seq = summary(seen)
    # Genau eine status-Nachricht je Änderung, in dieser Reihenfolge; Telemetrie nur bei connected.
    assert states(seen) == ["connected", "stale", "disconnected", "connected"], seq
    assert seen[0]["type"] == "status"  # erste Nachricht an jeden neuen Client
    stale, disconnected, reconnected = [i for i, m in enumerate(seen) if m["type"] == "status"][1:]
    assert seq[1:stale] == ["T"] * (stale - 1), seq  # Fahren vor der Pause
    assert stale > 1, "Client hat das Fahren vor der Pause verpasst"
    assert stale + 1 == disconnected, seq  # in der Pause und im Abbruch keine Telemetrie
    assert disconnected + 1 == reconnected, seq
    assert seq[reconnected + 1 :] == ["T"] * (len(seen) - reconnected - 1), seq  # wieder Daten

    for message in seen:
        if message["type"] == "status":
            assert message["source"] == "sim" and message["capabilities"] == ["CADENCE"]
        else:
            assert message["cadence"] == 80

    # stale kommt nach > 3 s ohne Daten – nicht früher, und nicht viel später.
    gap_ms = seen[stale]["t_ms"] - seen[stale - 1]["t_ms"]
    assert STALE_AFTER_MS <= gap_ms < STALE_AFTER_MS + 1000, gap_ms
    t_ms = [m["t_ms"] for m in seen]
    assert t_ms == sorted(t_ms), t_ms

    # Jeder Client sieht dieselben Statusänderungen, jede genau einmal.
    other = collect_until(second, lambda ms: len(states(ms)) >= 4)
    assert states(other) == states(seen)
    # Die Änderungen sind derselbe Broadcast (gleiches t_ms); nur der Anfangsstatus ist je Client.
    assert [m for m in other if m["type"] == "status"][1:] == [m for m in seen if m["type"] == "status"][1:]

    assert states(collect_until(late, lambda ms: bool(states(ms)))) == ["connected"]

    bridge.stop()
    log = bridge.log()
    for state in ("stale", "disconnected"):
        assert log.count(f"Status: {state} (") == 1, log  # Terminal: eine Zeile je Änderung
    assert log.count("Status: connected (") == 2, log


def test_cadence_zero_with_data_is_not_stale(bridge_process, bus_client, tmp_path):
    profile = tmp_path / "zero.toml"
    profile.write_text(
        "[[steps]]\nduration_s = 1\ncadence = 60\n\n"
        "[[steps]]\nduration_s = 4.5\ncadence = 0\n\n"
        "[[steps]]\nduration_s = 1\ncadence = 60\n",
        encoding="utf-8",
    )
    out = tmp_path / "out"
    bridge = bridge_process("--source", "sim", "--profile", str(profile), "--sessions-dir", str(out))
    client = bus_client()
    seen = collect_until(client, lambda ms: states(ms)[-1:] == ["disconnected"])

    # Nur der Anfangsstatus und das Profilende – kein stale trotz 4,5 s Kadenz 0.
    assert states(seen) == ["connected", "disconnected"], summary(seen)
    # Die Quelle lieferte 4,5 s lang Kadenz 0 (Rohwert in der Session-CSV) …
    [path] = out.glob("*.csv")
    with open(path, encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    zero_rows = [r for r in rows if r["cadence_raw"] and float(r["cadence_raw"]) == 0]
    zeros = [int(r["t_ms"]) for r in zero_rows]
    assert zeros and zeros[-1] - zeros[0] > STALE_AFTER_MS + 500
    # … am Bus fällt die geglättete Kadenz (EMA ~1 s) dabei stetig gegen 0, ohne Lücke.
    on_bus = {m["t_ms"]: m["cadence"] for m in seen if m["type"] == "telemetry"}
    falling = [on_bus[t] for t in zeros if t in on_bus]
    assert len(falling) >= 12, falling
    assert falling == sorted(falling, reverse=True) and falling[-1] < 2, falling
    # Danach wieder 60 rpm: die Kadenz steigt wieder.
    assert seen[-2]["type"] == seen[-3]["type"] == "telemetry"
    assert falling[-1] < seen[-3]["cadence"] < seen[-2]["cadence"] < 60
    bridge.stop()
    assert "Status: stale" not in bridge.log()
    assert "Status: disconnected (Quelle beendet)" in bridge.log()
