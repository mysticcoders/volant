# Localization

Tracking issue: #294. Volant ships in English only. This page covers the infrastructure that lets
strings be translated, and the rules for writing new ones. No other language has been chosen yet;
that, and who translates, is the owner's decision. Never ship unreviewed machine translation.

## Where strings live

| Catalog | Holds | Filled from |
| --- | --- | --- |
| `Volant/Resources/Localizable.xcstrings` | The app's strings: SwiftUI `Text`, `Button`, `Toggle` and similar literals, plus `String(localized:)` and `LocalizedStringResource` | The `.stringsdata` the compiler writes for the Volant target (`SWIFT_EMIT_LOC_STRINGS`), so interpolations keep their real format specifiers (`%lld of %lld`) |
| `Volant/Resources/Core.xcstrings` | VolantCore's strings, written with `table: "Core"` | `xcstringstool extract` over `Core/Sources`, because the package target emits no `.stringsdata` |
| `Volant/Resources/InfoPlist.xcstrings` | The permission prompts macOS shows (Contacts, Calendar, Location, Bluetooth, Microphone, Apple Events) | By hand; the English must equal `project.yml` |

`VolantCore` is a static library with no resource bundle, so its strings are looked up in the main
bundle's `Core` table. In the app that table exists. In the helpers, `swift test` and the ad-hoc
`swiftc` checks it doesn't, and the lookup returns the English source text instead of failing.
Never add a SwiftPM resource bundle or `Bundle.module` to Core: its accessor traps when the bundle
is missing, which it is in every helper process.

## Keeping catalogs current

- `tools/strings.py` updates `Localizable.xcstrings` and `Core.xcstrings` from the source. Run it
  after a Debug build into `build/` (`Scripts/build.sh`, or the test build in `Scripts/test.sh`),
  then review and commit the catalogs.
- `tools/strings.py --check` runs in `Scripts/test.sh` after the test build. It fails when a string
  is new, unused or changed and the catalog wasn't updated, and when the permission prompts in
  `InfoPlist.xcstrings` differ from `project.yml`.
- Building in Xcode may sync `Localizable.xcstrings` itself, from the same compiler output, so the
  two agree. If they ever disagree, the script's result is the one to commit.

## Writing strings

- **App:** literals in SwiftUI views need nothing extra: `Text("Refresh")` is already localizable.
  A `String` shown to the owner (notices, footer feedback, status, labels built in the model)
  uses `String(localized: "…", comment: "…")`. Add a comment whenever the text alone doesn't say
  where it appears or what a word means; translators see only the key and the comment.
- **Core:** use `LocalizedStringResource("…", table: "Core", comment: "…")` and expose a `String`
  through `String(localized:)`, as `CoreCommand.titleResource` and `title` do. Core strings must
  not interpolate, because Core's extraction can't know the format specifiers. Pass values to the
  app and build the sentence there, or add a specific format string by hand.
- **Whole sentences.** Never assemble a sentence from fragments, and never pluralize with
  `count == 1 ? … : …`. Use an interpolated `String(localized:)` and let the catalog hold plural
  variants.
- **Stays English, never localized:**
  - `config.json` keys and its `_help` text
  - log and diagnostic messages
  - extension manifest fields and the WASM ABI
  - anything parsed back or compared
  - the launcher's typed command words (`servers`, `caffeinate`, `clip`, `:`, the reserved words in
    `LauncherRouting`), so config, aliases, Raycast import and the docs work in every language.
    Displayed command names are translated, and `CoreCommand.search` matches the translated name
    and the English one.
- **No owner text through localization.** Queries, clipboard contents, note text and results are
  never keys, and `AGENTS.md`'s rule against logging them still applies.
- Use `Text(verbatim:)` for text that must never be looked up, such as a port number on its own.

## Checking layout without a translation

These launch arguments affect only lookups that go through a catalog, so they also show which text
is still hard-coded:

- `-NSDoubleLocalizedStrings YES` doubles every localized string, roughly the growth of German or
  Finnish.
- `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES` lays the app out right to left.

Run them on Volant Dev only in an agreed window, or in the VM fixtures; adding pseudo-locale fixture
renders is part of #294.

## Status

- Done:
  - the three catalogs, the project settings and `tools/strings.py`
  - the `--check` in `Scripts/test.sh`
  - command names and descriptions in Core (`CoreCommand`)
  - the Servers command's strings in the app, as the worked example
  - the permission prompts
  - `CoreLocalizationTests`, which checks Core strings resolve from the `Core` table
- Remaining (see #294):
  - the other plain-`String` messages in the app (about 280)
  - the other user-facing strings in Core (about 120)
  - AppKit menu titles and accessibility labels
  - locale-aware output formatting decisions
  - pseudo-locale and right-to-left fixture renders
  - choosing languages
