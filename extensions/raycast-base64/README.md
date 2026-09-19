# Base64 Encode — adapted Raycast command

This example runs the real Raycast Base64 Encode command as WASM through Volant's sandboxed XPC helper. It requires Volant with **command ABI 2** support. The original TypeScript command is unchanged; its host-facing imports are adapted to typed input and returned output.

From the repository root:

```sh
bash tools/build-raycast-example.sh
```

The build uses pinned npm dependencies and Javy 9.1.0, verifies the downloaded compiler checksum, adds a 16 MiB memory maximum and generates `encode.wasm` plus a hash-pinned `manifest.json` in this folder. You can set `JAVY=/path/to/javy` to use your own compiler. Generated runtime bytes are local build outputs, not checked-in binaries or bundled app resources.

1. Open Volant Settings → Extensions → Open Extensions Folder.
2. Copy this folder into that directory and click Refresh.
3. Turn on **Allow Community Extensions**. The individual command still starts disabled.
4. Type `ext base64 Hello, Volant!` and choose **Enable and Run**.
5. The result is `SGVsbG8sIFZvbGFudCE=`. Press Return on the result only if you want to copy it.

The command does **not** read or overwrite your clipboard automatically. The Raycast `Clipboard.read()` call receives the text typed after `ext base64`; its `update()` helper returns text to Volant. Raycast's paste/browser preferences and custom UI are not implemented. No permissions are requested by this sample. Disabling community extensions or the individual module prevents further runs; changed module hashes need approval again.

The TypeScript source and MIT attribution are in `tools/raycast-wasm/upstream`; build/runtime details and limits are in [the adapter guide](../../tools/raycast-wasm/README.md). Public distribution of third-party runtime build outputs is separate from this source example and should include the embedded dependencies' required notices.
