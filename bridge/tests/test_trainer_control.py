"""Steuerung der Trainerquelle über FTMS (Spec #75, Stories 5, 7, 11) gegen den BLE-Fake: Request Control, Start,
Simulation und die Bytes von `0x11`, alle Antwortcodes und das Zeitlimit, Kontrollverlust über `0x2ADA`, Drosselung,
Grundlast, Neuverbinden.

Der Wächter „nur lesen“ aus `test_trainer_source.py::run()` gilt hier bewusst nicht: Diese Tests prüfen
`adapter.writes` selbst (über `control_writes`). Für Trainer ohne Simulation und im Nur-lesen-Modus gilt er weiter.
Asynchron über `asyncio.run`, alle Zeiten kurz."""

import asyncio

import pytest
from fake_ble import FakeBleAdapter
from trainer_harness import KICKR, control_responder, control_writes, kickr, sim_kickr, simulation

from vspin_bridge.ble import BleError
from vspin_bridge.sources.base import Capability, ControlRefusedError, NotSupportedError
from vspin_bridge.sources.trainer import GRADE_INTERVAL_S, GRADE_STEP, TrainerSource
from vspin_bridge.sources.trainer_control import (
    CONTROL_POINT,
    CW_KG_PER_M,
    CRR,
    MACHINE_STATUS,
    ControlPoint,
    ControlPointError,
    ControlState,
    simulation_parameters,
)

TIMEOUT_S = 5
RESPONSE_S = 0.2

REQUEST_CONTROL, RESET, START = b"\x00", b"\x01", b"\x07"
TAKEN = [REQUEST_CONTROL, START]  # so beginnt jede Verbindung mit Steuerung


def run(scenario) -> None:
    async def main() -> None:
        await asyncio.wait_for(scenario(FakeBleAdapter()), TIMEOUT_S * 2)

    asyncio.run(main())


def controlled(adapter: FakeBleAdapter, **options) -> tuple[TrainerSource, list[str]]:
    """Trainerquelle mit kurzen Zeiten; ohne Angabe ohne Drosselung. Die Liste sammelt jede Änderung der Steuerung."""
    options.setdefault("grade_interval_s", 0.0)
    source = TrainerSource(adapter, scan_s=0.3, settle_s=0.05, response_timeout_s=RESPONSE_S, **options)
    changes: list[str] = []
    source.on_control_changed = lambda state, reason: changes.append(str(state))
    return source, changes


# --- Übernehmen ------------------------------------------------------------------------------


def test_subscribes_then_requests_control_then_starts():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, changes = controlled(adapter)
        assert source.control is ControlState.NONE
        await source.connect()
        assert {CONTROL_POINT, MACHINE_STATUS} <= set(adapter.connections[KICKR].subscriptions)
        assert control_writes(adapter) == TAKEN  # noch keine Steigung gemeldet → kein 0x11
        assert source.control is ControlState.ACTIVE and changes == ["requesting", "active"]
        assert Capability.RESISTANCE_CONTROL in source.capabilities

    run(scenario)


def test_without_the_indication_subscription_the_trainer_refuses_writes(monkeypatch):
    # Gegenprobe zum Abo vor dem Schreiben: ohne Abo lehnt der Trainer (wie der Fake) jeden Schreibzugriff ab.
    async def no_subscription(self):
        return None

    monkeypatch.setattr(ControlPoint, "subscribe", no_subscription)

    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()  # lesen geht trotzdem
        assert adapter.writes == [] and source.control is ControlState.ERROR

    run(scenario)


def test_capability_needs_the_simulation_target_and_the_control_point():
    async def scenario(adapter):
        kickr(adapter)  # Target Setting Features ohne Indoor Bike Simulation
        source, changes = controlled(adapter)
        await source.connect()
        assert Capability.RESISTANCE_CONTROL not in source.capabilities
        assert source.control is ControlState.NOT_SUPPORTED and changes == ["not_supported"]
        with pytest.raises(NotSupportedError):
            await source.set_grade(0.05)
        assert adapter.writes == []

    run(scenario)


