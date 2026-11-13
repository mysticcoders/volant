# Contributing to Volant

Thanks for helping. Volant is a small project, so every bug report, idea and pull request gets read.

## Ways to help

- **Try it and tell us what broke.** [Open an issue](https://github.com/mysticcoders/volant/issues/new) with your Volant version (Settings › About), your macOS version, what you typed and what happened. Leave out personal data such as clipboard contents, note text or file paths you'd rather not share.
- **Ideas and questions** go in [Discussions](https://github.com/mysticcoders/volant/discussions).
- **Pick up a starter issue.** Issues labeled [good first issue](https://github.com/mysticcoders/volant/labels/good%20first%20issue) are small and say how to check the result.
- **Write an extension.** It's the easiest way to add something to Volant, and you never touch the app. See [below](#write-an-extension).
- **Review a translation.** Every translation is a beta. If you speak German or Spanish, see [#353](https://github.com/mysticcoders/volant/issues/353) and [#354](https://github.com/mysticcoders/volant/issues/354).

## Build and test

You need macOS 15 or later, Xcode 26, xcodegen, swiftlint and uv (`brew install xcodegen swiftlint uv`). With [just](https://github.com/casey/just) installed, run `just doctor` to check these and see how to install what is missing. `just` lists the other recipes, which run the scripts below.

`Scripts/build.sh` also runs `tools/python-env.sh`. That script uses uv to make `.venv` hold the hash-locked Python packages in `tools/security/requirements.txt`, the same ones CI uses. `Scripts/test.sh` runs its Python checks with `.venv` when it exists. To use another Python, set `VOLANT_TEST_PYTHON`.

    Scripts/build.sh                     # regenerate the project and build Volant Dev
    swift test --package-path Core       # VolantCore tests: calculator, units, time zones and more
    Scripts/test.sh --base origin/main   # the checks for what your branch changed

Debug builds are **Volant Dev**, with their own bundle ID, settings and Keychain, so they never touch an installed copy of Volant. Both answer the same hotkeys, so quit one while you try the other.

`Core/` (VolantCore) is plain Foundation with no AppKit or SwiftUI. Calculator, unit, currency and time zone changes usually live there and are the quickest place to start.

The website is in `website/`: `npm ci --ignore-scripts`, then `npm run dev`, `npm run build` and `npm run lint`.

## Ground rules

These keep Volant's privacy promises true. A pull request that breaks one won't be merged, however useful it is.

- **The main app has no network access.** Network work goes through one of the existing helpers, never the app.
- **Ask for permissions on first use**, never at launch.
- **Nothing leaves the Mac without the owner choosing it**: no telemetry, and no logging of what people type, copy or write.
- **User-facing text comes from String Catalogs.** See [localization](docs/localization.md), and run `tools/strings.py` after a Debug build.
- Use US English, and comment methods rather than individual lines.

[AGENTS.md](AGENTS.md) has the full set of rules for each area, such as clipboard, extensions and agents. Read the section for the part you're changing.

## Pull requests

1. Fork, then branch from `main`.
2. Keep each pull request to one change, with tests where the change has logic.
3. Run `Scripts/test.sh --base origin/main`.
4. Describe the problem, what changes, how you checked it, and what's still untested. For a visible change, include light and dark screenshots.

The **PR gate** check must pass before merging. UI tests only run when your change touches UI files.

## Write an extension

Extensions live in [volant-extensions](https://github.com/mysticcoders/volant-extensions). Each one is a folder with a `manifest.json` and a WebAssembly module. There are templates for Rust, TypeScript and Python:

1. Start one with `tools/new-extension.py rust|typescript|python <folder> --name "Your Name"`. See [Start a new extension](https://github.com/mysticcoders/volant-extensions#start-a-new-extension).
2. Run `./build.sh` to test it, build it and pin its hash in the manifest.
3. Copy the folder into Volant's Extensions folder (Settings › Extensions › Open Folder) and type its keyword.
4. Open a pull request in volant-extensions. Once it's merged with a `listing.json`, the extension appears in the signed catalog.

An extension never touches the network itself. It returns the URLs it wants, Volant fetches them from hosts the owner approved, and the extension renders the reply. The full contract is in [extensions](docs/extensions.md) and [network extensions](docs/network-extensions.md).

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
