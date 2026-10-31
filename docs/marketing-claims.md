# Marketing claims — October 7, 2026 (0.2.0)

## Promise and release boundary

Keep work moving without leaving your flow: apps, answers, notes, and agents within reach. Keep the established “Your Mac. Your agents. One shortcut away.” headline and graphite/coral site system.

The public artifact is Volant 0.3.1, build 17 (October 13, 2026; build commit and notarization in `docs/release-quality.md`). It adds the Extension Catalog in the launcher, per-extension storage with row actions, extension icons, filler-word removal and dictation sounds over 0.3.0 build 16, which added the signed extension catalog with Install and Update over 0.2.7 build 15, which added network extensions with per-host approval, a Network Access list and extension uninstall over 0.2.6 build 14, which added opt-in dictation typed at the cursor, several AI conversations at once and provider accounts per conversation over 0.2.5 build 13, which added Caffeinate's keep-display-on-and-unlocked setting, lowering the volume while dictating, a floating dictation indicator that keeps the owner's app focused, creating snippets and quicklinks from the launcher, lighter AI Chat polling and clearer shortcut confirmations over 0.2.4 build 12, which added unit-math parentheses, daylight-saving explanations for time conversions, lazy notes loading, clipboard image capture alongside text, default-app handoff, per-copy app shortcuts and smaller fixes over 0.2.3 build 11, which added ACP conversation resume and the typing-pause fix over 0.2.2 build 10 (`e45903c`), which added the Volant menu, list edge fades under a translucent footer, the Herdr footer status, and the re-landed Notes editor theme colors. The rows below that were Coming next for 0.1.5 shipped in 0.2.0, verified against the notarized DMG: version, both architectures, stapled signature, iCloud key-value and loginwindow entitlements, and the embedded Developer ID profile. Advance claims only after verifying the actual distributed artifact; merging a website PR does not distribute a new app or publish the website.

| Story | In 0.2.0 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Apps, learned ranking, aliases, shortcuts, files, contacts, calendar | Yes | Existing native fixtures; hardware shortcut delivery is separate | Everyday launcher story |
| Markdown notes, encrypted clipboard, snippets, Raycast data import | Yes | Persistence and native fixture coverage; supported import types only | Useful things within reach |
| Basic arithmetic, units, timezone cards, city lookup | Yes | Core and native coverage | Existing download remains useful |
| Expanded percentages, dates, cooking, colors, fiat/crypto, answer reuse | Yes | #137–#149; signed rates helper fetched ECB, ExchangeRate-API and keyless CoinGecko; keyed CoinGecko path unverified | Answers as you type; New in 0.2.0 |
| Local Herdr status, supported Claude/Codex responses | Yes | Local installed response evidence and isolated routing checks | Actionable agent workflows; supported questions only |
| Saved remote Herdr machines | Yes | Fictional routing tests; compatible remote signed-app focus/answer smoke remains pending | Requirements and verification qualification in Agents docs |
| OpenCode, Claude Code, Codex ACP conversations | Yes | Existing verified provider paths; Claude/Codex require adapters | Separate new conversations from terminal panes |
| Resume the last ACP conversation | Yes, from 0.2.3 | #174; protocol fake-agent checks, model tests, native light/dark header fixture; owner resumed a real conversation in the installed app; only the latest conversation per provider and folder | Agents docs; no conversation picker claim |
| Cursor ACP | Launch path only | End-to-end verification pending | Explicit qualification |
| API/local models | Yes | HTTP and signed-helper fixtures; live authenticated provider/local inference remains separate | Implemented options, no blanket readiness claim |
| Apple Intelligence | Yes, eligible macOS 26+ | Signed sandboxed streamed probe; installed UI remains unverified | OS and eligibility requirement, docs limitation |
| Explicit note/clipboard-text attachments | Yes | #100; native picker and transport fixtures; live provider attachment prompt unverified | User-selected context, not automatic sharing; no snippets/files/images claim |
| Audio, connectivity, keep-awake, Settings panes | Yes | Native and functional fixtures; hardware and OS destination coverage is scoped | Everyday Mac controls |
| Color themes, Raycast theme import, themed Notes | Yes | #147, #148, #150; owner checked theme switching in the installed app | New in 0.2.0 |
| Lock, sleep, screen saver, restart/shutdown/logout | Yes | #102; native fixtures, sandbox probes, owner checked in the installed app | New in 0.2.0; OS confirmation for disruptive actions |
| Opt-in iCloud settings sync | Yes | #153 entitlement and Developer ID profile, present in the notarized 0.2.0 DMG; owner verified settings syncing between two Macs on October 7, 2026; quota and account-change notifications unverified | New in 0.2.0; selected settings only, no notes/history/keys |

