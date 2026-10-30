# Localization

Tracking issue: #294. Volant is written in English and ships 14 translations, all drafted without
a native speaker's review and labeled as betas, by the owner's choice:

- Spanish (`es`, neutral wording for Spain and Latin America), added October 26, 2026.
- German (`de`), French (`fr`) and Italian (`it`), added October 27, 2026.
- Japanese (`ja`), Simplified Chinese (`zh-Hans`), Brazilian Portuguese (`pt-BR`), Korean (`ko`),
  Dutch (`nl`), Polish (`pl`), Russian (`ru`), Ukrainian (`uk`) and Turkish (`tr`), added October 27,
  2026.
- European Portuguese (`pt-PT`), added October 27, 2026, written separately from `pt-BR`:
  Definições, ficheiro, "A carregar…", and polite third-person address.

Each follows Apple's own macOS style in that language, including its forms of address and its terms
for Settings, System Settings, Finder (Apple's Simplified Chinese calls it 访达) and the Shortcuts
app. Plural strings carry each language's CLDR categories: one form for Japanese, Chinese and Korean,
two for most others, and four for Polish, Russian and Ukrainian. Right-to-left languages wait for the
right-to-left layout work in #294.

## Choosing the language

Settings › General › Language lists System, English and each translation by its own name, marked
beta. It writes Volant's own `AppleLanguages` preference, which is the value System Settings › General ›
Language & Region › Applications sets for each app, so the two stay in step. It is never written to
`config.json` or synced. The change applies after a relaunch, which the section offers.

## Unreviewed translations

- A translation that no native speaker has reviewed ships only as a labeled beta. Its strings stay
  in the `needs_review` state in the catalogs. Settings › About tells anyone running Volant in that
  language that the translation is an unreviewed beta, with a link to report problems.
- Marketing copy, release notes and the website call it a beta and never claim a reviewed or
  native-quality translation (`docs/marketing-claims.md`).
- A reviewer marks strings `translated` as they check them. Once every string in a language is
  reviewed, the beta labels can go.
- Never ship a language whose strings are missing from the catalog: `tools/strings.py --check`
  fails when a key has no value in a shipped language (`SHIPPED_LANGUAGES`).

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
  is new or changed and the catalog wasn't updated, when a string has no text in a shipped language, and when the
  permission prompts in `InfoPlist.xcstrings` differ from `project.yml`. It doesn't fail on unused
  strings: CI's older SDK doesn't compile macOS 26-only code, so those strings look unused there.
  A local `tools/strings.py` marks strings that really are unused as stale.
- Building in Xcode may sync `Localizable.xcstrings` itself, from the same compiler output, so the
  two agree. If they ever disagree, the script's result is the one to commit.

## Writing strings

- **App:** literals in SwiftUI views need nothing extra: `Text("Refresh")` is already localizable.
  A `String` shown to the owner (notices, footer feedback, status, labels built in the model)
  uses `String(localized: "…", comment: "…")`. Add a comment whenever the text alone doesn't say
  where it appears or what a word means; translators see only the key and the comment.
- **Core:** use `LocalizedStringResource("…", table: "Core", comment: "…")` and expose a `String`
  through `String(localized:)`, as `CoreCommand.titleResource` and `title` do. Core's extraction
  runs without the compiler, so it can't see an interpolation's type and skips any string with a
  plain `\(value)`; such a string would stay English. Interpolate only with an explicit specifier:
  `\(count, specifier: "%lld")` for an integer and `\(text, format: .verbatim)` for text
  (`VerbatimFormatStyle`), or `\(list, format: .list(type: .and))` for a list. Extraction then
  reads `%lld` and `%@`, exactly the key built at run time, and the catalog can carry plural
  variants for the count. `tools/strings.py` reports any Core string extraction skipped. Format a
  year or another number that must not be grouped as text (`String(year)`), since `%lld` follows
  the locale's grouping.
- **Plural keys in Core** are written in the plural (`"%lld panes"`), and English's singular comes
  from the catalog's `en` plural variant. `swift test` and the helpers have no catalog, so there a
  count of one shows the key's form ("1 panes"); `CoreLocalizationTests` checks the app's English.
- **Helper messages:** helpers have no catalog either, so a message worded in `VolantAgentHost`,
  `VolantAIHost` or `Shared/` reaches the app in English. A helper replies with a
  `HostMessage` code instead (`HostMessage(.rexNotRunning).wire`, or `HostMessage.wire(for:)` for a
  thrown error), in the same string reply the XPC method already has, and the app shows
  `HostMessage.display(_:)`. Text that isn't a code, such as an agent's or provider's own error,
  is shown as it arrives.
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

Run them on Volant Dev only in an agreed window, or in the VM fixtures.

The fixtures render a pseudo-locale instead: `tools/pseudo-locale.py` compiles `en-XA` from both
catalogs, with accented look-alike letters about 35% longer than English inside brackets
("[Ŕéƒŕéšĥ~~]"), keeping format specifiers, line breaks and plural categories. A clipped string
loses its closing bracket, and plain English is text that never went through a catalog.
`tools/render-vm.py --pseudo --rtl` adds runs of the Actions fixture's Servers scenario (light and
dark) and the Settings preview (every section, light and dark) in `en-XA`, and right to left with
`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`; `--layout-only` skips the default
runs, and `--build-only` compiles the bundles on the host without starting Tart. Their image names
carry `-pseudo` or `-pseudo-rtl`. The renders show layout, not translation quality.

