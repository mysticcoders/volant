# AI connections: ACP, BYOK and local models

## Behavior

Settings → AI offers ACP, BYOK and Local Models. Existing configuration migrates to ACP without changing its provider or project. Settings changes apply to the next conversation; an active chat and its draft retain their connection. AI Chat still uses Return to send, Shift-Return for a newline, the existing Markdown renderer, explicit cancellation and full-panel conversation UI.

ACP retains the existing CLI login, optional working folder and agent permission flow. BYOK supports OpenAI Responses streaming, Anthropic Messages streaming and custom OpenAI-compatible Chat Completions endpoints. Local connections use the compatible protocol on loopback. API chat is text-only; it does not inherit ACP's terminal/filesystem tools. The configured server receives the current prompt and previously completed turns. OpenAI requests use `store: false`; this is not a claim about every provider's retention policy.

API keys are stored in device-local Keychain generic-password entries keyed by provider and endpoint, never in config JSON or backups. Save Key and Remove Key report failures without replacing a working key on an update failure. Key bytes pass only to the selected helper connection/request. Custom endpoints require HTTPS, except explicit loopback HTTP. Redirects are refused, preventing keys/prompts from following redirects to another origin. No provider error bodies or source/response text are logged by Volant.

The separate `VolantAIHost` XPC service has App Sandbox plus outbound networking. The main app and WASM helper gain no network entitlement. Sessions are ephemeral, with no cookies, URL cache, background downloads or credential storage. Ending the connection cancels in-flight work. API snapshots stop polling once the conversation is ready; typing and launcher startup do not start network requests.

## Local detection

Opening Local Models in Settings probes the OpenAI-compatible model-list endpoints on loopback ports 11434 (Ollama convention), 1234 (LM Studio convention), and 8000 (generic local API). These are candidate server locations, not proof of a particular installed application. The list comes from the server; it does not mean every returned model is currently loaded or supports chat. Volant does not scan model files, launch services, download models, or start inference during detection. Custom loopback ports/base paths and optional local authentication are supported through manual fields and Test Connection.

Use selects a discovered server and model. Test Connection lists models on the selected endpoint; it verifies discovery/authentication, not a successful inference request. Unavailable, no-model and key-required servers remain explicit. Closing Settings, switching connection type, editing an endpoint or rescanning rejects late discovery responses. Detection does not enable or select a connection automatically.

## Resource and failure bounds

One turn at a time, at most 100 visible messages, 64 KiB per new prompt, 256 KiB transcript/history budget, 2 MiB stream wire budget, 64 KiB SSE line/event limit and a 180-second resource timeout. Model lists are capped at 1 MiB/1,000 entries. Stop cancels the turn and invalidates its generation; partial failed/cancelled responses stay visible but are excluded from future request history. Truncated streams are reported, never treated as complete. No automatic prompt retries or cloud fallback from Local Models.

## Verification and limitations

`AIHTTPTests` covers endpoint/credential isolation, provider request shapes, SSE completion/Unicode/error bounds, migration and stale discovery. `tools/check-ai-http.sh` runs the production transport/conversation against a fictional loopback server: model listing, streaming, concurrent rejection, cancellation, stale chunks, redirects, truncation and generic authentication errors. It runs through `Scripts/test.sh` in native CI. ACP regression checks remain required.

`tools/check-ai-xpc.sh` separately exercises the exported Developer ID helper through the production chat model and Settings discovery against that loopback fixture. It requires `VOLANT_AI_APP` and signing credentials, does not launch owner UI, and is not live provider authentication or inference evidence. Native Tart fixtures cover the affected Settings modes, local available/unavailable states, and chat in light/dark appearances without real credentials or servers.

Before claiming installed provider readiness, verify Keychain save/read/remove and a minimal user-authorized prompt through the signed installed app for each cloud provider and an actual local server. No live account, purchased API request, model download or installed-app restart is implied by fixture success. API key availability, model access, provider-specific context limits, reasoning/tool output, attachments and full compatible-server parity remain separate checks/features. Anthropic model pagination and richer local model state are follow-ups; manual model IDs are supported.

## Sources

- [OpenAI streaming](https://developers.openai.com/api/docs/guides/streaming-responses)
- [Anthropic streaming](https://platform.claude.com/docs/en/build-with-claude/streaming)
- [LM Studio model listing](https://lmstudio.ai/docs/developer/openai-compat/models)
- [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)

## Quality decision

Keep the API transport separate from ACP so provider tools and CLI credentials cannot leak into BYOK/local requests. Preserve connection ownership across Settings edits, use explicit cancellation and validate the final streamed completion marker. Fake discovery/credentials are injectable in native fixtures; opening a preview must not contact owner servers or Keychain. Build, rendered UI, real HTTP, signed XPC and live provider evidence are distinct.
