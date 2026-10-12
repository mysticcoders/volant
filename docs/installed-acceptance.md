# Installed acceptance in a disposable VM

`tools/installed-acceptance/run-vm.py` runs the installed-app checks for Settings and data (#2),
app shortcuts (#3) and translation (#5) against a notarized release DMG. It runs in a throwaway
clone of `volant-ui-xcode`, never on the owner's Mac and never with owner data.

```sh
tools/installed-acceptance/run-vm.py                      # newest DMG in website/public/updates
tools/installed-acceptance/run-vm.py --dmg path/to/Volant-0.2.6.dmg
tools/installed-acceptance/run-vm.py --only shortcuts     # shortcuts, translation or settings; repeatable
tools/installed-acceptance/run-vm.py --explore            # install only, keep the clone to look around
tools/installed-acceptance/run-vm.py --build --only settings   # an ad hoc build of this checkout
tools/installed-acceptance/run-vm.py --build ../other-worktree # an ad hoc build of another checkout
```

`--build` signs the Release app ad hoc, without the iCloud key-value entitlement (it needs a
provisioning profile), as `tools/memory/app-vm.py` does. Use it to check a fix before release;
Gatekeeper and signing are then not evidence, and the app reports the version in `project.yml`.

The runner prints an artifact folder that holds `summary.md`, `results.tsv` (section, PASS, FAIL
or NOTE, check, detail), one log per phase, screenshots in `shots/`, the unified log for
`com.mysticcoders.volant`, and any crash reports. It exits 1 when a check fails or a phase cannot
run. A full run takes about 20 minutes: language downloads need the guest's network, and Launch
at Login needs two reboots.

## How it works

- **Install:** the DMG is copied the way a Finder drag copies it, and Gatekeeper must report
  *Notarized Developer ID*. The first launch creates the container and `config.json`, then
  Sparkle's automatic checks are turned off so its prompt and update offers cannot cover the
  windows under test.
- **Guest setup:** Cirrus images ship with Spotlight indexing off, which leaves Volant's app list
  empty, so the install phase turns it on and waits for TextEdit to be indexed. It also turns on
  full keyboard access, makes TextEdit open an untitled window on reopen, and answers the macOS 15
  screen-capture prompt for the SSH session.
- **Resume:** loginwindow reopens apps from a snapshot that lags behind quits, so a reboot soon
  after quitting Volant can relaunch it even with Launch at Login off. Before each reboot the
  guest turns off loginwindow's relaunching and clears its list, so only the login item can start
  Volant. The login checks record how Volant was started and the loginwindow and background-task
  log around boot.
- **Input:** keys are posted by System Events from the guest's SSH session. They go through the
  window server like hardware keys and reach Carbon global hotkeys, but they are still synthesized
  events, not a physical keyboard.
- **Reading results:** each check reads what happened independently of Volant: the frontmost app,
  window-server window lists (`guest/windows.swift`), `config.json`, `sfltool dumpbtm` for the login
  item, the clipboard and the file system. Accessibility values are used to find controls and to
  read the translation view's status and result.
- **Accessibility claims:** System Events names elements by their title, so two buttons in one
  Settings row (both titled with the row's label) resolve to the first one. Checks about what
  VoiceOver can reach use `guest/axtree.swift`, which reads and presses elements through
  `AXUIElement` directly.
- **Another app's shortcut:** `guest/hold-hotkey.swift` registers a combination with
  `RegisterEventHotKey` from a separate process, standing in for another app.
- **Offline:** `pf` blocks everything except the SSH connection the test runs over.
- **Reboots:** the host shuts the clone down cleanly and boots it again; the guest has auto-login.

## What it covers and what it does not

| Area | Covered in the VM | Still needs the owner |
|---|---|---|
| App shortcuts (#3) | Record, deliver, hide, show, change and remove without restarting; conflicts with Volant's own shortcuts and with another process; bindings after a restart; keyboard-only editing from the launcher; reopening an app with no windows | A physical keyboard, including the owner's Caps Lock Hyper mapping; the owner's window manager |
| Settings and data (#2) | Status menu version and build; Settings keyboard navigation in light and dark; changing a setting; export, import, Reload Configuration and Reveal in Finder; Launch at Login on, removal in System Settings, restart, off, restart | Backup files with real data; login items on the owner's account; macOS releases other than the VM's |
| Translation (#5) | Download consent declined and accepted; translation and Copy; an installed pair offline; a missing pair offline and after reconnecting; Arabic results, copying and Arabic input | Visual review of right-to-left layout (screenshots are collected); Hebrew (not in the macOS 15 target list); Intel hardware |

The clone runs macOS 15.7.7 on Apple silicon. The results are evidence for that system, not for
other macOS releases or for Intel Macs.
