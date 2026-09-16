# Local Volant opening speed — September 15, 2026

Follow-up: [matched Raycast comparison](opening-comparison-2026-09-15.md) uses identical Finder-focus preparation for both apps. Use that dataset for comparisons; this earlier Volant-only run remains an audit record.

Measured on the owner’s Mac, not a VM. The existing Tart VMs were stopped and no test VM was started. Installed app: 0.1.3 build 5, development Release from main `0a5771f`, executable SHA-256 `03f58b2dfb7dbba984513924c12fb2c262817eb1ead5ed789c916b564a92090c`. Host: Apple silicon Mac16,6, 128 GiB RAM, macOS 27.0 build 26A428. Existing configuration, data, app index and pinned Herdr overview were used; the harness did not edit configuration or app data. App settings confirmed ⌘Space and show-on-launch enabled.

## Metric

**macOS application open request → launcher registered as visible by WindowServer.** This includes Launch Services/application handling and window publication. It does not establish first rendered pixels, display scanout, search completion or keyboard readiness.

The [reference image](https://pbs.twimg.com/media/HSPSSYgW8AAby5G?format=jpg&name=large) measures shortcut → first visible frame. Our trigger and endpoint differ, and its hardware/setup are unknown; do not label Volant faster/slower than those plotted apps from this result.

An initial read-only event-tap attempt received no automated shortcut events, so it produced no usable shortcut timings. The retained benchmark does not log keys. An initial visibility detector incorrectly looked for ordinary window level 0; the actual launcher is floating level 3. Those failed trials were discarded as invalid detector runs, not slow application results. A later development harness run had a 67 ms reopen median; it was superseded by the finalized source and repeated runs recorded below, not mixed into their statistics.

## Final runs

| Test | Trials | Median | P95 (nearest rank) | Minimum–maximum |
| --- | ---: | ---: | ---: | ---: |
| reopen | 60 | 46.8 ms | 95.9 ms | 33.2–193.4 ms |
| startup | 15 | 1013.6 ms | 1029.6 ms | 998.5–1029.6 ms |

Three identical complete runs: reopen medians **48.3, 47.4, 45.1 ms**; fresh-process medians **1019.3, 1013.0, 1012.8 ms**. First reopen trials were **193.4, 189.7, 101.9 ms** and remain included. These first-opening outliers deserve separate investigation; the data does not identify their cause. Five startup observations per run are insufficient for a robust tail estimate.

[Raw runs, binary/environment identity and per-run summaries](opening-speed-2026-09-15/) are committed alongside the report. The app was left running from `/Applications` after the final trial.

The benchmark compiled and all 75 final trials completed with no timing errors; CSV count/order/range checks passed. Standard repository validation is recorded in the PR. The change touches tools/docs only, so UI test selection remains off; the measured native launches are performance evidence, not visual-quality or keyboard-readiness verification.

## Method and interpretation

See [reproducer](../tools/launch-speed/README.md). The helper uses a monotonic clock, confirms hidden/terminated state, then checks target PID, floating level, aspect ratio, dimensions and alpha through `CGWindowListCopyWindowInfo`. Nominal polling interval is 2 ms; it adds observer delay and jitter rather than providing frame-accurate timing. The app launch completion callback is not required before looking for the window.

Each run has 20 reopen trials and five fresh-process starts, with 300 ms settling between phases. Fresh-process starts use a graceful quit and warm filesystem/system caches; no machine reboot, cache purge, fresh user account or first-run installation is involved. No warmup/first-trial samples are removed. Normal background host activity was not frozen. The Settings dialog was closed before measuring. Native sessions/Caffeinate can end on restart; the harness never force-quits.

## Next optimization candidate

`AppDelegate.applicationDidFinishLaunching` schedules normal show-on-launch after **0.6 seconds**; explicit `--show` uses **0.8 seconds**. This benchmark uses ordinary launching, not `--show`. The fixed delay is a concrete startup cost worth investigating. Replace it only with a verified readiness/focus condition, and test first typing/clicks, modal handling and repeated summon before claiming a win. Global shortcut opening already follows a different path and does not incur that startup timer.

No app optimization or new release is included here. Remaining work: genuine shortcut-to-presented-frame measurement, input-ready timing, and controlled before/after tests of startup scheduling. Display refresh/rendering and host differences prevent comparison with the reference chart.