Added in 0.2.6:

| Story | In 0.2.6 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Dictation typed at the cursor (opt-in output; while speaking or when finished) | Yes | Fake-client unit tests; a VM run of the real Developer ID signed helper with a stand-in container (TextEdit through Accessibility, Chrome through the paste fallback, password fields refused, app change refused, Return finishes). The owner dictated into Obsidian (Electron) and Claude Code in Ghostty with the installed app and live speech on October 14, 2026; other Electron apps and terminals remain unverified (docs/dictation-at-cursor-design.md) | Never "no Accessibility", only "no Accessibility unless you choose Type at the cursor" |
| Several AI conversations at once (up to six) | Yes | #197 (contributed); slot limit tests, ACP check, native fixtures and light/dark renders; several live conversations with real providers in the signed installed app unverified | Agents docs; no unattended or fan-out claims |
| Provider account per conversation (Claude Code, Codex) | Yes | #200 (contributed, reworked); account tests, ACP check, renders; real second-account conversations and per-folder Keychain logins unverified | Agents docs; Volant never reads or copies the account folder; no automatic routing |

Added in 0.2.7:

| Story | In 0.2.7 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Network extensions (Hacker News, Lobsters) with per-host approval | Yes | #214; Core boundary tests, extension manager tests, production JavaScriptCore runs of a list fixture, an installed-acceptance VM run of the notarized DMG that approved hosts, read real stories and opened links, and the owner using both readers in the installed app on October 12, 2026; readers live in the separate mysticcoders/volant-extensions repository and are installed by copying a folder | Extensions docs; the module has no network access, Volant fetches only approved https hosts; no catalog or one-click install claim |
| Network Access list and extension uninstall | Yes | #214; same VM run removed a host and uninstalled an extension with orphaned-host pruning | Extensions docs |

Added in 0.3.0:

| Story | In 0.3.0 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Signed extension catalog with Install and Update in Settings | Yes | #218; Core and app tests with a throwaway key and in-memory files, native light/dark renders, and the published catalog (sequence 5) decoded and both packages verified by the production code on the host. The notarized 0.3.0 DMG installed both readers from the live catalog in the installed-acceptance VM (#220), and the owner's installed app, updated from 0.2.7 through Sparkle, listed the catalog on October 12, 2026; only the Hacker News and Lobsters readers are listed | Extensions and Privacy docs; "signed, reviewed extensions", never "Raycast extensions", a store, or automatic updates |

Added in 0.3.1:

| Story | In 0.3.1 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extension Catalog in the launcher (search, details, Install, Update, Turn On) | Yes | #224, #225, #230; launcher catalog tests (typing never fetches), VM renders; the owner used it in a Developer ID test build on October 13, 2026 | Extensions docs; "reviewed, signed extensions", never a store or automatic updates |
| Per-extension storage and row actions; Hacker News and Lobsters pin, hide and read state | Yes | #226, #227, volant-extensions #6; Core and app storage tests, the real reader module run through the production extension runtime, VM fixture of Pin; signed installed-app use pending the release's acceptance run | Extensions and Privacy docs; "kept only on this Mac", 16 KB, never synced or backed up |
| Extension icons | Yes | #222; tests and VM renders with a fictional icon; the readers' icons are their sites' marks, credited in volant-extensions | Extensions docs only; no logos on the website |
| Filler words removed from English dictation | Yes | #229; Core cleanup tests; the owner confirmed fillers gone in a Developer ID test build on October 13, 2026 | Privacy docs; English only, cannot fix a filler heard as another word |
| Dictation start and stop sounds | Yes | #229; ordering unit tests; the owner heard them in the installed app on October 14, 2026 | System control docs |
| Turned-off extensions hidden from search; one Refresh | Yes | #230; launcher tests and VM fixture | Extensions docs |

Added in 0.3.3 (built once as 0.3.2, never published; see release-quality.md):

