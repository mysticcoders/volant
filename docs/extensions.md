# Volant extensions — ABI 1

Volant supports small, user-invoked WebAssembly commands in its sandboxed XPC helper. This is a deliberately narrow first version: plain-text input and output, no background activation, no extension UI or store. A bundled Hello World example starts disabled.

Settings → Extensions now has **Allow Community Extensions**, off by default, in addition to each extension's enable switch. The master gate applies to installed community folders; origin is determined by the app's resource location, never a manifest's claimed ID. Bundled Hello World has its own switch and is independent of the community gate. Allowing community extensions does not approve any individual module. First use still offers Enable and Run. When the master gate is off, activating a community result opens Extension Settings instead.

Turning the master gate off preserves individual approvals but revokes the pending/active community invocation, discards its result and blocks callbacks and new runs. A helper already executing code may finish or reach its watchdog timeout; cancellation does not promise immediate process termination. Restoring the master gate restores still-valid individual approvals, but never runs commands automatically. Changed code/manifest still requires approval again. The persisted top-level `communityExtensionsAllowed` Boolean is edited narrowly alongside the existing per-ID `extensions` map.

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

The helper has App Sandbox only: no network entitlement or broad filesystem entitlement. JavaScriptCore instantiates WASM with only granted function imports. ABI 1 requires one non-shared wasm32 memory with an explicit maximum of 16 MiB. Modules are limited to 2 MiB, input/output to 64 KiB, and execution to 0.5–10 seconds. Host callbacks are capped at 64 per invocation. These are linear-memory/data limits, **not a hard cap on total JavaScriptCore process footprint**. A timed-out helper is terminated; the next connection starts a fresh service. A bounded readiness handshake handles the service-restart race; only readiness may retry, never a submitted extension invocation. Startup has a separate 15-second bound to accommodate macOS launchd’s restart throttling; the execution timeout begins only after readiness.

## Evidence and next gaps

`tools/check-extensions.sh` executes the actual WASM greeting, Unicode, size limits, denied imports, malformed modules and the runaway watchdog. It runs in native CI through `Scripts/test.sh`. Model tests cover opt-in approval, stale edits, changed permissions, hash failure, duplicate IDs and bounded-memory validation. Branded native fixtures cover first-use consent and Settings in light/dark layouts. Direct runtime tests are separate from signed XPC delivery evidence, recorded in the PR.

Next: signed package distribution/update policy; deliberate async/streaming and richer result APIs; process-memory resource accounting; more capabilities with individually reviewed permission semantics. Existing pre-ABI spike manifests must be rebuilt with ABI 1 and explicit memory maxima before enabling. This is not a Raycast extension compatibility layer.

A [reproducible Raycast TypeScript-to-WASM experiment](../tools/raycast-wasm/README.md) runs the real Base64 Encode command with fictional host adapters. It demonstrates compilation and standalone WASI execution, not compatibility with the shipped Volant ABI. No additional runtime is bundled in the app.

### Signed XPC recovery verification — September 18, 2026

A Developer ID archive/export provided the sandboxed helper for `tools/check-extensions-xpc.sh`. The headless signed fixture used only fictional config and sample modules: Hello World succeeded, a runaway module terminated, then a new Hello World invocation succeeded through a restarted service. No normal app startup, clipboard monitoring, owner configuration, host windows or hotkeys were involved.

This caught a real difference from the direct engine checks: launchd throttles rapid restarts (its documented default is ten seconds). A single short deadline made the next request fail even though the new service would become available. Prevention: a separate bounded readiness handshake and execution deadline, no replay after submission, and the repeatable signed-XPC smoke script. The script requires signing credentials and is separate from ordinary CI. The direct WASM and approval tests are automated in CI. Signed installed-app consent interaction and a granted clipboard callback are not claimed by this headless test.
