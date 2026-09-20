# Competitors

How Volant compares with other launchers on the Mac. Each entry records when it was reviewed and what was verified, so claims can be rechecked as products change. Linux and Windows support are out of scope for Volant and are not counted against it.

## Vicinae

Reviewed 2026-09-14 from vicinae.com, docs.vicinae.com, and the `vicinaehq/vicinae` source at `main`. Not installed or run; no performance comparison. Platform scope, release contents, star and fork counts refreshed 2026-09-19 from the GitHub API.

### Snapshot

- Free and open source, GPL-3.0. C++ and Qt core; extensions are React and TypeScript on Node. Sponsor funded.
- Active: v0.29.0 released 2026-09-18, 9,893 GitHub stars and 296 forks, commits daily.
- **Three platforms as of 2026-09-19, and that is the whole story.** Linux is the center of gravity: releases have shipped Linux AppImages and tarballs throughout, and Raycast has no Linux build and no announced plans, so Vicinae is the default Raycast-style launcher on a platform the incumbent refuses to serve. Windows arrived in v0.29.0 on 2026-09-18 (`vicinae-x64-setup.exe` and a portable zip; v0.28.2 and earlier shipped Linux and macOS only), which puts Vicinae on two of Raycast's platforms while Raycast contests none of its own. Its own site frames the product as "Bring your macOS workflow to Linux."
- **It runs on macOS.** macOS support has been beta since v0.23.0 and the docs claim feature parity with Linux. Notarized DMG or `brew install --cask vicinae`. The install guide requires macOS 26 and Apple Silicon, although the bundle declares a 14.4 minimum.
- Positioning: "a high-performance, native command palette for your desktop", Raycast compatible.

### Where Vicinae is ahead

- **Extension ecosystem.** Runs many Raycast extensions, with in-app access to both the Vicinae store and the Raycast store, plus Raycast-style script commands and a dmenu mode. Volant has a sandboxed WebAssembly spike with an unstable API and no store.
- **Text expansion.** Snippet keywords expand as you type in any app, through a keyboard event tap and paste injection. Placeholders include named arguments, `{cursor}`, formatted dates, and shell commands. Volant snippets are copied from the launcher and never paste.
- **System control.** Window switching and closing, browser tab switching, power actions, font browsing, volume, and theming. The source also has macOS menu bar and selected-text services. Volant has none of these by design, since they need the Accessibility permission.
- **Calculator.** Ships SoulverCore as a calculator backend on macOS.
- **Clipboard search.** Full-text search over history and preservation of every copied representation, including files.
- **Price and community.** Free, open source, and has an established community.

### Where Volant is ahead

- **Security posture.**
  - Volant: App Sandbox on, no network entitlement, no telemetry, and no Accessibility or Input Monitoring grant.
  - Vicinae is not sandboxed: its entitlements are Apple Events, Calendars, and Contacts only. Paste, snippets, window management, the menu bar, and selection services use Accessibility APIs, and snippet expansion uses a keyboard event tap.
- **Telemetry and network.**
  - Vicinae enables anonymous system-info telemetry by default (`telemetry.system_info = true`). A one-hour timer sends at most once a day to the Vicinae API. The payload holds a random user ID, CPU architecture, OS and kernel version, locale, screen resolutions and scale, desktop, and app version.
  - It also checks GitHub for updates every six hours and can download and install them.
  - A telemetry notice appears in its news feed, and a "forget" call exists.
- **Clipboard privacy.**
  - Volant: history is AES-GCM encrypted at rest by default with a Keychain key, capped by count (500 by default), and skips password-manager copies.
  - Vicinae: data is unencrypted by default (AES-256-GCM is opt-in), history has "currently no limit" on growth, and it also skips password-manager copies.
- **Extension isolation.**
  - Volant: extension code runs as WebAssembly in a separate sandboxed XPC process, limited to the capabilities its manifest declares.
  - Vicinae: extensions get "all standard Node.js APIs", and its docs don't describe process isolation or a permission model.
- **Agents.** Herdr pane discovery, focus, and pinned status, plus native ACP conversations with OpenCode, Claude Code, and Codex. Vicinae has no built-in equivalent.
- **Notes.** A Live Markdown notes window of plain `.md` files, with code-block copy. Vicinae has no built-in notes.
- **Calendar and contacts built in.** Volant has a `cal` agenda with meeting join, plus contact search. Vicinae requests calendar, reminders, and contacts access for extensions rather than shipping these.
- **Reach on the Mac specifically.** Volant targets macOS 15 and builds for Apple Silicon and Intel; Vicinae's install guide requires macOS 26 on Apple Silicon. Note the direction of this claim: Vicinae reaches far more machines overall, across three operating systems. It reaches fewer *Macs*.
- **Native UI.** Volant uses AppKit and SwiftUI; Vicinae's core uses Qt.
- **Migration.** Volant imports Raycast snippets, quicklinks, aliases, hotkeys, and notes. Whether Vicinae imports Raycast settings wasn't assessed.

