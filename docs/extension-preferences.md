# Extension preferences

A list extension can declare settings for the owner to choose in Settings › Extensions, such as domains
to hide, how many rows to show, or a default sort. Volant draws native controls for them, keeps the
owner's choices, and sends them with every list request. Tracking issue: #65.

## Declaring them

`preferences` in `manifest.json` is an array of up to 12 entries:

```json
"preferences": [
  {"id": "sort", "type": "dropdown", "title": "Sort stories by",
   "choices": [{"id": "top", "title": "Top"}, {"id": "new", "title": "Newest"}]},
  {"id": "hideDomains", "type": "text", "title": "Hidden domains",
   "description": "Comma-separated, such as example.com", "placeholder": "example.com", "maxLength": 200},
  {"id": "limit", "type": "number", "title": "Stories to show", "default": 30, "min": 5, "max": 50},
  {"id": "showScores", "type": "toggle", "title": "Show scores", "default": true}
]
```

| Type | Control | Value | Fields | Fallback |
| --- | --- | --- | --- | --- |
| `toggle` | checkbox | boolean | — | `false` |
| `text` | one-line field | string, no newlines | `maxLength` (default 200, at most 1,000), `placeholder` | `""` |
| `dropdown` | menu | a choice's `id` | `choices`: 2–20, with the same id and title rules as list filters | the first choice |
| `number` | number field | number in range | `min` and `max`, both required | `min` |

Every entry has these fields:
- **`id`:** ASCII letters, digits, `-` and `_`, up to 32 characters, unique within the manifest.
- **`title`:** one line, up to 60 characters.
- **`description`:** optional, up to 200 characters.
- **`default`:** optional, and must be a value the entry's type accepts.

Only list extensions (`"output": "items"`) may declare preferences, because only they receive a JSON
request. A manifest with an invalid entry is rejected, like any other invalid field.

## Receiving them

Every list request (plan, render, opened and action phases) includes `"preferences"`, an object with
every declared id:

```json
{"phase": "plan", "query": "", "preferences": {"sort": "top", "hideDomains": "example.com", "limit": 30, "showScores": true}}
```

Each value is the owner's saved choice when it still fits the current declaration, otherwise the
fallback. That covers a value saved for an older version of the manifest, or edited by hand in
config.json. Keys the manifest no longer declares are dropped. A request has no `preferences` when the
manifest declares none.

## Where values go: sync, backups and hand edits

| Path | Preferences travel? | Notes |
| --- | --- | --- |
| iCloud settings sync | No | `extensionPreferences` is not in `SettingsSync.keys`. Like extension approvals, it's per Mac, because each Mac installs and approves its own extensions. |
| Volant backup (Settings › Data & Configuration) | Yes | A backup copies config.json whole, so preferences are included. A restore writes them back; it strips only per-Mac location grants. Extensions themselves aren't backed up, so a restored extension's preferences apply again once the same id is installed. |
| Editing config.json by hand | Yes | Values are read fresh on every run, so no reload is needed. A value that doesn't fit its declaration falls back to the default, and the next save from Settings rewrites only that extension's entry. |
| Uninstalling | Removed | Disabling and updating keep them. |

## Storage and approval

- **Where values live:** the owner's choices are in config.json under `extensionPreferences`, keyed by
  extension id, then preference id.
- **Saving:** values equal to the fallback aren't stored, so a changed default reaches the owner. Saving
  reads the latest file, keeps every other field, and is refused when the values changed since the sheet
  opened.
- **Lifetime:** values are kept when an extension is disabled or updated, removed when it is
  uninstalled, and never synced through iCloud.
- **Approval:** declarations are not part of the approval fingerprint, and a catalog update that adds or
  changes them keeps an enabled extension on. A preference is the owner's own setting and gives the
  extension no new access: hosts, tokens, capabilities and permissions are enforced separately, every
  time.
- **No secrets:** never use a preference for a password, token or API key. Declare a `secret`, which is
  kept in the Keychain and never reaches the module (see `docs/network-extensions.md`).

## Checks

`ExtensionPreferenceTests` (Core) cover validation per type, fallbacks, values that no longer fit, and
the request field. `ExtensionPreferenceRunTests` cover what reaches the module, preserving other config
fields, refusing a stale editor, staying enabled when declarations change, and forgetting on uninstall.
The branded Actions fixture renders the Settings row and the preferences sheet from a fictional manifest.
Text extensions (ABI 1 `run` with a plain string) can't receive preferences until they get a JSON
envelope (#65).
