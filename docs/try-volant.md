# Try Volant in the browser

`usevolant.com/try` is an interactive, clearly labeled browser demo of the launcher. It runs real
Volant code: the catalog's own extension modules, and VolantCore's calculator compiled to
WebAssembly. Nothing a visitor types leaves the page. The homepage hero is the same card, replaying
examples recorded keystroke by keystroke, and hands over to `/try` when a visitor clicks or types. It grew out of the spike
in PR #369.

## What runs

- **Extensions.** `website/public/try/host.js` repeats `VolantExtensionHost/ExtensionHost.swift`
  (ABI 1), `WASICommand.swift` (ABI 2) and `ExtensionMemory.validate` with the same limits, in a
  module Worker that the page terminates on timeout. The nine modules in
  `public/try/extensions` are copied by `tools/try-wasm/copy-extensions.mjs`, which checks each
  against its manifest's sha256. Network extensions (Hacker News, Lobsters, Wikipedia) replay
  responses recorded once on November 7, 2026 (`public/try/samples.json`), labeled as sample data.
- **The calculator.** `tools/try-wasm` builds `CalculationAnswer.answers` for
  `wasm32-unknown-wasip1` from VolantCore's `Calculator`, `Units` and `Currency` sources, unchanged
  (symlinked), plus WASI stand-ins documented in `Sources/VolantCalc`:
  - English localized strings, since Foundation for WASI has no String Catalogs.
  - `MeasurementFormatter` and `DateComponentsFormatter`, which corelibs doesn't provide on WASI.
  - A `DateFormatter` that formats through a named zone's fixed offset at each moment. Corelibs'
    traps with named zones, and switches to ICU root symbols when given a calendar.
  - `CurrencyRates` importing `FoundationXML`.

  It runs in its own worker (`public/try/calculator-worker.js`, `calculator.js`). It isn't an
  extension: it needs more of WASI, and it's over the extension size limit.
- **Parity.** The 26 queries in `tools/try-wasm/queries.txt` give the same answers as the app's
  native VolantCore (`tools/try-wasm/native`). That includes `5 km in miles`, after VolantCore
  added the international mile (1609.344 m) and mph to its exact factors; corelibs rounds the mile
  to 1609.34 m.

## Size

| Calculator module | Raw | gzip | brotli |
| --- | --- | --- | --- |
| Full build | 54.9 MB | 19.4 MB | 12.7 MB |
| English ICU data, `wasm-opt -Oz` | 15.6 MB | 5.57 MB | 4.08 MB |

- **ICU data.** Foundation for WASI links ICU's whole common data package (34.0 MB, 4,855 items).
  `tools/try-wasm/icu-data.mjs` rebuilds it with only the items in `icu-keep.txt`: 40 items,
  1.79 MB, English only. The data that followed the package in the same segment stays at its
  original address in a second segment.
  - **Verification.** `parity.mjs` compares the full and trimmed modules on 80 queries, with the
    same rates and clock: all identical. That covers currency, spelled-out numbers, time-zone names
    and abbreviations, plurals and units, dates, and accented place names. `keep-prune.sh` tests
    removing entries one at a time.
  - **Why items stay.** `curr/supplementalData.res` is required: without it, currency formatting
    traps. Small locale-fallback tables also stay, for queries the parity set lacks.
- **Code.** Code is 16.75 MB (`code-size.mjs`):
  - Swift standard library and runtime: 5.2 MB.
  - FoundationEssentials: 3.0 MB.
  - Generic specializations: 2.4 MB.
  - ICU code: 1.5 MB.
  - Foundation: 1.4 MB.
  - CoreFoundation: 0.5 MB.
  - The calculator: 0.5 MB.
  - FoundationXML with libxml2: 0.4 MB.

  FoundationNetworking isn't linked. libxml2 stays because VolantCore parses the ECB feed with
  `XMLParser`. Binaryen's `wasm-opt -Oz` takes 7.1 MB off the trimmed module, with answers
  unchanged.
- **Load time.** At a throttled 3 MB/s, the first answer arrived about 2.15 s after loading began,
  down from 6.5 s. That was measured locally over gzip; over HTTPS, browsers get brotli.

## Serving

- **Calculator module.** It's in the private R2 bucket `volant-try`, with no r2.dev or custom
  domain, as a brotli and a gzip copy named by the raw module's content hash.
  - `worker/index.ts` serves `/try/calculator/<name>.wasm` ahead of vinext (`lib/try-calculator.ts`),
    because vinext rebuilds route responses and drops `encodeBody: 'manual'`.
  - It picks brotli or gzip from `request.cf.clientAcceptEncoding`, the client's own header, since
    Cloudflare rewrites `Accept-Encoding`. It answers with `Content-Encoding` and
    `public, max-age=31536000, immutable`, and the browser decodes natively.
  - `public/try/calculator.json` names the file and its raw size, which the progress bar measures
    against.
- **Publishing.** `tools/try-wasm/publish-calculator.sh` builds, uploads and writes
  `calculator.json`, and recaptures the hero's examples. It needs the swift.org 6.4.2 open-source
  toolchain and its Wasm SDK (Xcode's compiler can't use the SDK), binaryen, brotli, and wrangler
  signed in.
- **Loading.** The page starts the calculator when idle, or at once when the hero handed text
  over. If loading takes over 0.4 s, a slim progress bar shows; a query waiting on the calculator
  shows inline progress and is answered when it's ready. A failure offers Retry and shows no answers.

## Exchange rates

Rates follow the app's `VolantRatesHost` design: three fixed upstream URLs, the same as the app's.
Requests follow no redirects and have size caps, and the bodies are checked before they're kept.