### Roughly at parity

App search, file search, emoji, calculator, clipboard history with images, snippets, and quicklinks (Vicinae calls them shortcuts). Both are free to run locally. Learned ranking wasn't compared.

### Implications

- Vicinae is the strongest free option for someone who wants Raycast extensions on a Mac without a subscription. Don't compete on extension breadth or system control.
- **Most of the posture gap is the price of portability, not carelessness.** A C++, Qt and QML core exists to run on three operating systems. App Sandbox is macOS-only, so a portable core cannot adopt it; Carbon hotkeys, AppKit and SwiftUI are likewise unavailable to it. Vicinae's lack of sandboxing, its Accessibility dependence and its non-native UI are downstream of that single decision. Treat them as structural consequences rather than as oversights a future release might simply fix, because fixing them would mean forking the architecture per platform.
- **macOS is Vicinae's weakest leg, and it is a port.** Support is still beta, requires macOS 26, and renders through Qt rather than AppKit. Volant and Vicinae therefore overlap on one narrow user: a Mac owner who wants free Raycast extensions. They are not otherwise competing for the same person.
- Lead with what Vicinae structurally can't claim: sandboxed, no network access, no telemetry, no Accessibility grant, and encrypted clipboard history by default. Then agents and notes. Every one of these is currently true and verified against Volant's own entitlements and source.
- System-wide text expansion and window switching are the most visible gaps. Both require the Accessibility permission. If they're ever added, they belong in a separate, optional helper so the main app keeps its posture.
- Recheck on each Vicinae release: telemetry default, clipboard encryption default, macOS minimum, and whether an extension permission model has shipped.
- Follow-up research and decisions on system control, the calculator, clipboard search, text expansion, and Raycast extension compatibility: [system control and extensions research](system-control-and-extensions-research.md).

### Sources

- https://www.vicinae.com/
- https://docs.vicinae.com/ and the `install/macos`, `clipboard`, `snippets`, `window`, `extensions/introduction` pages
- https://github.com/vicinaehq/vicinae: `README.md`, `extra/Vicinae.entitlements`, `extra/Info.plist.in`, `src/server/src/services/telemetry/telemetry-service.cpp`, `src/server/src/config/config.hpp`, `src/server/src/services/update/update-service.cpp`, `src/server/src/services/snippet/macos-snippet-server.mm`
- GitHub API, 2026-09-19: repository metadata, language byte counts, and the release asset lists for v0.27.0, v0.28.1, v0.28.2 and v0.29.0, which is how the Windows addition was dated
- Raycast platform availability, including the absence of Linux plans: https://www.raycast.com/faq

## Raycast

Reviewed 2026-09-19. Pricing and feature gating from raycast.com and the September 2026 changelog. Performance figures are this repository's own matched benchmark against installed Raycast 2.4.1.0 build 0; process figures are a direct Activity Monitor reading on this machine. Not decompiled; internal architecture is inferred from process names and counts.

### Snapshot

- Closed source, company funded, free tier plus Raycast Pro at $8/month. An account is required for sync and AI.
- The reference product in this category. Extension store, AI, Focus sessions, window management, script commands, dictation.
- Gated behind Pro: unlimited clipboard history, cloud sync, translation, and notes beyond five.
- Runs seven processes totalling **516.0 MB** physical footprint: Backend 267.5 MB (45 threads), UI 152.1 MB, Raycast 55.5 MB (427 Mach ports), Graphics and Media 20.0 MB, `com.raycast.macos.Pasteboard` 7.6 MB, Networking 7.0 MB, `com.raycast.macos.Accessibility` 6.3 MB. Volant on the same machine is **~76 MB across two processes** (70.7 MB main, 4.9 MB helper).
- "Graphics and Media" and "Networking" are WebKit's standard helper process names, so Raycast embeds WKWebView. Backend's size and thread count are consistent with a Node runtime hosting extensions and AI.
- Pasteboard and Accessibility are deliberate, separately named XPC services rather than framework-spawned helpers.

### Where Raycast is ahead

- **Ecosystem.** A large extension store with managed authentication. Volant has a WebAssembly spike with an unstable API and no store.
- **Reopen latency.** In 150 matched trials, Raycast's median reopen was **55.3 ms against Volant's 69.6 ms** (p95 69.0 ms against 94.8 ms). Do not claim Volant opens faster than Raycast; that claim is currently false on this measurement.
- **Feature breadth.** AI chat and agents, Focus sessions, window management, script commands, dictation, and text expansion, none of which Volant has.
- **Maturity and polish.** Company backed, frequent releases, and already updated for the macOS 26 and 27 design language.

