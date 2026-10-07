# iCloud settings sync

An opt-in, per-Mac switch (Settings → Data & Configuration → iCloud, stored as `syncSettingsWithICloud` in config.json) mirrors a fixed subset of config.json through iCloud key-value storage (`NSUbiquitousKeyValueStore`).

## What syncs

`SettingsSync.keys` in `Core/Sources/VolantCore/Settings/SettingsSync.swift`:

- `summonHotKey`, `notesHotKey`, `emojiHotKey`, `talkHotKey`
- `snippets`, `quicklinks`, `aliases`
- `appearance` (including `colorTheme`), `clipboardRetention`

Everything else stays on the Mac: `appHotKeys` and `favoriteApps` (they name installed bundles), `showInDock`, `showOnLaunch`, `statusBar`, AI configuration, extension approvals, the sync switch itself, and any unknown top-level key. Notes, clipboard history, Keychain items and `UserDefaults` state (note pins, launcher position) are out of scope.

## Model

- config.json stays the source of truth and remains hand-editable. Each synced key travels as its raw JSON value, so unknown fields inside a synced block (for example inside `appearance`) survive.
- Cloud entries live under `settings.<key>` as `{value: canonical JSON Data, modified: epoch seconds}`.
- `icloud-sync.json` in the support directory records the last value this Mac and iCloud agreed on per key. It is not part of config.json, so Backup and Raycast import never carry one Mac's sync history to another.
- Per key three-way merge: if only one side moved away from the baseline, that side wins. If both moved, the later of config.json's modification date and the cloud entry's `modified` wins. With no baseline (first enable, after turning sync off, or after an Apple Account change), a value already in iCloud is adopted; missing cloud values are sent.
- Before the first pass with no baseline, a copy of config.json is written as `config.before-icloud-<timestamp>.json` beside it. Existing copies are never overwritten.
- Received values are validated by decoding the merged config; an invalid one is left unapplied, reported, and does not advance the baseline. A malformed local config exchanges nothing.
- Writes recheck that config.json is byte-identical to what was read; otherwise the pass is abandoned and retried on the next reload or iCloud change.
- When the synced values exceed the 1 MB store limit (a 960 KB budget is enforced), local changes are held back and Settings reports it. A store quota notification is reported the same way.

## Triggers

A pass runs at launch when enabled, after every configuration reload (all in-app edits reload), and on `didChangeExternallyNotification`. Edits made to config.json outside the app sync after Reload Configuration. Applied changes reload the configuration once; the follow-up pass finds nothing to do.

## Entitlement and signing (not yet done)

This branch does not add the iCloud entitlement. The App ID `com.mysticcoders.volant` has no iCloud capability and release signing uses a Developer ID certificate without a provisioning profile, so adding `com.apple.developer.ubiquity-kvstore-identifier` now would break signed builds. Without it `synchronize()` returns false and Settings shows iCloud as unavailable; nothing is written.

To enable:

1. Enable iCloud (key-value storage) on the App ID in the developer portal.
2. Create a Developer ID provisioning profile for `com.mysticcoders.volant` and embed it (manual signing: `PROVISIONING_PROFILE_SPECIFIER` in `Scripts/release.sh`, `provisioningProfiles` in `Scripts/ExportOptions.plist`).
3. Add `com.apple.developer.ubiquity-kvstore-identifier: $(TeamIdentifierPrefix)$(CFBundleIdentifier)` to the Volant entitlements in `project.yml`, and extend the release entitlement assertions.

## Evidence

- `swift test --package-path Core`: `SettingsSyncTests` covers merge rules, unknown-field preservation, invalid cloud values, malformed config, budget and copies.
- Hosted `ICloudSettingsSyncTests` drive the service against an in-memory store and temporary files: first enable, local edit send, unavailable iCloud, malformed config, switch-off and account change.
- Not verified: real iCloud delivery between two Macs, quota and account-change notifications from the system, and the signed installed app. These need the entitlement above and two Macs on the same Apple Account.
