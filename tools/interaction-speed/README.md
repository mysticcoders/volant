# Real-use summon timing and interaction fixture

## Passive installed-app capture

From the repository root, with a build containing `LauncherOpeningTrace` installed:

```sh
tools/profile-summons.sh /tmp/volant-real-use 120
```

Use the normal Show Volant shortcut, search, launch, dismiss and return while the script listens. It sends no keys, polls no windows, records no screen, and does not restart Volant. Output includes raw fixed-content signposts, installed binary identity and a summary grouped by source. Ctrl-C also attempts to produce a summary. Use a new output directory each time; duration is 1–3600 seconds.

`source=hotkey` starts inside the registered summon callback, before lazy panel creation, and ends once the window is key and has an `NSTextView` editing responder. Other sources start at panel toggle entry. This is **handler-to-editor readiness**, not physical key arrival, input-event queue delay, first rendered frame, GPU presentation or display scanout. Successful toggles that close the window are not opening samples; app-modal guards do not emit a summon interval. Incomplete/cancelled readiness events are counted separately, not silently mixed into successful timings.

Durations use monotonic uptime; unified logging adds wall timestamps for correlation. No query, result, app identity, clipboard contents, draft, provider message or raw error is in the application event payload. The log includes normal process/timestamp metadata. No telemetry is uploaded. The capture script writes the stream outside the app; Volant performs no synchronous log-file writes.

No instrumentation is literally zero-overhead. This uses a few clock reads and fixed signposts instead of an external open request, polling loop or per-frame screenshots. Collector activity can still affect the host. Measure under comparable load; do not run builds or other UI automation during timing. The timing does not prove pixels are ready; pair it with interaction and visual checks.

## Automated isolated interaction cycles

```sh
tools/profile-interaction.sh /tmp/volant-interaction 30 250 /Applications/Volant.app
```

Builds an optimized native fixture bundle from current source and copies the specified app's **compiled asset catalog**. It alternates hidden preparation enabled/disabled in the same executable, reversing order each cycle. Each cycle summons, sends the first key immediately, types a fictional search, presses Return, verifies exactly one fake app activation and dismissal, waits the requested idle interval, and repeats. First presentation is reported separately from subsequent cycles. No real target app is launched; no owner data, global shortcuts, clipboard monitoring, updater, or normal app delegate is started. Fixture notes/clipboard/usage are isolated in the output directory.

The baseline flag disables only hidden preparation, not the previously shipped layout optimization. Default idle is 250 ms; accepted cycle counts are 1–200, idle 0–60000 ms. Zero idle is useful for a burst stress test but alternation between two panels still takes time; it is not a physical zero-delay hotkey replay. The native regression fixtures also exercise immediate reopen without pumping the run loop.

`handler_to_editor_ready_ms` wraps the direct panel call and verifies its responder. `first_key_delivery_ms` measures in-process native key dispatch through the model update, including any synchronous search triggered by that key. These are functional/native fixture measurements, not full installed-app or real target application launch measurements. The fixture cannot prove physical Carbon delivery, screen presentation timing or field-editor readiness under every OS/input method.

The app performs one cancellable hidden preparation 100 ms after ordinary dismissal. Rapid reopen cancels it; state changes invalidate it. Active ACP sessions, ACP drafts, translation drafts and connectivity work/forms retain their original behavior. No repeating idle timer or extra result/image cache was added.

## Automated safeguards

`Scripts/test.sh --base origin/main` runs parser tests and selects native UI fixtures for changes to the interaction harness. Those fixtures cover search/Return/dismiss/idle/reopen, immediate first-key delivery, stale task rejection, no hidden focus theft, and ACP/translation draft preservation in light/dark. `tools/interaction-speed/check.py` rejects invalid timings and verifies failures and sources remain separate. The profiling executable itself is opt-in and is not a timing gate on shared CI runners.
