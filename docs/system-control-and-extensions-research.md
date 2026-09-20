# System control, calculator, clipboard search, text expansion, and Raycast extensions

Research from 2026-09-14, prompted by the [Vicinae comparison](competitors.md). Each section records the owner's decision so far. Nothing here is scheduled or implemented.

| Topic | Decision |
|---|---|
| System control | Agreed direction: sandbox-compatible features in the main app, Accessibility features in an optional helper |
| Calculator (SoulverCore) | Deferred to a later pass |
| Clipboard search | Keep encryption at rest. Only in-memory approaches; nothing index-like written to disk |
| Text expansion | Declined. Too close to a keylogger if done poorly, and not needed |
| Raycast extension compatibility | Research saved; revisit soon |

## System control

**Decision:** agreed split. Features that work inside the App Sandbox, without an Accessibility grant, go in the main app. Features that need Accessibility or Screen Recording go in an optional signed helper outside the sandbox, following the existing agent helper precedent. The main app's security posture stays unchanged.

| Feature | macOS requirement | Where it goes |
|---|---|---|
| Volume | CoreAudio, no permission | Main app |
| Now-playing controls | Private MediaRemote framework | Main app if pursued; fragile across OS releases |
| Theming | UI work only (today: `appearance.scale` and `opacity`) | Main app |
| Font browser | `NSFontManager`, no permission | Main app; low value |
| Sleep, lock, restart, log out | Apple Events to System Events: `com.apple.security.automation.apple-events`, a sandbox scripting-target exception, and an Automation prompt | Main app; adds an Automation prompt, not Accessibility |
| Switch to an app | None | Already covered by per-app hotkeys |
| Switch to a specific window | Screen Recording for window titles, Accessibility to raise the window | Helper |
| Move, resize, tile windows | Accessibility | Helper |
| Menu bar search, selected text | Accessibility | Helper |
| Browser tabs | Per-browser AppleScript (an Automation prompt each), or a browser extension plus a small bridge app outside the sandbox | Helper or bridge |

For reference, Vicinae implements its macOS window manager, menu bar, selection, and paste services with Accessibility APIs, and is not sandboxed.

## Calculator

**Decision:** deferred to a later pass.

**Volant today** (`Volant/Calculator/Calculator.swift`, `Volant/Units/UnitConverter.swift`):
- A 152-line arithmetic parser: `+ - * / ^ %`, parentheses, `pi`, `e`, `sqrt`, `abs`, `round`, `floor`, `ceil`.
- Offline unit conversion using Foundation's Measurement types.
- No currency, dates, time zones, or variables.
- `%` is the remainder operator, so "20% of 50" doesn't work and "50 + 10%" gives remainder semantics. This is worth fixing whichever route is chosen.

**SoulverCore:**
- Natural-language math, percentage phrases, date and calendar math, time-zone conversion, and rate calculations.
- Live rates for 190 fiat and crypto currencies, with an ECB provider for 33 fiat currencies.
- Variables and custom functions. Claims 7,000+ calculations per second on Apple Silicon.
- Ships as a binary xcframework through Swift Package Manager.

**Costs of adopting SoulverCore:**
- Licensing: free for personal and non-commercial projects. Publicly available or commercial projects must email the Soulver team; a free license with attribution is among the options.
- It's a closed binary dependency, which ends the "zero dependencies" claim.
- Live currency needs network access, which conflicts with the no-network entitlement. Either leave currency off or supply rates ourselves.
- Unverified: whether the framework makes any network calls when currency isn't used.

**Cheaper alternative:** add percentage phrases, dates, and time zones on Foundation. This keeps both the no-network and zero-dependency promises.

## Clipboard search

**Decision:** keep encryption at rest. Only use approaches that never write searchable text, or any index derived from it, to disk.

**Today:**
- `clip <term>` calls `ClipboardStore.recent(matching:)` (`Volant/Clipboard/ClipboardStore.swift:67-94`).
- It decrypts entries newest first, up to the retention cap, runs a case-insensitive substring match, and stops after the limit (12 from the launcher).
- Images match only the word "image".
- Clipboard entries don't appear in the main results.

**Options that fit the decision:**
1. Keep the linear scan. Add fuzzy matching and ranking, and optionally surface top clipboard matches in the main results. This is fine at the 500-entry default. Measure first if retention is raised a lot.
2. Build a search index in memory after launch or unlock. Discard it on quit, and never persist it.
3. Run on-device OCR on image clips with the Vision framework (local, no permission). Hold the recognized text only in memory, or encrypt it alongside the image.

**Rejected:**
- A plaintext full-text index on disk. Vicinae's FTS5 approach stores searchable text unencrypted, which defeats encryption at rest.
- A persisted hashed index (HMAC of normalized words). It loses prefix and fuzzy search, reveals word frequency, and is still an index on disk.

