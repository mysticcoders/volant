# Matched Volant / Raycast opening comparison — September 15, 2026

Measured on this Mac, not a VM: Apple silicon Mac16,6, 128 GiB RAM, macOS 27.0 (26A428). Installed apps: Volant 0.1.3 build 5 (development Release, dictionary included) and Raycast 2.4.1.0 build 0. Binary hashes, harness source hashes and environment files accompany every reopen cohort; startup hashes are recorded separately. No product code, preferences, extensions, notes or clipboard contents were edited by the benchmark. Both apps were left running.

## Results

| App | Reopen median (60) | Reopen p95 | First reopen samples | Fresh-process median (15) | Fresh-process range |
| --- | ---: | ---: | --- | ---: | --- |
| volant | 69.6 ms | 94.8 ms | 185.3, 94.8, 107.1 ms | 998.2 ms | 950.3–1018.6 ms |
| raycast | 55.3 ms | 69.0 ms | 95.6, 72.5, 73.0 ms | 1068.0 ms | 997.2–1080.5 ms |

Each app has three complete cohorts: 20 reopens and five fresh-process starts per cohort. No first trial is discarded. “First reopen” means the first sample in a cohort with the app **already running**, not a fresh process or the first-ever launch after installation.

Raycast's median reopen window publication was about **14.3 ms earlier** on this request path. Volant's median fresh-process window publication was about **69.8 ms earlier**. These differences do not establish which app presents usable content sooner.

## Matching and limitations

The clock starts immediately before `NSWorkspace.openApplication` and stops when WindowServer reports the target launcher on screen. Both apps use the same monotonic clock and nominal 2 ms polling. The predicate matches PID, observed window level, aspect ratio, minimum size and nonzero alpha: Volant level 3 / 750×480; Raycast level 8 / 750×475. App settings and auxiliary windows do not qualify. Reopen cohorts enforce the same process throughout.

Before every reopen, the helper focuses Finder, requests target-app hide, verifies that the launcher is no longer on screen, and waits 300 ms. Preparation is outside the measured interval. Raycast did not reliably dismiss through app-hide alone, so **both apps** use this matched preparation. Three reopen pairs were run in alternating order: Volant 1, Raycast 1, Volant 2, Raycast 2, Volant 3, Raycast 3.

Startup cohorts used the same normal quit request, verified OS process exit with signal-zero liveness checks, and refused forced termination or an automatic restart before the timed request. Raycast's initial `NSRunningApplication.isTerminated` check did not settle; OS PID-exit verification resolved the measurement problem. Startup order was Raycast 1, Volant 1, Raycast 2, Volant 2, Raycast 3, Volant 3. Warm OS/filesystem caches were retained; these are not post-reboot cold launches. Normal app startup services and the owner's existing app configuration were included.

The endpoint is **window publication, not first rendered pixels, display scanout or keyboard readiness**. The supplied Raycast/Tinycast image uses shortcut → first visible frame. Its trigger and endpoint differ, so this table cannot confirm or contradict that chart. In particular, a window may exist before all native/web content paints. Background host load and observer overhead were not removed; the startup sample count is small.

The earlier Volant-only [run](opening-speed-2026-09-15.md) used app-hide without Finder focus and had a 46.8 ms median. Use the matched data above for this comparison; the earlier results remain available for audit. First-sample behavior is visibly variable and its cause has not been isolated.

## Reproduce and evidence

`tools/profile-opening.sh NEW_DIRECTORY volant reopen` or `... raycast reopen` measures a 20-trial reopen cohort. Omit `reopen` to include five clean restarts. The apps and Finder must already be running. Complete active work before restart tests; normal quits can end in-memory sessions. The tool never force-quits or posts keys and does not capture screen pixels or app contents.

[Raw results](opening-comparison-2026-09-15/summary.md) include every sample. `benchmark-reopen.swift` and `benchmark-startup.swift` preserve the exact measured source; the reopen snapshot hash was checked against its environment file. The only later timing-helper change added OS PID liveness checks for startup and target discovery. `python3 tools/launch-speed/compare.py docs/opening-comparison-2026-09-15` validates counts/order/timing bounds and reproduces this table.

All 150 final matched trials completed. The optimized helper and CSV checks passed. Repository native checks are required through the PR; no production UI changed, so UI job selection remains off. These launches do not establish visual quality or keyboard readiness.

## Next concrete investigations

- Replace Volant's fixed 600 ms normal-startup timer only after proving an equivalent readiness/focus condition and first-input behavior.
- Attribute the slower first reopen samples using native signposts/allocations and controlled idle intervals.
- Measure actual global-shortcut delivery through presented frames and input readiness before making competitive UX claims.
