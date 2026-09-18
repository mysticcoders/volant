# Herdr machines

Volant discovers Local plus enabled saved Herdr machines with `herdr machine list --json`. It does not add hosts, change SSH trust, install or restart remote servers, or forward arbitrary SSH destinations from the UI. A saved profile chooses one remote session, not every session on that host. Remote forwarding requires Herdr 0.9.1 or later on both machines and a compatible running server.

The status bar aggregates connected panes. Expanded details and Open Agents show machine connection states; pane rows, search, and waiting cards identify the machine. Disabled profiles remain disabled. Unavailable machines contribute no stale panes, working counts, questions or answer buttons. The warning explains that SSH access and remote Herdr compatibility need checking. Local and remote discovery failures are independent, and polling recovers when the destination becomes available. Polling runs off the UI thread. Local discovery and saved-machine catalog reads have dedicated queues; remote discovery uses at most four workers. Local panes publish immediately when their request completes, even before catalog discovery finishes. Each enabled remote starts with a Loading state and publishes independently. The five-second poll refreshes Local and completed machines without waiting for an outstanding remote request. Each destination has at most one outstanding request per connection/profile revision. Focus and answers use a separate serialized queue so discovery cannot block their execution.

A remote agent's stable identity includes saved profile ID, SSH target, remote session, terminal and pane. Every read, validation, focus and keystroke uses the same `--machine <profile-id>` route. Before each forwarded operation, the helper rereads the catalog and rejects removed, disabled or retargeted profiles. The provider response token retains its original destination and cannot be repurposed for an identical pane ID on Local. Profile labels can change without retargeting input. The remote CLI never falls back to Local, and uncertain delivery is never automatically resent.

Herdr still has no atomic compare-and-send operation. A change between validation and delivery remains possible, including a saved profile changing during the CLI call. Remote focus selects the pane on its server; the user may still need to choose that machine in the Herdr client. Custom SSH configurations or agent authentication that require an interactive prompt must be completed in Herdr; Volant does not prompt in the background.

The helper passes only its minimal process environment plus the SSH authentication socket reference when available. Standard input is closed. Output remains bounded in memory; processes time out, and inherited stdout handles cannot keep a read pending forever. No terminal contents or SSH credentials are logged or persisted.

## Evidence and follow-up

Regression coverage includes identical IDs on different machines, machine/session retargeting, disabled and removed profiles, partial outages in either direction, single-use remote answer routing, and process timeout. Native fixtures cover machine labels, filtering, status details, unavailable state, and provider answer buttons in light/dark compact/default/large layouts. Final check and installed-artifact evidence is recorded in the PR.

Read-only discovery against the owner's saved `acubed` profile found that the remote installation lacks machine forwarding. This is a compatibility failure, not a working remote end-to-end test. A successful remote signed-app read/focus/answer smoke remains pending until that server is updated separately. No owner remote agent receives test input.

Next: verify the signed app against a compatible remote machine using a fictional disposable agent, then evaluate per-machine polling backoff for larger machine catalogs.

## Progressive discovery regression checks

The former combined inventory reply waited for every remote process before publishing Local. Independent XPC requests now isolate local/catalog/remote scheduling. Callback generations and per-destination request IDs reject replies after disconnect, removal, disabling, or retargeting. A failed machine loses only its own actionable panes; catalog failure clears remote destinations but preserves Local. Tests hold catalog/remote replies explicitly to prove local results and later local refreshes do not wait; native light/dark fixtures cover connected Local alongside a loading remote. Installed signed-XPC behavior remains separate from injected transport tests.
