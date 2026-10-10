# Notes memory profile — October 9, 2026

Issue #17 asked for notes to load lazily and for unchanged files to be reused. Before this change `NotesStore` kept the full text of every note in memory and read every file again on each reload: opening the notes panel, Retry Loading Notes, and every configuration change. Everything below was measured with the opt-in fixture in `tools/memory` and generated fictional notes. No owner notes were read.

## What changed

- **Listed notes keep metadata only:** id, URL, modification date, a disk stamp (modification date and byte size), the title (at most 80 characters) and the preview (the second non-empty line, now capped at 200 characters; rows show one line). The title and preview are computed once from the first two non-empty lines, by the same rules as before.
- **Full text is resident only where needed:** the note open in the notes panel, and any note with an unsaved or failed write. Selecting another note releases the previous clean note's text. A note whose save succeeds while another note is open releases its text too.
- **Reload reuses unchanged files:** a clean, readable note whose modification date and size match its last read is kept without opening the file. Changed files, new files and unreadable notes are read again, so Retry Loading Notes still repairs an unreadable note. The stamp is taken before the read, so a write during the read is picked up on the next reload rather than masked.
- **Search reads files one at a time:** resident text is searched in memory. Every other note is read from disk, checked with the same `localizedCaseInsensitiveContains` and released before the next file. Search stops once it has `limit` matches; the matching set and order are unchanged. For the current term, the result for each file is remembered while its stamp is unchanged, so the browse overlay re-rendering one query does not reread the notebook. The memory is per-note booleans, not text.
- **Chat context:** the AI Chat @ picker reads a note's text only for the at most eight notes it offers.

Persistence rules are unchanged: dirty text always wins over disk and survives reload and folder failure; failed creates and updates stay dirty and retry; writes drain before trashing; unreadable notes keep their id, pin and bytes, show the read-only placeholder, and are never written. A note that becomes unreadable between reload and opening now shows that placeholder instead of an editor.

## Method

`VOLANT_MEMORY_SCENARIOS="notes notes-small" tools/profile-memory.sh OUTPUT` built the optimized fixture from the sources at `777deff` (before) and from this branch (after), with the same `tools/memory/main.swift`. Each workload ran in three fresh processes; the tables show the median. Host: Apple silicon Mac16,6, macOS 27.0.1 (26A434), Swift 6.4.

- **notes:** 1,000 notes of about 64 KB (about 61 MiB), loaded, then reloaded three times with an 8-result search each time, then three identical searches for a phrase no note contains (`limit: Int.max`, so every file is examined), then released.
- **notes-small:** the same phases with 300 notes of about 4 KB (about 1.2 MiB), closer to the 200-note VM profile.

The fixture creates a `NotesStore` without a notes panel, so no note is open; with the panel open, one more note's text is resident. Footprint, live heap and sampled peak are separate measures and are not additive.

## Results

1,000 notes, about 61 MiB, MiB:

| Phase | Before footprint | Before live heap | After footprint | After live heap |
| --- | ---: | ---: | ---: | ---: |
| loaded | 84.36 | 79.00 | 6.25 | 1.00 |
| after reload 1 | 163.83 | 79.05 | 7.44 | 1.05 |
| after reload 3 | 183.03 (166.5–201.6 across runs) | 79.06 | 7.45 | 1.05 |
| after 3 absent-phrase searches (sampled peak) | 183.03 | 79.06 | 7.50 | 1.14 |
| store released | 183.03 | 0.30 | 7.52 | 0.28 |

300 notes, about 1.2 MiB, MiB:

| Phase | Before footprint | Before live heap | After footprint | After live heap |
| --- | ---: | ---: | ---: | ---: |
| loaded | 5.59 | 1.89 | 4.22 | 0.47 |
| after reload 3 | 7.77 | 1.94 | 4.80 | 0.52 |
| after 3 absent-phrase searches (sampled peak) | 7.77 | 1.94 | 4.84 | 0.54 |

Timing, median ms (throughput in the fixture, not interactive latency):

| Phase | 1,000 notes before | after | 300 notes before | after |
| --- | ---: | ---: | ---: | ---: |
| first load | 33.16 | 27.47 | 6.50 | 7.60 |
| reload 3 (with search) | 28.16 | 6.83 | 5.70 | 1.91 |
| 3 absent-phrase searches | 614.75 | 222.86 | 12.05 | 8.72 |

The before build's footprint grew with every reload although its live heap stayed at 79 MiB: each reload allocated a fresh 61 MiB of text before the old copy was freed. The after build's footprint stays flat because unchanged files are not read. A full-notebook search still decodes every non-resident file once: the before build spent about 205 ms per in-memory scan of 61 MiB, and the after build's three searches took 223 ms in total, almost all of it the first scan; the second and third used the remembered per-file results. Peak footprint during that scan stayed at 7.50 MiB, so one file at a time is resident.

## Verified and not verified

- **Verified:** the fixture numbers above. Hosted tests in `NotesStoreTests` cover metadata-only listing, one resident note, reuse of an unchanged file (made unreadable without changing its date or size, then reloaded without error), rereading changed files including a same-size edit with a new date, search parity with a full-text reference across resident, dirty, unreadable and on-disk notes, release after save, the placeholder for a file that became unreadable before opening, and title/preview parity with the old rules. The existing persistence and recovery tests pass unchanged.
- **Not verified:**
  - The installed, signed app, and the VM app profile (`tools/memory/app-vm.py`); this is a model-only measurement.
  - Interactive search latency with a large notebook. A query that matches few notes reads every file once per distinct term on the main thread, as the in-memory scan did; the remembered results only help repeated renders of the same term.
  - An external edit that keeps both the modification date and the size is not detected until one of them changes. APFS records nanosecond modification dates, so this needs a tool that restores the date.
  - Notes panel rendering and keyboard behavior; the view changes are limited to reading the loaded text, and `NotesRenderTests` is the UI fixture for them.
