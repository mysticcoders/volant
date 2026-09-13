# Volant identity and rename

The app, Xcode project, scheme, module, tests, extension host, source folders and wing asset are named Volant. The GitHub repository is mysticcoders/volant. The checkout directory is volant. Marketing copy uses Volant.

The legacy bundle identifier com.mysticcoders.vey, XPC service identifier, Keychain service, HKDF context, Application Support/Vey directory, VeyNotes frame preference, and WASM vey imports remain compatibility contracts. Do not mechanically replace these strings: doing so can disconnect existing settings or encrypted clipboard data. Old Vey backups remain importable. No data is migrated or deleted.

The repository is private. Marketing must not promise public source access until the owner explicitly changes visibility. No public binary download exists yet. Domain registration and Cloudflare DNS setup are pending with the owner.

Validation: the display-name rename previously passed 48 tests and Release build. The full source/project rename is validated separately. Native OS appearance and installed login-item behavior are not established by unit tests.

Full rename validation: clean Release build passed using Volant.xcodeproj / Volant scheme and a separate derived-data directory. All 48 hosted tests passed under the Volant module. Marketing production build passed; renamed desktop/mobile branding was inspected. Public deployment is deferred until the owner's Cloudflare domains are configured.
