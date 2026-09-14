# Native agent integrations

Scope requested: Herdr panes plus OpenCode, Cursor, Claude Code and Codex sessions inside Volant. Not yet implemented in the shipping app.

- Herdr: local socket API for discovery, state, focus and explicit prompts. Installed at ~/.local/bin/herdr; CLI exposes api schema, agent list/get/focus/prompt and pane operations.
- OpenCode: ACP over stdio. Installed at /opt/homebrew/bin/opencode; acp subcommand confirmed locally. Negotiate installed capabilities instead of assuming current website docs match this version.
- Cursor: ACP via agent acp. The agent executable was not found on PATH; detect its supported installation path and present setup instructions if absent.
- Claude Code: Agent SDK adapter for structured events and permissions; Herdr for existing terminal panes. Installed CLI found.
- Codex: native app-server protocol, confirmed by installed CLI help; threads, turns and approval events. Do not equate saved thread discovery with attaching to arbitrary running desktop conversations.

Sources: https://herdr.dev/docs/socket-api/ ; https://opencode.ai/v2/docs/cli/acp/ ; https://cursor.com/docs/cli/acp ; https://code.claude.com/docs/en/agent-sdk/overview ; https://learn.chatgpt.com/docs/app-server

Next implementation slice:
1. Prove sandbox-to-local-harness connectivity in an isolated spike. Volant and its extension XPC service are sandboxed; neither automatically grants a spawned agent project or network access. Evaluate an optional local companion with scoped IPC.
2. Normalize provider/session/project identity and capabilities; keep pane identity separate from conversation identity.
3. Add native Agents results: attention states, status, selected-session detail and focus. Expose unsupported/unknown states honestly.
4. Add explicit note/snippet context preview and prompt submission; never send clipboard history implicitly. Keep terminal approval dialogs in their owning pane until structured permission handling is supported.
5. Implement ACP streaming, cancellation, permissions, Cursor blocking extensions, then Claude SDK and Codex app-server adapters behind the same interface.

Validation: no agent tasks or user-pane mutations performed during initial discovery. Use fictional project fixtures for protocol and permission tests. Include disconnect, stale session, duplicate submission prevention and cancellation behavior.
