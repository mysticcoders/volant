# App memory profile — October 7, 2026

The owner's installed Volant showed a 76 MB physical footprint in Activity Monitor, beside "AutoFill (Volant)" at about 19 MB and VolantAgentHost at 5.5 MB. A read-only `footprint` summary of that process showed about 50 MB of dirty "Malloc Small" and 6 MB of "Malloc Large", a few MB of graphics, and little else. Its contents were not inspected. Everything below was measured in isolated fixtures and a disposable VM with fictional data.

## Environment

- Host: Apple silicon Mac16,6, macOS 27.0.1 (26A434), Swift 6.3.3. It built the fixtures and the app, and ran the Core fixtures.
- Guest: `volant-render-27`, a Tart clone of Cirrus's macOS 27.0 (26A428) vanilla image with 4 CPUs and 8 GB, headless. Nothing ran on the owner's desktop.

## Method

**Core fixture (model only).** A release-built fixture links VolantCore and loads the bundled `cities.tsv.deflate` and `airports.tsv.deflate` the way the app does. It runs ordinary queries, then a city question, then an airport question, each in an autorelease pool. It reads `TASK_VM_INFO` physical footprint and RSS and all-zone `malloc_zone_statistics` live bytes, with footprint sampled every 5 ms for peaks. Each build ran in three fresh processes and the tables show the median.

**Real app in the VM: `tools/memory/app-vm.py`.**
- **Build:** the host builds the Release app unsigned and signs it ad hoc with the app's entitlements, minus the iCloud key-value entitlement, which needs a provisioning profile. The sandbox is kept.
- **Clean start:** each run deletes the app's container and clipboard key in the guest, because a key from an earlier signature makes the keychain prompt and block launch.
- **Driving the app:** the app is started with `--memory-check` (`Volant/App/MemoryCheck.swift`). It hides the launcher shown at launch, then pauses at each phase so the guest can sample it:
  - **launch:** 8 s at rest
  - **summon:** launcher shown
  - **typed:** 50 queries 0.6 s apart: apps, calculator, `:` emoji, `clip`, `note`
  - **settings:** Settings open
  - **closed:** everything hidden, 8 s later
  - **relieved:** the same after a diagnostic `malloc_zone_pressure_relief`
- **Fictional data:** after the launch sample, the guest writes 200 generated notes (about 4 KB each) and copies 25 generated text snippets and 4 system wallpapers, resized to 1400 px PNGs, through the real clipboard monitor.
- **What's recorded at each phase:** the app's own counters, plus `footprint`, `vmmap -summary` and `heap --sortBySize` on the guest process, and the helper processes, each with the process launchd considers responsible for it.
- **Repetitions:** three fresh boots for each build.

Footprint, RSS and live heap are different measures and are not additive. VM numbers are functional evidence and are not the owner's installed app.

## Findings

### 1. City and airport tables loaded for arithmetic (fixed in #155)

`TimeCalculator.suggestions` treated any number followed by a token (`2 + 2`, `5 km`) as a time question and looked the token up in the city table. `resolve` did the same for non-names such as `+ 2:45`. So the first calculation of a session decompressed and parsed all 34,000 cities, about 70 ms on the main thread, and kept them. Now only time questions that name a place the built-in names don't cover load the tables. Entries are packed to 40 bytes, parsing builds no line array, and airport zone names are stored once.

Core fixture, change in MB, median of 3:

| Step | Before footprint | Before live | After footprint | After live |
| --- | --- | --- | --- | --- |
| 5 ordinary queries | +11.02 | +5.39 | +0.67 | +0.27 |
| then `3pm springfield in tokyo` | +0.02 (already loaded) | +0.01 | +6.69 | +3.78 |
| then `time in JFK` | +1.55 | +1.01 | +1.16 | +0.74 |

Per-keystroke calculator time is unchanged: a median of 0.19 ms over 208 keystrokes on both builds.

### 2. Clipboard images kept at full size (fixed here)

**The cause:** `LauncherRowState.image(for:)` built each clipboard row's image with `NSImage(data:)` from the full decrypted bytes and cached up to 32 of them. The image retained the bytes, and drawing it decoded the full-resolution bitmap. In the VM, one `clip` query with four 1400 px images left 30 MB of "Image IO" and about 8.5 MB of `Data` buffers resident for the rest of the session.

