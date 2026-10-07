# ADR-0003: Geräte-Abstraktion, Simulator und Replay

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Das Protokoll des JC312 ist noch unbekannt (FTMS oder CSC, evtl. proprietär).
Entwicklung muss ohne Rad und ohne Windows möglich sein. Später soll ein
ESP32-Retrofit Widerstandssteuerung ergänzen.

## Entscheidung

Alle Datenquellen implementieren eine gemeinsame Schnittstelle in der Bridge:

```python
class DeviceSource(Protocol):
    capabilities: set[Capability]   # CADENCE, SPEED, POWER, RESISTANCE_CONTROL …
    async def connect(self) -> None
    def samples(self) -> AsyncIterator[TelemetrySample]
    async def set_resistance(self, level: float) -> None  # NotSupported ohne Capability
```

`TelemetrySample` ist protokollneutral: Zeitstempel, Kadenz, Geschwindigkeit,
Leistung – jeder Wert optional und mit Herkunft `measured | estimated`.

Implementierungen:

| Quelle | Ebene | Zweck |
|---|---|---|
| `BleSource` (FTMS / CSC / ggf. proprietär) | Bytes → Parser | echtes Rad |
| `ReplaySource` | aufgezeichnete Roh-Notifications → Parser | Parser-Tests mit echten Daten, ohne Rad |
| `SimulatorSource` | direkt `TelemetrySample` | Game-Entwicklung |

Simulator-Modi:

- **manuell** – Kadenz per Tastatur im Bridge-Terminal (v1; Slider/Web-UI später möglich)
- **Profil** – geskriptete Abläufe inkl. Edge-Cases (Abbruch, Kadenz 0, Ausreißer)
- **Rauschen/Jitter** zuschaltbar

Auswahl per CLI: `vspin-bridge --source ble|sim|replay <datei>`.

Die Bridge zeichnet rohe BLE-Notifications mit Zeitstempel auf (Replay-Format).

## Konsequenzen

- Games können nicht unterscheiden, ob Daten echt oder simuliert sind.
- Parser sind ohne Hardware unit-testbar; der Discovery-Dump liefert erste Fixtures.
- `set_resistance` ist von Anfang an Teil der Schnittstelle (Andockpunkt ESP32).

## Verworfen

- **Virtuelles BLE-Peripheral** zum Simulieren: hoher Aufwand, unter Windows
  umständlich; diese Rolle übernimmt später der ESP32.
