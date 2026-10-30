# Volant extensions — ABI 1 and text-command ABI 2

Volant supports small, user-invoked WebAssembly commands in its sandboxed XPC helper. This is a deliberately narrow first version: plain-text input and output, no background activation and no extension UI. Signed, reviewed extensions can be installed from the catalog in Settings. A bundled Hello World example starts disabled.

Settings → Extensions now has **Allow Community Extensions**, off by default, in addition to each extension's enable switch. The master gate applies to installed community folders; origin is determined by the app's resource location, never a manifest's claimed ID. Bundled Hello World has its own switch and is independent of the community gate. Allowing community extensions does not approve any individual module. First use still offers Enable and Run. When the master gate is off, activating a community result opens Extension Settings instead.

Turning the master gate off preserves individual approvals but revokes the pending/active community invocation, discards its result and blocks callbacks and new runs. A helper already executing code may finish or reach its watchdog timeout; cancellation does not promise immediate process termination. Restoring the master gate restores still-valid individual approvals, but never runs commands automatically. Changed code/manifest still requires approval again. The persisted top-level `communityExtensionsAllowed` Boolean is edited narrowly alongside the existing per-ID `extensions` map.

## Try it

1. Type `ext hello Andrew` in Volant. Extensions that are off, as Hello World is at first, stay out of everyday search.
2. Press Return. Review **No permissions required**, then choose **Enable and Run**. From then on `hello Andrew` works directly.
3. The real WASM module returns `Hello, Andrew!`. Return on the result copies it; merely running Hello World does not change the clipboard.
4. Settings → Extensions can disable it again. No extension code runs during search or Settings browsing.

Installed folders live in `~/Library/Containers/com.mysticcoders.volant/Data/Library/Application Support/Volant/Extensions/`. Use **Open Extensions Folder** and **Refresh** in Settings. Each folder contains `manifest.json` and its module. Duplicate IDs, invalid manifests and unsupported ABI versions are reported and excluded. Settings → Extensions → Catalog installs and updates signed, reviewed extensions into this folder; see [extension catalog](extension-catalog.md).

## Direct command discovery

