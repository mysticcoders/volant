# Vey extensions: WebAssembly in a sandboxed process

Status: **spike, working end to end** (2026-09-13). Not a stable API.

## The model

An extension is a folder containing `manifest.json` and a WebAssembly module. The manifest names the module, pins its SHA-256, and lists the **capabilities** the module may use. That list is the complete set of host functions the module can call; nothing else exists from its point of view.

```
{
  "id": "com.mysticcoders.vey.hello-rust",
  "name": "Hello (Rust)",
  "version": "0.1.0",
  "module": "hello.wasm",
  "capabilities": ["log", "clipboard.write"],
  "timeoutSeconds": 2,
  "sha256": "…"
}
```

Extensions are written in **any language that compiles to `wasm32-unknown-unknown`**. The sample is Rust; C, Zig, Go via TinyGo, Swift via SwiftWasm, or AssemblyScript all produce the same kind of module.

## Where it runs

```
Vey.app (sandbox: contacts, calendars)
  └─ NSXPCConnection ─▶ VeyExtensionHost.xpc (sandbox only; no network, no files, no UI)
                            └─ JavaScriptCore  ─▶  WebAssembly.Instance(module, { vey: grantedImports })
```

- **The service is a separate process** with only the App Sandbox entitlement. It links Foundation and JavaScriptCore and nothing else. A crash, a runaway loop or a memory blow-up ends there.
- **JavaScript is glue, not a runtime for extensions.** The service uses JavaScriptCore's built-in WebAssembly engine, which Apple maintains and ships with macOS, so Vey adds no third-party runtime. The module never sees JavaScript globals; a WebAssembly instance can only call the imports it is handed.
- **Imports are constructed from the manifest.** Before instantiation the service reads the module's declared imports and refuses any that the manifest does not grant. A module compiled against `clipboard.write` fails to load under a manifest that only grants `log`.
- **The app re-checks every callback.** Capabilities execute in the app (the clipboard write happens there), and the app checks the running manifest again before honoring each one. Two independent gates.
- **Integrity.** The app hashes the module and refuses to run it if the hash differs from the manifest's pin.
- **Watchdog.** If `run` has not returned within `timeoutSeconds`, the service process exits. launchd restarts it for the next call.

## ABI (spike)

The module exports `memory`, `alloc(len) -> ptr`, and `run(ptr, len) -> ptr`. The host writes the UTF-8 input into `alloc`'d memory, calls `run`, and reads a record at the returned pointer: a little-endian `u32` length followed by UTF-8 bytes. Host imports live in module `vey`: `log(ptr, len)` and `clipboard_write(ptr, len)`.

## Using it

Folders go in `~/Library/Containers/com.mysticcoders.vey/Data/Library/Application Support/Vey/Extensions/<name>/`. In the launcher, `ext hello some text` runs the extension with the text as input and shows the result. From the command line, `Vey --run-extension hello "some text"` does the same and prints the log.

Build the sample: `extensions/hello-rust/build.sh` (uses rustup's toolchain, since Homebrew's cargo lacks the wasm target).

## Verified in the spike

- Rust source → wasm → service → capability callbacks → clipboard, end to end.
- One flipped byte in the module: refused by the hash check.
- Manifest without `clipboard.write` for a module that imports it: refused at load.
- A module whose `run` loops forever: the service is killed at the timeout and the next run works.

## Not yet

Memory caps per module, a capability catalog beyond two functions, a permissions dialog at install, signed manifests, an install flow, async or streaming results, and a stable ABI. Add each deliberately.
