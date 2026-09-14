# Volant installation and Settings

The /Applications copy remained Vey after the source rename. A Release build is now installed as Volant.app; the old app was quit cleanly and backed up to /tmp/Vey-before-Volant-install.app. Bundle identity, Keychain and data paths remain compatible.

Dock absence came from accessory activation policy. Startup now reads showInDock (default true); Settings can change it live and retain menu-bar-only mode. The menu bar and application menu expose Settings, with Command-comma. Settings also controls launcher-on-start and opens the JSON config. Dock reopen brings up the launcher.

Persistence uses an atomic single-key JSON patch, preserving unknown keys and rejecting malformed config. Isolated executable checks passed for persistence, alias/unknown-field preservation, malformed-file preservation and migration defaults. Equivalent XCTest cases are included; they have not yet been run through the hosted test target.

Release build and signature verification passed. macOS Dock accessibility inventory includes Volant; the installed executable path was verified. Light fixture rendering inspected. Live Settings windows were not exposed by UI automation, and screen captures returned wallpaper. Dark fixture capture returned blank, so dark/live visual verification remains unresolved; do not call these checks passed.

Next: verify live Settings toggle/relaunch and both OS appearances once computer-use access is working. Native controls use semantic AppKit colors; no fixed palette introduced. Keep installed artifact checks separate from build checks.
