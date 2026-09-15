# Delivery workflow

- Make changes on a focused branch, not directly on `main`. Commit, push the branch, and open a pull request with the problem, resulting behavior, validation, and remaining limitations.
- Wait for GitHub workflow checks on the latest PR commit to finish successfully before merging. Fix failures on the branch; do not bypass failed or pending checks. Merge the PR, then return to `main` and fast-forward it from the remote. Repository work is authorized through this cycle; publishing the website or distributing a release remains separately scoped.
- `PR gate` is the stable aggregate check. Native build/logic tests run for native or test-infrastructure changes; UI jobs run only when the shared change classifier identifies UI-affecting files. A skipped UI job is not visual verification.
- Use `Scripts/test.sh --base origin/main` locally. It includes committed branch changes plus staged, unstaged and untracked changes when selecting UI tests. Use `--ui always` for an unlisted UI impact, `--ui only` to rerun UI checks, or `--ui never` for an explicitly scoped non-UI run. Explain overrides in the PR. Keep `tools/test-scope.py` and its tests current when adding UI surfaces or dependencies.
- Do not launch previews, UI automation, or appearance checks for docs, backend-only changes or unchanged UI. When UI behavior or appearance changes, inspect only the affected surfaces and navigation destinations in light/dark appearances; hosted runners do not replace installed-app, hardware, signing or visual inspection evidence.
- Unit-test hosts must not start real clipboard monitoring, hotkeys, menus, updater checks or normal app windows. Keep test fixtures isolated from owner data. Run native UI fixtures one process at a time to avoid key-window interference. Render branded UI from the compiled release assets, not a bare executable with missing images.

# Project working notes

- Keep notes as plain Markdown files. Failed creates/updates must remain dirty through reload and support retry; never report Saved while any dirty write remains.
- Drain queued notes writes before trashing. Preserve dirty text on save or trash failure.
- Notes use native material and semantic styles. Keep the default surface focused on one note; browsing and secondary actions are on demand.
- Run persistence tests for storage changes. `NotesRenderTests` generates fictional light/dark view fixtures; inspect them, but do not count successful rendering as live keyboard, sheet, titlebar, or OS appearance verification.
- Current decisions, evidence and remaining work: [notes design review](docs/notes-design-review.md).

- Live Markdown must preserve UTF-16 source ranges, selection, undo and input-method composition. Language choices edit only the opening fence through NSTextView’s editing API; Auto must stay local and must not rewrite detected tags into source. Live and Preview share fence parsing.

- Agent pane identity and conversation identity are separate. Revalidate the current occupant before focusing or sending input; never submit prompts through a generic shell-input path. The local agent helper must keep an explicit narrow API.
- Native hosting views need a semantic window background for reliable light/dark rendering. Verify actual rendered controls, not just a successful build.

- ACP turns must own their native session IDs, invalidate stale snapshots, reject concurrent prompts, and cancel pending permission requests explicitly. Do not advertise client filesystem/terminal capabilities without implementing them. Run `./tools/check-acp.sh` after transport changes; its fake-agent checks do not replace a signed installed-provider smoke test.

- The agent XPC helper must join the caller’s security session for provider Keychain logins. A successful ACP handshake does not prove authentication: verify a minimal prompt through the signed installed app. Never copy provider OAuth tokens or weaken Keychain ACLs to bypass a session configuration bug.

- Launcher rows must activate by stable identity, never a cached array offset or `firstIndex(...) ?? 0`. Use native buttons for row actions. Before showing a non-activating panel, handle any app-modal window; test actual panel typing/clicks and repeated summon, not only a titled hosting window.
- Raycast import changes require `tools/check-raycast.sh`; keep personal exports/passwords out of fixtures, logs, and arguments. Preserve unknown fields inside existing config entries as well as at the top level. `tools/check-launcher.sh` and focused SwiftLint rules run from `Scripts/test.sh`; see `docs/launcher-quality.md` for what is and is not verified.

- New launcher queries select their first result; only same-query asynchronous updates preserve selection identity. Lazy result rows observe selection directly. Keep rendered-highlight assertions alongside keyboard/model tests.

- System controls must re-resolve the current device when activated, honor hardware capabilities, preserve stereo balance and mute state, and report partial failures. Run `tools/check-volume.sh` plus native launcher fixtures for volume changes; signed sandbox writes are separate hardware evidence.

- Bluetooth and Location permissions are requested only on first use of their connectivity commands, never startup. Do not log or persist scanned networks, device identifiers, or Wi-Fi passwords. Never change the owner’s Wi-Fi network in automated checks. Secure-field Return and focus transitions need native tests; unchanged search text must not reset an open form. Raycast extension prototyping is deferred in favor of audio/connectivity.

- After bundle-ID changes, install a fresh app bundle rather than overwriting its directory. Verify connectivity from `/Applications`, not only DerivedData: macOS can retain the old bundle identity and redact Wi-Fi names despite a successful Location grant. See `docs/system-control.md`.

- Website product screenshots must come from the actual native views with fictional data and the release asset catalog; never rebuild the launcher in HTML as a screenshot. Sparkle releases must archive AND export to sign nested helpers, notarize/staple the app and DMG, and sign the update feed. Increase the build number for every distributed update. See `docs/release-quality.md`.
- Active ACP sessions and unfinished prompts must survive launcher focus loss. Explicit dismissal remains available. Verify drag movement in a real native preview; `isMovableByWindowBackground` alone does not prove a hosted view can be dragged. Keep remembered positions reachable after display changes.

- Settings shortcut edits must preserve unknown configuration fields and reject stale snapshots. Recording a key is not proof of global Carbon delivery. Keep reserved commands in Shared/LauncherRouting.swift so import and editing agree; check native Settings section sizes after navigation.

- Translation requests own immutable text/language snapshots and reject stale completions. Keep drafts in memory, copy only on request, and never log source/result text or raw framework errors. Use runtime Apple language availability and system download consent; fake translation fixtures do not verify installed language models or the signed app's service access.

- Dictionary lookups use validated UTF-16 ranges and explicit ownership of returned CFStrings. Keep calls off the UI executor, reject stale completions after edits/dismissal, and never persist or log lookup text. See `docs/dictionary-quality.md`; enabled-dictionary coverage and signed app handoff require separate native evidence.

- Memory reports must separate physical footprint, RSS, live allocations, and transient peaks. Use isolated fictional fixtures, fresh-process repetitions and explicit autorelease-pool boundaries; retained footprint alone is not a leak verdict. Keep model-only measurements distinct from installed UI/XPC behavior, and never capture owner process arguments or memory contents. See `tools/memory/README.md` and `docs/memory-profile-2026-09-15.md`.