| Story | In 0.3.3 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Optional fsearch file search (whole disk, typo tolerance) | Yes | #234, #235; Core and app tests, the client against the owner's real fsearch daemon, the owner's installed Developer ID build on October 14, 2026 | Launcher docs; "works with fsearch if you run it", never implying Volant searches the disk itself or bundles fsearch |
| Redesigned Settings: searchable sidebar, theme colors, sections for Keyboard Shortcuts, Dictation, File Search and About | Yes | #236; VM renders in light, dark and palette themes, the launcher fixture's Settings checks, the owner's look at a development-signed install on October 14, 2026 | Settings paths in the docs updated (Dictation, File Search, Import from Raycast); no screenshots of Settings on the website |
| What's New in the app (bundled release notes) | Yes | #240; Core parser tests, launcher menu test, VM renders in light and dark | Release notes only; no website change |

Added in 0.3.4:

| Story | In 0.3.4 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extensions the owner allows get their approximate location (about 11 km), shared with the sites they read; the Location prompt and Settings say so | Yes | Core tests for rounding, grants and validation, app tests that location goes only to allowed extensions and never into config; not yet run with real Location Services in a signed build | Privacy, System control and Extensions docs: "an extension you allow can receive your approximate location (about 11 km), and so can the sites it reads"; Wi-Fi names still never request coordinates |
| Extension rows open declared app links, such as a Todoist task in Todoist.app, falling back to the web link | Yes | Core tests for scheme validation and declared-only links, an app test of the fallback; not yet opened through an installed Todoist.app | Extensions doc updated on main: an extension may open its own app if it says so first; live with the next release |
| Extension tokens kept in the Keychain and added only for their host; actions may POST, confirm, and run from Return (for the Todoist extension) | Yes | Core validation tests, app tests that the token reaches only its host and never the module or config, that only actions may POST, and the opened phase cannot; no live Todoist account test yet | Privacy and Extensions docs: tokens stay in the Keychain and go only to their host; changes only from an action you choose |
| List extensions fetch in up to three rounds with state, every request says US or metric units, and limits rise to 1 MiB in, 256 KiB out, 512 KB per fetched page and 256 KB of storage | Yes | #242; Core and app tests (rounds, round limit, a host removed mid-run), `tools/check-extensions.sh` with exact-boundary probes, VM extensions acceptance 44/44 | Extensions and Privacy docs updated on main (rounds, units, 512 KB pages, 256 KB storage); live with the next release, which includes #242 |

Added in 0.3.5:

| Story | In 0.3.5 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extension rows can show one of Volant's weather icons (sun, rain, snow and 12 more), drawn by Volant | Yes | Core tests that known names survive and unknown ones are dropped, an app test that every symbol exists in SF Symbols, VM renders in light and dark | Extensions doc: rows can show Volant's weather icons, drawn by Volant |

Added in 0.3.6:

| Story | In 0.3.6 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Settings explains community extensions before they are turned on, and hides the catalog and community rows until then | Yes | #252; VM renders of the off and on states in light and dark; the installed-acceptance script presses the new Turn On button but has not run against it yet | None; Settings only |

Added in 0.3.7:

| Story | In 0.3.7 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| List extensions get their own scope in the launcher: Return enters, a Back chip shows the extension, typing goes only to it, Escape clears then leaves | Yes | #256; Core and app tests, a launcher fixture driving real key dispatch, VM renders in light and dark; not yet checked in the signed installed app with the real extensions | Extensions doc: how to enter and leave an extension |

Added in 0.3.8:

| Story | In 0.3.8 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extension rows show up to three badges (points, comments, site, author, time) drawn by Volant, and Command-K on a row lists Open Link, its second link (such as Open Comments) and Copy Link | Yes | #258; Core tests for trimming, the three-badge cap and unknown symbols, app tests that every badge symbol exists in SF Symbols and of the menu entries, VM renders of badges and the story Actions menu in light and dark; Hacker News badges are volant-extensions #12, held until this ships; not yet checked in the signed installed app | Extensions doc: badges and the link actions in Command-K |

Added in 0.3.9:

| Story | In 0.3.9 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extensions can add a dropdown at the end of the search field (Command-P picks the next entry), sent to the extension as its filter | Yes | #260; Core validation and fingerprint tests, launcher tests of the default, choosing, Command-P, wrapping and the remembered choice, a VM fixture driving Command-P through the panel, renders in light and dark; Hacker News's Top, New, Ask HN and Show HN are volant-extensions hn-filters, held until this ships; not yet checked in the signed installed app; the owner used the updated Hacker News filters in the installed 0.3.9 on October 16, 2026 | Extensions doc: the dropdown and Command-P |

