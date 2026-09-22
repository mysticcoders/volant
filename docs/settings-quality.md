# Settings and app shortcuts

## Scope

Issues #2 and #3: compact status menu (Show Volant, Settings, disabled version/build, updates, quit); native Settings sections for General, App Shortcuts, Data & Configuration. Login state and errors are handled in Settings. Existing backup/import actions are relocated, not reimplemented. Notes remains available through `note`/`notes`; Settings and Reload Configuration are searchable commands.

App results expose Actions with Command-K. Return opens the selected app’s shortcut/alias editor; Escape dismisses the actions. The captured app identity is validated before opening Settings. Query/selection changes close the actions. Command-comma remains Settings and Command-Return remains Reveal in Finder. Raycast’s documented Command-K convention was checked against https://manual.raycast.com/action-panel and https://manual.raycast.com/command-aliases-and-hotkeys.

The recorder requires Command, Control or Option. Aliases are single words/letters typed into the launcher; they never claim ordinary typing globally. App bindings retain bundle identifiers. The editor rejects Volant conflicts, unavailable combinations, reserved aliases, collisions and stale configuration snapshots. Atomic writes preserve unrelated aliases and nested unknown fields. Failed writes retain draft values. Global registration failures are surfaced in App Shortcuts; an OS registration race after saving is reported rather than silently described as working.

## Verification

- `tools/check-launcher.sh`: light/dark native launcher regression checks plus app-binding persistence, nested unknown fields, replacement/removal, reserved and duplicate aliases, modifier validation, existing Volant shortcuts, external availability failure, stale snapshots and searchable Settings/Reload commands.
- `tools/check-raycast.sh`: 30 checks passed after adding new reserved commands to shared routing.
- Focused SwiftLint passed; Release compilation passed before final sizing correction, with final release validation recorded below.
- `tools/preview-settings.sh`: isolated config and application fixtures; live light/dark sheet inspection, native shortcut capture, successful alias/shortcut save reflected in list, Cancel, Command-K from focused launcher search and Return into the editor. It never imports the owner’s backups or changes their login-item preferences.
- `tools/preview-settings.sh --render`: minimum-size section fixtures in both appearances, written to `/tmp/volant-settings-renders`.

## Remaining verification

A physical global-hotkey launch/focus/hide and reassignment test in the signed installed app remains necessary. CUA key injection did not establish Carbon global event delivery; recording a key in an editor is separate evidence. Real login-item registration/approval, backup export/import with personal data and the installed Sparkle upgrade are not exercised by these fixtures. Preserve the owner’s data; use an isolated account for full release smoke tests.

## Next steps

1. Install the test DMG and check app hotkeys physically; complete #7’s two-version updater test.
2. Show orphaned app bindings when their apps are no longer installed.
3. Translation: evaluate Apple TranslationSession on macOS 15+, with on-device shared language packs and runtime pair availability. No translation command is implemented by this settings change. References: https://developer.apple.com/videos/play/wwdc2024/10117/ and https://support.apple.com/en-ie/guide/mac-help/mchldd8b3c15/mac.

## Rendering lesson

Visible fixture windows were resized by external accessibility requests during capture (confirmed by an NSWindow setter stack through NSAccessibilityEntryPointSetValueForAttribute). This initially resembled a SwiftUI sizing bug. Minimum-size renders now use hidden native windows and assert their bounds; live keyboard and sheet checks remain separate. Do not change the owner’s window-management configuration to force a test pass.

## Final build evidence — 2026-09-14

Volant 0.1.2 build 4 was archived/exported with Developer ID, notarized and stapled at `dist-release.ykah5E/updates/Volant-0.1.2.dmg`. Both app and DMG passed Gatekeeper as Notarized Developer ID; signed Sparkle artifacts were generated and verified locally. This is a local test delivery; the public website/feed still offer 0.1.1.

Final launcher light/dark suite and binding checks passed. All six section render fixtures assert 680×500 bounds and were visually inspected with readable controls. The native menu accessibility tree confirms the intended order and disabled version label. Native-menu popup pixels were not captured by the window-only screenshot surface. The preview editor recorded and saved a fictional shortcut/alias; physical global activation remains unverified.

Settings ranking follow-up: generic `settings` queries no longer short-circuit to Volant Settings. Matching application rows precede built-in commands, including partial queries; explicit `volant settings` remains direct. Light/dark launcher checks assert System Settings is selected first for `sett`, `Settings`, and mixed-case/whitespace variants. Release build passed.

Global shortcut editor follow-up: General now includes shared native recorders and explicit Save buttons for Show Volant and Open Notes. Changing a binding re-registers shortcuts through the existing reload path. Config patches preserve nested unknown fields, reject stale values and conflicts with the other global binding or app bindings, and retain failed drafts for retry. The main app now surfaces registration failures for these two shortcuts as well.

Global shortcut validation: native fixture recording and Save succeeded for both controls; assigning the same combination to Notes showed a conflict, retained the draft, and accepted a corrected combination on retry. Light/dark compact renders and the expanded persistence suite passed. These fixture values never changed the owner’s preferences.

