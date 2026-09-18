# Volant extensions — ABI 1

Volant supports small, user-invoked WebAssembly commands in its sandboxed XPC helper. This is a deliberately narrow first version: plain-text input and output, no background activation, no extension UI or store. A bundled Hello World example starts disabled.

## Try it

1. Type `ext hello Andrew` in Volant.
2. Press Return. Review **No permissions required**, then choose **Enable and Run**.
3. The real WASM module returns `Hello, Andrew!`. Return on the result copies it; merely running Hello World does not change the clipboard.
4. Settings → Extensions can disable it again. No extension code runs during search or Settings browsing.

Installed folders live in Volant's preserved storage location: `~/Library/Containers/com.mysticcoders.volant/Data/Library/Application Support/Vey/Extensions/`. Use **Open Extensions Folder** and **Refresh** in Settings. Each folder contains `manifest.json` and its module. Duplicate IDs, invalid manifests and unsupported ABI versions are reported and excluded. There is no automatic downloader or package installer yet.

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

ABI 1 exports `memory`, `alloc(byteCount) -> i32`, and `run(ptr, byteCount) -> i32`. Inputs are UTF-8. The returned pointer addresses a little-endian u32 length followed by UTF-8 output. Memory belongs to a single invocation; the instance is discarded afterward. Supported capability imports retain the original namespace `vey`: `log(ptr,len)` and `clipboard_write(ptr,len)`. No other import types or namespaces are accepted. Hello World imports neither.

## Enablement and isolation

Approval lives under the configuration's `extensions` map and is bound to the complete manifest, including module hash, version and capabilities. Changed code or permissions requires fresh enablement. Writes patch only the relevant entry, preserve unknown fields, and reject stale toggle state. Every invocation rereads the manifest, verifies the pinned code hash and checks approval. A hash establishes integrity against the reviewed manifest, not publisher authenticity; install only code you trust.

Each run gets its own XPC connection, capability snapshot and exactly-once completion. The app serializes extension invocations. Disabling a running extension revokes its callbacks and completes it with an error. Every callback rechecks approval; permission state is not shared across runs. Failures, interruption and watchdog termination return a recoverable error to the launcher.

The helper has App Sandbox only: no network entitlement or broad filesystem entitlement. JavaScriptCore instantiates WASM with only granted function imports. ABI 1 requires one non-shared wasm32 memory with an explicit maximum of 16 MiB. Modules are limited to 2 MiB, input/output to 64 KiB, and execution to 0.5–10 seconds. Host callbacks are capped at 64 per invocation. These are linear-memory/data limits, **not a hard cap on total JavaScriptCore process footprint**. A timed-out helper is terminated; the next connection starts a fresh service.

## Evidence and next gaps

`tools/check-extensions.sh` executes the actual WASM greeting, Unicode, size limits, denied imports, malformed modules and the runaway watchdog. It runs in native CI through `Scripts/test.sh`. Model tests cover opt-in approval, stale edits, changed permissions, hash failure, duplicate IDs and bounded-memory validation. Branded native fixtures cover first-use consent and Settings in light/dark layouts. Direct runtime tests are separate from signed XPC delivery evidence, recorded in the PR.

Next: signed package distribution/update policy; deliberate async/streaming and richer result APIs; process-memory resource accounting; more capabilities with individually reviewed permission semantics. Existing pre-ABI spike manifests must be rebuilt with ABI 1 and explicit memory maxima before enabling. This is not a Raycast extension compatibility layer.