Added in 0.3.10:

| Story | In 0.3.10 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Settings → Extensions lists installed extensions with Check for Updates, Update All and per-extension Update; Browse Extensions is its own sheet | Yes | #270; app tests of the installer and VM renders of the up-to-date, update, Browse and paused states; Update in the signed installed app needs a second published version of a listed extension and is unverified | Extensions doc: Check for Updates, Update All, Browse Extensions; never automatic or background updates |
| A catalog update keeps an enabled extension on unless it asks for new access | Yes | #270; Core tests of which manifest changes count as new access, app tests that an equal-access update stays on, a wider one turns off and an owner-disabled one stays off | Extensions doc |
| Extensions withdrawn from the signed catalog are turned off, show why, and can't be enabled, run or reinstalled | Yes | #270 and volant-extensions #15; Core and app tests of matching, persistence and rollback, a VM render of the withdrawn row; no extension has been revoked in the live catalog, and a revocation reaches a Mac only when its owner checks for updates | Extensions and Privacy docs; never "remote kill switch" or background protection |

Added in 0.3.11:

| Story | In 0.3.11 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Dictation vocabulary: words written your way, with mishearings, import and iCloud settings sync | Yes | #272; Core tests including the recognizer's actual mishearings, VM renders of Settings and the editor; recognizer hints measured and ignored by SpeechTranscriber; live dictation with a vocabulary and real exports unverified | Privacy and System Control docs; corrections, never "trains the recognizer" or "learns your words" |
| Close matches by sound for words the spell checker doesn't know | Yes | #273; Core tests and a false-positive scan over 5,103 lines of Markdown with the system spell checker; the owner's own speech unverified | Docs: only unknown words change, real-word mishearings need Also heard as |

Added in 0.3.12:

| Story | In 0.3.12 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| `rex` lists Rex panes with waiting ones first, filters them and focuses one | Yes | #276, #277; Core and app tests, `tools/check-rex.sh` against fake `rex` scripts, VM renders in light, dark, compact and large; the owner focused panes across sessions in an installed Volant Dev build with Remote Control on; the Release-signed helper and the activation fallback are unverified | Home page agents item 02 with a native Actions-fixture capture (fictional panes, release asset catalog) and the Agents doc; "reads what programs report to Rex", never "monitors your terminals" or "reads pane output" |
| Switching sessions needs Rex's Remote Control, and Volant says so when it's off | Yes | #277; the refusal measured live with Remote Control off and the switch with it on; three `rex://` URL forms tried by the owner did nothing, so Volant doesn't use the scheme | Agents doc names the Rex setting |
| Rex footer status ("Rex: 2 waiting"), off by default | Yes | #276; VM renders and app tests; changes arrive about 50 ms after Rex's watcher prints them, measured outside the app; a program's own reports can lag | Agents doc |

Added in 0.3.13:

| Story | In 0.3.13 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Rex Overview: every session and tab drawn as its real pane layout, colored by status, click to focus | Yes | #279; Core parse tests, app tests, a VM render of the fictional overview in light and dark; the owner used it in Volant Dev and then in the installed, Release-signed 0.3.13 against live Rex; no keyboard navigation, floating or zoomed panes | Home page agents item 02 with a native Actions-fixture capture (fictional sessions and screen text), Agents doc |
| Opt-in pane previews: last 12 screen lines per pane, read only while the overview is open | Yes | #279; `rexPanePreviews` off by default, per-Mac, not synced; app tests that nothing is read without the window open and previews on, and that turning off forgets at once; `check-rex.sh` that the watcher reads screens only in preview mode; Rex returns full scrollback, about 100 KB for 15 panes | Privacy and Agents docs; "shows what's on screen once you turn it on", never "monitors" or "records" terminals; always say off by default |

Added in 0.3.14:

| Story | In 0.3.14 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Rex Overview keyboard navigation: arrows between tabs and panes, Tab to waiting panes, Return to focus, Esc to close | Yes | #284; Core tests of every move and identity-based selection across refreshes, app tests of the key handler, the native fixture driving the real window's keys; VM renders of the selection in light and dark | Agents doc lists the keys; home download line |
| Floating and zoomed panes drawn as Rex shows them, with chips for panes a zoom hides | Yes | #285; floating coordinates checked against a temporary Rex session; Core parse and navigation tests; VM renders; the owner used it in Volant Dev against live Rex; floating panes can only be created through Rex's API | Agents doc; never claim Volant creates or arranges panes |
| Minimize sessions in the Rex Overview, remembered per Mac | Yes | #285; Core and app tests, the fixture minimizing through the window's keys, VM renders; kept by session ID, the 200 most recent | Agents doc |

