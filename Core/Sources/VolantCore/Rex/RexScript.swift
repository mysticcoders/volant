import Foundation

/// The two fixed Lua scripts the agent helper runs with `rex do -e`, and the arguments they take:
/// a long-lived watcher that prints the panes whenever they change, and a one-shot focus. The app
/// never supplies script text or a method name: only a session and block ID, checked by
/// `RexIdentifier`, reach `focus` as JSON arguments. Neither script types into a pane or reads its
/// clipboard. Only the watcher started with `preview` reads screen text, and it keeps just the last
/// `previewLines` lines of each pane.
public enum RexScript {
    /// The Rex app's bundle identifier, activated after a pane is focused.
    public static let appBundleIdentifier = "com.superlogical.rex"

    /// Global CLI options: never start a server, bound each request, and talk to this Mac's server
    /// rather than whichever home server the owner configured.
    public static func globalArguments(home: String) -> [String] {
        ["--autostart=false", "--timeout", "5s", "-S", socketAddress(home: home)]
    }

    /// `unix://` plus the percent-encoded path of the local server's socket.
    public static func socketAddress(home: String) -> String {
        let path = home + "/Library/Application Support/rex/server.sock"
        return "unix://" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }

    /// The exit status `rex` uses when no server is running and autostart is off.
    public static let notRunningStatus: Int32 = 4

    /// How long one watcher runs before it exits and the helper starts a fresh one, so a watcher
    /// can never outlive its purpose by more than this.
    public static let watchLifetime = "30m"

