# Sparkle updates in shipped builds

> **Corrected 2026-09-20.** The original diagnosis below did not survive re-measurement. The feed
> download succeeds today, and the stated root cause is contradicted by Sparkle's own
> documentation and by the shipped bundle. Read the correction at the end before acting on
> anything above it; the fix direction it proposes would have been wasted work.


Verified 2026-09-15 in a clean macOS 15.7.7 VM against the notarized 0.1.1 and 0.1.3 DMGs from `website/public/updates/`. This is the two-version upgrade test that [release quality](release-quality.md) lists as unverified.

## Summary

Auto-update cannot work in either shipped build. Sparkle's downloader transfers **0 bytes and times out after 60 seconds**, while `curl` in the same guest fetches the same URL successfully. The app is sandboxed without a network entitlement, and the Sparkle XPC services that are supposed to do the networking are neither present under the names the entitlements grant nor entitled themselves.

## What the user sees

1. Menu bar → **Check for Updates…**
2. "Software Update — Checking for updates…" with a progress bar, for a full minute.
3. **"Update Error! An error occurred in retrieving update information. Please try again later."**

A scheduled (automatic) check fails the same way, but silently: `SULastCheckTime` advances, no alert is shown, and the app stays on the old version.

## Evidence

Guest log at the moment of failure:

```
Downloader[963] [com.apple.CFNetwork:Default] Task <…>.<1> HTTP load canceled, 0/0 bytes (error code: -999)
Volant[817] [org.sparkle-project.Sparkle:Sparkle] Encountered download feed error:
  SUSparkleErrorDomain Code=2001 "Failed to download temporary data"
  NSURLErrorDomain Code=-1001 "The request timed out."
  NSErrorFailingURLStringKey=https://usevolant.com/updates/appcast.xml
```

In the same guest, at the same time: `curl https://usevolant.com/updates/appcast.xml` returns HTTP 200, 1149 bytes. The feed is healthy, signed, and advertises `sparkle:version 5` against the installed `CFBundleVersion 3`.

Bundle inspection, identical for 0.1.1 and 0.1.3:

- App entitlements: `app-sandbox`, `device.bluetooth`, `files.user-selected.read-only`, `personal-information.addressbook/calendars/location`, and mach-lookup exceptions for `com.apple.airportd`, `com.mysticcoders.volant-spks`, `com.mysticcoders.volant-spki`. There is **no `com.apple.security.network.client`**.
- `Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/` contains stock `Downloader.xpc` and `Installer.xpc`, signed by team REMBT6JY4N with identifier `org.sparkle-project.DownloaderService`, and **empty entitlements** for both.
- The bundle contains **no `-spks` or `-spki` services**, so the two mach-lookup exceptions grant access to services that do not exist.

Repository references:

- `Volant/Volant.entitlements:19-21` and `project.yml:40-41` declare the `-spks` / `-spki` exceptions.
- `Scripts/release.sh:45-46` asserts the archive carries no network entitlement, so the release gate enforces "no network" while shipping an updater that must reach the network.
- `README.md:9` states "Sparkle checks and downloads updates through its dedicated helper". That helper is not in the shipped bundle.
- `docs/release-quality.md:18, 32, 57` require and then defer exactly this test.

## Why it fails

Sparkle performs its network work in an XPC service so that a sandboxed host app does not need a network entitlement itself. That requires the service to be embedded under the name the app grants in its entitlements and to carry its own sandbox and network-client entitlements. Neither holds here: the services keep Sparkle's default identifiers and ship with no entitlements at all, and the app has no network access of its own. The connection is made, the service starts and exits about a second later, and the request never completes.

## Fix direction

Two options, in preference order.

1. **Embed Sparkle's XPC services properly.** Copy `Downloader.xpc` and `Installer.xpc` into the app, rename them to `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki` to match the existing entitlement grants, and sign each with `com.apple.security.app-sandbox` plus `com.apple.security.network.client`. The main app stays network-free, so the README claim and the `release.sh` assertion both remain true. Confirm against Sparkle 2.10's sandboxing documentation before implementing; the exact embedding step is a packaging change in `project.yml` and `Scripts/release.sh`.
2. **Give the app `com.apple.security.network.client`.** Simpler, but it breaks the "no network entitlement" promise in the README and security posture, and it would require removing the assertion in `Scripts/release.sh`. Not recommended.

Either way, add a release gate that fails when the shipped bundle lacks a network-capable updater path: assert the `-spks`/`-spki` services exist and carry the expected entitlements, so this cannot regress silently.

## Also observed

- After the failure, Sparkle's alert was logged as "ordered front from a non-active application and may order beneath the active application's windows". It did come to the front in this test, but as a menu bar app Volant can show update alerts behind other windows. Worth activating the app before presenting update UI.
- The clipboard store logs `duplicate column name: kind in "ALTER TABLE clips ADD COLUMN kind INTEGER NOT NULL DEFAULT 0"` on every launch. Harmless, but noisy; guard the migration.
- A sandbox violation appears at launch: `Sandbox: Volant(788) deny(1) hid-control`. Unrelated to updates, but unexplained.

