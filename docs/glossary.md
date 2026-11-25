# Glossary

The words Volant's code, docs and agents use, and what each one means here. Use these terms when naming types, settings, docs and PRs. If a new concept needs a name, add it here in the same change. Decisions and the reasons behind them live in [architecture decision records](adr/README.md); this page says what things are, not why.

## Words with more than one meaning

These collide. Use the preferred term in new code and prose, and qualify the word when the context does not settle it.

| Word | Meanings in this repo | Preferred terms |
| --- | --- | --- |
| host | An XPC service target (`VolantFetchHost`); a network host an extension may reach (`extensionHosts`); a SwiftUI hosting view or window | **helper** for the XPC service (keep the `*Host` target names); **approved host** for the network sense; **hosting view** for SwiftUI |
| agent | A coding agent reached over ACP; `VolantAgentHost`, which also runs file search, fsearch, Rex and Servers; the agent results in the launcher | **coding agent** for the program; **agent helper** for `VolantAgentHost`, and say which of its jobs you mean |
| session | An ACP session; a Focus session; a Rex session; the launcher session that holds menu titles; the macOS security session the agent helper joins | Always qualify it: **ACP session**, **Focus session**, **Rex session**, **launcher session**, **security session** |
| extension | A Volant extension (WASM module plus manifest); a Raycast extension; Apple's network extensions | **extension** alone means a Volant extension; say **Raycast extension** or **Apple network extension** otherwise |
| network extension | A Volant extension that declares `hosts` (docs/network-extensions.md); Apple's NetworkExtension framework, which Volant does not use | **network extension** means the Volant kind; name the Apple framework explicitly |
| conversation | An ACP conversation in AI Chat; an agent pane's terminal session | **conversation** is Volant-owned (ACP); a **pane** belongs to Herdr or Rex. Their identities are separate |
| focus | A Focus session (the feature); keyboard or window focus; focusing an agent pane | **Focus** (capitalized) is the feature; **focus loss** and **focus a pane** are the other senses |
| catalog | The signed extension catalog; String Catalogs (localization) | **extension catalog**; **String Catalog** |

## People

- **Owner**: the person using this copy of Volant. Docs and rules say "owner" rather than "user" so that an approval, a grant or a testing window is always someone's explicit choice.
- **Contributor**: someone changing the code, human or coding agent.

## The launcher

- **Launcher**: the search window summoned by `summonHotKey`. Implemented as a non-activating **panel**.
- **Panel**: the launcher's non-activating window. It dismisses on focus loss, except while a system permission prompt is up.
- **Query**: the text typed into the launcher. A **prefix** (`/`, `@`, `clip`, `cal`, `note`, `agents`, `acp`) forces one source.
- **Result** / **row**: one entry in the result list. Rows activate by **result identity**, never by array offset.
- **Command**: a typed word that names a built-in feature (`weather`, `volume`, `servers`, `menus`).
- **Launcher Actions**: the action list opened with ⌘K on a row; it stays inside the panel.
- **Favorite**: a result the owner pinned; edited by narrow configuration patches.
- **Learned ranking**: per-query choice scores in a local SQLite file, with a seven-day half-life.
- **Alias**: a word mapped to an app name; it ranks first.
- **Quicklink**: a saved URL with an optional `{query}` slot.
- **Snippet**: saved text with a keyword, copied (never pasted) with placeholders expanded.
- **Clipboard history**: encrypted captures of copied text and images, under `clip`. Its key lives in this Mac's Keychain, so it is excluded from backups.

## Notes

- **Note**: one plain `.md` file in the app container, edited in the notes window.
- **Live mode**, **Markdown Source**, **Preview**: the three ways the notes window shows a note.
- **Pinned note**: shown first in the notes browser. Pinning is a local preference, excluded from backups.

## Extensions

- **Extension**: a WASM module plus a manifest, run by `VolantExtensionHost` inside a capability cage.
- **Manifest**: the extension's declaration of commands, permissions, `hosts`, `appLinks`, `preferences` and `storage`.
- **List extension** / **text extension**: an extension that returns rows, or one that returns text.
- **ABI 1** / **ABI 2**: the two module interfaces. ABI 2 uses virtual in-memory WASI streams only.
- **Bundled extension**: shipped inside the app; its origin comes from the app's resource path.
- **Community extension**: installed from the extension catalog; gated by the community **master gate** as well as its own approval.
- **Approval**: the owner's enablement of one extension, bound to its **fingerprint** (manifest and code hash). Changed bytes that ask for anything new need fresh approval.
- **Approved hosts**: the hosts the owner allowed for network extensions (`extensionHosts`); not synced.
- **Extension catalog**: the Ed25519-signed index of installable extensions, fetched only through `VolantFetchHost`.
- **Extension preferences**: the owner's own settings for an extension; never secrets, never part of the fingerprint.
- **Extension storage**: per-extension data that travels inside list requests and replies, for manifests with `"storage": true`.
- **Extension activity**: what Volant observed an extension do at its own boundaries (`ExtensionActivity`), kept in memory only and shown in Settings › Extensions › Activity…. Not an extension's log, which is the extension's own words.
- **Extension secret**: a declared token kept only in the Keychain (`ExtensionSecretStore`) and added as a header by the fetch helper.

