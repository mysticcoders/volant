# Hidden launcher preparation and real-use timing

The ordinary launcher now resets and lays out its home view once, 100 ms after dismissal, instead of leaving all cleanup for the next invocation. Work is cancelled on summon; a generation token and query snapshot reject stale tasks. Execution rechecks visibility, modal state and protected conversations/drafts. Index or usage changes can still require layout on the next summon. This trades a bounded amount of hidden main-thread work for reduced interactive waiting, not unlimited caching or repeated polling.

Two optimized fictional search/Return/fake-launch/dismiss/reopen runs, alternating enabled/disabled in one executable, measured:

| Run | Reopens per mode | Preparation off median | Preparation on median |
| --- | ---: | ---: | ---: |
| Initial | 20 | 25.929 ms | 15.401 ms |
| With passive log capture | 30 | 21.348 ms | 11.270 ms |

These are direct native handler-to-editor readiness measurements in an isolated fixture, not installed hotkey or screen-frame latency. Every first key, complete search, exact-once fake activation and dismissal assertion passed. First presentations are excluded and retained separately in raw data. Different runs have different warm caches and background activity, so the difference between runs does not measure logging overhead. No claim of zero-cost instrumentation is made.

The passive installed-app harness captures the real summon callback without sending an `NSWorkspace.openApplication` request or polling WindowServer. It uses monotonic durations and unified log wall timestamps, with only fixed source/readiness metadata. `other` fixture events are never presented as real hotkey measurements. Live collection of 62 fixture invocations validated the end-to-end log format and parser, with zero incomplete readiness events. Physical shortcut delivery and first-pixel timing require separate evidence; the installed Release was separately checked for search, dismissal, blank-query reopen and readable light/dark rendering. Its signature verified, and its executable SHA-256 is `d642a08085e02d3921765dac561a6e7e1ae8fd7dd97c41ee188b2cdea812e832`. Installed capture produced a successful `workspace` event; UI automation did not establish Carbon hotkey delivery, so normal-owner-use hotkey collection remains outstanding.

See [harness instructions](../tools/interaction-speed/README.md) for commands, isolation, measurements, and limitations. The native CI fixtures verify cancellation, stale input protection, no hidden focus theft and retained ACP/translation drafts. Keep those checks when changing delayed work: a faster callback is not sufficient if it mutates a newer query or steals focus.

Next gaps: collect real `hotkey` samples across normal owner use and long idle intervals; measure first-frame presentation separately; profile any remaining focus/rendering cost. The privacy-preserving timing stream deliberately excludes queries and app names, so scenario labels must be recorded separately using fictional or non-sensitive descriptions.
