# Worktrees command

Status: phase 1 (read-only) and phase 2 (Remove and Prune) built on 2026-11-23 at the owner's go-ahead. Reviewed against `servers` and `VolantAgentHost` the same day (see Review notes).

Two phases. **Phase 1 is read-only**, like `servers`: list, reveal, copy, open. **Phase 2 adds Remove and Prune** and needs the owner's separate approval, the same way stopping servers waits on `docs/process-control-spike.md`.

## Why

Agents and release scripts create git worktrees freely and rarely clean them up. On 2026-11-23 a cleanup on Andrew's Mac found 43 live worktrees across 8 repositories taking about 70 GB, with the data volume at 100% and 17 GB free. Another 23 registered worktrees pointed at folders that no longer existed. Removing them brought free space to 76 GB.

Where the space was:

| Source | Count | Size |
|---|---|---|
| volant `dist-release.ship-*/worktree` (left by `Scripts/ship.sh`) | 10 | ~23 GB |
| volant `.claude/worktrees/*` (agent worktrees) | 9 | ~18 GB |
| cara sibling folders and agent worktrees | 7 | ~6.6 GB |
| volant-extensions `.claude/worktrees/*` | 7 | ~5.5 GB |
| other repos (pronto, campfire spikes, reviewbot) | 6 | ~3.5 GB |

Nobody noticed until the disk filled. The `servers` command already answers "what am I running that I forgot about" for ports; `worktrees` answers it for disk.

## Command

Query words: `worktrees`, `worktree`, `wt`, added to `LauncherRouting`'s reserved commands so import and editing agree. `wt` is two letters, so check it doesn't bury an app the owner reaches with `wt` today; drop it if it does. Text after the word filters by repository, branch or path, like `servers`. `worktrees stale` shows only stale entries.

Sections, in order:

1. **In Use**: a dev server is listening from inside it (from `ListeningServers.scan`, matching `ListeningServer.directory` by path prefix) or an agent's working folder is inside it (`RexPane.cwd`, which Rex reports only when the shell sends OSC 7, and Herdr pane folders where known). Agents run in a plain terminal aren't seen, so In Use can miss them; the Remove confirmation says so.
2. **Worktrees**: everything else that exists on disk, largest first.
3. **Stale**: registered with git but the folder is missing or empty (`git worktree list --porcelain` marks these `prunable`).

Row: first line is the folder name and branch, or `detached` with the short commit. Second line, following `ListeningServer.detail`: repository name, abbreviated path, size, `N uncommitted` when dirty, and the last commit's age (`3d`, `2w`). Right-side label like the servers command's Local/Network: `Clean`, `Uncommitted`, or `Stale`.

A notice line shows the total size and, when the volume holding the worktrees has under 10% or 25 GB free, the free space.

## Actions

| Key | Action |
|---|---|
| Return | Reveal in Finder |
| Command-Return | Copy path |
| Actions menu | Open in Terminal, Open Repository; in phase 2, Remove Worktree and Prune Stale (on the Stale section or a stale row) |

Opening in Rex is left out: Volant never starts Rex or types into a pane (`docs/rex-integration.md`).

Remove Worktree (phase 2). The app sends only the repository path, the worktree path and the HEAD it showed; the helper rechecks, right before acting, that the path is still a registered, non-main worktree of that repository at that HEAD, and refuses otherwise (a stale row never removes whatever is there now). Rules, in order:

1. Refuse when the row is In Use, rechecked at removal time. Say which server or agent holds it.
1. Refuse when the worktree is `locked`; someone locked it on purpose.
2. Refuse when HEAD has commits no branch or remote reaches (`git log HEAD --not --branches --remotes`). Removing it would lose them. Offer Copy Path instead.
3. When there are uncommitted changes, save them first, then remove. Tracked changes: `git diff HEAD --binary`. Untracked, non-ignored files: listed with `git ls-files --others --exclude-standard -z` and copied beside the patch, so the index is never touched (`git add -N` would change it, and a failed removal would leave that behind). Bounded (say 100 MB; refuse above it and say why). Saved in `~/Library/Application Support/Volant/Worktree Backups/<date>/<repo>-<folder>/` by the unsandboxed helper, not inside the app's container, so the owner can find it. Never synced, logged or included in backups. The confirmation says a backup will be kept and where. If saving fails, nothing is removed.
4. Otherwise confirm, then `git worktree remove --force <path>` from the main repository (one `--force`: it allows the dirty tree we just backed up, but not a locked one). The branch is kept; the confirmation says so.

