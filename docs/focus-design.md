# Focus sessions

Focus helps the owner stay on one task: a goal, a duration, and the apps and websites to keep out of reach until the session ends. Raycast's [Focus](https://www.raycast.com/core-features/focus) and its [walkthrough](https://www.youtube.com/watch?v=NZwqx_dS-k0) are the behavioral reference; no implementation is copied. The full product spec and delivery plan are in issue #16.

## Decisions

- **Apps are hidden, never quit.** When a blocked app comes forward, Volant hides it and shows a reminder with the goal, Snooze and Back to Work. This needs no permission and loses no work.
- **Websites are blocked by asking the browser** (owner's decision, November 11, 2026). While a session runs, Volant asks the frontmost supported browser for its active tab's address through Apple Events. It swaps a blocked tab for a blank page and restores it on Snooze, Pause, Complete or End. macOS asks once per browser for Automation consent, on first use. Safari and the Chromium browsers (Chrome, Arc, Brave, Edge, Vivaldi, Chromium) are candidates; each is listed only after it's verified in the signed app. Firefox can't report tab addresses to scripts and is unsupported.
- **Rejected for now:**
  - Reading the address bar through Accessibility in the input helper. It would cover Firefox, but it breaks that helper's rule of never reading window text.
  - A Network Extension content filter. It needs a system extension, can't restore tabs, and its macOS 26 URL filter can't serve the macOS 15 baseline.
  - Hosts-file edits and quitting apps. Never.
- **Focus is not Caffeinate and not macOS Focus.** A session doesn't keep the Mac awake or silence notifications, and the copy never claims either.

## Engine (VolantCore, `Core/Sources/VolantCore/Focus`)

- `FocusSetup`: goal, minutes (nil runs until ended, at most 12 hours), apps by bundle identifier, website rules and categories. Decoding drops unknown categories and invalid rules instead of failing.
- `FocusCategory`: Social Media, News, Video and Streaming, Shopping, Messaging and Mail, each with website rules and Mac apps. Amazon is listed as `www.amazon.com` so AWS stays reachable.
- `FocusHost`: rules come from what the owner types (`https://www.x.com/home` becomes `x.com`). A rule matches its host and subdomains, never a host that merely contains it. Internationalized names compare in their Punycode form. Only http and https pages have hosts.
- `FocusSession`: start, pause, resume, edit, snooze, finish, all taking the current time, so the app drives it from the real clock and tests from a fixed one.
  - A new length counts from the start, not counting time spent paused.
  - Volant, the Finder, the Dock, System Settings, loginwindow and SecurityAgent are never hidden.
  - `nextChange(after:)` tells the app when a session or snooze ends without the owner doing anything. The session is Codable, so it survives relaunch.
- `FocusCommand`: the `focus` launcher query handles `focus`, `focus 25m goal`, `focus 1h30m`, and `pause`, `resume`, `complete`/`done`, `end`/`stop`, and `edit`.
- `Preferences.focus`: the setup new sessions start from and the snooze length (3 minutes by default, 1 to 30). It's patched by `Preferences.updateFocus` against an expected snapshot, keeping unknown keys. It's per-Mac and not in `SettingsSync.keys`.

Tests: `FocusTests.swift` (`swift test --package-path Core --filter Focus`).

## App (`Volant/Focus`)

- **`FocusController`** owns the running session.
  - It saves the session to `focus-session.json` in the support folder after every change and restores it on launch, unless it has already run out.
  - While a session runs, it ticks once a second and observes app activation. A blocked app is hidden with `NSRunningApplication.hide()`, never quit, and a reminder is published.
  - The clock, state file, frontmost-app lookup and hiding are injected for tests.
  - Completing a session, by time or by the owner, throws confetti. Ending it doesn't.
- **Launcher:**
  - `focus` lists Start Focus Session… and Start with Last Setup while idle, and Pause/Resume, Complete, Edit and End while a session runs. `focus 25m goal` starts at once with the remembered block list.
  - The form reuses the snippet and quicklink entry form (`LauncherEntryKind.focus` and `.focusEdit`). The goal is the name field, plus a length menu and the block list as chips with an add field suggesting categories, installed apps and typed websites.
  - Starting saves the setup as `config.focus.lastSetup` through `Preferences.updateFocus`, retrying once against a newer file.
  - New `focus` queries select their first row; a session change under the same query keeps the selection.
  - `Focus Session` is a core command, and `focus` is reserved in `LauncherRouting`.
- **Focus bar** (`FocusBarPanel`): a borderless, non-activating floating panel with the goal, the time left, Pause/Resume, Complete and a menu (Edit Session…, Move to Menu Bar, Reset Position, End Session). Its position is remembered and clamped back on screen. Docking hides it and shows `FocusStatusItem` in the menu bar instead: the time as text, with the same controls in a popover. The placement choice is kept in UserDefaults.
- **Notch** (`FocusNotchPanel`, `Volant/Focus/FocusNotch.swift`): the default placement.
  - On the screen in use (`NSScreen.main`), when it has a camera notch, the session shows as a black pill around the notch: the Focus symbol in the left wing and the time in the right, each 72 pt wide, so menu bar items beside the notch stay visible.
  - The notch's position comes from `safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (`NotchGeometry`).
  - Resting the pointer on it for 0.25 s expands it downward into the goal, time and controls. Leaving collapses it after 0.6 s.
  - Reminders drop out of the notch instead of the reminder panel. The panel still announces them to VoiceOver and closes them after its lifetime.
  - A completed session shows a green "Done" for 2.5 s.
  - It joins every Space and full-screen app at status-bar level plus one, and never activates Volant.
  - On screens without a notch, the placement falls back to the floating bar. The placement (notch, floating bar or menu bar) is picked from the bar's "Show In" menu and kept per-Mac in UserDefaults. An earlier "Move to Menu Bar" choice carries over as the menu bar.
- **Reminder** (`FocusReminderPanel`): near the top of the screen under the pointer. It shows what was blocked, the goal, Snooze N Minutes and Back to Work, is announced to VoiceOver, and closes itself after 12 seconds.
- **Settings:** a Focus section in General with the snooze length (1 to 30 minutes). The Toggle Focus Session shortcut (`focusHotKey`, per-Mac, not synced) is in Keyboard Shortcuts. It ends a running session, or starts one with the last setup, opening the form when that setup blocks nothing.

Tests: `FocusControllerTests`, `FocusRowTests`, `FocusDraftTests` and `LauncherFocusTests`. The launcher fixture renders the idle rows, form, running rows, focus bar and reminder in light and dark (`/tmp/volant-core-focus-*`). Fixture renders aren't evidence of hiding a real app, live hotkey delivery, the menu bar item, or behavior across Spaces and full-screen apps. Those need the installed app.

## Websites (`Volant/Focus/FocusBrowsers.swift`)

- **How a tab is checked:** while a session is running, not paused, and blocks websites, `FocusController` asks the frontmost supported browser for its current tab. It asks once a second on the timer and immediately when a browser comes forward, with one check at a time. The answer is dropped if the session changed meanwhile.
- **How Focus talks to the browser:** Apple Events are built directly (no compiled AppleScript) and sent on a private queue, the same way `SystemEvents.swift` does it:
  - Chromium browsers: `URL ` of the `acTa` (active tab) of the front window, addressed by window `ID  ` and tab `ID  `.
  - Safari: `pURL` of the `cTab` (current tab), with the tab addressed by its `pidx`.
  - Nothing launches a browser. Only the one in front is asked.
- **What happens to a blocked tab:** a match by `FocusSession.blockingRule` sets the tab to `about:blank` and shows the reminder ("x.com is blocked") from the notch or the reminder panel.
- **Restoring tabs:** Focus keeps the blanked tab and its address in memory only. It puts the address back if the tab still shows the blank page:
  - Snooze restores that site's tabs.
  - Pause, End, Complete and edits that unblock a site restore the affected tabs.
  - A crash loses the addresses, and those tabs stay blank.
- **Permissions:** each browser is in `com.apple.security.temporary-exception.apple-events`, in both entitlements files, and `NSAppleEventsUsageDescription` explains the use. macOS asks once per browser. A refusal (`-1743`) stops Focus asking that browser until relaunch.
- **Browser support:**
  - **Verified** by the owner in signed Volant Dev on November 11, 2026: Google Chrome (blocking, Snooze restore, End and Pause restore, incognito), Safari, Brave, Brave Origin (`com.brave.Browser.origin`) and Vivaldi.
  - **Implemented but not verified, not installed on the test Mac:** Microsoft Edge, Arc, Chromium and Safari Technology Preview. Don't list these until each is checked.
  - **Unsupported:** Firefox, which has no scripting access to tabs.
- **Limits:** only the front window's current tab is checked, so a blocked site in a background tab is caught when it's selected. A blocked page can show for up to about a second before it's blanked.

Tests: `FocusBrowserTests` (a fake browser: blanking and the reminder, other sites and apps left alone, Snooze, Pause, End and edits restoring tabs, refused browsers not asked again, sessions without websites never asking, and every supported browser holding an Apple Events exception).

## Privacy rules

- Page addresses are compared in memory only while a session is blocking, and only for the frontmost supported browser. They're never logged, persisted or synced.
- Only blanked tabs' addresses are kept, in memory, until they're restored. A crash loses them, and the tabs stay blank.
- Block lists live in config.json under `focus`. No browsing history is recorded.
