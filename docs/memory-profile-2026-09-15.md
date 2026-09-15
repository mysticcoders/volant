# Controlled memory profile — September 15, 2026

Production source: `1fd0fcf` (dictionary merged). Measurements use an optimized, ad-hoc signed fixture built from production sources with a separate entry point. This is component profiling, not a signed installed-app UI stress test. The running owner app and helper were sampled read-only and left untouched.

## Installed-app snapshot

On this machine, `/Applications/Volant.app` **0.1.2 build 4** (PID 99871) reported 47.8 MiB physical footprint, 49.4 MiB lifetime peak, and approximately 116 MiB RSS. Its agent helper (PID 99874) reported 4.56 MiB physical footprint, 4.66 MiB lifetime peak, and approximately 11 MiB RSS. These were separate near-time `ps` and filtered `vmmap -summary` samples, not a controlled idle baseline. No personal data, provider tokens, process arguments or memory contents were captured. No extension helper was present in the sampled process list.

## Reproducible workloads

See [profiler instructions](../tools/memory/README.md). Six workloads run three times, each in a fresh process, using fictional stores and an injected clipboard key. macOS 27.0 build 26A428, Apple silicon Mac16,6, 128 GiB RAM, Swift 6.3.3; results may differ on macOS 15, Intel and smaller-memory machines.

Counters: physical footprint, RSS, live malloc allocation bytes across all zones, and 5 ms sampled footprint peaks. The CSVs record fixture generation separately, plus explicit release, outer autorelease-pool drain and diagnostic allocator-relief stages. Short peaks may be missed. No machine-dependent pass/fail memory threshold is introduced.

The initial experiment omitted an outer autorelease-pool drain and appeared to retain decoded image allocations after clearing the array. The final harness adds that boundary before judging post-workload retention; the image allocations still remained after draining, so autorelease lifetime alone does not explain them. A CLI fixture without the application event loop must not be used to claim a production leak from undrained Cocoa autoreleases.

## Findings

Three-run medians; full phase tables and counters are in [raw results](memory-profile-2026-09-15/summary.md).

| Workload | Measured result | Interpretation / priority |
| --- | --- | --- |
| 11 large clipboard images plus one text row | 85.8 MiB live heap while rows are held; 0.65 MiB after releasing rows. Text-only searches take ~36–38 ms each. | **First:** skip image blob reads/decryption for text-only queries; move rows toward metadata plus bounded thumbnails. The source currently decrypts before checking image kind/query eligibility. |
| Three 4096×4096 full-size image decodes | ~195 MiB live heap during decode, ~194 MiB remains after pool drain; 138.6 MiB sampled footprint peak. | **First:** pixel/decode budgets and bounded image rendering. This forced-raster fixture is not a UI leak proof; `leaks` found no unreachable allocations and retaining-owner attribution remains pending. |
| 1,000 notes / ~61 MiB Markdown | ~79 MiB live heap loaded; footprint grows from 84 to ~167 MiB across reloads. Live heap returns to 0.29 MiB on release. | **Second:** avoid rereading unchanged clean notes, then assess metadata/lazy loading. Preserve dirty drafts, pending writes and full-text search. Stable live heap across reloads does not establish an object leak. |
| 100 emoji model cycles | 2.23 MiB live heap after 100 cycles, 1.72 MiB after release/pool drain; footprint ~9.5 MiB at end. | Lower priority in this component run; full picker/window and graphics churn still unmeasured. |
| 400 ACP snapshot encode/decode/equality cycles | Live heap stays ~3 MiB across all four batches, falls to 0.31 MiB on release; ~5.4 ms per full cycle. | Lower memory priority here. Measure actual XPC/provider polling before changing transport. |

These are total fixture heap/footprint counters at each phase, not independent additive per-feature costs. The image fixture's ~194 MiB live allocations versus ~14 MiB settled footprint particularly illustrates that allocations, RSS and footprint are not interchangeable. Diagnostic allocator relief did not materially reduce settled footprint. No production cache-purge change is proposed.

### Concrete implementation backlog

1. Add a deterministic clipboard regression fixture asserting text queries exclude image payload work, then optimize query selection/decryption. Measure against these same fixtures.
2. Add explicit pixel/decode limits and on-demand thumbnails; profile both large noisy and highly compressible images and verify actual launcher rendering separately.
3. Add unchanged-file note reuse before a larger lazy-loading design. Run dirty-write/reload/failure persistence tests and preserve search semantics.
4. Finish installed picker/UI and XPC/helper profiling and obtain allocation-stack attribution before labeling any retained memory a leak.

### Validation

`Scripts/test.sh --base origin/main` passed all 66 native tests plus the routing/volume/ACP checks. The classifier selected `native=true, ui=false`; no UI override or appearance run was used. Optimized fixture compilation, all 18 final workload processes, CSV completeness/counter assertions, shell syntax and diff checks passed. Raw CSVs contain fictional workload metrics only. The repository PR must still pass its required checks before merge.

## Limits and next work

- Instruments Allocations recording could not attach to the fixture process. No allocation-stack or VM-category attribution is claimed. A separate `leaks --atExit` image-decode run completed and reported **0 unreachable leaks / 0 leaked bytes**, while ~194 MiB remained allocated. This suggests reachable retained storage/cache rather than proving an unreachable leak, but it does not identify the retaining owner or prove the installed app leak-free. The failed Instruments trace is not evidence of a completed recording. Final counter-only repetitions were collected serially after diagnostic tools exited.
- Emoji measurements exercise model queries/selection/reset, not SwiftUI cell creation, window opening or graphics resources. A 100-cycle installed picker/window test is still needed.
- The image workload forces full-size raster decoding; it does not prove the thumbnail UI retains those buffers. Solid images demonstrate why compressed input size is insufficient as a decoded-size budget; footprint/RSS/live heap differ substantially and should not be conflated.
- ACP measurements cover sequential encode/decode/equality with fictional state, not actual XPC/helper/provider polling, streaming or UI rendering. No owner conversation was used.
- Large-note and clipboard fixture generation can leave allocator pages resident before measured reads; live heap and phase deltas are more useful than attributing the entire process footprint to result rows.
- Installed long-duration growth, provider/helper workloads, allocation stacks, Intel and constrained-memory runs remain in issue #17. No production optimization or release is part of this profiling change.

## References

Apple distinguishes footprint from resident clean mappings and recommends examining allocations and VM behavior: [Profile and optimize your game's memory](https://developer.apple.com/videos/play/wwdc2022/10106/), [Gathering information about memory use](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use). Counter semantics and allocator-relief behavior were also checked against the installed macOS SDK headers.
