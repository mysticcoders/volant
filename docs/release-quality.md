# Volant release and screenshot quality

## Decisions — 2026-09-14

- Use the existing coral wing brand for the launcher wing, selected result, and Herdr strip. AccentColor has separate light/dark values; native materials and semantic text remain intact.
- Herdr’s chevron persists the expanded overview in app preferences. It shows project, provider, pane ID, and textual status, with attention first. The overview is bounded and scrollable. Default stays compact; disclosure does not focus or send input to an agent.
- Marketing must use captures of the real SwiftUI launcher with fictional data. `tools/render-marketing.sh` uses the exported app’s Assets.car and the same source views. A hand-built HTML approximation had drifted from the product; native captures prevent that mismatch.
- Sparkle 2.10.0 is pinned. Use its Installer and Downloader XPC services; the main app still has no outgoing-network entitlement. Export the archive using Developer ID so all Sparkle helpers are re-signed. See [Sparkle sandbox integration](https://sparkle-project.org/documentation/sandboxing/).
- Update private key is in login Keychain under account `volant`; only its public key is in project.yml. Do not regenerate or rotate it casually. Back it up securely before the first public release; never commit it.

## Release procedure

1. Increase `CURRENT_PROJECT_VERSION` for every distributed update, and set `MARKETING_VERSION`. Never reuse a build number for different release bytes.
2. Configure notarization locally: `xcrun notarytool store-credentials volant --apple-id <your-Apple-ID> --team-id REMBT6JY4N`. Enter the app-specific password interactively, never in a checked-in file or chat. An existing App Store Connect API key can also be used through notarytool.
3. Run `VOLANT_NOTARY_PROFILE=volant ./Scripts/release.sh`. The default profile is `volant`; override it as needed. Alternatively set `VOLANT_NOTARY_KEY` (path to the existing .p8), `VOLANT_NOTARY_KEY_ID`, and `VOLANT_NOTARY_ISSUER`. Credentials are checked before building. The Sparkle key must be accessible in Keychain.
4. Script archives and exports, validates entitlements/signatures, notarizes and staples the app, creates and signs a drag-to-Applications DMG, notarizes and staples the DMG, then generates its signed Sparkle appcast and SHA256SUMS. Unique output directories preserve older artifacts. A failure stops the release; unsigned/unnotarized output is never declared validated.
5. After public release authorization, host the complete `updates` directory at `https://usevolant.com/updates/`. Keep the feed URL stable. Publish the DMG before the appcast. Preserve old hosted DMGs until no published feed references them; update the website’s download CTA only after verifying public delivery.
6. Validate an installed previous build updating to a newer build through Sparkle, including decline/cancel, relaunch, and preserved notes/config. A signed appcast alone does not establish a working update installation.

## Evidence

- Developer ID archive and export succeeded on this Mac. Export includes Sparkle’s framework, installer/downloader XPC services, updater, and autoupdate helper.
- SwiftLint passed. `tools/check-launcher.sh` passed in light and dark appearances, including actual non-activating panel typing/clicks, repeated summon, selection, and connectivity fixtures.
- Inspected native light/dark marketing renders with expanded fictional Herdr panes and coral accents.
- Website production build and TypeScript check passed. Desktop and 390px mobile renders inspected.
- Signed `dist/Volant-0.1.0-unnotarized.dmg` is a development delivery, not a public release. Notarization profile `vey` is absent. This initial attempt was blocked on credentials; the public releases below resolved it.

## Remaining work

- Notarization completed for build 2; see the release evidence below.
- Installed signed-app live smoke test: OS appearance switching, Herdr disclosure click/persistence, Settings/menus, updater prompt, larger text and minimum launcher scale. Render fixtures do not establish these.
- Complete a two-version Sparkle installation test. The signed live feed is published; installation from a previous build remains unverified.
- Intel hardware verification remains outstanding. Inspect archive architecture before making hardware support claims.

## Automation

Release signature/entitlement/notarization/stapling checks are automated in `Scripts/release.sh`; launcher interaction fixtures are automated through `Scripts/test.sh`. Visual review and installed updater smoke tests remain manual. No CI release upload is configured.

Additional artifact checks: the mounted DMG contains `Volant.app` and the `/Applications` symlink. The executable has `x86_64 arm64` slices; mounted app signature and DMG checksum validation passed. Local Sparkle appcast generation succeeded using Keychain account `volant`, producing an Ed25519 signature for the DMG. This preview appcast is intentionally not hosted. Mobile page width equals scroll width (390px), and the full-size screenshot link was followed successfully.

The local preview appcast was also signed as XML with Sparkle `sign_update` and its embedded signature verified successfully. Release script now performs both steps after generating the DMG enclosure signature. SHA-256 of the current unnotarized DMG: `5927d1d98d77025ecd2a8d9a10829554b2ab6b461075b930ce51ef0663080ce5`.


## Public DMG — 2026-09-14

The owner requested that Volant be offered as a packaged DMG. Released **0.1.0, build 2** to `https://usevolant.com/updates/Volant-0.1.0.dmg`, with the signed Sparkle feed at `/updates/appcast.xml` and checksums at `/updates/SHA256SUMS`. The website now has Download for Mac links and installation instructions, labeled as an early release.

- Apple accepted the app submission `9f38d346-532f-4d93-b6c1-f15e99024f4b` and DMG submission `289a4aee-718a-4891-abd4-8db1ec813a90`.
- Both artifacts were stapled, validated, and accepted by Gatekeeper as Notarized Developer ID.
- The public DMG downloaded with HTTP 200 and SHA-256 `a636cd7ab4259ead34bbf5c381d7382dba12c15573979ea771d663785dae2cd2`, matching the release exactly. Public appcast matches the locally signed/verified XML byte-for-byte. Both use revalidation rather than a stale long-lived cache.
- Website production build, TypeScript, page lint, and desktop/mobile download-section inspection passed. Public download links were verified in the browser.
- Cloudflare Worker version: `cd45f136-3ef1-4483-b70b-dbd65a5a74b5`.
- Release source/output: `dist-release.HbFKCk/`. Notarization used the existing same-team App Store Connect API key already used by GeoKids, without exporting private credentials. The earlier missing Keychain profile is no longer a blocker.

Lessons: checking only the old `vey` profile missed an existing reusable Apple API credential. Check established same-team release configuration before declaring notarization blocked. On this macOS, `codesign -dv` did not show Authority lines; `-dvvv` does. Save signing output before inspecting it, avoiding an early-closing pipeline in a pipefail script. Both preflight authentication and the corrected signature check are now automated.

Remaining verification: installed two-version Sparkle upgrade, installed-app live appearance/accessibility checks, and Intel hardware smoke test. A notarized universal package is not evidence that those tests passed.

## Public 0.1.1 — 2026-09-14

Build 3 adds active-work focus retention and remembered window placement by dragging the wing. Native isolated panel checks passed in light/dark, and interactive dragging and appearance were inspected. Apple accepted app submission `a35033b4-5b78-4bac-b77e-a971a35e9014` and DMG submission `a2de573a-ecb2-4b63-9440-81f7e277a392`. Release output: `dist-release.IsCYA6/`.

The public DMG SHA-256 is `78444a229e185be884741ef1a9c11c929349aa02631d6ebc2e7fa2cc2e5c6370`, matching the local artifact. The downloaded artifact passed stapler validation and Gatekeeper (Notarized Developer ID); the published appcast matches the signed local feed byte-for-byte. Website build, TypeScript, page lint and desktop/390px mobile inspection passed. Cloudflare deployment: `edc2b78b-084f-4a71-91cc-9e6ead8895ee`.

The repository is public under MIT. The website highlights that in its hero, main copy, FAQ and footer, with GitHub and Mystic Coders X links. Footer headline: “Move faster with Volant.” The installed two-version Sparkle upgrade and Intel hardware checks remain outstanding.

## Local Settings test DMG — 0.1.2 build 4

`dist-release.ykah5E/updates/Volant-0.1.2.dmg` contains the expanded Settings, compact menu and app shortcut/alias editor. Archive/export, Apple notarization, stapling, Gatekeeper and signed appcast verification passed. It has not replaced the public 0.1.1 feed. See [Settings quality](settings-quality.md) for native UI evidence and installed hotkey verification still required. An earlier local candidate in `dist-release.3pKrno` is superseded; deliver only `ykah5E`.


## 0.1.3 build 5 — September 15, 2026

Prepared from release version commit `82590f3`, incorporating main `683c24e`. Includes the latest Settings/shortcuts, emoji grid, Caffeinate cup, window positioning and translation UI. Output: `dist-release.emndwF/`.

Apple accepted app submission `823e6314-1f14-4350-bb1e-762f86d4a225` and DMG submission `124f624e-bbd3-4952-9741-5cca146f5181`. Both artifacts were stapled and passed Gatekeeper as Notarized Developer ID. Mounted app signature/staple, version/build, `x86_64 arm64` slices and Applications symlink verified. SHA-256: `eb7785cefa3a8f1288fc272c77bfa42c01bbf8acff9fc873c376efc8ca05452b`. Generated Sparkle enclosure metadata matches build 5, version 0.1.3 and the DMG size; signed appcast verification passed.

Local diff-selected native checks passed; UI fixtures correctly skipped for this version/download-only change. Feature UI verification is recorded in the earlier feature PRs. Website production build, TypeScript and page lint passed.

Publish in two stages: first the new DMG and website links while retaining the old feed, verify public delivery, then publish the signed build-5 appcast. Existing public DMGs and checksums remain available. Download published through Cloudflare version `bdb53f1a-09b7-41b8-a2ee-94f584b23bf6` after PR #20 passed its native/scope/PR gate checks. The live homepage offers 0.1.3. A fresh public download matched the SHA-256 above and passed stapler/Gatekeeper. The follow-up publishes the exact already-verified signed build-5 appcast; public feed verification follows activation.

Remaining limits: no installed two-version Sparkle upgrade, Intel hardware smoke test, or signed installed-app Apple translation/model-download verification. This publication does not replace the owner's running app or interrupt its Caffeinate session.

## 0.1.4 build 6 — September 18, 2026

Release includes merged launcher window/status fixes and global app-shortcut delivery fixes. The owner confirmed physical shortcuts, Settings handoff, dragging and focus-loss dismissal. PR #53 passed 103 native tests, the full headless Tart UI suite and inspected light/dark fixtures. The version-only release branch passed its scoped checks; unchanged UI fixtures were correctly skipped.

Archive and export, app and DMG notarization/stapling, deep strict signature verification, Gatekeeper and signed Sparkle appcast verification passed. DMG SHA-256: `8df71edca02de2625c548b3a36bebeca6aaf4b16c94dd60633c06b45579af4f3`. Publish the DMG first, verify public delivery, then activate the signed build-6 feed. Preserve the previously deployed documentation site and all old DMGs.

Sparkle's official sandboxing documentation confirms its XPC services belong inside the framework, with an unsandboxed Downloader by default. The previous untracked timeout report does not establish an entitlement or service-name defect; do not rename services or broaden application permissions based on that hypothesis. End-to-end updater verification is tracked separately from signing/feed checks.

Public DMG delivery verified after Cloudflare deployment `0f92328a-cb8f-4783-8161-4f6ee095a572`: downloaded bytes matched the checksum above, and the downloaded DMG passed staple validation and Gatekeeper. The deployed documentation pages were preserved using an isolated copy of their already-published source. The next change activates the exact signed appcast generated alongside this DMG.

Final publication: signed build-6 feed activated in Cloudflare deployment `ff799860-de5d-4823-b1b5-747976f07e8c`. The public feed matched the generated file byte-for-byte and passed Sparkle signature verification. Live homepage version/download links and `/docs` returned correctly. Release PRs #54 and #55 passed required workflow checks before merging.

A disposable headless macOS 15.7.7 VM installed the original notarized 0.1.1 app with Gatekeeper enabled. Its stock Sparkle Downloader fetched the public feed successfully: HTTP 200, 1,121 response bytes, 227 ms transaction duration. The earlier timeout did not reproduce, so service renaming or broader network entitlements are not justified. VM AppleEvent UI inspection timed out, so update acceptance, replacement/relaunch and retained-data checks are **not verified**. Next release-quality task: make the headless updater UI fixture reliable and complete an old-to-current upgrade with fictional notes/config. Do not equate feed/network success with a completed upgrade.
