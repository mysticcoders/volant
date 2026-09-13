# Project working notes

- Keep notes as plain Markdown files. Failed creates/updates must remain dirty through reload and support retry; never report Saved while any dirty write remains.
- Drain queued notes writes before trashing. Preserve dirty text on save or trash failure.
- Notes use native material and semantic styles. Keep the default surface focused on one note; browsing and secondary actions are on demand.
- Run persistence tests for storage changes. `NotesRenderTests` generates fictional light/dark view fixtures; inspect them, but do not count successful rendering as live keyboard, sheet, titlebar, or OS appearance verification.
- Current decisions, evidence and remaining work: [notes design review](docs/notes-design-review.md).

- Live Markdown must preserve UTF-16 source ranges, selection, undo and input-method composition. Language choices edit only the opening fence through NSTextView’s editing API; Auto must stay local and must not rewrite detected tags into source. Live and Preview share fence parsing.
