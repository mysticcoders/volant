# Slingshot assessment — September 12, 2026

The architecture fits the product: a small, native, local macOS utility whose security comes largely from limiting its capabilities. Keep that direction. The implementation is an early personal-use prototype, with reproducible data-loss bugs and incomplete release assurance. Harden storage and validation before adding more features.

This is an assessment, not a remediation release. Application source was not edited. Another agent added notes during this review; the final reviewed snapshot includes them. Source hashes and test evidence are in `assessment-2026-09-12/`. There were no Git commits at review time, and all application files were untracked.

## Product and prior decisions

Read the relevant Claude conversation under `~/.claude/projects/-Users-kinabalu-Obsidian-Brain/543a9446-2dc0-484d-9f06-d0652d82a64e.jsonl`, including the user's decisions. There is no repository-local `.claude` folder. The discussion prioritizes security, auditability, low overhead, per-app hotkeys, and quick notes with clean copying of rendered code/URLs. Cost was not the driver. Window management and window/menu-bar search were rejected; currency, AI and extensions were deferred. Statements made by the other agent are context, not independent verification.

The final snapshot contains 2,088 lines of application Swift and 23 existing unit tests. It uses AppKit/SwiftUI, Carbon hotkeys, Spotlight metadata, Contacts, EventKit, CryptoKit, Keychain and SQLite, without third-party runtime packages.

| Capability | Implementation |
| --- | --- |
| Launcher | Floating keyboard panel, fuzzy app matching, per-app launch/activate/hide hotkeys |
| Answers | Arithmetic parser and offline unit conversion; Return copies |
| Files | Debounced filename search through Spotlight; open/reveal actions |
| People | Contact name lookup and copy actions; today/tomorrow calendar and meeting links |
| Clipboard | Poll every 0.5 seconds; text filtering; encrypted SQLite history; default 500 entries |
| Notes | Multiple plaintext Markdown files, floating editor/preview, code/URL copy, launcher search/create |
| Suggestions | Last-used metadata plus 12 locally launched paths; no actual learned query/frequency model |
| Absent | Aliases, chosen notes folder, currency, AI, extension runtime, settings UI, updater |

The right next product additions remain learned suggestions and aliases. Notes now exist but need storage corrections. Avoid building an extension platform until a specific useful extension justifies its cost. WASM plus XPC is a design direction, not by itself proof of isolation: host imports, IPC validation, signing, resource limits and updates would all need their own review.

## Findings, in priority order

### 1. High — rapid note creation overwrites existing files

`Slingshot/Notes/NotesStore.swift:49` creates filenames using a timestamp with second precision. Two notes created in one second share a path, and atomic writing replaces the earlier file. The in-memory array then contains duplicate identities. A fictional-fixture regression created ten notes and produced only two unique files.

Use a UUID-backed identifier/filename and collision-safe creation. Keep a regression for multiple creations within the same second. This is a confirmed data-loss defect.

### 2. High — note saving lacks a coherent lifecycle

`NotesStore.swift:35` reloads disk contents without reconciling pending edits; `:58` schedules writes on a concurrent global queue; `:69` manually performs queued work. A regression confirmed that update followed immediately by reload replaces the new in-memory text with the old disk text. Subsequent editing can overwrite the newer content. Both notes-panel opening and launcher note searches call reload.

There is also no notes flush in `Slingshot/App/AppDelegate.swift:42` on app termination, and no ordinary close-button override in `NotesPanel`; rapid quit can lose the last debounced edit. Cancellation does not serialize a write already in progress. Errors from writing and moving to Trash are swallowed, even though the UI updates as if successful.

Use one serial persistence owner with versioned writes, explicit dirty state, ordered reload/flush/delete operations, error reporting and shutdown flushing. Test rapid edit/reload/quit and write failures. The reload defect is reproduced; the concurrent-write and shutdown failure paths are source-level findings, not timed stress-test results.

### 3. High — old or malformed configuration is silently replaced

