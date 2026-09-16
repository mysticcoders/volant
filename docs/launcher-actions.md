# Application and file Actions

The footer exposes Actions (⌘K); Reveal in Finder moves inside this searchable menu. ⌘↩ still reveals the selected result directly. The menu stays inside the launcher panel, with native button rows, keyboard arrows, Return, and Escape (close Actions first, then the launcher). Only displayed, implemented shortcuts have glyph hints.

Applications offer Open, Reveal in Finder, Show Package Contents, Add/Remove Favorites, Copy Path/Name/Bundle Identifier, Edit Shortcut & Alias, and Reset Ranking. Files offer Open, Reveal, Copy Path/Name, and Reset Ranking. Missing bundle metadata reports an error without changing the clipboard.

Favorites are stored as app paths in `favoriteApps` in configuration. The home screen shows installed favorites separately, preserving their configured order and avoiding duplicate Suggestions. Membership edits read the latest document, preserve unknown fields and other favorites, and reject stale membership. Reset Ranking drains queued usage writes and transactionally removes the app/file's Volant score and exact-query choices; Spotlight recency can still suggest the app afterward.

A menu captures stable result identity and revalidates before execution. Selection/query changes, removed results, and hiding the panel dismiss it. Bundle metadata is read only when Copy Bundle Identifier is activated; constructing the menu adds no startup discovery or background process.

## Verification

- `LauncherActionsTests` checks favorite persistence, unknown-field preservation, stale writes, ranking persistence, and stale action targets with isolated fictional stores.
- `tools/check-launcher-actions.sh` compiles the production asset catalog using release optimization, then runs a separate native branded fixture in light/dark appearances. It is dispatched through headless Tart locally and the UI job in CI. This avoids changing activation behavior in the existing bare launcher fixture.
- Rendered screens, fixture keyboard evidence, and signed installed Finder integration are separate evidence. See the PR for results.

## Follow-ups

- Finder's Get Info integration, without unnecessary automation permission prompts.
- Broader configurable per-action keyboard shortcuts.
- App lifecycle actions, Auto Quit, and uninstall remain outside this everyday-actions scope.

## Recurring lesson

Symptom: the newer host compiler accepted the expanded LauncherView while Xcode 16.4 in Tart failed its expression type-checking budget. Cause: one large SwiftUI body combined content, overlay, and keyboard modifiers. Prevention: split content from interaction modifiers; keep the VM/compiler CI check. A host build alone is not compatibility evidence.
