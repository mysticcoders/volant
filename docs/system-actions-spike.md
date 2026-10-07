# System actions spike — September 30, 2026

Can Volant lock the screen, sleep, start the screen saver and show macOS's restart, shut down
and log out dialogs, and at what permission cost? Answered by measurement. Nothing is wired
into the app.

## Method

`tools/spike-system-actions.sh` builds one probe (`tools/systemactions/probe.swift`) into two
Developer ID signed bundles that differ only in App Sandbox. The sandboxed one carries what
production would need: `com.apple.security.automation.apple-events` and a
`temporary-exception.apple-events` list naming `com.apple.loginwindow`, `com.apple.finder` and
`com.apple.systemevents`. Each invocation performs one action and prints one JSON line.

`tools/spike-system-actions-vm.py` runs them in a headless Tart guest, never on the owner's
desktop, with a fresh boot per state-changing step, because a locked session cannot be unlocked
remotely. Probes run in the console user's GUI session over SSH with `launchctl asuser`.
Automation permission is checked with `AEDeterminePermissionToAutomateTarget` and
`askUserIfNeeded: false`, so no probe can raise a consent dialog. Restart and log out were probed
only with the *show dialog* events (`aevt/rrst`, `aevt/logo`), never the events that act
immediately.

Guests: `volant-render-27` (macOS 27.0, 26A428) and `volant-ui-xcode` (macOS 15.7.7, 24G720).

## Results

| Action | Mechanism | Sandboxed result, macOS 15 and 27 | Prompt |
|---|---|---|---|
| Lock Screen | `SACLockScreenImmediate()` from the private `login.framework`, loaded with `dlopen` | Returns 0; session goes from unlocked to locked (`CGSSessionScreenIsLocked`) | None |
| Show restart dialog | Apple Event `aevt/rrst` to `com.apple.loginwindow` | Sent without error; the only new window belongs to `loginwindow`; the guest restarted after the dialog's 60 second countdown, which a consent prompt would not do | None |
| Start screen saver | `NSWorkspace.openApplication` on `ScreenSaverEngine.app` | Engine running | None |
| Sleep displays | `/usr/bin/pmset displaysleepnow` | Exit 0; the guest (password required immediately) became locked | None |
| Sleep | `/usr/bin/pmset sleepnow` | Exit 71, no message, sleep count 0, sandboxed and unsandboxed alike | Inconclusive: the guests do not sleep |

Findings worth keeping:

- **Nothing here needs the helper.** Every working action worked from the sandboxed bundle.
- **`AEDeterminePermissionToAutomateTarget` is not the truth for `loginwindow`.** It reported
  `-1744` (would require consent) for the restart and log out dialogs, yet sending proceeded
  with no prompt and produced the real dialog. Decisions must rest on sending, not that check.
- **Finder and System Events do need consent** (`-1744` and not running, respectively), which
  keeps Empty Trash and appearance switching behind a first-use Automation prompt.
- **Sleep displays locks** when the owner requires a password immediately, which is the default.
- **An unsandboxed screen saver launch reported not running** in a clean boot on macOS 27, while
  the sandboxed launch succeeded twice. Unexplained and irrelevant to shipping, since the
  sandboxed path is the one Volant would use.

## Risks

`SACLockScreenImmediate` is private API. It worked on both the minimum and the newest supported
systems, but a future macOS can remove it. Load it with `dlopen`/`dlsym` as the probe does, so
a missing symbol becomes a visible "Lock Screen is unavailable" rather than a crash, and fall
back to Sleep Displays, which locks under default settings.

## Not verified

Sleep on real hardware, which needs an agreed moment on the owner's Mac. Log out, shut down and
the non-dialog events were not sent; they use the same `loginwindow` route as the restart
dialog. Whether a signed installed Volant behaves identically to these probe bundles.

## Implemented — September 30, 2026

The launcher's **System** section offers Lock Screen, Sleep, Sleep Displays, Start Screen
Saver, Restart…, Shut Down… and Log Out…. It comes before System Settings panes, so "lock" finds
the action before the Lock Screen pane. Matching is from the start of a name or keyword only,
from three characters, so "displays" still finds the Displays pane. Restart, Shut Down and Log
Out send loginwindow's *show dialog* events, so macOS asks before acting.

The launcher hides first and the action runs 0.2 s later, so the panel is not on screen when the
Mac locks or a dialog appears; a failure reopens the launcher with the reason. Lock Screen and
Sleep Displays have optional global shortcuts in Settings → General, which share the duplicate
checks with the other shortcuts. Lock Screen looks up `SACLockScreenImmediate` at run time and,
if it is missing, sleeps the displays and says so. Sleep tries `pmset sleepnow`, then IOKit's
`IOPMSleepSystem`, which the console user may call.

Entitlements added: `com.apple.security.automation.apple-events` and a
`temporary-exception.apple-events` for `com.apple.loginwindow` only; Finder and System Events are
not included, because Empty Trash and appearance switching are not implemented. Sleep on real
hardware remains to be confirmed on the owner's Mac.
