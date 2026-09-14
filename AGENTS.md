# Project working notes

- Keep notes as plain Markdown files. Failed creates/updates must remain dirty through reload and support retry; never report Saved while any dirty write remains.
- Drain queued notes writes before trashing. Preserve dirty text on save or trash failure.
- Notes use native material and semantic styles. Keep the default surface focused on one note; browsing and secondary actions are on demand.
- Run persistence tests for storage changes. `NotesRenderTests` generates fictional light/dark view fixtures; inspect them, but do not count successful rendering as live keyboard, sheet, titlebar, or OS appearance verification.
- Current decisions, evidence and remaining work: [notes design review](docs/notes-design-review.md).

- Live Markdown must preserve UTF-16 source ranges, selection, undo and input-method composition. Language choices edit only the opening fence through NSTextView’s editing API; Auto must stay local and must not rewrite detected tags into source. Live and Preview share fence parsing.

- Agent pane identity and conversation identity are separate. Revalidate the current occupant before focusing or sending input; never submit prompts through a generic shell-input path. The local agent helper must keep an explicit narrow API.
- Native hosting views need a semantic window background for reliable light/dark rendering. Verify actual rendered controls, not just a successful build.

- ACP turns must own their native session IDs, invalidate stale snapshots, reject concurrent prompts, and cancel pending permission requests explicitly. Do not advertise client filesystem/terminal capabilities without implementing them. Run `./tools/check-acp.sh` after transport changes; its fake-agent checks do not replace a signed installed-provider smoke test.

- The agent XPC helper must join the caller’s security session for provider Keychain logins. A successful ACP handshake does not prove authentication: verify a minimal prompt through the signed installed app. Never copy provider OAuth tokens or weaken Keychain ACLs to bypass a session configuration bug.

- Launcher rows must activate by stable identity, never a cached array offset or `firstIndex(...) ?? 0`. Use native buttons for row actions. Before showing a non-activating panel, handle any app-modal window; test actual panel typing/clicks and repeated summon, not only a titled hosting window.
- Raycast import changes require `tools/check-raycast.sh`; keep personal exports/passwords out of fixtures, logs, and arguments. Preserve unknown fields inside existing config entries as well as at the top level. `tools/check-launcher.sh` and focused SwiftLint rules run from `Scripts/test.sh`; see `docs/launcher-quality.md` for what is and is not verified.
