"""Geräteprüfung: Trainer und Zwift-Controller einmal am echten Gerät erfassen (Spec #75, Story 17).

Das Werkzeug ist für Nutzer ohne VSpin-Kenntnisse gedacht und läuft mit einem Befehl
(`tools\\geraete-pruefen.cmd`). Es liest nur: keine Schreibzugriffe auf irgendeine Characteristic
(insbesondere nicht auf den FTMS Control Point 0x2AD9), kein RideOn-Handshake, keine Tastenauswertung.
Abonniert werden nur die SIG-Standard-Characteristics aus `SUBSCRIBABLE`.

Ablauf: suchen -> Trainer (FTMS, ersatzweise Cycling Power/CSC) und Zwift-Controller (Firma 0x094A)
erkennen -> Trainer verbinden, GATT-Dump, Mitschrift der Messdaten -> jeden Controller verbinden,
GATT-Dump, Firmware, Urteil -> Ergebnisdatei schreiben.

Ausgabe im Ordner `<repo>/pruefung/<zeit>/` (oder `--out`):
  geraetepruefung_<zeit>.json     alle Funde, Dumps, dekodierte Features und Urteile
  trainer_<zeit>.raw.jsonl        eine Zeile pro Notification: {"t_ms", "char", "hex"}
                                  (Replay-Format der Bridge, ADR-0008)

Benötigt nur `bleak` (das venv der Bridge). Exit-Code: 0 = etwas erfasst, 1 = kein Bluetooth,
2 = nichts gefunden, 3 = gefunden, aber keine Verbindung möglich.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from bleak import BleakClient, BleakScanner
    from bleak.exc import BleakError
except ImportError:  # pragma: no cover - Hinweis für frische Installationen
    sys.exit("bleak fehlt: bitte `tools\\geraete-pruefen.cmd` benutzen (venv der Bridge).")

BASE_UUID_SUFFIX = "-0000-1000-8000-00805f9b34fb"

# Services
FTMS, CYCLING_POWER, CSC, HEART_RATE, DEVICE_INFO, BATTERY = 0x1826, 0x1818, 0x1816, 0x180D, 0x180A, 0x180F
# Characteristics
FITNESS_MACHINE_FEATURE, INDOOR_BIKE_DATA, TRAINING_STATUS = 0x2ACC, 0x2AD2, 0x2AD3
RESISTANCE_RANGE, POWER_RANGE, CONTROL_POINT, MACHINE_STATUS = 0x2AD6, 0x2AD8, 0x2AD9, 0x2ADA
CYCLING_POWER_MEASUREMENT, CSC_MEASUREMENT, HEART_RATE_MEASUREMENT = 0x2A63, 0x2A5B, 0x2A37
BATTERY_LEVEL, FIRMWARE_REVISION = 0x2A19, 0x2A26

# Nur diese Characteristics werden abonniert (CCCD). Nie der Control Point 0x2AD9, nichts Proprietäres.
SUBSCRIBABLE = frozenset(
    {INDOOR_BIKE_DATA, MACHINE_STATUS, TRAINING_STATUS, CYCLING_POWER_MEASUREMENT, CSC_MEASUREMENT,
     HEART_RATE_MEASUREMENT}
)

# Zwift-Controller
ZWIFT_COMPANY_ID = 0x094A
ZWIFT_SERVICE = 0xFC82
ZWIFT_SERVICE_LEGACY = "00000001-19ca-4651-86e5-fa29dcdd09d1"
ZWIFT_NAME = "zwift sf2"
ZWIFT_SIDES = {7: "rechts", 8: "links"}

KNOWN_UUIDS: dict[int, str] = {
    FTMS: "Fitness Machine (FTMS)", CYCLING_POWER: "Cycling Power (CP)", CSC: "Cycling Speed and Cadence (CSC)",
    HEART_RATE: "Heart Rate (HR)", DEVICE_INFO: "Device Information", BATTERY: "Battery",
    0x1800: "Generic Access", 0x1801: "Generic Attribute", ZWIFT_SERVICE: "Zwift Controller",
    0x2A00: "Device Name", 0x2A01: "Appearance", 0x2A04: "Peripheral Preferred Connection Parameters",
    0x2A05: "Service Changed", BATTERY_LEVEL: "Battery Level", 0x2A23: "System ID",
    0x2A24: "Model Number String", 0x2A25: "Serial Number String", FIRMWARE_REVISION: "Firmware Revision String",
    0x2A27: "Hardware Revision String", 0x2A28: "Software Revision String", 0x2A29: "Manufacturer Name String",
    HEART_RATE_MEASUREMENT: "Heart Rate Measurement", CSC_MEASUREMENT: "CSC Measurement", 0x2A5C: "CSC Feature",
    0x2A5D: "Sensor Location", 0x2A55: "SC Control Point", CYCLING_POWER_MEASUREMENT: "Cycling Power Measurement",
    0x2A65: "Cycling Power Feature", 0x2A66: "Cycling Power Control Point",
    FITNESS_MACHINE_FEATURE: "Fitness Machine Feature", INDOOR_BIKE_DATA: "Indoor Bike Data",
    TRAINING_STATUS: "Training Status", RESISTANCE_RANGE: "Supported Resistance Level Range",
    POWER_RANGE: "Supported Power Range", CONTROL_POINT: "Fitness Machine Control Point",
    MACHINE_STATUS: "Fitness Machine Status", 0x2902: "Client Characteristic Configuration",
    0x2901: "Characteristic User Description",
}

# FTMS 1.0 (Bluetooth SIG): Fitness Machine Features und Target Setting Features, je uint32.
MACHINE_FEATURES = {
    0: "Durchschnittsgeschwindigkeit", 1: "Kadenz", 2: "Gesamtstrecke", 3: "Neigung", 4: "Höhengewinn",
    5: "Pace", 6: "Schrittzahl", 7: "Widerstandsstufe", 8: "Stride-Zähler", 9: "Energieverbrauch",
    10: "Herzfrequenz", 11: "Metabolisches Äquivalent", 12: "Verstrichene Zeit", 13: "Verbleibende Zeit",
    14: "Leistung", 15: "Kraft am Band und Leistung", 16: "Nutzerdaten speichern",
}
TARGET_FEATURES = {
    0: "Zielgeschwindigkeit", 1: "Zielneigung", 2: "Zielwiderstand", 3: "Zielleistung (ERG)",
    4: "Zielherzfrequenz", 5: "Zielenergie", 6: "Zielschrittzahl", 7: "Ziel-Stride-Zahl", 8: "Zielstrecke",
    9: "Zieltrainingszeit", 10: "Zielzeit in zwei Herzfrequenzzonen", 11: "Zielzeit in drei Herzfrequenzzonen",
    12: "Zielzeit in fünf Herzfrequenzzonen", 13: "Simulation (SIM)", 14: "Radumfang",
    15: "Ausrollen (Spin Down)", 16: "Zielkadenz",
}

# Indoor Bike Data 0x2AD2: Flag-Bit -> Feldgröße in Bytes (Bit 0 ist umgekehrt: 0 = Geschwindigkeit da).
_IBD_SIZES = {1: 2, 2: 2, 3: 2, 4: 3, 5: 2, 6: 2, 7: 2, 8: 5, 9: 1, 10: 1, 11: 2, 12: 2}

PAIR_HINT = (
    "Der KICKR CORE 2 verlangt gebondetes Pairing (EU RED). Bitte in den Windows-Einstellungen unter "
    "„Bluetooth & Geräte“ den Trainer koppeln (Gerät hinzufügen -> Bluetooth) und das Werkzeug erneut starten."
)
BUSY_HINT = (
    "Trainer eingeschaltet und aufgeweckt (kurz treten)? Zwift, Wahoo-App und andere Trainer-Apps geschlossen? "
    "Der Trainer erlaubt nur 3 BLE-Verbindungen gleichzeitig; Bluetooth am Handy/Tablet kurz auszuschalten hilft."
)
NO_BLUETOOTH_HINT = (
    "Bluetooth ist nicht verfügbar. Ist ein Bluetooth-Adapter (oder USB-Dongle) eingesteckt und Bluetooth in den "
    "Windows-Einstellungen eingeschaltet?"
)


# --- UUIDs ---------------------------------------------------------------------------------------------

def short_uuid(uuid: str) -> int | None:
    """16-Bit-Kurzform einer Standard-UUID, sonst None."""
    u = str(uuid).lower()
    if u.endswith(BASE_UUID_SUFFIX) and u.startswith("0000"):
        return int(u[4:8], 16)
    return None


def full_uuid(uuid: str | int) -> str:
    """Volle 128-Bit-UUID in Kleinschreibung (ADR-0008); 16-Bit-Kurzformen werden aufgefüllt."""
    if isinstance(uuid, int):
        return f"{uuid:08x}{BASE_UUID_SUFFIX}"
    u = str(uuid).lower()
    if re.fullmatch(r"(0x)?[0-9a-f]{4}", u):
        return f"0000{u[-4:]}{BASE_UUID_SUFFIX}"
    return u


def describe_uuid(uuid: str) -> str:
    s = short_uuid(uuid)
    if s is None:
        if full_uuid(uuid) == ZWIFT_SERVICE_LEGACY:
            return f"{uuid} Zwift Controller (älteres Format)"
        return f"{uuid} (herstellerspezifisch)"
    return f"0x{s:04X} {KNOWN_UUIDS.get(s, 'unbekannt')}"


def ascii_preview(data: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


def timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d_%H-%M-%S")


# --- Dekodierung (nur Spezifikation, kein Bridge-Parser) -----------------------------------------------

def _bits(value: int, names: dict[int, str]) -> list[str]:
    """Namen der gesetzten Bits; Bits ohne Namen als „unbekanntes Bit N“."""
    return [names.get(bit, f"unbekanntes Bit {bit}") for bit in range(32) if value >> bit & 1]


def decode_fitness_machine_feature(data: bytes) -> dict[str, Any]:
    """0x2ACC: uint32 Fitness Machine Features, uint32 Target Setting Features (Little Endian)."""
    if len(data) < 8:
        raise ValueError(f"Fitness Machine Feature braucht 8 Bytes, bekam {len(data)}")
    machine = int.from_bytes(data[0:4], "little")
    target = int.from_bytes(data[4:8], "little")
    return {
        "machine_raw": f"0x{machine:08X}",
        "machine": _bits(machine, MACHINE_FEATURES),
        "target_raw": f"0x{target:08X}",
        "target": _bits(target, TARGET_FEATURES),
    }


def decode_resistance_range(data: bytes) -> dict[str, float]:
    """0x2AD6: sint16 min, sint16 max, uint16 Schrittweite, je Einheit 0,1."""
    if len(data) < 6:
        raise ValueError(f"Supported Resistance Level Range braucht 6 Bytes, bekam {len(data)}")
    low = int.from_bytes(data[0:2], "little", signed=True)
    high = int.from_bytes(data[2:4], "little", signed=True)
    step = int.from_bytes(data[4:6], "little")
    return {"min": low / 10, "max": high / 10, "step": step / 10}


def decode_power_range(data: bytes) -> dict[str, int]:
    """0x2AD8: sint16 min (W), sint16 max (W), uint16 Schrittweite (W)."""
    if len(data) < 6:
        raise ValueError(f"Supported Power Range braucht 6 Bytes, bekam {len(data)}")
    return {
        "min_w": int.from_bytes(data[0:2], "little", signed=True),
        "max_w": int.from_bytes(data[2:4], "little", signed=True),
        "step_w": int.from_bytes(data[4:6], "little"),
    }


def inspect_indoor_bike_data(data: bytes) -> dict[str, Any]:
    """Flags und, soweit lesbar, Kadenz (rpm) und Leistung (W) einer 0x2AD2-Meldung."""
    if len(data) < 2:
        return {"cadence_flag": False, "power_flag": False, "cadence_rpm": None, "power_w": None}
    flags = int.from_bytes(data[:2], "little")
    result: dict[str, Any] = {
        "cadence_flag": bool(flags & 1 << 2), "power_flag": bool(flags & 1 << 6),
        "cadence_rpm": None, "power_w": None,
    }
    offset = 2 if flags & 1 else 4  # Bit 0 = 0: Geschwindigkeit (uint16) steht vorn
    for bit in range(1, 13):
        if not flags & 1 << bit:
            continue
        size = _IBD_SIZES[bit]
        if len(data) < offset + size:
            break
        if bit == 2:
            result["cadence_rpm"] = int.from_bytes(data[offset:offset + 2], "little") / 2
        elif bit == 6:
            result["power_w"] = int.from_bytes(data[offset:offset + 2], "little", signed=True)
        offset += size
    return result


# --- Erkennung -----------------------------------------------------------------------------------------

def classify_device(name: str, service_uuids: list[str], manufacturer_data: dict[int, bytes]) -> dict[str, Any]:
    """Rolle eines Geräts aus seiner Ankündigung: Zwift-Controller oder Trainer (oder keines)."""
    shorts = {short_uuid(u) for u in service_uuids}
    full = {full_uuid(u) for u in service_uuids}
    info: dict[str, Any] = {"role": None, "trainer_kind": None}
    zwift_data = manufacturer_data.get(ZWIFT_COMPANY_ID)
    if zwift_data is not None or ZWIFT_NAME in name.lower():
        info["role"] = "controller"
        side = ZWIFT_SIDES.get(zwift_data[0]) if zwift_data else None
        info["side"] = side or "unbekannt"
        info["advertises_zwift_service"] = ZWIFT_SERVICE in shorts or ZWIFT_SERVICE_LEGACY in full
    elif FTMS in shorts:
        info.update(role="trainer", trainer_kind="FTMS")
    elif CYCLING_POWER in shorts:
        info.update(role="trainer", trainer_kind="Cycling Power")
    elif CSC in shorts:
        info.update(role="trainer", trainer_kind="CSC")
    return info


def pick_trainer(devices: list[dict[str, Any]]) -> dict[str, Any] | None:
    """FTMS-Geräte vor Cycling Power vor CSC; unter gleichen das mit der stärksten Signalstärke."""
    for kind in ("FTMS", "Cycling Power", "CSC"):
        candidates = [d for d in devices if d["role"] == "trainer" and d["trainer_kind"] == kind]
        if candidates:
            return max(candidates, key=lambda d: d["rssi"])
    return None


def parse_firmware(text: str | None) -> tuple[int, ...] | None:
    match = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text or "")
    return tuple(int(g) for g in match.groups() if g is not None) if match else None


def judge_controller(service_visible: bool, firmware: str | None) -> dict[str, str]:
    """Urteil in Klartext: „sichtbar“ = Service da, „gesperrt“ = Service fehlt."""
    version = parse_firmware(firmware)
    new_firmware = version is not None and version[:2] >= (1, 3)
    if service_visible:
        return {"verdict": "sichtbar",
                "text": "Sichtbar: Der Zwift-Service ist ohne Zwift-App da, die Tasten wären für VSpin erreichbar."}
    text = "Gesperrt: Der Zwift-Service fehlt, die Tasten wären für VSpin nicht erreichbar."
    if new_firmware:
        text += (f" Firmware {firmware} (ab 1.3, Ride V2): Ride V2 gibt ihn erst frei, nachdem er in der "
                 "Zwift-App verbunden war (ca. 24 h).")
    elif version is None:
        text += (" Die Firmware ließ sich nicht lesen; ab Firmware 1.3 (Ride V2) gibt der Controller den Service "
                 "erst frei, nachdem er in der Zwift-App verbunden war (ca. 24 h).")
    else:
        text += f" Firmware {firmware} ist älter als 1.3; das ist unerwartet."
    return {"verdict": "gesperrt", "text": text}


# --- Suche ---------------------------------------------------------------------------------------------

async def scan(scan_time: float) -> list[dict[str, Any]]:
    print(f"Suche {scan_time:.0f} s nach Bluetooth-Geräten ...")
    found = await BleakScanner.discover(timeout=scan_time, return_adv=True)
    devices = []
    for device, adv in found.values():
        manufacturer = {int(k): bytes(v) for k, v in (adv.manufacturer_data or {}).items()}
        name = adv.local_name or device.name or ""
        services = [str(u).lower() for u in adv.service_uuids]
        devices.append({
            "_device": device, "name": name, "address": device.address, "rssi": adv.rssi,
            "service_uuids": services,
            "manufacturer_data": {f"0x{k:04X}": v.hex() for k, v in manufacturer.items()},
            **classify_device(name, services, manufacturer),
        })
    devices.sort(key=lambda d: d["rssi"], reverse=True)
    print(f"\n{len(devices)} Gerät(e) gefunden:")
    for d in devices:
        label = ""
        if d["role"] == "trainer":
            label = f"TRAINER ({d['trainer_kind']})"
        elif d["role"] == "controller":
            label = f"ZWIFT-CONTROLLER ({d['side']})"
        print(f"  {d['rssi']:>4} dBm  {d['address']}  {d['name'] or '(ohne Name)'}  {label}")
    return devices


# --- GATT ----------------------------------------------------------------------------------------------

async def dump_gatt(client: Any) -> list[dict[str, Any]]:
    """Alle Services/Characteristics samt lesbarer Werte. Nur Lesezugriffe."""
    services = []
    for service in client.services:
        print(f"\n  [Service] {describe_uuid(service.uuid)}")
        chars = []
        for char in service.characteristics:
            entry: dict[str, Any] = {
                "uuid": full_uuid(char.uuid), "name": describe_uuid(char.uuid), "handle": char.handle,
                "properties": list(char.properties),
                "descriptors": [full_uuid(d.uuid) for d in char.descriptors],
            }
            line = f"    [Char] {describe_uuid(char.uuid)}  ({','.join(char.properties)})"
            if "read" in char.properties:
                try:
                    value = bytes(await client.read_gatt_char(char))
                    entry["value_hex"] = value.hex()
                    entry["value_ascii"] = ascii_preview(value)
                    line += f"\n           Wert: {value.hex()}  \"{ascii_preview(value)}\""
                except Exception as exc:  # noqa: BLE001 - jeder Lesefehler wird nur protokolliert
                    entry["read_error"] = str(exc)
                    line += f"\n           Lesen fehlgeschlagen: {exc}"
            print(line)
            chars.append(entry)
        services.append({"uuid": full_uuid(service.uuid), "name": describe_uuid(service.uuid),
                         "characteristics": chars})
    return services


def find_value(services: list[dict[str, Any]], short: int) -> bytes | None:
    for service in services:
        for char in service["characteristics"]:
            if short_uuid(char["uuid"]) == short and "value_hex" in char:
                return bytes.fromhex(char["value_hex"])
    return None


def read_text(services: list[dict[str, Any]], short: int) -> str | None:
    value = find_value(services, short)
    return value.decode("utf-8", errors="replace").strip("\x00 ") if value is not None else None


def service_summary(services: list[dict[str, Any]]) -> list[dict[str, str]]:
    kinds = {FTMS: "FTMS", CYCLING_POWER: "Cycling Power", CSC: "CSC", HEART_RATE: "Herzfrequenz",
             DEVICE_INFO: "Device Information", BATTERY: "Batterie", 0x1800: "Generic Access",
             0x1801: "Generic Attribute"}
    result = []
    for service in services:
        kind = kinds.get(short_uuid(service["uuid"]))
        result.append({"uuid": service["uuid"], "kind": kind or "unbekannt (herstellerspezifisch, z. B. Wahoo/Zwift)"})
    return result


# --- Mitschrift ----------------------------------------------------------------------------------------

def capture_phases(duration: float) -> list[tuple[float, str]]:
    """Anleitung für die Mitschrift: erst locker, dann schneller, dann aufhören (Dauer einstellbar)."""
    easy, fast = round(duration * 0.5), round(duration * 0.25)
    return [
        (0.0, f"JETZT {easy} s locker treten."),
        (float(easy), f"JETZT {fast} s schneller treten."),
        (float(easy + fast), "JETZT AUFHÖREN zu treten (Pedale stehen lassen)."),
    ]


async def capture(client: Any, out_file: Path, duration: float) -> tuple[dict[str, int], list[tuple[int, str, bytes]]]:
    """Abonniert die SIG-Standard-Characteristics und schreibt jede Notification ins Replay-Format."""
    targets = [
        char for service in client.services for char in service.characteristics
        if short_uuid(char.uuid) in SUBSCRIBABLE and ("notify" in char.properties or "indicate" in char.properties)
    ]
    if not targets:
        print("\n  Keine Mess-Characteristic zum Mitschreiben gefunden.")
        return {}, []
    counts: dict[str, int] = {}
    records: list[tuple[int, str, bytes]] = []
    t0 = time.monotonic()
    with out_file.open("w", encoding="utf-8", newline="\n") as fh:

        def make_handler(uuid: str):
            def handler(_char: Any, data: bytearray) -> None:
                t_ms = int((time.monotonic() - t0) * 1000)
                fh.write(json.dumps({"t_ms": t_ms, "char": uuid, "hex": bytes(data).hex()}) + "\n")
                fh.flush()
                counts[uuid] = counts.get(uuid, 0) + 1
                records.append((t_ms, uuid, bytes(data)))
            return handler

        subscribed = []
        for char in targets:
            try:
                await client.start_notify(char, make_handler(full_uuid(char.uuid)))
                subscribed.append(char)
                print(f"  lausche mit: {describe_uuid(char.uuid)}")
            except Exception as exc:  # noqa: BLE001
                print(f"  Mitschrift nicht möglich für {describe_uuid(char.uuid)}: {exc}")

        print(f"\nMitschrift für {duration:.0f} s. Bitte jetzt aufs Rad:")
        begin = time.monotonic()  # Countdown ab hier; t0 der Datei bleibt unverändert, sonst fiele t_ms
        pending = capture_phases(duration)
        next_status = 5.0
        end = begin + duration
        while (now := time.monotonic()) < end and client.is_connected:
            elapsed = now - begin
            while pending and elapsed >= pending[0][0]:
                print(f"  [{elapsed:4.0f} s] {pending.pop(0)[1]}")
            if elapsed >= next_status:
                print(f"  [{elapsed:4.0f} s] noch {end - now:.0f} s, bisher {sum(counts.values())} Meldungen")
                next_status += 5.0
            await asyncio.sleep(max(0.01, min(1.0, end - now)))
        if not client.is_connected:
            print("\n  Die Verbindung ging während der Mitschrift verloren.")
        for char in subscribed:
            try:
                await client.stop_notify(char)
            except Exception:  # noqa: BLE001 - beim Aufräumen egal
                pass
    return counts, records


def analyse_capture(counts: dict[str, int], records: list[tuple[int, str, bytes]]) -> dict[str, Any]:
    """Was die Mitschrift über Kadenz/Leistung in Indoor Bike Data und die Meldungsrate sagt."""
    result: dict[str, Any] = {"messages": {describe_uuid(u): n for u, n in counts.items()}}
    ibd = [(t, inspect_indoor_bike_data(d)) for t, u, d in records if short_uuid(u) == INDOOR_BIKE_DATA]
    if ibd:
        span = (ibd[-1][0] - ibd[0][0]) / 1000
        cadences = [i["cadence_rpm"] for _, i in ibd if i["cadence_rpm"] is not None]
        powers = [i["power_w"] for _, i in ibd if i["power_w"] is not None]
        result["indoor_bike_data"] = {
            "messages": len(ibd),
            "messages_per_second": round((len(ibd) - 1) / span, 2) if span > 0 else None,
            "cadence_flag_messages": sum(i["cadence_flag"] for _, i in ibd),
            "power_flag_messages": sum(i["power_flag"] for _, i in ibd),
            "max_cadence_rpm": max(cadences) if cadences else None,
            "max_power_w": max(powers) if powers else None,
        }
    cp = [d for _, u, d in records if short_uuid(u) == CYCLING_POWER_MEASUREMENT and len(d) >= 2]
    if cp:
        result["cycling_power"] = {
            "messages": len(cp),
            "crank_data_messages": sum(bool(int.from_bytes(d[:2], "little") & 1 << 5) for d in cp),
        }
    csc = [d for _, u, d in records if short_uuid(u) == CSC_MEASUREMENT and d]
    if csc:
        result["csc"] = {"messages": len(csc), "crank_data_messages": sum(bool(d[0] & 1 << 1) for d in csc)}
    return result


def capture_findings(analysis: dict[str, Any]) -> list[str]:
    ibd = analysis.get("indoor_bike_data")
    if ibd is None:
        return ["Indoor Bike Data (0x2AD2): keine Meldungen in der Mitschrift, Kadenz und Leistung ungeklärt."]
    n = ibd["messages"]
    rate = f", {ibd['messages_per_second']} pro Sekunde." if ibd["messages_per_second"] is not None else "."
    lines = [f"Indoor Bike Data (0x2AD2): {n} Meldungen{rate}"]
    lines.append(
        f"Kadenz in 0x2AD2: ja ({ibd['cadence_flag_messages']} von {n} Meldungen, höchster Wert "
        f"{ibd['max_cadence_rpm']} rpm)." if ibd["cadence_flag_messages"]
        else "Kadenz in 0x2AD2: nein (Flag „Instantaneous Cadence present“ nie gesetzt).")
    lines.append(
        f"Leistung in 0x2AD2: ja ({ibd['power_flag_messages']} von {n} Meldungen, höchster Wert "
        f"{ibd['max_power_w']} W)." if ibd["power_flag_messages"]
        else "Leistung in 0x2AD2: nein (Flag „Instantaneous Power present“ nie gesetzt).")
    if "cycling_power" in analysis:
        cp = analysis["cycling_power"]
        lines.append(f"Cycling Power (0x2A63): {cp['messages']} Meldungen, Kurbeldaten in {cp['crank_data_messages']}.")
    if "csc" in analysis:
        c = analysis["csc"]
        lines.append(f"CSC (0x2A5B): {c['messages']} Meldungen, Kurbeldaten (Kadenz) in {c['crank_data_messages']}.")
    return lines


# --- Trainer / Controller ------------------------------------------------------------------------------

def decode_trainer_features(services: list[dict[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, short, decoder in (("features", FITNESS_MACHINE_FEATURE, decode_fitness_machine_feature),
                                ("resistance_range", RESISTANCE_RANGE, decode_resistance_range),
                                ("power_range", POWER_RANGE, decode_power_range)):
        value = find_value(services, short)
        if value is None:
            continue
        try:
            out[key] = decoder(value)
        except ValueError as exc:
            out[key] = {"error": str(exc)}
    return out


def print_trainer_report(result: dict[str, Any]) -> None:
    print("\nAuswertung Trainer:")
    print("  Services:")
    for s in result["services"]:
        print(f"    {s['kind']}: {s['uuid']}")
    info = result["device_information"]
    if any(info.values()):
        print("  Geräteinformation: " + ", ".join(f"{k} {v}" for k, v in info.items() if v))
    features = result.get("features")
    if features and "machine" in features:
        print(f"  FTMS Fitness Machine Features ({features['machine_raw']}): "
              + (", ".join(features["machine"]) or "keine"))
        print(f"  FTMS Target Setting Features ({features['target_raw']}): "
              + (", ".join(features["target"]) or "keine"))
    else:
        print("  FTMS Feature (0x2ACC): nicht lesbar oder nicht vorhanden.")
    if (r := result.get("resistance_range")) and "min" in r:
        print(f"  Widerstandsstufen (0x2AD6): {r['min']} bis {r['max']}, Schrittweite {r['step']}")
    if (p := result.get("power_range")) and "min_w" in p:
        print(f"  Leistungsbereich (0x2AD8): {p['min_w']} bis {p['max_w']} W, Schrittweite {p['step_w']} W")
    for line in result.get("findings", []):
        print(f"  {line}")


async def check_trainer(target: dict[str, Any], args: argparse.Namespace, out_dir: Path, stamp: str) -> dict[str, Any]:
    print(f"\n=== Trainer: {target['name'] or '(ohne Name)'} [{target['address']}] ===")
    print("Verbinde ...")
    raw_file = out_dir / f"trainer_{stamp}.raw.jsonl"
    result: dict[str, Any] = {"name": target["name"], "address": target["address"]}
    try:
        async with BleakClient(target["_device"], timeout=args.connect_timeout) as client:
            print("Verbunden. GATT-Dump (nur lesen):")
            services = await dump_gatt(client)
            result["gatt"] = services
            result["services"] = service_summary(services)
            result["device_information"] = {
                "manufacturer": read_text(services, 0x2A29), "model": read_text(services, 0x2A24),
                "firmware": read_text(services, FIRMWARE_REVISION), "hardware": read_text(services, 0x2A27),
            }
            result.update(decode_trainer_features(services))
            counts, records = await capture(client, raw_file, args.duration)
            result["capture"] = analyse_capture(counts, records)
            result["findings"] = capture_findings(result["capture"])
    except (BleakError, asyncio.TimeoutError, OSError) as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(f"\nVerbindung zum Trainer fehlgeschlagen: {exc}\n  {PAIR_HINT}\n  {BUSY_HINT}")
    if raw_file.exists():
        if raw_file.stat().st_size > 0:
            result["raw_file"] = str(raw_file)
        else:
            raw_file.unlink()
    if "gatt" in result:
        print_trainer_report(result)
    return result


async def check_controller(target: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    print(f"\n=== Zwift-Controller {target['side']}: {target['name'] or '(ohne Name)'} [{target['address']}] ===")
    result: dict[str, Any] = {"name": target["name"], "address": target["address"], "side": target["side"],
                              "advertises_zwift_service": target.get("advertises_zwift_service", False)}
    try:
        async with BleakClient(target["_device"], timeout=args.connect_timeout) as client:
            print("Verbunden. GATT-Dump (nur lesen):")
            services = await dump_gatt(client)
            result["gatt"] = services
            uuids = {s["uuid"] for s in services}
            result["service_visible"] = bool({full_uuid(ZWIFT_SERVICE), ZWIFT_SERVICE_LEGACY} & uuids)
            result["firmware"] = read_text(services, FIRMWARE_REVISION)
            battery = find_value(services, BATTERY_LEVEL)
            result["battery_percent"] = battery[0] if battery else None
            result.update(judge_controller(result["service_visible"], result["firmware"]))
    except (BleakError, asyncio.TimeoutError, OSError) as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
        result["verdict"] = "nicht geprüft"
        result["text"] = ("Nicht geprüft: keine Verbindung. Controller aufwecken (Taste drücken), von Zwift-App und "
                          "Handy trennen und erneut starten.")
        print(f"\nVerbindung zum Controller fehlgeschlagen: {exc}\n  {result['text']}")
        return result
    battery_text = f"{result['battery_percent']} %" if result["battery_percent"] is not None else "nicht lesbar"
    print("\nAuswertung Controller:")
    print(f"  Zwift-Service sichtbar: {'ja' if result['service_visible'] else 'nein'}")
    print(f"  Firmware: {result['firmware'] or 'nicht lesbar'}   Batterie: {battery_text}")
    print(f"  {result['text']}")
    return result


# --- Ablauf --------------------------------------------------------------------------------------------

def public(device: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in device.items() if not k.startswith("_")}


async def run(args: argparse.Namespace) -> int:
    print("Geräteprüfung: Trainer und Zwift-Controller")
    print("Es wird nur gelesen, am Trainer wird nichts verstellt.\n")
    print("BITTE VORHER SCHLIESSEN: Zwift, die Wahoo-App und alle anderen Trainer-Apps (auch am Handy/Tablet).\n")
    try:
        devices = await scan(args.scan_time)
    except (BleakError, OSError) as exc:
        print(f"\n{NO_BLUETOOTH_HINT}\n(Technische Meldung: {exc!r})")
        return 1
    if args.scan_only:
        return 0

    if args.address:
        trainer = next((d for d in devices if d["address"].lower() == args.address.lower()), None)
        if trainer is None:
            print(f"\nDas Gerät {args.address} wurde nicht gefunden.")
    else:
        trainer = pick_trainer(devices)
    controllers = [d for d in devices if d["role"] == "controller"]
    if trainer is None:
        print(f"\nKein Trainer gefunden. {BUSY_HINT}")
    elif any(d["role"] == "trainer" and d is not trainer for d in devices):
        print(f"\nMehrere Trainer gefunden, ich nehme den mit dem stärksten Signal: "
              f"{trainer['name']} [{trainer['address']}].")
    if not controllers:
        print("\nKein Zwift-Controller gefunden (Controller aufwecken: eine Taste drücken; er darf nicht mit der "
              "Zwift-App oder dem Handy verbunden sein).")

    stamp = timestamp()
    out_dir = Path(args.out) if args.out else Path(__file__).resolve().parent.parent / "pruefung" / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    trainer_result = await check_trainer(trainer, args, out_dir, stamp) if trainer else None
    controller_results = [await check_controller(c, args) for c in controllers]

    captured = bool(trainer_result and "gatt" in trainer_result) or any("gatt" in c for c in controller_results)
    result_file = out_dir / f"geraetepruefung_{stamp}.json"
    summary = {
        "created": datetime.now().isoformat(timespec="seconds"),
        "scan": [public(d) for d in devices],
        "trainer": trainer_result,
        "controllers": controller_results,
    }
    result_file.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    print("\n=== Fertig ===")
    files = [result_file]
    if trainer_result and trainer_result.get("raw_file"):
        files.append(Path(trainer_result["raw_file"]))
    if captured:
        print("Bitte schicke diese Dateien zurück:")
    else:
        print("Es konnte nichts erfasst werden. Die Ergebnisdatei zeigt, was gefunden wurde; bitte trotzdem schicken:")
    for f in files:
        print(f"  {f}")
    print(f"Ordner: {out_dir}")
    if captured:
        return 0
    return 3 if (trainer or controllers) else 2


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Geräteprüfung: erfasst Trainer (GATT-Dump, Features) und Zwift-Controller (Service, Firmware) "
                    "einmal am echten Gerät. Nur lesen.")
    p.add_argument("--address", help="Trainer fest wählen (BLE-Adresse statt automatischer Wahl)")
    p.add_argument("--scan-time", type=float, default=15.0, help="Suchdauer in s (Standard 15)")
    p.add_argument("--duration", type=float, default=60.0, help="Dauer der Mitschrift am Rad in s (Standard 60)")
    p.add_argument("--connect-timeout", type=float, default=20.0, help="Verbindungs-Timeout in s (Standard 20)")
    p.add_argument("--out", help="Ausgabeordner (Standard: <repo>/pruefung/<zeit>)")
    p.add_argument("--scan-only", action="store_true", help="nur suchen und die Funde auflisten")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    args = parse_args(argv)
    try:
        return asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\nAbgebrochen.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