`Slingshot/Settings/Preferences.swift:26` writes defaults after any decoding failure. Synthesized Codable does not use the declared property defaults for missing keys. A config from before `notesHotKey` was added now fails decoding; this was reproduced without touching the user's config. Loading it will attempt to overwrite customized hotkeys and retention settings.

Decode optional fields with defaults, version/migrate the schema, preserve invalid files, and display an actionable error. Only create a default file when none exists. Also fix Reload Config: it does not apply new clipboard retention to the existing store and unnecessarily registers app hotkeys before unregistering them.

### 4. High for distribution — the inspected artifact does not match the release claims

The existing `build-release/Build/Products/Release/Slingshot.app` passes strict code-signature verification, but is signed with **Apple Development**, has `com.apple.security.get-task-allow = true`, and has **no stapled ticket**. App Sandbox, Contacts and Calendar entitlements are present; networking entitlements are absent. The README describes Developer ID signing, notarization and stapling as accomplished properties. A release script that can do these steps is not evidence they were completed on this artifact.

Do not distribute this development artifact as the claimed release. Build the intended Developer ID archive, assert its exact entitlements (including absence of debugger access), notarize/staple, and smoke-test the actual ZIP after extraction. No release was signed, submitted or published during this assessment. Absence of a staple alone does not establish whether a binary was ever notarized.

Initial sandboxed signing-tool output was misleading; the findings above use successful verification outside the tool sandbox.

### 5. High for delivery reliability — scripts hide failed builds/tests

`Scripts/build.sh:7`, `Scripts/test.sh:7` and the archive pipeline in `Scripts/release.sh` pipe `xcodebuild` into output filters under `/bin/sh` with `set -eu`, without failure propagation for the pipeline. Mocking `xcodebuild` to exit 42 made both build.sh and test.sh exit **0**; build.sh even printed “built”. Later release verification can catch some archive failures, but the archive command itself is not reliably checked.

Use a shell with explicit `pipefail`, or capture and check the build exit status before filtering logs. Add a failure-injection check and run real tests in CI. No CI workflow is present in this snapshot.

### 6. Medium — plaintext hashes weaken clipboard confidentiality

`Slingshot/Clipboard/ClipboardStore.swift:36` stores an unkeyed SHA-256 of every plaintext alongside encrypted content. Someone who obtains the database can test guesses for low-entropy values without obtaining the AES key. Encryption of the blob does not hide the plaintext fingerprint; timestamps are plaintext too.

Use a keyed HMAC with an appropriately separated key for deduplication, or avoid persistent plaintext-derived fingerprints. Keep AES-GCM and fresh nonces. This is an offline disclosure risk after database access, not evidence of a remote exploit.

### 7. Medium — clipboard privacy controls are incomplete

Monitoring starts automatically, with no pause/disable control or source-app exclusion. Sensitive pasteboard markers are respected, which is good, but secrets copied from terminals/editors may have no markers. Store delete/clear APIs exist but have no user-facing actions. The retention count is lower-bounded at 10, has no maximum or age limit, and cannot disable collection. The monitor also trims whitespace, so copying history is not an exact round trip for code or indented text.

Expose pause, delete, clear and age/count/byte retention controls; preserve text exactly; document marker limitations. Use byte limits as well as character limits: Swift character count measures grapheme clusters and is not a storage bound. Keychain/SQLite failures currently look like an empty history; surface errors and offer retry rather than silently disabling history until restart. The key is retained in process memory, so Keychain accessibility should not be described as automatic purging on screen lock.

### 8. Medium — meeting links can misrepresent destinations

`Slingshot/People/CalendarAgenda.swift:50` checks `host.hasSuffix("zoom.us")`, which also matches a hostname such as `notzoom.us`; schemes are not checked. `:47` falls back to any detected URL, yet the launcher labels every non-nil URL “Join Meeting”. External calendar invitations can supply these strings. Return delegates opening to another app.

Match exact hosts or dot-delimited subdomains, normalize case, allow supported schemes explicitly, and distinguish “Open Link” from “Join Meeting” while exposing the destination. Do not automatically treat the first URL in notes as a meeting. Test malformed, misleading and non-web URLs. This requires user activation and is not demonstrated automatic code execution.

