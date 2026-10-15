# Per-extension storage

Part of #65. A list extension can remember things on this Mac, starting with what the Hacker News
and Lobsters readers need: pinned stories, hidden stories, read state and blocked domains. The design
was reviewed by the owner on October 13, 2026.

## Shape: state travels with the request

No new WebAssembly imports and no callbacks. Volant already runs list extensions as plain
request/reply invocations (plan, then render). Storage rides along:

- Every request to an extension that declares `storage` gains `"storage": {…}`, the JSON object it
  last saved (`{}` at first).
- Any reply may include `"storage": {…}`. Volant replaces the saved object with it, after checks.
  Leaving it out keeps the current one.

This works the same for ABI 1 and ABI 2 and keeps the extension helper free of host calls during
execution. An extension can only ever see its own object, because Volant chooses what to send.

## Actions on rows

Pinning and hiding need something to happen to one row. Items gain optional actions:

```json
{"title": "…", "url": "…", "actions": [{"id": "pin", "title": "Pin Story"}, {"id": "hide", "title": "Hide Story"}]}
```

They appear in the row's Command-K menu. Choosing one runs the module with
`{"phase": "action", "action": "pin", "item": {…the row…}, "query": …, "now": …, "storage": {…}}`.
The reply is `{"storage": {…}}` and optionally `{"items": […]}` to redraw at once. An action
never fetches. When the reply only saves data, Volant runs the list again (plan, fetch and render),
keeping the selected row where it still exists, so a hidden story disappears and a pinned one moves up.

Read state uses the same path. When Return opens a row's link, Volant can send
`{"phase": "opened", "item": {…}}` if the extension asked for it with `"onOpen": true` on the item.
That run happens after the link has opened, so a slow or failing extension never blocks the link.

## Permission and storage rules

- **Declared, approved, fingerprinted.** The manifest sets `"storage": true` (a list extension only;
  it is a separate field because `capabilities` names WebAssembly imports). It joins the approval
  fingerprint, so adding it to an existing extension needs enabling again; manifests without it keep
  their fingerprint. The consent and Settings text reads "Remember settings and lists on this Mac",
  and catalog listings carry the same flag, checked against the manifest.
- **Bounded.** At most 256 KB of JSON per extension, a top-level object, nesting depth 8. An
  oversized or invalid reply is rejected with a readable error, and the previous state is kept.
  256 KB leaves room in the 1 MiB request for fetched pages.
- **Where it lives.** `Application Support/Vey/ExtensionData/<SHA-256 of the ID>.json`, written atomically. It is
  per Mac: never synced through iCloud, never included in backups or exports.
- **Lifetime.** Kept across updates of the same ID. Removed on Uninstall. Settings shows **Clear
  Data…** for an extension with saved data, after a confirmation. Turning an extension off keeps its
  data.
- **Stale and revoked runs.** A reply is saved only if the run is still current: the extension is
  still approved, the community switch is on, its manifest on disk is unchanged, and no later run has
  saved since. Otherwise the reply's storage is discarded.
- **Files.** Each extension's object is a file named by the SHA-256 of its ID, so no ID chooses a path.
  Unreadable or oversized files read as `{}`.
- **Logging.** Stored values are never logged. Errors name only the size or shape problem.

## Out of scope for this step

- Text (non-list) extensions. Their input is plain text; they'd need a JSON envelope first.
- Preferences UI, such as a settings form for blocked domains. A first version manages these through
  actions like "Hide stories from this domain".
- Sharing between extensions, secrets, and anything synced.

## Evidence

- `ExtensionStorageTests` (Core): canonical encoding, objects only, the 256 KB and depth limits,
  errors that never repeat stored values, unreadable data as `{}`, storage requiring a list
  extension with fingerprints unchanged otherwise, request fields only when given, replies with
  items, storage or both, and row actions trimmed, deduplicated and capped at six.
- `ExtensionStorageRunTests` (app, a scripted module in place of the helper): data sent with the next
  request, no storage for undeclared extensions, oversized and non-object replies keeping the old
  data, runs disabled or blocked before their reply saving nothing, an older run unable to overwrite
  a newer save, actions and opened rows sending the row and saving, Clear Data and uninstall
  removing data while turning off keeps it, and hashed file names.
- The native Actions fixture runs a storage list extension, opens a row's Actions (⌘K), chooses Pin,
  checks the saved data and the redrawn rows, and renders the menu and Settings' Clear Data in light
  and dark.

Not yet: the real extension helper running a module that saves (the runtime is unchanged; the data
travels inside the existing JSON input and output), and the Hacker News and Lobsters readers adopting
it in volant-extensions.
