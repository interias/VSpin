# tools

## `ble_discovery.py` – Protokoll des JC312 herausfinden (Issue #1)

Scannt, verbindet, dumpt alle Services/Characteristics/Descriptors und loggt
danach alle Notifications mit. Braucht nur `bleak`.

```powershell
py -3.12 -m pip install bleak
py -3.12 tools\ble_discovery.py --scan-only          # Geräte auflisten
py -3.12 tools\ble_discovery.py                       # automatisch das Rad (FTMS/CSC) wählen
py -3.12 tools\ble_discovery.py --name JC312 --out dumps
py -3.12 tools\ble_discovery.py --address AA:BB:CC:DD:EE:FF --duration 60
```

Ausgabe im Ordner `--out`:

| Datei | Inhalt |
|---|---|
| `jc312_gatt_<zeit>.json` | GATT-Dump inkl. gelesener Werte (Hersteller, Firmware …) |
| `jc312_notify_<zeit>.raw.jsonl` | eine Zeile pro Notification: `{"t_ms", "char", "hex"}` – Replay-Format (ADR-0008) |

**Ablauf am Rad (60 s):** ca. 20 s locker treten, 20 s schnell, 10 s aufhören,
10 s wieder treten; dabei einmal am Widerstandsknopf drehen.

Vorher Kinomap/Zwift/Hersteller-App trennen – das Rad erlaubt nur eine Verbindung.
