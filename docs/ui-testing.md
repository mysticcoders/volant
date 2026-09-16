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
