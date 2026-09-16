# Launcher layout profile — 2026-09-15

## Result

Source `938d98f` conditionally reuses the retained launcher editor. It requires an unchanged empty query, result sections (including metadata), selection, and displayed text. Missing or stale editors, changed results/selection, and other modes retain forced layout. SwiftUI may still lay out and draw later; skipping the synchronous call does not eliminate all rendering work.

Three alternating candidate/baseline rounds used the same `/Applications/Volant.app` path, 20 reopens each, with clean process switches and the same real configuration. No builds or UI tests ran during measurement. Fixed-content signposts were streamed live and matched to request timestamps and process IDs.

| Measurement | Baseline median | Candidate median |
| --- | ---: | ---: |
| Request to WindowServer visibility, 60 each | 71.5 ms | 60.9 ms |
| Preparation, 57 matched each | 1 ms | 1 ms |
| Window ordering | 2 ms | 2 ms |
| Editor preparation (baseline forces layout) | 16 ms | <1 ms |
| Focus | 3 ms | 6 ms |
| Total synchronous opening | 22 ms | 9 ms |

End-to-end improvement: 10.6 ms / 14.8%. End-to-end p95 (nearest rank) changed from 89.3 to 81.9 ms. The sub-50 ms visibility target remains unmet. The compact trace has millisecond resolution; a displayed zero is below that resolution, not literally zero work. Component medians need not sum to the median total.

Candidate forced layout in 3/57 matched reopens; the remaining 54 reused the editor. The three initial cohort reopens per build have no matching preparation signpost sequence, consistent with the separate already-visible-window reopen path. All 60 remain in the end-to-end statistics; only the 57 timestamp-matched sequences contribute to internal stage statistics. The script rejects missing non-initial samples, duplicate matches and malformed timing rows.

Request to instrumented toggle entry still took about 26–28 ms median. This interval includes OS request delivery and any work queued before the handler; it is not evidence that all of it is LaunchServices overhead. Actual hotkey-to-first-pixel, compositor timing, first-frame freshness, and physical first-key latency have not been measured. No Raycast rerun was performed in this experiment.

## Validation

`Scripts/test.sh --base origin/main` passed, including native logic and light/dark panel fixtures. New tests send the first key synchronously after reopen, without a run-loop grace period, after empty search, a previous query, emoji, and dictionary. They verify the key remains after the following SwiftUI update. Existing tests cover visible highlight, repeated summon, clicks, modal guards, and active ACP/draft preservation. Signed universal Release build passed.

Installed appearance, typing and signature checks are recorded in [PR #26](https://github.com/mysticcoders/volant/pull/26) before merge. No public DMG release is included.

## Reproduction and limitations

The adjacent directory contains exact harnesses, CSVs, executable hashes, process IDs, live fixed-content signposts and the summarizer. Run `python3 docs/layout-profile-2026-09-15/summarize.py docs/layout-profile-2026-09-15`. The signpost timestamp parser explicitly uses the host's America/Los_Angeles timezone.

Baseline is main `29956fa`, binary SHA-256 starting `07b519b7`. Host: Mac16,6, Apple silicon, 128 GiB RAM, macOS 27.0 (26A428), pinned Herdr overview and existing configuration. Filesystem caches and background workload were not controlled; no VM was used. Raw signatures identify the exact candidate for every round.

An auxiliary startup trial aborted because the target restarted before the timed request; the harness refused to continue and restored the baseline. Its partial CSVs are retained for audit but excluded from this report. `complete-warm-comparison.sh` completed only the remaining third warm cohort, appending its trace. No failed sample was retried or removed from the reported warm data. Fresh-process startup performance is not assessed here.

## Next measured targets

- Profile automatic SwiftUI layout/drawing after focus to distinguish work avoided from work deferred.
- Measure the actual global shortcut through the first rendered frame and first-key delivery; NSWorkspace timing includes a different delivery path.
- Keep the editor-readiness and stale-state regressions when considering further caching or preparing views while hidden. Matching text alone does not prove results, mode, or selection are ready.