Added in 0.3.15:

| Story | In 0.3.15 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Data, the clipboard Keychain item and the extension ABI renamed from Vey to Volant, moved once on first launch | Yes | #288; Core tests of the folder move (only-old, both, fresh, failed move) and defaults, injected-Keychain tests of the key copy and read-back, isolated-SQLite fingerprint rehash; the move on a real installed copy and the Keychain item under the signed app need installed-app evidence; going back to 0.3.14 doesn't see the moved data | Home download line; release notes say a downgrade starts without the data. Never claim it was tested on every Mac |
| Command extension failures shown in the launcher | Yes | #289; app test that a failed run replaces the rows with its notice, failing without the fix; found by the owner's Clipboard Test check on 0.3.14 | Home download line |

Added in 0.3.16:

| Story | In 0.3.16 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Listening servers: `servers`/`ports` lists the owner's listening TCP ports by runtime, folder and age; Return opens localhost, Actions copy | Yes | #292; Core tests including a real-socket scan (loopback vs all interfaces, closed socket gone), launcher tests with a scripted helper, native fixture renders; live scan matched `lsof` on the owner's Mac; signed-helper delivery in the installed app needs installed evidence; runtime logos from Simple Icons are their owners' trademarks, licenses in About. Read-only: never stops a process | System control and Privacy docs; home download line; never say Volant stops or manages servers |

Added in 0.3.20:

| Story | In 0.3.20 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| 13 beta translations (Spanish, German, French, Italian, Japanese, Simplified Chinese, Brazilian Portuguese, Korean, Dutch, Polish, Russian, Ukrainian, Turkish) and a Language setting | Yes | #296–#299; drafted without native speakers' review and shipped as labeled betas by the owner's choice (docs/localization.md); about 1,280 strings each with each language's plural forms; some messages stay English (helper-produced, compared values, about 40 interpolated Core messages); translated fixture renders cover the Servers scenario only. Settings › General › Language sets Volant's per-app language | Home download line; release notes. Always "(beta)" or "beta, unreviewed translations"; list languages only as betas; never "fully translated", "native", "localized for <country>" or "14 languages" without "beta" |

Added in 0.3.21:

| Story | In 0.3.21 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| European Portuguese (pt-PT) beta, separate from Brazilian Portuguese | Yes | #301; drafted without native review like the other betas; written from English with pt-BR only as a reference (Definições, ficheiro, "A carregar…") | Home download line; release notes. Say "European Portuguese (beta)"; never imply both Portuguese variants were reviewed |

Added in 0.3.22:

| Story | In 0.3.22 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extension preferences: list extensions declare toggles, text, dropdowns and numbers; owners set them in Settings › Extensions | Yes | #303; Core and app tests, fixture renders of the row and sheet; Hacker News 0.5.0 (volant-extensions#17) is the first to declare them | Extensions docs; release notes; claim for list extensions only; never say preferences can hold tokens |

Added in 0.3.24:

| Story | In 0.3.24 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| A blended launcher: no lines under the search field or above the footer; the footer fades in at its top edge and is solid beneath its labels | Yes | #317; macOS 27 VM renders in light and dark, theme render label contrast 9.86–18.02:1 with rows still showing through the top band; the owner tuned it in Volant Dev. No fixture captures a long list scrolled under the footer, and Reduce Transparency wasn't rendered | Home download line; release notes |
| Extension clipboard permission: an extension that declares `clipboard` gets the clipboard's plain text once per run, up to 64 KB, never concealed or password-manager items | Yes | #308; Core tests of the filter and manifest rules, app tests of when it is read and sent; no signed installed-app read yet, and no catalog extension uses it | Extensions docs; release notes. Never say Volant reads the clipboard in the background, and never call it "secure" beyond the filter's stated rules |
| Text commands with `"input": "json"` get preferences, saved data and the clipboard | Yes | #308; app tests of the request and reply; no catalog extension uses it yet | Extensions docs; release notes |
| Typing in a list extension stops the earlier search; leaving or closing stops it; row actions are never interrupted | Yes | #307; app tests with a scripted fetcher; a module already running finishes within its time limit. Not verified through the signed fetch helper | Release notes |
| Extension activity recorded by Volant (in memory only) | Not shown to owners | #309; no UI, persistence or export yet (#68) | None until #68 ships |

