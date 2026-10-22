# Volant identity and rename

The app, Xcode project, scheme, module, tests, extension host, source folders and wing asset are named Volant. The GitHub repository is mysticcoders/volant. The checkout directory is volant. Marketing copy uses Volant.

The app bundle identifier is now `com.mysticcoders.volant`, with `.ExtensionHost`, `.AgentHost`, and `.tests` identities. The agent helper authenticates the new app identifier and signing team.

## Remaining Vey names, removed after 0.3.14

Releases up to 0.3.14 kept the old name in storage and the extension ABI. 0.3.15 renames them, and moves what each installed copy holds once:

| What | Up to 0.3.14 | From 0.3.15 | Carried over by |
| --- | --- | --- | --- |
| Data folder | `Application Support/Vey` | `Application Support/Volant` | `SupportDirectory.resolve`: renames `Vey` to `Volant` when only `Vey` exists. A failed rename keeps using `Vey` for that launch and retries on the next; an existing `Volant` folder is never merged or replaced. |
| Notes pins and other path-keyed Notes settings | `notes.<…/Vey/…>` | `notes.<…/Volant/…>` | `SupportDirectory.moveLegacyDefaults`, after a successful move. |
| Notes window frame | `VeyNotes` | `VolantNotes` | `moveLegacyDefaults`, on every launch until the old key is gone. |
| Clipboard key Keychain item | `com.mysticcoders.vey.clipboard-key` | `com.mysticcoders.volant.clipboard-key` | `KeychainKey.load`: copies the key, then deletes the old item only once the new one reads back with the same bytes. A denied read of the old item is reported, never replaced by a new key. |
| Clipboard duplicate fingerprint context | `vey-clip-dedupe` | `volant-clip-dedupe` | `ClipboardStore` recomputes stored fingerprints once in one transaction (SQLite `user_version` 1). |
| WASM ABI 1 import namespace | `vey` | `volant` | Nothing: no catalog module imports it. Modules still importing `vey` are refused and must be rebuilt. |
| Sample IDs | `com.mysticcoders.vey.*` | `com.mysticcoders.volant.*` | Not needed; Spin isn't bundled. |

The old bundle-ID migration script (`tools/migrate-bundle-data.py`) and its check are removed: no install still uses the `com.mysticcoders.vey` bundle. Old Vey backups remain importable.

Fake-file-manager, injected-Keychain and isolated-SQLite tests cover each step. On October 22, 2026 the owner upgraded an installed 0.3.14 to 0.3.15 and found settings, notes, pins, clipboard history, extensions and approvals intact, so the move and the Keychain copy have worked under the signed app on one Mac; see [release quality](release-quality.md).

The repository is private. Marketing must not promise public source access until the owner explicitly changes visibility. No public binary download exists yet. Domain registration and Cloudflare DNS setup are pending with the owner.

Validation: the display-name rename previously passed 48 tests and Release build. The full source/project rename is validated separately. Native OS appearance and installed login-item behavior are not established by unit tests.

Full rename validation: clean Release build passed using Volant.xcodeproj / Volant scheme and a separate derived-data directory. All 48 hosted tests passed under the Volant module. Marketing production build passed; renamed desktop/mobile branding was inspected. Public deployment is deferred until the owner's Cloudflare domains are configured.


Bundle identity delivery (2026-09-14): migration fixtures, focused ACP checks, strict lint, and Release build passed. Installed main/ExtensionHost/AgentHost plist identifiers and deep/strict signing were checked. Original and copied config, notes, usage database and encrypted clipboard matched; the signed new app decrypted all 35 existing clipboard entries using the existing Keychain item. The renamed extension host returned the fictional hello input. The agent helper returned 31 Herdr panes; the existing ten-second check can falsely print failed when it samples during the five-second refresh. Login-item and Contacts/Calendar grants remain separate OS state to verify after the identity change.

Research read alongside this change: `competitors.md` and `system-control-and-extensions-research.md`. Preserve the owner's decisions: optional helpers for privileged system controls; calculator deferred; clipboard search only in memory with encryption at rest; system-wide text expansion declined; Raycast compatibility remains research. Avoid blanket no-network claims for the whole product because the unsandboxed agent helper runs network-capable providers. The main-app entitlement claim is narrower. Before implementing controls or extension tiers, verify their platform/permission assumptions with primary sources and a small working probe. Next concrete research-to-build step: permission-free volume commands; extension API compatibility should begin with a bounded UI-only fixture, not a promise to run the Raycast catalog.