### Where Volant is ahead

- **Footprint.** Roughly 76 MB across two processes against 516 MB across seven, measured the same way on the same machine.
- **Cold start.** Volant's median fresh-process window publication was **998.2 ms against Raycast's 1068.0 ms**, about 70 ms earlier.
- **Security posture.** App Sandbox on, no network entitlement, no telemetry, no account, and no Accessibility or Input Monitoring grant. Raycast requires an account for its paid tier and embeds a browser engine and a Node runtime.
- **Price and license.** Free and MIT, with no gated features, against $8/month for clipboard history, sync, translation, and unlimited notes.
- **Agents.** Herdr pane discovery, focus, and pinned status, plus native ACP conversations. Raycast has no equivalent.

### Roughly at parity

App and file search, calculator, unit conversion, emoji, snippets, quicklinks, clipboard history with images, and a calendar agenda.

### Implications

- The memory comparison is the strongest honest number Volant has against Raycast, and it is a direct consequence of not embedding WebKit or Node. It does not depend on any claim about speed.
- The endpoint of the opening benchmark is window publication, not first rendered pixel or keyboard readiness. Raycast's own published chart uses shortcut to first visible frame, a different endpoint, so the two are not comparable. Measure real input readiness before making any competitive UX claim.
- Their `com.raycast.macos.Accessibility` service is the architecture to copy if paste-in-place or window management is ever wanted: isolate the grant in a separate process so the main sandboxed binary continues to hold none. The same applies to their Pasteboard split, though Volant's clipboard needs no privilege the app lacks, so its main-thread polling is a threading problem rather than a process-boundary one.
- Recheck on each release: Pro gating, macOS minimum, and whether the process count grows.

### Sources

- https://www.raycast.com/ for pricing and Pro feature gating, and the September 2026 changelog
- [Matched Volant / Raycast opening comparison](opening-comparison-2026-09-15.md) for every latency figure quoted here, including the raw samples and harness
- Activity Monitor process listing on this machine, 2026-09-19, for the seven-process footprint; Volant's own figures from `vmmap --summary` and `footprint` on the running app and helper

## SuperCmd

Reviewed 2026-09-19 from supercmd.sh and the `SuperCmdLabs` GitHub organization. Not installed or run; no performance comparison. The memory and native-Swift claims below are the vendor's and were not verified.

### Snapshot

- **Two different products share the name, and the distinction matters.**
  - **v1** is genuinely open source: MIT, `SuperCmdLabs/SuperCmd`, 3,193 stars and 154 forks. It is an **Electron 40 and React** application — TypeScript 4.16 MB against Swift 177 KB — and its README says so directly. Swift and Objective-C are used only for system integration. Releases stop at 1.0.26 on 2026-06-20; last push 2026-07-11.
  - **v2 is closed source.** It ships as signed binaries through a Sparkle appcast in `SuperCmdLabs/SuperCmd-v2-releases`, a 122 KB repository with no license containing only a README and two appcast files. Releases 1.0.5 to 1.0.8, current 1.0.8 on 2026-09-18.
- v2 is marketed as a native Swift, AppKit and SwiftUI rewrite, about 50 MB on disk and 20 MB to download, claiming "3×less memory than Raycast".
- **$19.99 one-time** (regularly $39.99), covering three Macs, positioned directly against "Raycast Pro $8/month".
- **Requires macOS 26 or later.** Solo developer.
- 33 listed modules. Positions as Raycast plus Wispr Flow plus Speechify plus AI in one purchase.
- Raycast extensions: "Most Raycast extensions work in SuperCmd. Extensions that rely on Raycast-managed authentication are not supported yet."
- AI across 11+ providers including local ones: OpenAI, Anthropic, Gemini, OpenRouter, LM Studio, Ollama, MLX, Mistral, ElevenLabs, and Apple Intelligence.
- Privacy: "Your SuperCmd data is 100% local. We do not collect your clipboard history, screenshots, snippets, searches, or app activity." It nonetheless uses Aptabase for anonymous sessions.

### Where SuperCmd is ahead

- **The bundling play, which is the actual value.** It collapses Raycast Pro, a dictation subscription, and a text-to-speech subscription into a single $19.99 purchase. That is roughly $30 a month of subscriptions replaced once, and it is a far sharper pitch than "cheaper launcher".
- **Feature breadth.** 33 modules against Volant's much smaller surface, including dictation, text-to-speech, screenshot and annotation, window management, and an Alt-Tab switcher.
- **Raycast extension ecosystem**, via `@raycast/api` and `@raycast/utils` shims.
- **AI provider breadth**, including fully local inference.
- **Community.** 3,193 stars on v1 against Volant's 1.

