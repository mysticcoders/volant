# Native agent integrations

Scope requested: Herdr panes plus OpenCode, Cursor, Claude Code and Codex sessions inside Volant. First development slice implemented: native Herdr session discovery and pane focus. ACP/provider conversations are not implemented.

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

## First slice delivered

Open Agents from the Volant menu or type `agents` / `herdr` in the launcher. Connect Herdr explicitly. Search project/provider/status, refresh, disconnect, and focus an agent pane. Closing the panel disconnects and stops polling. This version targets only the default local Herdr session.

The main app stays sandboxed. VolantAgentHost is a separately signed, intentionally unsandboxed embedded XPC service with a narrow list/focus interface. It authenticates the calling app against the Volant bundle identifier and team. It executes the installed Herdr CLI by absolute path without a shell or inherited pane context. It cannot receive arbitrary commands, prompts, filenames, or clipboard content through its interface. Herdr output is bounded and command execution has an eight-second termination timeout.

Focus re-reads live state and checks pane ID, terminal ID, provider and native session identity when available. If Herdr supplies no native session ID, identity falls back to provider plus terminal ID: a same-provider restart inside the same terminal cannot be distinguished reliably. Do not claim stronger identity guarantees. Focus changes selection in Herdr; automatic activation of the owning terminal application is not implemented.

Validation: signed Release app-to-XPC discovery succeeded (29 live sessions), and focus succeeded against this task's own Herdr pane. Isolated model checks passed for attention-first sorting, unknown status, identity and malformed payloads. Fictional native panel renders inspected in light and dark. Website desktop (1440) and mobile (390) renders inspected. Complete live keyboard navigation, alternate sessions/machines, enlarged accessibility text, and every error state remain unverified.

Next: ACP transport initialization and capability negotiation for OpenCode/Cursor; then session prompts, streaming, cancellation and explicit approvals. Follow with Claude SDK and Codex app-server adapters. Do not market these as shipped before end-to-end verification.

Rendering lesson: a transparent NSHostingView captured white behind dark controls. An explicit semantic windowBackgroundColor now covers the panel; both appearances were inspected after the fix. Use a compiled SwiftUI fixture renderer with a short run-loop layout pass, since the interpreter failed to link SwiftUI in this environment. No automated visual gate exists yet.
