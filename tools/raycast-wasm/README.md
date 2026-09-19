# Raycast TypeScript → Volant WASM command adapter

The Base64 Encode command now runs through **Volant's production extension manager and sandboxed XPC helper**, using a restricted WASI Preview 1 profile designated **Volant ABI 2**. This is a text-command interface, not general Raycast API compatibility or a full WASI runtime. ABI 1 Rust commands keep their existing interface.

## Source and build

`upstream/encode.tsx` is the unchanged MIT-licensed [Raycast Base64 Encode command](https://github.com/raycast/extensions/blob/7385d56717d2666708493dae1f9e2fb4a681dc3d/extensions/base64/src/encode.tsx), revision `7385d56717d2666708493dae1f9e2fb4a681dc3d`. Upstream lists DanielSinclair as author; its license is retained in `upstream/LICENSE`.

The esbuild adapter resolves `@raycast/api` and the local `update` utility to `adapter.ts`. `Clipboard.read()` receives command input, and `update({contents})` writes command output. It does not access the actual clipboard, toast, preferences, paste target or browser. The real pinned `js-base64` dependency performs the encoding. Javy embeds the resulting JavaScript in QuickJS compiled to WASM; this is not native compilation of the TypeScript logic.

```sh
# From the repository root; Node/npm are required.
bash tools/build-raycast-example.sh
# Or use an existing compiler:
JAVY=/absolute/path/to/javy bash tools/build-raycast-example.sh
```

The macOS build helper downloads Javy 9.1.0 for Apple Silicon or Intel and checks its pinned SHA-256 before execution. esbuild 0.25.10, js-base64 3.7.8 and development-only wabt 1.0.39 are locked. `bound-memory.mjs` validates the compiler output and rewrites only its single memory declaration to impose a maximum of 256 pages (16 MiB). Hashing happens **after** that change. Generated WASM and manifest live in `extensions/raycast-base64/`, are gitignored, and are not bundled with the app. See [install/use instructions](../../extensions/raycast-base64/README.md).

## Runtime contract

ABI 2 manifests use `abiVersion: 2`, a `.wasm` module, its SHA-256, and **empty capabilities**. Both ABI versions require one defined non-shared wasm32 memory with an explicit maximum ≤16 MiB, module size ≤2 MiB, input/output ≤64 KiB and a 0.5–10 second execution deadline. The separate XPC readiness deadline and no-replay behavior are unchanged.

An ABI 2 module exports `memory` and `_start`. Only these function imports from `wasi_snapshot_preview1` are accepted:

| Import | Volant behavior |
|---|---|
| `fd_read` | Descriptor 0 reads only the user-supplied UTF-8 command input, with EOF and partial-read support. |
| `fd_write` | Descriptor 1 accumulates at most 64 KiB of result bytes. Descriptor 2 discards at most 4 KiB of diagnostics; they are never logged or surfaced. |
| `fd_close` | Closes only the invocation's virtual descriptors 0–2. |
| `fd_fdstat_get` | Reports stream type and read/write rights for those virtual descriptors. |
| `fd_seek` | Returns ESPIPE for open streams and EBADF otherwise. |
| `environ_sizes_get`, `environ_get` | Empty environment. |
| `clock_time_get` | Realtime/monotonic IDs return a fixed zero clock; other IDs return EINVAL. This is not live date/time support. |
| `proc_exit` | Terminates this invocation; zero succeeds, nonzero discards partial output and returns an error. Never exits the helper directly. |

Descriptors are entirely in memory and never map to OS descriptors. There are no preopened directories, environment variables, shell, network, random source or real clipboard APIs. Other import namespaces, names and types are rejected before instantiation. Modules must defer host calls requiring memory until `_start`, after exported memory is available. Every pointer, iovec and result range is checked; at most 1,024 iovecs and 4,096 host calls are permitted. Output must be valid UTF-8. Exceptions and nonzero exits discard partial output. A CPU loop terminates the helper through its existing watchdog; later invocations start a fresh service.

These limits cover WASM linear memory and data, not the entire JavaScriptCore process footprint. The adapter adds no app or helper entitlements and no third-party runtime to the Volant bundle. Any QuickJS runtime belongs to the extension's own bounded module. The community master gate, manifest/hash approval, pre-submission and callback/result rechecks apply unchanged; the ABI version is included in the approval fingerprint.

## Verification

`tools/check-extensions.sh` builds the example if absent and executes it through the production `ExtensionHost`/JavaScriptCore implementation. It compares empty, ASCII and Unicode Base64 results against Foundation, tests the exact output boundary and rejects oversized output. Checked-in WAT/WASM probes cover empty environment, frozen clocks, descriptor rights, EOF, closed streams, forbidden imports, prototype names, bad pointers, excessive iovecs/calls, stderr/output limits, invalid UTF-8, exit codes, memory growth and watchdog termination. Generate the probes with `node generate-probes.mjs` from this directory after `npm ci`.

`npm test` remains a **separate** Node WASI comparison using fictional stdin/stdout, empty environment and no preopened directories. It does not establish production sandbox behavior. Node WASI is not used by Volant.

`tools/check-extensions-xpc.sh` uses an exported Developer ID build and isolated fictional configuration. It exercises the actual manager's ABI dispatch through signed XPC, including the TypeScript module, existing Rust ABI, recovery and community revocation. It does not restart the owner's app or claim installed launcher interaction.

September 18, 2026 evidence: the clean checksum-verified build and standalone comparison passed; production JavaScriptCore tests passed, including exactly 64 KiB output and rejection above it; 111 native tests passed. A fresh Developer ID archive/export passed the signed XPC fixture with the real Unicode Base64 command, Rust greeting, watchdog recovery and master revocation. A regression probe also verifies that caught `proc_exit` cannot resume I/O. Local UI checks were explicitly skipped because this change preserves the existing launcher/Settings surfaces; this is not installed-app UI verification.

No latency or total-memory benchmark has been performed. Next: an installed-app first-use/copy smoke test in an agreed window, package/update distribution and notice handling, and only then additional explicitly reviewed APIs. React views, Node APIs, real clipboard reads, filesystem/network commands and general Raycast compatibility remain unsupported.

## Original experiment

The first experiment produced a 1,361,532-byte unbounded-memory module that ran only under standalone Node WASI. ABI 1 correctly rejected it. The production adapter fixes the memory declaration at build time and explicitly routes ABI 2 modules through the new command contract. Merely compiling a module never implied Raycast API compatibility.