## Status

- **Done:**
  - the catalogs, project settings and `tools/strings.py`, with `--check` in `Scripts/test.sh` (it fails on stale strings and on any string without text in a shipped language)
  - about 1,280 strings converted across the app and Core
  - Spanish drafts for every string, marked `needs_review`
  - plural variants in English and Spanish for strings that count something
  - the About notice
  - a Spanish pass of the Servers scenario in the branded Actions fixture, light and dark
  - interpolated Core messages, through `specifier:` and `format: .verbatim` interpolation: Herdr and Rex status and tooltips, extension network and storage errors, dictation results, Git summaries, AI account, attachment and connection errors, snippet, quicklink and theme errors, contact actions, the backup report, and calculator date details (relative days, days left, leap years, age, holidays) and percent change labels, with plural variants in every shipped language
  - helper messages as `HostMessage` codes: Apple Shortcuts, Herdr discovery and question delivery, Rex, fsearch, listening servers and repository errors from `VolantAgentHost` and `Shared/`, and AI errors and statuses from `VolantAIHost`
  - the `en-XA` pseudo-locale and right-to-left runs in `tools/render-vm.py`, built on the host; their VM renders still need inspecting
  - **formatting** (the owner's decision of October 30, 2026; see "Formatting" below): dates, times, numbers, durations and currency in calculator answers follow the Mac's language and region, Copy copies what the card shows, and values meant for code or parsed back keep a fixed form. Time and date answers, their Copy text and details, the tip and percentage details are translated, with drafts in every shipped language
- **Remaining (#294):**
  - **Calculator words outside dates and times:** their numbers, units and currency already follow the locale, but some words are still English: kitchen measures and ingredient names (`About 1 ¼ cups`, `Gas mark`), currency rate tags (`ECB rates · …`, `per hour`), color operation labels (`Alpha 50%`), screen-unit assumptions (`1rem = 16px`) and money-for-time phrases (`… at $20.00/hour`). Their swap queries stay English on purpose, since Volant parses them back.
  - **ACP helper text:** `ACPConnection`'s statuses and refusals ("Working…", "Needs your permission", "Volant runs up to N conversations…") are still worded in the helper, often around the agent's own text, and `tools/check-acp.sh` asserts their English. They need `HostMessage` codes with arguments.
  - **Shown values compared elsewhere:** Wi-Fi security labels, System Settings pane names, `SystemAction` titles (search has no English fallback), Raycast import category names, and ACP roles.
  - **More fixture renders:** Spanish passes of scenarios that compare English text, which need language-neutral assertions first; the pseudo-locale and right-to-left renders cover the same scenarios for the same reason.
  - **Review:** a native speaker's review, after which strings move from `needs_review` to `translated`.

## Formatting

Decided by the owner on October 30, 2026: dates, numbers and calculator answers follow the Mac's
language and region settings (the current locale), and Copy copies exactly what is shown, so it
follows the locale too, except values meant for code or other programs, which keep a fixed form.

- **Follows the locale:** decimal and grouping separators, dates (`Tuesday, October 27`,
  `Dienstag, 27. Oktober`), clock times, which use the locale's 12- or 24-hour clock and the
  owner's own 24-hour setting (`9:00 PM`, `21:00`), durations and counts with the locale's unit
  words and plurals from Foundation (`2 hours 25 minutes`, `2 Stunden 25 Minuten`, `80日`),
  currency in the locale's format for the target currency (`€80.00`, `80,00 €`), unit names, and
  spelled-out numbers. Formatter no-break spaces become ordinary spaces, so a pasted answer
  behaves like typed text.
- **Copy and Use Answer:** Copy puts the card's own text on the clipboard. Command-Return puts it
  in the search field, where numbers in the locale's format read back (`2,5 * 2` in German).
- **Stays fixed:** CSS and Swift color values (`#ff6363`, `rgb(255 99 99)`, `hsl(0 100% 69.4%)`),
  number bases and Roman numerals, ISO 8601 dates and week numbers, Unix time, and swap queries:
  a swapped time conversion keeps `9:00pm cet in est` and `2026-10-03 4:00am cet in est`, and unit
  and currency swaps write their amount the way the locale's calculator reads it
  (`3,106856 mi in km` in German). The `%` sign stays right after the number, since the calculator
  reads it there.
- **Injection:** every calculator entry point takes a `locale` (defaulting to `.current`) beside
  the injected clock and time zone. Tests pin `en_US` and check `de_DE`, `fr_FR` and `ja_JP`
  (`LocaleFormattingTests`); `swift test` has no catalog, so it checks formatting and English
  words, and `CoreLocalizationTests` in the app checks English singulars from the catalog.