### 9. Medium — “read-only permissions” and absolute offline claims overstate guarantees

The code reads contacts/events and does not write them. The Calendar API nevertheless requests full access, which Apple documents as read **and write** access. Describe this as read-only application behavior, not an OS-enforced read-only grant. [Apple EventKit documentation](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)).

There is no direct networking implementation or network entitlement in the reviewed app. However, meeting links and Markdown links can open other applications, which may access the network. Prefer “No direct network requests or telemetry; opening links uses your other apps” to an unconditional “nothing leaves the machine.” [Apple NSWorkspace documentation](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)).

### 10. Medium — avoidable work sits on the UI thread

* Clipboard search uses `queue.sync` from query refresh, decrypting/searching up to 200 recent rows per query. It can also wait behind writes and trimming. There is no `copied_at` index. Searches cannot reach older retained entries beyond that 200-row window, despite the default retention of 500.
* Notes search calls `notes.reload()` on every keystroke after the note prefix, synchronously loading every Markdown file. All note bodies remain resident with no aggregate size bound. Title/preview calculations repeatedly split whole notes. `MarkdownBlocks.parse` builds code arrays using `current + [raw]`, causing repeated copying for long fenced blocks; Markdown rendering uses an eager VStack.
* Calendar retrieval and link detection run on the main thread. Contacts launches a new background lookup per eligible edit without debounce or cancellation; generation checks prevent stale UI delivery but do not stop the old work.
* AppIndex watches local-computer metadata, then rescans/sorts all results on each update. File queries debounce, but return only after gathering completes. Synchronous icon lookup occurs during row rendering.

Move persistence/search to bounded background work; cache small metadata/previews and icons; publish results on the main actor; add cancellation and incremental reloads. Index clipboard ordering, and search retained history asynchronously without persisting a plaintext full-text index. Optimize fuzzy matching only after measurements: typical application lists are small, so it is a lower priority.

### 11. Medium — Markdown identities are unstable or duplicate

`Slingshot/Notes/MarkdownBlocks.swift:14` generates a fresh UUID whenever a rule ID is read. Equal paragraph contents have equal IDs, so a note with repeated paragraphs has duplicate identifiers in ForEach. Both properties were reproduced. Give parsed block occurrences stable identities, such as a document revision plus occurrence index, rather than a content hash or computed random ID. Rendered impact has not been visually verified.

### 12. Lower-priority correctness and maintainability gaps

* Suggestions assign every locally recorded app a synthetic timestamp near “now” forever. Old local choices can outrank apps used recently elsewhere; actual frequency and query-to-choice learning are absent.
* Fuzzy matching lowercases candidates before testing camel-case word boundaries, so that boundary branch cannot work.
* Async section insertion preserves a numeric selection index rather than the selected row's identity; a contact result arriving above selected files can change what Return opens.
* App-index updates are not observed by LauncherModel, so a panel opened before indexing completes can remain empty until another refresh.
* `clip` matches any word with that prefix, potentially swallowing app searches. Contacts denial has no dedicated explanation. Calendar end-of-tomorrow uses 48 hours rather than calendar-day arithmetic, which is incorrect across daylight-saving transitions.
* `SWIFT_STRICT_CONCURRENCY` is minimal. Explicit main-actor UI ownership and strict concurrency checking would help make the persistence boundaries enforceable.
* `build-release/` is not ignored, and there is no initial Git commit. Establish a reviewed baseline and exclude generated artifacts before starting remediation.

## Memory and efficiency verdict

The native architecture is a sensible basis for a small footprint. There is no bundled browser, JS runtime or model. This does not prove a specific resident-memory number. No matching running Slingshot process was found during the filtered process check, and the production app was not launched to collect or mutate real clipboard/notes data. The previous agent's “17 MB” statement is not a newly verified measurement and may predate notes.

The main growth risk is retained note text and repeated parsing/loading, not the bounded app list. Clipboard disk usage is count-bounded only: 500 ASCII entries of 100,000 characters is approximately **50 MB of plaintext payload**, before encryption and SQLite overhead. That is a storage example, not app RSS; Unicode can be much larger. A no-match clipboard search may decrypt roughly 20 MB of ASCII payload cumulatively across 200 such rows, without retaining all of it simultaneously.