## How this was tested

Tart (`brew`-less install at `~/.local/lib/tart`, notarized 2.37.0) running `ghcr.io/cirruslabs/macos-sequoia-vanilla:15.7.7`, the oldest macOS Volant supports.

- Baseline VM `volant-sequoia-15`: SSH key installed, **Gatekeeper enabled** (`sudo spctl --master-enable` — the vanilla image ships with assessments disabled, so install tests are meaningless without this).
- `tools/vm-test.sh <dmg>` clones a throwaway VM, shares the DMG folder read-only, installs, verifies startup, and deletes the VM afterwards.
- Verified in the VM: notarized install accepted by Gatekeeper, first-run container and `config.json` creation, launcher panel rendering, and keyboard input (typing `2+2` produced the `= 4` answer row).

### Gotchas for VM testing

- **Quarantine by hand causes App Translocation.** Setting `com.apple.quarantine` with `xattr` after a `ditto` copy makes macOS run the app from a read-only random path, where it creates no container. A Finder drag does not. The script clears the flag by default and offers `--gatekeeper-prompt` when the download warning is the thing under test.
- **`open` over SSH is refused** (`RBSRequestErrorDomain Code=5`, `OSLaunchdErrorDomain Code=125`). Use `sudo launchctl asuser $(id -u) /usr/bin/open -a …`.
- **A live process is not a successful launch.** An app parked behind a modal Gatekeeper dialog passes `pgrep`. Verify the sandbox container and `config.json` instead.
- **The Gatekeeper first-launch dialog is modal and sticky.** It blocks every later launch until dismissed; `killall CoreServicesUIAgent` does not clear it, but restarting the VM does.

## Not verified

- Whether a corrected build actually updates 0.1.1 → 0.1.3 end to end, including relaunch and preserved notes and config.
- Update behavior on Intel hardware, and on macOS versions other than 15.7.7.

## Correction — September 20, 2026

Re-measured with `tools/spike-sparkle.sh`, which installs a DMG in a throwaway VM, backdates
`SULastCheckTime` to force a scheduled check against the live feed, and captures the logs. Run
against the published 0.1.3 (build 5) while the live appcast advertised 0.1.4 (build 6).

### The reported failure did not reproduce

The downloader completed its request normally. DNS resolved, TLS 1.3 connected over HTTP/3, the
request was sent, and the connection went dormant and deallocated roughly 100 ms after it started.
There was no `-999` cancellation, no `-1001` timeout, and no 60-second stall. `SULastCheckTime`
advanced to the current time.

So the headline claim above — that auto-update cannot work in either shipped build because the
downloader transfers 0 bytes — is not what happens today. Issue #7's note that "the alleged
network timeout was not reproduced" is the accurate record.

### The stated root cause is wrong

The analysis above says the XPC services must be embedded in the app and renamed to
`$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki`, and that the bundle is broken because it contains
no services under those names. Sparkle's [sandboxing
documentation](https://sparkle-project.org/documentation/sandboxing/) says the opposite: the two
services ship inside the framework, **no renaming is required**, and the two mach-lookup
exceptions Volant already declares are exactly the documented ones.

Inspection of the shipped 0.1.4 agrees with the documentation rather than with the analysis:
`Downloader.xpc` and `Installer.xpc` are present in
`Sparkle.framework/Versions/B/XPCServices/`, both verify against their designated requirement, the
entitlement variables substituted correctly to `com.mysticcoders.volant-spks` and `-spki`, and
`SUEnableInstallerLauncherService` and `SUEnableDownloaderService` are both set. Following the fix
direction above would have repackaged a bundle that already matches what Sparkle asks for.

### What is actually wrong

Two findings survive, both on the installer side rather than the download side.

1. **`com.mysticcoders.volant-spks` fails to resolve.** The running app attempts the lookup twice
   and both fail with `xpc_error=[3: No such process]`, immediately before it connects to
   `org.sparkle-project.DownloaderService` successfully. The check proceeds regardless, so this is
   not what breaks a feed download, but it is a real unresolved service.
2. **`-spkp` is granted nowhere.** The Sparkle binary references three mach-name suffixes,
   `-spki`, `-spks` and `-spkp`, and `Volant.entitlements` grants only the first two. Sparkle's own
   string next to it reads "Timed out while probing installer progress. If your app is sandboxed,
   please see …/sandboxing/#testing", which ties the missing grant directly to sandboxed installs.

Both plausibly bite at install time, which is exactly the half that has never been verified.

### Still unverified, and now the only real question

Whether an update **installs**. Downloading the appcast is proven; downloading the DMG, validating
its signature, replacing the app, relaunching and preserving notes and configuration are not. That
is issue #7's checklist and it remains open. A scheduled check that advances `SULastCheckTime`
without visibly offering an update is also unexplained: the guest has no Accessibility consent, so
no UI could be inspected over SSH.

### Method note

`log show` returns nothing without root in the Tart guest. The first two runs of this
investigation produced empty log sections that read like "no problem found" when they actually
meant "no data". Any future guest log capture must use `sudo`, or it will quietly prove nothing.
