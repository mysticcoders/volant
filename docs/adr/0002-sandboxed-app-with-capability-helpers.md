# ADR 0002: Sandboxed main app; each capability in its own narrow helper

- **Status:** Accepted
- **Date:** in force by 2026-09-13; extended with each helper through 2026-11-18
- **Enforced by:** entitlement files per target in `project.yml`; `tools/check-dev-entitlements.py`; `tools/check-sandbox-reads.py`

## Context

A launcher sees everything the owner types, copies and opens. It also runs third-party extension code and talks to AI providers, weather, currency and catalog servers. If the main app held all of those capabilities, a bug or a hostile extension anywhere in it would have all of them too. The App Sandbox limits a process but grants entitlements per process, not per feature.

## Decision

The main app is sandboxed and has **no network entitlement**. Every capability that needs network access, JIT or freedom from the sandbox lives in its own signed XPC helper with only the entitlements that one job needs (see the helper table in the [glossary](../glossary.md#helpers)):

- Network: `VolantFetchHost` (extensions, catalog), `VolantAIHost` (BYOK chat), `VolantRatesHost` (currency), `VolantWeatherHost` (WeatherKit), each against fixed or approved destinations.
- Untrusted code: `VolantExtensionHost` (WASM with JIT, no network).
- Outside the sandbox: `VolantAgentHost` and `VolantInputHost`, under [ADR 0003](0003-unsandboxed-helpers-stay-narrow.md).

Helpers return data or `HostMessage` codes; the app decides what to show.

## Consequences

- A compromised extension or parser holds only its own helper's entitlements.
- Every new network feature means a new helper or an existing helper's fixed API, never a network entitlement on the app.
- More targets to build, sign and notarize, and XPC plumbing for each feature. Release archives must export so nested helpers are signed (docs/release-quality.md).
- A sandbox read that works in Debug proves nothing for the release app, because Xcode adds a read exception for `/` to Debug and test builds; `tools/check-sandbox-reads.py` checks against the release entitlements instead.
