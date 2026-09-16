# Apple Shortcuts

Volant lists Apple Shortcuts as native result rows. Type a workflow name in ordinary search, or use `shortcuts`, `shortcut`, `apple shortcuts`, or `apple shortcut` (optionally followed by a filter). The Apple Shortcuts core command opens the same browser. Return runs the selected identifier; duplicate names are separate rows. The browser includes Refresh and Open Shortcuts, plus loading, empty and failure messages.

Discovery uses Apple's `/usr/bin/shortcuts list --show-identifiers` through the existing signed local XPC helper. The helper has a narrow list/run API, a fixed executable, UUID validation for runs, bounded catalog output and a discovery deadline. No shell command is constructed. Apple owns workflow permissions and interactive prompts. See [Apple's command-line documentation](https://support.apple.com/en-gb/guide/shortcuts-mac/apd455c82f02/mac).

The first relevant typed search loads the catalog asynchronously; summon and startup do not wait for it. Names and identifiers are cached only in memory for 60 seconds, with explicit refresh. Same-query updates preserve selection identity, and late updates are filtered against the current query. A failed refresh retains the last catalog with a failure message in the browser. Unexpected catalog formats fail visibly rather than selecting a workflow by a guessed name.

Execution passes only the UUID to `shortcuts run`. It does not automatically retry, pass clipboard/selected text, or capture workflow output. Concurrent Return presses are ignored while a run is active. Completion callbacks own tokens so an old response cannot finish a newer run. Interactive workflows may remain running while awaiting Apple's prompt; closing the launcher does not cancel them. If the helper connection fails, review Shortcuts before retrying because the workflow may already have started.

Shortcut rows are excluded from Volant's usage history. Catalog contents, workflow output and raw process errors are not logged. Unit hosts cannot connect to the real helper; tests inject fictional catalogs and executions. The helper's existing signed-client requirement remains intact.

Initial scope does not include per-workflow custom icons, folder browsing, passing input/output, or assigning workflow-specific global hotkeys. The generic stacked icon identifies an Apple Shortcut. Successful real-workflow execution and permissions prompts require separate signed-app evidence from fixture tests.

## Validation — September 16, 2026

- `Scripts/test.sh --base origin/main` passed, including parser/cache/execution-token tests and headless Tart UI checks. Native fixtures cover Return execution, duplicate suppression, filtering, empty/error states, stale query updates and selection preservation after refresh failure.
- Release build and `codesign --verify --deep --strict` passed. The host app was not installed or relaunched while the owner was working.
- Separate native fixtures using the Release asset catalog were inspected in the VM under OS light and dark appearances: populated, loading, empty, failed and cached-result/error states. Functional keyboard tests are separate from these rendered images.
- A signed sandboxed probe exercised the actual signed XPC helper in the VM: empty and nonempty catalog discovery, invalid-identifier rejection, and execution of a deliberately empty workflow. Apple's CLI returned `Empty Shortcut`; the helper reported failure correctly. No owner workflows were inspected or run.
- Remaining smoke test: run a harmless workflow containing actions through the installed signed app, including any Apple permission prompt. Successful action execution is not established by the empty-workflow failure test. Workflow-specific icons, folders, input/output and global hotkeys remain follow-up scope.

## Recurring checks

A refresh failure initially disappeared when cached results remained visible: the generic empty-state notice renders only without result rows. Cached-result failures now use visible action feedback, with a native regression check for the message and preserved selection. Future cached sources should test errors with both empty and populated results.

Native render capture can disturb the search field editor. Keyboard fixtures explicitly restore the editor after capture before sending Return; image generation alone is not keyboard evidence.
