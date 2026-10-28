"""OpenRouter für die Stimme (ADR-0011, #79): Sprachsynthese und Kostenabruf, über eine kleine HTTP-Nahtstelle.

Nur die Standardbibliothek (`urllib`), keine zusätzliche Abhängigkeit: Es sind zwei kurze Anfragen, die Antwort ist
ein ganzer Satz MP3. Die Nahtstelle `Http` lässt Tests ohne Netz laufen. Eine abgebrochene Synthese (Barge-in)
verwirft das Ergebnis; die Anfrage im Thread läuft noch zu Ende – bei Sätzen von wenigen Sekunden vertretbar.

Bewusst **nicht** gesetzt: `provider.zdr` – ElevenLabs bietet Zero Retention nur für Enterprise, OpenRouter würde
die Anfrage sonst ablehnen (Spec #76).
"""

import asyncio
import json
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Protocol
from urllib.parse import quote

BASE_URL = "https://openrouter.ai/api/v1"
SPEECH_URL = f"{BASE_URL}/audio/speech"
GENERATION_URL = f"{BASE_URL}/generation"
TIMEOUT_S = 20.0
USER_AGENT = "vspin-companion"


class OpenRouterError(Exception):
    """OpenRouter hat die Anfrage abgelehnt oder Unbrauchbares geliefert (Toni wird heiser)."""


@dataclass(frozen=True, slots=True)
class HttpResponse:
    status: int
    headers: dict[str, str] = field(default_factory=dict)  # Namen kleingeschrieben
    body: bytes = b""


class Http(Protocol):
    async def request(self, method: str, url: str, headers: dict[str, str], body: bytes | None = None) -> HttpResponse:
        """Eine Anfrage; HTTP-Fehlerstatus kommen als `HttpResponse`, Netzfehler als Ausnahme."""
        ...


class UrllibHttp:
    async def request(self, method: str, url: str, headers: dict[str, str], body: bytes | None = None) -> HttpResponse:
        return await asyncio.to_thread(self._request, method, url, headers, body)

    @staticmethod
    def _request(method: str, url: str, headers: dict[str, str], body: bytes | None) -> HttpResponse:
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                return HttpResponse(response.status, _lower(response.headers.items()), response.read())
        except urllib.error.HTTPError as error:
            with error:
                return HttpResponse(error.code, _lower(error.headers.items()), error.read())


def _lower(items) -> dict[str, str]:
    return {name.lower(): value for name, value in items}


@dataclass(frozen=True, slots=True)
class Speech:
    audio: bytes  # MP3
    generation_id: str | None  # `X-Generation-Id`; fehlt der Header, bleibt der Satz im Kostenprotokoll „unbekannt“


class OpenRouterClient:
    """`api_key` wird je Anfrage gelesen (Umgebung oder `.env` der Ablage): ein nachgetragener Schlüssel wirkt ohne
    Neustart; fehlt er, wirft die Funktion und Toni wird heiser."""

    def __init__(self, http: Http, api_key: Callable[[], str], model: str, voice: str) -> None:
        self._http = http
        self._api_key = api_key
        self._model = model
        self._voice = voice

    async def speech(self, text: str) -> Speech:
        body = json.dumps(
            {"model": self._model, "input": text, "voice": self._voice, "response_format": "mp3"}, ensure_ascii=False
        ).encode("utf-8")
        response = await self._http.request("POST", SPEECH_URL, self._headers(json_body=True), body)
        if response.status != 200:
            raise OpenRouterError(f"Sprachsynthese: HTTP {response.status} {_snippet(response.body)}")
        if not response.body:
            raise OpenRouterError("Sprachsynthese: leere Antwort")
        return Speech(response.body, response.headers.get("x-generation-id") or None)

    async def generation_cost(self, generation_id: str) -> float | None:
        """`total_cost` (Dollar) der Generation; `None`, solange OpenRouter den Datensatz noch nicht hat (404)."""
        url = f"{GENERATION_URL}?id={quote(generation_id, safe='')}"
        response = await self._http.request("GET", url, self._headers(json_body=False))
        if response.status == 404:
            return None
        if response.status != 200:
            raise OpenRouterError(f"Generation {generation_id}: HTTP {response.status} {_snippet(response.body)}")
        try:
            cost = json.loads(response.body)["data"]["total_cost"]
        except (ValueError, KeyError, TypeError):
            raise OpenRouterError(f"Generation {generation_id}: Antwort ohne data.total_cost") from None
        if isinstance(cost, bool) or not isinstance(cost, (int, float)):
            raise OpenRouterError(f"Generation {generation_id}: total_cost ist keine Zahl")
        return float(cost)

    def _headers(self, json_body: bool) -> dict[str, str]:
        headers = {"Authorization": f"Bearer {self._api_key()}", "User-Agent": USER_AGENT}
        if json_body:
            headers["Content-Type"] = "application/json"
        return headers


def _snippet(body: bytes) -> str:
    return body[:200].decode("utf-8", errors="replace").strip()
