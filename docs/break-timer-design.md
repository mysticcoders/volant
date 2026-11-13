# Break reminders

Breaks remind the owner to step away: after a stretch of work, Volant covers the screen for a short break. The feature and the decisions below were approved by the owner on November 11, 2026.

## Decisions

- **Off by default.** Breaks start only after the owner turns them on in Settings › General › Breaks or with the launcher's Turn On Breaks. A fresh install never shows a break unasked. Take a Break Now works while they're off, for one break.
- **Two ways to count work**, the owner's choice:
  - **Active Time** (default) counts only time at the Mac. An idle stretch under two minutes still counts as work, such as reading. Being away for at least the break length counts as a break taken and starts the count over.
  - **Clock Time** counts wall-clock minutes since the last break, whatever the owner is doing. If the owner is away for at least the break length at the moment a break is due, it counts as taken.
  - Sleep, display sleep, screen lock and fast user switching count as time away in both modes. So does any gap of over 30 seconds between two checks, which covers sleep and time Volant wasn't running.
- **Defaults:** a break every 45 minutes, 5 minutes long. The interval runs from 10 to 180 minutes in 5-minute steps, the length from 1 to 30 minutes.
- **Heads-up** (on by default): a small non-activating notice in the top corner a minute before a break, with Postpone 5 Minutes and Skip.
- **Strictness**, the owner's choice:
  - **Gentle:** a reminder panel, never full screen, with Start Break, Postpone and Skip. A break started there counts down in the same panel with End Break.
  - **Standard** (default): a dimmed overlay on every display and Space with a countdown, a suggestion, Postpone 5 Minutes and Skip.
  - **Strict:** the same overlay without Postpone. Skip appears after 10 seconds and must be held for 3 seconds, by pointer or by holding Return. VoiceOver's press skips at once, since it is already deliberate.
- **Never trap the owner.** There is always a visible way out, and Volant disables nothing: no process-switching locks, no quitting apps, no kiosk mode. Overlays are ordinary windows of Volant's process, so they disappear if Volant quits or crashes. Each overlay has its own watchdog that removes it 3 seconds after the break's end time, whatever happens to the schedule's timer. A break running at relaunch counts as taken, so a restart never covers the screen again.
- **Calls and screen sharing.** A break doesn't start, and the heads-up doesn't show, while a camera or microphone is in use. The break waits, and once both are free the heads-up appears for a minute, or the break starts when the heads-up is off. A call that starts during a break ends the overlay, and the break waits until the call is over. A quiet call isn't counted as time away.
- **Focus.** A running Focus session pauses for a break and resumes afterward, so it shows no blocked-app reminders during one. A session the owner had already paused stays paused.
- **Breaks are per-Mac.** Settings live in config.json under `breaks` and aren't in `SettingsSync.keys`.

## Engine (VolantCore, `Core/Sources/VolantCore/Breaks`)

- `BreakPreferences`: on or off, mode (`active` or `clock`), interval, length, strictness and heads-up. Decoding clamps out-of-range numbers and falls back to defaults for unknown or mistyped values. `Preferences.updateBreaks` replaces the block against an expected snapshot, keeping unknown keys inside `breaks` and everywhere else, so a stale copy is refused.
- `BreakSchedule`: a pure state machine with phases `working`, `headsUp`, `waitingForCall`, `reminding` (Gentle) and `onBreak`. `advance(_:settings:)` takes a `BreakInput` with the time, idle seconds, whether the owner is away and whether a camera or microphone is in use. It never reads a clock or the system. Owner actions are `startBreak`, `postpone`, `skip`, `endBreak`, `pause(until:)`, `resume` and `restart`. `restored(at:)` turns a running break into a taken one after relaunch. `needsCallState` limits device checks to the minute before a break and after.
- `BreakCommand`: the `break` and `breaks` launcher queries, with `now`, `skip`, `pause`, `resume`, `on`, `off` and `end`. Both words are reserved in `LauncherRouting`, and `Breaks` is a core command.

Tests: `BreakTests.swift` (`swift test --package-path Core --filter Break`) cover both modes, heads-up, postpone, skip, pause and resume, time away from idle, lock and sleep, call deferral, Gentle reminders, relaunch, settings decoding and the stale-checked patch.

## App (`Volant/Breaks`)