## Helpers

Separate signed processes inside the app bundle. Each one does a single job, and the main app talks to them over XPC. Several decisions depend on which helpers are sandboxed and which may use the network: see [ADR 0002](adr/0002-sandboxed-app-with-capability-helpers.md).

| Helper | Job | Sandbox | Network |
| --- | --- | --- | --- |
| `VolantExtensionHost` | Runs extension WASM; draws SVG row images | Yes | No |
| `VolantFetchHost` | Fetches for network extensions and the extension catalog | Yes | Yes |
| `VolantAIHost` | Bring-your-own-key and local model chat | Yes | Yes |
| `VolantRatesHost` | Currency rates from fixed URLs | Yes | Yes |
| `VolantWeatherHost` | WeatherKit forecasts and geocoding | Yes | Yes |
| `VolantAgentHost` | Herdr and Rex panes, ACP providers, home-folder file search, fsearch, Servers | **No** | Not restricted by the OS |
| `VolantInputHost` | Accessibility and event posting: typing at the cursor, Search Menu Items | **No** | Not restricted by the OS; its API has no network call |
| `VolantMCPBridge` (`volant-mcp`) | Byte relay between an AI app's stdio and the MCP socket | Yes | No |

The main app is sandboxed and has no network entitlement. The two unsandboxed helpers are kept safe by their narrow APIs and caller checks, not by the OS.

## AI and agents

- **AI Chat**: Volant's chat surface. It connects only after a command is activated.
- **ACP**: Agent Client Protocol. Volant is the client; a **provider** (Claude Code, Codex, Cursor) is the coding agent behind an installed CLI and adapter.
- **ACP conversation**: one Volant-owned conversation with a provider, up to six at once. Its transcript is in memory only.
- **Native session ID**: the provider's own ID for an ACP session. Resume uses only a recorded native session ID.
- **Account**: an alternate provider configuration folder (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`) for new conversations.
- **BYOK**: bring your own key; chat through `VolantAIHost` with a key kept in the Keychain.
- **Herdr**: a terminal multiplexer whose agent panes Volant lists and focuses, locally or on a saved remote **machine**.
- **Rex**: a terminal workspace whose panes Volant lists through a fixed Lua script. A Rex pane's identity is session plus block ID, never a label.
- **Pane**: one terminal in Herdr or Rex. Volant focuses panes and never types into them.
- **Pinned harness**: one harness's agent status, kept below the launcher's search field.
- **Rex Overview**: the window that previews Rex panes, with screen text only when `rexPanePreviews` is on.

## MCP server

- **MCP server**: Volant serving tools and resources to AI apps, off by default (Settings > AI > Connected Apps).
- **MCP bridge**: `volant-mcp`, the stdio process an AI app starts. It relays bytes to the app's Unix socket in the app group and holds no logic.
- **Connected App**: an AI app the owner set up to use the MCP server.
- **Sensitive tool**: a tool (clipboard, files, currency, weather) with its own switch that asks in Volant on every call unless the owner chose Always Allow for that app and tool.

## Settings and data

- **config.json**: the owner's configuration file. Edits are narrow patches that keep unknown fields and reject stale snapshots.
- **Per-Mac setting**: stays on this Mac. Hotkeys, favorites, AI, extension approvals, approved hosts, Focus, Breaks, the MCP server and the sync switch are per-Mac.
- **Synced setting**: a key listed in `SettingsSync.keys`, exchanged through iCloud key-value storage.
- **Backup**: Export Backup / Import Backup of config and notes to a folder the owner chooses.
- **Welcome window**: shown once per Mac on first run (`welcomeCompleted`, never synced).
- **Your Volant**: the Settings section that shows local activity such as break history.

## Features

- **Focus** / **Focus session**: hides blocked apps and blocks listed websites for a period. It never quits apps or installs network filters. Not Caffeinate, and not macOS Focus.
- **Breaks**: reminders to step away, with a full-screen overlay and optional phone alerts. Paused while a camera or microphone is in use.
- **Type at the cursor**: dictation typed into the frontmost app through `VolantInputHost`.
- **Dictation vocabulary**: phrase corrections applied after filler removal.
- **Search Menu Items**: searches and presses the frontmost app's menu bar items (`menus`), through `VolantInputHost`.
- **Servers**: lists this user's listening TCP ports (`servers`, `ports`). It acts on nothing.
- **System controls**: audio devices, volume, Bluetooth, Wi-Fi, appearance, menu bar, Pick Color, camera.

## Builds, releases and evidence

- **Volant** / **Volant Dev**: the release app (`com.mysticcoders.volant`) and the Debug build (`com.mysticcoders.volant.dev`), with separate grants, container and Keychain.
- **Release PR**: the PR opened by `Scripts/ship.sh`; merging it is the approval to publish.
- **Fixture**: a test harness with fictional data. Passing fixtures are functional evidence only.
- **Signed installed-app evidence**: a check run against the signed app installed in `/Applications`. Several rules require it on top of fixtures: TCC attribution, Keychain, iCloud, WeatherKit, live providers.
- **Test VM**: the headless Tart VM where local UI tests run (docs/ui-testing.md).
- **PR gate**: the aggregate CI check every PR must pass before merging.
