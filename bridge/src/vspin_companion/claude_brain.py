"""Echter Brain-Adapter (ADR-0011): Claude Haiku 5.5 über das Claude Agent SDK.

`ClaudeSDKClient` mit einer Sitzung je Fahrt, eingebaute Werkzeuge aus, keine Projekt- oder Nutzereinstellungen,
Tonis Werkzeuge über einen In-Process-MCP-Server, `effort: low` für die Latenz. Anmeldung nach `brain` in
`companion.json`: `oauth` (Standard) mit `CLAUDE_CODE_OAUTH_TOKEN` aus `claude setup-token`, `api_key` mit
`ANTHROPIC_API_KEY` – je aus der Umgebung oder der `.env` der Ablage (`env_file.py`). **Kein stilles Ausweichen:**
fehlt das Geheimnis der gewählten Anmeldung, wird Toni heiser; das jeweils andere wird für den CLI-Prozess geleert.

`claude_agent_sdk` (Extra `companion`) wird erst beim ersten Gebrauch importiert; ohne das Paket wird Toni heiser,
der Prozess läuft weiter. Kein Test ruft diesen Adapter gegen Claude – der Nutzer prüft ihn von Hand (Spec #76).
"""

from collections.abc import AsyncIterator
from pathlib import Path

from .env_file import ENV_FILE, load_secret
from .ports import ToolCall, ToolHandler

MODEL = "claude-haiku-5-5"
EFFORT = "low"  # Haiku 5.5 denkt adaptiv, Standard wäre `medium` – Ziel ≤ 2,5 s bis zum ersten Ton
OAUTH_TOKEN_ENV = "CLAUDE_CODE_OAUTH_TOKEN"
API_KEY_ENV = "ANTHROPIC_API_KEY"
AUTH_TOKEN_ENV = "ANTHROPIC_AUTH_TOKEN"  # stünde in der Rangfolge der CLI über beiden – wird immer geleert
SERVER = "toni"  # Werkzeuge heißen für das SDK `mcp__toni__<name>`

SUMMARY_SYSTEM = (
    "Du räumst Textdateien eines sprechenden Radbegleiters auf. Antworte auf Deutsch und nur mit dem verlangten Text."
)

