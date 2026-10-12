# Network extensions (prototype)

Network extensions read public web data, such as the Hacker News front page or Lobsters' hottest
stories, and show it as rows in the launcher. Return opens a row's link; Command-Return opens its
second link, typically the discussion. The first two are in `extensions/hackernews` and
`extensions/lobsters`. Both are Rust modules built with `extensions/build-list-extensions.sh` on a
shared kit (`extensions/volant-extension-kit`).

## The boundary

The WebAssembly module never touches the network, and neither do Volant or the extension helper.
A run has two phases, each an ordinary ABI 1 or ABI 2 invocation whose input is JSON:

1. **Plan.** `{"phase":"plan","query":"new","now":1791000000}` → `{"fetch":["https://lobste.rs/newest.json"]}`.
   A plan may return `{"items":[…]}` instead, for example one row explaining an unusable query; Volant
   shows it without fetching.
2. **Fetch.** Volant checks every planned URL with `ExtensionNetwork.permittedURL`: https on the
   default port, no credentials or fragment, and a host the manifest declares *and* the owner allowed.
   One bad URL rejects the whole plan. At most 4 URLs.
3. **Render.** `{"phase":"render","query":…,"now":…,"responses":[{"url","status","body"}]}` →
   `{"items":[{"title","subtitle","url","secondaryURL","secondaryTitle"}]}`. A failed fetch arrives
   as status 0 with an empty body so the module can explain it.

`VolantFetchHost` is the only process with network access for this. It is a sandboxed XPC service
with just `network.client`, built like `VolantRatesHost`: it re-checks each URL against the hosts it
was given, refuses redirects, uses an ephemeral session with no cookies or cache, and stops reading a
response past 48 KB. The JavaScriptCore runtime, its imports and its 64 KiB input and output limits
are unchanged; plans, responses and rows all pass through them.

Items are trimmed before display: at most 100 rows, titles and subtitles cut to 300 characters, and
any link that is not http or https dropped, so a row can only open a web page.

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
- Hosts are checked again after the plan and again after fetching, so a host removed mid-run stops it.

## Not yet

- A catalog of approved extensions that installs from a repository (see #63). Today extensions are
  installed by copying their folder into Settings → Extensions → Open Folder.
- Per-extension storage for pins, hidden stories or read state, and preferences such as blocked domains.
- POST requests, authentication, streaming, or responses over 48 KB.
- A signed-delivery check of `VolantFetchHost` through the release build, like `tools/check-rates-xpc.sh`.

## Checks

- `swift test --package-path Core --filter ExtensionNetworkTests`: host names, URL permission, plans,
  item trimming and shared host approvals.
- `VolantTests/ExtensionTests`: enabling allows hosts, a removed host asks again, uninstall prunes only
  orphaned hosts.
- `tools/check-extensions.sh`: the real Hacker News and Lobsters modules run in the production
  JavaScriptCore host, plan only their host, and render fictional pages.
- `cargo test` in each extension folder (run by the build script).
- `tools/installed-acceptance/run-vm.py --build --only extensions`: installs both extensions in a
  disposable VM, approves hosts from the prompt, reads real stories, opens a story and its discussion,
  removes a host and uninstalls one extension.
