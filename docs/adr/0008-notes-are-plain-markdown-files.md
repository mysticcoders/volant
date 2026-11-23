# ADR 0008: Notes are plain Markdown files

- **Status:** Accepted
- **Date:** in force by 2026-09-13
- **Enforced by:** notes persistence tests (`NotesICloudSyncTests` and the notes store suites)

## Context

Notes could live in a database (fast search, structured metadata, easy sync) or as files. A database locks the owner's writing inside Volant; files can be read, backed up, synced and edited by anything.

## Decision

Each note is one plain `.md` file in the app container. Pinning and the last selection are local preferences, not note content. Failed writes stay dirty through reload and retry; Volant never reports Saved while a dirty write remains, and never saves empty fallback text over a file it could not read. iCloud sync, when the owner turns it on, moves notes by copying first and keeps the local folder as a dated backup.

## Consequences

- The owner's notes survive Volant: they are ordinary files that export, back up and import as-is.
- Search, pinning and metadata are built on top of the files rather than stored in them, so rich features cost more.
- Every storage path has to handle partial failure explicitly (unreadable files, failed directory reads, save failure on trash).
- See docs/notes-design-review.md, docs/notes-icloud.md and docs/search-note-recovery.md.