Search by display name or the final component of an extension ID: `base64`, `base64 some text`, or `Base64 Encode some text`. Full display names are matched before their shorter ID trigger so arguments retain their text and casing. Partial names find commands without running them. Once a complete short trigger is present, following text is input (`base64 Enc` encodes `Enc`); a complete full display name takes precedence. Return invokes the selected result; typing never executes code. Everyday search shows only extensions that are on (October 13, 2026, at the owner's request); `ext <name>` and the Extension Catalog still list extensions that are off, where Enable and Run or Turn On asks first, and master-blocked community commands open Settings. Existing `ext …` searches remain supported for compatibility and explicit extension-only browsing.

Direct matches appear alongside app and quicklink matches; reserved built-in routes retain precedence. Two extensions sharing a trigger remain separate selectable rows. The catalog caches only manifest metadata, not executable modules. Settings changes, Refresh and Reload Configuration invalidate it; execution still rechecks current approval and the exact manifest/module hash.

See [extension catalog](extension-catalog.md) for signed distribution, updates and curation plans.

## Example

Source: `extensions/hello-rust/src/lib.rs`. Build with `bash extensions/hello-rust/build.sh`; it uses rustup, sets a 16 MiB WASM linear-memory maximum, pins the hash, and updates the bundled copy. The wasm32-unknown-unknown target must be installed. The script needs no third-party Rust crates.

```json
{
  "abiVersion": 1,
  "id": "com.mysticcoders.volant.hello",
  "name": "Hello World",
  "version": "1.0.0",
  "module": "hello.wasm",
  "capabilities": [],
  "timeoutSeconds": 2,
  "sha256": "<SHA-256 of hello.wasm>"
}
```

An optional `"icon": "icon.webp"` with `"iconSha256"` gives the extension an icon in launcher rows and Settings. It must be a square WebP of 16–512 pixels and at most 32 KB in the extension's folder, matching its hash; ImageIO in the app decodes it, and anything else falls back to the generic symbol. Both fields are part of the approval fingerprint, so a changed icon needs enabling again; manifests without them keep their existing fingerprint.

ABI 1 exports `memory`, `alloc(byteCount) -> i32`, and `run(ptr, byteCount) -> i32`. Inputs are UTF-8. The returned pointer addresses a little-endian u32 length followed by UTF-8 output. Memory belongs to a single invocation; the instance is discarded afterward. Supported capability imports live in the namespace `volant`: `log(ptr,len)` and `clipboard_write(ptr,len)`. No other import types or namespaces are accepted, including the `vey` namespace used before 0.3.15. Hello World imports neither.

## Enablement and isolation

Approval lives under the configuration's `extensions` map and is bound to the complete manifest, including module hash, version and capabilities. Changed code or permissions requires fresh enablement. Writes patch only the relevant entry, preserve unknown fields, and reject stale toggle state. Every invocation rereads the manifest, verifies the pinned code hash and checks approval. A hash establishes integrity against the reviewed manifest, not publisher authenticity; install only code you trust.

Each run gets its own XPC connection, capability snapshot and exactly-once completion. The app serializes extension invocations. Disabling a running extension revokes its callbacks and completes it with an error. Every callback rechecks approval; permission state is not shared across runs. Failures, interruption and watchdog termination return a recoverable error to the launcher.

The helper has App Sandbox and Apple’s `com.apple.security.cs.allow-jit` entitlement for JavaScriptCore WASM execution, including SIMD on macOS 15. It has no network entitlement or broad filesystem entitlement; the main app receives no new entitlement. JavaScriptCore instantiates WASM with only granted function imports. ABI 1 requires one non-shared wasm32 memory with an explicit maximum of 16 MiB. Modules are limited to 2 MiB, input to 1 MiB, output to 256 KiB, and execution to 0.5–10 seconds. Host callbacks are capped at 64 per invocation. These are linear-memory/data limits, **not a hard cap on total JavaScriptCore process footprint**. A timed-out helper is terminated; the next connection starts a fresh service. A bounded readiness handshake handles the service-restart race; only readiness may retry, never a submitted extension invocation. Startup has a separate 15-second bound to accommodate macOS launchd’s restart throttling; the execution timeout begins only after readiness.

## Evidence and next gaps

`tools/check-extensions.sh` executes the actual WASM greeting, Unicode, size limits, denied imports, malformed modules and the runaway watchdog. It runs in native CI through `Scripts/test.sh`. Model tests cover opt-in approval, stale edits, changed permissions, hash failure, duplicate IDs and bounded-memory validation. Branded native fixtures cover first-use consent and Settings in light/dark layouts. Direct runtime tests are separate from signed XPC delivery evidence, recorded in the PR.

The helper's memory was profiled on October 30, 2026: it plateaus under repeated runs and settles on its own to about 7–12 MiB within seconds (measured in-process, without XPC), so it has no idle shutdown; handing modules to JavaScript as one `Uint8Array` cut a Base64 run from 43 ms to 5.5 ms and its allocations by 90%. See [the extension helper memory profile](memory-profile-2026-10-30-extensions.md).

Next: signed package distribution/update policy; deliberate async/streaming and richer result APIs; process-memory resource accounting; more capabilities with individually reviewed permission semantics. Existing pre-ABI spike manifests must be rebuilt with ABI 1 and explicit memory maxima before enabling. This is not a Raycast extension compatibility layer.

A [restricted WASI command adapter](../tools/raycast-wasm/README.md) now runs the real Base64 Encode TypeScript command through the production XPC helper. ABI 2 uses `_start` and in-memory stdin/stdout, with empty capabilities; it does not expose the real clipboard or general Raycast/Node APIs. Build and install the opt-in [community Base64 sample](../extensions/raycast-base64/README.md) separately. No additional runtime or sample binary is bundled in the app. The legacy ABI 1 contract above remains unchanged.

### Signed XPC recovery verification — September 18, 2026

A Developer ID archive/export provided the sandboxed helper for `tools/check-extensions-xpc.sh`. The headless signed fixture used only fictional config and sample modules: Hello World succeeded, a runaway module terminated, then a new Hello World invocation succeeded through a restarted service. No normal app startup, clipboard monitoring, owner configuration, host windows or hotkeys were involved.

This caught a real difference from the direct engine checks: launchd throttles rapid restarts (its documented default is ten seconds). A single short deadline made the next request fail even though the new service would become available. Prevention: a separate bounded readiness handshake and execution deadline, no replay after submission, and the repeatable signed-XPC smoke script. The script requires signing credentials and is separate from ordinary CI. The direct WASM and approval tests are automated in CI. Signed installed-app consent interaction and a granted clipboard callback are not claimed by this headless test.

## Network extensions

List extensions can declare `hosts` and `"output": "items"` to read public web data and show it as launcher rows. The module still never touches the network: it plans URLs, Volant fetches them through the sandboxed `VolantFetchHost` from hosts the owner allowed, and the module renders the responses. Hosts are approved in a prompt, shared between extensions, listed under Settings → Extensions → Network Access, and pruned when the last extension using them is uninstalled. See [network extensions](network-extensions.md); the first two, Hacker News and Lobsters, are in [mysticcoders/volant-extensions](https://github.com/mysticcoders/volant-extensions).


## JSON input for text extensions

A text extension can set `"input": "json"` to receive the same kind of request a list extension gets instead of the bare typed text: `{"phase":"run","query":…,"now":…,"units":…}` plus `preferences`, its saved `storage` and, when allowed, `clipboard`. It replies `{"text":"…"}`, optionally with `"notice"` (a short confirmation, at most 120 characters) and `"storage"` (saved under the [storage](extension-storage.md) rules). Return copies the text, as for any text extension; a reply with only a notice shows the notice. A reply that is not JSON is an error. Hosts and location stay list-only. `"input"` is part of the approval fingerprint, and list extensions leave it out.

## Clipboard

An extension that receives JSON requests (a list extension, or a text extension with `"input": "json"`) can declare `"permissions": ["clipboard"]`. Its requests then carry the clipboard's text as `clipboard`. The approval prompt says **Read your clipboard’s text when you run it**, and the permission is part of the approval fingerprint, so adding it needs enabling again, and a catalog update that adds it turns the extension off. Volant reads the clipboard once, when a run or row action starts, and sends that same text with each of that run's requests. It never reads the clipboard while you search or browse Settings, or for an extension that is off or blocked. It sends plain text only, at most 64 KB, and nothing when the item is marked concealed, transient or from a password manager (the same `PasteboardFilter` that keeps those out of clipboard history). Volant never stores or logs the text; an extension that declares storage could keep it, so approve only extensions you trust. This is separate from `clipboard.write`, the ABI 1 import that writes to the clipboard. `ExtensionClipboardRunTests` and `ExtensionManifestRulesTests` cover it.

## Activity

Volant records what each extension does where it checks or performs the operation, never from anything the extension reports (`ExtensionActivity`). Each event has the extension ID, version, code hash, an invocation number shared by every step of one run, the time, the operation, its outcome (completed, failed, denied, cancelled or timed out) and, where it has one, a duration. Operations are each module call (named by its phase), each GET and POST (named by host only), clipboard reads and writes, diagnostic log calls, location shares and storage saves. Denials include runs of disabled, blocked or revoked extensions, URLs or hosts the owner hasn't allowed, storage from a stale or no-longer-approved run and callbacks after a run ended. A helper stopped after its time limit counts as timed out.

Events never hold the query, clipboard text, rows, headers, tokens, URL paths or queries, log text or raw errors. A host name is still private, so activity stays in memory on this Mac: the newest 500 events, with a count of any dropped, cleared when Volant quits. Showing, keeping and exporting it is #68. `ExtensionActivityTests` covers ordering, correlation, redaction, cancellation, refusals and the timeout rule; it does not verify signed helper-to-app delivery.

## Preferences

List extensions, and text extensions with `"input": "json"`, can declare `preferences` (toggles, one-line text, dropdowns and numbers) that the owner sets from the extension's **Preferences…** button in Settings › Extensions. Volant sends the chosen values, or the defaults, as `preferences` with every list request. They are the owner's own settings, grant no access, and never hold secrets. See [extension preferences](extension-preferences.md).
