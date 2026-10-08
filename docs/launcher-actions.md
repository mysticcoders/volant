# Application and file Actions

The footer exposes Actions (⌘K); Reveal in Finder moves inside this searchable menu. ⌘↩ still reveals the selected result directly. The menu stays inside the launcher panel, with native button rows, keyboard arrows, Return, and Escape (close Actions first, then the launcher). Only displayed, implemented shortcuts have glyph hints.

Applications offer Open, Reveal in Finder, Show Package Contents, Add/Remove Favorites, Copy Path/Name/Bundle Identifier, Edit Shortcut & Alias, and Reset Ranking. Files offer Open, Reveal, Copy Path/Name, and Reset Ranking. Missing bundle metadata reports an error without changing the clipboard.

Favorites are stored as app paths in `favoriteApps` in configuration. The home screen shows installed favorites separately, preserving their configured order and avoiding duplicate Suggestions. Membership edits read the latest document, preserve unknown fields and other favorites, and reject stale membership. Reset Ranking drains queued usage writes and transactionally removes the app/file's Volant score and exact-query choices; Spotlight recency can still suggest the app afterward.

A menu captures stable result identity and revalidates before execution. Selection/query changes, removed results, and hiding the panel dismiss it. Bundle metadata is read only when Copy Bundle Identifier is activated; constructing the menu adds no startup discovery or background process.

## Volant menu

Clicking the Volant mark at the bottom left of the footer opens the launcher's own menu, anchored there inside the panel and styled like Actions. Its header names the running version ("Volant v0.2.1", read from the bundle), so it's always clear which build is installed. Items: Send Feedback (a new GitHub issue with only the app version, build and macOS version prefilled), Manual (usevolant.com/docs), Changelog (GitHub Releases), Check for Updates… (Sparkle, as in the menu bar), About Volant, Settings (⌘,) and Quit Volant (⌘Q). "Search for actions…" filters them. Arrows, Return and Escape work as in Actions; Escape closes the menu before the launcher, typing a new query closes it, and only one of Actions and the Volant menu is open at a time. Links open in the browser through NSWorkspace; the main app still has no network access.

## Scroll fade and footer

The results list runs the full height of the panel, and the footer is a translucent bar over it: an ultra-thin material under the theme's surface at 40%, or the solid surface when Reduce Transparency is on. Rows scroll softly beneath it, as in Raycast. A bottom content margin equal to the measured footer height lets the last row scroll fully into view above the bar, and the scroll indicator stops above it. The footer's controls sit on the bar, so they stay legible and take clicks over moving content.

The list also fades at edges with more results beyond them (`EdgeFadeMask`, driven by `onScrollGeometryChange`): a 36-point band under the search field down to 25% opacity, and a band that starts 28 points above the footer and runs underneath it down to 35%. At the start and end of the list nothing lies beyond, so the first and last rows are never dimmed, and keyboard selection scrolls the selected row to the center. The fade is off when Reduce Motion or Reduce Transparency is on. A per-row `scrollTransition` was tried first; it only touched rows almost fully out of view and was not visible in practice.

## Verification

- `LauncherActionsTests` checks favorite persistence, unknown-field preservation, stale writes, ranking persistence, and stale action targets with isolated fictional stores.
- `LauncherAppMenuTests` checks the Volant menu's order, filtering, version header, feedback URL contents, link and command routing, and that it never shows with item Actions. The Actions fixture clicks the Volant mark, reads the version header (a fictional 0.0.0 fixture bundle), filters, activates with Return and checks the Escape order.
- `tools/check-launcher-actions.sh` compiles the production asset catalog using release optimization, then runs a separate native branded fixture in light/dark appearances. It is dispatched through headless Tart locally and the UI job in CI. This avoids changing activation behavior in the existing bare launcher fixture.
- Rendered screens, fixture keyboard evidence, and signed installed Finder integration are separate evidence. See the PR for results.

## Follow-ups

- Finder's Get Info integration, without unnecessary automation permission prompts.
- Broader configurable per-action keyboard shortcuts.
- App lifecycle actions, Auto Quit, and uninstall remain outside this everyday-actions scope.

## Recurring lesson

Symptom: the newer host compiler accepted the expanded LauncherView while Xcode 16.4 in Tart failed its expression type-checking budget. Cause: one large SwiftUI body combined content, overlay, and keyboard modifiers. Prevention: split content from interaction modifiers; keep the VM/compiler CI check. A host build alone is not compatibility evidence.