Prune Stale runs `git worktree prune` in each affected repository. It deletes only git's records for folders that are already gone, so it needs no confirmation beyond the action itself.

Never delete branches. Never remove the main worktree.

## Finding repositories

This is the hard part. Worktrees often live in gitignored folders (`.claude/worktrees/`, `dist-release.*/`), so a filesystem walk that honors `.gitignore` misses them; the first manual scan did exactly that. Use git's own records instead:

1. Collect candidate repositories from:
   - Folders set in Settings (default `~/workspace`, `~/Developer`, `~/src`, `~/code` when present), scanned a few levels deep for `.git` directories (not files) that contain a `worktrees/` subfolder.
   - Folders Volant already knows agents work in: `RexPane.cwd`, Herdr pane folders and `ListeningServer.directory`, walked up to their repository root.
   - Optionally, the folder *names* in `~/.claude/projects/` (never the files inside), which cover every repository Claude Code has worked in. The encoding replaces `/` and `.` with `-`, so it's ambiguous: decode only by testing which candidate paths exist, and treat a miss as nothing. Behind a Settings switch, off by default, since it reads another app's data folder.
2. For each repository with a `.git/worktrees/` folder, run `git worktree list --porcelain -z` and skip the first (main) entry. Bound it like `ListeningServers.maximumServers`: at most so many repositories and worktrees, each git call with a short timeout, as `RepositoryInspector` does.
3. Skip submodules: a `.git` file whose `gitdir:` points into another repository's `.git/modules/` is a submodule, not a worktree.

## Reading

The sandboxed app can't read other folders or run git, so the agent helper does the reading, as it does for `servers`. It already runs git for agent panes (`RepositoryInspector` with `RepositoryStatusCommand`: fixed arguments, a 3 s timeout, a clean environment); reuse that pattern rather than a general "run git" call.

Helper API, explicit and narrow like the rest of `VolantAgentHost`:

- `listWorktrees(reply:)`: no input; rows without sizes.
- `worktreeSizes(paths:reply:)`: only paths the last listing returned, re-checked in the helper; sizes measured in Swift (allocated size per file, bounded time and file count, cancellable), not by running `du`. Size is an estimate of space freed: APFS clones and hard links can make it smaller.
- Phase 2 only: `removeWorktree(repository:path:head:reply:)` and `pruneWorktrees(repository:reply:)`.

The helper returns rows without sizes first, then sizes as they finish: `du` on a 3 GB worktree with `node_modules` and build output took several seconds. Keep sizes in memory for the launcher session only. Uncommitted counts come from `git status --porcelain` per worktree, also lazily. Paths and branch names are read on use, never cached across launches, logged, persisted, synced or ranked, as with `servers`; failures come back as `HostMessage` codes.

The helper never reads file contents beyond git's own metadata, and the reply carries paths, branch names, counts and sizes, not diffs. The backup is written only when the owner removes a dirty worktree.

## Fix the source too

`Scripts/ship.sh` removes its worktree only on success (lines 155 and 333); the ERR trap at line 36 exits without cleanup, so every failed or aborted run leaves a ~2.3 GB worktree. The `dist-release.ship-$VERSION.*` logs folder (logs, appcasts, a DMG) is never removed even on success. Suggested:

- An EXIT trap that runs `git worktree remove --force "$WT"` when `$WT` is set, whatever the outcome. This is safe for resuming: `--publish` re-adds the worktree when it's missing (line 267).
- On success, delete the logs folder or keep only `release.log` and `pr.md`; on failure, keep the logs but not the worktree. `Scripts/release.sh` run on its own also leaves `dist-release.XXXXXX` output folders (line 39), which `ship.sh` points into `$LOGS`; standalone runs need the same treatment.