TOOLS = (
    (
        "remember",
        "Merke dir dauerhaft etwas über den Fahrer: Ziel, Vorliebe, Anweisung oder Running Gag (ein kurzer Satz).",
        {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    ),
    (
        "update_soul",
        "Ändere deinen Charakter dauerhaft, z. B. auf „sei witziger“ oder „sei mal ernster“. `text` ist der "
        "vollständige neue Text deiner Seele, höchstens 1 500 Zeichen.",
        {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
    ),
    (
        "set_wake_interval",
        "Stelle ein, wie oft du dich von selbst meldest: zufällig alle min_minutes bis max_minutes Minuten (je 1–30).",
        {
            "type": "object",
            "properties": {
                "min_minutes": {"type": "number", "minimum": 1, "maximum": 30},
                "max_minutes": {"type": "number", "minimum": 1, "maximum": 30},
            },
            "required": ["min_minutes", "max_minutes"],
        },
    ),
    (
        "stay_silent",
        "Der Fahrer will Ruhe: bis zum Fahrtende meldest du dich nicht mehr von selbst, Fragen beantwortest du weiter. "
        "until_ride_end=false hebt das wieder auf.",
        {"type": "object", "properties": {"until_ride_end": {"type": "boolean"}}, "required": ["until_ride_end"]},
    ),
)


class BrainUnavailable(Exception):
    """Toni kann nicht denken: Anmeldung fehlt, SDK fehlt oder Claude meldet einen Fehler (Netz, Token, Limit)."""


def sdk_env(brain: str, data_dir: Path, env: dict[str, str] | None = None) -> dict[str, str]:
    """Umgebung für den CLI-Prozess des SDK nach der Weiche `brain` – nur das Geheimnis der gewählten Anmeldung,
    das andere geleert, damit der CLI-Prozess nie still auf die andere Abrechnung ausweicht."""
    if brain == "oauth":
        token = load_secret(OAUTH_TOKEN_ENV, data_dir, env)
        if not token:
            raise BrainUnavailable(
                f"{OAUTH_TOKEN_ENV} fehlt (`claude setup-token`, in die Umgebung oder {data_dir / ENV_FILE}) – "
                "kein Ausweichen auf den API-Schlüssel ohne `brain: api_key`"
            )
        chosen = {OAUTH_TOKEN_ENV: token, API_KEY_ENV: ""}
    elif brain == "api_key":
        key = load_secret(API_KEY_ENV, data_dir, env)
        if not key:
            raise BrainUnavailable(f"{API_KEY_ENV} fehlt (Umgebung oder {data_dir / ENV_FILE}) bei `brain: api_key`")
        chosen = {API_KEY_ENV: key, OAUTH_TOKEN_ENV: ""}
    else:
        raise BrainUnavailable(f"unbekannte Anmeldung brain={brain!r}")
    chosen[AUTH_TOKEN_ENV] = ""  # ein geerbtes Bearer-Token würde sonst vor beiden Anmeldungen gelten
    chosen["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"  # Gesprächsverlauf nur im Speicher (ADR-0008 Nachtrag #76)
    chosen["ENABLE_TOOL_SEARCH"] = "false"  # vier Werkzeuge gleich geladen, keine Suchrunde vor dem ersten Ton
    return chosen


class ClaudeBrain:
    def __init__(self, brain: str, data_dir: Path) -> None:
        self._brain = brain
        self._data_dir = data_dir
        self._client = None

    async def open_session(self, system_prompt: str, tools: ToolHandler) -> None:
        env = sdk_env(self._brain, self._data_dir)
        sdk = _import_sdk()
        server = sdk.create_sdk_mcp_server(name=SERVER, version="1.0.0", tools=_sdk_tools(sdk, tools))
        options = self._options(
            sdk,
            system_prompt,
            env,
            mcp_servers={SERVER: server},
            allowed_tools=[f"mcp__{SERVER}__{name}" for name, _, _ in TOOLS],
        )
        client = sdk.ClaudeSDKClient(options=options)
        await client.connect()
        self._client = client

    async def close_session(self) -> None:
        client, self._client = self._client, None
        if client is not None:
            await client.disconnect()

    async def respond(self, prompt: str) -> AsyncIterator[str | ToolCall]:
        if self._client is None:
            raise BrainUnavailable("keine offene Sitzung")
        sdk = _import_sdk()
        await self._client.query(prompt)
        async for message in self._client.receive_response():
            if isinstance(message, sdk.AssistantMessage):
                if message.error:
                    raise BrainUnavailable(f"Claude: {message.error}")
                for block in message.content:
                    if isinstance(block, sdk.TextBlock):
                        yield block.text
                    elif isinstance(block, sdk.ToolUseBlock):
                        yield ToolCall(block.name.removeprefix(f"mcp__{SERVER}__"), dict(block.input))
            elif isinstance(message, sdk.ResultMessage) and message.is_error:
                raise BrainUnavailable(_result_error(message))

    async def summarize(self, prompt: str) -> str:
        env = sdk_env(self._brain, self._data_dir)
        sdk = _import_sdk()
        parts: list[str] = []
        async for message in sdk.query(prompt=prompt, options=self._options(sdk, SUMMARY_SYSTEM, env)):
            if isinstance(message, sdk.AssistantMessage):
                if message.error:
                    raise BrainUnavailable(f"Claude: {message.error}")
                parts.extend(block.text for block in message.content if isinstance(block, sdk.TextBlock))
            elif isinstance(message, sdk.ResultMessage) and message.is_error:
                raise BrainUnavailable(_result_error(message))
        return "".join(parts)

    def _options(self, sdk, system_prompt: str, env: dict[str, str], **extra):
        return sdk.ClaudeAgentOptions(
            model=MODEL,
            effort=EFFORT,
            system_prompt=system_prompt,
            tools=[],  # keine eingebauten Werkzeuge (Bash, Read, …) – nur Tonis eigene
            setting_sources=[],  # keine Projekt-/Nutzereinstellungen, kein CLAUDE.md
            env=env,
            cwd=str(self._data_dir),  # nie das Repo
            **extra,
        )


def _sdk_tools(sdk, tools: ToolHandler) -> list:
    def handler(name: str):
        async def run(args: dict) -> dict:
            result = await tools(ToolCall(name, dict(args)))
            return {"content": [{"type": "text", "text": result.text}], "is_error": result.is_error}

        return run

    return [sdk.tool(name, description, schema)(handler(name)) for name, description, schema in TOOLS]


def _result_error(message) -> str:
    detail = "; ".join(message.errors or []) or message.result or message.stop_reason or ""
    status = f" (HTTP {message.api_error_status})" if message.api_error_status else ""
    return f"Claude: {message.subtype}{status} {detail}".strip()


def _import_sdk():
    try:
        import claude_agent_sdk
    except ImportError as exc:
        raise BrainUnavailable("claude-agent-sdk nicht installiert (Extra `companion`)") from exc
    return claude_agent_sdk
