# Status Bar and AI settings

The former pinned harness was a Herdr activity overview, filtered to all agents or one provider. It did not pin applications or conversations. Settings now separates Status Bar sources from AI connections.

Status Bar offers Herdr activity, its provider filter, and pane details. It is hidden by default. Existing `promotedHarness` choices load into `statusBar.sources` and `statusBar.herdrFilter`; editing the setting writes the new structure. Disabling Herdr retains its filter. Updates preserve unknown fields and future source identifiers, so adding a source does not require reusing Herdr's preferences. Launcher controls use status/configuration language rather than pinning.

AI currently configures ACP only, by owner choice. OpenCode, Cursor, Claude Code and Codex use the existing ACP transport and provider CLI login. Provider and optional working-folder edits save automatically. Choose Folder is a native sheet; Connect ACP starts the selected provider without requiring a project. General chat uses a Volant-managed working directory. An existing conversation is reopened rather than replaced. `AI Chat` is discoverable by searching `ai` or `acp`. Activating it automatically connects the configured provider, or opens AI Settings if none is selected. Merely typing a search never connects. Existing explicit provider configurations are retained; new configurations require selecting a provider. No connection starts from opening Settings. Unknown AI configuration fields are preserved; stale settings snapshots and malformed configuration are rejected.

## Validation and limits

Automated checks cover legacy migration, retained Herdr filters, unknown fields/sources, stale AI writes and protection of active conversations. Native fixtures exercise full-row sidebar navigation, minimum window size, dismissal and no automatic connection. The new settings/configuration dependencies participate in the shared UI change classifier. Routine UI checks run in headless Tart.

Branded native Settings fixtures use compiled Release assets and fictional data. Inspect General, Status Bar and AI at 680×500 and 760×540 in light/dark, including disabled, empty, malformed-configuration and active-conversation states. Fixture images do not establish real provider authentication. A signed installed-app ACP prompt remains a separate smoke test; no owner provider account was used during this change, and the host app was not installed or relaunched.

## Lessons and next work

Loading a saved provider originally triggered the same change handler as editing and showed a misleading Saved message. Skip unchanged writes after checking the loaded snapshot; native fixtures assert that navigation leaves the file untouched.

Native bordered buttons synchronously track mouse release. The in-process fixture queues mouse-up before sending mouse-down, then dispatches any unconsumed release for SwiftUI controls. Settings owns its project sheet explicitly instead of looking up the current key window. Check the attached sheet rather than assuming macOS's panel service exposes an NSOpenPanel subclass.

Next: verify the Settings → project selection → signed ACP conversation flow with an authenticated provider during an agreed host testing window. API providers and secure API-key storage are deferred. Additional status sources should get their own configuration and data lifecycle; only Herdr is implemented today.

## General chat and footer refinement

Actions sits at the far right of the launcher footer. Feedback such as “Added to Favorites” sits beside the small Volant icon, truncating visually with the full text available through help/accessibility. The home section is named Commands.

Chat input receives focus on entry and resummon. An active session and draft survive reopening and Settings navigation. ACP still requires an absolute `cwd`; the helper creates `~/Library/Application Support/Volant/Chat` for general chat and validates explicitly chosen directories. This is a working directory, not a filesystem sandbox or a permission grant.

Automated checks cover configuration migration, no-project setup, working-directory validation, active-session preservation, search-versus-activation routing, and native prompt focus. Native fixtures use fake connection callbacks and never start a real provider. Signed provider authentication and a real prompt remain separate smoke-test evidence.

Chat replaces the entire launcher content and has a Back button. It uses its own native text editor, with focus requested only on entry/resummon. Delayed search-focus requests revalidate the current pane. This addresses the native regression where a SwiftUI focus request could leave the old search field (or no editor) focused after a pane change; native typing and Back/resummon checks guard that behavior.