- **`BreakController`** owns the schedule and the settings. While breaks are on, or a break runs, it ticks once a second. It reads idle time and camera or microphone use through injected closures, and follows `NSWorkspace` sleep, display sleep and session notifications plus the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` distributed notifications. It saves the schedule to `break-schedule.json` in the support folder on every phase change and at least once a minute. It pauses and resumes Focus through two closures the app sets. `AppDelegate` owns it like the Focus controller, applies config on every reload, and stops it in `applicationWillTerminate`, which ends a running break and resumes Focus.
- **`BreakSignals`** reads the real signals:
  - Idle time: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`.
  - Microphones: `kAudioDevicePropertyDeviceIsRunningSomewhere` on each audio device that has input streams.
  - Cameras: `kCMIODevicePropertyDeviceIsRunningSomewhere` on each CoreMediaIO device.

  These read properties only. No audio or video is opened, and nothing names the app using a device.
- **`BreakPresenter`** shows what the schedule calls for:
  - `BreakNoticePanel`: the heads-up and the Gentle panel. It's a borderless non-activating panel in the top corner of the screen under the pointer, on every Space.
  - `BreakOverlayWindow`: one per display at screen-saver level, with `canJoinAllSpaces`, `fullScreenAuxiliary` and `stationary`. Overlays are rebuilt when displays change. The overlay on the pointer's display becomes key, so Return reaches Strict's hold, but Volant isn't activated.
  - Content uses `ThemedRoot` and `theme.windowBackground`. VoiceOver hears an announcement when the heads-up shows and when a break is due. Overlay buttons ignore presses for the first second, so keys already in flight can't skip a break, and no button is a default action.
- **Launcher:** `break` lists Turn On Breaks and Take a Break Now while off. While on, it lists Take a Break Now, Skip Next Break, Pause Breaks for 1 Hour and Turn Off Breaks. While paused, it lists Resume Breaks first, and during a break, End Break. Subtitles show the next break, such as "Next break in 23 min · active time", or the settings it would turn on. New queries select their first row; a state change under the same query keeps the selected row while it's still offered. Turning breaks on or off is a stale-checked `updateBreaks` patch, retried once against a newer file, followed by a configuration reload.
- **Settings › General › Breaks:** on or off, Count (Active Time or Clock Time), the interval and length, Strictness and the heads-up. Each change is a narrow `updateBreaks` patch.

The optional Take a Break global shortcut was left out to keep the scope down.

Tests: `BreakControllerTests`, `BreakRowTests` and `LauncherBreakTests` use a fake clock, fake idle and call readers and temporary files. They start no timers, observers or windows. The launcher fixture (`tools/launcher/check.swift`, "Breaks:") renders these to `/tmp/volant-core-break-*-{light,dark}.png` in the UI VM:

- the off and on rows
- the heads-up
- the Gentle reminder and countdown
- the Standard overlay
- the Strict overlay before and after Skip appears

It also checks that Return can't start Skip early, that letting go cancels it, that a three-second hold skips the break and removes every overlay, and that an orphaned overlay's watchdog removes it.

## What was verified, and what needs the installed app

- **Verified in the sandboxed test host:** `BreakControllerTests.testSystemSignalsAnswerInsideTheSandbox` runs inside Volant Dev's sandbox (`APP_SANDBOX_CONTAINER_ID` set), with Volant's entitlements and no new ones.
  - The idle counter returned a live value of a few seconds.
  - CoreAudio listed 5 input devices, and CoreMediaIO listed 5 cameras, the same counts as an unsandboxed probe on the same Mac.
  - No device was in use at the time, so both checks answered "not in use".
  - The test completed without waiting on any permission request. These calls read properties only and need no Input Monitoring, Accessibility, camera or microphone grant. The screen wasn't watched during the run, so the installed app should still confirm that no prompt appears.
  - CoreMediaIO logs one harmless `inot` property error on first use.
- **Needs installed-app evidence:**
  - Real idle tracking over a working day.
  - Overlays above full-screen apps and across Spaces and multiple displays.
  - Deferral during real calls in FaceTime, Zoom, Meet and Teams.
  - A device "in use" reading while one actually runs.
  - Sleep, wake and lock transitions.
  - Keyboard focus in the overlay with Full Keyboard Access.
  - VoiceOver announcements.
- **Known limits:**
  - Any app holding a microphone open, including Volant's own dictation or an always-listening utility, defers breaks for as long as it does.
  - Screen sharing without a camera or microphone isn't detected; that would need a screen-capture API or permission, which wasn't added.
  - Clock Time doesn't reset for time away before a break is due, by design.

## Privacy

`break-schedule.json` holds only the phase, times, the active seconds counted, and whether a break paused Focus. Idle time, device state and lock state are read in memory each second and never logged, persisted or synced. Volant doesn't record which app uses a camera or microphone, what the owner was doing, or any input.
