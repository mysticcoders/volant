# Extension helper memory — October 30, 2026

Issue #66. The owner saw VolantExtensionHost at about 18 MB, still resident after community extensions were turned off. That alone is not a leak verdict, and the helper had no explicit idle shutdown. This profile measures what the helper's engine costs per run, whether it grows with repeated runs, and how far it settles on its own, before deciding on idle cleanup. Fictional inputs and the repository's sample modules only; no owner data, owner process, installed app or signed helper.

## Method

`tools/profile-memory.sh OUTPUT` now builds a second fixture, `VolantExtensionMemoryProfile`, from the helper's production `ExtensionHost.swift` and `WASICommand.swift` (as `tools/check-extensions.sh` compiles them) plus `tools/memory/extension-host/main.swift`. It is optimized and ad-hoc signed with the hardened runtime and the helper's `allow-jit` entitlement. It links only Foundation, JavaScriptCore and VolantCore, like the helper, but has no XPC listener, launchd lifecycle or sandbox. The counters are shared with the app fixture (`tools/memory/measure.swift`): physical footprint and RSS from `TASK_VM_INFO`, footprint sampled every 5 ms for peaks, live malloc bytes from `malloc_zone_statistics`, and allocation churn from `malloc_logger`. JavaScriptCore's own heap and WebAssembly memory are not malloc allocations, so they show in footprint but not in live heap.

`VOLANT_MEMORY_SCENARIOS="ext-idle ext-hello ext-base64 ext-mixed ext-bursts ext-parts"` ran each workload in three fresh processes; tables show medians. Each run calls `ExtensionHost.run` or `runCommand` with a fresh fictional input ("Fixture N") and checks the output.

- **ext-idle:** the engine created, no run, then 15 s idle.
- **ext-hello:** the bundled Hello World (ABI 1, 18 KB module), one first run, then 200 runs in batches of 25, then idle phases ending 1, 5 and 15 s after the last run.
- **ext-base64:** the community Base64 sample (ABI 2 through the WASI adapter, 1.36 MB Javy module), the same phases.
- **ext-mixed:** rounds of Hello World, the clipboard test with `clipboard.write` (no client, so the callback goes nowhere), the list fixture's plan and Base64; 100 rounds (400 runs), then idle.
- **ext-bursts:** three bursts of 25 mixed rounds, each followed by 10 s idle, to see whether settled memory ratchets.
- **ext-parts:** 25 runs each of a bare `JSContext`; the module bridged as `[UInt8]` (the old path); the module as one `Uint8Array` (the new path); that plus `WebAssembly.Module` compilation; and a full Base64 run.

## What the first profile found

The engine's largest cost was not the context or the module but how the module reached JavaScript. `ctx.setObject([UInt8](module), …)` bridges to an `NSArray` of boxed numbers and then a JavaScript array, one element per byte; the scripts then copied that into a `Uint8Array`. For the 1.36 MB Base64 module that was 11.7 MiB of allocations and about 40 ms of every 43 ms run (`ext-parts`, `array_bytes_25`: 292 MiB and 990 ms for 25).

## What changed

`ExtensionHost` now hands the module and the input to JavaScript as one `Uint8Array` each (`JSObjectMakeTypedArray`, one `memcpy`), and both scripts compile and read those directly. The module still runs in a fresh context per invocation; validation, limits, imports, the watchdog and the WASI profile are unchanged. Output still returns through a JavaScript array; it is at most 256 KiB and was not measured as a cost here.

## Results

Per-run figures are from the last batch of 25 (the mixed figures are per round of four runs). Settled is 15 s after the last run.

| Workload | Before | After |
| --- | --- | --- |
| Hello World, warm run | 1.43 ms, 0.18 MiB allocated | 0.96 ms, 0.02 MiB allocated |
| Hello World, first run in a process | 11.3 ms | 7.0 ms |
| Base64, warm run | 42.9 ms, 13.0 MiB allocated | 5.5 ms, 1.3 MiB allocated |
| Base64, first run in a process | 60.7 ms | 13.9 ms |
| Mixed round (four runs) | 49.0 ms, 13.6 MiB allocated | 8.9 ms, 1.4 MiB allocated |
| Base64 footprint while running (sampled peak) | 91.2 MiB | 60.6 MiB |
| Mixed footprint while running (sampled peak) | 96.6 MiB | 65.8 MiB |
| Base64 footprint, settled | 20.1 MiB | 9.9 MiB |
| Mixed footprint, settled | 21.1 MiB | 9.6 MiB |
| Hello World footprint, settled | 7.0 MiB | 6.8 MiB |

After the change, medians in MiB:

