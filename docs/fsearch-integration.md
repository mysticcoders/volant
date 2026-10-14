# fsearch file search (optional)

Volant can take its file results from [fsearch](https://github.com/noahdunnagan/fsearch), a separate
MIT-licensed whole-disk file finder for macOS, instead of Spotlight. It is off by default:
Settings → General → File Search → **Use fsearch for file search** (`fileSearchUsesFSearch`, per Mac,
not synced). The owner chose this over a native index to avoid giving Volant Full Disk Access
(October 14, 2026); fsearch holds that permission itself.

## Boundary

- Volant never installs, starts or runs fsearch. It talks only to a daemon the owner already runs,
  through its JSON-lines socket at `~/Library/Application Support/FSearch/fsearch.sock`. The fsearch
  binary lives in a user-writable folder, so executing it would run code Volant cannot check.
- The sandboxed app cannot reach that socket, so `VolantAgentHost` (not sandboxed, accepts only the
  Volant app that embeds it) makes the call through three narrow methods: `fsearchSearch(query, limit)`,
  `fsearchStatus` and `fsearchOpened(path)`. Nothing else is forwarded.
- `VolantCore/FSearch` builds one request line (a query of at most 256 characters on one line, at most
  50 hits), waits at most 2 seconds, reads at most 1 MB, and keeps only absolute paths with their
  kind, modification time, size and score.
- Queries go only to that local daemon. Volant reports a file the owner opens from its results
  (`open`), which fsearch uses to rank it higher for a while.

## Behavior

- Everyday search shows up to five file rows; `/` shows up to eight and passes fsearch's syntax
  through, such as `/ext:swift launcher` or `/in:~/workspace readme`. Typos are tolerated.
- Results hide the same noise as Spotlight results (Library, build folders, dotfiles, node_modules).
- A query is sent 50 ms after typing pauses (Spotlight keeps 150 ms); only the newest answer is shown.
- When fsearch is not running, still indexing, or fails, the same query goes to Spotlight. Settings
  shows the daemon's state: its item count and whether it has Full Disk Access, or how to start it.

## Evidence

- `FSearchTests` (Core) run the client against a fake daemon socket: request lines, hit validation,
  daemon errors, a missing daemon, silence (timeout) and an oversized reply.
- `FSearchFileSearchTests` (app): fsearch answering without Spotlight and hiding noise, fallback to
  Spotlight, stale answers dropped, and the setting switching the source.
- Against the owner's real fsearch 0.2.1 daemon (9.48M entries, no Full Disk Access), the Core client
  answered `mian.rs` in 4.6 ms and other queries in under 1 ms (October 14, 2026). The owner then
  used it in an installed Developer ID build: the File Search status, typo-tolerant `/` searches and
  fsearch's filters worked through `VolantAgentHost` (October 14, 2026).
- Measured on the same Mac: `fd -uu --glob main.rs ~` took 34–48 s; fsearch's own benchmark put the
  same query at a 0.65 ms median. The fsearch daemon held about 920 MB resident with content indexing,
  and its index used about 446 MB on disk; that memory belongs to fsearch, not Volant.

Not yet: content search (`grep:`) results in the launcher, and starting fsearch from Volant.
