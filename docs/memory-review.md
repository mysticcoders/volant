# Memory review — September 14, 2026

This is a source audit plus an uncontrolled live RSS snapshot, not an Instruments leak/peak-footprint assessment. The already-running development Release process (PID 74049, about three hours old) used 195,424 KiB RSS (~190.8 MiB); its agent helper used 11,776 KiB (~11.5 MiB). This process predates the current changes and is not the installed /Applications copy. Its current sessions and personal data were left untouched. RSS includes shared and reclaimable pages and is not a per-feature budget or evidence of a leak. Read process names and metrics only, never process argument lists.

## Improvements in this change

- Launcher result access previously flattened every section into a newly allocated array on every read, including selection checks by each visible emoji cell. Cache the flattened array when sections change. Swift arrays share element/string storage through copy-on-write; this trades a small retained result-index array for eliminating repeated full-result allocations during navigation.
- Emoji search previously built complete prefix and substring result arrays, performed linear membership searches to exclude duplicates, then concatenated before applying the limit. A single scan now keeps bounded prefix/substring buckets and appends only the needed fallback results. Empty browsing reuses the catalog array when all entries are requested. The grid uses lazy cells.
- Caffeinate keeps a single owned assertion and one weak-capturing timer, invalidates the timer at completion/Stop/deinit, and persists no session data. Countdown publication is observed by its status strip, not by the whole launcher list.

An optimized Swift benchmark on the bundled 1,765-entry catalog ran 1,500 searches across face/heart/cat/smile/no-match. Previous: 3.600 s; new: 2.991 s (~17% less elapsed time in this run). Result order and content matched for each query. This is a local CPU benchmark, not a claimed measured reduction in process memory. No flaky wall-time threshold was added to CI; ordering/limits are functional tests.

## Existing bounds and next gaps

| Area | Current behavior | Next measurement/change |
| --- | --- | --- |
| Emoji | One static bundled catalog; lazy grid | Measure retained cells after repeated open/filter/close |
| Clipboard | Input caps: 256 KB text / 8 MB compressed image; rows limited by retention; launcher shows 12 | Full image data remains on result rows, and decoding PNG/TIFF can expand far beyond compressed size. Profile large fictional images, add pixel/decode budgets and thumbnail loading. Skip decrypting image blobs for text-only queries. |
| Notes | Every Markdown file is read into memory; dirty drafts are separately preserved | Large fictional notebook benchmark; consider metadata index/lazy clean-note loading without compromising pending writes or search |
| ACP | Frame, transcript-text, tool-detail and event limits exist in helper; client polls snapshots | Measure full snapshot encode/decode every 250 ms on a large fictional transcript; consider revision/delta transport only in a separately tested ACP change |
| Herdr | Polling ends and sessions clear when launcher dismisses | Check helper/observer lifetime with repeated open/close and failure paths |
| App/file results | App index lives for app lifetime; file search shows at most eight results and stops its query | Profile icon decoding and Spotlight peak allocations before introducing a new cache |

Next concrete gap: controlled signed-build profiling of idle baseline, 100 picker open/search/close cycles, maximum-size fictional clipboard images, a large fictional notebook, and a bounded ACP transcript. Capture physical footprint, allocation backtraces, peak/residual growth and helper processes separately. Don't discard active conversations or dirty notes merely to lower memory numbers.
