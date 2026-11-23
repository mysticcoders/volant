# ADR 0010: Debug builds are Volant Dev with their own bundle ID

- **Status:** Accepted
- **Date:** 2026-10-12
- **Enforced by:** `tools/check-dev-entitlements.py`

## Context

macOS keys privacy grants (Accessibility, Location, camera and others) to a bundle ID and its code signature. When a differently signed Debug build shared the release bundle ID, it broke the installed app's Accessibility grant while System Settings still showed the switch on, a failure the owner cannot diagnose. Debug builds also need to run without touching the owner's real container, Keychain items or update feed.

## Decision

Debug builds are **Volant Dev** (`com.mysticcoders.volant.dev`): separate TCC grants, container and Keychain, no update feed and no iCloud entitlement. A non-release build never uses the release bundle ID. `Volant/VolantDev.entitlements` stays equal to `Volant/Volant.entitlements` minus iCloud.

## Consequences

- Development cannot corrupt the owner's installed app or data.
- Grants have to be given twice, and some behavior (iCloud, CloudKit phone alerts) can only be verified with the signed release app.
- After any bundle-ID change, install a fresh app bundle rather than overwriting the directory; macOS can keep the old identity.
- See docs/dictation-at-cursor-design.md and docs/system-control.md.
