# App shortcut activation

## Symptom and diagnosis

On 2026-09-17, the installed app's Claude shortcut was confirmed in Settings as
`cmd+ctrl+option+shift+c` (✦ C). The owner's Caps Lock mapping supplies Control,
Option and Shift; adding Command matches this shortcut. Command-Space summoned
Volant. The owner reported that Claude did not come forward during the scripted
Hyper-C checks. No shortcut registration error was displayed.

The old running-app path called `NSRunningApplication.activate()` and discarded
its return value. Unlike normal launcher activation, it never sent a reopen
request. This is a concrete gap, but the original failure has not yet been
attributed conclusively to event delivery versus activation. Desktop automation
stalled and its app-specific snapshots did not establish foreground ownership.

## Change and prevention

Inactive targets now use `NSWorkspace.openApplication`, including apps already
running. The running process's bundle URL takes precedence over a Launch Services
lookup. The configuration explicitly activates and unhides the target. A
frontmost target still hides on the next press.

Missing apps, rejected hides and failed asynchronous opens report an error in the
existing Settings error area and sound a beep. Event-handler installation and
registration failures are logged. The `AppShortcuts` log category records when a
configured shortcut reaches its action, with running/active booleans only; it
does not monitor or log arbitrary keyboard input or app content.

## Evidence and remaining checks

- 101 native tests passed, including four new tests covering open/hide dispatch,
  missing applications, rejected hides, and asynchronous open success/failure.
- These injected logic tests do not establish global Carbon event delivery or
  foreground activation on the owner's macOS version.
- Pending: headless UI checks, signed installed-app Hyper-C/Hyper-S delivery,
  focus/hide/reopen behavior, and hardware Caps Lock plus Command verification.

If installed verification still fails, first check for an `App shortcut delivered`
event in subsystem `com.mysticcoders.volant`, category `AppShortcuts`. Its absence
points to registration/delivery; its presence narrows the next check to the app
handoff. Do not label a saved shortcut or successful open callback proof that an
app reached the foreground.