**The fix:**
- Rows draw clipboard images at 24 points, so the cache now holds an ImageIO thumbnail of at most 72 px that keeps no reference to the bytes.
- Clipboard search also stops decrypting image blobs to list them. It reads their size from the stored length, and image bytes are decrypted only for rows that are shown.

App in the VM, MB, median of 3 boots (spread under 1 MB except where noted):

| Phase | Before footprint | Before RSS | Before live | After footprint | After RSS | After live |
| --- | --- | --- | --- | --- | --- | --- |
| launch, at rest | 43.3 | 120.6 | 21.8 | 43.2 (spread 3.9) | 120.2 | 21.9 |
| launcher shown | 53.9 | 133.7 | 25.2 | 54.0 | 133.9 | 25.2 |
| after 50 queries | 109.1 | 204.7 | 36.6 | 78.3 | 174.3 | 28.2 |
| Settings open | 110.1 | 205.4 | 37.9 | 73.3 | 170.9 | 29.5 |
| everything closed | 110.0 | 205.3 | 37.7 | 73.1 | 170.6 | 29.4 |
| after pressure relief | 110.0 | 205.3 | 37.7 | 73.1 | 170.6 | 29.4 |

Both columns include #155. After the typing phase, the before build's footprint was 47 MB Malloc Small, 30 MB Image IO and 17 MB Malloc Large; after the fix it was 48 MB Malloc Small and 15 MB Malloc Large, with no Image IO line. The saving grows with the number and size of images in clipboard history that a `clip` query shows.

### 3. What remains

- **The rest of the footprint:** after a session about 73 MB remains. Live heap is about 29 MB, so most of the rest is dirty pages in partly used malloc regions. A diagnostic pressure relief returns none of it, so this is fragmentation from the typing workload, not free memory the allocator is holding. No single owner dominates the live heap: the largest classes are SwiftUI and AppKit view state, Swift metadata, string storage and the app index.
- **Not changed:** the app-icon cache (256 entries, icons decoded by IconServices at row size) and the emoji catalog are small in comparison and help typing speed, so they stay.

### 4. "AutoFill (Volant)" is macOS's, and not avoidable

**What it is:** `com.apple.SafariPlatformSupport.Helper`, which launchd lists as responsible to Volant. In the VM it started one second after launch.

**What a probe app showed** (run in the same guest):
- The helper starts for any window that contains an editable text control: `NSTextField`, `NSSearchField`, `NSSecureTextField` or `NSTextView`. It starts whether or not the control is focused.
- None of these stopped it: `contentType` values (`URL`, empty, `none`), `isAutomaticTextCompletionEnabled = false`, or registering or setting `NSAutoFillHeuristicControllerEnabled = false`.
- Only a window without editable text, or a non-editable label, avoided it.

**Conclusion:** the launcher needs an editable search field, so Volant ships no change here. The helper belongs to macOS, and the system manages its memory.

### 5. VolantAgentHost is started on use, by design

It is not started unconditionally at launch. It starts in four cases:
- **Apple Shortcuts:** the first typed query of two or more characters, to list shortcuts. The list refreshes at most once a minute.
- **Herdr status bar:** opening the launcher when the status bar shows Herdr agents (`resumeAgentsIfNeeded`), which then refreshes every 5 seconds.
- **Herdr list:** connecting from the Herdr agents list.
- **AI Chat:** starting an ACP conversation.

**What the VM showed:** the helper started at the first typed query and used about 2.5 MB. Invalidating the client's connection after a list does not make the process exit; launchd keeps an idle XPC service until it needs the memory. An idle-exit change could not be verified, because the helper accepts connections only from Volant signed by the team, which an ad hoc VM build is not. So no lifecycle change is made.

**On the owner's machine:** the owner's helper started about 2 seconds after launch, which matches the Herdr status-bar path. That connection legitimately stays open.

## Verified and not verified

- **Verified:**
  - **#155:** the Core fixture numbers above. A loader-counting test (`CityDirectoryTests.testOnlyPlaceQuestionsLoadTheTables`) fails on the old code. All city, airport and ambiguous-zone tests pass.
  - **This change:** the VM numbers above. Hosted tests check that clipboard search keeps image bytes and sizes exact and that thumbnails are at most 72 px.
- **Not verified:**
  - The owner's installed, signed app with real data volumes.
  - Long sessions.
  - Intel Macs and 8 GB Macs under memory pressure.
  - The signed agent helper's connection lifecycle.
  - Whether the owner's 76 MB matches the VM's 73 to 110 MB range. That depends on the owner's clipboard images, notes and usage.
