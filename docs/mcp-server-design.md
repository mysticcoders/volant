# Volant as an MCP server

Draft, November 18, 2026. The owner asked how Raycast 2.13 lets AI apps use Raycast, and whether Volant
can do the same. This is the design and the transport spike; nothing is built yet.

## What Raycast shipped

Raycast 2.13 ([changelog](https://www.raycast.com/changelog/macos/2-13),
[manual](https://manual.raycast.com/ai/model-context-protocol)) runs a local MCP server so AI apps can
use Raycast's own features as tools:

- **Switch:** Settings › MCP › Raycast MCP Server, off by default on each device, Pro only.
- **Transport:** HTTP at `http://127.0.0.1:8267/mcp`, reachable only from the same Mac.
- **Connecting:** a Connect App menu writes the configuration for Claude Code, Claude Desktop, Codex,
  Cursor, Gemini CLI, GitHub Copilot and VS Code; Copy Configuration covers any other app. Each app gets
  its own token, revocable alone.
- **Tools:** its AI Extensions, chosen in a Shared Extensions list: clipboard history (search, pin,
  delete), snippets, quicklinks, notes, apps and Auto Quit, browser tabs, history and bookmarks, Focus,
  calendar, settings and memory. Automations are off by default. Notes, snippets and quicklinks are also
  MCP resources. Long lists page, responses are short, errors are explicit.
- **Approval:** Raycast asks nothing itself. It sends tool annotations and leaves approval to the AI app.

Raycast is also an MCP client. Volant decided against its own client list in September, because the
Claude Code and Codex adapters already load their own MCP configuration (see
[agent integrations](agent-integrations.md)). That doc names "Volant offered to agents as an MCP server"
as a separate design with sandbox implications: this one.

## Constraints from Volant's rules

- The main app has no network entitlement, and helpers hold only the access they need.
- Every capability is the owner's explicit choice, off by default, per Mac, never synced.
- Content (notes, clipboard, file paths, places) is never logged or persisted beyond what each feature
  already keeps. Clipboard reads exclude items `PasteboardFilter` excludes.
- Accessibility, event posting, Rex and Herdr pane input, Wi-Fi changes and AI keys stay out of reach
  of anything automated.
- The app is sandboxed, so it can't write other apps' configuration files the way Raycast's Connect App
  does.

## Transport

### Spike results

`tools/spike-mcp-transport.py` signs copies of `tools/mcp-transport/probe.c` with the release Developer
ID identity and only the entitlements each case needs, in a probe-only app group
(`REMBT6JY4N.com.mysticcoders.volant.transport-probe`), and runs servers and clients against each other.
On macOS 27.0 on November 18, 2026 (macOS keeps the probes' empty containers; they can only be removed
in Finder):

| Case | Result |
| --- | --- |
| Sandboxed, no network entitlement, app group: listen on a Unix socket in the group container | Listens |
| Separate process, same team and app group, sandboxed: connect | Connects |
| Unsigned, unsandboxed process: connect | Connects |
| The sandboxed listener reads each peer's signature from its audit token | Bridge: team REMBT6JY4N, its identifier; stranger: no team |
| Sandboxed with `network.server` only: listen on 127.0.0.1 | Listens |
| Control: sandboxed, no network entitlement: listen on 127.0.0.1 | `bind: Operation not permitted` |

So the main app can host a Unix socket with no network entitlement, and the socket alone is not access
control: any local process that can reach the path can connect. The listener can tell who connected,
though: inside the sandbox, `getsockopt(LOCAL_PEERTOKEN)` and `SecCodeCopyGuestWithAttributes` returned
the bridge's team and identifier and no team for the stranger, which is the check option 1 relies on. The stranger ran from a terminal whose
privacy grants may be broader than a typical app's, but the design must assume anyone can connect.

### Options

1. **Stdio bridge and a Unix socket (recommended).** AI apps start
   `Volant.app/Contents/Helpers/volant-mcp` as a stdio MCP server. The bridge copies bytes between its
   stdin/stdout and a Unix socket the running app listens on in Volant's app group container. The app
   checks every connection's peer before reading a byte: it takes the peer's audit token
   (`LOCAL_PEERTOKEN`) and accepts only code signed by team REMBT6JY4N with the bridge's identifier. The
   bridge holds no logic, so the MCP protocol and every tool live in the app, where they can be tested.
   - No TCP listener anywhere, so no exposure to browsers or DNS rebinding, and no network entitlement.
   - Every major AI app supports stdio servers, and the Connect App configuration is just a command line.
   - Needs a new `com.apple.security.application-groups` entitlement
     (`REMBT6JY4N.com.mysticcoders.volant`). Volant Dev shares it under `tools/check-dev-entitlements.py`,
     so the socket name must include the bundle identifier.
2. **Loopback HTTP helper (Raycast's shape).** A new `VolantMCPHost` holding only `network.server`
   listens on 127.0.0.1, checks a per-app bearer token and the `Origin` and `Host` headers, and passes
   validated calls to the app over XPC, like the fetch, rates and weather helpers. It works, but any
   local process and any web page can reach a TCP port, so its safety rests on the token and header
   checks, and it adds a long-running helper with a listening socket.
3. **XPC through a launch agent.** A Mach service registered with `SMAppService` would avoid sockets, but
   needs a launch agent plist and a second process lifecycle for the same result as option 1.

Recommendation: option 1. Option 2 stays the fallback if the signed release app can't hold the app group.

## Protocol

MCP changed shape in revision 2026-07-28 ([spec](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)).
Revisions up to 2025-11-25 ("legacy") open with an `initialize` handshake; 2026-07-28 ("modern") has
none: every request carries `_meta` with `io.modelcontextprotocol/protocolVersion` and
`io.modelcontextprotocol/clientCapabilities`, servers must answer `server/discover`, and every result
carries `resultType`. AI apps in use today may speak either, so Volant is a dual-era server, which the
spec allows on one stdio connection:

- A request whose `_meta` names a modern version is served statelessly under 2026-07-28. One that names
  an unknown version gets `UnsupportedProtocolVersionError` (`-32022`) listing the supported versions.
  One missing a required `_meta` field gets `-32602`.
- `initialize` selects legacy semantics for that connection: the reply names 2025-11-25 (the newest
  legacy revision) unless the client asked for another legacy revision Volant also speaks, and
  `notifications/initialized` is accepted.
- Methods: `server/discover`, `ping`, `tools/list`, `tools/call`, and `initialize` with
  `notifications/initialized`. Unknown methods get `-32601`. Unknown tools get `-32602`; a tool's own
  failure is a result with `isError: true`, so the model can correct itself.
- Framing is the stdio binding's: one JSON-RPC message per line, no embedded newlines, UTF-8. The
  bridge writes nothing else to stdout; the socket uses the same framing, as the spec recommends for
  custom transports. Lines over 1 MB are refused.
- `tools/list` is deterministic, tools without parameters use
  `{"type": "object", "additionalProperties": false}`, and results that return data also return it as
  `structuredContent` with the same JSON in a text block.

## Clients and setup

- **Settings › AI › Connected Apps:** one switch, off by default, per Mac, never in
  `SettingsSync.keys`. Turning it on shows the capability list (the tiers below) with clipboard history
  as its own unchecked choice to approve. Below it, one row per connected app with Revoke.
- **Connect App** shows the configuration to copy, because the sandbox can't write other apps' files:
  `claude mcp add volant -- /Applications/Volant.app/Contents/Helpers/volant-mcp --client claude-code`
  for Claude Code and Codex, and the JSON entry for Claude Desktop, Cursor and others.
- **Per-app identity.** Each configuration names its client (`--client`), and the app records a token for
  it the first time that client connects, shown in Settings. Revoke removes it and refuses that client.
  A local process can read another app's configuration, so this is for attribution and revocation, not
  a security boundary; the peer signature check is the boundary.
- **Volant not running.** The bridge launches Volant (by its bundle identifier, the copy it ships
  inside) and waits briefly for the socket. If Volant doesn't come up, or the server is off in Settings,
  it answers `initialize` with an error that says which.

## Tools

Tool names are stable and English, descriptions say what each touches, and every tool carries MCP
annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`). Lists page with a cursor and cap each
response, and errors say what to do next. Arguments and results are never logged.

| Tier | Tools | Default |
| --- | --- | --- |
| Read | calculate (units, time zones, dates); search notes, read a note; list snippets and quicklinks; break and Focus status, break history; app search | on with the server |
| Write: notes, snippets, quicklinks | create a note, append to a note; add or edit a snippet or quicklink | off, one switch each (phase 1) |
| Write: Focus and Breaks | start, pause or end Focus; take, skip or pause a break | off, per capability (phase 2) |
| Sensitive | clipboard history search (excluded items never returned); home file search; currency conversion (rates helper); weather for a named place (weather helper); listening servers | off, per capability, and each call asks in Volant |
| Never | typing at the cursor, menu presses, anything through Accessibility; Rex or Herdr pane input; Wi-Fi, Bluetooth and system actions; AI keys; Location; extension installs or approvals | not offered |

**Asking in Volant.** Raycast leaves approval to the AI app. Volant should also ask for sensitive tools:
a small non-activating panel names the app and the action with Allow Once, Always for This App and Deny,
and an unanswered prompt is denied after 60 seconds. "Always" is per app and per tool, revoked with the
app. Writes rely on the AI app's own approval plus the per-capability switch.

**Resources.** Notes, snippets and quicklinks as MCP resources, read-only, listed only while their tier
is shared.

**Existing paths only.** Each tool calls the same code the launcher and Settings use: notes through
`NotesStore` with its dirty-write rules, snippets and quicklinks through the narrow, stale-checked config
patches, Focus and Breaks through their controllers. No tool gets a second write path.

## Phases

1. **Transport, read tools, and note, snippet and quicklink writes.** The app group entitlement and its
   signed-release check, `volant-mcp`, the socket listener with the peer signature check, the dual-era
   protocol in VolantCore, the read tier, the note, snippet and quicklink write switches (the owner asked
   for these first, as Raycast offers them), and Settings with the switch, Connect App and Revoke.
2. **Focus and Breaks writes, and resources.** Notes, snippets and quicklinks as MCP resources.
3. **Sensitive tier.** The Volant approval panel and the sensitive tools.

## Tests and evidence

- VolantCore: MCP message parsing, unknown methods, malformed and oversized input, paging, and that
  every tool's annotations match its tier.
- App: the peer check refuses an unsigned or wrongly signed peer (using the spike's probes), revoked and
  disabled clients are refused, tiers that are off aren't listed, and nothing is logged.
- Signed release app: the app group entitlement under the Developer ID profile, and a real session from
  Claude Code and Claude Desktop. Fixtures don't establish either.

## Owner decisions, November 18, 2026

- **Settings placement:** inside Settings › AI, not a section of its own.
- **Clipboard history:** offered, but only as a choice shown and approved when the owner turns the
  server on, and off unless approved there. It stays in the sensitive tier, so each call also asks in
  Volant.
- **Volant not running:** the bridge launches Volant and waits for its socket, instead of returning an
  error.
