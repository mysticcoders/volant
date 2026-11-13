# Network extensions (prototype)

Network extensions read public web data, such as the Hacker News front page or Lobsters' hottest
stories, and show it as rows in the launcher. Return opens a row's link; Command-Return opens its
second link, typically the discussion. The first two, Hacker News and Lobsters, live in their own
repository, [mysticcoders/volant-extensions](https://github.com/mysticcoders/volant-extensions), as
Rust modules on a shared kit with a pinned toolchain and a reproducible build. This repository keeps
only the host side and a dependency-free fixture, `tools/extensions/list-fixture`, for its own checks.

## The boundary

The WebAssembly module never touches the network, and neither do Volant or the extension helper.
A run has two phases, each an ordinary ABI 1 or ABI 2 invocation whose input is JSON. Every request
carries `"units"`: `"us"` when the system uses US customary units, otherwise `"metric"` (the United
Kingdom's mixed system reads as metric).

1. **Plan.** `{"phase":"plan","query":"new","now":1791000000,"units":"us"}` → `{"fetch":["https://lobste.rs/newest.json"]}`,
   optionally with `"state"`: a string of at most 4 KB that the render after this fetch receives.
   A plan may return `{"items":[…]}` instead, for example one row explaining an unusable query; Volant
   shows it without fetching.
2. **Fetch.** Volant checks every planned URL with `ExtensionNetwork.permittedURL`: https on the
   default port, no credentials or fragment, and a host the manifest declares *and* the owner allowed.
   One bad URL rejects the whole plan. At most 4 URLs.
3. **Render.** `{"phase":"render","query":…,"now":…,"responses":[{"url","status","body"}]}` →
   `{"items":[{"title","subtitle","url","secondaryURL","secondaryTitle"}]}`. A failed fetch arrives
   as status 0 with an empty body so the module can explain it.
4. **Another round.** A render may instead return `{"fetch":[…],"state":"…"}` when it needs one answer
   before it can ask the next question, such as looking up a place and then its forecast. Volant checks
   approval and hosts again, fetches, and renders with the new responses and that `state`. A run fetches
   at most 3 rounds; a fourth request fails the run with "Extension kept asking for more pages".
5. **Cancellation.** Typing a new query inside the extension, leaving it, or closing the launcher
   cancels the run in progress. Fetches in flight stop at once (closing their helper connection cancels
   the transfer), and no further plan or render starts. A module call already running finishes within
   its time limit; its reply is dropped, storage included, and the new query runs after it. A row
   action is never cancelled, since its POST may already have reached the server.

## Tokens, changes and confirmations

- **Tokens.** A manifest may declare up to four `secrets`, one per host it also declares:
  `{"id":"token","title":"Todoist API token","help":"…","host":"api.todoist.com","header":"Authorization","prefix":"Bearer "}`.
  The header must be `Authorization` or `X-API-Key`. The first-run prompt asks for each missing token
  with a secure field. Volant keeps it in the Keychain (service `com.mysticcoders.volant.extensions`,
  account `<extension id>/<secret id>`, this device only), never in config.json, backups, iCloud
  sync, logs or any request to the module. The fetch helper adds it as that header only to requests
  for that exact host. Secrets are part of the approval fingerprint. Settings → Extensions → Remove
  Tokens deletes them, and so does uninstalling.
- **Changes.** Only the `action` phase, which the owner starts by choosing a row or an action, may
  reply `{"fetch":[{"url","method":"POST","json":{…}}],"state":"…"}`. Each URL must be https on a
  declared, approved host, at most 4 requests, each JSON body at most 64 KiB. Volant checks approval,
  hosts and tokens again, sends them, and runs `render` with the responses, the row, the action and the
  state. `plan`, `render` and `opened` cannot send anything but GET.
- **Confirmations.** Any reply may carry `"notice"` (at most 120 characters), shown briefly in the
  launcher. An action reply without rows runs the list again, so a completed task disappears.
- **Return runs an action.** A row's `"primaryAction":"<action id>"` makes Return run that action
  instead of opening the row's link, such as adding the typed text as a task.
- **Row symbols.** A row's `"symbol"` names one of Volant's row icons: `sun`, `moon`, `cloud-sun`,
  `cloud-moon`, `cloud`, `fog`, `drizzle`, `rain`, `heavy-rain`, `sleet`, `snow`, `thunderstorm`,
  `wind`, `hot` and `cold` (`ExtensionItemSymbol`). Volant draws the matching SF Symbol in color in
  place of the extension's icon. An unknown name is dropped and the row shows the extension's icon.
  Older Volant versions ignore the field. A row image (below) takes the symbol's place once it loads.
- **Row badges.** A row's `"badges"`, up to three `{"symbol","text"}` pairs, show at its end in place of
  the extension's name, such as a story's points, comments and site. `symbol` is one of `points`,
  `comments`, `site`, `author` and `time` (`ExtensionItemBadge.Symbol`), drawn by Volant; an unknown
  name keeps the text without a symbol. Text is one line of at most 32 characters, and a blank badge is
  dropped. Older Volant versions ignore the field.
- **Link actions.** A row's Actions menu (Command-K) lists Open Link, its second link under the row's
  `secondaryTitle` (Command-Return), and Copy Link, each only when the row has that link, before the
  row's own `actions`.
- **Copying.** A list extension that declares `"permissions": ["clipboard-write"]` can give a row a
  `"copy"`: `{"text": "<svg …>…</svg>", "title": "Copy SVG"}`, up to 64 KB of UTF-8 copied as plain
  text, or `{"url": "https://cdn.example.com/logo.png", "type": "png", "title": "Copy Image"}` with
  `type` one of `svg`, `png`, `jpeg`, `webp`, `ico`, `gif`, `bmp`, `avif`, `image` or `text`. `title` is one line of at most 40
  characters, "Copy" when absent. Without the permission, or with a text over 64 KB, an unknown type, or
  a URL that is not https on the default port to a declared host, the copy is dropped while sanitizing
  and the row stays. The prompt and Settings say "Copy text and images to your clipboard when you
  choose them"; the permission is part of the approval fingerprint, so adding it needs enabling again
  and a catalog update that adds it turns the extension off (`ExtensionItemCopy`).
  - The Actions menu lists the copy right after the link entries. Return performs it when the row has
    no `url` (and no `primaryAction`); otherwise Return still opens the link. The launcher stays open
    and confirms "Copied SVG" in the footer.
  - A URL copy is fetched only when the owner chooses it, never while listing: Volant checks the
    extension is still enabled, unchanged, not revoked and not blocked by the community switch, and that
    the host is declared and allowed, then fetches it once through `VolantFetchHost` with the same rules
    as a plan (https, no redirects, at most 512 KB, the host's declared token). It checks the bytes
    match `type` before copying: `svg` and `text` must be UTF-8 without NUL characters, and SVG's root
    element must be `<svg`. Before the root it may have whitespace and up to 16 of an XML prolog,
    `<!-- … -->` comments and a `<!DOCTYPE svg …>` that names `svg` as its root, as svgl's files do. A
    DOCTYPE with an internal subset (`<!DOCTYPE svg [ … ]>`) is refused, since it can declare entities for
    whatever later reads the copy, and so is any other DOCTYPE, such as `<!DOCTYPE html><svg>`. This is a
    text scan; the markup is never parsed or rendered.
    Images must carry the signature of a format the type accepts, be reported by ImageIO as that format,
    be at most 8192 pixels on a side and 32 megapixels, and decode; they are copied as PNG and TIFF. A GIF
    copies its first frame and an ICO its largest entry. Approval and the host are checked again after
    the download. An unapproved host, a failed or non-2xx fetch, a wrong type or an oversized file shows
    why in the footer and copies nothing.
  - **Any image.** An extension often cannot know a service's format: DuckDuckGo's icon service answers
    the same URL pattern with ICO or PNG. `"type": "image"` accepts any raster image Volant decodes (PNG,
    JPEG, GIF, WebP, ICO with PNG or BMP entries, BMP, TIFF, AVIF and HEIC), identified by its signature
    and confirmed by ImageIO, so no other ImageIO decoder (PDF, PSD, camera raw) is reachable. Bytes that
    are SVG markup instead are copied as text under the SVG rules above. The explicit types stay strict:
    `png` accepts only PNG, `gif` only GIF, and so on (`ExtensionImageFormat`).
  - **Older Volant.** 0.3.35 drops a copy whose `type` it does not know (`image`, `gif`, `bmp`, `avif`)
    while sanitizing and keeps the row, so an extension that must work on 0.3.35 keeps the explicit
    0.3.35 types (`svg`, `png`, `jpeg`, `webp`, `ico`, `text`). Checked against the v0.3.35 sources.
  - The module never sees the downloaded bytes. Each copy is recorded as a clipboard write in
    `ExtensionActivity`, with the host for a URL copy and its GET, never the content.
  - Older Volant versions ignore `copy`, so give such rows a `url` or a title that is useful to copy.
- **Row images.** A list extension that declares `"permissions": ["row-images"]` can give a row an
  `"image": {"url": "https://icons.example.com/ip3/example.com.ico"}`, such as a site's favicon or a
  company's logo. Volant shows it at the row's leading edge in place of the row's symbol or the
  extension's icon: 24 points, aspect-fit, rounded corners. The row's symbol, or the extension's icon,
  shows while it loads and stays when it fails. The URL must be https on the default port to a declared
  host, with no credentials or fragment; otherwise, or without the permission, the image is dropped while
  sanitizing and the row stays. `image` must be an object. The prompt and Settings say "Show images from
  its sites in its rows"; the permission is part of the approval fingerprint, so adding it needs enabling
  again and a catalog update that adds it turns the extension off (`ExtensionItemImage`).
  - *When it loads.* Only rows that appear on screen ask for their image, never while listing. Each list
    starts at most 30 fetches and at most 4 run at once across lists; rows past the thirtieth keep the
    placeholder. A new list, a new query, leaving the extension or closing the launcher drops results
    still loading.
  - *Checks.* Before each fetch and again after it, Volant checks that the extension declares
    `row-images` and is enabled, unchanged, not revoked and not blocked by the community switch, and that
    the host is declared and allowed. A cached image is shown in a new list only after the same checks.
  - *Decoding outside the app.* `VolantFetchHost.rowImage` fetches the URL under the plan rules (no
    redirects, no cookies, the host's declared token) and at most 256 KB. Inside that sandboxed helper,
    ImageIO opens it only when its signature is PNG, JPEG, GIF, WebP, ICO, BMP, TIFF, AVIF or HEIC and
    ImageIO agrees, the source is at most 4096 pixels on a side and 16 megapixels, and it draws a
    thumbnail of at most 64 pixels (`CGImageSourceCreateThumbnailAtIndex`, no caching) into a fresh 8-bit
    sRGB bitmap, so no metadata, color profile or animation survives, and replies with that PNG. A GIF
    shows its first frame and an ICO its largest entry. The app decodes only that reply, and only when it
    is a single-frame PNG of at most 64 KB and 64 by 64 pixels.
  - *SVG (after 0.3.36).* An image URL that returns SVG markup (detected as for a copy: no raster
    signature, UTF-8 without NUL, an `<svg` root after the allowed preamble) is drawn after checking, in
    the extension helper, never in the app or the fetch helper. Before that change it showed the
    placeholder, as it still does on 0.3.36. The steps:
    1. `VolantFetchHost.rowImage` downloads it under the rules above, does not draw it, and checks it
       with `ExtensionSVGPreview` (VolantCore). Accepted markup goes back to Volant unchanged, marked as
       SVG; refused markup goes back as no data, still marked.
    2. Volant does not parse or draw the markup. It forwards the bytes to `VolantExtensionHost`
       (sandboxed, no `network.client`, no file access outside its container) through one call,
       `rasterizeSVG(data:maximumPixels:reply:)`, on a fresh connection.
    3. The extension helper checks the markup again, then draws it with AppKit's own SVG image
       representation (`NSImage(data:)`, which must open it with the class AppKit registers for
       `public.svg-image`, CoreSVG; not WebKit) into the same fresh 8-bit sRGB bitmap the raster path
       uses, at most 64 pixels on its longer side, and replies with that PNG. The renderer's own bitmap
       never leaves the helper. ImageIO has no SVG decoder on macOS 27 (`CGImageSourceCreateWithData`
       reports no type), so AppKit's representation is the only native non-browser renderer.
    4. A watchdog ends the helper if drawing passes 1 second (`ExtensionSVGPreview.renderTimeout`), as
       for a runaway module, and launchd starts a fresh one for the next request. Volant gives up 1.5
       seconds after sending the markup (10 seconds to start the helper) and shows the placeholder.
       A helper stopped this way also stops any extension run it was doing at that moment, which then
       reports that it stopped.
    5. The app accepts only that PNG, under the usual thumbnail checks, and caches it like any row image.
       Refusals, timeouts and failures are cached as failures for the session, so a file that stops the
       helper is not sent again. `ExtensionActivity` records the GET by host and the drawing as
       `svgRender` (completed, denied, timedOut or failed), never any markup.

    `ExtensionSVGPreview` is a token scan, not an XML parser: it never resolves entities, reads a DTD or
    follows a reference, and it refuses rather than rewrites. It refuses:
    - a DOCTYPE or any other `<!` declaration (so no entities, billion laughs or XXE), and processing
      instructions other than a leading `<?xml … ?>`;
    - `<script>`, `<foreignObject>`, `<image>`, `<feImage>`, `iframe`, `object`, `embed`, `audio`,
      `video`, `canvas`, `img`, `link`, `meta`, `base`, `xi:include` and the other embedding elements,
      and animation elements (`set`, `animate…`), which can change attributes after the check;
    - `on…` event attributes, `src`, `xml:base`, and any `href` or `xlink:href` (any prefix) not starting
      with `#`;
    - CSS in a `<style>` element or any attribute with `@import`, `@font-face`, a backslash escape, an
      unterminated comment, a `url(` other than `url(#…)`, or `image(`, `image-set(`, `cross-fade(` or
      `src(`; character references are decoded before these checks, so `&#117;rl(` is caught;
    - filters and masks (`<filter>`, any `fe…` primitive, `<mask>`, the `filter` and `mask` attributes,
      and CSS naming either). CoreSVG draws them at the document's own resolution before scaling down:
      measured on macOS 27, one blurred rectangle on a 16,384-unit canvas, or on a 64-unit canvas under
      `scale(256)`, used about 7 GB; a mask on a 16,384 canvas used about 3 GB. Clip paths, gradients,
      patterns and group opacity under the same scale stayed near 15 MB, so they are allowed. Logos that
      use a blur, such as svgl's Google logo, keep the placeholder;
    - a `<use>` pointing at something that itself contains a `<use>` (exponential drawing), including a
      `<use>` that draws itself or an ancestor;
    - more than 256 KB, 5,000 elements or 64 levels of nesting, and any `width`, `height` (in px, pt,
      pc, mm, cm, in, em or ex) or `viewBox` value above 16,384;
    - malformed markup: unbalanced or unterminated tags, unquoted attributes, `<` in an attribute value,
      undefined entities, a bare `&`, and text or another element after the root.

    Checked against real logos: svgl's GitHub, Vercel, Figma (clip path) and Instagram (gradients linked
    by `xlink:href="#…"`) and Simple Icons 16's GitHub, Nike and Airbus pass unchanged. What the check
    cannot bound is drawing time: one evenodd path of 2,000 long crossing segments (21 KB) took 2.6
    seconds, which is what the 1-second watchdog is for. With the check bypassed, CoreSVG opened no
    connection to a loopback listener and drew no local file for `<image>`, `<use>`, CSS `@import` and
    `url()`, `@font-face`, `feImage`, external DTDs and entities, XInclude, script and `foreignObject`
    references, in an unsandboxed process; an unresolved `<image>` draws as a red box, and `data:` images
    do draw, which is one reason `<image>` is refused outright. Simple Icons marks have no fill and draw
    black, which is hard to see in Dark appearance; extension authors should prefer a colored or
    appearance-appropriate variant. Volant does not tint previews.
  - *Memory only.* Thumbnails, and failures, are cached in memory by extension and URL for the session,
    at most 200 entries and 4 MB of pixels, least recently used first out; nothing is written to disk,
    and Volant forgets them when it quits. Each fetch is recorded as a GET in `ExtensionActivity`, naming
    only the host.
  - *Why a permission.* The URLs are the extension's choice on hosts the owner already allowed, and its
    own fetches reveal the owner's address, timing and query to those hosts. Row images add three
    things those fetches don't: requests that follow what the owner scrolls to (which rows were on
    screen, like a read receipt per row), up to 30 more requests per list without any owner choice
    beyond opening it, and an image decoder (and, for SVG, a renderer) fed from the network
    automatically, even if only in sandboxed helpers. That is a small but real step beyond reading data,
    so the owner opts in. SVG previews add no permission: they fall under `row-images`.
  - *Older Volant.* Versions before row images ignore `image`, and the row keeps its symbol or the
    extension's icon. But 0.3.35 refuses a manifest whose `permissions` names one it does not know, so
    an extension that declares `row-images` does not load there at all; publish it only for a Volant
    release that supports it.

`VolantFetchHost` is the only process with network access for this. It is a sandboxed XPC service
with just `network.client`, built like `VolantRatesHost`: it re-checks each URL against the hosts it
was given, refuses redirects, uses an ephemeral session with no cookies or cache, and stops reading a
response past 512 KB. Requests to the module are limited to 1 MiB and its replies to 256 KiB
(`ExtensionLimits`); plans, responses and rows all pass through them. The module's memory stays capped
at 16 MiB. In the production host a 730 KB render request parses in about 60 ms.

Items are trimmed before display: at most 100 rows, titles and subtitles cut to 300 characters, and
any link that is not http, https or a declared app link dropped. A row's `copy` carries longer text,
such as an SVG logo, without changing the 300-character title limit.

**Location.** A list extension may declare `"permissions": ["location"]`. The first-run prompt
then also asks to share the owner's approximate location (about 11 km) with that extension and the
sites it reads; the grant is that extension's alone, kept as `extensionLocation` in config.json, never
shared, not synced through iCloud, removed by Settings → Extensions → Location → Stop Sharing or by
uninstalling, and dropped when a backup is restored onto a Mac. Location Services is asked only on
that extension's first run after the grant. Each fix is rounded to 0.1° before the extension sees it
as `"location": {"latitude", "longitude"}` in `plan` and every `render`, kept in memory for at most
15 minutes, and never written or logged. If macOS refuses or no fix arrives within ten seconds, the
run goes on without `location`.

**App links.** A list extension may declare up to four app URL schemes, `"appLinks": ["todoist"]`, so
a row can open its item in that app (`todoist://task?id=…`). The schemes are part of the approval
fingerprint and appear in the prompt and Settings as "Opens todoist: links". Files, scripts, inline
data, the web, network shares, remote sessions, `prefs` and every `x-apple` scheme are always refused.
Volant opens an app link only through an installed app that handles it; otherwise it opens the row's
other link instead, so a task without Todoist.app opens on the web.

## Manifest

```json
{
  "abiVersion": 1,
  "id": "community.volant.lobsters",
  "name": "Lobsters",
  "version": "0.1.0",
  "module": "lobsters.wasm",
  "capabilities": [],
  "hosts": ["lobste.rs"],
  "output": "items",
  "sha256": "…"
}
```

`hosts` holds exact lowercase hostnames: no scheme, port, path, wildcard or IP literal, at most 8.
Declaring hosts requires `"output": "items"`. Both fields are part of the manifest fingerprint, so
changing them needs a fresh enablement. Older manifests without them keep the same fingerprint.
The launcher keyword is the extension's name or the last part of its ID: `hn`, `hn new`, `hn ask`,
`hn show`, `hn <search>`; `lobsters`, `lobsters new`, `lobsters <tag>`.

## Inside an extension

Return on a list extension's row enters it. The search field clears, or keeps the text typed after the
keyword (`hn ask` enters Hacker News with `ask`), and a Back chip with the extension's icon and name
sits at its start. From then on the field is the extension's query: no launcher source sees it, and each
edit runs the extension again once typing pauses for 0.3 seconds. The rows on screen stay until the new
ones arrive; a run started while another is going waits for it, and only the newest text runs.

Three optional manifest fields shape this. Neither is part of the approval fingerprint, so changing them
never asks the owner to enable the extension again, and older Volant versions ignore them.

- `"mode"`: `"list"` (the default) runs as soon as the extension is entered and whenever the field is
  cleared; `"search"` shows only its prompt until something is typed.
- `"placeholder"`: the field's prompt, at most 80 characters, such as `"Search Wikipedia"`. Without it
  the field reads "Search <name>…".
- `"filters"`: two to eight `{"id","title"}` choices for a dropdown at the end of the field, such as
  Hacker News's Top, New, Ask HN and Show HN. Ids are lowercase ASCII of at most 32 characters, titles
  one line of at most 24. The first is the default; every request while inside the extension carries
  the chosen one as `"filter"`, including actions. Choosing an entry, or Command-P for the next one,
  runs the extension at once with the field's text. Volant remembers each extension's choice until it
  quits.

Escape clears typed text, and Escape again goes back to the launcher; so does Delete in an empty field
or clicking the chip. Closing the launcher also leaves the extension. Text extensions still run once
from their row, without a scope.

## Host approval

- **Prompt.** The first run, or enabling the extension in Settings, shows the hosts it needs: "To use
  this extension, Volant needs to allow access to the following hosts". Allow enables the extension
  and allows the hosts in one step; Cancel changes nothing.
- **Shared hosts.** Allowed hosts live in `extensionHosts` in config.json, shared by every extension
  that declares them. Writes patch only that key and preserve every other field. The list is per Mac
  and is not part of iCloud settings sync.
- **Settings → Extensions → Network Access** lists each allowed host and the installed extensions that
  use it. Remove takes the host away from all of them at once; their next run asks again.
- **Uninstall** (community extensions only) moves the folder to the Trash, forgets its approval, and
  removes every host it declared that no other installed extension declares.
- Hosts are checked again after the plan, after every fetch and before every further round, so a host
  removed mid-run stops it.

## Not yet

- The signed catalog ([extension catalog](extension-catalog.md)), per-extension storage
  ([extension storage](extension-storage.md), #226) and declared preferences with a Settings UI
  ([extension preferences](extension-preferences.md)) have shipped.
- Methods other than GET and POST, OAuth, streaming, or responses over 512 KB.
- Secrets in catalog listings: the catalog does not list them yet, so Settings shows them only after install.
- A signed-delivery check of `VolantFetchHost` through the release build, like `tools/check-rates-xpc.sh`.

## Checks

- `swift test --package-path Core --filter ExtensionNetworkTests`: host names, URL permission, plans,
  item trimming and shared host approvals.
- `swift test --package-path Core --filter ExtensionItemCopyTests`: the `clipboard-write` permission,
  dropping copies while sanitizing, size, type, title and host limits, and the SVG and image checks,
  including the `image` type, each format's signature and SVG preambles. `ExtensionItemImageTests`: the
  `row-images` permission, dropping images while sanitizing, host rules and limits.
- `VolantTests/ExtensionRowImageThumbnailTests`: thumbnails from generated PNG, JPEG, GIF (first
  frame), BMP, TIFF and ICO with PNG and BMP entries (largest entry), a WebP fixture (ImageIO cannot
  write WebP), and AVIF and HEIC when the Mac can write them; SVG, HTML, PDF, garbage, truncated and
  oversized sources refused; the app's PNG-only acceptance. `ExtensionRowImageTests` (a fake fetch
  helper): loads, failures, refusals before and after the fetch, activity, the fingerprint, and the
  loader's concurrency, per-list cap, stale-list dropping and cache bounds. `LauncherExtensionImageTests`:
  rows keep images, nothing loads until a row asks, leaving drops loads, and the row view's placeholder.
  The Actions fixture's `extension-row-images` scenario renders the prompt and rows with loaded, loading
  and failed images in light and dark. A row image through the signed fetch helper and real services
  are not verified.
- SVG previews: `swift test --package-path Core --filter ExtensionSVGPreviewTests` runs the check over
  real svgl and Simple Icons logos and a hostile corpus (DOCTYPE, billion laughs, XXE, script, event
  attributes, `foreignObject`, external `href`/`xlink:href`, `<image>`, `@import`, `url(http…)`, escapes,
  filters, masks, nested `<use>`, oversized, deep and huge-canvas files). `VolantTests/ExtensionSVGRasterizerTests`:
  logos become small PNGs of the right size and color, refused markup is never drawn, a pathological
  file that passes the check outlasts the timeout, and, where a loopback listener is allowed (CI, not
  the sandboxed local test host), the renderer fetches nothing with the check bypassed.
  `ExtensionRowImageSVGTests` (fake helpers): the markup reaches the extension helper unchanged, only
  its PNG is shown, refusals, timeouts and failures keep the placeholder and are cached, a change while
  drawing drops the result, and activity. `tools/check-extensions.sh` drives the production
  `ExtensionHost.rasterizeSVG`, confirms its watchdog exits on the pathological file, and repeats the
  loopback and local-file check unsandboxed. The Actions fixture's `extension-row-images-svg` scenario
  renders svgl and Simple Icons logos and refused files in light and dark. Not verified: the signed
  `VolantExtensionHost` XPC call (`tools/check-extensions-xpc.sh` needs the exported app), real
  servers, and macOS versions before 27 beyond CI's build and tests.
- `VolantTests/ExtensionRowCopyTests` (a fake fetch helper and clipboard): text, SVG, text and each image
  type; wrong types, oversized and failed downloads, unapproved hosts, a host removed mid-download,
  and disabled, blocked, revoked or unpermitted extensions; the fingerprint. `LauncherExtensionCopyTests`:
  Actions entries and Return. The Actions fixture's `extension-row-copy` scenario renders the prompt and
  the menu. Pasting into real apps and a copy through the signed fetch helper are not verified.
- `VolantTests/ExtensionTests`: enabling allows hosts, a removed host asks again, uninstall prunes only
  orphaned hosts, and a cancelled run stops its reads and never renders.
- `tools/check-extensions.sh`: the list fixture runs in the production JavaScriptCore host, plans only
  its host, may return rows instead of URLs, and renders fetched and failed responses.
- In volant-extensions, `./build.sh --check` runs each extension's tests and confirms the committed
  modules and hashes match a fresh build (CI runs it).
- `tools/installed-acceptance/run-vm.py --build --only extensions`, with volant-extensions checked out
  next to this repository: installs both readers in a disposable VM, approves hosts from the prompt,
  reads real stories, opens a story and its discussion, removes a host and uninstalls one extension.
