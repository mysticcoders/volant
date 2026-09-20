# VolantCore

The portable half of Volant. Every file here imports Foundation and nothing else: no
AppKit, SwiftUI, Carbon, CryptoKit, Combine or other system framework. That rule is the
point of the package — it keeps platform code from leaking into the algorithmic core and
lets the core be built and tested without the app.

Run `swift test` from this directory. The package has no dependencies, so it needs
neither Xcode nor a generated project.

Adding a file here means committing to that constraint. If a change needs a platform
framework, the code belongs in the app target instead. See `docs/cross-platform-core.md`
for the measurement and reasoning behind the split.