def test_control_point_that_cannot_be_subscribed_is_not_supported():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        original = adapter.connect

        async def connect(address, on_disconnect):
            connection = await original(address, on_disconnect)
            subscribe = connection.subscribe

            async def refusing(char, on_notify):
                if char == CONTROL_POINT:
                    raise BleError("Characteristic fehlt")
                await subscribe(char, on_notify)

            connection.subscribe = refusing
            return connection

        adapter.connect = connect
        await source.connect()
        assert source.control is ControlState.NOT_SUPPORTED
        assert Capability.RESISTANCE_CONTROL not in source.capabilities
        assert adapter.writes == []

    run(scenario)


@pytest.mark.parametrize(
    ("results", "writes", "state", "capable"),
    [
        ({0x00: 0x05}, [REQUEST_CONTROL], ControlState.LOST, True),  # eine andere App hat die Steuerung
        ({0x00: 0x02}, [REQUEST_CONTROL], ControlState.NOT_SUPPORTED, False),
        ({0x00: 0x04}, [REQUEST_CONTROL], ControlState.ERROR, True),
        ({0x00: None}, [REQUEST_CONTROL], ControlState.ERROR, True),  # keine Antwort
        ({0x07: 0x04}, TAKEN, ControlState.ERROR, True),
        ({0x07: 0x05}, TAKEN, ControlState.LOST, True),
    ],
)
def test_failed_takeover_keeps_reading_and_writes_nothing_more(results, writes, state, capable):
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder(results))
        source, _ = controlled(adapter)
        await source.connect()
        assert adapter.connected == {KICKR}  # die Verbindung zum Lesen bleibt
        assert source.control is state
        assert (Capability.RESISTANCE_CONTROL in source.capabilities) is capable
        with pytest.raises(Exception) as refused:
            await source.set_grade(0.05)
        if state is ControlState.LOST:
            assert isinstance(refused.value, ControlRefusedError) and refused.value.reason == "control_lost"
        elif state is ControlState.NOT_SUPPORTED:
            assert isinstance(refused.value, NotSupportedError)
        else:
            assert isinstance(refused.value, RuntimeError)
        assert control_writes(adapter) == writes

    run(scenario)


# --- Simulation ------------------------------------------------------------------------------


def test_simulation_parameters_follow_ftms():
    # Wind sint16 (0,001 m/s), Steigung sint16 (0,01 %), Crr uint8 (0,0001), Cw uint8 (0,01 kg/m), Little Endian.
    assert (CRR, CW_KG_PER_M) == (0.0040, 0.51)
    assert simulation_parameters(0.07) == b"\x00\x00\xbc\x02\x28\x33"
    assert simulation_parameters(-0.05) == b"\x00\x00\x0c\xfe\x28\x33"
    with pytest.raises(ValueError):
        simulation_parameters(3.5)  # 350 % passt nicht in sint16 – kein stilles Begrenzen


@pytest.mark.parametrize(
    ("grade", "hundredths"), [(0.07, 700), (-0.05, -500), (0.0, 0), (0.16, 1600), (0.2, 2000), (0.1234, 1234)]
)
def test_set_grade_writes_0x11_with_the_grade(grade, hundredths):
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        await source.set_grade(grade)
        assert control_writes(adapter) == [*TAKEN, simulation(hundredths)]

    run(scenario)


def test_steep_grade_is_not_clamped_and_a_refusal_is_an_error():
    async def scenario(adapter):
        sim_kickr(adapter, respond=lambda data: bytes([0x80, data[0], 0x03 if data[0] == 0x11 else 0x01]))
        source, _ = controlled(adapter)
        await source.connect()
        with pytest.raises(ControlPointError, match="ungültiger Parameter") as refused:
            await source.set_grade(0.25)
        assert refused.value.result == 0x03
        assert control_writes(adapter)[-1] == simulation(2500)  # so geschrieben, wie gemeldet
        assert source.control is ControlState.ACTIVE  # die Steuerung bleibt

    run(scenario)