- **Refresh.** A Cron Trigger on the website worker refreshes them into the KV namespace
  `volant-try-rates`: ECB and ExchangeRate-API every 6 hours, CoinGecko every 5 minutes
  (`lib/try-rates.ts`). A failed fetch keeps the previous copy.
- **Reading.** `/try/rates/{ecb,world,crypto}` only reads KV; a visitor request never reaches a
  provider. A copy past its stale threshold (ECB 4 days, ExchangeRate-API 2 days, CoinGecko 30
  minutes), or a missing one, returns 503, and the page says live rates need the app.
- **Rate limit.** The Workers rate-limiting binding `TRY_RATES_LIMIT` allows 60 requests a minute
  per client address. The address is used only as the limiter's key.
- **What VolantCore decides.** Whether a query needs rates, and which feeds, using the app's own
  `feedsNeeded`. It never mixes ECB and ExchangeRate-API in one conversion. Answers carry
  VolantCore's tags, and the page links each provider: European Central Bank, "Rates By Exchange
  Rate API", "Data provided by CoinGecko". The `/try` page also always shows all three.
- **Privacy.** The privacy page says the site refreshes public rates on a schedule and that
  visitors' queries never reach the providers.

## Security

- **Page policy.** `website/proxy.ts` adds `'wasm-unsafe-eval'` and `worker-src 'self'` to the
  policy only for `/try`; every other page is unchanged.
- **Static files.** `/try/*` static files get their own strict policy from `_headers`:
  `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'`.
- **Smoke test.** `scripts/security-smoke.mjs` now visits `/try`. It checks that only `/try`
  allows WebAssembly, tests the hero hand-off (first keystroke kept, focus kept, no CSP
  violations), and checks the worker scripts' policy.

## The hero

`components/hero-launcher.tsx` is the `/try` card in plain HTML, with the same styles (`app/try/try.css`,
on the site's tokens, so both follow the appearance button). It first paints like an empty launcher:
the prompt "Try Volant in your browser now…" and an empty results area. About 0.2 s after hydration
it starts typing four examples in turn (`hn` and Return, then `3pm tokyo in new york`, `15% of 80`
and `5 km in miles`), 90–150 ms a character and about 250 ms after a space, pausing 0.7 s on the
`hn` match before Return. Each keystroke shows the results `/try` gave for exactly that text: an
answer appears, changes or disappears, and a prefix with no answer shows nothing. The last frame
holds for 3.75 s (5 s for the Hacker News list), fades out over 0.3 s, and the prompt rests 1.35 s
before the next example.

- **Recording.** `scripts/try-hero-capture.mjs` records the frames into
  `lib/try-hero-examples.json` on every website build (prebuild). For each prefix it runs the
  published calculator module (a local build, or the R2 copy) and `/try`'s extension match
  (`lib/try-extensions.json`, shared with `components/try-launcher.tsx`). After Return it runs the
  Hacker News module on `/try`'s sample data, with `/try`'s first filter and default preferences.
  Rows are stored once and frames refer to them, about 2.5 KB in all. A prefix whose rows differ
  from both neighbors while those match (`5 km in mil`, a one-keystroke flicker) is typed together
  with the next character. If no module is reachable it keeps the existing file.
- **No stale dates.** Text that depends on the capture day ("Sunday, November 8", "Tomorrow",
  "19h ago") is left out; the footer says when the examples were captured.
- **Nothing computed.** The hero computes nothing, and the homepage's policy has no
  `'wasm-unsafe-eval'`. It loads the extension icons that frames show (Hacker News, Characters).
- **Hand-off.** Clicking the card, typing or pressing Return opens `/try?q=…` with the first
  keystroke kept; keyboard focus alone stops and clears the replay. The replay is `aria-hidden`; the
  field's description says the examples are recorded.
- **Reduced motion.** Nothing is typed: the card shows the prompt and the final frame of
  `5 km in miles`, captioned as a recorded example.
- **Checks.** `scripts/try-hero-check.mjs <base> <out>` checks the homepage: prompt-only first
  paint, every replayed frame against the recording, final answers against `/try`, hand-off,
  reduced motion, and no WebAssembly or rates requests on the homepage.
- **Layout.** The headline, intro and Download sit above the card, which spans the hero's width.

"Try it" is the first link in the site header, and the hero's secondary link ("Try it now") goes to
`/try`. A homepage section and a line on `/try` say that extensions are WebAssembly: the same file
runs in Volant's sandboxed helper on the Mac and on `/try` in a modern browser, and the host, not
the module, does any fetching (see the claim's row in `docs/marketing-claims.md`).

`/try` uses the same page frame as the homepage (`components/site-shell.tsx`): its header with the
appearance button, home.css type, spacing, colors and buttons, and the footer.

## Local preview

`website/scripts/try-preview.sh [port]` builds the site and copies the calculator module (from
`tools/try-wasm/out`) into local R2. It starts `wrangler dev --test-scheduled` with state in
`.wrangler/try-state`, which survives rebuilds, and fires both Cron schedules so local KV has rates.
`scripts/try-drive.mjs <url> <dir>` drives it headless; `scripts/try-cache-check.mjs` checks repeat
visits.

## Not verified

- **On Cloudflare's network:**
  - The Cron Trigger firing.
  - R2 serving with `encodeBody: 'manual'` and `clientAcceptEncoding` over HTTPS. Locally, plain
    HTTP negotiated gzip, which Chromium decoded byte for byte; the brotli copy is uploaded but no
    browser has downloaded it yet.
  - The rate-limit binding's real limits, which are approximate per data center.
- **Under load:** CoinGecko's keyless limits with the 5-minute refresh.
- **Real networks:** download and compile time on real networks and mobile devices.
