# ADR-0011: Begleiter – Claude über Abo-OAuth, Stimme über OpenRouter, Erkennung lokal

- **Status:** akzeptiert
- **Datum:** 2026-10-28

## Kontext

Der Begleiter Toni (Spec #76) soll während der Fahrt zuhören, denken und mit Stimme antworten – mit einer Antwort
nach höchstens etwa 2,5 s. Er braucht drei Dienste: ein Sprachmodell, eine Stimme und eine Spracherkennung. Der
Nutzer hat ein privates Claude-Max-Abo und einen OpenRouter-Schlüssel; der PC hat eine RTX 4070. Weitere Konten
sollen nicht nötig sein, und die Stimme des Fahrers soll den PC nicht verlassen.

## Entscheidung

- **Denken:** Claude Haiku 5.5 (`claude-haiku-5-5`) über das Claude Agent SDK – `ClaudeSDKClient` mit einer Sitzung
  je Fahrt, eingebaute Werkzeuge aus, keine Projekt- oder Nutzereinstellungen laden, eigene Werkzeuge über einen
  In-Process-MCP-Server, `effort: low` für die Latenz.
- **Anmeldung:** standardmäßig über `CLAUDE_CODE_OAUTH_TOKEN` aus `claude setup-token` (Max-Abo des Nutzers).
  Weiche `brain = oauth | api_key` in `companion.json`, Standard `oauth`. **Kein stilles Ausweichen** auf den
  API-Schlüssel: scheitert OAuth (abgelaufen, Abo-Limit), wird Toni heiser; der API-Schlüssel gilt nur per
  Einstellung. Die Abo-Limits teilt sich Toni mit Claude Code.
- **Stimme:** OpenRouter `/api/v1/audio/speech`, Modell `elevenlabs/eleven-v4-turbo`, Stimme `charlie`, Format
  `mp3`, Schlüssel `OPENROUTER_API_KEY`. Nur Tonis Text verlässt den PC, nie die Stimme des Fahrers. ElevenLabs
  bietet Zero Retention nur für Enterprise; `provider.zdr` würde die Anfrage ablehnen und wird deshalb nicht gesetzt.
- **Erkennung:** faster-whisper `large-v3-turbo` lokal auf der GPU (CUDA, `int8_float16`), `language="de"`,
  VAD-Filter; ohne CUDA `small` auf der CPU. Modell und Pakete werden nur nach Zustimmung des Nutzers geladen.
- Jeder Fehler eines dieser Dienste macht Toni **heiser** (`companion_status: hoarse`); die Fahrt läuft weiter.

## Nutzungsbedingungen

- **Entscheidung des Nutzers am 28.10.2026:** Abo-OAuth ist der Standard. Seine Begründung wörtlich: „das ist
  mittlerweile wieder erlaubt für eigene Apps von Anthropic“.
- **Stand der Prüfung am 28.10.2026 – drei Primärquellen sagen etwas anderes:**
  - code.claude.com/docs/en/legal-and-compliance, Abschnitt „Authentication and credential use“: OAuth ist nur für
    Abo-Kunden gedacht, für „ordinary use of Claude Code and other native Anthropic applications“; Entwickler, die
    Produkte bauen, auch mit dem Agent SDK, sollen API-Schlüssel verwenden.
  - code.claude.com/docs/en/agent-sdk/overview: Ohne vorherige Freigabe erlaubt Anthropic Drittentwicklern keinen
    claude.ai-Login und keine Abo-Rate-Limits für ihre Produkte, auch nicht für Agenten auf Basis des Agent SDK.
  - Consumer Terms (gültig ab 08.10.2025), Abschnitt 3 Punkt 7: kein automatisierter Zugriff per Bot oder Skript
    außer über einen Anthropic-API-Schlüssel oder mit ausdrücklicher Erlaubnis.
- **Gegenstimme, ebenfalls Primärquelle:** support.claude.com, Artikel 15036540 „Use the Claude Agent SDK with your
  Claude plan“. Hinweis vom 07.10.2026: Wer mit seinem Claude-Plan angemeldet ist, dessen Agent-SDK- und
  `claude -p`-Nutzung zählt gegen die Abo-Limits; die Monatsguthaben von Max gelten nur für Nutzung mit einem
  API-Schlüssel aus einer verknüpften Console-Organisation. Hinweis vom 15.06.2026: Die angekündigten Änderungen an
  der Agent-SDK-Nutzung sind pausiert; Agent SDK, `claude -p` und Drittanbieter-Apps zählen weiter gegen die
  Abo-Limits.
- **Ergebnis:** Eine Quelle, die eigene Apps per Abo-OAuth **ausdrücklich erlaubt**, wurde nicht gefunden –
  nicht belegt, Entscheidung des Nutzers. Er trägt das Risiko; die Weiche auf den API-Schlüssel bleibt deshalb Pflicht.

## Begründung

- Das eigene Abo braucht kein weiteres Konto und keine weiteren Kosten fürs Denken; Haiku ist schnell genug für
  ein Gespräch, eine warme Sitzung je Fahrt spart Anlaufzeit.
- OpenRouter nutzt den vorhandenen Schlüssel. Hörprobe am 28.10.2026: eleven-v4-turbo/charlie kostete 0,003840 $
  für 96 Zeichen (≈ 0,28–0,68 $ je Fahrstunde), erstes Byte nach 1,04 s (eine Messung) – Gewinner von zehn Stimmen.
- Lokale Erkennung hält die Stimme des Fahrers auf dem PC; `large-v3-turbo` passt mit etwa 1,5 GB VRAM neben das
  Spiel.

## Konsequenzen

- Ohne Netz, bei abgelaufenem OAuth oder erreichtem Abo-Limit ist Toni heiser – es gibt keinen lokalen Ersatz.
- Die echten Adapter werden nicht automatisch getestet (kein Test ruft Claude, OpenRouter, Mikrofon oder GPU); der
  Nutzer prüft sie von Hand. Die Logik läuft gegen Fakes der Ports `Brain`, `Ears`, `Mouth`, `Clock`.
- Je Fahrt kommen Sprachkosten und Antwortzeiten ins Protokoll des Begleiters (ADR-0008, Nachtrag #76).
- Ändert Anthropic die Bedingungen oder die Abrechnung, ist nur die Weiche `brain` umzustellen.

## Verworfen

- **Lokale Stimme** (Piper, Windows-Stimmen) als Ersatz: ohne Netz schweigt Toni (Spec #76, Out of Scope).
- **Wake-Word oder Dauer-Mithören:** das Mikrofon hört nur, solange die Sprechtaste gedrückt ist.
- **API-Schlüssel als Standard:** vom Nutzer verworfen; bleibt als Reserve über `brain = api_key`.
