# UI tests without interrupting the desktop

Routine local UI checks run in a dedicated headless Tart VM. No VM window, host key injection, audio or clipboard sharing is enabled. Functional and render results from the guest do not establish physical-device hotkey delivery, signing, hardware integration or native opening speed.

One-time setup (the Xcode image is a large download):

```sh
tart clone ghcr.io/cirruslabs/macos-sequoia-xcode:16.4 volant-ui-xcode
tart set volant-ui-xcode --cpu 4 --memory 8192
```

Start it once with `tart run volant-ui-xcode --no-graphics --no-audio --no-clipboard`. From another terminal, after the guest boots, run `tart exec volant-ui-xcode /bin/bash -lc 'brew install xcodegen'`, then `tart stop volant-ui-xcode`.

The image must have a logged-in desktop, Tart guest agent, full Xcode and `xcodegen`. Keep this VM dedicated to fictional test data. The smaller vanilla install-test VM lacks full Xcode. See [Tart's image catalog](https://tart.run/quick-start/).

Run the usual command:

```sh
Scripts/test.sh --base origin/main
# UI checks only:
Scripts/test.sh --ui only
```

Non-UI checks stay local. When UI checks are selected, `tools/test-ui-vm.py` snapshots tracked files (including modifications) and nonignored new files, boots the VM headlessly, runs `Scripts/test.sh --ci --ui only` in the guest and stops the VM afterward. The VM receives only a dedicated temporary artifact directory. Source archives, VM/test logs, rendered fixtures and xcresults remain there; the runner prints its path. Ignored local files/builds and `.git` are not copied. `VOLANT_UI_VM` selects another prepared VM. An already-running or unavailable VM is an error, never a reason to launch UI checks on the host.

`--ci` keeps hosted GitHub UI checks on their disposable runner. `VOLANT_HOST_UI_TESTS=1` is an explicit local escape hatch, requiring an agreed testing window with the owner. Do not use it just to get past VM setup failures. Native performance measurements and installed-app hardware checks need their own agreed window; VM timing is not a performance comparison.

`tools/ui-vm-dispatch-tests.py` verifies that successful and failed VM dispatch do not reach host UI execution. Builds, functional fixtures, rendered-screen inspection and installed hardware checks remain separate evidence.

Verified on 2026-09-15: `Scripts/test.sh --ui only` passed in `volant-ui-xcode` (macOS 15.7.7, Xcode 16.4, four cores, 8 GB). Both light/dark launcher fixtures and the selected XCTest rendering/editor tests passed. Logs, rendered fixtures and xcresults were collected, and Tart stopped the VM automatically. The first setup attempt failed because `xcodegen` was absent; installing it in the guest resolved the setup gap. No host UI fallback was used.

## Renders on a newer macOS — September 22, 2026

`tools/render-vm.py` renders native fixtures in `volant-render-27`, a clone of
`ghcr.io/cirruslabs/macos-golden-gate-vanilla:27.0` (macOS 27, no Xcode). The host compiles the
launcher, Actions and Settings fixtures against its own SDK, bundled with the compiled asset
catalog. The SDK is what decides whether AppKit and SwiftUI draw Liquid Glass. The guest only
runs the finished bundles. It is render evidence, not a test gate: whatever a fixture rendered
before a failed check is still collected.

Cirrus's vanilla images have no Tart guest agent. Setup is one-time: generate
`~/.ssh/volant-render-vm`, install it for `admin` (password `admin`) with `ssh-copy-id`, and confirm
`admin` is logged in on the console. The runner connects over SSH and starts fixtures in that GUI
session with `launchctl asuser`.

Offscreen captures (`cacheDisplay`) cannot draw Liquid Glass backdrop layers: a glass sidebar
selection comes out as a solid black capsule with its icon missing. Layout, type metrics and
glass-styled controls such as sliders and switches do render. The guest denies `screencapture`
(Screen Recording is not granted and SIP stays on).

## Settings renders from the window server — October 7, 2026

The black Settings sidebar row reported on the render VM was that offscreen artifact, not an app
bug. A window-server capture of the same window in the same guest draws the selected row as a
readable light gray capsule in light appearance and a dark gray one in dark, with its icon and
label. An app may capture its own windows without Screen Recording, so the Settings fixture's
`--render` mode now orders its window in and captures it with `CGWindowListCreateImage`, looked up at
runtime because it is marked unavailable from macOS 15. Each capture asserts that the selected row
is neither black nor indistinguishable from the rows around it. When the capture is unavailable
the fixture falls back to `cacheDisplay` and says so.

`--render` orders the window in without activating it, so these captures show the inactive-window
selection. The accent-colored selection of a key window still needs a look on a real display.

The launcher and Actions fixtures used to stop early on the render VM while CI passed. Four causes,
all fixed, and every render VM run now exits 0:

- `render-vm.py` started fixtures directly from the SSH session, and such a process never becomes
  the active app in the guest. The first launcher panel still became key, but a later panel did
  not, and the launcher correctly dismissed it rather than leave an unresponsive panel. Fixtures now
  start through LaunchServices with `open -n -W`, as an app would. `open` cannot report an exit
  status, so a run fails when its log contains a fixture `FAIL` or a Swift trap.
- On macOS 27 the Appearance form lays out taller, which left later color theme tiles such as Nord
  below the 500-point fold, where a synthesized click hits nothing. The fixture now scrolls a control
  into view before clicking it, as a person would.
- The launcher fixture is now bundled without Hello World, matching `tools/check-launcher.sh`, which
  runs it as a bare executable. A bundled Hello World matches "h" and its Extensions section ranks
  above Applications, so "Home ranks first for each query prefix" failed only in the VM.
- The Actions fixture copies Hello World into a folder whose URL has no trailing slash. On macOS 27
  that URL can stay unslashed after resolving symlinks, so `ExtensionManager`'s check that a manifest
  sits inside its folder compared unequal URLs and refused the copy. The check now compares resolved
  paths, which keeps refusing a manifest symlinked out of its folder. Folders listed from disk end
  in a slash, so installed extensions were not affected.
