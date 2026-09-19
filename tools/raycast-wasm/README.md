# Raycast TypeScript → WASM experiment

This is an isolated developer experiment, not a shipped extension or a general Raycast compatibility layer. No changes to Volant's WASM ABI or sandbox permissions are needed to keep this experiment in the repository.

## Source and adapter

`upstream/encode.tsx` is the **unchanged** MIT-licensed Base64 Encode command from [raycast/extensions](https://github.com/raycast/extensions/blob/7385d56717d2666708493dae1f9e2fb4a681dc3d/extensions/base64/src/encode.tsx), revision `7385d56717d2666708493dae1f9e2fb4a681dc3d`. Upstream lists DanielSinclair as author. Its MIT license is retained in `upstream/LICENSE`.

The command imports `Clipboard` from `@raycast/api`, `update` from its local utility, and `encode` from `js-base64`. We bundle the real command and pinned `js-base64` dependency with esbuild. The two host-facing imports resolve to `adapter.ts`: fictional stdin supplies the clipboard text and stdout captures the result. There is no real clipboard access, paste, browser opening, toast, preferences, React view, network or filesystem capability. The original extension's default-action preferences and UI are not implemented. The adapter is a test harness, not an authorization boundary for arbitrary code.

Javy then embeds the resulting JavaScript in its QuickJS WASM runtime. This does **not** convert the TypeScript logic directly into native-speed WASM instructions. See [Javy](https://github.com/bytecodealliance/javy) and [AssemblyScript's compatibility limits](https://www.assemblyscript.org/concepts.html).

## Reproduce

Requirements: Node 24, npm, and [Javy 9.1.0](https://github.com/bytecodealliance/javy/releases/tag/v9.1.0). Download the compiler for your platform and verify its release checksum. The tested `javy-arm-macos-v9.1.0.gz` SHA-256 is `99e9ec6a8e8c98e119d137c08a921d2443d3b873c675a5571e1800f4451e6294`.

```sh
cd tools/raycast-wasm
npm ci --ignore-scripts
JAVY=/absolute/path/to/javy npm run build
npm test
```

The harness runs the resulting WASM with Node's WASI Preview 1 implementation, empty environment and no preopened directories. Only fictional input/output files are passed as descriptors. Node documents WASI as experimental; this is not the production sandbox. Generated files and node_modules are ignored and not shipped in Volant.

To test the result against the actual production ABI validator/host, from the repository root:

```sh
fixture=$(mktemp -d /tmp/volant-raycast-check.XXXXXX)
cp tools/raycast-wasm/check-host.swift "$fixture/main.swift"
swiftc Shared/ExtensionProtocol.swift VolantExtensionHost/ExtensionHost.swift "$fixture/main.swift" -o "$fixture/check"
"$fixture/check" tools/raycast-wasm/out/encode.wasm
```

## Evidence — September 18, 2026

- Javy 9.1.0 + esbuild 0.25.10 + js-base64 3.7.8, Node 24.16.0 on Apple Silicon.
- Compiled WASM: **1,361,532 bytes** (~1.36 MB / 1.30 MiB), including its JavaScript runtime. This is about 75× our 18,245-byte Rust Hello World; these are different commands, not a like-for-like size or speed benchmark.
- The unchanged upstream encode function ran successfully for empty input, `Hello, Volant!`, `café ☕ 日本語`, and 4,096 ASCII characters. Outputs matched Node's independent Base64 implementation.
- Imports nine `wasi_snapshot_preview1` functions for environment, clock, file descriptors and process exit. Exports `memory`, `cabi_realloc`, `config-schema`, `_start`; it does not export Volant's `alloc`/`run` ABI.
- Production `ExtensionHost` rejected the module at bounded-memory validation. Even after fixing that declaration, the WASI imports and entry point are incompatible with ABI 1. Do not install this artifact into Volant or broaden imports merely to make it load.
- No execution-speed or memory-footprint benchmark was performed. The artifact size is not runtime memory usage.

## Next decision

For a real first compatible command, choose between an explicitly supported JavaScript command runtime in the existing XPC helper, or a reviewed WASI adapter with bounded memory, stdin/stdout, timeout and capability semantics. JavaScriptCore already runs JavaScript, so carrying QuickJS inside WASM may add unnecessary work. Neither option supplies Raycast's React UI, Node APIs or extension API automatically. Begin with a narrow no-view command contract and test signed delivery separately before advertising Raycast compatibility.

The app's master community switch and per-extension approval still apply to any future adapter. Installing code, globally allowing community extensions, and approving a particular extension are separate steps.