@pytest.mark.parametrize(
    ("result", "error"),
    [(0x02, NotSupportedError), (0x03, ControlPointError), (0x04, ControlPointError), (None, ControlPointError)],
)
def test_every_answer_to_0x11_maps_to_an_error(result, error):
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x11: result}))
        source, _ = controlled(adapter)
        await source.connect()
        started = asyncio.get_running_loop().time()
        with pytest.raises(error):
            await source.set_grade(0.05)
        if result is None:  # Zeitlimit
            assert RESPONSE_S * 0.9 <= asyncio.get_running_loop().time() - started < RESPONSE_S + 1.0
        assert source.control is ControlState.ACTIVE

    run(scenario)


def test_success_is_ok():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        assert await source.set_grade(0.05) is None

    run(scenario)


# --- Kontrollverlust -------------------------------------------------------------------------


def test_answer_0x05_is_control_lost_and_nothing_is_written_after():
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x11: 0x05}))
        source, changes = controlled(adapter)
        await source.connect()
        with pytest.raises(ControlRefusedError) as refused:
            await source.set_grade(0.05)
        assert refused.value.reason == "control_lost"
        assert source.control is ControlState.LOST and changes[-1] == "lost"
        before = list(adapter.writes)
        with pytest.raises(ControlRefusedError):
            await source.set_grade(0.07)
        assert await source.reset_grade() is False  # auch die Grundlast schreibt nicht in eine fremde Steuerung
        await source.release()
        assert adapter.writes == before

    run(scenario)


def test_machine_status_control_permission_lost_reports_lost_once():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, changes = controlled(adapter)
        await source.connect()
        await source.set_grade(0.05)
        adapter.indicate(KICKR, MACHINE_STATUS, b"\x02\x01")  # vom Fahrer gestoppt: zählt nicht als Verlust
        assert source.control is ControlState.ACTIVE
        adapter.indicate(KICKR, MACHINE_STATUS, b"\xff")
        adapter.indicate(KICKR, MACHINE_STATUS, b"\xff")
        assert changes == ["requesting", "active", "lost"]  # genau eine Änderung
        writes = list(adapter.writes)
        with pytest.raises(ControlRefusedError):
            await source.set_grade(0.08)
        assert adapter.writes == writes

    run(scenario)


def test_reset_by_another_app_is_control_lost():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        adapter.indicate(KICKR, MACHINE_STATUS, b"\x01")
        assert source.control is ControlState.LOST

    run(scenario)


def test_lost_control_cancels_a_pending_catch_up():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter, grade_interval_s=0.2)
        await source.connect()
        await source.set_grade(0.05)
        await source.set_grade(0.08)  # gedrosselt, wird nachgeholt …
        adapter.indicate(KICKR, MACHINE_STATUS, b"\xff")  # … aber jetzt steuert eine andere App
        await asyncio.sleep(0.4)
        assert control_writes(adapter) == [*TAKEN, simulation(500)]

    run(scenario)


# --- Neuverbinden ----------------------------------------------------------------------------


def test_reconnect_requests_control_again_and_resends_the_last_grade():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, changes = controlled(adapter)
        await source.connect()
        await source.set_grade(0.05)
        await source.set_grade(0.06)
        adapter.drop(KICKR)
        assert source.control is ControlState.NONE
        with pytest.raises(RuntimeError):
            await source.set_grade(0.07)  # ohne Verbindung: gemerkt, folgt nach dem Verbinden
        await source.connect()
        assert control_writes(adapter) == [*TAKEN, simulation(500), simulation(600), *TAKEN, simulation(700)]
        assert changes == ["requesting", "active", "none", "requesting", "active"]

    run(scenario)


def test_reconnect_after_lost_control_requests_it_anew():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        await source.set_grade(0.04)
        adapter.indicate(KICKR, MACHINE_STATUS, b"\xff")
        adapter.drop(KICKR)
        await source.connect()
        assert source.control is ControlState.ACTIVE
        assert control_writes(adapter) == [*TAKEN, simulation(400), *TAKEN, simulation(400)]

    run(scenario)


