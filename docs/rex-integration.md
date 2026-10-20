# Rex integration

Checked against Rex `0.0.1792519967-gd05acf`, server API revision 4, on October 20, 2026. Rex is in
beta; its API documents itself (`rex api describe <method>`), and that output, not this page, is the
authority for field names.

## What it does

Type `rex` to list the terminal panes of this Mac's [Rex](https://www.superlogical.com/rex/docs)
server with the ones that need the owner first. Return focuses the selected pane in Rex, switches the
Rex app to its session and brings Rex forward. A trailing term filters by project, session, program,
state or message (`rex deploy`). The optional footer status ("Rex: 2 waiting", off by default, under
Settings › Status Bar) counts waiting panes and opens the same list.

Rex panes are deliberately not merged into the `herdr` / `agents` list: they come from a different
tool with different identity, status and delivery rules.

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

Claude Code already reports it. `working` and `blocked` records are dropped by Rex when the process
exits or a new shell prompt starts; `done` and `error` survive until the owner returns to the pane.

**Layout and identity.** `session.list` returns `session_id` and `label`. A connection must attach
to a session (`session.attach`, which returns the same view as `session.view`) before it can read
its windows, layers and blocks; `session.view` from an unattached script fails with a 409. IDs are
stable UUID-based strings (`session:…`, `block:…`); labels are display names and can change. Shells
usually label every pane `shell`, so rows are titled by the reported working directory (`pwd`) and
fall back to the session label.

**Focus.** `session.focus_block` focuses a block within its session. The Rex app is a client that
declares a `session.select` action; `client.perform` asks it to show a session and window.

