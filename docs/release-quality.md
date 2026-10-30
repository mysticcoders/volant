# Volant release and screenshot quality

## Decisions — 2026-09-14

- The launcher wing, selected result and Herdr strip follow the color theme's accent. The default System theme uses the macOS accent color; the Volant theme keeps the coral wing brand with separate light/dark values, and marketing renders still use the AccentColor asset. See [color themes](color-themes.md).
- Herdr’s chevron persists the expanded overview in app preferences. It shows project, provider, pane ID, and textual status, with attention first. The overview is bounded and scrollable. Default stays compact; disclosure does not focus or send input to an agent.
- Marketing must use captures of the real SwiftUI launcher with fictional data. `tools/render-marketing.sh` uses the exported app’s Assets.car and the same source views. A hand-built HTML approximation had drifted from the product; native captures prevent that mismatch.
- Sparkle 2.10.0 is pinned. Use its Installer and Downloader XPC services; the main app still has no outgoing-network entitlement. Export the archive using Developer ID so all Sparkle helpers are re-signed. See [Sparkle sandbox integration](https://sparkle-project.org/documentation/sandboxing/).
- Update private key is in login Keychain under account `volant`; only its public key is in project.yml. Do not regenerate or rotate it casually. Back it up securely before the first public release; never commit it.

## Release procedure

A release needs one owner action: merging its release pull request.

1. **Notes and copy.** On a `release/<version>` branch from current `main`, write `docs/releases/<version>.md`. It is the GitHub release body and is also bundled into the app, where Settings → What's New (and the launcher menu's What's New item) shows every release's notes, so the notes must be final before `Scripts/ship.sh` builds. Pull request references such as (#236) are hidden in the app. Commit any website copy, feature badges, documentation notices and `docs/marketing-claims.md` changes the release makes true. Push the branch.
2. **Ship.** Run `Scripts/ship.sh <version>`. It sets `MARKETING_VERSION` and the next `CURRENT_PROJECT_VERSION` (never reused), runs `Scripts/release.sh` to archive, export, notarize and staple the app and DMG and sign the appcast, inspects the mounted DMG, and opens one pull request with the DMG, `SHA256SUMS`, the signed appcast and this document's build record. It never merges.
3. **Merge.** Merging the release pull request after its checks pass approves publication. The owner asking for the release authorizes the agent shipping it to merge once every check has passed (October 29, 2026); a failing or pending check always waits. The waiting script then works only from the merged commit: it deploys the download while serving the previous feed, verifies the public DMG's SHA-256, staple and Gatekeeper result, deploys the merged feed and compares it byte for byte, checks the pages and both DMGs, publishes the GitHub release with the DMG, and posts the results on the pull request. If the script was interrupted, `Scripts/ship.sh <version> --publish` resumes from the merged pull request.

Every step stops on failure and states what is and is not published; the new feed is never served before its download is verified. Each script run uses its own `dist-release.ship-*` folder and a temporary worktree, leaving the main checkout untouched.

**One-time setup.** Notarization uses the App Store Connect API key in `~/.appstoreconnect`: `private_keys/AuthKey_SCV5964PL2.p8` and the `issuer_id` file. `Scripts/release.sh` picks it up on its own when there is no working `volant` Keychain profile, which happened for 0.3.24. Storing it as that profile (`xcrun notarytool store-credentials volant --key ~/.appstoreconnect/private_keys/AuthKey_SCV5964PL2.p8 --key-id SCV5964PL2 --issuer <issuer-ID>`) is optional. Explicit `VOLANT_NOTARY_KEY`, `VOLANT_NOTARY_KEY_ID` and `VOLANT_NOTARY_ISSUER` still take precedence, and `VOLANT_NOTARY_KEY_ID` also picks a different key from the folder. Allow Keychain access for the Developer ID key and the Sparkle key (account `volant`) when first prompted so later runs are unattended. `gh` and `wrangler` must be signed in.

Not automated: an installed previous build updating through Sparkle (decline/cancel, relaunch, preserved notes and config). A signed appcast alone does not establish a working update installation.

## Evidence

- Developer ID archive and export succeeded on this Mac. Export includes Sparkle’s framework, installer/downloader XPC services, updater, and autoupdate helper.
- SwiftLint passed. `tools/check-launcher.sh` passed in light and dark appearances, including actual non-activating panel typing/clicks, repeated summon, selection, and connectivity fixtures.
- Inspected native light/dark marketing renders with expanded fictional Herdr panes and coral accents.
- Website production build and TypeScript check passed. Desktop and 390px mobile renders inspected.
- Signed `dist/Volant-0.1.0-unnotarized.dmg` is a development delivery, not a public release. Notarization profile `vey` is absent. This initial attempt was blocked on credentials; the public releases below resolved it.

## Remaining work

- Notarization completed for build 2; see the release evidence below.
- Installed signed-app live smoke test: OS appearance switching, Herdr disclosure click/persistence, Settings/menus, updater prompt, larger text and minimum launcher scale. Render fixtures do not establish these.
- Two-version Sparkle installation verified on October 7, 2026: the owner updated two Macs from 0.1.5 to 0.2.0 through Sparkle. See the 0.2.0 entry.
- Intel hardware testing is out of scope (decided October 15, 2026): the owner has no Intel Mac. Releases stay universal, and `Scripts/ship.sh` refuses a DMG whose app lacks the `x86_64` slice, which is what the "Apple silicon & Intel" download line rests on. Records before this date list Intel as unverified; that is no longer tracked.

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

## 0.1.5 build 7 — October 3, 2026

Release includes iCloud settings sync code (#104), Finder and CoreServices apps in the app list (#105), human-readable timezone answers (#106–#108), the two-sided calculator card (#109), relative-day times (#110) and GeoNames city lookup (#111). Each feature PR passed hosted native, UI and PR gate checks. The owner chose to ship the iCloud switch as-is: release signing has no provisioning profile yet, so this build carries no iCloud entitlement and the switch reports iCloud as unavailable.

Built from `release/0.1.5` (version-only commit on main `bedbf0e`). Output: `dist-release.qgFDxi/`. Notarization used App Store Connect API key `SCV5964PL2` at the owner's direction. Apple accepted app submission `fd5b8c8e-5e90-408e-a1ef-d77d4a18f69b` and DMG submission `5dd3ed1b-3b5e-43e2-8880-ad28a5a0c4cc`. Both were stapled and passed Gatekeeper as Notarized Developer ID. The mounted DMG contains `Volant.app` (0.1.5, build 7, `x86_64 arm64`, valid deep strict signature, stapled, bundled city table, no iCloud or network-client entitlement) and the Applications symlink. DMG SHA-256: `022d447abd30cb87f6ae2b13f2e9e4e875117f4fa62280e174dc55b3a62c3400`. The signed appcast references build 7 and the DMG length.

Publish in two stages as before: DMG, checksums and website first, verify public delivery, then activate the signed build-7 feed.

Public DMG delivery verified after Cloudflare deployment `41b96146-f281-4a01-b448-eba3e428dc68` (run by the owner): the homepage offers 0.1.5 and `/docs/launcher` serves the time-conversion section. The downloaded DMG (HTTP 200, 8,359,368 bytes) matched the SHA-256 above, passed stapler validation and Gatekeeper (Notarized Developer ID), and `getvolant.com` still redirects. The public feed remained on 0.1.4 until the follow-up activates the exact signed build-7 appcast.

Final publication: signed build-7 feed activated in Cloudflare deployment `aba0225d-8607-4ab2-aac9-4998ff522012` (run by the owner). The public feed (HTTP 200, `max-age=0, must-revalidate`) matched the generated file byte-for-byte, reports version 0.1.5 build 7, and passed Sparkle `sign_update --verify`. The homepage, `/docs`, and the 0.1.5 and 0.1.4 DMGs returned 200. Release PRs #112 and #113 passed required workflow checks before merging. As before, an installed 0.1.4 → 0.1.5 upgrade, the Intel hardware smoke test and working iCloud sync (no entitlement in this build) remain unverified.

## 0.2.0 build 8 — October 7, 2026

Release includes everything merged since 0.1.5:

- **Calculator:** the expanded calculator, #137–#149.
- **Currencies:** about 160 fiat currencies through ExchangeRate-API behind ECB, #146.
- **Crypto:** keyless CoinGecko prices, #138.
- **Themes:** color themes, Raycast theme import and a themed Notes editor, #147, #148, #150.
- **System commands:** lock, sleep, screen saver, restart, shut down and log out, #102.
- **Launcher:** steadier launcher typing, #144.
- **Memory:** reductions, #155, #156.
- **iCloud:** settings sync enabled by the key-value entitlement and Developer ID profile signing, #153.

The owner chose 0.2.0 for the iCloud sync.

**Profile fix.** The first Developer ID run failed before building: the "Volant Developer ID" profile created on October 1 listed only the March 2024 Developer ID Application certificate (`1CA0…D900`), while this Mac signs with the April 22, 2026 certificate (`2AFC…A6D2`), which also signed every published DMG. The owner regenerated the profile with the April 22 certificate (UUID `282891c4-d009-44b6-a929-e10b1f637ea5`). The team holds three Developer ID Application certificates, all expiring February 1, 2027; the March 2024 and April 11, 2026 ones are unused. Create a new certificate and add it to the profile before then.

**Build.** Built from `main` at `d9b6dbc` (#157, version-only). Output: `dist-release.DNIqft/`.

- **Notarization:** used App Store Connect API key `SCV5964PL2`. Apple accepted app submission `e3ab46a4-2c31-42ab-a45c-3bbb317c6f00` and DMG submission `cd5daa84-4ca6-4514-9bd1-21ebdb7b11b5`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** contains `Volant.app` (0.2.0, build 8, `x86_64 arm64`, valid deep strict signature, stapled, sandboxed, iCloud key-value and loginwindow Apple Events entitlements, embedded provisioning profile, no network-client entitlement) and the Applications symlink.
- **DMG SHA-256:** `a2fb27d792b8c309e72ec597faa449f01c9710c97b3c3dc75eae607abc74c03e`.
- **Appcast:** the signed appcast references build 8 and the DMG length (12,261,884 bytes).

An earlier local test build of the same code, still labeled 0.1.5 build 7 (`dist-release.2gNQDA/`, DMG submission `b296668c-8808-4af4-be60-c5588d004a11`), was used only to try iCloud sync on a second Mac and must never be published.

**Publishing.** Publish in two stages as before: DMG, checksums and website first, verify public delivery, then activate the signed build-8 feed.

**Verified by the owner.** iCloud settings sync between two Macs on the same Apple Account, theme switching, and the system actions in the installed app.

**Unverified.** Intel hardware, and iCloud quota and account-change notifications.

Public DMG delivery verified after Cloudflare Worker deployment `c71b8169-4bb7-4cac-9bdd-48a4616605bb` (run by the owner from #158):

- **Homepage:** offers `Volant-0.2.0.dmg` and the New in 0.2.0 sections.
- **Download:** HTTP 200, 12,261,884 bytes. It matched the SHA-256 above, passed stapler validation and passed Gatekeeper as Notarized Developer ID.
- **Pages:** `/docs`, `/docs/calculator`, `/docs/system-control` and `/docs/privacy-and-security` returned 200.
- **Redirect:** `getvolant.com` still redirects to usevolant.com.
- **Feed:** the public feed (`max-age=0, must-revalidate`) remained on 0.1.5 build 7 until the follow-up activates the exact signed build-8 appcast. That appcast passes `sign_update --verify` and references `Volant-0.2.0.dmg`, 12,261,884 bytes.

Final publication: the signed build-8 feed was activated in Cloudflare Worker deployment `8250b031-a1ab-4eff-8700-b096bcbe2047` (run by the owner from #159).

- **Feed:** the public feed (HTTP 200, `max-age=0, must-revalidate`) matched both the committed file and the release output byte-for-byte. It reports version 0.2.0 build 8 and passed Sparkle `sign_update --verify`.
- **Pages and downloads:** the homepage, `/docs`, and the 0.2.0 and 0.1.5 DMGs returned 200.
- **Release PRs:** #157, #158 and #159 passed required workflow checks before merging.
- **Still unverified:** Intel hardware.

Installed upgrade verified by the owner after activation: two Macs running 0.1.5 updated to 0.2.0 through Sparkle, relaunched, and worked normally. This is the first completed two-version Sparkle upgrade for Volant.

## 0.2.1 build 9 — October 8, 2026

**The fix.** 0.2.1 fixes a 0.2.0 regression that left the app list empty on some Macs (#162). The app index searched the whole computer, so Spotlight waited on every mounted volume. On the owner's Mac (an SMB share from another Mac, Xcode's CoreDevice DeviceFS and simulator images), gathering never finished. The launcher and Settings showed no applications and no error, while the same build worked on another Mac. The query now searches only the application folders and reads results during gathering.

**Probes on the affected Mac.** Exact predicate and filter, run as a sandboxed ad-hoc app bundle:

| Scope | Result |
| --- | --- |
| Whole computer | Never finished within 40 s |
| Application folders | About 1 s, 198 apps |

A development build with the fix, installed on the owner's Mac, was used before release.

**Build.** Built from `main` at `20adedf` (#163, version-only). Output: `dist-release.dyZ8UO/`.

- **Notarization:** used App Store Connect API key `SCV5964PL2`. Apple accepted app submission `a4bf4d92-72f0-4284-85dc-01e7273a8165` and DMG submission `89b518ed-b1ea-413d-bb9d-ac57303987af`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.1, build 9, `x86_64 arm64`, valid deep strict signature, stapled, sandboxed, iCloud key-value and loginwindow entitlements, embedded provisioning profile.
- **DMG SHA-256:** `eb064c2689bc643d4059ef61903539893f3b3d082201b593e1e3535e580e8f89` (12,262,988 bytes).

**Publishing.** In two stages: DMG, checksums and website first, then the signed build-9 feed.

Public DMG delivery verified after Cloudflare Worker deployment `00f07ab2-5ced-46b3-a85d-b34d9dc3f69c` (run by the owner from #164):

- **Homepage:** offers `Volant-0.2.1.dmg`.
- **Download:** HTTP 200, 12,262,988 bytes. It matched the SHA-256 above, passed stapler validation and passed Gatekeeper as Notarized Developer ID.
- **Pages:** `/docs`, `/docs/agents` and the 0.2.0 DMG returned 200.
- **Feed:** the public feed stayed on 0.2.0 build 8 until the signed build-9 appcast (passes `sign_update --verify`, 12,262,988 bytes) is activated.

Final publication: the signed build-9 feed was activated in Cloudflare Worker deployment `6484610c-0027-4926-8a2f-2a51e7c6cc54` (run by the owner from #165).

- **Feed:** the public feed (HTTP 200, `max-age=0, must-revalidate`) matched both the committed file and the release output byte-for-byte. It reports version 0.2.1 build 9 and passed Sparkle `sign_update --verify`.
- **Pages and downloads:** the homepage, `/docs`, and the 0.2.1 and 0.2.0 DMGs returned 200.
- **Release PRs:** #162 through #165 passed required workflow checks before merging.
- **Still unverified:** installed 0.2.0 → 0.2.1 Sparkle upgrades, and Intel hardware.

## 0.2.2 build 10 — October 9, 2026

**What's in it.**

- **Volant menu:** the version header, feedback, manual, changelog, Check for Updates, About, Settings and Quit (#167). Approved by the owner on an installed build.
- **Footer and fades:** list edge fades, and results scrolling under a translucent footer (#167), with a measured show-through guard.
- **Herdr footer status:** "Herdr: N waiting" replaces the strip under the search field (#168). Owner-approved after testing with a remote machine. The fix for scroll stutter while a remote loads is in the same PR: Herdr change announcements went from 197 to 14 over 10 refresh ticks, and the launcher view no longer observes the agents model.
- **Notes editor theme colors:** re-landed (#169). #152's squash merge had reverted #150, so 0.2.0 and 0.2.1 shipped without them.

**Build.** Built from `main` at `e45903c` (#170, version-only). Output: `dist-release.nqK5Xo/`.

- **Notarization:** used App Store Connect API key `SCV5964PL2`. Apple accepted app submission `2780c849-cd20-4e02-bead-a662d68523dc` and DMG submission `8613d058-b6b2-49db-b748-cd53dd820ab2`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.2, build 10, `x86_64 arm64`, valid deep strict signature, stapled, sandboxed, iCloud key-value and loginwindow entitlements, embedded provisioning profile.
- **DMG SHA-256:** `1794d625444d1fb77bbed54d4e079fa633fa1365525f7ce7b762c691b0cbb228` (12,450,153 bytes).

**Publishing.** In two stages: DMG, checksums and website first, then the signed build-10 feed.

Public DMG delivery verified after Cloudflare Worker deployment `2ea13735-f621-48e5-b76d-3bad30886f79` (run by the owner from #171):

- **Homepage:** offers `Volant-0.2.2.dmg`.
- **Download:** HTTP 200, 12,450,153 bytes. It matched the SHA-256 above, passed stapler validation and passed Gatekeeper as Notarized Developer ID.
- **Docs:** `/docs/agents` shows "Herdr in the footer".
- **Feed:** stayed on 0.2.1 build 9 until the signed build-10 appcast (passes `sign_update --verify`, 12,450,153 bytes) is activated.

Final publication: the signed build-10 feed was activated in Cloudflare Worker deployment `3de4348f-8f1e-42d6-9efd-50831b1bf24a` (run by the owner from #172).

- **Feed:** the public feed (HTTP 200, `max-age=0, must-revalidate`) matched both the committed file and the release output byte-for-byte. It reports version 0.2.2 build 10 and passed Sparkle `sign_update --verify`.
- **Pages and downloads:** the homepage, `/docs`, and the 0.2.2 and 0.2.1 DMGs returned 200.
- **Release PRs:** #167 through #172 passed required workflow checks before merging.
- **Still unverified:** installed 0.2.1 → 0.2.2 Sparkle upgrades, and Intel hardware.

## 0.2.3 build 11 — October 9, 2026

**What's in it.** See the [release notes](releases/0.2.3.md).

**Build.** Built from `450f1e9` on `release/0.2.3` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `0338caa3-8c56-4e92-89b5-7b54526f814a` and DMG submission `a214fbd4-0acb-4ab2-b237-1d59649bb93d`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.3, build 11, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `7d6e45cc58beeedad3dd2b442a8ec7312352fc20836182b499b797825977015d` (12463165 bytes).
- **Feed:** the signed build-11 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.2.4 build 12 — October 9, 2026

**What's in it.** See the [release notes](releases/0.2.4.md).

**Build.** Built from `cd8c04e` on `release/0.2.4` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `36619658-f48c-4ba9-8f3f-9d249a73918f` and DMG submission `117bbf31-5dac-4c21-bcb4-602f18d8a365`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.4, build 12, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `5f7ec0eab6eb672242e67d8286c75b3c8e580ff42a23719a2fdb3f242cd52898` (12691634 bytes).
- **Feed:** the signed build-12 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.2.5 build 13 — October 11, 2026

**What's in it.** See the [release notes](releases/0.2.5.md).

**Build.** Built from `cc429f9` on `release/0.2.5` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `6af3b80a-d444-4863-87a9-381d653d897f` and DMG submission `97ccc51d-40c2-477e-9ee6-4ee235f11ef7`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.5, build 13, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `fa3e5b4c11c8c9f11c1f69f953e526354c8ca82e0566914b2726a789f5aaaaf9` (12937625 bytes).
- **Feed:** the signed build-13 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.2.6 build 14 — October 11, 2026

**What's in it.** See the [release notes](releases/0.2.6.md).

**Build.** Built from `0acc510` on `release/0.2.6` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `4bd87feb-b394-43b7-aa1a-299538880ab8` and DMG submission `ad3ce35b-6005-4896-aede-921cd530d59d`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.6, build 14, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `7314f36dbc36d32f5bf17ad410fa45353e8bd8787adcf0798f99d65f757beb36` (14856646 bytes).
- **Feed:** the signed build-14 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.2.7 build 15 — October 12, 2026

**What's in it.** See the [release notes](releases/0.2.7.md).

**Build.** Built from `3312d09` on `release/0.2.7` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `1503f7d9-05e3-47a7-93d1-0dcf0c6b0237` and DMG submission `f7640f0d-83b0-4950-b528-f469b327a0e9`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.2.7, build 15, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `469c248808212749be4b3315a91d2e76371a9db405a43c132a7164759978b181` (16623088 bytes).
- **Feed:** the signed build-15 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Installed acceptance.** `tools/installed-acceptance/run-vm.py --dmg` against this DMG in a disposable macOS 15.7.7 VM: 124 passed or noted, 0 failed. This was the first run of the signed `VolantFetchHost`: the Hacker News and Lobsters readers from mysticcoders/volant-extensions showed real stories, opened stories and discussions, and handled host removal and uninstall.

**Owner verification (October 12, 2026).** Check for Updates upgraded the owner's installed 0.2.5 directly to 0.2.7 through Sparkle, and the Hacker News and Lobsters extensions worked in the installed app after approving their hosts. Intel hardware remains unverified.

## 0.3.0 build 16 — October 12, 2026

**What's in it.** See the [release notes](releases/0.3.0.md).

**Build.** Built from `a06099a` on `release/0.3.0` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `08df80e8-ae43-443e-b779-16ac1224271a` and DMG submission `c1925003-37b1-4ac8-9a64-cee2c21a48b9`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.0, build 16, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `6918b9f98d2b54d96cd950728c7f9ca9529971b4bbf9094659cbed83c61739ec` (16950139 bytes).
- **Feed:** the signed build-16 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Installed acceptance (before publishing).** `tools/installed-acceptance/run-vm.py --dmg` against this DMG in a disposable macOS VM: 129 passed or noted, 2 failed. The extensions section now installs from the catalog: the notarized app loaded the live signed catalog (sequence 5) through `VolantFetchHost.fetchCatalogFile` and installed both readers from Settings → Catalog, recording their catalog origin, enabling nothing, allowing no hosts and leaving no staging folders. All 32 extension checks passed, including reading, host removal and uninstall. The two failures are the shortcut row's Saved and Removed confirmations, which a shortcuts-only rerun repeated; the 0.2.7 DMG, which passed them in its own run, now fails them the same way, so they are not a 0.3.0 regression and are being investigated separately. The bindings themselves were written and removed correctly. Installed 0.2.7 → 0.3.0 Sparkle upgrades and Intel hardware remain unverified.

**Owner verification (October 12, 2026).** Check for Updates upgraded the owner's installed 0.2.7 to 0.3.0 through Sparkle, and Settings → Extensions → Check Catalog listed the catalog in the installed app. Installing from the catalog on the owner's Mac was not tried; the acceptance VM run above covers that path. Intel hardware remains unverified.

Later the same day the owner installed a reader from Settings → Catalog in the installed 0.3.0 app and used it successfully.

## 0.3.1 build 17 — October 13, 2026

**What's in it.** See the [release notes](releases/0.3.1.md).

**Build.** Built from `017a85b` on `release/0.3.1` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `0d314bd4-4213-4909-b3e8-32e1873c40fa` and DMG submission `a0217003-2f9c-40d5-bf40-fe37f19a916d`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.1, build 17, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `50687d72baceb89e1f90bef53434a7138cc773bf2b0d783dd6a64b07c1f88ed8` (17466781 bytes).
- **Feed:** the signed build-17 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Installed acceptance (before publishing).** `tools/installed-acceptance/run-vm.py --dmg` against this DMG in a disposable macOS VM. A first full run had 21 failures caused by the acceptance script, not the app: a new step left the launcher open, so the next summon closed it and `ext hn` was typed into the desktop (Hacker News was never turned on, so its later checks failed with it), two catalog counts assumed only two listings (npm and Wikipedia are now listed too), and three Finder checks in settings were disturbed by the window that step left open; the shortcut confirmation checks that had failed since 0.2.7 passed. After fixing the script, a rerun of the extensions and settings sections passed 86 of 86: Hacker News and Lobsters installed from the live catalog without enabling or allowing hosts; `hn` did not list Hacker News while it was off and `ext hn` led to consent; stories loaded and opened; the opened story showed as Read, Command-K offered Pin Story, Pin moved it to the top as Pinned and the extension's data was saved on disk (the first signed-app evidence for extension storage); the readers showed their icons; host approval, removal and uninstall passed, and uninstall deleted the saved data. Installed 0.3.0 → 0.3.1 Sparkle upgrades and Intel hardware remain unverified.

## 0.3.2 build 18 — October 14, 2026

**What's in it.** See the [release notes](releases/0.3.2.md).

**Build.** Built from `069d934` on `release/0.3.2` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `84c64eee-3336-402f-ae09-df4bbe162e83` and DMG submission `1dc98e35-c545-4dce-b19b-49b246e20942`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.2, build 18, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `570e0b37ec0c4a5843b8ff96e1b2c9e7b6e97e2e703edf0765613c19ae303462` (17652286 bytes).
- **Feed:** the signed build-18 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Withdrawn, October 14, 2026.** Build 18 (0.3.2) was notarized and its release PR #237 merged, but `Scripts/ship.sh` refused to publish: the Settings redesign (#236) had merged first, so the DMG no longer matched `main`. Nothing was deployed and no GitHub release was made. The DMG, its checksum and the 0.3.2 feed were removed from `main` again, and the feed restored to the live 0.3.1 one. Build 18 stays used. fsearch and the Settings redesign ship together as 0.3.3. Lesson: merge app changes either before a release branch is cut or after its release PR is published, never in between.

**Build 19 withdrawn too.** 0.3.3 build 19 was notarized and its release PR #239 was closed unmerged, because the owner wanted the changelog built into the app first. `main` moved to build 19 with that change so the next release uses build 20; nothing from build 19 was published.

## 0.3.3 build 20 — October 14, 2026

**What's in it.** See the [release notes](releases/0.3.3.md).

**Build.** Built from `34d7cf6` on `release/0.3.3` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `975a9a2b-9619-4dd3-a758-6b2213147506` and DMG submission `4b6e6665-ce49-492e-9bdf-d2a62d38c295`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.3, build 20, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `6ab20ab4fe64724e0ae7dc1652247f03474ddd2b3536d0ee71b9feedfe630959` (17862453 bytes).
- **Feed:** the signed build-20 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.4 build 21 — October 15, 2026

**What's in it.** See the [release notes](releases/0.3.4.md).

**Build.** Built from `1fcd144` on `release/0.3.4` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `2ba0ca79-b913-4e06-94d4-91268a3f4d91` and DMG submission `dc64d23f-9270-429b-b96e-f6e7b599fb10`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.4, build 21, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `9751a58d9871cd671ca914354fa948d3576754a17e8172b45aff2ba89198e0d3` (18259250 bytes).
- **Feed:** the signed build-21 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.5 build 22 — October 15, 2026

**What's in it.** See the [release notes](releases/0.3.5.md).

**Build.** Built from `f09ee0e` on `release/0.3.5` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `59a768b8-00b7-423c-bbd4-0259153aca19` and DMG submission `5c824bd5-b061-4438-9885-0e67c2db2170`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.5, build 22, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `59525145255fc9fa02c7834d5d87a5d01abe85aa41f9be4a472a1dadf5861f48` (18296990 bytes).
- **Feed:** the signed build-22 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.6 build 23 — October 15, 2026

**What's in it.** See the [release notes](releases/0.3.6.md).

**Build.** Built from `df86647` on `release/0.3.6` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `a49aa35e-d670-45c6-b218-6257689fe324` and DMG submission `927445b5-cf45-4039-8299-87a88fc6f6c4`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.6, build 23, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `2bb0b014eff379979b9ad7ae2f858ab363295888312c1e23d03d5b275e12a2bd` (18314404 bytes).
- **Feed:** the signed build-23 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.7 build 24 — October 15, 2026

**What's in it.** See the [release notes](releases/0.3.7.md).

**Build.** Built from `4069c69` on `release/0.3.7` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `e5e5f28d-0b09-4fa9-b0ea-635d74249ede` and DMG submission `71aea248-615b-4270-9a64-fdf621f5a9d9`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.7, build 24, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `909771d3034c7ededaf5719a5dc18a5dd365cd6b2510924c2021e13e99548a1c` (18360475 bytes).
- **Feed:** the signed build-24 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.8 build 25 — October 15, 2026

**What's in it.** See the [release notes](releases/0.3.8.md).

**Build.** Built from `ef17335` on `release/0.3.8` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `fbfcc40a-501c-4556-9752-78be271212db` and DMG submission `b52289dc-a312-4984-8b51-573b5ace6f8a`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.8, build 25, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `1fe3a71e91416acc0672bdc6b875faaea15243d265a0deae9e09291242a29df1` (18430375 bytes).
- **Feed:** the signed build-25 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.9 build 26 — October 16, 2026

**What's in it.** See the [release notes](releases/0.3.9.md).

**Build.** Built from `644b36d` on `release/0.3.9` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `e5c27529-9c13-4f38-b0f1-6f9cfd01117f` and DMG submission `2394005e-98ec-491f-8ff8-61fcb71a3532`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.9, build 26, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `0f8b5ed50b9e6a16380fea91687d7defbbbc9b0577119fd1595f16ddaca7efc8` (18501906 bytes).
- **Feed:** the signed build-26 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Owner verification (October 16, 2026).** Check for Updates upgraded the owner's installed 0.3.8 to 0.3.9 through Sparkle, and the updated Hacker News extension from the catalog worked in it, including its new filters. This is the first owner-confirmed Sparkle upgrade since 0.3.0; releases 0.3.3 through 0.3.8 listed the upgrade as unverified.

## 0.3.10 build 27 — October 18, 2026

**What's in it.** See the [release notes](releases/0.3.10.md).

**Build.** Built from `b7ee285` on `release/0.3.10` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `bb5f9888-ec3a-4b6c-b7b3-5d0d1a0fc18d` and DMG submission `1fbe9936-10eb-4b68-a98f-2974b3b8046c`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.10, build 27, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `713ae94603934844a01bbdbf16f8373ee665724d314dcfd8f41e7835a86413f6` (18700875 bytes).
- **Feed:** the signed build-27 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.11 build 28 — October 19, 2026

**What's in it.** See the [release notes](releases/0.3.11.md).

**Build.** Built from `bc717af` on `release/0.3.11` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `515746ae-0cbc-476d-85f9-b707c4883c8f` and DMG submission `66d85122-fb8d-4945-a054-9403a37396f7`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.11, build 28, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `1205fb10bea1178b10cda74937f75a288d6887cf7269a88a98837aa898cd4b48` (19084083 bytes).
- **Feed:** the signed build-28 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.12 build 29 — October 21, 2026

**What's in it.** See the [release notes](releases/0.3.12.md).

**Build.** Built from `c7fdf92` on `release/0.3.12` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `add2a513-6087-4d18-87c9-1a59131e4a24` and DMG submission `b1e9b303-1574-4970-8316-5bda5382c76f`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.12, build 29, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `0d6faf11d6b3e36cfe7e45516dfe8bfacdf5a9bc5606bbbf7c32b9745b9aab25` (19660589 bytes).
- **Feed:** the signed build-29 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.13 build 30 — October 21, 2026

**What's in it.** See the [release notes](releases/0.3.13.md).

**Build.** Built from `cc3be43` on `release/0.3.13` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `27530e1a-918d-461b-b508-597955abfc95` and DMG submission `5ee01215-1101-4793-a2b5-428240a62517`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.13, build 30, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `18cd438941f74b2154de1257c31a7058823c32741f912dc7349d76e4c5568e63` (20089559 bytes).
- **Feed:** the signed build-30 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Installed check.** On October 21, 2026 the owner upgraded an installed 0.3.12 to 0.3.13 through the app's updater, and used the Rex Overview, including pane previews, in that Release-signed app against live Rex. This is the first Release-signed check of the Rex helper path and the overview; it covers the owner's Mac only.

## 0.3.14 build 31 — October 21, 2026

**What's in it.** See the [release notes](releases/0.3.14.md).

**Build.** Built from `e6d205c` on `release/0.3.14` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `845a8ae1-17ab-4fac-98fb-7bbb59bb1cc6` and DMG submission `f7c3383e-c472-4377-9297-f9ee445dee5f`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.14, build 31, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `3e1942110f1018fb91129dc515699b8ab825e3f4b855bc86a7d3f7d8941dd9b6` (20274065 bytes).
- **Feed:** the signed build-31 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.15 build 32 — October 22, 2026

**What's in it.** See the [release notes](releases/0.3.15.md).

**Build.** Built from `a34cd82` on `release/0.3.15` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `3a05b905-b6b0-4df6-9377-7bb49393578b` and DMG submission `2a6867e3-904d-4940-82f1-a14d3f9e7992`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.15, build 32, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `28fe4879181800508616e2474c7a089d7af8b71ec33ebb7ed3b55f8d98597cfe` (20333139 bytes).
- **Feed:** the signed build-32 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** The owner approved publication, and the release pull request was merged on their instruction. `Scripts/ship.sh` then deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

**Installed check.** On October 22, 2026 the owner upgraded an installed 0.3.14 to 0.3.15 through the app's updater, cancelled an update while it downloaded, and saw an automatic check show the update alert rather than install. After the upgrade, settings, notes, pins, clipboard history, extensions and their approvals were all present. This is the first installed evidence of the one-time Vey → Volant move (#288), including the clipboard key's Keychain copy under the signed app. Clipboard Test's `denied` build was refused with a visible error (#289). This covers the owner's Mac only.

## 0.3.16 build 33 — October 25, 2026

**What's in it.** See the [release notes](releases/0.3.16.md).

**Build.** Built from `8284cc9` on `release/0.3.16` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `f555d2c4-9a8b-4aa9-bb6d-91896653505c` and DMG submission `b37d1682-7cab-4ada-b160-999d368be825`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.16, build 33, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `a73d6615c2ee25aa494edbb870ae5e6c0d67c17df0e79084de007bc47ae2e17b` (20763455 bytes).
- **Feed:** the signed build-33 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.20 build 34 — October 26, 2026

**What's in it.** See the [release notes](releases/0.3.20.md).

**Build.** Built from `2fa2280` on `release/0.3.20` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `20a007dd-42fa-44da-893d-90a6f3de63bc` and DMG submission `bbe7d7b2-bb99-4f8e-863a-4d8d8ec6c711`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.20, build 34, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `43df56ec2a98eacbf9bc718fdb0884a7103d81911b54bd63a625d2e21a0a80d9` (22700881 bytes).
- **Feed:** the signed build-34 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.21 build 35 — October 27, 2026

**What's in it.** See the [release notes](releases/0.3.21.md).

**Build.** Built from `04d2a5c` on `release/0.3.21` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `125d2c46-6f51-4977-b933-3cdbba746510` and DMG submission `98ec1feb-f240-4227-a3f4-d79283c3afb1`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.21, build 35, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `af4acc4a05eff3f16b1351f25d0fd87f5eb4952982a6085c21d76c0166b427ba` (22719560 bytes).
- **Feed:** the signed build-35 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.22 build 36 — October 27, 2026

**What's in it.** See the [release notes](releases/0.3.22.md).

**Build.** Built from `b078847` on `release/0.3.22` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `633dd2dc-ab40-43ff-b0d4-be7ca4f755b5` and DMG submission `112de787-3e42-4be3-8cef-4ee3304cd27c`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.22, build 36, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `e8bbba50ac6745cb67792cb636b565d9f8fd0c5453567a1f5a7af855e7d7096d` (22969034 bytes).
- **Feed:** the signed build-36 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.23 build 37 — October 27, 2026

**What's in it.** See the [release notes](releases/0.3.23.md).

**Build.** Built from `06940d5` on `release/0.3.23` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `20d7e92d-20f6-4e64-a502-f9e54b0a06c0` and DMG submission `a840f0d4-8f5e-4196-bd49-6a41bd26ffa0`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.23, build 37, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `a543bf9a78a9f24b95e47a2f5cd680898470d5b49063a00220f78148f3b9f3a4` (23586446 bytes).
- **Feed:** the signed build-37 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.24 build 38 — October 29, 2026

**What's in it.** See the [release notes](releases/0.3.24.md).

**Build.** Built from `5e1cc02` on `release/0.3.24` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `126dbd4b-66bf-4b0a-803b-d58113ba77d5` and DMG submission `f0c93567-4247-44d4-85b0-8b05801167f0`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.24, build 38, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `fb4548cf7f119a83f06a1730374733e7545b0458b40abca595b818da4ab896e1` (23154241 bytes).
- **Feed:** the signed build-38 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.

## 0.3.25 build 39 — October 29, 2026

**What's in it.** See the [release notes](releases/0.3.25.md).

**Build.** Built from `574d58e` on `release/0.3.25` by `Scripts/ship.sh`.

- **Notarization:** Apple accepted app submission `462c543b-67f7-462d-8920-80dbe0aafb65` and DMG submission `6496e074-abaa-45d9-8385-e5a93c2b5f2e`. Both were stapled and passed Gatekeeper as Notarized Developer ID.
- **Mounted DMG:** `Volant.app` 0.3.25, build 39, `x86_64 arm64`, valid deep strict signature, stapled, Applications link present.
- **DMG SHA-256:** `6ca57058a648f23ad150f7b3250e7b13a6984068b242755a6d3035904028384b` (23197180 bytes).
- **Feed:** the signed build-39 appcast generated with this DMG passes `sign_update --verify`.

**Publishing.** After the owner merged this release, `Scripts/ship.sh` deployed the download while the previous feed stayed live, verified the public DMG, then deployed the feed and compared it byte for byte. Its results are posted on the release pull request.