def test_drop_while_waiting_for_the_answer_fails_at_once():
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x11: None}))
        source = TrainerSource(adapter, scan_s=0.3, settle_s=0.05, response_timeout_s=5.0, grade_interval_s=0.0)
        await source.connect()
        pending = asyncio.create_task(source.set_grade(0.05))
        await asyncio.sleep(0.05)
        adapter.drop(KICKR)
        with pytest.raises(BleError):
            await asyncio.wait_for(pending, 1.0)  # nicht erst nach dem Zeitlimit von 5 s
        assert source.control is ControlState.NONE

    run(scenario)


# --- Drosselung ------------------------------------------------------------------------------


def test_throttle_defaults():
    assert (GRADE_STEP, GRADE_INTERVAL_S) == (0.001, 0.5)  # 0,1 %, 2 Hz


def test_changes_below_a_tenth_of_a_percent_are_not_written():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        for grade in (0.05, 0.0505, 0.0491, 0.0509, 0.051, 0.0501):
            await source.set_grade(grade)
        # gegen den zuletzt geschriebenen Wert: 5,0 → (5,05 4,91 5,09 nein) → 5,1 → (5,01 nein, 0,09 % von 5,1)
        assert control_writes(adapter) == [*TAKEN, simulation(500), simulation(510)]

    run(scenario)


def test_at_most_one_write_per_interval_and_the_last_value_is_caught_up():
    async def scenario(adapter):
        times: list[float] = []
        respond = control_responder()

        def timed(data):
            if data[0] == 0x11:
                times.append(asyncio.get_running_loop().time())
            return respond(data)

        sim_kickr(adapter, respond=timed)
        source, _ = controlled(adapter, grade_interval_s=0.3)
        await source.connect()
        for grade in (0.05, 0.06, 0.07, 0.065):
            assert await source.set_grade(grade) is None  # auch gedrosselt kein Fehler: der Client bekommt ok
        assert control_writes(adapter) == [*TAKEN, simulation(500)]
        await asyncio.sleep(0.5)
        assert control_writes(adapter) == [*TAKEN, simulation(500), simulation(650)]  # Endwert nachgeholt, einmal
        assert times[1] - times[0] >= 0.3 - 0.02
        await asyncio.sleep(0.4)
        assert len(control_writes(adapter)) == 4  # danach nichts mehr

    run(scenario)


def test_catch_up_skips_a_value_that_came_back_to_the_written_one():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter, grade_interval_s=0.2)
        await source.connect()
        await source.set_grade(0.05)
        await source.set_grade(0.06)
        await source.set_grade(0.0502)  # zurück: unter der Schwelle zum geschriebenen Wert
        await asyncio.sleep(0.35)
        assert control_writes(adapter) == [*TAKEN, simulation(500)]

    run(scenario)


# --- Grundlast -------------------------------------------------------------------------------


def test_reset_grade_writes_zero_at_once_and_drops_the_pending_catch_up():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter, grade_interval_s=0.3)
        await source.connect()
        await source.set_grade(0.08)
        await source.set_grade(0.09)  # gedrosselt
        assert await source.reset_grade() is True  # sofort, obwohl das Intervall noch läuft
        assert control_writes(adapter) == [*TAKEN, simulation(800), simulation(0)]
        await asyncio.sleep(0.5)
        assert control_writes(adapter) == [*TAKEN, simulation(800), simulation(0)]  # 9 % kommt nie nach

    run(scenario)


def test_reset_grade_without_control_becomes_the_grade_for_the_next_connection():
    async def scenario(adapter):
        sim_kickr(adapter)
        source, _ = controlled(adapter)
        await source.connect()
        await source.set_grade(0.08)
        adapter.drop(KICKR)
        assert await source.reset_grade() is False
        await source.connect()
        assert control_writes(adapter)[-1] == simulation(0)

    run(scenario)


def test_release_writes_zero_then_reset_and_gives_control_back():
    async def scenario(adapter):
        respond = control_responder()

        def with_status(data):
            if data[0] == 0x01:  # der Trainer meldet das eigene Reset auch als Machine Status
                adapter.indicate(KICKR, MACHINE_STATUS, b"\x01")
            return respond(data)

        sim_kickr(adapter, respond=with_status)
        source, changes = controlled(adapter, grade_interval_s=5.0)
        await source.connect()
        await source.set_grade(0.08)
        await source.set_grade(0.09)  # gedrosselt – die Grundlast wartet nicht darauf
        await source.release()
        assert control_writes(adapter) == [*TAKEN, simulation(800), simulation(0), RESET]
        assert adapter.connected == {KICKR}  # getrennt wird erst danach (Bridge)
        assert source.control is ControlState.NONE and "lost" not in changes

    run(scenario)