## Text expansion

**Decision:** declined. Detecting keywords means watching every keystroke system-wide. Done poorly, that's a keylogger, and the feature isn't needed.

What it would require, recorded so the decision can be revisited with the facts:
- **Detection:** a listen-only keyboard event tap with the Input Monitoring permission. This reportedly works in the App Sandbox, though App Store review may reject it.
- **Replacement:** post Backspace to delete the keyword, write the expansion to the pasteboard, post Cmd+V, then restore the old clipboard. Posting events needs Accessibility, and the App Sandbox silently blocks it. That means a helper outside the sandbox.
- **Edge cases:**
  - Secure input fields hide keystrokes from the tap.
  - macOS disables slow taps; they must be detected and re-enabled.
  - Input-method composition.
  - Per-app exclusions for terminals and password managers.
  - Arrow-key posting for `{cursor}`.
  - Undo and clipboard restoration.
- There's no permission-free way to expand text in place.

Volant snippets remain copy-from-launcher, and the main app never sees keystrokes outside its own panel.

## Raycast extension compatibility

**Decision:** research saved, to revisit soon. Nothing decided.

**Licensing:**
- `raycast/extensions` is MIT licensed, and so is the `@raycast/api` npm package (v2.4.1 at review time). Reimplementing the API is permitted; Vicinae does this.
- Not checked: Raycast store terms for fetching extensions from their store.

**Architecture:**
- Raycast extensions are TypeScript and React written for Node.js. A WebAssembly wrapper is the wrong shape.
- The sandboxed extension host already embeds JavaScriptCore, so extension JavaScript could run directly in that process.
- A Volant implementation of `@raycast/api` (List, Detail, Form, Action, preferences, LocalStorage, Toast, clipboard) would emit a serialized UI tree for SwiftUI to render. Vicinae renders natively from a serialized tree the same way.
- React itself runs in JavaScriptCore.

**The hard part is Node.** Approximate GitHub code-search counts of *files* (not extensions) in `raycast/extensions` on 2026-09-14:

| Pattern | Files |
|---|---|
| `"@raycast/api"` | 29,632 |
| `"child_process"` | 1,148 |
| `"node:fs"` (bare `"fs"` not counted) | 715 |
| `runAppleScript` | 604 |
| `useFetch` | 1,266 |

A meaningful minority shell out or run AppleScript, and they skew toward popular system-control extensions.

**Knowing what an extension needs:**
- Raycast manifests have no permission fields; the only related ones are `access` (public or private) and `platforms`.
- At install: statically scan the bundled output for network, `child_process`, `fs`, and AppleScript use, and show the result. This is heuristic, since dynamic imports and bundled dependencies hide calls.
- At runtime, which is the actual guarantee: provide only the granted shims. Deny by default, and prompt per network domain on first use.

**Possible tiers:**
1. **UI only**, plus LocalStorage and clipboard. Runs in today's sandboxed host with no network.
2. **Network** through a Volant `fetch` shim with a per-extension domain allowlist. Requires a separate host process that has network access. "The main app has no network" stays true; "Volant has no network" no longer would.
3. **Shell, AppleScript, file access.** Unsupported, or only through the optional helper with explicit consent. Probably never.

**Effort:** the API surface is large (List, Grid, Form, Detail, MenuBarExtra, `@raycast/utils` hooks, OAuth, AI). Vicinae is at v0.28 and still describes "decent support for many" extensions. Expect months.

**Positioning angle:** Raycast and Vicinae run extensions with full Node access; Vicinae's docs describe no isolation. "Raycast extensions with declared, enforced permissions" would be unique. Tiers 1 and 2 could be a credible first release.

## Sources

- [SoulverCore](https://github.com/soulverteam/SoulverCore)
- [Raycast manifest reference](https://developers.raycast.com/information/manifest)
- [@raycast/api on npm](https://www.npmjs.com/package/@raycast/api) and [raycast/extensions](https://github.com/raycast/extensions)
- [Vicinae docs](https://docs.vicinae.com/) and [source](https://github.com/vicinaehq/vicinae)
- [Shipping Global Keyboard Shortcuts on macOS Sandbox](https://www.quicopy.com/blog/macos-sandbox-keyboard-shortcuts)
- [Apple Developer Forums: Accessibility and Input Monitoring APIs for App Store apps](https://developer.apple.com/forums/thread/780626)
- [Detect/Listen To Global Key Events on macOS](https://levelup.gitconnected.com/swiftui-macos-detect-listen-to-global-key-events-two-ways-df19e565793d?gi=b3396cf1e4fc)
- [macOS Input Monitoring, Screen Capture & Accessibility](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-input-monitoring-screen-capture-accessibility.html)
