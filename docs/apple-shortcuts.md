# Apple Shortcuts

Volant lists Apple Shortcuts as native result rows. Type a workflow name in ordinary search, or use `shortcuts`, `shortcut`, `apple shortcuts`, or `apple shortcut` (optionally followed by a filter). The Apple Shortcuts core command opens the same browser. Return runs the selected identifier; duplicate names are separate rows. The browser includes Refresh and Open Shortcuts, plus loading, empty and failure messages.

Discovery uses Apple's `/usr/bin/shortcuts list --show-identifiers` through the existing signed local XPC helper. The helper has a narrow list/run API, a fixed executable, UUID validation for runs, bounded catalog output and a discovery deadline. No shell command is constructed. Apple owns workflow permissions and interactive prompts. See [Apple's command-line documentation](https://support.apple.com/en-gb/guide/shortcuts-mac/apd455c82f02/mac).

The first relevant typed search loads the catalog asynchronously; summon and startup do not wait for it. Names and identifiers are cached only in memory for 60 seconds, with explicit refresh. Same-query updates preserve selection identity, and late updates are filtered against the current query. A failed refresh retains the last catalog with a failure message in the browser. Unexpected catalog formats fail visibly rather than selecting a workflow by a guessed name.

Execution passes only the UUID to `shortcuts run`. It does not automatically retry, pass clipboard/selected text, or capture workflow output. Concurrent Return presses are ignored while a run is active. Completion callbacks own tokens so an old response cannot finish a newer run. Interactive workflows may remain running while awaiting Apple's prompt; closing the launcher does not cancel them. If the helper connection fails, review Shortcuts before retrying because the workflow may already have started.

Shortcut rows are excluded from Volant's usage history. Catalog contents, workflow output and raw process errors are not logged. Unit hosts cannot connect to the real helper; tests inject fictional catalogs and executions. The helper's existing signed-client requirement remains intact.

Initial scope does not include per-workflow custom icons, folder browsing, passing input/output, or assigning workflow-specific global hotkeys. The generic stacked icon identifies an Apple Shortcut. Successful real-workflow execution and permissions prompts require separate signed-app evidence from fixture tests.
