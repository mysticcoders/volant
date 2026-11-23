# ADR 0011: Local UI tests run in a headless VM

- **Status:** Accepted
- **Date:** 2026-09-15
- **Enforced by:** `Scripts/test.sh` routing UI checks to `tools/test-ui-vm.py`

## Context

UI tests drive windows, keyboard focus, hotkeys and the clipboard. Run on the owner's desktop, they steal focus while the owner works, can type into the wrong window, and mix test data with real data. Coding agents run tests often and without warning.

## Decision

Routine local UI checks and visual previews run in a dedicated headless Tart VM with no window, key injection, audio or clipboard sharing, using fictional data. If the VM is unavailable the run fails; it never falls back to host UI. Host UI testing (`VOLANT_HOST_UI_TESTS=1`), app relaunches and disruptive performance measurements need an explicitly agreed window with the owner. CI keeps hosted UI checks on its disposable runner.

## Consequences

- Agents can run UI tests at any time without interrupting the owner.
- VM results are functional and render evidence only. They do not establish hotkey delivery, signing, hardware integration or native performance; those need their own evidence.
- Setting up and maintaining the VM image (full Xcode, xcodegen) is a cost on each new machine.
- See docs/ui-testing.md.
