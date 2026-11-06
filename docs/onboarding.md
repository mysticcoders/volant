# Welcome window

The first launch on a Mac opens a Welcome window instead of the launcher. It sets up the summon
shortcut, shows what can be typed, offers the permissions Volant uses, lists agents found on the Mac,
and ends on the extensions with a GitHub star request. Every page can be skipped, and closing the
window at any page counts as done.

## When it shows

`WelcomeLaunch.decide` (VolantCore) reads two things at launch: whether `config.json` existed before
Volant loaded it (loading writes a default file when there is none), and the `welcomeCompleted` key.

| config.json before launch | `welcomeCompleted` | Result |
| --- | --- | --- |
| missing | absent | Show, after writing `welcomeCompleted: false` |
| present | `false` | Show again: the last Welcome never closed (a crash or forced quit) |
| present | absent | An install from before the Welcome window: write `true`, never show |
| any | `true` | Skip |

Launches for a task (`--settings`, `--show`, `--notes`, `--agents`, `--import-raycast`, and the memory
check) never show it. `welcomeCompleted` is per Mac and is not in `SettingsSync.keys`: every new Mac
needs its own shortcut and permissions. It is written with `Preferences.updateBoolean`, which keeps
every other field, including unknown ones.

Reopen it by typing `welcome` (also `onboarding` or `getting started`, all reserved in
`LauncherRouting`), or from Settings › About › Show Welcome…. Both open it at the first page.

## Pages

1. **Your shortcut.** The summon shortcut with the same recorder and stale-checked patch
   (`GlobalShortcutStore.save`) as Settings › Keyboard Shortcuts. If the shortcut failed to register,
   it says so; if Raycast or Alfred is running (checked by bundle identifier only), it says they may
   hold the same shortcut.
2. **What you can type.** `WelcomeTip.all`: `@`/`contacts`, `/`/`files`, `clip`/`clipboard`, `:`,
   `cal`/`today`, `notes`, `translate`, `define`, `talk`, `ai`/`agents`/`rex`, `ext` and `servers`. Try
   It closes Welcome and opens the launcher with that text typed.
3. **Allow access.** Contacts, Calendars and, on macOS 26 and later, Microphone, each Allowed, Allow
   (the system prompt appears only on that click) or Open System Settings at its Privacy pane when
   denied. Open at Login uses the same `SMAppService` call as Settings › General. Typing dictation at
   the cursor shows no status, because asking for Accessibility status adds a Privacy entry on
   macOS 15 (see the input helper rules in AGENTS.md); Set Up… opens Settings › Dictation. Location and
   Bluetooth have no button: they are asked only on first use of their commands.
4. **Your agents**, only when something is found: ACP agents from the helper's `detectACPAgents` (the
   same detection AI Chat's setup card uses), the Rex app by bundle identifier, and Herdr in
   `/opt/homebrew/bin` or `/usr/local/bin`. Nothing connects on its own: Chat opens AI Chat with that
   provider, Set Up… opens Settings › AI, and Show Status turns on the agent's status bar source with
   the same patch as Settings › Status Bar.
5. **Extensions.** Built-in extensions (community ones too, once the owner has allowed community
   extensions in Settings) with their usual switches; an extension that declares hosts asks for them
   before it turns on, as in Settings. Browse the Catalog… closes Welcome and opens the catalog in the
   launcher, which is when it is fetched. Star on GitHub opens the project page in the browser.

There is no Featured list: there are too few extensions for one, and without telemetry there is no
measure of what is popular.

## Privacy

The window records nothing about which pages were seen or what was chosen beyond the settings it
changes. Status reads (`CNContactStore`, `EKEventStore`, `AVCaptureDevice`, `SMAppService`) never
prompt. The helper detection starts no agent and reads no credentials.

## Evidence

- `WelcomeTests` (Core): the launch decision table, the pages with and without agents, tips and their
  reserved words, competing launcher names, and that completion is per Mac and keeps unknown fields.
- `WelcomeModelTests` (app), with fake permissions, login item, detection and a temporary config: no
  prompt until a click, the microphone hidden without dictation, the agents page hidden when nothing is
  found, found agents never connecting until chosen, Show Status, the summon shortcut saved and a
  taken one refused, community extensions hidden until allowed, hosts confirmed before enabling, and
  the `welcome` command closing the launcher and asking for the window.
- `tools/welcome/main.swift` renders every page in light and dark, plus the shortcut page's two
  warnings, from fictional data through `tools/render-vm.py`.
- `tools/installed-acceptance/guest/install.sh` notes the first launch's Welcome and marks it done, so
  the later phases see the launcher.

Not verified: the real Contacts, Calendars and Microphone prompts from the window in a signed build;
helper agent detection in the installed app; the Welcome window on a clean signed install.
