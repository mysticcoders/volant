# ADR 0005: VolantCore is a Foundation-only, statically linked package

- **Status:** Accepted
- **Date:** 2026-09-19
- **Enforced by:** the package's own dependencies; `swift test --package-path Core`

## Context

The question was whether Volant should share a portable core across macOS, Linux and Windows, possibly through WASM. Measurement showed about a quarter of the Swift files imported only Foundation (fuzzy matching, frecency, calculator, units, preferences, approval logic); the rest is platform integration that does not port. WASM would add a serialization boundary on per-keystroke code and a runtime dependency off macOS, and WASM already means one thing in Volant: untrusted extension code ([ADR 0006](0006-extensions-run-in-a-capability-cage.md)).

## Decision

Extract the Foundation-only code as `VolantCore`, a Swift package with no AppKit, SwiftUI, Carbon, CryptoKit or Combine, linked statically so it adds no embedded framework to sign. Do it for testability and as a barrier against platform code leaking in, not as a port. Code that needs a platform framework belongs in the app target. iOS links the same package; Mac-only code stays inside `#if os(macOS)`.

## Consequences

- Core logic tests run with `swift test` without building the app.
- Some code is awkward to place: anything touching a platform type stays in the app even if most of it is pure.
- A cross-platform launcher is still not planned. If a cross-platform play is wanted, the candidate is the agent layer, not the launcher.
- See docs/cross-platform-core.md for the measurement and reasoning.
