# Opening optimization — 2026-09-15

## Changes

- Remove the fixed 600 ms normal-startup timer. Present on the next main queue turn, with a visibility guard against a duplicate reopen. Explicit preview/notes launch flags retain their existing timing.
- Subscribe to app-index updates after publication. Refresh visible suggestions or ordinary app searches while preserving selection identity; leave specialized commands and forms untouched.
- Skip publishing identical normalized result sections. Equality includes row metadata, not only identity. Clearing a search rebuilds suggestions once instead of twice.
- Add content-free OS signposts for preparation, window ordering, layout, and focus (`com.mysticcoders.volant`, category `Opening`). These measure app-side work, not rendered pixels.

## Experiment and prevention

Moving Herdr connection setup to the next main turn did not help: 60 trials per build at the same installed path measured baseline median 58.9 ms / p95 82.4 ms versus candidate 66.7 / 91.4 ms. That change was removed. The result does not establish the cause of the earlier Raycast comparison gap.

Comparing `/Applications` with a temporary build path introduced a location difference. Final comparisons alternate builds at `/Applications/Volant.app`, preserve the original bundle, verify binary hashes, and restore the original afterward. UI tests and builds finish before timing. No VM, cache purge, or owner-data fixtures are used.

## Validation and measurements

Final source: `365b59f`. Three alternating candidate/baseline rounds at the same installed path, 20 reopens and 5 fresh-process starts per round. Full raw CSV, executable hashes, exact benchmark and switching harness are alongside this report.

| Metric | Baseline | Candidate |
| --- | ---: | ---: |
| Reopen median (60 each) | 63.3 ms | 65.9 ms |
| Reopen p95, nearest rank | 114.1 ms | 80.8 ms |
| Reopen range | 40.3–184.8 ms | 42.4–153.7 ms |
| Startup median (15 each) | 1011.6 ms | 510.9 ms |
| Startup range | 989.1–1026.9 ms | 377.3–535.9 ms |

Startup median improved 49.5%. Warm median did not improve; the sub-50 ms target remains unmet. The lower observed warm p95 is descriptive, not proof of a stable tail-latency improvement. Cohort medians varied; no causal claim about Raycast's earlier advantage follows.

`Scripts/test.sh --base origin/main` passed native logic and scoped light/dark UI checks. Regression fixtures cover identical-list suppression, changed-metadata publication, reset, selection preservation and protecting specialized queries from index refresh. Existing native fixtures cover repeat summon, typing, clicks, modal guard, active ACP/draft preservation and positioning. Signed universal Release build and installed `codesign --verify --deep --strict` passed.

The final candidate was installed at `/Applications/Volant.app` and directly inspected at 750×480 under both actual OS Light and Dark settings: readable search results, selected row, branding, footer controls, and typing after summoning via the automation interface. Original Dark setting restored; Escape dismissal observed. These checks do not measure first-key latency or prove physical global-hotkey delivery. No new public DMG was distributed. The prior app is preserved at `/tmp/volant-installed-final-ab/original.app`.

Host: Mac16,6, Apple silicon, 128 GiB RAM, macOS 27.0 (26A428), existing owner configuration, pinned Herdr overview. Baseline binary SHA-256 starts `03f58b2d` (main `0a5771f`, app 0.1.3 build 5). The timing endpoint remains an NSWorkspace open request to WindowServer visibility, not hotkey-to-first-pixel or keyboard readiness. Fresh-process startup uses warm OS caches. Hardware and existing user configuration are shared; background workload is not controlled.

Two retained signpost sequences from the final installed manual smoke check show preparation at 0–1 ms, window ordering at 2–7 ms, forced layout at 29–39 ms, and focus at 2–4 ms. This small manual sample is not the 60-trial benchmark; it identifies forced layout as the next profiling target. Do not remove that layout call without verifying initial text-field installation, stale-query clearing, first-key delivery, and frame rendering.

## Next gaps

- Actual global-shortcut-to-rendered-frame measurement and first-key latency.
- Attribute window ordering/layout costs using the new signposts before choosing icon caching or pre-layout changes.
- Check default startup with login launch, multiple displays, and an active modal permission prompt; ordinary installed launch and isolated panel fixtures are separate evidence.
