# Architecture decision records

An architecture decision record (ADR) captures one decision that shapes Volant: what forced it, what we chose, and what we accept as a result. The [glossary](../glossary.md) and the code say what Volant is; ADRs say why it is that way. Read the relevant record before changing something it covers. A rule that looks pointless is often one whose reason is written here.

## When to write one

Write an ADR when a decision meets all three tests:

1. **Not obvious.** Someone reading the code would be surprised, or would undo it.
2. **A real trade-off.** There was a credible alternative, and we gave something up.
3. **Hard to reverse.** Undoing it costs a migration, a re-signing, a lost grant, or the owner's trust.

Skip it for refactors, dependency bumps, bug fixes and anything a revert undoes. Propose new records during design, in the PR that introduces the decision, rather than writing them after the fact.

## Format

Copy [the template](template.md) to `NNNN-kebab-case-title.md` using the next free number. Numbers are never reused. Keep a record to one decision and about a page; link the design doc for detail rather than restating it.

Records are not rewritten once accepted. A changed decision gets a new record that supersedes the old one, and both link to each other. Correcting a fact or adding a link is fine; changing what was decided is not.

## Index

The first records document decisions already in force when the practice started (2026-11-23), dated by when each decision entered the repository.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions and keep a glossary | Accepted |
| [0002](0002-sandboxed-app-with-capability-helpers.md) | Sandboxed main app; each capability in its own narrow helper | Accepted |
| [0003](0003-unsandboxed-helpers-stay-narrow.md) | Unsandboxed helpers expose fixed, caller-checked APIs | Accepted |
| [0004](0004-accessibility-confined-to-input-helper.md) | Accessibility and event posting only in VolantInputHost | Accepted |
| [0005](0005-foundation-only-core-package.md) | VolantCore is a Foundation-only, statically linked package | Accepted |
| [0006](0006-extensions-run-in-a-capability-cage.md) | Extensions are untrusted WASM in a capability cage | Accepted |
| [0007](0007-signed-extension-catalog.md) | Extensions install from a signed catalog | Accepted |
| [0008](0008-notes-are-plain-markdown-files.md) | Notes are plain Markdown files | Accepted |
| [0009](0009-settings-sync-allow-list.md) | Settings sync only an allow-list of keys | Accepted |
| [0010](0010-separate-bundle-id-for-debug-builds.md) | Debug builds are Volant Dev with their own bundle ID | Accepted |
| [0011](0011-ui-tests-run-in-a-vm.md) | Local UI tests run in a headless VM | Accepted |
| [0012](0012-acp-resume-by-native-session-id.md) | ACP conversations resume only by recorded session ID | Accepted |
| [0013](0013-mcp-over-stdio-bridge-and-unix-socket.md) | MCP over a stdio bridge and an app-group Unix socket | Accepted |
| [0014](0014-releases-ship-through-one-script.md) | Releases ship through one script, approved by one merge | Accepted |