    /// Arguments for the watcher, which hears every session's events until stopped. With `preview`
    /// it also prints the last lines of each pane's screen text, which only an owner who turned on
    /// pane previews asks for.
    public static func watchArguments(home: String, preview: Bool = false) -> [String] {
        globalArguments(home: home) + ["do", "--all", "--for", watchLifetime, "-e", watch] + (preview ? ["--args", #"{"preview":true}"#] : [])
    }

    /// The most screen lines a pane preview keeps, and the longest line, cut inside the script.
    public static let previewLines = 12
    public static let previewColumns = 160

    /// What the focus script reports after focusing the pane inside its session.
    public enum FocusOutcome: Equatable {
        case shown, refused, noApp, failed

        /// Reads the script's JSON result. Anything unrecognized counts as `failed`, never as shown.
        public init(output: Data) {
            let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any]
            if object?["shown"] as? Bool == true { self = .shown; return }
            switch object?["reason"] as? String {
            case "refused": self = .refused
            case "noApp": self = .noApp
            default: self = .failed
            }
        }

        /// The message shown when the Rex app did not switch to the pane's session, or nil when it did.
        public var message: String? { hostMessage?.text }

        /// The code `VolantAgentHost` replies with when the Rex app did not switch, or nil when it did.
        public var hostMessage: HostMessage? {
            switch self {
            case .shown: return nil
            case .refused: return HostMessage(.rexFocusRefused)
            case .noApp: return HostMessage(.rexFocusNoApp)
            case .failed: return HostMessage(.rexFocusFailed)
            }
        }
    }

    /// Arguments for the focus script, or nil when either ID is malformed.
    public static func focusArguments(home: String, session: String, block: String) -> [String]? {
        guard RexIdentifier.isValid(session, kind: .session), RexIdentifier.isValid(block, kind: .block),
              let data = try? JSONSerialization.data(withJSONObject: ["session_id": session, "block_id": block], options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return globalArguments(home: home) + ["do", "-e", focus, "--args", json]
    }

    /// Floating layers come after the tiled one, back to front, and their panes' rects are fractions
    /// of the whole tab like the tiled panes', so `layer` alone says how to stack them.
    /// Prints every session's terminal panes, with their status records and reported directory, as
    /// one JSON line: once on start, 0.1 s after a burst of relevant events goes quiet (or 0.5 s
    /// after its first event, so a steady stream cannot hold a snapshot back), and every 30 seconds
    /// in case an event was missed. A script run with `--all` is attached to every
    /// session once it is listening, so it reads each view directly, from timers only.
    public static let watch = """
    local terminal = "com.superlogical.terminal"
    local preview = rex.args.preview == true
    local function tail(text)
      local lines = {}
      for line in string.gmatch(text or "", "([^\\n]*)\\n?") do
        if string.find(line, "%S") then table.insert(lines, string.sub(line, 1, \(previewColumns))) end
      end
      local kept = {}
      for i = math.max(1, #lines - \(previewLines) + 1), #lines do table.insert(kept, lines[i]) end
      return kept
    end
    local function leaves(node, rects)
      if node == nil then return end
      if node.block_id then rects[node.block_id] = node.rect end
      if node.split then leaves(node.split.before, rects); leaves(node.split.after, rects) end
    end
    local function snapshot()
      local out = {}
      local list, err = rex.call("session.list", {})
      if err ~= nil then return end
      for _, s in ipairs(list.sessions or {}) do
        local entry = { session_id = s.session_id, label = s.label, panes = {}, windows = {} }
        local view, verr = rex.call("session.view", { session_id = s.session_id })
        if verr ~= nil or view == nil then
          entry.error = "unreadable"
        else
          for _, w in ipairs(view.windows or {}) do
            table.insert(entry.windows, {
              window_id = w.window_id, label = w.label,
              active = w.window_id == view.active_window_id, focused_block_id = w.focused_block_id,
              zoomed_block_id = w.zoomed_block_id,
            })
            for index, layer in ipairs(w.layers or {}) do
              local rects = {}
              leaves(layer.layout, rects)
              for _, b in ipairs(layer.blocks or {}) do
                if b.creator_name == terminal then
                  local status = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" })
                  local dir = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "pwd" })
                  local title = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "title" })
                  local process = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "process" })
                  local pane = {
                    block_id = b.block_id,
                    label = b.label,
                    cwd = dir and dir.pwd,
                    records = status and status.records,
                    window_id = w.window_id,
                    rect = rects[b.block_id],
                    layer = index - 1,
                    title = title and title.title,
                    program = process and process.foreground and (process.foreground.script or process.foreground.argv0 or process.foreground.name),
                  }
                  if preview then
                    local screen = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "format", args = { format = "text", trim = true } })
                    pane.preview = tail(screen and screen.content)
                  end
                  table.insert(entry.panes, pane)
                end
              end
            end
          end
        end
        table.insert(out, entry)
      end
      print(rex.json.encode({ sessions = out }))
    end
    local quiet, cap
    local function flush()
      if quiet then quiet:cancel(); quiet = nil end
      if cap then cap:cancel(); cap = nil end
      snapshot()
    end
    local function soon()
      if quiet then quiet:cancel() end
      quiet = rex.after(0.1, flush)
      if cap == nil then cap = rex.after(0.5, flush) end
    end
    for _, name in ipairs({
      "terminal.program_status_changed", "terminal.pwd_changed", "block_created", "block_closed",
      "session_created", "session_destroyed", "session_view_changed",
    }) do
      rex.on(name, function() soon() end)
    end
    rex.after(0, snapshot)
    rex.every(preview and 2 or 30, snapshot)
    """

    /// Focuses a pane only if it is still a terminal in a window of that session, then asks the Rex
    /// app to show the session, preferring an app window that already has it open. Returns `shown`,
    /// or why the app did not switch: `refused` when the app has Remote Control off, `noApp` when no
    /// app window is connected, `failed` otherwise. Rex's own error text is never passed on.
    public static let focus = """
    local terminal = "com.superlogical.terminal"
    local sid, bid = rex.args.session_id, rex.args.block_id
    local attached, aerr = rex.call("session.attach", { session_id = sid })
    if aerr ~= nil or attached == nil or attached.view == nil then error("missing", 0) end
    local window
    for _, w in ipairs(attached.view.windows or {}) do
      for _, layer in ipairs(w.layers or {}) do
        for _, b in ipairs(layer.blocks or {}) do
          if b.block_id == bid and b.creator_name == terminal then window = w.window_id end
        end
      end
    end
    if window == nil then
      rex.call("session.detach", { session_id = sid })
      error("missing", 0)
    end
    local _, ferr = rex.call("session.focus_block", { session_id = sid, block_id = bid })
    rex.call("session.detach", { session_id = sid })
    if ferr ~= nil then error("unfocused", 0) end
    local preferred, others = {}, {}
    local clients = rex.call("client.list", {})
    for _, c in ipairs((clients and clients.clients) or {}) do
      local inspected = rex.call("client.inspect", { client_id = c.client_id })
      local offers = false
      for _, a in ipairs((inspected and inspected.actions) or {}) do
        if a.name == "session.select" then offers = true end
      end
      if offers then
        local showing = false
        for _, id in ipairs((inspected.client and inspected.client.session_ids) or {}) do
          if id == sid then showing = true end
        end
        table.insert(showing and preferred or others, c.client_id)
      end
    end
    for _, id in ipairs(others) do table.insert(preferred, id) end
    if #preferred == 0 then return { shown = false, reason = "noApp" } end
    local reason = "failed"
    for _, id in ipairs(preferred) do
      local _, perr = rex.call("client.perform", {
        client_id = id, action = "session.select", origin = "api",
        args = { session_id = sid, window_id = window }, timeout_ms = 3000,
      })
      if perr == nil then return { shown = true } end
      if string.find(perr, "code=refused", 1, true) then reason = "refused" end
    end
    return { shown = false, reason = reason }
    """
}