## Immediate shortcut saving

The owner replaced the explicit Save flow: all shortcut recorders now commit when a combination is captured, show a checkmark with Saved only after a successful write, and expose a native hover × to remove the binding immediately. Removal shows Removed and persists an empty global key (no fallback to the default) or deletes the app binding. Keyboard focus plus Delete and the accessibility Remove shortcut action provide alternatives to hover. Conflicts and write errors retain the attempted change for Retry, without claiming success. App shortcut writes preserve aliases and do not apply unfinished alias text. Alias text retains a separate Apply Alias action and is applied on Done.

Native preview evidence: recording updates General and app controls immediately; the app sheet shows Saved without Save; global accessibility removal shows Not set and Removed. Persistence checks cover removal of both global bindings, app removal and alias preservation. Physical global-key activation remains a separate installed check.

Hover rendering evidence: native mouse-enter events were driven in hidden fixtures to assert the remove buttons become visible; inspected the resulting light/dark controls. CUA’s accessibility Remove action also verified immediate persistence and Removed feedback. Final recorder honors disabled-state environment; app shortcut autosave does not invalidate protection against concurrent alias edits.

## Settings dialog and preview compatibility

Settings now uses an NSPanel with AXDialog semantics and fullscreen disabled, so AeroSpace can float it without owner configuration changes. The entire padded sidebar label is a hit target. Escape reaches the panel through the responder chain and hides Settings; a recording shortcut consumes the first Escape to cancel recording. Attached sheets keep their own dismissal behavior.

Evidence: Release build, SwiftLint and launcher checks passed. All six compact light/dark section renders were inspected. With AeroSpace running, the native preview remained 680×500 and exposed a dialog accessibility role; clicking the blank trailing area of App Shortcuts switched sections. Escape canceled recording without changing the binding, and a second Escape dismissed the window. These interactions used fictional preferences; installed-app interaction and a refreshed notarized DMG remain separate delivery checks.

The stray V icon came from a leftover Settings preview, not the production wing asset. Preview status items are now hidden except during explicit menu testing, when they use the real wing. Close preview processes after inspection. The preview compiler had defaulted to a macOS 28 target, causing Launch Services to reject it on the owner's system even though direct execution worked. Its build now explicitly targets macOS 15, matching project.yml; the rebuilt preview opened successfully through Launch Services. Target selection is automated in the script; live launch and window-manager checks remain manual.

## Searchable System Settings destinations

The launcher now searches 18 curated pane titles and synonyms (for example `settings login`, `dark mode`, `disk space`, and `software update`). Generic `settings` retains the System Settings application as the first result. Explicit pane queries containing `settings` bypass connectivity discovery, so `wifi settings` does not trigger permission requests or scans. Result identities use the destination identifier and activation reports URL-opening failures without dismissing the launcher.

Pane identifiers were checked against the installed Apple extension bundles. These are pane-level URL links, not Apple's private search index; matching a permission keyword opens Privacy & Security, not an individual permission control. URL acceptance does not prove the OS navigated to the correct pane. The native preview's Login Items result was clicked and the resulting System Settings Login Items screen was confirmed. Other destinations and macOS 15 remain to be exercised individually. Release build, SwiftLint, launcher routing/ranking tests, and light/dark destination-row fixtures passed; renders use the actual LauncherPanel size. The dedicated `tools/preview-settings.sh --destinations` fixture supports manual navigation checks without owner preference writes.

Next concrete work: finish the pane-link matrix on supported macOS versions and refresh the notarized delivery. Caffeinate is not implemented: use public IOKit idle-sleep assertions with duration, optional display assertion, clear active/stop state, release on stop/quit and OS timeout; do not mutate power preferences. Translation remains issue #5: use Apple's TranslationSession on macOS 15+, runtime language-pair checks and system-managed model-download consent, then show source/target text and Copy Translation. Both are separate features from this search change.

## Native grouped forms — September 22, 2026

The owner found Settings padded and uneven. Every pane was a hand-built `VStack` inside a detail
column that already added 24 pt, so nested lists, scroll views and cards stacked their own insets
on top; spacing varied between 4 and 18 pt with no shared rule, captions sat 18 pt from the control
they explained, and each pane repeated its sidebar name as a large title.

Settings now follows the System Settings pattern. The sidebar is a native `.sidebar` list with a
symbol per section. General, Status Bar, AI, Extensions and Data & Configuration are grouped
`Form` sections: labels align on the leading edge and controls on the trailing edge, and
explanatory text is a section footer directly under the controls it describes. The form owns its
own margins and scrolling, so no pane adds padding of its own. App Shortcuts remains a plain list
under a compact search header, with shorter rows and a visible alias field. Recorders are 26 pt
tall instead of 32.

Fixtures no longer click hard-coded coordinates. `accessibilityFrame(_:in:)` in the launcher and
Actions fixtures locates the sidebar rows, Connect ACP, Choose Folder, the Herdr toggle and the
local server's Use button by accessibility label, and prints every label it saw on a miss. The
launcher fixture and `tools/preview-settings.sh --render` now render all six sections.
