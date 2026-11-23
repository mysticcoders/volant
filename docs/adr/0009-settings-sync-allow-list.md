# ADR 0009: Settings sync only an allow-list of keys

- **Status:** Accepted
- **Date:** 2026-10-01
- **Enforced by:** `SettingsSync.keys`; settings sync tests

## Context

Owners with two Macs want their snippets, quicklinks and preferences to match. Syncing the whole config would also sync settings that are dangerous or meaningless on another Mac: hotkeys tied to one keyboard setup, favorites, AI configuration, extension approvals and approved hosts, privacy switches, and the sync switch itself.

## Decision

iCloud key-value sync exchanges only the keys listed in `SettingsSync.keys`, as raw JSON values merged per key against a baseline kept outside config.json. A new setting is per-Mac until someone deliberately adds it to the list. Security-sensitive and per-Mac settings never go on it. Volant copies config.json before the first pass, rechecks the file before writing, and never applies a cloud value that fails to decode.

## Consequences

- Turning on sync can never grant an extension, approve a host or switch on a privacy-sensitive feature on another Mac.
- Every new setting needs a deliberate sync decision; AGENTS.md rules repeat "never in `SettingsSync.keys`" for each sensitive one.
- Fake-store tests do not verify iCloud delivery; that needs the entitlement and two signed Macs.
- See docs/icloud-settings-sync.md.
