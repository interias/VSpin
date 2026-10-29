"""Nahtstelle zum BLE-Stack: suchen, verbinden, lesen, schreiben, Notifications, Abbruch, trennen.

Allgemein gehalten, nicht pulsspezifisch: Die `HeartRateSource` nutzt sie als Erste, die
Trainerquelle fürs Rad (`sources/trainer.py`) nutzt sie ebenfalls. Was ein Gerät bedeutet (Rolle, Vorrang,
Parser), gehört der Quelle, nicht hierher.

Erweiterung (Spec #75): Eine Suche nimmt mehrere Services und/oder Hersteller-IDs; ein Gerät
zählt, wenn es einen der Services ankündigt oder Herstellerdaten einer der Firmen sendet (ein
Gerät, das nur Herstellerdaten sendet, ist über Services nie zu finden). `Advertisement` trägt
beides mit. Die Verbindung kann `read` und `write` (mit Antwort, mit Zeitlimit) und nennt die
Services der Gerätedatenbank. `subscribe` gilt für Notify und Indicate gleich. Die Reihenfolge
„erst Indications abonnieren, dann schreiben“ gehört der Quelle; die Nahtstelle ermöglicht sie.

Erweiterung (Spec #89, Controller): Die Verbindung nennt auch die Characteristics der Gerätedatenbank mit ihren
Eigenschaften (`characteristics`), und `write` kann ohne Antwort schreiben („write without response“), für eine
Characteristic, die nur das kann.

Alle Rückrufe kommen im Event-Loop der Bridge an (bleak ruft sie dort auf, der Fake auch).
"""

from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from typing import Protocol


class BleError(Exception):
    """BLE-Vorgang gescheitert: Suche lässt sich nicht starten (z. B. kein Bluetooth-Adapter),
    Gerät nicht erreichbar, Abonnieren oder Trennen gescheitert."""


@dataclass(frozen=True, slots=True)
class Advertisement:
    """Ein gefundenes Gerät, so wie es gerade sendet. `name` fehlt, wenn das Gerät keinen
    mitschickt; `rssi` ist die Signalstärke in dBm. `service_uuids`: angekündigte Services (volle
    128-Bit-UUIDs, klein geschrieben). `manufacturer_data`: Firmen-ID → Nutzdaten ohne die ID, wie
    bleak sie liefert. Beides ist leer, wenn das Gerät es nicht sendet."""

    address: str
    name: str | None
    rssi: int
    service_uuids: tuple[str, ...] = ()
    manufacturer_data: Mapping[int, bytes] = field(default_factory=dict, hash=False)


@dataclass(frozen=True, slots=True)
class GattCharacteristic:
    """Eine Characteristic der Gerätedatenbank: `service` und `uuid` als volle 128-Bit-UUIDs (klein geschrieben),
    `properties` wie bleak sie nennt (z. B. `notify`, `indicate`, `read`, `write`, `write-without-response`)."""

    service: str
    uuid: str
    properties: frozenset[str] = frozenset()


class BleScan(Protocol):
    """Eine laufende Suche."""

    async def stop(self) -> None: ...


class BleConnection(Protocol):
    """Eine bestehende Verbindung zu einem Gerät."""

    address: str

    @property
    def service_uuids(self) -> frozenset[str]:
        """Services der Gerätedatenbank (volle 128-Bit-UUIDs, klein geschrieben), nicht der
        Ankündigung. Fehlt ein erwarteter Service, ist das Gerät z. B. gesperrt."""
        ...

    @property
    def characteristics(self) -> tuple[GattCharacteristic, ...]:
        """Characteristics der Gerätedatenbank mit Eigenschaften, in ihrer Reihenfolge. Wirft `BleError`, wenn sie
        sich nicht lesen lässt."""
        ...

    async def subscribe(self, char: str, on_notify: Callable[[bytes], None]) -> None:
        """Notifications oder Indications der Characteristic `char` (volle 128-Bit-UUID)
        abonnieren; für die Quelle ist beides dasselbe. Wirft `BleError`."""
        ...

    async def read(self, char: str) -> bytes:
        """Wert der Characteristic `char` lesen. Wirft `BleError`, auch bei Zeitüberschreitung."""
        ...

    async def write(self, char: str, data: bytes, *, response: bool = True) -> None:
        """`data` mit Antwort („write with response“) in `char` schreiben. Kehrt zurück, wenn das
        Gerät quittiert hat. Mit `response=False` ohne Antwort (kehrt nach dem Absenden zurück). Wirft `BleError`,
        auch bei Zeitüberschreitung."""
        ...

    async def disconnect(self) -> None:
        """Trennen. Ein schon getrenntes Gerät ist kein Fehler."""
        ...


class BleAdapter(Protocol):
    """Zugang zum BLE-Stack (bleak oder der Fake der Tests)."""

    async def start_scan(
        self,
        on_found: Callable[[Advertisement], None],
        *,
        services: Iterable[str] = (),
        manufacturer_ids: Iterable[int] = (),
    ) -> BleScan:
        """Sucht nach Geräten, die einen der `services` (volle 128-Bit-UUIDs) ankündigen oder
        Herstellerdaten einer der `manufacturer_ids` (Firmen-IDs) senden. Beides leer: jede
        Ankündigung. `on_found` bekommt laufend jede passende Ankündigung, also dasselbe Gerät
        wiederholt mit aktueller Signalstärke. Wirft `BleError`, wenn die Suche nicht startet."""
        ...

    async def connect(self, address: str, on_disconnect: Callable[[], None]) -> BleConnection:
        """Verbindet mit dem Gerät an `address`. `on_disconnect` meldet, dass die Verbindung
        weg ist, auch nach eigenem `disconnect`. Wirft `BleError`, wenn das Gerät nicht
        erreichbar ist."""
        ...
