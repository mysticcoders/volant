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
  place of the extension's icon. Extensions never supply row images; an unknown name is dropped and
  the row shows the extension's icon. Older Volant versions ignore the field.
- **Row badges.** A row's `"badges"`, up to three `{"symbol","text"}` pairs, show at its end in place of
  the extension's name, such as a story's points, comments and site. `symbol` is one of `points`,
  `comments`, `site`, `author` and `time` (`ExtensionItemBadge.Symbol`), drawn by Volant; an unknown
  name keeps the text without a symbol. Text is one line of at most 32 characters, and a blank badge is
  dropped. Older Volant versions ignore the field.
- **Link actions.** A row's Actions menu (Command-K) lists Open Link, its second link under the row's
  `secondaryTitle` (Command-Return), and Copy Link, each only when the row has that link, before the
  row's own `actions`.

`VolantFetchHost` is the only process with network access for this. It is a sandboxed XPC service
with just `network.client`, built like `VolantRatesHost`: it re-checks each URL against the hosts it
was given, refuses redirects, uses an ephemeral session with no cookies or cache, and stops reading a
response past 512 KB. Requests to the module are limited to 1 MiB and its replies to 256 KiB
(`ExtensionLimits`); plans, responses and rows all pass through them. The module's memory stays capped
at 16 MiB. In the production host a 730 KB render request parses in about 60 ms.

Items are trimmed before display: at most 100 rows, titles and subtitles cut to 300 characters, and
any link that is not http, https or a declared app link dropped.

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

- Preferences an extension declares, such as blocked domains, with a Settings UI (#65). The signed
  catalog ([extension catalog](extension-catalog.md)) and per-extension storage
  ([extension storage](extension-storage.md), #226) have shipped.
- Methods other than GET and POST, OAuth, streaming, or responses over 512 KB.
- Secrets in catalog listings: the catalog does not list them yet, so Settings shows them only after install.
- A signed-delivery check of `VolantFetchHost` through the release build, like `tools/check-rates-xpc.sh`.

## Checks

- `swift test --package-path Core --filter ExtensionNetworkTests`: host names, URL permission, plans,
  item trimming and shared host approvals.
- `VolantTests/ExtensionTests`: enabling allows hosts, a removed host asks again, uninstall prunes only
  orphaned hosts.
- `tools/check-extensions.sh`: the list fixture runs in the production JavaScriptCore host, plans only
  its host, may return rows instead of URLs, and renders fetched and failed responses.
- In volant-extensions, `./build.sh --check` runs each extension's tests and confirms the committed
  modules and hashes match a fresh build (CI runs it).
- `tools/installed-acceptance/run-vm.py --build --only extensions`, with volant-extensions checked out
  next to this repository: installs both readers in a disposable VM, approves hosts from the prompt,
  reads real stories, opens a story and its discussion, removes a host and uninstalls one extension.
