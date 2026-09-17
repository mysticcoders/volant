# Launcher review and regression checks — 2026-09-14

Symptom: the owner typed “screen” but saw the placeholder and Suggestions, several highlighted rows, and clicks did not activate Screen Sharing.

Review: requested through `herdr --skill`, verified HERDR_ENV and the idle Claude agent in the Volant workspace (`wK:p1`), then sent a read-only review. Claude confirmed the positional fallback problem and identified an app-modal session as another plausible cause: the floating panel can be visible without ever becoming key, so resignKey never dismisses it. The original screenshot alone does not establish which path occurred.

Fixes:
- Result actions use native buttons and stable row IDs. Missing/stale IDs never fall back to index zero. Context menus exist only on agent rows.
- Every summon restores the native search editor if present. SwiftUI focus recovery does not clear a field editor that already owns input.
- While an app-modal window exists, summon brings that window forward and does not show an inert launcher. A panel that fails to become key is dismissed with an OSLog fault.
- Duplicate result IDs are removed before SwiftUI sees them, with a count-only OSLog warning. Identical section titles merge. Result updates assert main-thread delivery in debug builds. Imported snippets without keywords have distinct IDs.
- Import review fixes: UTF-8-safe hexadecimal parsing, lowercase aliases bound to exact app paths, reserved-command conflicts reported, nested unknown config fields preserved, and checked import casts/values.

Automated evidence:
- `tools/check-launcher.sh` uses isolated clipboard/usage/notes storage. It covers stale activation, identity vs changing app metadata, keyword-free snippets, deduplication, exact app eligibility, and focus restoration.
- The same script now uses the actual non-activating LauncherPanel, in-process key/mouse events, a seeded Screen Sharing entry, and an injected launch closure: typing screen, clicking its result, repeated summon, and a dummy modal session. No real app is launched by this fixture and no global input events are posted.
- `tools/check-raycast.sh` has 30 focused checks, including an independently generated encrypted archive and exact expected errors for malformed headers, authentication failures and rollback.
- `.swiftlint.yml` adds focused correctness rules for positional fallback, gesture-only launcher actions, unchecked import casts/unwraps, and app-modal calls in Panel/Import. These are pattern checks, not proof of runtime correctness.
- `Scripts/test.sh` runs lint and both focused suites before the existing hosted tests. No GitHub Actions workflow has been added yet; standalone focused suites were run locally, not the whole hosted test suite.
- Actual rendered launcher and importer views were inspected in light/dark appearances. Computer Use cannot initialize in the stale workspace environment. Installed desktop input and the personal archive password/file-picker path still need live verification.

Next gaps:
1. Verify the installed launcher with the owner's actual Screen Sharing search and their real encrypted export locally.
2. Move remaining older Backup/ACP app-modal pickers to sheets; the launcher guard now prevents the dead-panel failure meanwhile.
3. Add a macOS CI job for focused checks and retain rendered artifacts; confirm WindowServer support on the selected runner first.
4. Surface app launch/hotkey registration errors, add rich-note conversion after inspecting an actual unlocked export, and make multi-file import recovery automatic after process interruption.

Prevention: model tests alone did not cover the window's modal/non-activating behavior. Preserve the real-panel regression in the standard test entry point. Never describe synthetic archive compatibility or in-process input as a live installed-user-data test.

Delivery: the final Release artifact was installed at `/Applications/Volant.app`; deep/strict code-signature validation and byte comparison of the installed executable passed. A read-only window-title check confirmed the installed “Import from Raycast” window opened. This does not establish that the personal archive has been unlocked or imported.

## Home / Home Assistant follow-up

Symptom: typing ho/hom showed Home first but highlighted Home Assistant; Up appeared ineffective.
Cause: composing a fresh query preserved the previous suggestion identity. Separately, lazy row styling could remain stale after the model selection changed.
Fix: fresh queries reset to their own first result; same-query asynchronous deliveries still preserve identity. Each row observes the launcher model directly for selection styling and accessibility selection.
Prevention/evidence: isolated actual-panel tests cover h/ho/hom, Down/Up, and clicking Home with the pinned harness strip. Pixel assertions compare the two rendered row backgrounds after every transition in light and dark, independently of model assertions. These run in the existing focused test entry point. Installed real-data keyboard/mouse verification remains a separate smoke check.

## Active conversations and window placement — September 14, 2026

Focus loss previously dismissed every launcher, including active ACP work. The panel now stays visible for active ACP sessions, submitted/unsent prompts, open Wi-Fi forms, and pending connectivity actions. Ordinary search still dismisses. Summon refocuses an already-visible inactive panel; Escape and summon while focused remain explicit dismissals. Summoning from AI Chat returns to the default launcher while preserving its ACP session, messages, pending permissions and draft. Tab from the main search editor resumes the chat. Other active forms retain their existing preservation behavior.

The wing is an explicit native drag target, with an open-hand cursor and accessibility help. Movement saves coordinates in preferences; re-summon restores them and clamps to an available screen after display changes. Tests use an isolated preference store. A semantic window backdrop keeps text and materials readable in both appearances.

Automated native checks cover real key-window transfers across ACP phases, explicit dismissal, draft preservation, ordinary blur, move notifications, remembered position, and recovery of offscreen coordinates. Interactive drag/appearance verification is separate from those tests.

Interactive evidence: the isolated fictional ACP preview was inspected in light/dark appearances. CUA mouse dragging moved the panel and `windowDidMove` persisted coordinates (observed `(635,383)`, then `(735,333)`). AppKit `performDrag` did not reliably start a move in this non-activating hosted view, so the dedicated native NSView tracks mouse down/drag/up directly. Source tests and the preview remain separate from an installed-provider ACP smoke test.
