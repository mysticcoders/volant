# Project working notes

- Keep notes as plain Markdown files. Failed creates/updates must remain dirty through reload and support retry; never report Saved while any dirty write remains.
- Drain queued notes writes before trashing. Preserve dirty text on save or trash failure.
- Notes use native material and semantic styles. Keep the default surface focused on one note; browsing and secondary actions are on demand.
- Run persistence tests for storage changes. `NotesRenderTests` generates fictional light/dark view fixtures; inspect them, but do not count successful rendering as live keyboard, sheet, titlebar, or OS appearance verification.
- Current decisions, evidence and remaining work: [notes design review](docs/notes-design-review.md).

- Live Markdown must preserve UTF-16 source ranges, selection, undo and input-method composition. Language choices edit only the opening fence through NSTextView’s editing API; Auto must stay local and must not rewrite detected tags into source. Live and Preview share fence parsing.

- Agent pane identity and conversation identity are separate. Revalidate the current occupant before focusing or sending input; never submit prompts through a generic shell-input path. The local agent helper must keep an explicit narrow API.
- Native hosting views need a semantic window background for reliable light/dark rendering. Verify actual rendered controls, not just a successful build.
