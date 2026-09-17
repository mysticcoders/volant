# Herdr attention previews

A pinned Herdr status with waiting agents shows one passive terminal excerpt below the status strip. Previous/next controls select another waiting agent without depending on a cached row index. The selected pane's last 30 detection lines are refreshed with the existing five-second agent polling; hidden launchers disconnect Herdr and release the excerpt. Display text is bounded to 4,000 characters, literal, selectable, and never persisted or logged. Empty output and failed reads offer a pane handoff instead of an invented question.

The helper exposes only a narrow attention-read method. It validates pane ID, terminal ID, provider/session identity and blocked state before and after `herdr agent read --source detection --lines 30 --format text`. Detection reads are passive: no scrollback capture, input, or viewport movement. The UI rejects stale replies after target changes, disappearance, resolution or disconnect. A target change cannot display the old excerpt under the new identity, even before the next view task runs.

Open in Herdr uses the existing revalidated pane-focus method; it selects the pane but the user must switch to their Herdr terminal. It does not approve or deny anything. Herdr 0.9.0 / protocol 22 has agent key delivery but no structured permission response with an expected request/screen revision. Direct approval buttons and their keyboard shortcuts are deferred until we can bind delivery to the request shown. The provider's exact scope must be preserved (once/session/rule); do not guess an Always mapping or interpret terminal text as executable instructions.

Automated checks: native unit tests cover identity, bounded literal text and delayed callbacks; branded headless UI fixtures cover loading, multiple waiting agents, changed targets, errors and resolution in both appearances at three sizes. Release signature and installed helper access are separate evidence. No owner terminal content is used in fixtures.

Next steps: obtain a conditional response contract (expected terminal/session plus prompt revision or request ID), then add independently verified Claude Code and Codex response adapters and scoped card shortcuts. Until then, use preview plus pane handoff. Persistent question history is out of scope.

References: https://herdr.dev/docs/agent-automation/ and https://herdr.dev/docs/socket-api/ (checked 2026-09-16).