### Where Volant is ahead

- **Open source as shipped.** Volant's MIT repository is the application people run. SuperCmd's MIT repository is the superseded Electron v1; the product being sold is closed source with no published license. Anyone concluding "open source, therefore the privacy claims are auditable" is mistaken about v2.
- **Enforced rather than promised privacy.** Volant's main binary has no network entitlement, which the operating system enforces regardless of intent. SuperCmd offers a policy statement plus Aptabase telemetry, and no source to check it against.
- **Extension isolation.** WebAssembly in a capability-limited sandboxed process, against extensions running with the full Node API through Raycast shims.
- **Platform reach.** macOS 15 with Apple Silicon and Intel builds, against macOS 26 or later.
- **Price.** Free against $19.99.
- **Agents.** Herdr pane discovery and native ACP conversations. No equivalent.

### Roughly at parity

App and file search, clipboard history, snippets, quicklinks, calculator, emoji, notes, and a calendar agenda.

### Implications

- Be precise, not dismissive, about the licensing: v1 really is MIT and really did earn 3.2k stars. The accurate statement is that the paid v2 is closed source, not that the project is dishonest.
- The subscription-replacement framing is the strongest competitive idea seen in this category. Volant, being free, cannot use it, but it explains why feature bundling wins attention.
- macOS 26 is required by both SuperCmd and Vicinae. Volant's macOS 15 and Intel support is a genuine reach advantage against both, and is worth stating plainly.
- Recheck: whether v2 source is ever published, whether Aptabase remains, and whether the macOS minimum drops.

### Sources

- https://supercmd.sh/en
- https://github.com/SuperCmdLabs/SuperCmd — README, language statistics, releases, license
- https://github.com/SuperCmdLabs/SuperCmd-v2-releases — contents, releases, absence of a license

## Where this leaves Volant

Reviewed across Raycast, Vicinae, and SuperCmd on 2026-09-19.

Two of the three compete with Volant for the same person; one mostly does not. Platform scope is what separates them.

| | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Raycast | Yes, primary | Public beta | No, and no announced plans |
| Vicinae | Beta, macOS 26 | New in v0.29.0, 2026-09-18 | Yes, center of gravity |
| SuperCmd | Yes, macOS 26 | No | No |
| Volant | Yes, macOS 15, Intel and Apple Silicon | No | No |

**SuperCmd is the direct competitor.** Mac-only, native, privacy-forward, anti-subscription — it wants the same user Volant wants, and it converges with Vicinae on the same tactic of Raycast extension compatibility at a lower price. Competing with that on feature count or ecosystem breadth is a losing race and is not worth entering.

**Vicinae is a different product that happens to also run on a Mac.** Its Linux position is uncontested because Raycast will not ship there, which is where nearly ten thousand stars and 296 forks came from, and as of 2026-09-18 it also ships Windows. Its macOS build is a beta port requiring macOS 26. Read its star count as evidence of Linux demand, not of Mac competition.

**The most useful consequence is the inverse.** Being Mac-only is not a limitation Volant is working around; it is what makes the security posture possible. App Sandbox, no network entitlement, Carbon hotkeys that need no Accessibility grant, and an AppKit and SwiftUI interface are all macOS-specific. A launcher targeting three operating systems structurally cannot offer them without maintaining a separate architecture per platform. Mac-only is therefore load-bearing, and the doc's scoping note at the top — that Linux and Windows support is not counted against Volant — understates it: the absence of those platforms is what the differentiation rests on.

Two positions are defensible because they are structural rather than a matter of effort.

1. **A security posture the operating system enforces rather than one the vendor promises.** Every competitor reviewed runs unsandboxed, executes extensions with full Node privileges, and ships some form of telemetry. Volant is sandboxed, holds no network entitlement, requests no Accessibility or Input Monitoring grant, encrypts clipboard history by default, sends no telemetry, and is open source as shipped. Each of those is checkable against entitlements and source, which is precisely what the competitors cannot offer.
2. **Agent workflows.** None of Raycast, Vicinae, or SuperCmd has Herdr pane discovery or native ACP conversations. This is the only capability Volant has that the category does not, and the competitive review reinforces that it is the wedge rather than a side feature.

A shared weakness worth using: both Vicinae and SuperCmd require macOS 26. Volant runs on macOS 15 and still ships Intel builds.

Weaknesses to hold honestly: Volant has 1 GitHub star against 3.2k and 9.9k, no extension ecosystem, far fewer features, and Raycast is measurably faster on reopen. None of these should be argued away in marketing copy.