**Events.** `rex do --all` runs a [Lua script](https://www.superlogical.com/rex/docs/automate/lua-scripts)
that hears [events](https://www.superlogical.com/rex/docs/automate/lua-events) from every session,
including ones created later, and keeps running while it has handlers. Measured on this version:
`program_status_changed` reaches a `--all` handler, which can read that pane's status, and `print`
reaches a pipe line by line as events arrive. The script is attached to every session only once it
is listening: `session.view` from its top level fails with a 409, but from a timer it succeeds for
every session without attaching. (The CLI's `rex events` differs: its whole-server stream carries
no block events.) The same stream also carries `desktop_notification`, which Claude Code sends.

## How it works

**One long-lived watcher.** `VolantAgentHost` runs `rex do --all --for 30m -e <watch>`, the fixed
watch script in `RexScript`. It registers handlers for `program_status_changed`, `pwd_changed`,
pane, session and view changes, and prints every session's terminal panes (status records and
reported directory) as one JSON line: on start, about 0.25 s after the last event of a burst, and
every 30 s in case an event was missed. It never attaches or detaches, since detaching would stop
that session's events. The first snapshot arrives about 0.3 s after start.

`RexWatch` in the helper supervises it:

- Reads stdout line by line, skips lines that are not inventories, parses and bounds each one, and
  keeps the latest with a revision number that advances on every change of panes or message. A line
  over 4 MB stops the watcher.
- Starts on the first read. The app asks once a second with the revision it holds, as
  `readRexPanes(after:)`, and an unchanged revision replies with nothing, so idle reads cost one XPC
  round trip and no process.
- Restarts at once when the watcher reaches its 30-minute lifetime. After a failure it restarts with
  backoff from 1 s to 10 s, reporting "Rex isn’t running" for exit status 4, but only while reads keep
  arriving: with no read for 20 s it stops instead.
- Stops on `stopRexPanes` (sent when the launcher hides), when the helper's connection ends, and
  when idle. It sends SIGTERM, then SIGKILL after a second if needed.

This replaced polling, which spawned a `rex` process every five seconds while the view was open.

The focus script is still a one-shot `rex do -e` and receives only a session and block ID, checked by
`RexIdentifier`, as JSON `--args`. The app never supplies script text or method names.

Rex encodes an empty Lua table as `{}`, so the parser accepts an empty object wherever it expects a
list.

**Which `rex` runs.** The helper looks inside Rex's server bundle
(`~/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/…`), inside the app,
then in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`, resolving symlinks. It runs a
candidate only if its signature satisfies `anchor apple generic` with Superlogical's team
`AG92C3PT77`, because other tools are also called `rex` and the helper runs outside the sandbox. The
check costs about 0.17 s and is cached per path while the file's modification date is unchanged, so
a Rex update is checked again.

**Which server.** Every call passes `--autostart=false`, a 5 s request timeout and
`-S unix://…/Library/Application%20Support/rex/server.sock`, so Volant never starts Rex and never
follows a home server the owner pointed at another machine. Exit status 4 means no server is running
and becomes "Rex isn’t running. Open Rex, then try again." The child gets `ChildProcessEnvironment.rex`
(home, user, system folders, fixed locale), closed stdin and bounded output through `HerdrProcess`.

**Narrow helper API.** Two XPC methods, both typed:

- `readRexPanes(after:)` replies with the watcher's revision and, when newer, a `RexInventory` the
  helper has already parsed and bounded: valid IDs only, text flattened to one line (labels 200
  characters, messages 500), absolute directories only, at most 500 panes. Each pane is represented
  by its most urgent record, then its newest. `stopRexPanes` stops the watcher.
- `focusRexPane(session:block:)` runs the focus script, which refuses unless the block is still a
  terminal in a window of that session, focuses it, then asks one Rex app client to `session.select`
  it, preferring a window that already has the session open. The app checks the pane is still in its
  current list before asking, and activates Rex with `NSApp.yieldActivation(to:)` only on success.

Neither script reads `format`, `clipboard_read`, `write`, `send`, `client.key` or `block.event`, and
neither uses `rex.exec`, `io` or `os`; `RexInventoryTests` fails if one appears.

**In the app.** `RexModel` reads the helper's revision once a second while the `rex` view or footer
status is showing, with one outstanding request; replies after a disconnect or behind a newer
connection are dropped, and only real changes are published. The launcher disconnects Rex, which
stops the watcher, when it hides. Unlike Herdr there
is no Connect button: typing `rex` starts reading, since it reads only local status and starts
nothing. Model changes never reconnect on their own, so a failing helper is retried on the next
keystroke rather than in a loop.

## Not in this version

- **Answering prompts.** Rex can type into a pane, but AGENTS.md forbids submitting prompts through
  a generic shell-input path, Rex has no atomic check-then-send, and OSC 7501 gives a message rather
  than structured choices. Revisit only if Rex adds a conditional, structured response method.
- **Remote hosts** (`hosts.list`, `-S <host>`). Needs the same per-machine identity, revalidation and
  no-fallback-to-local rules as [Herdr machines](herdr-machines.md).
- **Push to the app.** The helper hears events immediately, but the app still asks it once a second;
  a reverse XPC callback could remove that last second.
- **Screen contents.** Volant never reads a pane's screen or scrollback from Rex.

## Privacy

`msg` and `title` are program-supplied text that can include file names or commands. They stay in
memory for display only and are never logged or persisted. Process names, pids and labels are not
logged either; the `owner` field is not decoded at all.

## Evidence

- `RexInventoryTests` (Core): fictional inventory JSON with empty Lua tables, urgency and recency
  ordering, unknown states and kinds, malformed IDs, unreadable sessions, bounded text, focus
  argument checks, and the forbidden-method check on both scripts.
- `RexModelTests` (app): stale replies after reconnect, disconnect stopping the watcher, unchanged
  revisions, the starting state, not running then recovery, focus refused for an unlisted pane and Rex
  activated on success, and the `rex` query listing waiting panes first and filtering. Injected
  reader, stopper and focuser only.
- `tools/check-rex.sh` (run by `Scripts/test.sh`): the helper's real `RexWatch` against fake `rex`
  shell scripts, never a real Rex: inventory lines replacing each other with a non-inventory line
  skipped, unchanged reads, stop ending the process, exit status 4 as not running, an oversized line,
  and lifetime restart.
- Native Actions fixture `rex` scenario: fictional panes and footer rendered in the panel at every
  size, Return focusing through a fake, and the not-running message.
- Live, outside the app: the helper's `RexHost` compiled on its own against the owner's running Rex
  passed the signature check, delivered the watcher's first snapshot of six panes in 0.29 s, left no
  watcher process behind after stop, and refused to focus a nonexistent pane. A separate `--all`
  Lua watcher received live `program_status_changed` events. No status changed during the
  `RexWatch` probe itself, so an event-driven snapshot through `RexWatch` was not observed end to end.
- Not yet verified: focus and `session.select` against the live Rex app, the signed installed helper
  reaching the Rex socket, and the activation handoff. Driving the owner's Rex app was out of bounds
  for automated checks; these need a check in the installed app.