Added in 0.3.25:

| Story | In 0.3.25 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extension updates listed in the launcher from the last accepted signed catalog, never fetched to show it | Yes | #324; tests that the row comes only from the saved, re-verified index and makes no fetch, and a tampered index shows nothing; VM renders light/dark | Extensions docs; release notes |
| Optional daily catalog check, off by default, per Mac, not synced; applies revocations, never installs | Yes | #324; tests that it is off by default, runs at most once a day across all checks; not verified through the signed fetch helper against the live catalog | Extensions and privacy docs; release notes. Always say off by default |
| Catalog icons before install, checked against the signed catalog's SHA-256 | Yes | #322; tests of hash and shape refusal and one fetch per icon; launcher fixture shows a not-installed listing's icon | Release notes |
| AI Chat streaming sends only changed messages | Yes | #321; memory fixture: 1 MB conversation 26.9 → 0.83 MiB/s allocated, 20.4 → 1.8 ms/s CPU; not verified with a real provider through the signed helper | Release notes; give figures as measured on a fixture, not a promise for every conversation |

Added in 0.3.26:

| Story | In 0.3.26 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Dictation keeps capturing 200 ms after release, starts capture before the recognizer is ready, and discards near-silent dictations | Yes | #327; Core level tests; the owner dictated with it in Volant Dev on October 30, 2026; macOS 26 only, like all dictation; no fixture verifies a real microphone or recognizer | Release notes; say "keeps your last word" and "an accidental tap types nothing", never "perfect" or "never misses a word" |
| ACP helper allocates less while handling provider frames | Yes | #326; fixture: 1 MB conversation build 62.6 → 55.7 MiB allocated | Release notes only; too small for marketing |

Added in 0.3.27:

| Story | In 0.3.27 | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Extensions run faster: modules reach the sandbox as one typed-array copy | Yes | #330; in-process fixture with the production host: Base64 warm run 42.9 → 5.5 ms, peak footprint 91 → 61 MiB; not measured through the signed XPC helper | Release notes; give figures as fixture measurements |
| Interpolated Core messages and helper messages translated in every beta language | Yes | #331; app-hosted English checks, Core round-trip tests, pseudo-locale and right-to-left VM renders; translations remain unreviewed betas; calculator answers still English | Release notes; always say beta |

Merged after 0.3.27, not in the current download:

| Story | Released | Evidence and limits | Website treatment |
| --- | --- | --- | --- |
| Calculator answers follow the Mac's language and region (dates, 12/24-hour clocks, durations, currency), and Copy matches the card | No | #294; Core tests pin en_US and check de_DE, fr_FR and ja_JP formatting, Copy and swap round trips; translated words are unreviewed betas; kitchen, currency-tag and color words are still English; not verified in a VM render | Release notes; say beta for translated words |

## Privacy language

No Volant account or telemetry. Notes and encrypted clipboard history remain local. Submitted AI prompts and selected context reach the chosen provider/server. Keys stay in Keychain. Updates, HTTP AI, rates and network extensions use separate helpers; opt-in iCloud uses Apple's system service. Avoid blanket “everything stays on your Mac,” “entirely offline,” or “zero dependencies” claims. Say “no Accessibility unless you choose Type at the cursor”: the main app stays sandboxed and never uses Accessibility, and only the separate input helper does, listed as Volant in System Settings, after the owner picks that output.

## Imagery

Existing hero and Notes assets are native fixtures. Added calculator, waiting-question, and unsent attachment-draft images come from the production SwiftUI views compiled with the release-optimized asset catalog, in a headless macOS 27 Tart guest. All stores, project names, session identifiers, note text, and questions are fictional. Agent input and network/provider connections are injected or absent. Light/dark captures are inspected separately. Render success is not a live provider, remote-machine, hardware, or performance test.

## Next concrete gaps

1. Done October 7, 2026: published the 0.2.0 website, verified DMG delivery, activated the signed build-8 appcast, and the owner completed 0.1.5 → 0.2.0 Sparkle upgrades on two Macs.
2. Complete compatible remote Herdr, real-provider attachment, and installed Apple/model checks under their own authorized test scope.
3. Refresh the original hero/Notes imagery in a future cohesive capture pass; do not reconstruct native UI in HTML.
