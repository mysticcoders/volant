# ADR 0006: Extensions are untrusted WASM in a capability cage

- **Status:** Accepted
- **Date:** in force by 2026-09-13 (WASM host); network model 2026-10-12
- **Enforced by:** `tools/check-extensions.sh`; extension runtime, network, storage and approval test suites

## Context

Extensions are third-party code that runs on every matching query. Raycast's model runs extensions as Node with broad access. Volant's promise is that the launcher cannot leak what the owner types or copies, so extension code has to be treated as hostile.

## Decision

- Extensions are WASM modules run by `VolantExtensionHost`, which has no network. ABI 2 commands see only virtual in-memory WASI streams, explicit import allowlists, bounded memory, output and call counts, a fixed clock and an empty environment.
- Enablement is opt-in and bound to the extension's **fingerprint** (manifest and code hash). Changed bytes that request anything new need fresh approval. Community extensions also sit behind a master gate, rechecked before submission, callbacks and result delivery.
- Extensions never get network access. The module plans URLs; Volant checks each against the manifest's `hosts` and the owner's approved hosts; `VolantFetchHost` fetches (no redirects, no cookies, size-capped) and hands the bytes back, for at most three rounds.
- Secrets, clipboard, location, storage, row images and copies are each a separate declared permission with its own limits.

## Consequences

- An extension can only see what Volant hands it and can only reach hosts the owner approved.
- Extension authors give up direct networking, file access and long-running work, so many Raycast extensions cannot be ported as-is. A compiled Raycast module is not API compatibility.
- Every new capability for extensions is a new permission, a new fingerprint input where it grants access, and new tests.
- See docs/extensions.md and docs/network-extensions.md.