| Workload | Phase | Footprint | RSS | Live heap | Sampled peak |
| --- | --- | ---: | ---: | ---: | ---: |
| ext-idle | baseline (process start) | 2.13 | 6.36 | 0.10 | 2.13 |
| ext-idle | idle 15 s, no run | 4.09 | 10.05 | 1.53 | 4.09 |
| ext-hello | first run | 11.88 | 18.47 | 1.61 | 11.88 |
| ext-hello | 25 runs | 17.72 | 24.33 | 1.65 | 17.72 |
| ext-hello | 100 runs | 20.17 | 27.02 | 1.71 | 20.31 |
| ext-hello | 200 runs | 21.84 | 28.69 | 1.80 | 21.84 |
| ext-hello | idle 1 s / 5 s / 15 s | 20.55 / 9.20 / 6.77 | 28.69 / 28.70 / 28.11 | 1.80 / 1.70 / 1.69 | |
| ext-base64 | first run | 36.05 | 42.67 | 1.61 | 36.05 |
| ext-base64 | 25 runs | 57.16 | 66.34 | 1.66 | 57.16 |
| ext-base64 | 100 runs | 60.39 | 70.50 | 1.72 | 60.39 |
| ext-base64 | 200 runs | 60.33 | 72.14 | 1.81 | 60.33 |
| ext-base64 | idle 1 s / 5 s / 15 s | 52.52 / 13.58 / 9.89 | 72.14 / 72.17 / 71.61 | 1.80 / 1.71 / 1.70 | |
| ext-mixed | 100 rounds | 65.24 | 76.28 | 2.02 | 65.78 |
| ext-mixed | idle 15 s | 9.56 | 75.72 | 1.81 | |
| ext-bursts | burst 1 / 2 / 3, running | 61.16 / 17.14 / 15.06 | 70.48 / 73.27 / 73.94 | 1.76 / 1.79 / 1.83 | 61.16 / 17.14 / 15.06 |
| ext-bursts | burst 1 / 2 / 3, after 10 s idle | 12.22 / 11.99 / 11.99 | 69.91 / 72.81 / 73.50 | 1.71 / 1.74 / 1.77 | |
| ext-parts | 25 bare contexts | 8.55 | 15.05 | 1.62 | 8.55 |
| ext-parts | + 25 modules as `[UInt8]` (old) | 51.86 | 59.02 | 1.63 | 52.52 |
| ext-parts | + 25 modules as `Uint8Array` (new) | 51.95 | 59.09 | 1.64 | 51.95 |
| ext-parts | + 25 compilations | 90.94 | 98.14 | 1.64 | 90.94 |

In `ext-parts` the phases run in one process, so footprint accumulates; the per-phase costs are in the churn and time columns of the full summary: a bare context is 0.5 ms and 0.04 MiB, the old bridge 39.6 ms and 11.7 MiB, the new copy 0.66 ms and under 0.01 MiB, compilation about 1.5 ms with no malloc churn (JavaScriptCore allocates it outside malloc).

## Reading the numbers

- **It plateaus.** Base64 footprint holds at about 60 MiB from 75 to 200 runs, mixed at about 65 MiB. Hello World still creeps by about 0.3–0.5 MiB per 25 runs at 200 runs, which it returns when idle.
- **It settles on its own.** Within 5 s of the last run JavaScriptCore returns most of it: footprint falls to about 7–10 MiB by 15 s, from 2.1 MiB at process start and 4.1 MiB after creating the engine. RSS stays high because the returned pages are reusable rather than unmapped; footprint is the figure memory pressure acts on. The diagnostic `malloc_zone_pressure_relief` changed nothing, since the retained memory is not malloc's.
- **Bursts do not ratchet.** Settled footprint after three bursts was 12.2, 12.0 and 12.0 MiB, and later bursts peaked far lower (17 and 15 MiB) than the first (61 MiB), because JavaScriptCore reuses what it kept.
- **Live heap grows slightly.** About 0.3 KB of malloc memory per run stays after idle (1.71 to 1.77 MiB over 200 runs in `ext-bursts`). A `heap` comparison of two settled phases attributed it only to non-object allocations; with stack logging off it is unattributed. At that rate 10,000 runs would hold about 3 MiB. It is recorded, not a leak verdict.
- **The 16 MiB linear-memory cap is not the process total.** A running Base64 helper held about 60 MiB, most of it JavaScriptCore's compiled code and heap, not the module's linear memory.
- The owner's 18 MB is consistent with a helper that ran Base64 under the old bridge and settled (20 MiB in this fixture, before XPC and Foundation service overhead).

## Idle cleanup: not implemented

The helper settles by itself to within about 3–8 MiB of an engine that never ran, and repeated bursts settle at the same level. An idle exit would reclaim those few MiB plus the process's own baseline, and in exchange every next run would pay a process launch and a cold first run (7 ms for Hello World and 14 ms for Base64 in this fixture, before launchd and XPC startup, which this fixture does not measure). It would also add a shutdown that must race safely with a connection arriving and with launchd's restart throttling, which the readiness handshake already has to absorb. The app already invalidates its connection after every run, so an idle helper holds no open connection or transaction; launchd may reclaim such a service under memory pressure (documented behavior, not verified here). The measured problem was per-run churn and peak, which the bridging change addresses; the app is unchanged.

Revisit if a signed, installed helper settles far above these numbers, or if live heap growth turns out to scale with something larger than run count.

## Verified and not verified

- **Verified:**
  - The tables above, three fresh processes each.
  - `./tools/check-extensions.sh` passes with the new bridge: greeting, empty input, UTF-8, input/output limits, malformed modules, denied imports, every WASI probe, the Base64 sample at and past its buffer, the list fixture, and both watchdogs.
  - The app fixture still builds and runs on the shared counters (`idle` and `acp` rerun).
- **Not verified:**
  - The signed, sandboxed helper over XPC, its baseline with NSXPCListener and launchd, or launchd's reclaiming of an idle helper. `tools/check-extensions-xpc.sh` needs signing credentials and was not run.
  - Cold-start latency including process launch and the readiness handshake.
  - Cancellation and revocation: these are app-side and end the run's connection; a runaway is killed by the watchdog, which frees everything.
  - Intel, older macOS and longer runs than 400.
