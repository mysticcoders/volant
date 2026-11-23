# ADR 0007: Extensions install from a signed catalog

- **Status:** Accepted
- **Date:** 2026-10-13
- **Enforced by:** `ExtensionCatalogTests`, `ExtensionCatalogInstallTests`

## Context

Once community extensions exist, the install path becomes the easiest way to get hostile code onto an owner's Mac: a compromised host, a rollback to a vulnerable version, or an index that points outside the extensions folder. Fetching packages straight from repositories would make the hosting service part of Volant's trust boundary.

## Decision

The extension catalog is an Ed25519-signed index, with the signing key held only in the volant-extensions repository's Actions secret. Volant fetches it only through `VolantFetchHost` at fixed paths, only when the owner checks it or once a day if the owner turned on daily checks. The saved index is re-verified on every read. Package paths are derived, never taken from the index, and archives are never extracted. Rollback below the recorded sequence is rejected. Installation stages and moves atomically and never enables, approves hosts or runs code. Signed revocations turn off matching installed code and block reinstalling it.

## Consequences

- A compromised host can withhold updates but cannot substitute code or roll back.
- Losing the signing key, or needing to rotate it, requires shipping an app update that trusts the new key.
- Publishing depends on the volant-extensions repository's signing workflow.
- See docs/extension-catalog.md.
