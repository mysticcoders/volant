# Rex integration (design)

Status: proposed, not implemented. Checked against Rex `0.0.1792519967-gd05acf`, server API revision 4,
on October 20, 2026. Rex is in beta; its API documents itself (`rex api describe <method>`), and that
output, not this page, is the authority for field names.

## Goal

Show what programs running in [Rex](https://www.superlogical.com/rex/docs) panes are doing, and
which of them are waiting on the owner, without leaving the launcher. A `rex` keyword lists panes
with blocked ones first, Return focuses the selected pane in Rex, and an optional footer item counts
waiting panes. Rex panes are deliberately not merged into the `herdr` / `agents` list: they come from
a different tool with different identity, status and delivery rules.

## What Rex provides

**Program Status Protocol (OSC 7501).** A generic terminal escape sequence that lets a program report
its own state. Rex keeps a set of records per pane and returns them through the pane's
`program_status` block method:

| Field | Meaning |
| --- | --- |
| `state` | `idle`, `working`, `done`, `blocked` or `error`. An unknown value is treated as `idle`. |
| `kind` | For `blocked` only: `permission`, `question` or `auth`. Unknown values are treated as absent. |
| `msg`, `title` | One line of program-supplied text. Plain text only; never interpreted. |
| `app`, `effective_app` | Stable program identifier, such as `claude-code` or `cargo`. |
| `progress` | 0–100, for `working` and `blocked`, when reported. |
| `id` | Record path (`build/test`); absent for the root record. |
| `owner` | Foreground `pid` and process `name` when the report arrived. |
| `updated_at` | Timestamp of the report. |

Claude Code already reports it: during this design the pane running it returned
`state=working, app=claude-code` with its current activity as `msg`. `working` and `blocked` records
are dropped by Rex when the process exits or a new shell prompt starts; `done` and `error` survive
until the owner returns to the pane.

**Layout and identity.** `session.list` returns `session_id` and `label`. `session.view` returns
windows, layers and blocks with `block_id`, `label`, `creator_name` (`com.superlogical.terminal` for
terminals) and `host_id`. IDs are stable UUID-based strings (`session:…`, `block:…`); labels are
display names and can change.

**Focus.** `session.focus_block` focuses a block and makes its window active.

**Events.** `rex events --json` streams newline-delimited JSON. Measured on this version: the
whole-server stream carries session-level changes but not block events; `program_status_changed`
arrives only on a per-session stream (`rex events --json -s <session>`), wrapped as
`session_event → block_event` with `block_id`, `name`, the new `record` and a `reason`.

**Remote servers.** `hosts.list` lists other Rex servers by label, and `-S <host>` targets one.
Out of scope for the first version.

## Design

**Transport.** `VolantAgentHost` runs the `rex` CLI through the same bounded process runner used for
Herdr (`HerdrProcess`: minimal environment, stdin closed, bounded output, timeout). It looks for
`rex` at fixed install paths and reports "Rex was not found" otherwise. The CLI is preferred over
speaking to `~/Library/Application Support/rex/server.sock` directly because the socket's wire
protocol is not documented and the CLI follows the server's API version. Pass `--autostart=false`
so Volant never starts a Rex server. The main app stays without process or socket access.

**Narrow helper API.** New XPC methods take typed arguments, never a method name or JSON from the
app:

- `listRexPanes` — `session.list`, then `session.view` and `program_status` per terminal block.
  Returns session/block IDs, labels, app, state, kind, progress, `msg` and `updated_at`.
- `focusRexPane(sessionID, blockID)` — revalidates that the session and block still exist and the
  block is still a terminal, then calls `session.focus_block`.

The helper never calls `format`, `clipboard_read`, `write`, `send`, `client.key` or any other method
that reads screen contents or types input. Those are not reachable from the XPC API at all.

**Refresh.** Start with a five-second poll while the `rex` view or footer item is visible, matching
the Herdr cadence, with one outstanding request at a time and stale replies rejected by request
generation. A later step can replace polling with one `rex events --json -s` stream per session,
supervised by the helper, with a full refresh on reconnect or session add/remove.

**Launcher.** `rex` is a reserved keyword in `Shared/LauncherRouting.swift` so imports and Settings
agree. Rows sort `blocked` first (then `error`, `done`, `working`, `idle`), show the app, the pane or
session label and `msg`, and activate by stable `(session_id, block_id)` identity. A pane without
status records still appears, as idle. A trailing term filters by label or app.

**Footer.** Optional and off by default, built like `HerdrStatusSummary`: "Rex: 2 waiting",
"Rex: none waiting", "Rex: not running". Click opens `rex`.

## Not in the first version

- **Answering prompts.** Rex can type into a pane, but AGENTS.md forbids submitting prompts through
  a generic shell-input path, Rex has no atomic check-then-send, and OSC 7501 gives a message rather
  than structured choices. Revisit only if Rex adds a conditional, structured response method.
- **Remote hosts** (`hosts.list`, `-S`). Needs the same per-machine identity, revalidation and
  no-fallback-to-local rules as [Herdr machines](herdr-machines.md).
- **Screen contents.** Volant never reads a pane's screen or scrollback from Rex.

## Privacy

`msg` and `title` are program-supplied text that can include file names or commands. Keep them in
memory only for display; never log or persist them. Do not log process names, pids or labels.

## Evidence plan

- Core tests decode recorded, fictional `session.view` and `program_status` JSON, including unknown
  states and kinds, missing `owner`, child records and a session that disappears between calls.
- Helper tests use an injected process runner: Rex missing, server not running, timeout, malformed
  JSON and a stale focus target that must not be focused.
- Native fixtures render the `rex` list and footer in light and dark with fictional panes.
- Installed-app check against a live Rex server with a disposable pane emitting OSC 7501 states.
  Fixture and injected-runner tests do not verify the signed helper's access to the Rex socket.
