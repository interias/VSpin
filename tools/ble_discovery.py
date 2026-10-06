"""BLE-Discovery für das Wenoker JC312 (Issue #1).

Scannt nach BLE-Geräten, verbindet sich mit dem Rad, dumpt alle Services,
Characteristics und Descriptors und loggt danach alle Notifications/Indications
für eine feste Dauer mit.

Ausgabe (im Ordner --out):
  jc312_gatt_<zeit>.json          vollständiger GATT-Dump
  jc312_notify_<zeit>.raw.jsonl   eine Zeile pro Notification: {"t_ms", "char", "hex"}
                                  (gleiches Format wie die Session-Rohdaten, ADR-0008)

Beispiele:
  python tools/ble_discovery.py                       # Scan + automatische Wahl (FTMS/CSC)
  python tools/ble_discovery.py --scan-only           # nur Geräte auflisten
  python tools/ble_discovery.py --name JC312 --duration 60
  python tools/ble_discovery.py --address AA:BB:CC:DD:EE:FF

Benötigt nur `bleak` (pip install bleak). Läuft unter Windows, Linux und macOS.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    from bleak import BleakClient, BleakScanner
    from bleak.exc import BleakError
except ImportError:  # pragma: no cover - Hinweis für frische Installationen
    sys.exit("bleak fehlt: bitte zuerst `pip install bleak` ausführen.")

BASE_UUID_SUFFIX = "-0000-1000-8000-00805f9b34fb"

# Bekannte 16-Bit-UUIDs (Bluetooth SIG), damit der Dump lesbar ist.
KNOWN_UUIDS: dict[int, str] = {
    # Services
    0x1800: "Generic Access",
    0x1801: "Generic Attribute",
    0x180A: "Device Information",
    0x180D: "Heart Rate",
    0x180F: "Battery",
    0x1816: "Cycling Speed and Cadence (CSC)",
    0x1818: "Cycling Power (CPS)",
    0x1826: "Fitness Machine (FTMS)",
    # Characteristics
    0x2A00: "Device Name",
    0x2A01: "Appearance",
    0x2A04: "Peripheral Preferred Connection Parameters",
    0x2A05: "Service Changed",
    0x2A19: "Battery Level",
    0x2A23: "System ID",
    0x2A24: "Model Number String",
    0x2A25: "Serial Number String",
    0x2A26: "Firmware Revision String",
    0x2A27: "Hardware Revision String",
    0x2A28: "Software Revision String",
    0x2A29: "Manufacturer Name String",
    0x2A37: "Heart Rate Measurement",
    0x2A5B: "CSC Measurement",
    0x2A5C: "CSC Feature",
    0x2A5D: "Sensor Location",
    0x2A55: "SC Control Point",
    0x2A63: "Cycling Power Measurement",
    0x2A65: "Cycling Power Feature",
    0x2A66: "Cycling Power Control Point",
    0x2ACC: "Fitness Machine Feature",
    0x2AD2: "Indoor Bike Data",
    0x2AD3: "Training Status",
    0x2AD6: "Supported Resistance Level Range",
    0x2AD8: "Supported Power Range",
    0x2AD9: "Fitness Machine Control Point",
    0x2ADA: "Fitness Machine Status",
    # Descriptors
    0x2902: "Client Characteristic Configuration",
    0x2901: "Characteristic User Description",
}

BIKE_SERVICES = {0x1826, 0x1816, 0x1818}

BUSY_HINT = (
    "Hinweis: Ein BLE-Rad erlaubt meist nur EINE Verbindung gleichzeitig. "
    "Ist noch Kinomap, Zwift oder die Hersteller-App (Handy/Tablet) verbunden? "
    "Dort trennen bzw. Bluetooth am Handy kurz ausschalten und erneut versuchen."
)


def short_uuid(uuid: str) -> int | None:
    """16-Bit-Kurzform einer Standard-UUID, sonst None."""
    u = uuid.lower()
    if u.endswith(BASE_UUID_SUFFIX) and u.startswith("0000"):
        return int(u[4:8], 16)
    return None


def describe_uuid(uuid: str) -> str:
    s = short_uuid(uuid)
    if s is None:
        return f"{uuid} (herstellerspezifisch)"
    name = KNOWN_UUIDS.get(s, "unbekannt")
    return f"0x{s:04X} {name}"


def ascii_preview(data: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


def timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d_%H-%M-%S")


async def scan(scan_time: float) -> list[dict[str, Any]]:
    print(f"Scanne {scan_time:.0f} s nach BLE-Geräten …")
    found = await BleakScanner.discover(timeout=scan_time, return_adv=True)
    devices = []
    for device, adv in found.values():
        devices.append(
            {
                "device": device,
                "name": adv.local_name or device.name or "",
                "address": device.address,
                "rssi": adv.rssi,
                "service_uuids": [u.lower() for u in adv.service_uuids],
            }
        )
    devices.sort(key=lambda d: d["rssi"], reverse=True)
    print(f"\n{len(devices)} Gerät(e) gefunden:")
    for d in devices:
        services = ", ".join(describe_uuid(u) for u in d["service_uuids"]) or "–"
        print(f"  {d['rssi']:>4} dBm  {d['address']}  {d['name'] or '(ohne Name)'}")
        print(f"            Services: {services}")
    return devices


def is_bike(d: dict[str, Any]) -> bool:
    return any(short_uuid(u) in BIKE_SERVICES for u in d["service_uuids"])


def choose(devices: list[dict[str, Any]], name: str | None, address: str | None) -> dict[str, Any] | None:
    if address:
        matches = [d for d in devices if d["address"].lower() == address.lower()]
    elif name:
        matches = [d for d in devices if name.lower() in d["name"].lower()]
    else:
        matches = [d for d in devices if is_bike(d)]
    if len(matches) > 1 and not address:
        print("\nMehrere passende Geräte – nehme das mit dem stärksten Signal. "
              "Mit --address eindeutig festlegen.")
    return matches[0] if matches else None


async def dump_gatt(client: BleakClient) -> list[dict[str, Any]]:
    print("\nGATT-Dump:")
    services = []
    for service in client.services:
        print(f"\n[Service] {describe_uuid(service.uuid)}")
        chars = []
        for char in service.characteristics:
            entry: dict[str, Any] = {
                "uuid": char.uuid,
                "name": describe_uuid(char.uuid),
                "handle": char.handle,
                "properties": list(char.properties),
                "descriptors": [],
            }
            print(f"  [Char] {describe_uuid(char.uuid)}  handle={char.handle}  "
                  f"props={','.join(char.properties)}")
            if "read" in char.properties:
                try:
                    value = bytes(await client.read_gatt_char(char))
                    entry["value_hex"] = value.hex()
                    entry["value_ascii"] = ascii_preview(value)
                    print(f"         Wert: {value.hex()}  \"{ascii_preview(value)}\"")
                except Exception as exc:  # noqa: BLE001 - jeder Lesefehler wird nur protokolliert
                    entry["read_error"] = str(exc)
                    print(f"         Lesen fehlgeschlagen: {exc}")
            for desc in char.descriptors:
                d_entry: dict[str, Any] = {
                    "uuid": desc.uuid,
                    "name": describe_uuid(desc.uuid),
                    "handle": desc.handle,
                }
                try:
                    value = bytes(await client.read_gatt_descriptor(desc.handle))
                    d_entry["value_hex"] = value.hex()
                except Exception as exc:  # noqa: BLE001
                    d_entry["read_error"] = str(exc)
                entry["descriptors"].append(d_entry)
                print(f"    [Desc] {describe_uuid(desc.uuid)}  handle={desc.handle}  "
                      f"{d_entry.get('value_hex', d_entry.get('read_error', ''))}")
            chars.append(entry)
        services.append(
            {"uuid": service.uuid, "name": describe_uuid(service.uuid), "characteristics": chars}
        )
    return services


async def log_notifications(client: BleakClient, out_file: Path, duration: float) -> dict[str, int]:
    targets = [
        char
        for service in client.services
        for char in service.characteristics
        if "notify" in char.properties or "indicate" in char.properties
    ]
    if not targets:
        print("\nKeine Characteristic mit notify/indicate gefunden.")
        return {}

    counts: dict[str, int] = {}
    last: dict[str, str] = {}
    t0 = time.monotonic()

    with out_file.open("w", encoding="utf-8", newline="\n") as fh:

        def make_handler(uuid: str):
            def handler(_char: Any, data: bytearray) -> None:
                t_ms = int((time.monotonic() - t0) * 1000)
                fh.write(json.dumps({"t_ms": t_ms, "char": uuid, "hex": bytes(data).hex()}) + "\n")
                fh.flush()
                counts[uuid] = counts.get(uuid, 0) + 1
                last[uuid] = bytes(data).hex()
            return handler

        subscribed = []
        for char in targets:
            try:
                await client.start_notify(char, make_handler(char.uuid))
                counts[char.uuid] = 0
                subscribed.append(char)
                print(f"  abonniert: {describe_uuid(char.uuid)}")
            except Exception as exc:  # noqa: BLE001
                print(f"  Abo fehlgeschlagen: {describe_uuid(char.uuid)}: {exc}")

        print(f"\nLogge Notifications für {duration:.0f} s – jetzt treten! "
              "(locker → schnell → aufhören → wieder treten, einmal am Knopf drehen)")
        end = t0 + duration
        while (now := time.monotonic()) < end and client.is_connected:
            await asyncio.sleep(min(5.0, end - now))
            elapsed = time.monotonic() - t0
            summary = "  ".join(
                f"{describe_uuid(u).split(' ')[0]}: {counts[u]}x {last.get(u, '')[:24]}"
                for u in counts
            )
            print(f"  [{elapsed:5.1f} s] {summary}")

        if not client.is_connected:
            print("\nVerbindung während des Loggens verloren.")
        for char in subscribed:
            try:
                await client.stop_notify(char)
            except Exception:  # noqa: BLE001 - beim Aufräumen egal
                pass
    return counts


async def run(args: argparse.Namespace) -> int:
    devices = await scan(args.scan_time)
    if args.scan_only:
        return 0

    target = choose(devices, args.name, args.address)
    if target is None:
        if args.name or args.address:
            print("\nDas angegebene Gerät wurde nicht gefunden.")
        else:
            print("\nKein Gerät mit FTMS/CSC/Cycling-Power-Service gefunden. "
                  "Gerät per --name oder --address wählen (siehe Liste oben).")
        print(BUSY_HINT)
        return 2

    print(f"\nVerbinde mit {target['name'] or '(ohne Name)'} [{target['address']}] …")
    stamp = timestamp()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    gatt_file = out_dir / f"jc312_gatt_{stamp}.json"
    notify_file = out_dir / f"jc312_notify_{stamp}.raw.jsonl"

    try:
        async with BleakClient(target["device"], timeout=args.connect_timeout) as client:
            services = await dump_gatt(client)
            gatt = {
                "created": datetime.now().isoformat(timespec="seconds"),
                "device": {
                    "name": target["name"],
                    "address": target["address"],
                    "rssi": target["rssi"],
                    "advertised_services": target["service_uuids"],
                },
                "services": services,
            }
            gatt_file.write_text(json.dumps(gatt, indent=2, ensure_ascii=False), encoding="utf-8")
            print(f"\nGATT-Dump gespeichert: {gatt_file}")

            counts = await log_notifications(client, notify_file, args.duration)
    except (BleakError, asyncio.TimeoutError, OSError) as exc:
        print(f"\nVerbindung fehlgeschlagen: {exc}")
        print(BUSY_HINT)
        return 3

    print("\nZusammenfassung Notifications:")
    for uuid, n in counts.items():
        print(f"  {n:>5}x  {describe_uuid(uuid)}")
    if counts:
        print(f"Rohdaten gespeichert: {notify_file}")
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="BLE-Discovery für das Wenoker JC312 (Issue #1)")
    p.add_argument("--name", help="Gerätename (Teilstring, Groß-/Kleinschreibung egal)")
    p.add_argument("--address", help="BLE-Adresse (Windows/Linux: MAC, macOS: UUID)")
    p.add_argument("--scan-time", type=float, default=10.0, help="Scan-Dauer in s (Standard 10)")
    p.add_argument("--duration", type=float, default=60.0, help="Notification-Log in s (Standard 60)")
    p.add_argument("--connect-timeout", type=float, default=20.0, help="Verbindungs-Timeout in s")
    p.add_argument("--out", default=".", help="Ausgabeordner (Standard: aktueller Ordner)")
    p.add_argument("--scan-only", action="store_true", help="nur scannen und Geräte auflisten")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        return asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\nAbgebrochen.")
        return 130
    except (BleakError, OSError) as exc:
        # z. B. kein Bluetooth-Adapter, Bluetooth ausgeschaltet, kein BlueZ/D-Bus unter Linux
        print(f"Bluetooth nicht verfügbar: {exc!r}\n"
              "Ist der USB-Dongle eingesteckt und Bluetooth eingeschaltet?")
        return 1


if __name__ == "__main__":
    sys.exit(main())
