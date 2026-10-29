# ADR-0003: Geräte-Abstraktion, Simulator und Replay

- **Status:** akzeptiert
- **Datum:** 2026-10-06

## Kontext

Das Protokoll des Rads ist noch unbekannt (FTMS oder CSC, evtl. proprietär).
Entwicklung muss ohne Rad und ohne Windows möglich sein. Später soll
Widerstandssteuerung am Trainer (FTMS) ergänzt werden.

## Entscheidung

Alle Datenquellen implementieren eine gemeinsame Schnittstelle in der Bridge:

```python
class DeviceSource(Protocol):
    capabilities: set[Capability]   # CADENCE, SPEED, POWER, RESISTANCE_CONTROL …
    async def connect(self) -> None
    def samples(self) -> AsyncIterator[TelemetrySample]
    async def set_grade(self, grade: float) -> None  # Steigung als Anteil; NotSupported ohne Capability
```

`TelemetrySample` ist protokollneutral: Zeitstempel, Kadenz, Geschwindigkeit,
Leistung – jeder Wert optional und mit Herkunft `measured | estimated`.

Implementierungen:

| Quelle | Ebene | Zweck |
|---|---|---|
| `TrainerSource` (FTMS / CSC / ggf. proprietär) | Bytes → Parser | echtes Rad |
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
- `set_grade` ist von Anfang an Teil der Schnittstelle (Andockpunkt Trainer-Steuerung).

## Verworfen

- **Virtuelles BLE-Peripheral** zum Simulieren: hoher Aufwand, unter Windows
  umständlich; diese Rolle entfällt mit dem FTMS-Trainer.

## Nachtrag (2026-10-07, #19): `set_resistance` heißt `set_grade`

- Die Methode trug schon immer die virtuelle Steigung als Anteil (0.07 = 7 %), keine
  Widerstandsstufe. Sie heißt daher wie die Bus-Nachricht `set_grade`; das Gerät setzt die
  Steigung selbst in Widerstand um (ADR-0007). Der Simulator wertet sie aus und antwortet
  trotzdem mit `NotSupported`.

## Nachtrag (2026-10-28, Spec #75): Das Spiel wählt den Trainer zur Laufzeit

- Mit dem Verbindungsfenster (Kacheln je Rolle: Trainer, Puls, Controller) wählt nicht mehr allein das CLI die
  Radquelle: Welches BLE-Gerät die Radquelle ist, entscheidet das Spiel zur Laufzeit. Es merkt sich Trainer (wie die
  Pulsgeräte) in `user://settings.cfg` und schickt die Liste nach jedem Verbinden über den Bus (`set_devices`,
  `kind: "trainer"`); die Bridge verbindet das stärkste gemerkte Gerät, das sendet („Background Pairing“). Merkt das
  Spiel einen anderen, gibt die Bridge den alten frei (Steigung 0, Reset) und verbindet den neuen.
- `--source ble` heißt damit „Trainer aus den gemerkten Geräten“. Eine leere Liste heißt: kein Trainer verbindet
  sich von selbst. Ohne jede Liste – eine Bridge von Hand ohne Spiel – gilt weiter `--trainer ADRESSE` bzw. das
  stärkste FTMS-Gerät; die Bridge aus dem Spiel startet mit `--known-trainers` und wartet auf die Liste, damit sie vor
  ihr kein fremdes Gerät übernimmt.
- `sim` und `replay` bleiben CLI-Modi: Mit ihnen gibt es keinen Trainer, `set_devices` für den Trainer bleibt ohne
  Wirkung. Die Klasse der echten Radquelle heißt `TrainerSource`.
