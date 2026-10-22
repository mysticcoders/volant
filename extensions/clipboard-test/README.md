# Clipboard Test

An owner-verification fixture for the ABI 1 `clipboard.write` capability. No bundled or catalog
extension uses it, so this one exists to check it in the installed app. It is not bundled with
Volant and is not in the catalog.

Run it and it copies one line of fictional text, `Volant clipboard test v1`, followed by anything
you typed after its name, then shows what it copied. Running it replaces your clipboard, and
clipboard history records the copy like any other.

## Build

```sh
extensions/clipboard-test/build.sh
```

It writes three extension folders under `out/`, all with the same ID:

| Folder | Code | Capabilities | Used for |
| --- | --- | --- | --- |
| `v1` | copies `… v1` | `clipboard.write` | the granted check |
| `v2` | copies `… v2` | `clipboard.write` | changed code asks for approval again |
| `denied` | same as `v1` | none | a module importing an ungranted capability doesn't load |

Install only one at a time. Two folders with the same ID are both disabled as duplicates.

## Owner checks

Settings › Extensions › Open Folder opens the Extensions folder. Community extensions must be on.

1. **Granted.** Copy `out/v1` into the Extensions folder. In Settings it lists "Write to clipboard";
   enable it. Type `Clipboard Test hello` in the launcher and press Return. The clipboard holds
   `Volant clipboard test v1: hello`.
2. **Revoked.** Copy something else, then disable Clipboard Test in Settings. Typing its name in
   the launcher no longer offers it, and the clipboard is unchanged.
3. **Changed code.** Enable v1 again, then replace its folder with `out/v2`. Approval covers the
   whole manifest, so Settings shows it off and the launcher doesn't offer it until you enable it
   again. Then it copies `Volant clipboard test v2`.
4. **Denied import.** Replace the folder with `out/denied` and enable it. Running it fails with
   an error instead of a result, because its module imports `clipboard_write` and the manifest
   grants nothing. The clipboard is unchanged.

Remove the folder (or Uninstall in Settings) when done.

`tools/check-extensions.sh` runs the committed `clipboard.wasm` (v1) with and without the
capability. That checks the runtime only, not the signed helper or the app's approval checks.