def test_no_grade_follows_the_rest_load_while_releasing():
    # Ein Client, der beim Beenden noch sendet, darf die Grundlast nicht überschreiben – auch nicht, wenn das Reset
    # hängt (keine Antwort) und die Steuerung deshalb noch `active` ist.
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x01: None}))
        source, _ = controlled(adapter, grade_interval_s=0.1)
        await source.connect()
        await source.set_grade(0.08)
        releasing = asyncio.create_task(source.release())
        await asyncio.sleep(0.05)  # 0 ist geschrieben, das Reset wartet auf die Antwort
        with pytest.raises(RuntimeError):
            await source.set_grade(0.09)
        await asyncio.sleep(0.15)  # ungedrosselt: wieder ein direkter Versuch
        with pytest.raises(RuntimeError):
            await source.set_grade(0.10)
        with pytest.raises(RuntimeError, match="Reset"):
            await releasing
        await asyncio.sleep(0.2)
        assert control_writes(adapter) == [*TAKEN, simulation(800), simulation(0), RESET]

    run(scenario)


def test_release_gives_control_back_after_a_granted_request_even_if_start_hangs():
    # `0x00` bestätigt, `0x07` ohne Antwort → `error`; der Trainer führt VSpin trotzdem als Steuerer.
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x07: None}))
        source, _ = controlled(adapter)
        await source.connect()
        assert source.control is ControlState.ERROR
        await source.release()
        assert control_writes(adapter) == [*TAKEN, RESET]  # keine Steigung geschrieben → kein 0x11
        assert source.control is ControlState.NONE

    run(scenario)


def test_release_while_start_is_pending_writes_no_grade_after_the_reset():
    # Bridge endet mitten im Verbinden: `0x00` bestätigt, `0x07` offen; antwortet `0x07` erst danach, folgt dem Reset
    # keine nachgesendete Steigung mehr.
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x07: None}))
        source, _ = controlled(adapter)
        with pytest.raises(NotSupportedError):
            await source.set_grade(0.05)  # vor dem Verbinden gemeldet → Ziel fürs Nachsenden
        connecting = asyncio.create_task(source.connect())
        while control_writes(adapter) != TAKEN:
            await asyncio.sleep(0.01)
        releasing = asyncio.create_task(source.release())
        await asyncio.sleep(0.05)  # das Reset wartet hinter `0x07`
        adapter.indicate(KICKR, CONTROL_POINT, b"\x80\x07\x01")
        await releasing
        await connecting
        assert control_writes(adapter) == [*TAKEN, RESET]
        assert source.control is ControlState.NONE

    run(scenario)


def test_release_after_a_refused_request_or_a_foreign_takeover_writes_nothing():
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x00: 0x04}))  # `0x00` abgelehnt: nie Steuerer
        source, _ = controlled(adapter)
        await source.connect()
        await source.release()
        assert control_writes(adapter) == [REQUEST_CONTROL]

    run(scenario)

    async def foreign(adapter):
        sim_kickr(adapter, respond=control_responder({0x07: 0x04}))
        source, _ = controlled(adapter)
        await source.connect()
        adapter.indicate(KICKR, MACHINE_STATUS, b"\xff")  # danach übernimmt eine andere App
        await source.release()
        assert control_writes(adapter) == TAKEN

    run(foreign)


def test_release_tries_the_reset_even_if_zero_grade_fails():
    async def scenario(adapter):
        sim_kickr(adapter, respond=control_responder({0x11: 0x04}))
        source, _ = controlled(adapter)
        await source.connect()
        with pytest.raises(RuntimeError, match="Steigung 0"):
            await source.release()
        assert control_writes(adapter) == [*TAKEN, simulation(0), RESET]

    run(scenario)