Measure a signed Release build with fictional fixtures: cold launch, hidden idle, warm summon, rapid typing, 500/5,000 apps, 500 clipboard entries, and 10/1,000 notes including a large code block. Record physical footprint/RSS separately, CPU/wakeups, and p50/p95 query-to-render latency; repeat open/close cycles and inspect allocations for growth. Compare competitors only under equivalent workloads. Suggested targets to choose, not measured results: warm summon under 100 ms and no synchronous input stall over one display frame during ordinary typing.

## Evidence and limitations

* **Passed:** unsigned Release configuration build for both arm64 and x86_64 from the final snapshot.
* **Passed:** all 23 existing XCTest cases in a temporary Swift Package harness using the unchanged relevant sources. This avoids launching the production app/test host. It is not an end-to-end Xcode-hosted test run.
* **Confirmed failures:** four added assessment tests fail on six assertions: note filename collision, reload losing dirty state, previous config decoding, and Markdown identity stability/uniqueness. Their source and logs are preserved separately, not added to the project's test target.
* **Confirmed:** injected build failures are reported as success by both scripts.
* **Confirmed on existing artifact:** valid signature, development identity, debugger entitlement, sandbox present, no network entitlement, no stapled ticket.
* **Not verified:** actual app RSS/leaks/latency, real sandbox file-search coverage, hotkey/permission integration, signed distribution archive, Intel runtime behavior, or rendered light/dark/accessibility/keyboard quality. No UI was changed or declared ready by this assessment. Existing tests of Markdown parsing do not prove native copy/selection behavior.

## Next-step backlog and recurring prevention

1. Fix note filenames and save lifecycle, then non-destructive config migration. Land the reproduced regressions in the normal suite.
2. Fix script exit propagation and establish CI plus a clean Git baseline. The recurring lesson is that filtered success-looking logs are not exit-status evidence; the mock failure demonstrates the gap.
3. Harden clipboard fingerprinting and controls; validate meeting URLs; make claims match enforced behavior. The recurring lesson is to inspect signed entitlements on the artifact, rather than infer them from project settings.
4. Move heavy storage/search off the UI thread, add representative fixture benchmarks, then verify real screens in light/dark and large accessibility text settings.
5. Build and verify the intended distribution artifact when distribution is authorized.
6. Add aliases and real frecency, then the optional user-selected notes folder. Preserve the intentionally small scope.

The automated checks performed here are the isolated unit tests, regression reproducers, builds and mocked script failures. No new CI gate or runtime safeguard has been installed.

## Naming direction

Aim for a short spoken name that fits “summon, find, copy, continue,” with room for notes. Avoid tying it specifically to launching rockets, AI, or a command shell.

| Candidate | Character | Reservation |
| --- | --- | --- |
| **Vey** (vay) | Fast, light, quiet; my preferred direction | Pronunciation/spelling needs a simple introduction; not cleared |
| **Kiv** (kiv) | Crisp, three letters, keyboard-friendly | More abstract; software acronym uses already exist |
| **Fletch** | Most memorable connection to Slingshot's motion/arrow theme | Crowded technology name; existing Fletch businesses |

Possible line: **“Vey. Find it. Do it. Back to work.”** These are creative candidates, not available-domain or trademark findings. Preliminary web screening found clear reasons to set aside several tempting alternatives: [Flick already has a macOS clipboard product](https://marketing.typeleaf.app/), [Skirr is an existing app](https://apps.apple.com/sg/app/skirr/id6447444587), [Kip has a productivity-adjacent product](https://kip.life/), and [Zim is an established desktop notes/wiki app](https://zim-wiki.org/downloads.html). [Fletch also has existing technology branding](https://fletch.co/). Validate the preferred name's searchability, store conflicts and domains before committing to a rename.

When renaming, preserve or explicitly migrate the bundle/container identity, Keychain service, clipboard database, notes, preferences and saved window state. A display-name change is much less disruptive than changing all internal identifiers at once.
