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
2. Extend shortcut editing to the launcher/Notes bindings and show orphaned app bindings when their apps are no longer installed.
3. Translation: evaluate Apple TranslationSession on macOS 15+, with on-device shared language packs and runtime pair availability. No translation command is implemented by this settings change. References: https://developer.apple.com/videos/play/wwdc2024/10117/ and https://support.apple.com/en-ie/guide/mac-help/mchldd8b3c15/mac.

## Rendering lesson

Visible fixture windows were resized by external accessibility requests during capture (confirmed by an NSWindow setter stack through NSAccessibilityEntryPointSetValueForAttribute). This initially resembled a SwiftUI sizing bug. Minimum-size renders now use hidden native windows and assert their bounds; live keyboard and sheet checks remain separate. Do not change the owner’s window-management configuration to force a test pass.

## Final build evidence — 2026-09-14

Volant 0.1.2 build 4 was archived/exported with Developer ID, notarized and stapled at `dist-release.ykah5E/updates/Volant-0.1.2.dmg`. Both app and DMG passed Gatekeeper as Notarized Developer ID; signed Sparkle artifacts were generated and verified locally. This is a local test delivery; the public website/feed still offer 0.1.1.

Final launcher light/dark suite and binding checks passed. All six section render fixtures assert 680×500 bounds and were visually inspected with readable controls. The native menu accessibility tree confirms the intended order and disabled version label. Native-menu popup pixels were not captured by the window-only screenshot surface. The preview editor recorded and saved a fictional shortcut/alias; physical global activation remains unverified.

Settings ranking follow-up: generic `settings` queries no longer short-circuit to Volant Settings. Matching application rows precede built-in commands, including partial queries; explicit `volant settings` remains direct. Light/dark launcher checks assert System Settings is selected first for `sett`, `Settings`, and mixed-case/whitespace variants. Release build passed.