This is worth doing regardless of the command.

## Tests

Follow `LauncherServersTests` and `ListeningServerTests`:

- Query parsing: the three words, `stale`, filter text.
- Arranging: In Use first, then by size, stale last; filter matches repository, branch and path.
- Removal guards: In Use, orphaned commits, dirty with patch, clean.
- Porcelain parsing: detached, branch, `prunable`, `locked`, paths with spaces.
- Submodule `.git` files are not reported as worktrees.
- Helper: only listed paths are sized; a removal whose path is no longer a registered worktree at the expected HEAD is refused; a locked worktree is refused; a failed backup removes nothing. Run against fixture repositories in a temporary folder, never the owner's, and never launch the helper from the unit-test host.

## Review notes

Changes from the first draft, after reading `servers` and `VolantAgentHost`:

- Split into a read-only phase 1 and a destructive phase 2 that needs separate approval, matching the rule that `servers` acts on nothing until process control is approved.
- Narrow helper methods instead of general git execution, and a recheck of identity (repository, path, HEAD) at removal time.
- Refuse locked worktrees; a single `--force`.
- Backups don't touch the index, are bounded, and a failed backup removes nothing.
- `~/.claude/projects` is optional and off by default; agent folders Volant already knows come first.
- Sizes are measured in Swift and labeled as estimates.
- No Open in Rex.
- When this ships, add an `AGENTS.md` entry like the `servers` one.

## Phase 1 as built

- Query words `worktrees`, `worktree`, `wt`; `stale` filters. Sections In Use, Worktrees (largest first) and Stale. Return reveals in Finder (copies the path for a missing folder), Command-Return copies the path, and the Actions menu adds Open in Terminal and Copy Branch Name.
- Helper: `listWorktrees(folders:)` and `worktreeDetails(paths:)` (four paths per call, 6 s size budget each). Folder hints are Rex and local Herdr pane folders the launcher already has; the helper adds listening servers' folders itself. The `~/.claude/projects` source and a Settings list of roots are not built; roots are the existing `Worktrees.rootNames` folders.
- In Use comes from listening servers and those agent folders. An agent in a plain terminal, or a Rex pane that never reported its folder, isn't seen.
- Measured on this Mac: a detached Volant worktree (1,513 files) measured 871.9 MB, the same as `du -sk`, in 0.01 s; discovery of three roots took 0.16 s.

## Phase 2 as built

- Actions: **Remove Worktree…** on rows that aren't stale or locked, and **Prune Stale Worktrees** on stale rows (for that row's repository).
- Remove opens a form in the launcher naming the folder, its size, what happens to the branch and to uncommitted work. Neither button is the default, so Return does nothing; Escape or Cancel closes it. A row the launcher knows a server or agent is working in is refused before the form opens.
- `WorktreeRemover` (VolantCore, called by `VolantAgentHost.removeWorktree`) rechecks, in order: the request is well formed (absolute paths, a full commit ID, not the main folder); the folder's `.git` file still points into that repository; git still lists it at that commit and not as prunable; it isn't locked; no process of the owner's has its working folder inside it (`ListeningServers.processes(workingInside:)`, which also catches agents and shells in plain terminals); `git rev-list -n 1 HEAD --not --branches --remotes` is empty. Then, if `git status` shows anything, it saves `changes.patch` (`git diff HEAD --binary --output=`) and copies untracked, unignored files under `untracked/`, with a README, in `~/Library/Application Support/Volant/Worktree Backups/<date>/<repo>-<folder>`, refusing above 100 MB or 10,000 files and deleting a partial backup. Only then `git worktree remove --force`.
- Each refusal is a `HostMessage` code the launcher shows: changed, locked, in use (with the process name), unreachable commits, backup failed, backup too large, git failed.
- `WorktreeRemoverTests` run all of this against real git in a temporary folder.

